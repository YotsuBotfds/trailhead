#!/usr/bin/env python3
import argparse
from collections import Counter
import struct
import sys
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS_BY_COLOR_TYPE = {
    0: 1,
    2: 3,
    3: 1,
    4: 2,
    6: 4,
}


def parse_args():
    parser = argparse.ArgumentParser(description="Validate a Trailhead terrain surface-ID PNG.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--expected-width", type=int)
    parser.add_argument("--expected-height", type=int)
    parser.add_argument("--expected-ids", default="")
    parser.add_argument("--min-ids", type=int, default=2)
    parser.add_argument("--forbid-zero", action="store_true")
    parser.add_argument("--require-grayscale", action="store_true")
    parser.add_argument("--min-pixels-per-id", type=int, default=1)
    return parser.parse_args()


def parse_expected_ids(text):
    if not text:
        return []
    ids = []
    for raw_value in text.split(","):
        value = int(raw_value.strip())
        if value < 0 or value > 255:
            raise ValueError("surface-ID values must be in 0..255: " + str(value))
        ids.append(value)
    return sorted(set(ids))


def fail(message):
    print("fail: " + message, file=sys.stderr)
    return False


def read_png_summary(path):
    data = path.read_bytes()
    if len(data) < 24:
        raise ValueError("surface-ID PNG is too small for a PNG header")
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("surface-ID PNG has invalid signature")

    offset = 8
    width = 0
    height = 0
    bit_depth = 0
    color_type = 0
    idat_chunks = []
    saw_iend = False
    while offset + 8 <= len(data):
        chunk_length = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        chunk_type = data[offset:offset + 4]
        offset += 4
        if offset + chunk_length + 4 > len(data):
            raise ValueError("surface-ID PNG has a truncated chunk")
        chunk_data = data[offset:offset + chunk_length]
        offset += chunk_length
        expected_crc = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError("surface-ID PNG has invalid CRC for chunk " + chunk_type.decode("latin1"))
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack_from(">IIBBBBB", chunk_data, 0)
            if compression != 0:
                raise ValueError("surface-ID PNG has unsupported compression method")
            if filter_method != 0:
                raise ValueError("surface-ID PNG has unsupported filter method")
            if interlace != 0:
                raise ValueError("surface-ID PNG must be non-interlaced")
        elif chunk_type == b"IDAT":
            idat_chunks.append(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
            break

    if not saw_iend:
        raise ValueError("surface-ID PNG is missing IEND")
    if width <= 0 or height <= 0:
        raise ValueError("surface-ID PNG has invalid dimensions " + str(width) + "x" + str(height))
    if bit_depth != 8:
        raise ValueError("surface-ID PNG must use 8-bit channels, got bit depth " + str(bit_depth))
    if color_type not in CHANNELS_BY_COLOR_TYPE:
        raise ValueError("surface-ID PNG has unsupported color type " + str(color_type))
    if not idat_chunks:
        raise ValueError("surface-ID PNG is missing IDAT data")

    samples = decode_png_samples(width, height, color_type, b"".join(idat_chunks))
    sample_counts = Counter(samples)
    return {
        "width": width,
        "height": height,
        "bit_depth": bit_depth,
        "color_type": color_type,
        "unique_samples": sorted(set(samples)),
        "sample_counts": dict(sorted(sample_counts.items())),
    }


def decode_png_samples(width, height, color_type, compressed_data):
    channels = CHANNELS_BY_COLOR_TYPE[color_type]
    stride = width * channels
    raw = zlib.decompress(compressed_data)
    expected_size = (stride + 1) * height
    if len(raw) != expected_size:
        raise ValueError("surface-ID PNG payload size " + str(len(raw)) + " != expected " + str(expected_size))

    samples = []
    previous = bytearray(stride)
    offset = 0
    for _y in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride
        unfilter_png_row(row, previous, channels, filter_type)
        for x in range(width):
            samples.append(row[x * channels])
        previous = row
    return samples


def unfilter_png_row(row, previous, bytes_per_pixel, filter_type):
    if filter_type == 0:
        return
    if filter_type == 1:
        for index in range(len(row)):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            row[index] = (row[index] + left) & 0xFF
        return
    if filter_type == 2:
        for index in range(len(row)):
            row[index] = (row[index] + previous[index]) & 0xFF
        return
    if filter_type == 3:
        for index in range(len(row)):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            up = previous[index]
            row[index] = (row[index] + ((left + up) // 2)) & 0xFF
        return
    if filter_type == 4:
        for index in range(len(row)):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            up = previous[index]
            up_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            row[index] = (row[index] + paeth(left, up, up_left)) & 0xFF
        return
    raise ValueError("surface-ID PNG has unsupported filter type " + str(filter_type))


def paeth(left, up, up_left):
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    if up_distance <= up_left_distance:
        return up
    return up_left


def validate(args):
    ok = True
    if not args.path.is_file():
        return fail("surface-ID PNG does not exist: " + str(args.path))
    try:
        expected_ids = parse_expected_ids(args.expected_ids)
        summary = read_png_summary(args.path)
    except Exception as exc:
        return fail(str(exc))

    width = summary["width"]
    height = summary["height"]
    unique_samples = summary["unique_samples"]
    sample_counts = summary["sample_counts"]
    print("surface-ID PNG: " + str(args.path) + " (" + str(width) + "x" + str(height) + ")")
    print("surface-ID PNG ids: " + ", ".join(str(value) for value in unique_samples))
    print("surface-ID PNG pixel counts: " + ", ".join(str(value) + "=" + str(sample_counts[value]) for value in unique_samples))

    if args.expected_width is not None and width != args.expected_width:
        ok = fail("surface-ID PNG width expected " + str(args.expected_width) + ", got " + str(width)) and ok
    if args.expected_height is not None and height != args.expected_height:
        ok = fail("surface-ID PNG height expected " + str(args.expected_height) + ", got " + str(height)) and ok
    if args.require_grayscale and summary["color_type"] != 0:
        ok = fail("surface-ID PNG color type expected grayscale 0, got " + str(summary["color_type"])) and ok
    if len(unique_samples) < args.min_ids:
        ok = fail("surface-ID PNG has " + str(len(unique_samples)) + " unique IDs, expected at least " + str(args.min_ids)) and ok
    if args.forbid_zero and 0 in unique_samples:
        ok = fail("surface-ID PNG contains reserved zero/unassigned ID") and ok
    if expected_ids and unique_samples != expected_ids:
        ok = fail("surface-ID PNG ids expected " + str(expected_ids) + ", got " + str(unique_samples)) and ok
    for value in expected_ids:
        count = int(sample_counts.get(value, 0))
        if count < args.min_pixels_per_id:
            ok = fail("surface-ID PNG id " + str(value) + " has " + str(count) + " pixels, expected at least " + str(args.min_pixels_per_id)) and ok

    if ok:
        print("ok: surface-ID PNG contract passed")
        return 0
    return 1


def main():
    return validate(parse_args())


if __name__ == "__main__":
    sys.exit(main())

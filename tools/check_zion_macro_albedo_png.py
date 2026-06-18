#!/usr/bin/env python3
"""Validate the Cedar Hollow Zion macro-albedo PNG contract.

Mirrors the structural checks of check_surface_id_png.py but for the de-lit
RGB macro-albedo texture produced by bake_zion_macro_albedo.py (color type 2,
8-bit RGB). Confirms the PNG is well-formed, has the expected dimensions,
carries real macro color variation, and is not dominated by a flat fill.
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a Trailhead macro-albedo RGB PNG.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--expected-width", type=int, default=256)
    parser.add_argument("--expected-height", type=int, default=265)
    parser.add_argument("--require-color-type", type=int, default=2)
    parser.add_argument("--min-unique-colors", type=int, default=1000)
    parser.add_argument("--min-std", type=float, default=8.0)
    return parser.parse_args()


def fail(message: str) -> bool:
    print("fail: " + message, file=sys.stderr)
    return False


def read_png_rgb(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 24:
        raise ValueError("macro-albedo PNG is too small for a PNG header")
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("macro-albedo PNG has invalid signature")

    offset = 8
    width = 0
    height = 0
    bit_depth = 0
    color_type = 0
    idat_chunks: list[bytes] = []
    saw_iend = False
    while offset + 8 <= len(data):
        chunk_length = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        chunk_type = data[offset:offset + 4]
        offset += 4
        if offset + chunk_length + 4 > len(data):
            raise ValueError("macro-albedo PNG has a truncated chunk")
        chunk_data = data[offset:offset + chunk_length]
        offset += chunk_length
        expected_crc = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError("macro-albedo PNG has invalid CRC for chunk " + chunk_type.decode("latin1"))
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = (
                struct.unpack_from(">IIBBBBB", chunk_data, 0)
            )
            if compression != 0:
                raise ValueError("macro-albedo PNG has unsupported compression method")
            if filter_method != 0:
                raise ValueError("macro-albedo PNG has unsupported filter method")
            if interlace != 0:
                raise ValueError("macro-albedo PNG must be non-interlaced")
        elif chunk_type == b"IDAT":
            idat_chunks.append(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
            break

    if not saw_iend:
        raise ValueError("macro-albedo PNG is missing IEND")
    if width <= 0 or height <= 0:
        raise ValueError("macro-albedo PNG has invalid dimensions " + str(width) + "x" + str(height))
    if bit_depth != 8:
        raise ValueError("macro-albedo PNG must use 8-bit channels, got bit depth " + str(bit_depth))
    if color_type != 2:
        raise ValueError("macro-albedo PNG must be color type 2 (RGB), got " + str(color_type))
    if not idat_chunks:
        raise ValueError("macro-albedo PNG is missing IDAT data")

    pixels = decode_png_rgb(width, height, b"".join(idat_chunks))
    return {
        "width": width,
        "height": height,
        "bit_depth": bit_depth,
        "color_type": color_type,
        "pixels": pixels,
    }


def decode_png_rgb(width: int, height: int, compressed_data: bytes) -> bytearray:
    channels = 3
    stride = width * channels
    raw = zlib.decompress(compressed_data)
    expected_size = (stride + 1) * height
    if len(raw) != expected_size:
        raise ValueError("macro-albedo PNG payload size " + str(len(raw)) + " != expected " + str(expected_size))

    pixels = bytearray(stride * height)
    previous = bytearray(stride)
    offset = 0
    for y in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride
        unfilter_png_row(row, previous, channels, filter_type)
        start = y * stride
        pixels[start:start + stride] = row
        previous = row
    return pixels


def unfilter_png_row(row: bytearray, previous: bytearray, bytes_per_pixel: int, filter_type: int) -> None:
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
    raise ValueError("macro-albedo PNG has unsupported filter type " + str(filter_type))


def paeth(left: int, up: int, up_left: int) -> int:
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    if up_distance <= up_left_distance:
        return up
    return up_left


def validate(args: argparse.Namespace) -> int:
    if not args.path.is_file():
        return fail("macro-albedo PNG does not exist: " + str(args.path))
    try:
        summary = read_png_rgb(args.path)
    except Exception as exc:
        return fail(str(exc))

    width = summary["width"]
    height = summary["height"]
    pixels = summary["pixels"]
    stride = width * 3

    channel_samples: list[list[int]] = [[], [], []]
    unique_colors: set[tuple[int, int, int]] = set()
    for y in range(height):
        row_start = y * stride
        for x in range(width):
            base = row_start + x * 3
            r = pixels[base]
            g = pixels[base + 1]
            b = pixels[base + 2]
            unique_colors.add((r, g, b))
            channel_samples[0].append(r)
            channel_samples[1].append(g)
            channel_samples[2].append(b)
            if len(unique_colors) >= max(args.min_unique_colors * 4, 4000):
                break
        if len(unique_colors) >= max(args.min_unique_colors * 4, 4000):
            break

    print("macro-albedo PNG: " + str(args.path) + " (" + str(width) + "x" + str(height) + ")")
    print("macro-albedo PNG color type: " + str(summary["color_type"]))
    print("macro-albedo PNG unique colors (early-stop): " + str(len(unique_colors)))

    ok = True
    if width != args.expected_width:
        ok = fail("macro-albedo PNG width expected " + str(args.expected_width) + ", got " + str(width)) and ok
    if height != args.expected_height:
        ok = fail("macro-albedo PNG height expected " + str(args.expected_height) + ", got " + str(height)) and ok
    if summary["color_type"] != args.require_color_type:
        ok = fail("macro-albedo PNG color type expected " + str(args.require_color_type) + ", got " + str(summary["color_type"])) and ok

    channel_std = []
    for samples in channel_samples:
        n = len(samples)
        if n == 0:
            ok = fail("macro-albedo PNG has no samples") and ok
            continue
        mean = sum(samples) / float(n)
        variance = sum((value - mean) ** 2 for value in samples) / float(n)
        channel_std.append(variance ** 0.5)
    if channel_std:
        min_std = min(channel_std)
        print("macro-albedo PNG min channel std-dev: " + format(min_std, ".3f"))
        if min_std < args.min_std:
            ok = fail("macro-albedo PNG variation too low (min channel std " + format(min_std, ".3f") + " < " + str(args.min_std) + ")") and ok

    if len(unique_colors) < args.min_unique_colors:
        ok = fail("macro-albedo PNG has " + str(len(unique_colors)) + " unique colors, expected at least " + str(args.min_unique_colors)) and ok

    if ok:
        print("ok: macro-albedo PNG contract passed")
        return 0
    return 1


def main() -> int:
    return validate(parse_args())


if __name__ == "__main__":
    sys.exit(main())

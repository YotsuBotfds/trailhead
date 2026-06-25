#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

allowlist_path="tools/export_safe_loads_allowlist.txt"
include_filter="$(awk -F= '/^include_filter=/{value=$2; sub(/^"/, "", value); sub(/"$/, "", value); print value; exit}' export_presets.cfg)"
status=0
direct_count=0
raw_count=0
allowlisted_count=0
dynamic_count=0
tmp_files=""

cleanup() {
	for tmp_file in $tmp_files; do
		rm -f "$tmp_file"
	done
}
trap cleanup EXIT INT TERM

trim() {
	printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

fail() {
	printf 'export-safe-loads: fail: %s\n' "$1" >&2
	status=1
}

validate_allowlist() {
	if [ ! -f "$allowlist_path" ]; then
		fail "missing allowlist: $allowlist_path"
		return
	fi
	while IFS='|' read -r kind file needle target reason; do
		case "$kind" in
			''|\#*) continue ;;
		esac
		if [ -z "$file" ] || [ -z "$needle" ] || [ -z "$target" ] || [ -z "$reason" ]; then
			fail "malformed allowlist row in $allowlist_path: $kind|$file|$needle|$target|$reason"
		fi
	done < "$allowlist_path"
}

is_allowlisted() {
	file="$1"
	line_text="$2"
	while IFS='|' read -r kind allow_file needle target reason; do
		case "$kind" in
			''|\#*) continue ;;
		esac
		if [ "$allow_file" = "$file" ] && printf '%s\n' "$line_text" | grep -F -q -- "$needle"; then
			return 0
		fi
	done < "$allowlist_path"
	return 1
}

path_in_include_filter() {
	asset_path="$1"
	old_ifs="$IFS"
	IFS=','
	# shellcheck disable=SC2086 # intentional splitting on comma-separated export filter
	set -- $include_filter
	IFS="$old_ifs"
	for raw_pattern in "$@"; do
		pattern="$(trim "$raw_pattern")"
		[ -n "$pattern" ] || continue
		case "$pattern" in
			*\*)
				prefix="${pattern%%\**}"
				case "$asset_path" in
					"$prefix"*) return 0 ;;
				esac
				;;
			*/)
				case "$asset_path" in
					"$pattern"*) return 0 ;;
				esac
				;;
			*)
				if [ "$asset_path" = "$pattern" ]; then
					return 0
				fi
				;;
		esac
	done
	return 1
}

res_path_from_line() {
	printf '%s\n' "$1" | sed -n 's/.*"\(res:\/\/[^"]*\)".*/\1/p'
}

classify_direct_res_path() {
	file="$1"
	line_no="$2"
	line_text="$3"
	res_path="$4"
	asset_path="${res_path#res://}"
	direct_count=$((direct_count + 1))

	if [ -f "$asset_path.import" ]; then
		if is_allowlisted "$file" "$line_text"; then
			allowlisted_count=$((allowlisted_count + 1))
			return
		fi
		fail "$file:$line_no loads imported asset by raw path ($res_path); $asset_path.import exists, so the raw source is stripped from exported PCKs"
		return
	fi

	if path_in_include_filter "$asset_path"; then
		raw_count=$((raw_count + 1))
		return
	fi
	fail "$file:$line_no loads raw data path ($res_path) but export_presets.cfg include_filter does not cover it"
}

validate_allowlist

direct_findings="$(rg -n -P '^[[:space:]]*[^#].*(?:Image\.load\s*\(\s*"res://|\b[[:lower:]_][A-Za-z0-9_]*\.load\s*\(\s*"res://|Image\.load_from_file\s*\(\s*"res://|FileAccess\.(?:open|get_file_as_bytes|get_file_as_string)\s*\(\s*"res://)' autoload data scenes systems tests tools --glob '*.gd' || true)"
if [ -n "$direct_findings" ]; then
	direct_tmp="$(mktemp)"
	tmp_files="$tmp_files $direct_tmp"
	printf '%s\n' "$direct_findings" > "$direct_tmp"
	while IFS= read -r finding; do
		file="${finding%%:*}"
		rest="${finding#*:}"
		line_no="${rest%%:*}"
		line_text="${rest#*:}"
		res_path="$(res_path_from_line "$line_text")"
		if [ -z "$res_path" ]; then
			fail "$file:$line_no matched a direct raw load but no res:// literal could be extracted"
			continue
		fi
		classify_direct_res_path "$file" "$line_no" "$line_text" "$res_path"
	done < "$direct_tmp"
fi

dynamic_findings="$(rg -n -P '^[[:space:]]*[^#].*(?:Image\.load_from_file\s*\(|\b[[:lower:]_][A-Za-z0-9_]*\.load\s*\(|FileAccess\.(?:open|get_file_as_bytes|get_file_as_string)\s*\()' systems/render systems/world --glob '*.gd' || true)"
if [ -n "$dynamic_findings" ]; then
	dynamic_tmp="$(mktemp)"
	tmp_files="$tmp_files $dynamic_tmp"
	printf '%s\n' "$dynamic_findings" > "$dynamic_tmp"
	while IFS= read -r finding; do
		file="${finding%%:*}"
		rest="${finding#*:}"
		line_no="${rest%%:*}"
		line_text="${rest#*:}"
		case "$line_text" in
			*ResourceLoader.load*) continue ;;
			*FileAccess.WRITE*) continue ;;
			*'res://'*) continue ;;
		esac
		dynamic_count=$((dynamic_count + 1))
		if is_allowlisted "$file" "$line_text"; then
			allowlisted_count=$((allowlisted_count + 1))
			continue
		fi
		fail "$file:$line_no is a dynamic raw project-file load that is not classified in $allowlist_path: $line_text"
	done < "$dynamic_tmp"
fi

globalize_findings="$(rg -n -P '^[[:space:]]*[^#].*(?:(?:load_from_file|FileAccess\.(?:open|get_file_as_bytes|get_file_as_string)).*ProjectSettings\.globalize_path|ProjectSettings\.globalize_path.*(?:load_from_file|FileAccess\.(?:open|get_file_as_bytes|get_file_as_string)))' autoload data scenes systems tests tools --glob '*.gd' || true)"
if [ -n "$globalize_findings" ]; then
	globalize_tmp="$(mktemp)"
	tmp_files="$tmp_files $globalize_tmp"
	printf '%s\n' "$globalize_findings" > "$globalize_tmp"
	while IFS= read -r finding; do
		file="${finding%%:*}"
		line_text="${finding#*:*:}"
		if is_allowlisted "$file" "$line_text"; then
			allowlisted_count=$((allowlisted_count + 1))
			continue
		fi
		fail "$finding globalizes a project path before raw FileAccess/load_from_file; use ResourceLoader/load for imported assets or classify raw data coverage"
	done < "$globalize_tmp"
fi

if [ "$status" -eq 0 ]; then
	printf 'ok: export-safe loads direct=%s raw=%s dynamic=%s allowlisted=%s\n' "$direct_count" "$raw_count" "$dynamic_count" "$allowlisted_count"
fi
exit "$status"

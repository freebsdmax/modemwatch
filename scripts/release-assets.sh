#!/bin/sh
set -eu

ARTIFACTS_DIR="${1:-artifacts}"
OUT_DIR="${2:-release}"
VERSIONS="${VERSIONS:-23.05.6 24.10.8 25.12.6}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

for ver in $VERSIONS; do
	case "$ver" in
		25.12.6) ext="apk" ;;
		*) ext="ipk" ;;
	esac

	bundle_files=""
	for pkg in modemwatch luci-app-modemwatch luci-i18n-modemwatch-uk; do
		src_dir="$ARTIFACTS_DIR/${pkg}-${ver}-all"
		src=$(find "$src_dir" -type f -name "${pkg}*.${ext}" 2>/dev/null | head -n 1 || true)
		if [ -z "$src" ]; then
			echo "ERROR: missing ${pkg} for ${ver}" >&2
			exit 1
		fi
		base=$(basename "$src")
		suffix="${base#${pkg}}"
		suffix="${suffix#_}"
		suffix="${suffix#-}"
		out="${pkg}_${ver}_${suffix}"
		cp "$src" "$OUT_DIR/$out"
		bundle_files="$bundle_files $out"
	done

	tar -czf "$OUT_DIR/modemwatch-${ver}-all.tar.gz" -C "$OUT_DIR" $bundle_files
done

echo "Release assets:"
ls -l "$OUT_DIR"

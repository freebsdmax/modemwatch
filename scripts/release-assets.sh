#!/bin/sh
set -eu

ARTIFACTS_DIR="${1:-artifacts}"
OUT_DIR="${2:-release}"
VERSIONS="${VERSIONS:-23.05.6 24.10.8 25.12.6}"
TMP_LIST="${TMPDIR:-/tmp}/modemwatch-release-list.$$"

cleanup() {
	rm -f "$TMP_LIST"
}
trap cleanup EXIT INT TERM

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

known_pkgs="modemwatch luci-app-modemwatch"
for dir in i18n/luci-i18n-modemwatch-*; do
	[ -d "$dir" ] && known_pkgs="$known_pkgs $(basename "$dir")"
done

for ver in $VERSIONS; do
	case "$ver" in
		25.12.6) ext="apk" ;;
		*) ext="ipk" ;;
	esac

	src_dir="$ARTIFACTS_DIR/modemwatch-${ver}-all-bundle"
	bundle_dir="$OUT_DIR/.bundle-${ver}"
	rm -rf "$bundle_dir"
	mkdir -p "$bundle_dir"
	bundle_files=""

	find "$src_dir" -type f -name "*.${ext}" 2>/dev/null | sort > "$TMP_LIST" || true
	if [ ! -s "$TMP_LIST" ]; then
		echo "ERROR: no packages for ${ver}" >&2
		exit 1
	fi

	while IFS= read -r src; do
		base=$(basename "$src")
		pkg=""
		for known in $known_pkgs; do
			case "$base" in
				"${known}_"*|"${known}-"*)
					pkg="$known"
					break
					;;
			esac
		done
		if [ -z "$pkg" ]; then
			echo "ERROR: cannot determine package name for ${base}" >&2
			exit 1
		fi
		suffix="${base#"$pkg"}"
		suffix="${suffix#_}"
		suffix="${suffix#-}"
		out="${pkg}_${ver}_${suffix}"
		cp "$src" "$bundle_dir/$out"
		bundle_files="$bundle_files $out"

		# Only the main packages and the Ukrainian translation are
		# published as individual release assets. All other languages
		# are available inside the combined archive.
		case "$pkg" in
			modemwatch|luci-app-modemwatch|luci-i18n-modemwatch-uk)
				cp "$src" "$OUT_DIR/$out"
				;;
		esac
	done < "$TMP_LIST"

	tar -czf "$OUT_DIR/modemwatch-${ver}-all.tar.gz" -C "$bundle_dir" $bundle_files
	rm -rf "$bundle_dir"
done

echo "Release assets:"
ls -l "$OUT_DIR"

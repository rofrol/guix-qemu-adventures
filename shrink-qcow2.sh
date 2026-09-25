#!/usr/bin/env bash
# Run on host after shrink-guest.sh and after VM is shut down.
# Usage: ./shrink-qcow2.sh [--in-place] [image.qcow2]
set -euo pipefail

in_place=0
if [ "${1:-}" = "--in-place" ]; then
	in_place=1
	shift
fi

image="${1:-guix-system-vm-image-1.5.0.aarch64-linux-modified.qcow2}"
# resolve symlink, so --in-place replaces the real file and keeps the symlink
real="$(realpath "$image")"
out="${real%.qcow2}-shrinked.qcow2"
tmp="$out.tmp"

trap 'rm -f "$tmp"' EXIT

# convert drops internal snapshots
if [ -n "$(qemu-img snapshot -l "$real")" ]; then
	echo "$real has internal snapshots, refusing" >&2
	exit 1
fi

du -h "$real"
# convert does not inherit compression type and defaults to zlib
qemu-img convert -p -O qcow2 -c -o compression_type=zstd "$real" "$tmp"
qemu-img check "$tmp"
# keep original permissions (600), not umask ones
chmod "$(stat -f %Lp "$real")" "$tmp"
mv "$tmp" "$out"
du -h "$out"

if [ "$in_place" = 1 ]; then
	mv "$out" "$real"
	echo "Replaced $real"
else
	echo "Written $out"
fi

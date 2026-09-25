#!/usr/bin/env bash
# Run inside the guest (e.g. /mnt/share/shrink-guest.sh) before shrink-qcow2.sh on host.
# qemu must run with discard=unmap,detect-zeroes=unmap on -drive, otherwise fstrim does nothing.
set -euo pipefail

du -sxh /
guix system delete-generations
guix package --delete-generations
# old guix pull generations keep whole Guix revisions alive
guix pull --delete-generations
rm -rf /root/.cache
guix gc
# commit ext4 journal, so fstrim sees blocks freed by gc
sync
# fstrim last, so blocks freed by gc are discarded too
fstrim -av
du -sxh /

echo "Now run: shutdown, then ./shrink-qcow2.sh on host"

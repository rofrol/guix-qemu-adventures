#!/usr/bin/env bash
# Run inside the guest as root (/mnt/share/reconfigure.sh).
set -euo pipefail
config=/mnt/share/config.scm

# --max-jobs=0: the daemon builds only derivations marked preferLocalBuild
# (config files, profile hooks, grafts, GRUB's image) and fails with "unable
# to start any build" on anything else, i.e. on a package without substitutes.
# `guix weather` is not enough: it checks package outputs, not inputs of the
# system's local derivations (grub-theme's image needs guile-rsvg -> librsvg
# -> rust -> llvm). --no-offload so no build goes elsewhere either.
opts=(--max-jobs=0 --no-offload)
trap 'echo "To see what would be compiled: guix system build -n --no-grafts --skip-checks $config" >&2' ERR

guix build "${opts[@]}" guix
guix system build "${opts[@]}" --skip-checks "$config"
guix system reconfigure "${opts[@]}" --skip-checks "$config"

#!/usr/bin/env bash
# Run inside the guest as root (/mnt/share/reconfigure.sh).
set -euo pipefail
config=/mnt/share/config.scm

# Stop if anything would be compiled, except derivations Guix marks
# preferLocalBuild (config files, profile hooks, grafts, GRUB's image).
# `guix weather` is not enough: it checks package outputs, not inputs of the
# system's local derivations (grub-theme's image needs guile-rsvg -> librsvg
# -> rust -> llvm). --no-grafts: with grafts the dry run lists only downloads
# (grafting needs the ungrafted outputs first) and no builds at all. So graft
# replacement packages are not checked; the real run can still build them.
# The dry run prints its plan to stderr, in English with C.
# `guix build guix` below is checked too.
if ! plan=$(export LC_ALL=C LANGUAGE=
            guix system reconfigure -n --no-grafts --skip-checks "$config" 2>&1 &&
            guix build -n --no-grafts guix 2>&1); then
  printf '%s\n' "$plan" >&2
  exit 1
fi
# Indented .drv paths after "would be built:", until the next unindented line.
drvs=$(awk '/would be built:/ { on = 1; next }
            /^[^ \t]/ { on = 0 }
            on && /\.drv$/ { print $1 }' <<< "$plan")
unexpected=0
for drv in $drvs; do
  grep -q '"preferLocalBuild","1"' "$drv" && continue
  echo "would build: $(basename "$drv" .drv | cut -d- -f2-)"
  unexpected=$((unexpected + 1))
done
if (( unexpected )); then
  echo "$unexpected derivations have no substitutes, not reconfiguring" >&2
  exit 1
fi

guix build guix
guix system build --skip-checks "$config"
guix system reconfigure --skip-checks "$config"

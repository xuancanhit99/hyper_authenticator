#!/usr/bin/env bash
set -euo pipefail

# Emit a NUL-delimited source list suitable for `tar --null --files-from=-`.
# `git ls-files --cached` intentionally reports tracked paths deleted in the
# working tree; skip those paths so an uncommitted deletion cannot abort the
# isolated Linux source archive. Keep symlinks, including broken symlinks,
# because their link text is still source material Git can track.
while IFS= read -r -d '' path; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf '%s\0' "$path"
  fi
done < <(git ls-files --cached --others --exclude-standard -z)

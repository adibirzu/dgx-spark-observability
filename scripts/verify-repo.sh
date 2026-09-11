#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
git -C "$root" diff --check

prohibited=$(git -C "$root" ls-files | awk '
  /(^|\/)private(\/|$)|(^|\/)backups(\/|$)|(^|\/)raw(\/|$)|\.(pem|key|p12|pfx|tar|tar\.gz|zip)$/ { print; next }
  /(^|\/)\.env($|\.)/ && $0 !~ /\.env\.example$/ { print }
')
if [ -n "$prohibited" ]; then
  printf '%s\n' "$prohibited" >&2
  exit 1
fi

git -C "$root" ls-files | while IFS= read -r file; do
  "$root/scripts/secret-scan.sh" "$root/$file"
done

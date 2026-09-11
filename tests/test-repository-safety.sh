#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root/scripts/secret-scan.sh" "$root/tests/fixtures/allowed.env.example"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM
printf '%s%s\n' 'TOKEN' '=example-value-that-must-be-rejected' > "$fixture_dir/rejected-secret.txt"
if "$root/scripts/secret-scan.sh" "$fixture_dir/rejected-secret.txt"; then
  echo "scanner accepted a credential fixture" >&2
  exit 1
fi

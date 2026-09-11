#!/bin/sh
set -eu

target=${1:?usage: secret-scan.sh PATH}
if rg -n -i '(sk-[a-z0-9]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|password|secret|api_key)=[^$])' "$target"; then
  exit 1
fi

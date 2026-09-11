#!/bin/sh
set -eu

env_file=${1:?usage: bootstrap-local-llm.sh PRIVATE_RUNTIME_ENV}
case "$env_file" in */private/*) ;; *) echo "runtime file must be below private/" >&2; exit 1;; esac
test ! -e "$env_file" || { echo "runtime file already exists" >&2; exit 1; }
private_dir=$(dirname "$env_file")
mkdir -p "$private_dir"
umask 077
secret() { openssl rand -hex 32; }
postgres_password=$(secret)
clickhouse_password=$(secret)
cat "$PWD/runtime/local-llm.env.example" > "$env_file"
{
  printf 'LITELLM_MASTER_KEY=sk-%s\n' "$(secret)"
  printf 'LANGFUSE_POSTGRES_DB=langfuse\nLANGFUSE_POSTGRES_USER=langfuse\n'
  printf 'LANGFUSE_POSTGRES_PASSWORD=%s\n' "$postgres_password"
  printf 'LANGFUSE_CLICKHOUSE_USER=langfuse\nLANGFUSE_CLICKHOUSE_PASSWORD=%s\n' "$clickhouse_password"
  printf 'LANGFUSE_REDIS_PASSWORD=%s\n' "$(secret)"
  printf 'LITELLM_DATABASE_URL=postgresql://langfuse:%s@langfuse-postgres:5432/langfuse\n' "$postgres_password"
  printf 'LANGFUSE_MASK_INPUTS=true\nLANGFUSE_MASK_OUTPUTS=true\n'
  printf 'LANGFUSE_NEXTAUTH_SECRET=%s\n' "$(secret)"
  printf 'LANGFUSE_SALT=%s\n' "$(secret)"
} >> "$env_file"
chmod 600 "$env_file"
git check-ignore -q "$env_file" || { echo "runtime path is not ignored" >&2; exit 1; }
printf '%s\n' "created protected runtime file: $env_file"

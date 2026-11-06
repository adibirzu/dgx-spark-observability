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
  printf '%s=%s\n' 'LANGFUSE_POSTGRES_PASSWORD' "$postgres_password"
  printf '%s=%s\n' 'LANGFUSE_CLICKHOUSE_USER' 'langfuse'
  printf '%s=%s\n' 'LANGFUSE_CLICKHOUSE_PASSWORD' "$clickhouse_password"
  printf '%s=%s\n' 'LANGFUSE_REDIS_PASSWORD' "$(secret)"
  printf 'LITELLM_DATABASE_URL=postgresql://langfuse:%s@langfuse-postgres:5432/langfuse\n' "$postgres_password"
  printf 'DATABASE_URL=postgresql://langfuse:%s@langfuse-postgres:5432/langfuse\n' "$postgres_password"
  printf 'LANGFUSE_MASK_INPUTS=true\nLANGFUSE_MASK_OUTPUTS=true\n'
  printf '%s=%s\n' 'NEXTAUTH_SECRET' "$(secret)"
  printf '%s=%s\n' 'SALT' "$(secret)"
  printf '%s=%s\n' 'ENCRYPTION_KEY' "$(secret)"
  printf '%s=%s\n' 'MINIO_ROOT_USER' 'langfuse'
  minio_password=$(secret)
  printf '%s=%s\n' 'MINIO_ROOT_PASSWORD' "$minio_password"
  printf '%s=%s\n' 'LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID' 'langfuse'
  printf '%s=%s\n' 'LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY' "$minio_password"
  printf '%s=%s\n' 'LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID' 'langfuse'
  printf '%s=%s\n' 'LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY' "$minio_password"
} >> "$env_file"
chmod 600 "$env_file"
git check-ignore -q "$env_file" || { echo "runtime path is not ignored" >&2; exit 1; }
printf '%s\n' "created protected runtime file: $env_file"

#!/bin/sh
set -eu

grep -q '^QWEN_MODEL=Qwen/Qwen3.8-Flash-Next$' runtime/local-llm.env.example
grep -q 'model_name: qwen3.8-flash-next' runtime/litellm-config.example.yaml
grep -q 'model_name: anthropic-claude' runtime/litellm-config.example.yaml
grep -q 'forward_client_headers_to_llm_api:' runtime/litellm-config.example.yaml
grep -q '  - anthropic-claude$' runtime/litellm-config.example.yaml
if rg -n 'forward_client_headers_to_llm_api: true|0\.0\.0\.0|LANGFUSE_CAPTURE_CONTENT=true' runtime; then
  echo "unsafe local LLM runtime setting" >&2
  exit 1
fi
if rg -n 'LANGFUSE_NEXTAUTH_SECRET|LANGFUSE_SALT|langfuse/langfuse:3|clickhouse-server:24\.8' runtime compose scripts; then
  echo "legacy Langfuse v3 configuration remains in an executable surface" >&2
  exit 1
fi
grep -q '^  litellm:$' compose/local-llm-primary.compose.example.yaml
grep -q '^  langfuse-web:$' compose/local-llm-primary.compose.example.yaml
grep -q '^  langfuse-worker:$' compose/local-llm-primary.compose.example.yaml
grep -q '^  langfuse-minio:$' compose/local-llm-primary.compose.example.yaml
grep -q '^LANGFUSE_IMAGE=docker.langfuse.com/langfuse/langfuse:4$' runtime/local-llm.env.example
grep -q '^LANGFUSE_WORKER_IMAGE=docker.langfuse.com/langfuse/langfuse-worker:4$' runtime/local-llm.env.example
grep -q '^CLICKHOUSE_IMAGE=clickhouse/clickhouse-server:25.12$' runtime/local-llm.env.example
grep -q 'image: \${LANGFUSE_WORKER_IMAGE}' compose/local-llm-primary.compose.example.yaml
grep -q 'image: \${CLICKHOUSE_IMAGE}' compose/local-llm-primary.compose.example.yaml
grep -q 'LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://langfuse-minio:9000' runtime/local-llm.env.example
grep -q 'LANGFUSE_S3_MEDIA_UPLOAD_INTERNAL_ENDPOINT=http://langfuse-minio:9000' runtime/local-llm.env.example
grep -q 'LANGFUSE_MIGRATION_V4_WRITE_MODE=dual' runtime/local-llm.env.example
grep -q '127.0.0.1:${LITELLM_PORT}:4000' compose/local-llm-primary.compose.example.yaml
grep -q '127.0.0.1:${LANGFUSE_PORT}:3000' compose/local-llm-primary.compose.example.yaml
if rg -n '0\.0\.0\.0:|privileged: true' compose/local-llm-primary.compose.example.yaml; then
  echo "unsafe local LLM compose setting" >&2
  exit 1
fi
mkdir -p private
fixture=$(mktemp -d private/local-llm-test.XXXXXX)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
runtime="$PWD/$fixture/runtime.env"
scripts/bootstrap-local-llm.sh "$runtime" >/dev/null
test "$(stat -c '%a' "$runtime")" = 600
postgres_password=$(sed -n 's/^LANGFUSE_POSTGRES_PASSWORD=//p' "$runtime")
database_url=$(sed -n 's/^LITELLM_DATABASE_URL=//p' "$runtime")
case "$database_url" in *":$postgres_password@langfuse-postgres:5432/langfuse") ;; *)
  echo "LiteLLM database URL does not use generated Postgres credential" >&2
  exit 1;;
esac
test "$(sed -n 's/^DATABASE_URL=//p' "$runtime")" = "$database_url"
test -n "$(sed -n 's/^NEXTAUTH_SECRET=//p' "$runtime")"
test -n "$(sed -n 's/^SALT=//p' "$runtime")"
test -n "$(sed -n 's/^ENCRYPTION_KEY=//p' "$runtime")"
test -n "$(sed -n 's/^MINIO_ROOT_USER=//p' "$runtime")"
test -n "$(sed -n 's/^MINIO_ROOT_PASSWORD=//p' "$runtime")"

#!/bin/sh
set -eu

ollama_api_base=${OLLAMA_API_BASE:?set OLLAMA_API_BASE to private Ollama endpoint}
body=$(curl --fail --silent --show-error --max-time 3 "$ollama_api_base/api/ps")
loaded=$(printf '%s' "$body" | jq '[.models[]?] | length')
printf '%s\n' '# TYPE ollama_state gauge'
printf '%s\n' 'ollama_state{state="up"} 1'
printf 'ollama_loaded_models %s\n' "$loaded"

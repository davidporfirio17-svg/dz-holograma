#!/usr/bin/env bash
set -euo pipefail

# Demonstración segura de la API de Cloudflare.
# No pongas tokens en este archivo. Usa variables de entorno o un gestor de secretos.
# Requisitos: curl, jq, base64.
# Variables requeridas: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
# Opcional: CLOUDFLARE_WORKER_NAME (por defecto: dz-holograma).

: "${CLOUDFLARE_API_TOKEN:?Falta CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?Falta CLOUDFLARE_ACCOUNT_ID}"
WORKER_NAME="${CLOUDFLARE_WORKER_NAME:-dz-holograma}"
API="https://api.cloudflare.com/client/v4"
AUTH=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H 'Content-Type: application/json')

cf() {
  curl --fail-with-body --silent --show-error "${AUTH[@]}" "$@"
}

say() { printf '\n== %s ==\n' "$1"; }

say '1. Verificar token'
cf "${API}/user/tokens/verify" | jq '{success,result}'

say '2. Listar Workers'
cf "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts" \
  | jq '[.result[] | {name:.id, tag:.tag}]'

say '3. Consultar el Worker objetivo'
cf "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
  | jq '{success,result:{id:.result.id,etag:.result.etag,modified_on:.result.modified_on}}'

say '4. Listar namespaces KV'
cf "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/storage/kv/namespaces?per_page=100" \
  | jq '[.result[] | {id,title}]'

say '5. Listar buckets R2'
cf "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets?per_page=100" \
  | jq '[.result[] | {name,creation_date,location}]'

say '6. Listar deployments del Worker'
cf "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/deployments?per_page=20" \
  | jq '[.result[] | {id,created_on,source,versions,annotations}]'

# Demostración opcional de subida. Solo se ejecuta si se proporciona un archivo.
# Requiere que el token tenga Workers Scripts Edit.
if [[ "${1:-}" == "--deploy" ]]; then
  SCRIPT_FILE="${2:-worker/dz.mjs}"
  [[ -f "$SCRIPT_FILE" ]] || { echo "No existe: $SCRIPT_FILE" >&2; exit 1; }
  say "7. Subir y desplegar ${SCRIPT_FILE}"
  curl --fail-with-body --silent --show-error \
    -X PUT "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -F 'metadata={"main_module":"worker.mjs","compatibility_date":"2026-10-19","bindings":[{"type":"kv_namespace","name":"DZH_KV","namespace_id":"0a46c6a8694d477f8430b4aa1f7921bc"},{"type":"r2_bucket","name":"DZH_FILES","bucket_name":"dz-holograma-files"}]};type=application/json' \
    -F "worker.mjs=@${SCRIPT_FILE};type=application/javascript+module" \
    | jq '{success,result,errors,messages}'
fi

# Demostración de la API de Cloudflare

## Qué se probó

La conexión OAuth de Cloudflare está activa para `davidporfirio17@gmail.com`. La API permitió consultar Workers, KV, R2 y el historial de deployments.

En la cuenta se confirmó:

- Worker `dz-holograma`.
- KV `DZ_HOLOGRAMA_DATA`.
- R2 `dz-holograma-files`.
- Historial de deployments del Worker.

## Capacidades principales

La API de Cloudflare permite administrar Workers y sus versiones, crear deployments, consultar logs e historial, asociar bindings de KV/R2, leer y escribir valores de KV, crear y listar buckets R2, configurar dominios y rutas, y gestionar secretos y variables de entorno. Los permisos deben limitarse por producto y por cuenta.

El script `scripts/cloudflare-api-demo.sh` ejecuta lecturas y verificación de token. Con `--deploy` también demuestra una subida multipart del Worker, pero solo si se ejecuta localmente con un token válido en `CLOUDFLARE_API_TOKEN`.

## Uso seguro

```bash
export CLOUDFLARE_API_TOKEN='secreto-solo-en-el-entorno'
export CLOUDFLARE_ACCOUNT_ID='cdf6281fd2e24d718ad9288b9d0cfd76'
./scripts/cloudflare-api-demo.sh
```

Para probar una subida:

```bash
./scripts/cloudflare-api-demo.sh --deploy worker/dz.mjs
```

Nunca se debe escribir el token en el repositorio, en el script ni en el chat. Para automatización, Cloudflare recomienda guardar `CLOUDFLARE_API_TOKEN` y `CLOUDFLARE_ACCOUNT_ID` como secretos del sistema CI/CD.

## Referencias

- [Cloudflare Workers API](https://developers.cloudflare.com/workers/versions-and-deployments/)
- [Cloudflare Workers authorization](https://developers.cloudflare.com/workers/authorization/)
- [Cloudflare KV](https://developers.cloudflare.com/kv/)
- [Cloudflare R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)
- [Cloudflare Workers Builds API](https://developers.cloudflare.com/workers/ci-cd/builds/api-reference/)

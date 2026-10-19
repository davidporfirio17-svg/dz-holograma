# DZ Holograma

Proyecto independiente de DZ Holograma: IPA cliente, panel administrativo y Worker/API separados de DZ principal.

## Separación de datos

Este repositorio no contiene keys, usuarios, vendedores, cases ni archivos operativos de DZ principal. El Worker usa el binding KV `DZH_KV` y claves con prefijo `dzh_`; debe desplegarse en un Worker independiente. La IPA apunta provisionalmente a `https://dz-holograma.davidporfirio17.workers.dev`.

## Flujos incluidos

La base conserva el flujo administrativo de DZ: crear y editar modos/cases, activar por Free Fire MAX o normal, ordenar, pausar/desactivar, eliminar, limpiar archivos, subir/reemplazar archivos por slot, gestionar licencias, vendedores, sesiones, auditoría, mantenimiento y configuración de avisos. Los valores iniciales de DZ no se copian como datos; el KV nuevo empieza vacío y debe configurarse desde el panel.

## Estado de Cloudflare

Ya existen recursos independientes en Cloudflare:

- Worker: `dz-holograma`.
- KV: `DZ_HOLOGRAMA_DATA`, enlazable como `DZH_KV`.
- R2: `dz-holograma-files`, enlazable como `DZH_FILES`.

El Worker que estaba desplegado al revisar la cuenta era una versión inicial de Files/Cases. El código completo del flujo administrativo vive en `worker/dz.mjs` y debe publicarse sobre ese Worker cuando la autorización de despliegue del conector principal de Cloudflare esté disponible.

## Despliegue y validación

1. Asociar `DZ_HOLOGRAMA_DATA` como `DZH_KV` y `dz-holograma-files` como `DZH_FILES`.
2. Configurar credenciales y secretos propios de Holograma.
3. Publicar `worker/dz.mjs` sobre el Worker existente `dz-holograma`.
4. Asociar el hostname definido para la IPA.
5. Configurar el bundle identifier y firma de la IPA independiente.
6. Validar login, creación de un case de prueba, subida de archivos MAX/normal, pausa, reanudación y eliminación antes de usar datos reales.

La configuración operativa y los secretos no se guardan en Git.

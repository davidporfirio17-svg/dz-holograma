# DZ Holograma

Proyecto independiente de DZ Holograma: IPA cliente, panel administrativo y Worker/API separados de DZ principal.

## Separación de datos

Este repositorio no contiene keys, usuarios, vendedores, cases ni archivos operativos de DZ principal. El Worker usa el binding KV `DZH_KV` y claves con prefijo `dzh_`; debe desplegarse en un Worker independiente. La IPA apunta provisionalmente a `https://dz-holograma.davidporfirio17.workers.dev` y no debe publicarse hasta asociar ese hostname al Worker nuevo.

## Flujos incluidos

La base conserva el flujo administrativo de DZ: crear y editar modos/cases, activar por Free Fire MAX o normal, ordenar, pausar/desactivar, eliminar, limpiar archivos, subir/reemplazar archivos por slot, gestionar licencias, vendedores, sesiones, auditoría, mantenimiento y configuración de avisos. Los valores iniciales de DZ no se copian como datos; el KV nuevo empieza vacío y debe configurarse desde el panel.

## Despliegue inicial

1. Crear un namespace KV nuevo y enlazarlo al Worker como `DZH_KV`.
2. Configurar credenciales y secretos propios de Holograma.
3. Crear el Worker `dz-holograma` y asociar el hostname definido para la IPA.
4. Configurar el bundle identifier y firma de la IPA independiente.
5. Validar login, creación de un case de prueba, subida de archivos MAX/normal, pausa, reanudación y eliminación antes de usar datos reales.

La configuración operativa y los secretos no se guardan en Git.

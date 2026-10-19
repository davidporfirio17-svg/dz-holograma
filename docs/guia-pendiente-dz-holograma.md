# Guía pendiente: DZ Holograma

## Aclaración importante

El proyecto activo es **DZ Holograma**, también llamado Web 2. El trabajo de infraestructura ocurre en el Worker de Cloudflare llamado `dz-holograma`.

No se está modificando el Worker principal `dz`, ni `davizin-ios-v2`, ni sus keys, archivos o cases.

Cuando se menciona **GitHub**, no significa otro Walker ni otra web. GitHub se usa únicamente para guardar el código, mantener historial y ejecutar el despliegue automático. El código termina publicándose en el Worker de Cloudflare `dz-holograma`.

## Estado actual

Ya está hecho:

- Repositorio privado: `davidporfirio17-svg/dz-holograma`.
- Worker independiente: `dz-holograma`.
- KV independiente: `DZ_HOLOGRAMA_DATA`.
- R2 independiente: `dz-holograma-files`.
- Código del Worker completo guardado en `worker/dz.mjs`.
- Configuración de bindings en `worker/wrangler.toml`.
- Workflow de despliegue en `.github/workflows/deploy-cloudflare.yml`.
- Script de demostración de la API en `scripts/cloudflare-api-demo.sh`.
- El código pasa la validación de sintaxis JavaScript.
- El repositorio principal `davizin-ios-v2` permanece intacto.
- El Worker principal `dz` permanece intacto.

## Lo que falta

### 1. Agregar secretos en GitHub

En el repositorio privado `dz-holograma`:

1. Abrir **Settings**.
2. Abrir **Secrets and variables → Actions**.
3. Pulsar **New repository secret**.
4. Crear el secreto:

```text
Name: CLOUDFLARE_ACCOUNT_ID
Value: cdf6281fd2e24d718ad9288b9d0cfd76
```

5. Crear otro secreto:

```text
Name: CLOUDFLARE_API_TOKEN
Value: el token de Cloudflare creado para despliegue
```

El token se debe escribir directamente en GitHub. No se debe enviar por este chat ni guardarlo en un archivo.

El token debe estar limitado a la cuenta correcta y tener permiso de edición para Workers Scripts. El workflow usa ese token exclusivamente para ejecutar `wrangler deploy`.

### 2. Ejecutar el primer despliegue automático

En el repositorio:

1. Abrir la pestaña **Actions**.
2. Seleccionar **Deploy DZ Holograma Worker**.
3. Pulsar **Run workflow**.
4. Elegir la rama `main`.
5. Pulsar nuevamente **Run workflow**.
6. Esperar a que aparezca el check verde.

El workflow hará tres cosas:

1. Descargar el repositorio.
2. Validar `worker/dz.mjs`.
3. Publicarlo en Cloudflare usando `worker/wrangler.toml`.

### 3. Configurar los secretos del propio Worker

El código espera al menos estos secretos en Cloudflare:

```text
DZ_MASTER_PASSWORD
DZ_SIGN_SECRET
```

Deben configurarse en **Cloudflare → Workers & Pages → dz-holograma → Settings → Variables and Bindings → Secrets**.

Los valores deben ser nuevos y exclusivos de Holograma. No se deben copiar las credenciales de DZ principal.

### 4. Confirmar los bindings después del despliegue

En la configuración del Worker debe quedar:

```text
DZH_KV    → DZ_HOLOGRAMA_DATA
DZH_FILES → dz-holograma-files
```

Si Wrangler muestra que el binding ya existe, se conserva; no se debe crear otro namespace ni otro bucket.

### 5. Probar la Web 2

Después del despliegue hay que abrir el dominio `workers.dev` de `dz-holograma` y comprobar:

- La pantalla de login.
- Acceso con las credenciales nuevas de Holograma.
- Creación de un case de prueba.
- Pausa del case.
- Reanudación del case.
- Eliminación del case de prueba.
- Subida de un archivo pequeño de prueba.
- Reemplazo del archivo.
- Consulta de actividad y logs.
- Cierre de sesión.

No se deben subir todavía archivos reales ni keys reales hasta terminar esta prueba.

### 6. Configurar el dominio final, si se va a usar uno

Si se quiere un dominio propio para la Web 2, se configura después de validar el Worker en `workers.dev`. El dominio debe apuntar únicamente a `dz-holograma` y no al Worker `dz` principal.

### 7. Preparar la IPA independiente

La IPA debe apuntar al endpoint de `dz-holograma`, no al endpoint de DZ principal. También debe conservar un bundle identifier distinto.

Antes de distribuirla hay que verificar:

- Bundle identifier independiente.
- URL de API de Holograma.
- Keys y casos separados.
- Sin endpoints heredados de DZ principal.
- Firma y provisioning propios.

## Qué no hay que hacer

- No tocar `davizin-ios-v2`.
- No tocar el Worker `dz` principal.
- No reutilizar `dz_keys`.
- No copiar los cases ni los archivos de DZ principal.
- No enviar tokens de Cloudflare por chat.
- No poner secretos en GitHub como archivos normales.
- No crear otro Worker con un nombre diferente.
- No crear otro KV o R2 si ya aparecen los recursos indicados.

## Resumen corto

El proyecto está en esta etapa:

```text
Código de DZ Holograma       Listo
Worker dz-holograma          Creado
KV independiente             Creado
R2 independiente             Creado
Automatización GitHub        Configurada
Secretos de GitHub            Pendiente
Primer despliegue automático  Pendiente
Secretos del Worker           Pendiente
Pruebas funcionales           Pendiente
Dominio final                 Opcional
IPA independiente             Pendiente de conectar/probar
```

#ifndef NYXEL_AIRLIFT_BRIDGE_H
#define NYXEL_AIRLIFT_BRIDGE_H
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int nyxel_pair_rppairing(const char *service_name, const char *reg_type, const char *hostname,
                         const char *pin, const unsigned char *record, size_t record_len,
                         char **error_message);
void nyxel_free_string(char *value);
int nyxel_pairable_host_start(const char *name, const char *model);
void nyxel_pairable_host_stop(void);
void nyxel_pairable_host_accept_local_fd(int fd);
uint16_t nyxel_pairable_host_local_port(void);

/* Fase 2: una vez que el dispositivo ya aceptó el emparejamiento (fase 1,
   arriba), iOS empieza a anunciar su propio servicio "_remotepairing._tcp".
   Esta función lo descubre, abre el túnel RSD reutilizando el registro de
   pairing ya guardado (sin PIN, ya es de confianza), y hace una operación
   de archivo con permisos elevados sobre el contenedor de bundle_id —
   exactamente el mecanismo que usa Xcode/Finder para gestionar documentos
   de apps en un dispositivo sin jailbreak.
   write_mode: 1 = escribir in_data en relative_path; 0 = leer relative_path.
   Devuelve 0 en éxito. En lectura, el llamador debe liberar *out_data con
   nyxel_free_data. */
int nyxel_airlift_container_io(const unsigned char *pairing_record, size_t record_len,
                               const char *bundle_id, const char *relative_path,
                               int write_mode,
                               const unsigned char *in_data, size_t in_len,
                               unsigned char **out_data, size_t *out_len,
                               double discover_timeout_seconds,
                               char **error_message);
void nyxel_free_data(unsigned char *data, size_t len);
#ifdef __cplusplus
}
#endif
#endif

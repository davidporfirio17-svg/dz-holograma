#ifndef NYXEL_AIRLIFT_C_H
#define NYXEL_AIRLIFT_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ALLogCallback)(void *ctx, const char *msg);
typedef void (*ALPairReadyCb)(void *ctx, const char *service_id, uint16_t port,
                               const char *const *txt_keys,
                               const char *const *txt_vals, size_t txt_count);
typedef void (*ALPairPinCb)(const char *pin, void *ctx);

typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
    char *host_alt_irk_hex;
} ALPairResult;

int32_t al_pairing_run_host(const char *bind_addr, uint16_t port,
                            const char *name, const char *model,
                            const char *out_path, const char *host_alt_irk_hex,
                            ALPairReadyCb ready_cb, ALPairPinCb pin_cb,
                            void *ctx, ALPairResult *out);
void al_pairing_result_free(ALPairResult *r);
void al_string_free(char *p);
int32_t al_exploit_write_dir(const char *pairing_path, const char *source_dir,
                             const char *target_dir, ALLogCallback log_cb,
                             void *ctx, char **out_error);
int32_t al_exploit_read_file(const char *pairing_path, const char *target_path,
                             const char *output_path, ALLogCallback log_cb,
                             void *ctx, char **out_error);
int32_t al_find_app_container(const char *pairing_path, const char *bundle_id,
                              ALLogCallback log_cb, void *ctx,
                              char **out_container, char **out_error);

#ifdef __cplusplus
}
#endif

#endif

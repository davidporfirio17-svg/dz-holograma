#ifndef NYXEL_IDEVICE_FFI_H
#define NYXEL_IDEVICE_FFI_H

#include <stddef.h>
#include <stdbool.h>
#include <sys/socket.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct IdeviceFfiError IdeviceFfiError;
typedef struct PairableHostHandle PairableHostHandle;
typedef void (*PairableHostPinCb)(const char *pin, void *context);
typedef socklen_t idevice_socklen_t;
typedef struct sockaddr idevice_sockaddr;

IdeviceFfiError *rp_pairing_file_generate(const char *hostname,
                                           void **out);
IdeviceFfiError *rp_pairing_file_from_bytes(const unsigned char *data,
                                             size_t len,
                                             void **out);
IdeviceFfiError *rp_pairing_file_to_bytes(void *handle,
                                          unsigned char **out_data,
                                          size_t *out_len);
void rp_pairing_file_free(void *handle);
void idevice_data_free(unsigned char *data, size_t len);
void idevice_string_free(char *value);

IdeviceFfiError *pairable_host_prepare(
    const char *name,
    const char *model,
    bool allows_pinless_pairing,
    PairableHostHandle **out_handle,
    char **out_service_id,
    unsigned char **out_txt_data,
    size_t *out_txt_len,
    unsigned char *out_host_alt_irk);
IdeviceFfiError *pairable_host_accept_fd(
    PairableHostHandle *handle,
    int fd,
    PairableHostPinCb pin_cb,
    void *context,
    void **out_peer_device,
    void **out_pairing_file);
void pairable_host_free(PairableHostHandle *handle);
void idevice_error_free(IdeviceFfiError *error);

IdeviceFfiError *tunnel_create_rppairing(
    const idevice_sockaddr *addr,
    idevice_socklen_t addr_len,
    const char *hostname,
    void *pairing_file,
    const char *(*pin_callback)(void *context),
    void *pin_context,
    void **out_adapter,
    void **out_handshake);

void adapter_free(void *handle);
void rsd_handshake_free(void *handle);

/* House Arrest / AFC — acceso con permisos elevados a la carpeta de otra app,
   via el tunel RSD ya establecido por tunnel_create_rppairing. */
typedef struct HouseArrestClientHandle HouseArrestClientHandle;
typedef struct AfcClientHandle AfcClientHandle;
typedef struct AfcFileHandle AfcFileHandle;

typedef enum {
    NyxelAfcRdOnly = 1,
    NyxelAfcRw = 2,
    NyxelAfcWrOnly = 3,
    NyxelAfcWr = 4,
    NyxelAfcAppend = 5,
    NyxelAfcRdAppend = 6
} NyxelAfcFopenMode;

IdeviceFfiError *house_arrest_client_connect_rsd(
    void *adapter,
    void *handshake,
    HouseArrestClientHandle **client);
IdeviceFfiError *house_arrest_vend_container(
    HouseArrestClientHandle *client,
    const char *bundle_id,
    AfcClientHandle **afc_client);
void house_arrest_client_free(HouseArrestClientHandle *handle);

IdeviceFfiError *afc_file_open(
    AfcClientHandle *client,
    const char *path,
    NyxelAfcFopenMode mode,
    AfcFileHandle **handle);
IdeviceFfiError *afc_file_close(AfcFileHandle *handle);
IdeviceFfiError *afc_file_write(AfcFileHandle *handle, const unsigned char *data, size_t length);
IdeviceFfiError *afc_file_read_entire(AfcFileHandle *handle, unsigned char **data, size_t *length);
void afc_client_free(AfcClientHandle *handle);

#ifdef __cplusplus
}
#endif

#endif

#import "NixelAirLiftBridge.h"
#import "NixelIdeviceFFI.h"
#import "NixelAirLiftC.h"
#import <Foundation/Foundation.h>
#import <dns_sd.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <unistd.h>

struct NyxelResolveContext {
    struct sockaddr_storage address;
    socklen_t length;
    char host[256];
    uint16_t port;
    int done;
    int error;
};

struct NyxelFfiErrorView {
    int32_t code;
    int32_t sub_code;
    const char *message;
};

static NSString *nyxel_ffi_error_text(IdeviceFfiError *error) {
    if (!error) return @"sin error";
    const struct NyxelFfiErrorView *view = (const struct NyxelFfiErrorView *)error;
    NSString *message = view->message ? [NSString stringWithUTF8String:view->message] : @"sin mensaje";
    return [NSString stringWithFormat:@"code=%d subcode=%d %@", view->code, view->sub_code, message];
}

static void nyxel_resolve_callback(DNSServiceRef sdRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                                   DNSServiceErrorType errorCode, const char *fullname,
                                   const char *hosttarget, uint16_t port, uint16_t txtLen,
                                   const unsigned char *txtRecord, void *context) {
    (void)sdRef; (void)flags; (void)interfaceIndex; (void)fullname; (void)txtLen; (void)txtRecord;
    struct NyxelResolveContext *ctx = context;
    if (errorCode != kDNSServiceErr_NoError || !hosttarget) { ctx->error = 1; ctx->done = 1; return; }
    ctx->port = ntohs(port);
    snprintf(ctx->host, sizeof(ctx->host), "%s", hosttarget);
    struct addrinfo hints = {0};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *result = NULL;
    if (getaddrinfo(hosttarget, NULL, &hints, &result) != 0 || !result) { ctx->error = 2; ctx->done = 1; return; }
    memcpy(&ctx->address, result->ai_addr, result->ai_addrlen);
    ctx->length = (socklen_t)result->ai_addrlen;
    if (ctx->address.ss_family == AF_INET) ((struct sockaddr_in *)&ctx->address)->sin_port = htons(ctx->port);
    if (ctx->address.ss_family == AF_INET6) ((struct sockaddr_in6 *)&ctx->address)->sin6_port = htons(ctx->port);
    freeaddrinfo(result);
    ctx->done = 1;
}

static int nyxel_resolve(const char *service, const char *regtype, struct sockaddr_storage *address, socklen_t *length) {
    if (!service || !regtype || !address || !length) return -1;
    struct NyxelResolveContext ctx = {0};
    DNSServiceRef ref = NULL;
    DNSServiceErrorType e = DNSServiceResolve(&ref, 0, 0, service, regtype, "local.", nyxel_resolve_callback, &ctx);
    if (e != kDNSServiceErr_NoError || !ref) return -2;
    while (!ctx.done) {
        e = DNSServiceProcessResult(ref);
        if (e != kDNSServiceErr_NoError) { ctx.error = 3; break; }
    }
    DNSServiceRefDeallocate(ref);
    if (ctx.error || !ctx.done) return -4;
    memcpy(address, &ctx.address, sizeof(*address));
    *length = ctx.length;
    return 0;
}

static const char *nyxel_pin_callback(void *context) { return (const char *)context; }

int nyxel_pair_rppairing(const char *service_name, const char *reg_type, const char *hostname,
                         const char *pin, const unsigned char *record, size_t record_len,
                         char **error_message) {
    if (error_message) *error_message = NULL;
    struct sockaddr_storage address = {0};
    socklen_t addressLength = 0;
    int resolveResult = nyxel_resolve(service_name, reg_type, &address, &addressLength);
    if (resolveResult != 0) return resolveResult;
    void *pairing = NULL;
    IdeviceFfiError *error = rp_pairing_file_from_bytes(record, record_len, &pairing);
    if (error || !pairing) return -10;
    void *adapter = NULL;
    void *handshake = NULL;
    error = tunnel_create_rppairing((const struct sockaddr *)&address, addressLength, hostname,
                                    pairing, nyxel_pin_callback, (void *)(pin ?: "000000"),
                                    &adapter, &handshake);
    rp_pairing_file_free(pairing);
    if (error) {
        NSLog(@"[AirLift] pair_rppairing falló: %@", nyxel_ffi_error_text(error));
        idevice_error_free(error);
        return -11;
    }
    if (adapter) adapter_free(adapter);
    if (handshake) rsd_handshake_free(handshake);
    return 0;
}

static uint16_t nyxel_pairing_host_local_port;
static volatile BOOL nyxel_pairing_host_running;
static void nyxel_pairing_post(NSString *name, NSDictionary *userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:userInfo];
    });
}
extern void nyxel_nw_listener_start(const char *service_name, uint16_t raw_port,
                                    const unsigned char *txt, size_t txt_len);
extern void nyxel_nw_listener_stop(void);

static void nyxel_pairing_pin_callback(const char *pin, void *context) {
    (void)context;
    NSString *value = pin ? [NSString stringWithUTF8String:pin] : @"";
    nyxel_pairing_post(@"NyxelPairingPIN", @{ @"pin": value });
}

static void nyxel_pairing_ready_callback(void *context, const char *service_id,
                                         uint16_t port, const char *const *txt_keys,
                                         const char *const *txt_vals, size_t txt_count) {
    (void)context;
    if (!service_id || !txt_keys || !txt_vals || txt_count == 0) {
        nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"AirLift devolvió datos mDNS incompletos." });
        return;
    }
    NSMutableDictionary *records = [NSMutableDictionary dictionaryWithCapacity:txt_count];
    for (size_t i = 0; i < txt_count; i++) {
        if (!txt_keys[i] || !txt_vals[i]) continue;
        NSString *key = [NSString stringWithUTF8String:txt_keys[i]];
        NSString *value = [NSString stringWithUTF8String:txt_vals[i]];
        if (key && value) records[key] = [value dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSString *serviceName = [NSString stringWithUTF8String:service_id];
    NSDictionary *copiedRecords = [records copy];
    if (!serviceName.length || port == 0 || copiedRecords.count == 0) {
        nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"AirLift devolvió un nombre, puerto o TXT inválido." });
        return;
    }
    // Los punteros del callback FFI solo viven durante esta llamada; conservar
    // copias antes de saltar al hilo principal y publicar el servicio mediante
    // Network.framework, cuyo listener admite enlaces Wi-Fi peer-to-peer.
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                NSData *txtRecord = [NSNetService dataFromTXTRecordDictionary:copiedRecords];
                if (!txtRecord) {
                    nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"No se pudo serializar el registro mDNS de AirLift." });
                    return;
                }
                nyxel_pairing_host_local_port = port;
                // NWListener acepta conexiones cercanas por Wi-Fi P2P/AWDL aun
                // cuando el equipo mantiene datos celulares para Internet.
                // El proxy Swift reenvía el flujo al socket local de AirLift.
                nyxel_nw_listener_start(serviceName.UTF8String, port,
                                         (const unsigned char *)txtRecord.bytes,
                                         txtRecord.length);
            } @catch (NSException *exception) {
                nyxel_pairing_post(@"NyxelPairingHostFailed", @{
                    @"message": [NSString stringWithFormat:@"El publicador AirLift lanzó %@: %@",
                                 exception.name, exception.reason ?: @"sin detalle"]
                });
            }
        }
    });
}

static void nyxel_pairing_run_airlift(void) {
    @autoreleasepool {
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [documents stringByAppendingPathComponent:@"airlift_pairing.plist"];
        if (!path) path = @"/tmp/airlift_pairing.plist";
        ALPairResult result = {0};
        nyxel_pairing_host_running = YES;
        int32_t code = al_pairing_run_host("0.0.0.0", 0, "SupportPatch", "iPhone",
                                           path.UTF8String, "",
                                           nyxel_pairing_ready_callback,
                                           nyxel_pairing_pin_callback, NULL, &result);
        nyxel_pairing_host_running = NO;
        if (code == 0 && result.pairing_file_path) {
            NSData *record = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:result.pairing_file_path]];
            if (record.length > 0) {
                nyxel_pairing_post(@"NyxelPairingCompleted", @{ @"record": record });
            } else {
                nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"AirLift terminó sin un registro de pairing válido." });
            }
        } else {
            NSString *message = result.error ? [NSString stringWithUTF8String:result.error] : @"El host RPPairing de AirLift falló.";
            nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": message ?: @"El host RPPairing de AirLift falló." });
        }
        al_pairing_result_free(&result);
    }
}

int nyxel_pairable_host_start(const char *name, const char *model) {
    (void)name;
    (void)model;
    nyxel_pairable_host_stop();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        nyxel_pairing_run_airlift();
    });
    return 0;
}

void nyxel_pairable_host_accept_local_fd(int fd) {
    if (fd >= 0) close(fd);
}

uint16_t nyxel_pairable_host_local_port(void) {
    return nyxel_pairing_host_local_port;
}

void nyxel_pairable_host_stop(void) {
    nyxel_nw_listener_stop();
    nyxel_pairing_host_running = NO;
    nyxel_pairing_host_local_port = 0;
}

void nyxel_free_string(char *value) { if (value) free(value); }

#pragma mark - Fase 2: House Arrest / AFC por el túnel RSD

struct NyxelBrowseContext {
    char serviceName[256];
    char regType[256];
    int done;
    int found;
};

static void nyxel_browse_callback(DNSServiceRef sdRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                                  DNSServiceErrorType errorCode, const char *serviceName,
                                  const char *regtype, const char *replyDomain, void *context) {
    (void)sdRef; (void)interfaceIndex; (void)replyDomain;
    struct NyxelBrowseContext *ctx = context;
    if (errorCode != kDNSServiceErr_NoError) { ctx->done = 1; return; }
    if (!(flags & kDNSServiceFlagsAdd)) return;
    snprintf(ctx->serviceName, sizeof(ctx->serviceName), "%s", serviceName ?: "");
    snprintf(ctx->regType, sizeof(ctx->regType), "%s", regtype ?: "");
    ctx->found = 1;
    ctx->done = 1;
}

/// Tras el emparejamiento (fase 1), iOS anuncia "_remotepairing._tcp" por su
/// cuenta. Lo descubrimos y resolvemos reutilizando nyxel_resolve().
static int nyxel_discover_remotepairing(struct sockaddr_storage *address, socklen_t *length,
                                        double timeoutSeconds) {
    struct NyxelBrowseContext ctx = {0};
    DNSServiceRef ref = NULL;
    DNSServiceErrorType e = DNSServiceBrowse(&ref, 0, 0, "_remotepairing._tcp", "local.",
                                             nyxel_browse_callback, &ctx);
    if (e != kDNSServiceErr_NoError || !ref) return -1;
    int fd = DNSServiceRefSockFD(ref);
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + timeoutSeconds;
    while (!ctx.done && [NSDate timeIntervalSinceReferenceDate] < deadline) {
        fd_set fds; FD_ZERO(&fds); FD_SET(fd, &fds);
        struct timeval tv = {0, 200000};
        if (select(fd + 1, &fds, NULL, NULL, &tv) > 0) {
            if (DNSServiceProcessResult(ref) != kDNSServiceErr_NoError) break;
        }
    }
    DNSServiceRefDeallocate(ref);
    if (!ctx.found) return -2;
    return nyxel_resolve(ctx.serviceName, ctx.regType, address, length);
}

int nyxel_airlift_container_io(const unsigned char *pairing_record, size_t record_len,
                               const char *bundle_id, const char *relative_path,
                               int write_mode,
                               const unsigned char *in_data, size_t in_len,
                               unsigned char **out_data, size_t *out_len,
                               double discover_timeout_seconds,
                               char **error_message) {
    if (error_message) *error_message = NULL;
    if (!pairing_record || record_len == 0 || !bundle_id || !relative_path) {
        if (error_message) *error_message = strdup("Parámetros inválidos.");
        return -1;
    }

    char normalizedPath[1024];
    if (relative_path[0] == '/') {
        snprintf(normalizedPath, sizeof(normalizedPath), "%s", relative_path);
    } else {
        snprintf(normalizedPath, sizeof(normalizedPath), "/%s", relative_path);
    }

    NSLog(@"[AirLift] Descubriendo _remotepairing._tcp (timeout=%.0fs)...", discover_timeout_seconds);
    struct sockaddr_storage address = {0};
    socklen_t addressLength = 0;
    if (nyxel_discover_remotepairing(&address, &addressLength, discover_timeout_seconds) != 0) {
        if (error_message) *error_message = strdup("No se encontró \"_remotepairing._tcp\" del dispositivo. ¿Sigue emparejado en Modo desarrollador?");
        return -2;
    }
    NSLog(@"[AirLift] Servicio descubierto. Parseando registro de pairing...");

    void *pairingFile = NULL;
    IdeviceFfiError *err = rp_pairing_file_from_bytes(pairing_record, record_len, &pairingFile);
    if (err || !pairingFile) {
        if (error_message) *error_message = strdup("Registro de pairing inválido o corrupto.");
        if (err) idevice_error_free(err);
        return -3;
    }

    NSLog(@"[AirLift] Creando túnel RSD (tunnel_create_rppairing)...");
    void *adapter = NULL;
    void *handshake = NULL;
    // El registro se genera en nyxel_pairable_host_start con nombre 2424.
    // tunnel_create_rppairing debe recibir exactamente el mismo hostname.
    err = tunnel_create_rppairing((const struct sockaddr *)&address, addressLength, "2424",
                                  pairingFile, nyxel_pin_callback, (void *)"000000",
                                  &adapter, &handshake);
    rp_pairing_file_free(pairingFile);
    pairingFile = NULL;
    if (err) {
        NSString *detail = [NSString stringWithFormat:@"No se pudo abrir el túnel RSD (%@). Puede requerir re-emparejar.", nyxel_ffi_error_text(err)];
        if (error_message) *error_message = strdup(detail.UTF8String);
        idevice_error_free(err);
        return -4;
    }
    NSLog(@"[AirLift] Túnel RSD abierto. Conectando House Arrest...");

    int result = -99;
    HouseArrestClientHandle *houseArrest = NULL;
    AfcClientHandle *afc = NULL;
    AfcFileHandle *file = NULL;

    err = house_arrest_client_connect_rsd(adapter, handshake, &houseArrest);
    if (err) {
        if (error_message) *error_message = strdup("House Arrest no disponible por este túnel RSD en esta versión de iOS.");
        idevice_error_free(err);
        result = -5;
        goto cleanup;
    }
    NSLog(@"[AirLift] House Arrest conectado. Obteniendo contenedor %s...", bundle_id);

    err = house_arrest_vend_container(houseArrest, bundle_id, &afc);
    houseArrest = NULL;
    if (err) {
        if (error_message) *error_message = strdup("No se pudo acceder al contenedor de esa app.");
        idevice_error_free(err);
        result = -6;
        goto cleanup;
    }
    NSLog(@"[AirLift] Contenedor obtenido. Abriendo archivo %s...", normalizedPath);

    err = afc_file_open(afc, normalizedPath, write_mode ? NyxelAfcWrOnly : NyxelAfcRdOnly, &file);
    if (err) {
        if (error_message) *error_message = strdup("No se pudo abrir el archivo remoto.");
        idevice_error_free(err);
        result = -7;
        goto cleanup;
    }

    if (write_mode) {
        NSLog(@"[AirLift] Escribiendo %zu bytes...", in_len);
        err = afc_file_write(file, in_data, in_len);
        if (err) {
            if (error_message) *error_message = strdup("Falló la escritura remota.");
            idevice_error_free(err);
            result = -8;
            goto cleanup;
        }
    } else {
        NSLog(@"[AirLift] Leyendo archivo...");
        unsigned char *bytes = NULL;
        size_t length = 0;
        err = afc_file_read_entire(file, &bytes, &length);
        if (err) {
            if (error_message) *error_message = strdup("Falló la lectura remota.");
            idevice_error_free(err);
            result = -9;
            goto cleanup;
        }
        if (out_data) *out_data = bytes; else idevice_data_free(bytes, length);
        if (out_len) *out_len = length;
    }

    result = 0;
    NSLog(@"[AirLift] Operación completada OK");

cleanup:
    if (file) afc_file_close(file);
    if (afc) afc_client_free(afc);
    if (houseArrest) house_arrest_client_free(houseArrest);
    if (pairingFile) rp_pairing_file_free(pairingFile);
    if (adapter) adapter_free(adapter);
    if (handshake) rsd_handshake_free(handshake);
    return result;
}

void nyxel_free_data(unsigned char *data, size_t len) { idevice_data_free(data, len); }

#import "NixelAirLiftBridge.h"
#import "NixelIdeviceFFI.h"
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

static PairableHostHandle *nyxel_pairing_host_handle;
static NSNetService *nyxel_pairing_host_service;
static NSNetService *nyxel_airlift_probe_service;
static int nyxel_pairing_host_listener = -1;
static uint16_t nyxel_pairing_host_local_port;
static dispatch_source_t nyxel_pairing_host_source;
static void nyxel_pairing_post(NSString *name, NSDictionary *userInfo);
extern void nyxel_nw_listener_start(const char *service_name, uint16_t raw_port,
                                    const unsigned char *txt, size_t txt_len);
extern void nyxel_nw_listener_stop(void);

@interface NyxelPairingNetServiceDelegate : NSObject <NSNetServiceDelegate>
@end

@implementation NyxelPairingNetServiceDelegate
- (void)netServiceDidPublish:(NSNetService *)sender {
    nyxel_pairing_post(@"NyxelPairingHostReady", @{ @"name": sender.name ?: @"2424" });
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    (void)sender;
    NSString *message = [NSString stringWithFormat:@"Bonjour no pudo publicar el host PairableHost (%@).", errorDict ?: @{}];
    nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": message });
}
@end

static NyxelPairingNetServiceDelegate *nyxel_pairing_host_delegate;

static void nyxel_pairing_post(NSString *name, NSDictionary *userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:userInfo];
    });
}

static void nyxel_pairing_pin_callback(const char *pin, void *context) {
    (void)context;
    NSString *value = pin ? [NSString stringWithUTF8String:pin] : @"";
    nyxel_pairing_post(@"NyxelPairingPIN", @{ @"pin": value });
}

static void nyxel_pairing_accept_connection(int fd) {
    PairableHostHandle *handle = nyxel_pairing_host_handle;
    if (!handle) { close(fd); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void *pairing = NULL;
        void *peer = NULL;
        IdeviceFfiError *error = pairable_host_accept_fd(handle, fd, nyxel_pairing_pin_callback,
                                                         NULL, &peer, &pairing);
        close(fd);
        if (error || !pairing) {
            if (error) idevice_error_free(error);
            nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"El handshake PairableHost fue rechazado." });
            return;
        }
        unsigned char *bytes = NULL;
        size_t length = 0;
        IdeviceFfiError *serializeError = rp_pairing_file_to_bytes(pairing, &bytes, &length);
        if (serializeError || !bytes || length == 0) {
            if (serializeError) idevice_error_free(serializeError);
            rp_pairing_file_free(pairing);
            nyxel_pairing_post(@"NyxelPairingHostFailed", @{ @"message": @"No se pudo guardar el registro RPairing." });
            return;
        }
        NSData *record = [NSData dataWithBytes:bytes length:length];
        idevice_data_free(bytes, length);
        rp_pairing_file_free(pairing);
        nyxel_pairing_post(@"NyxelPairingCompleted", @{ @"record": record });
    });
}

void nyxel_pairable_host_accept_local_fd(int fd) {
    nyxel_pairing_accept_connection(fd);
}

uint16_t nyxel_pairable_host_local_port(void) {
    return nyxel_pairing_host_local_port;
}

int nyxel_pairable_host_start(const char *name, const char *model) {
    nyxel_pairable_host_stop();
    if (!name || !model) return -1;

    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return -2;
    int yes = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(0);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 4) != 0) {
        close(listener);
        return -3;
    }
    socklen_t addressLength = sizeof(address);
    if (getsockname(listener, (struct sockaddr *)&address, &addressLength) != 0) {
        close(listener);
        return -4;
    }

    char *serviceID = NULL;
    unsigned char *txt = NULL;
    size_t txtLength = 0;
    IdeviceFfiError *error = pairable_host_prepare(name, model, false, &nyxel_pairing_host_handle,
                                                     &serviceID, &txt, &txtLength, NULL);
    if (error || !serviceID || !txt || txtLength == 0) {
        if (error) idevice_error_free(error);
        if (serviceID) idevice_string_free(serviceID);
        if (txt) idevice_data_free(txt, txtLength);
        pairable_host_free(nyxel_pairing_host_handle);
        nyxel_pairing_host_handle = NULL;
        close(listener);
        return -5;
    }

    NSData *plistData = [NSData dataWithBytes:txt length:txtLength];
    idevice_data_free(txt, txtLength);
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:nil error:nil];
    NSMutableDictionary *records = [NSMutableDictionary dictionary];
    [plist enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
            records[key] = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
        }
    }];
    NSData *txtRecord = [NSNetService dataFromTXTRecordDictionary:records];
    // PairableHost uses the generated service identifier as the mDNS instance
    // name. The human-facing name is already carried by the TXT `name` record.
    NSString *serviceName = [NSString stringWithUTF8String:serviceID];
    idevice_string_free(serviceID);
    if (!serviceName || !txtRecord) {
        pairable_host_free(nyxel_pairing_host_handle);
        nyxel_pairing_host_handle = NULL;
        close(listener);
        return -6;
    }

    uint16_t publishedPort = ntohs(address.sin_port);
    if (publishedPort == 0) {
        pairable_host_free(nyxel_pairing_host_handle);
        nyxel_pairing_host_handle = NULL;
        close(listener);
        return -7;
    }
    nyxel_pairing_host_listener = listener;
    nyxel_pairing_host_local_port = publishedPort;
    nyxel_nw_listener_start([serviceName UTF8String], publishedPort,
                             txtRecord.bytes, txtRecord.length);

    nyxel_pairing_host_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)listener, 0,
                                                        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_event_handler(nyxel_pairing_host_source, ^{
        int fd = accept(nyxel_pairing_host_listener, NULL, NULL);
        if (fd >= 0) nyxel_pairing_accept_connection(fd);
    });
    dispatch_resume(nyxel_pairing_host_source);
    return 0;
}

void nyxel_pairable_host_stop(void) {
    nyxel_nw_listener_stop();
    if (nyxel_pairing_host_source) {
        dispatch_source_cancel(nyxel_pairing_host_source);
        nyxel_pairing_host_source = nil;
    }
    if (nyxel_pairing_host_service) {
        [nyxel_pairing_host_service removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        [nyxel_pairing_host_service stop];
        nyxel_pairing_host_service = nil;
    }
    if (nyxel_airlift_probe_service) {
        [nyxel_airlift_probe_service removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        [nyxel_airlift_probe_service stop];
        nyxel_airlift_probe_service = nil;
    }
    nyxel_pairing_host_delegate = nil;
    if (nyxel_pairing_host_listener >= 0) {
        close(nyxel_pairing_host_listener);
        nyxel_pairing_host_listener = -1;
    }
    nyxel_pairing_host_local_port = 0;
    if (nyxel_pairing_host_handle) {
        pairable_host_free(nyxel_pairing_host_handle);
        nyxel_pairing_host_handle = NULL;
    }
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

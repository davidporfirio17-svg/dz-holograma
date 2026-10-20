#import "DavizinMCM.h"
#import <dlfcn.h>
#import <stdlib.h>
#import <xpc/xpc.h>
#import <Security/Security.h>
#import <fcntl.h>

typedef void *(*MCMQueryCreate_t)(void);
typedef void  (*MCMQuerySetU64_t)(void *, uint64_t);
typedef void  (*MCMQuerySetXPC_t)(void *, xpc_object_t);
typedef void *(*MCMQueryGetSingle_t)(void *);
typedef void *(*MCMQueryGetError_t)(void *);
typedef void  (*MCMQueryFree_t)(void *);
typedef const char *(*MCMObjectGetPath_t)(void *);
typedef void *(*MCMObjectCopy_t)(void *);
typedef char *(*MCMObjectCopyToken_t)(void *);
typedef bool  (*MCMObjectActivate_t)(void *, bool);
typedef void  (*MCMObjectFree_t)(void *);
typedef int   (*MCMErrorGetPOSIX_t)(void *);
typedef const char *(*MCMErrorGetMessage_t)(void *);

typedef struct {
    void *handle;
    MCMQueryCreate_t    queryCreate;
    MCMQuerySetU64_t    querySetClass;
    MCMQuerySetXPC_t    querySetIdentifiers;
    MCMQuerySetU64_t    querySetFlags;
    MCMQueryGetSingle_t queryGetSingle;
    MCMQueryGetError_t  queryGetLastError;
    MCMQueryFree_t      queryFree;
    MCMObjectGetPath_t  objectGetPath;
    MCMObjectCopy_t     objectCopy;
    MCMObjectCopyToken_t objectCopyToken;
    MCMObjectActivate_t objectActivate;
    MCMObjectFree_t     objectFree;
    MCMErrorGetPOSIX_t  errorGetPOSIX;
    MCMErrorGetMessage_t errorGetMessage;
} MCMAPI;

static MCMAPI *MCMGetAPI(void) {
    static MCMAPI api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        api.handle = dlopen("/usr/lib/system/libsystem_containermanager.dylib",
                            RTLD_NOW | RTLD_LOCAL);
        void *h = api.handle ? api.handle : RTLD_DEFAULT;
#define LOAD(f, sym) api.f = (__typeof(api.f))dlsym(h, sym)
        LOAD(queryCreate,        "container_query_create");
        LOAD(querySetClass,      "container_query_set_class");
        LOAD(querySetIdentifiers,"container_query_set_identifiers");
        LOAD(querySetFlags,      "container_query_operation_set_flags");
        LOAD(queryGetSingle,     "container_query_get_single_result");
        LOAD(queryGetLastError,  "container_query_get_last_error");
        LOAD(queryFree,          "container_query_free");
        LOAD(objectGetPath,      "container_object_get_path");
        LOAD(objectCopy,         "container_object_copy");
        LOAD(objectCopyToken,    "container_copy_sandbox_token");
        LOAD(objectActivate,     "container_object_sandbox_extension_activate");
        LOAD(objectFree,         "container_object_free");
        LOAD(errorGetPOSIX,      "container_error_get_posix_errno");
        LOAD(errorGetMessage,    "container_error_get_message");
#undef LOAD
    });
    return &api;
}

static NSString *MCMSigningIdentifier(void) {
    static NSString *identifier;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        typedef CFTypeRef (*SecTaskCreateFromSelf_t)(CFAllocatorRef);
        typedef CFStringRef (*SecTaskCopySigningID_t)(CFTypeRef, CFErrorRef *);
        void *secFw = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
        SecTaskCreateFromSelf_t createSelf = (SecTaskCreateFromSelf_t)dlsym(secFw, "SecTaskCreateFromSelf");
        SecTaskCopySigningID_t  copyID     = (SecTaskCopySigningID_t)dlsym(secFw, "SecTaskCopySigningIdentifier");
        if (createSelf && copyID) {
            CFTypeRef task = createSelf(kCFAllocatorDefault);
            if (task) {
                CFErrorRef err = NULL;
                CFStringRef value = copyID(task, &err);
                if (value) identifier = [(__bridge NSString *)value copy];
                if (value) CFRelease(value);
                if (err)   CFRelease(err);
                CFRelease(task);
            }
        }
    });
    return identifier;
}

NSString *DavizinGetContainerPath(NSString *bundleID, NSString **outError) {
    static const NSString *kRequiredID = @"com.apple.mobile.MobileHouseArrest";
    static const uint64_t kFlags = 0x900000000ULL;
    static const uint64_t kClass = 2;

    NSString *signingID = MCMSigningIdentifier();
    if (![signingID isEqualToString:(NSString *)kRequiredID]) {
        if (outError) *outError = [NSString stringWithFormat:
            @"Signing ID: '%@'", signingID];
        return nil;
    }

    MCMAPI *api = MCMGetAPI();
    if (!api->queryCreate || !api->queryGetSingle || !api->objectGetPath) {
        if (outError) *outError = @"containermanager no disponible";
        return nil;
    }

    void *query = api->queryCreate();
    if (!query) {
        if (outError) *outError = @"query_create devolvió NULL";
        return nil;
    }

    api->querySetClass(query, kClass);
    xpc_object_t xpcID = xpc_string_create(bundleID.UTF8String);
    api->querySetIdentifiers(query, xpcID);
    api->querySetFlags(query, kFlags);

    void *object = api->queryGetSingle(query);
    if (!object) {
        void *qErr = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
        int posix = qErr && api->errorGetPOSIX ? api->errorGetPOSIX(qErr) : 0;
        const char *msg = qErr && api->errorGetMessage ? api->errorGetMessage(qErr) : NULL;
        if (outError) *outError = [NSString stringWithFormat:
            @"No encontrado '%@' posix=%d %s", bundleID, posix, msg ?: ""];
        api->queryFree(query);
        return nil;
    }

    const char *rawPath = api->objectGetPath(object);
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;

    if (path.length == 0 || !path.isAbsolutePath) {
        if (outError) *outError = @"Path inválido";
        api->queryFree(query);
        return nil;
    }

    if ([path isEqualToString:@"/var"] || [path hasPrefix:@"/var/"])
        path = [@"/private" stringByAppendingString:path];

    void *copy = api->objectCopy ? api->objectCopy(object) : NULL;
    if (copy) {
        char *token = api->objectCopyToken ? api->objectCopyToken(copy) : NULL;
        if (token && token[0] != '\0') api->objectActivate(copy, false);
        free(token);
        if (api->objectFree) api->objectFree(copy);
    }

    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        if (outError) *outError = [NSString stringWithFormat:
            @"Sin acceso errno=%d path=%@", errno, path];
        api->queryFree(query);
        return nil;
    }
    close(fd);

    api->queryFree(query);
    return path;
}

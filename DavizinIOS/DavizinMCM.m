#import "DavizinMCM.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <fcntl.h>

// Tipos XPC sin importar xpc/xpc.h
typedef void *xpc_obj_t;
typedef xpc_obj_t (*xpc_string_create_fn)(const char *);

// Tipos containermanager
typedef void *(*cm_query_create_fn)(void);
typedef void  (*cm_query_set_u64_fn)(void *, uint64_t);
typedef void  (*cm_query_set_xpc_fn)(void *, xpc_obj_t);
typedef void *(*cm_query_single_fn)(void *);
typedef void *(*cm_query_err_fn)(void *);
typedef void  (*cm_query_free_fn)(void *);
typedef const char *(*cm_path_fn)(void *);
typedef char *(*cm_token_fn)(void *);
typedef void  (*cm_free_fn)(void *);
typedef int   (*cm_posix_fn)(void *);
typedef const char *(*cm_msg_fn)(void *);
typedef int64_t (*sb_consume_fn)(const char *);

typedef struct {
    cm_query_create_fn  create;
    cm_query_set_u64_fn setClass;
    cm_query_set_xpc_fn setIds;
    cm_query_set_u64_fn setFlags;
    cm_query_single_fn  getSingle;
    cm_query_err_fn     getErr;
    cm_query_free_fn    freeQ;
    cm_path_fn          getPath;
    cm_token_fn         getToken;
    cm_free_fn          freeObj;
    cm_posix_fn         posix;
    cm_msg_fn           msg;
    xpc_string_create_fn xpcStr;
    sb_consume_fn        sbConsume;
} API;

static API *getAPI(void) {
    static API api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *cm = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW|RTLD_LOCAL);
        void *h  = cm ? cm : RTLD_DEFAULT;
        void *xh = dlopen("/usr/lib/system/libxpc.dylib", RTLD_NOW|RTLD_LOCAL);
        if (!xh) xh = RTLD_DEFAULT;
        void *sh = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW|RTLD_LOCAL);
        if (!sh) sh = RTLD_DEFAULT;

#define G(lib,field,sym) api.field = (__typeof(api.field))dlsym(lib,sym)
        G(h,  create,    "container_query_create");
        G(h,  setClass,  "container_query_set_class");
        G(h,  setIds,    "container_query_set_identifiers");
        G(h,  setFlags,  "container_query_operation_set_flags");
        G(h,  getSingle, "container_query_get_single_result");
        G(h,  getErr,    "container_query_get_last_error");
        G(h,  freeQ,     "container_query_free");
        G(h,  getPath,   "container_object_get_path");
        G(h,  getToken,  "container_copy_sandbox_token");
        G(h,  freeObj,   "container_object_free");
        G(h,  posix,     "container_error_get_posix_errno");
        G(h,  msg,       "container_error_get_message");
        G(xh, xpcStr,    "xpc_string_create");
        G(sh, sbConsume, "sandbox_extension_consume");
#undef G
    });
    return &api;
}

// Signing ID via dlsym
typedef void *(*SecTaskCreateFn)(void *);
typedef void *(*SecTaskCopyIDFn)(void *, void **);

static NSString *getSigningID(void) {
    static NSString *result;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SecTaskCreateFn cfn = (SecTaskCreateFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
        SecTaskCopyIDFn idfn = (SecTaskCopyIDFn)dlsym(RTLD_DEFAULT, "SecTaskCopySigningIdentifier");
        if (cfn && idfn) {
            void *task = cfn(NULL);
            if (task) {
                void *err = NULL;
                void *val = idfn(task, &err);
                if (val) { result = [(__bridge NSString *)val copy]; CFRelease(val); }
                CFRelease(task);
            }
        }
    });
    return result;
}

NSString *DavizinGetContainerPath(NSString *bundleID, NSString **outErr) {
    static const uint64_t kClass = 2;
    static const uint64_t kFlags = 0x900000000ULL;

    NSString *sid = getSigningID();
    if (![sid isEqualToString:@"com.apple.mobile.MobileHouseArrest"]) {
        if (outErr) *outErr = [NSString stringWithFormat:@"Signing ID: '%@'", sid];
        return nil;
    }

    API *api = getAPI();
    if (!api->create || !api->getSingle || !api->getPath) {
        if (outErr) *outErr = @"containermanager no disponible";
        return nil;
    }

    void *query = api->create();
    if (!query) { if (outErr) *outErr = @"query NULL"; return nil; }

    api->setClass(query, kClass);
    if (api->xpcStr) {
        xpc_obj_t xid = api->xpcStr(bundleID.UTF8String);
        if (xid) api->setIds(query, xid);
    }
    api->setFlags(query, kFlags);

    void *obj = api->getSingle(query);
    if (!obj) {
        int p = 0; const char *m = NULL;
        void *e = api->getErr ? api->getErr(query) : NULL;
        if (e) { if (api->posix) p = api->posix(e); if (api->msg) m = api->msg(e); }
        if (outErr) *outErr = [NSString stringWithFormat:@"No encontrado '%@' posix=%d %s", bundleID, p, m?:""];
        api->freeQ(query);
        return nil;
    }

    const char *raw = api->getPath(obj);
    NSString *path = raw ? @(raw) : nil;
    if (!path || !path.isAbsolutePath) {
        if (outErr) *outErr = @"Path inválido";
        api->freeQ(query);
        return nil;
    }

    if ([path hasPrefix:@"/var/"])
        path = [@"/private" stringByAppendingString:path];

    if (api->getToken) {
        char *tok = api->getToken(obj);
        if (tok && tok[0] && api->sbConsume) api->sbConsume(tok);
        if (tok) free(tok);
    }

    api->freeQ(query);
    return path;
}

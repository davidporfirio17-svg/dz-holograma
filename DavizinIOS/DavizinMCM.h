#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obtiene el path del container de datos de una app por bundle ID.
/// Requiere bundle ID + CodeDirectory = com.apple.mobile.MobileHouseArrest
/// Activa el sandbox extension para lectura/escritura.
NSString * _Nullable DavizinGetContainerPath(NSString *bundleID,
                                              NSString * _Nullable * _Nullable error);

/// Consume un sandbox extension para el path dado (no-op si ya fue consumido).
int64_t DavizinGrantContainerAccess(NSString *path);

/// Libera un sandbox extension previamente consumido.
void DavizinReleaseContainerGrant(int64_t handle);

NS_ASSUME_NONNULL_END

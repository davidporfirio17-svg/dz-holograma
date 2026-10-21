#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obtiene el path del container de datos de una app por bundle ID.
/// Requiere bundle ID + CodeDirectory = com.apple.mobile.MobileHouseArrest
/// Activa el sandbox extension para lectura/escritura.
NSString * _Nullable DavizinGetContainerPath(NSString *bundleID,
                                              NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END

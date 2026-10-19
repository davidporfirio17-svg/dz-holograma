#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Obtiene un grant ACTIVO para acceso al container.
/// Retorna handle >= 0 si exitoso. Handle debe ser liberado con DavizinReleaseContainerGrant().
/// En iOS < 26, retorna -1 (no es necesario grant).
/// El grant se mantiene activo desde el retorno hasta que se llame DavizinReleaseContainerGrant().
int64_t DavizinGrantContainerAccess(const char *containerPath);

/// Libera un grant previamente obtenido. No hace nada si handle < 0.
void DavizinReleaseContainerGrant(int64_t handle);

/// Obtiene el path del container de datos de una app por bundle ID.
/// Usa MCMActivateContainerPath con bad_query grant para acceso confiable.
NSString * _Nullable DavizinGetContainerPath(NSString *bundleID,
                                              NSString * _Nullable * _Nullable error);

/// Stub for backward compatibility
NSString * _Nullable DavizinPrepareInjectionQuery(NSString *bundleID,
                                                  NSString * _Nullable * _Nullable error);

/// Diagnóstico de la última llamada a DavizinGetContainerPath.
NSString * _Nullable DavizinMCMLastDiagnostic(void);

NS_ASSUME_NONNULL_END

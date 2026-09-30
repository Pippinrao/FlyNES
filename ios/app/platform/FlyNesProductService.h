#import <Foundation/Foundation.h>
@class FlyNesAppBridge, CatalogSourceService;
NS_ASSUME_NONNULL_BEGIN

typedef void (^FlyNesProductCompletion)(NSDictionary<NSString *, id> * _Nullable result,
                                      NSString * _Nullable errorCode);
/// Called on main; the host owns UIKit navigation and completes after return.
typedef void (^FlyNesProductPlatformHandler)(NSString *method, NSDictionary<NSString *, id> *arguments,
                                            FlyNesProductCompletion completion);
typedef void (^FlyNesProductEventHandler)(NSString *method, NSDictionary<NSString *, id> *event);

/// Native product projection owner. No Flutter/UI dependency and no second fly_app.
@interface FlyNesProductService : NSObject
- (instancetype)initWithBridge:(FlyNesAppBridge *)bridge
                        sources:(CatalogSourceService *)sources
                       defaults:(NSUserDefaults *)defaults
                         bundle:(NSBundle *)bundle
                  documentsRoot:(NSURL *)documentsRoot;
@property(nonatomic, copy, nullable) FlyNesProductPlatformHandler platformHandler;
@property(nonatomic, copy, nullable) FlyNesProductEventHandler eventHandler;
/// Main-thread host lease operation. Context includes route/purpose/returnToken.
- (NSDictionary<NSString *, id> *)activateContext:(NSDictionary<NSString *, id> *)context;
/// Main-thread native close: revoke the lease and pause UI events, preserving
/// all application owners and observation intent for the next activateContext.
- (void)deactivateContext;
- (void)handleMethod:(NSString *)method arguments:(NSDictionary<NSString *, id> *)arguments
           completion:(FlyNesProductCompletion)completion;
/// Notify after native gameplay/settings returns; does not destroy any owner.
- (void)invalidateDomains:(NSArray<NSString *> *)domains;
@end

/// Exact existing iOS single-slot identity. Shared by query and native playback.
FOUNDATION_EXPORT NSURL * _Nullable FlyNesLegacyAutosaveURL(NSURL *documentsRoot, NSString *canonicalID);
NS_ASSUME_NONNULL_END

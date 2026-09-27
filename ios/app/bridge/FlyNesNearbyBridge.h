#ifndef FLYNES_NEARBY_BRIDGE_H
#define FLYNES_NEARBY_BRIDGE_H

#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Process-scoped owner of the shared LAN MVP session. UI layers remain native;
/// protocol, role, lockstep, pause and lobby transitions stay in shared code.
@interface FlyNesNearbyBridge : NSObject

@property(class, nonatomic, readonly) FlyNesNearbyBridge *sharedInstance;
@property(nonatomic, readonly, copy) NSString *gameTitle;
@property(nonatomic, readonly, copy) NSString *canonicalId;
@property(nonatomic, readonly) NSTimeInterval sourceFrameDuration;

- (BOOL)startHost:(NSError * _Nullable * _Nullable)error;
- (BOOL)hasUsableIPv4;
- (BOOL)hasUsableWifiIPv4;
- (BOOL)joinInvite:(NSString *)invite error:(NSError * _Nullable * _Nullable)error;
- (BOOL)joinInviteOnWifi:(NSString *)invite error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)inviteText;
- (NSDictionary<NSString *, id> *)snapshot;
- (BOOL)selectHostGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                   title:(NSString *)title;
- (BOOL)selectGuestGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                    title:(NSString *)title;
- (BOOL)confirm;
- (BOOL)setPaused:(BOOL)paused;
- (BOOL)returnLobby;
- (BOOL)stepWithButtons:(uint32_t)buttons;
- (nullable NSData *)copyLatestRgb565Frame;
- (nullable NSData *)copyLatestRgb565FrameWithFrameIndex:(uint64_t * _Nullable)frameIndex;
- (NSData *)pullPCM;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

#endif

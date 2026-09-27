#import "FlyNesNearbyBridge.h"
#import "FlyNesAppBridge.h"
#include "NearbyLanAddressSelector.hpp"

#include <flynes/flynes_nearby_mvp.h>

#import <Security/Security.h>
#import <os/log.h>

#include <arpa/inet.h>
#include <cstring>
#include <ifaddrs.h>
#include <net/if.h>

namespace {
void nearby_diagnostic(void *, const char *line)
{
    // Shared diagnostics contain counters/states, never QR payloads or ROM bytes.
    os_log_info(OS_LOG_DEFAULT, "FlyNesNearby %{public}s", line);
}
NSError *nearby_error(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"FlyNesNearby" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *local_ipv4(bool wifi_only = false)
{
    struct ifaddrs *interfaces = nullptr;
    if (getifaddrs(&interfaces) != 0) return nil;
    std::vector<flynes::ios::NearbyLanCandidate> candidates;
    for (struct ifaddrs *item = interfaces; item != nullptr; item = item->ifa_next) {
        if (item->ifa_addr == nullptr || item->ifa_addr->sa_family != AF_INET) continue;
        char address[INET_ADDRSTRLEN]{};
        const auto *ipv4 = reinterpret_cast<const struct sockaddr_in *>(item->ifa_addr);
        if (inet_ntop(AF_INET, &ipv4->sin_addr, address, sizeof(address)) == nullptr) continue;
        candidates.push_back({item->ifa_name, address,
                              (item->ifa_flags & IFF_UP) != 0,
                              (item->ifa_flags & IFF_LOOPBACK) != 0});
    }
    freeifaddrs(interfaces);
    const auto selected = flynes::ios::select_lan_ipv4(candidates, wifi_only);
    return selected ? [NSString stringWithUTF8String:selected->c_str()] : nil;
}

}

@implementation FlyNesNearbyBridge {
    fly_lan_mvp_session *session_;
    NSString *_gameTitle;
    NSString *_canonicalId;
    uint64_t selectionGeneration_;
    uint64_t playbackGeneration_;
}

+ (instancetype)sharedInstance
{
    static FlyNesNearbyBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[FlyNesNearbyBridge alloc] init]; });
    return instance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _gameTitle = @"";
        _canonicalId = @"";
    }
    return self;
}

- (void)dealloc
{
    if (session_ != nullptr) fly_lan_mvp_destroy(session_);
}

- (NSString *)gameTitle { return _gameTitle; }
- (NSString *)canonicalId { return _canonicalId; }
- (uint64_t)playbackGeneration { return playbackGeneration_; }
- (NSTimeInterval)sourceFrameDuration
{
    fly_runtime_source_timing_v1 timing{};
    timing.struct_size = FLY_RUNTIME_SOURCE_TIMING_V1_SIZE;
    timing.version = FLY_RUNTIME_SOURCE_TIMING_VERSION_1;
    if (session_ == nullptr || fly_lan_mvp_source_timing(session_, &timing) != 1 ||
        timing.frame_rate_numerator == 0) return 1.0 / 60.0;
    return static_cast<double>(timing.frame_rate_denominator) / timing.frame_rate_numerator;
}

- (BOOL)replaceSession:(NSError **)error
{
    ++selectionGeneration_;
    ++playbackGeneration_;
    if (session_ != nullptr) fly_lan_mvp_destroy(session_);
    session_ = fly_lan_mvp_create();
    if (session_) fly_lan_mvp_set_diagnostic_sink(session_, nearby_diagnostic, nullptr);
    _gameTitle = @"";
    _canonicalId = @"";
    if (session_ != nullptr) return YES;
    if (error) *error = nearby_error(1, @"Nearby transport is unavailable");
    return NO;
}

- (BOOL)startHost:(NSError **)error
{
    NSString *address = local_ipv4();
    if (address.length == 0) {
        if (error) *error = nearby_error(2, @"No reachable IPv4 interface");
        return NO;
    }
    if (![self replaceSession:error]) return NO;
    uint8_t token[16]{};
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(token), token) != errSecSuccess) {
        if (error) *error = nearby_error(3, @"Secure random generation failed");
        [self cancel];
        return NO;
    }
    const BOOL started = fly_lan_mvp_host(session_, address.UTF8String, token) == 1;
    memset(token, 0, sizeof(token));
    if (!started) {
        if (error) *error = nearby_error(4, @"Nearby host could not start");
        [self cancel];
    }
    return started;
}

- (BOOL)hasUsableIPv4 { return local_ipv4().length != 0; }
- (BOOL)hasUsableWifiIPv4 { return local_ipv4(true).length != 0; }

- (BOOL)joinInvite:(NSString *)invite error:(NSError **)error
{
    return [self joinInvite:invite usingWifiOnly:NO error:error];
}

- (BOOL)joinInviteOnWifi:(NSString *)invite error:(NSError **)error
{
    return [self joinInvite:invite usingWifiOnly:YES error:error];
}

- (BOOL)joinInvite:(NSString *)invite usingWifiOnly:(BOOL)wifiOnly error:(NSError **)error
{
    NSString *address = local_ipv4(wifiOnly);
    NSData *utf8 = [invite dataUsingEncoding:NSUTF8StringEncoding];
    if (address.length == 0 || utf8.length == 0 || ![self replaceSession:error]) return NO;
    const BOOL started = fly_lan_mvp_join(session_, address.UTF8String,
        static_cast<const char *>(utf8.bytes), utf8.length) == 1;
    if (!started) {
        if (error) *error = nearby_error(5, @"Nearby invitation is invalid or unreachable");
        [self cancel];
    }
    return started;
}

- (NSString *)inviteText
{
    if (session_ == nullptr) return nil;
    const size_t size = fly_lan_mvp_copy_invite(session_, nullptr, 0);
    if (size == 0 || size > 256) return nil;
    char bytes[256]{};
    if (fly_lan_mvp_copy_invite(session_, bytes, sizeof(bytes)) != size) return nil;
    return [NSString stringWithUTF8String:bytes];
}

- (NSDictionary<NSString *, id> *)snapshot
{
    fly_lan_mvp_snapshot value{};
    if (session_ == nullptr || fly_lan_mvp_snapshot_read(session_, &value) != 1)
        return @{ @"state": @0, @"role": @0 };
    NSMutableString *peerConfigToken = [NSMutableString string];
    uint8_t peerConfigHash[32]{};
    if (fly_lan_mvp_copy_peer_config_hash_v1(session_, peerConfigHash)) {
        for (uint8_t byte : peerConfigHash) [peerConfigToken appendFormat:@"%02x", byte];
    }
    return @{ @"state": @(value.state), @"reason": @(value.reason), @"role": @(value.role),
              @"localConfigured": @(value.local_configured), @"peerConfigured": @(value.peer_configured),
              @"localReady": @(value.local_ready), @"peerReady": @(value.peer_ready),
              @"paused": @(value.paused), @"completedFrames": @(value.completed_frames),
              @"peerGameKey": [NSString stringWithUTF8String:value.peer_game_key] ?: @"",
              @"peerConfigToken": peerConfigToken };
}

- (BOOL)confirm { return session_ != nullptr && fly_lan_mvp_confirm(session_) == 1; }
- (BOOL)setPaused:(BOOL)paused { return session_ != nullptr && fly_lan_mvp_set_paused(session_, paused) == 1; }
- (BOOL)resumeGame { return session_ != nullptr && fly_lan_mvp_resume_game(session_) == 1; }
- (BOOL)returnLobby
{
    if (session_ == nullptr || fly_lan_mvp_return_lobby(session_) != 1) return NO;
    _gameTitle = @"";
    _canonicalId = @"";
    return YES;
}

- (BOOL)selectHostGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                   title:(NSString *)title
{
    // Immediate initial selection only; UI game changes use the asynchronous API.
    NSString *gameKey = [FlyNesAppBridge.sharedInstance nearbyGameKeyForCanonicalID:canonicalID];
    if (session_ == nullptr || rom.length == 0 || canonicalID.length == 0 ||
        fly_lan_mvp_select_game(session_, static_cast<const uint8_t *>(rom.bytes),
                                rom.length, gameKey.UTF8String) != 1 ||
        fly_lan_mvp_confirm(session_) != 1) return NO;
    _canonicalId = [canonicalID copy];
    _gameTitle = [title copy];
    ++playbackGeneration_;
    return YES;
}

- (void)selectHostGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                   title:(NSString *)title completion:(void (^)(BOOL))completion
{
    NSAssert(NSThread.isMainThread, @"Nearby UI selection must run on the main thread");
    const uint64_t generation = ++selectionGeneration_;
    dispatch_async(dispatch_get_main_queue(), ^{
        fly_lan_mvp_snapshot state{};
        if (generation != self->selectionGeneration_ || !self->session_ ||
            !fly_lan_mvp_snapshot_read(self->session_, &state) ||
            state.role != FLY_LAN_MVP_ROLE_HOST_P1 || rom.length == 0 || canonicalID.length == 0) {
            completion(NO);
            return;
        }
        if (state.state == FLY_LAN_MVP_RUNNING || state.state == FLY_LAN_MVP_CONFIGURING) {
            if (!fly_lan_mvp_return_lobby(self->session_)) { completion(NO); return; }
        }
        [self finishSelection:rom canonicalID:canonicalID title:title generation:generation
                     deadline:NSProcessInfo.processInfo.systemUptime + 3.0 completion:completion];
    });
}

- (void)finishSelection:(NSData *)rom canonicalID:(NSString *)canonicalID title:(NSString *)title
             generation:(uint64_t)generation deadline:(NSTimeInterval)deadline
             completion:(void (^)(BOOL))completion
{
    fly_lan_mvp_snapshot state{};
    if (generation != selectionGeneration_ || !session_ ||
        !fly_lan_mvp_snapshot_read(session_, &state)) { completion(NO); return; }
    if (state.state == FLY_LAN_MVP_RETURNING && NSProcessInfo.processInfo.systemUptime < deadline) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self finishSelection:rom canonicalID:canonicalID title:title generation:generation
                         deadline:deadline completion:completion];
        });
        return;
    }
    completion(state.state == FLY_LAN_MVP_LOBBY &&
               [self selectHostGameROM:rom canonicalID:canonicalID title:title]);
}

- (BOOL)selectGuestGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                    title:(NSString *)title
{
    if (session_ == nullptr || rom.length == 0 || canonicalID.length == 0) return NO;
    fly_lan_mvp_snapshot state{};
    NSString *gameKey = [FlyNesAppBridge.sharedInstance nearbyGameKeyForCanonicalID:canonicalID];
    if (fly_lan_mvp_snapshot_read(session_, &state) != 1 ||
        state.role != FLY_LAN_MVP_ROLE_GUEST_P2 ||
        (![canonicalID isEqualToString:[NSString stringWithUTF8String:state.peer_game_key]] &&
         ![gameKey isEqualToString:[NSString stringWithUTF8String:state.peer_game_key]]) ||
        fly_lan_mvp_select_rom(session_, static_cast<const uint8_t *>(rom.bytes),
                               rom.length) != 1 || fly_lan_mvp_confirm(session_) != 1) return NO;
    _canonicalId = [canonicalID copy];
    _gameTitle = [title copy];
    ++playbackGeneration_;
    return YES;
}
- (BOOL)stepWithButtons:(uint32_t)buttons { return session_ != nullptr && fly_lan_mvp_submit_input(session_, buttons) == 1; }

- (NSData *)copyLatestRgb565Frame
{
    return [self copyLatestRgb565FrameWithFrameIndex:nullptr];
}

- (NSData *)copyLatestRgb565FrameWithFrameIndex:(uint64_t * _Nullable)frameIndex
{
    if (session_ == nullptr) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:FLY_RUNTIME_RGB565_BYTES];
    fly_latest_frame_v1 meta{};
    meta.struct_size = FLY_LATEST_FRAME_V1_SIZE;
    meta.version = FLY_LATEST_FRAME_VERSION_1;
    if (fly_lan_mvp_copy_latest_frame(session_, data.mutableBytes, data.length, &meta) != 1)
        return nil;
    if (frameIndex != nullptr) *frameIndex = meta.frame_index;
    return data;
}

- (NSData *)pullPCM
{
    if (session_ == nullptr) return [NSData data];
    int16_t samples[4096]{};
    fly_pcm_block_v1 block{};
    block.struct_size = FLY_PCM_BLOCK_V1_SIZE;
    block.version = FLY_PCM_BLOCK_VERSION_1;
    if (fly_lan_mvp_pull_pcm(session_, samples, 4096, &block) != 1) return [NSData data];
    return [NSData dataWithBytes:samples length:block.sample_count * sizeof(int16_t)];
}

- (void)cancel
{
    ++selectionGeneration_;
    ++playbackGeneration_;
    if (session_ != nullptr) { fly_lan_mvp_destroy(session_); session_ = nullptr; }
    _gameTitle = @"";
    _canonicalId = @"";
}

@end

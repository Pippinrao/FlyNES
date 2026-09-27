#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if FLYNES_UI_TEST_PEER && TARGET_OS_SIMULATOR
#import "FlyNesNearbyBridge.h"
#import "FlyNesCoverStore.h"
#import <Security/Security.h>
#include <flynes/flynes_nearby_mvp.h>
#include <cstring>

/// Explicitly opted-in UI fixture: a real native peer, never fabricated UI state.
@interface NearbyUITestPeer : NSObject
@end

@implementation NearbyUITestPeer {
    fly_lan_mvp_session *peer_;
    NSTimer *timer_;
    NSArray<NSDictionary *> *games_;
    NSString *fixtureRoot_;
    NSString *role_;
    NSString *error_;
    NSString *lastCommand_;
    NSInteger pendingGame_;
    NSUInteger ticks_;
    BOOL joined_;
    BOOL peerHosting_;
    BOOL cleaned_;
}

+ (void)load {
    NSString *role = NSProcessInfo.processInfo.environment[@"FLYNES_UI_NEARBY_ROLE"];
    if (![role isEqual:@"host"] && ![role isEqual:@"guest"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static NearbyUITestPeer *fixture;
        fixture = [NearbyUITestPeer new];
        [fixture start:role];
    });
}

- (NSString *)path:(NSString *)name {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)start:(NSString *)role {
    role_ = role;
    pendingGame_ = -1;
    NSString *identifier = NSProcessInfo.processInfo.environment[@"FLYNES_UI_NEARBY_FIXTURE_ID"];
    if (!identifier.length || ![[NSUUID alloc] initWithUUIDString:identifier]) {
        error_ = @"A unique fixture UUID is required";
        [self publish];
        return;
    }
    fixtureRoot_ = [self path:[@"flynes-nearby-ui-" stringByAppendingString:identifier]];
    [self ensureCoverDirectory];
    [NSFileManager.defaultManager removeItemAtPath:[self path:@"nearby-ui-command.plist"] error:nil];
    NSData *manifest = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"builtin-games" withExtension:@"json"]];
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil];
    NSMutableArray *supported = [NSMutableArray array];
    for (NSDictionary *game in root[@"games"]) {
        if ([game[@"multiplayerProfile"][@"eligibility"] isEqual:@"SUPPORTED"] &&
            [game[@"multiplayerProfile"][@"maxPlayers"] integerValue] >= 2) [supported addObject:game];
    }
    games_ = supported;
    if (games_.count < 2) error_ = @"Two manifest-supported games are required";
    peer_ = fly_lan_mvp_create();
    if (!peer_) error_ = @"Native peer creation failed";
    NSError *error = nil;
    if (![FlyNesNearbyBridge.sharedInstance startHost:&error]) error_ = @"App host preparation failed";
    timer_ = [NSTimer timerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer_ forMode:NSRunLoopCommonModes];
}

- (NSString *)key:(NSDictionary *)game {
    return [@"game:" stringByAppendingString:[game[@"romSha256"] uppercaseString]];
}

- (NSData *)rom:(NSDictionary *)game {
    NSString *asset = [game[@"assetFilename"] stringByDeletingPathExtension];
    return [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:asset ofType:@"nes"]];
}

- (void)connect {
    FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
    if (peerHosting_) {
        char qr[512]{};
        if (!fly_lan_mvp_copy_invite(peer_, qr, sizeof(qr))) return;
        NSError *error = nil;
        if (![bridge joinInvite:@(qr) error:&error]) error_ = @"App guest join failed";
        joined_ = YES;
        return;
    }
    NSString *invite = bridge.inviteText;
    if (!invite.length) return;
    NSString *address = [invite componentsSeparatedByString:@":"][1];
    if ([role_ isEqual:@"host"]) {
        if (fly_lan_mvp_join(peer_, address.UTF8String, invite.UTF8String,
                             [invite lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) != 1)
            error_ = @"Native guest join failed";
    } else {
        [bridge cancel];
        uint8_t token[16]{};
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(token), token) != errSecSuccess ||
            fly_lan_mvp_host(peer_, address.UTF8String, token) != 1) {
            error_ = @"Native host startup failed";
        } else { peerHosting_ = YES; }
        memset(token, 0, sizeof(token));
        return;
    }
    joined_ = YES;
}

- (void)selectGame:(NSDictionary *)game {
    NSData *rom = [self rom:game];
    if (!rom.length || fly_lan_mvp_select_game(peer_, static_cast<const uint8_t *>(rom.bytes),
            rom.length, [self key:game].UTF8String) != 1 || fly_lan_mvp_confirm(peer_) != 1)
        error_ = @"Native peer ROM selection failed";
}

- (void)captureCurrentCover {
    FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
    NSString *key = bridge.canonicalId;
    if (!key.length) return;
    [self ensureCoverDirectory];
    FlyNesCoverStore *store = FlyNesCoverStore.sharedInstance;
    if ([store hasCoverForCanonicalId:key]) return;
    NSData *pixels = [bridge copyLatestRgb565Frame];
    if (pixels.length != FLY_RUNTIME_RGB565_BYTES) return;
    // The real store writes only into this run's temporary fixture directory.
    if (![store storeRgb565Frame:pixels canonicalId:key width:256 height:240])
        error_ = @"Could not capture the real game frame";
}

- (void)ensureCoverDirectory {
    if (!fixtureRoot_.length) return;
    FlyNesCoverStore *store = FlyNesCoverStore.sharedInstance;
    NSString *expected = [fixtureRoot_ stringByAppendingPathComponent:@"covers/v1"];
    if (![store.directory isEqual:expected]) [store configureWithCacheRoot:fixtureRoot_];
}

- (void)cleanup {
    [FlyNesNearbyBridge.sharedInstance cancel];
    if (peer_) { fly_lan_mvp_destroy(peer_); peer_ = nullptr; }
    NSString *resolved = fixtureRoot_.stringByResolvingSymlinksInPath;
    NSString *temporary = NSTemporaryDirectory().stringByResolvingSymlinksInPath;
    if ([resolved.stringByDeletingLastPathComponent isEqual:temporary] &&
        [resolved.lastPathComponent hasPrefix:@"flynes-nearby-ui-"])
        [NSFileManager.defaultManager removeItemAtPath:resolved error:nil];
    cleaned_ = YES;
    [timer_ invalidate];
    [self publish];
}

- (void)command {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:[self path:@"nearby-ui-command.plist"]];
    NSString *identifier = request[@"id"];
    if (!identifier.length || [identifier isEqual:lastCommand_]) return;
    lastCommand_ = identifier;
    [self ensureCoverDirectory];
    NSString *action = request[@"action"];
    if ([action isEqual:@"cleanup"]) { [self cleanup]; return; }
    if ([action isEqual:@"pause"]) fly_lan_mvp_set_paused(peer_, 1);
    if ([action isEqual:@"resume"]) fly_lan_mvp_resume_game(peer_);
    if ([action isEqual:@"select-first"]) pendingGame_ = 0;
    if ([action isEqual:@"change-game"]) {
        pendingGame_ = 1;
        if (!fly_lan_mvp_return_lobby(peer_)) error_ = @"Native host return-to-lobby failed";
    }
    if ([action isEqual:@"capture-cover"]) [self captureCurrentCover];
}

- (void)publish {
    fly_lan_mvp_snapshot peer{};
    if (peer_) fly_lan_mvp_snapshot_read(peer_, &peer);
    FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
    NSMutableArray *games = [NSMutableArray array];
    for (NSDictionary *game in games_)
        [games addObject:@{@"key": [self key:game], @"title": game[@"titleEn"]}];
    NSDictionary *status = @{@"app": bridge.snapshot, @"peerState": @(peer.state),
        @"fixtureID": NSProcessInfo.processInfo.environment[@"FLYNES_UI_NEARBY_FIXTURE_ID"] ?: @"",
        @"peerFrames": @(peer.completed_frames), @"peerPaused": @(peer.paused),
        @"title": bridge.gameTitle, @"key": bridge.canonicalId,
        @"playbackGeneration": @(bridge.playbackGeneration),
        @"coverDirectory": FlyNesCoverStore.sharedInstance.directory,
        @"error": error_ ?: @"", @"games": games, @"command": lastCommand_ ?: @"",
        @"cleaned": @(cleaned_)};
    [status writeToFile:[self path:@"nearby-ui-state.plist"] atomically:YES];
}

- (void)tick {
    [self ensureCoverDirectory];
    if (!error_ && !joined_) [self connect];
    if ((ticks_++ % 6) == 0) {
        [self command];
        if (cleaned_) return;
    }
    if (peer_ && !error_) {
        fly_lan_mvp_snapshot state{};
        fly_lan_mvp_snapshot_read(peer_, &state);
        if ([role_ isEqual:@"guest"] && pendingGame_ >= 0 && state.state == FLY_LAN_MVP_LOBBY) {
            [self selectGame:games_[pendingGame_]];
            pendingGame_ = -1;
        } else if ([role_ isEqual:@"host"] && state.state == FLY_LAN_MVP_CONFIGURING &&
                   !state.local_configured && state.peer_game_key[0]) {
            NSString *key = @(state.peer_game_key);
            for (NSDictionary *game in games_)
                if ([[self key:game] isEqual:key]) { [self selectGame:game]; break; }
        }
        if (state.state == FLY_LAN_MVP_RUNNING && !state.paused)
            fly_lan_mvp_submit_input(peer_, 0);
    }
    if ((ticks_ % 6) == 0) [self publish];
}
@end
#endif

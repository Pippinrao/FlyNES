#import <XCTest/XCTest.h>

#import "FlyNesNearbyBridge.h"
#import "BuiltinGames.h"
#import "../app/run/RunSurfaceViewController.h"
#include <flynes/flynes_nearby_mvp.h>
#include "NearbyPlaybackState.hpp"

#include <vector>
#include <map>

// Declaration lets the regression fail at its assertion before the API is added.
@interface FlyNesNearbyBridge (AsyncSelectionContract)
- (void)selectHostGameROM:(NSData *)rom canonicalID:(NSString *)canonicalID
                   title:(NSString *)title completion:(void (^)(BOOL))completion;
@end

@interface RunSurfaceViewController (NearbyDrawerContract)
- (void)openPauseDrawer;
- (void)resumeFromPause;
- (void)applicationWillResignActive:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
@end

static UIView *viewWithId(UIView *root, NSString *identifier)
{
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = viewWithId(child, identifier);
        if (found) return found;
    }
    return nil;
}

@interface NearbyMvpBridgeTests : XCTestCase
@end

@implementation NearbyMvpBridgeTests

- (void)testSelectionCompletesAsynchronouslyAndRejectsCancelledRequest
{
    FlyNesNearbyBridge *host = FlyNesNearbyBridge.sharedInstance;
    SEL selector = @selector(selectHostGameROM:canonicalID:title:completion:);
    XCTAssertTrue([host respondsToSelector:selector], @"Changing games must not synchronously wait on the UI thread");
    if (![host respondsToSelector:selector]) return;
    [host cancel];
    NSError *error = nil;
    XCTAssertTrue([host startHost:&error], @"%@", error);
    XCTestExpectation *completed = [self expectationWithDescription:@"cancelled selection completes"];
    __block BOOL returned = NO;
    [host selectHostGameROM:[NSData dataWithBytes:"invalid" length:7]
               canonicalID:@"test:cancelled" title:@"Cancelled" completion:^(BOOL selected) {
        XCTAssertTrue(returned, @"Selection must yield the main run loop");
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertFalse(selected);
        XCTAssertEqualObjects(host.canonicalId, @"");
        [completed fulfill];
    }];
    returned = YES;
    [host cancel];
    XCTAssertTrue([host startHost:&error], @"%@", error);
    [self waitForExpectations:@[completed] timeout:4];
    XCTAssertEqualObjects(host.canonicalId, @"");
    [host cancel];
}

- (void)testPeerPauseHoldsPlaybackWithoutLeavingTheSession
{
    using flynes::ios::NearbyPlaybackAction;
    using flynes::ios::nearbyPlaybackAction;
    XCTAssertEqual(nearbyPlaybackAction(FLY_LAN_MVP_RUNNING, true), NearbyPlaybackAction::Hold);
    XCTAssertEqual(nearbyPlaybackAction(FLY_LAN_MVP_RUNNING, false), NearbyPlaybackAction::Submit);
    XCTAssertEqual(nearbyPlaybackAction(FLY_LAN_MVP_RETURNING, false), NearbyPlaybackAction::Exit);
    XCTAssertEqual(nearbyPlaybackAction(FLY_LAN_MVP_ENDED, false), NearbyPlaybackAction::Exit);
    XCTAssertEqual(nearbyPlaybackAction(FLY_LAN_MVP_LOBBY, false), NearbyPlaybackAction::Exit);
}

- (void)testHostPublishesSharedInviteAsPlayerOne
{
    FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
    [bridge cancel];
    NSError *error = nil;
    XCTAssertTrue([bridge startHost:&error], @"%@", error);
    NSString *invite = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
    do {
        invite = bridge.inviteText;
        if (invite.length == 0) [NSThread sleepForTimeInterval:0.02];
    } while (invite.length == 0 && [deadline timeIntervalSinceNow] > 0);
    XCTAssertTrue([invite hasPrefix:@"flynes-lan-v1:"]);
    XCTAssertEqual([bridge.snapshot[@"role"] unsignedIntegerValue], 1u);
    [bridge cancel];
}

- (void)testRealSimulatorSessionPublishesIdenticalPicturesAndPcm
{
    FlyNesNearbyBridge *host = FlyNesNearbyBridge.sharedInstance;
    [host cancel];
    NSError *error = nil;
    XCTAssertTrue([host startHost:&error], @"%@", error);
    NSString *invite = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
    while (invite.length == 0 && deadline.timeIntervalSinceNow > 0) {
        invite = host.inviteText;
        [NSThread sleepForTimeInterval:0.01];
    }
    XCTAssertNotNil(invite);
    fly_lan_mvp_session *guest = fly_lan_mvp_create();
    XCTAssertNotEqual(guest, nullptr);
    @try {
        NSArray<NSString *> *parts = [invite componentsSeparatedByString:@":"];
        XCTAssertGreaterThan(parts.count, 2u);
        XCTAssertEqual(fly_lan_mvp_join(guest, parts[1].UTF8String,
                                       invite.UTF8String, invite.length), 1);
        fly_lan_mvp_snapshot guest_state{};
        deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
        while (deadline.timeIntervalSinceNow > 0) {
            fly_lan_mvp_snapshot_read(guest, &guest_state);
            if ([host.snapshot[@"state"] unsignedIntegerValue] == FLY_LAN_MVP_LOBBY &&
                guest_state.state == FLY_LAN_MVP_LOBBY) break;
            [NSThread sleepForTimeInterval:0.01];
        }
        XCTAssertEqual(guest_state.state, FLY_LAN_MVP_LOBBY);
        XCTAssertEqual([host.snapshot[@"localConfigured"] intValue], 0);
        XCTAssertEqual(guest_state.local_configured, 0u);
        XCTAssertEqualObjects(host.gameTitle, @"");
        FlyNesBuiltinGame *game = nil;
        for (FlyNesBuiltinGame *candidate in FlyNesBuiltinGames.shared.all) {
            if ([candidate.multiplayerEligibility isEqualToString:@"SUPPORTED"] &&
                candidate.multiplayerMaxPlayers == 2) { game = candidate; break; }
        }
        XCTAssertNotNil(game);
        NSString *path = [NSBundle.mainBundle pathForResource:
            [FlyNesBuiltinGames resourceNameForAssetFilename:game.assetFilename] ofType:@"nes"];
        NSData *rom = [NSData dataWithContentsOfFile:path];
        XCTAssertGreaterThan(rom.length, 0u);
        XCTAssertTrue([host selectHostGameROM:rom canonicalID:game.canonicalId title:game.titleEn]);
        XCTAssertEqual([host.snapshot[@"localReady"] intValue], 1);
        XCTAssertEqual(fly_lan_mvp_select_rom(guest,
            static_cast<const uint8_t *>(rom.bytes), rom.length), 1);
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([host.snapshot[@"peerConfigToken"] length] == 0 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        XCTAssertEqual([host.snapshot[@"peerConfigToken"] length], 64u);
        XCTAssertEqual(fly_lan_mvp_confirm(guest), 1);
        deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
        while (deadline.timeIntervalSinceNow > 0) {
            fly_lan_mvp_snapshot_read(guest, &guest_state);
            if ([host.snapshot[@"state"] unsignedIntegerValue] == FLY_LAN_MVP_RUNNING &&
                guest_state.state == FLY_LAN_MVP_RUNNING) break;
            [NSThread sleepForTimeInterval:0.01];
        }
        XCTAssertEqual(guest_state.state, FLY_LAN_MVP_RUNNING);
        RunSurfaceViewController *surface = [[RunSurfaceViewController alloc] init];
        surface.nearbySession = YES;
        surface.canonicalId = game.canonicalId;
        surface.gameTitle = game.titleEn;
        [surface loadViewIfNeeded];
        XCTAssertNil(viewWithId(surface.view, @"nearby_status_banner"), @"Retired recovery placeholders must not obscure gameplay");
        [surface openPauseDrawer];
        XCTAssertNotNil(viewWithId(surface.view, @"resume"));
        XCTAssertNotNil(viewWithId(surface.view, @"game_center"));
        XCTAssertNil(viewWithId(surface.view, @"settings"), @"Nearby settings command has no supported destination");
        [surface resumeFromPause];
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([host.snapshot[@"paused"] boolValue] && deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        for (uint64_t frame = 0; frame < 20; ++frame) {
            deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
            while (![host stepWithButtons:frame == 0 ? 1u : 0u] &&
                   deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.002];
            XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 0.0);
            XCTAssertEqual(fly_lan_mvp_submit_input(guest, frame == 0 ? 0x80u : 0u), 1);
            while (deadline.timeIntervalSinceNow > 0) {
                fly_lan_mvp_snapshot_read(guest, &guest_state);
                if ([host.snapshot[@"completedFrames"] unsignedLongLongValue] > frame &&
                    guest_state.completed_frames > frame) break;
                [NSThread sleepForTimeInterval:0.002];
            }
            XCTAssertGreaterThan(guest_state.completed_frames, frame);
        }
        // Prediction can leave the peers at different latest frames. Drive both forward
        // and compare atomically copied pictures only when their simulation index matches.
        NSData *host_pixels = nil;
        std::vector<uint8_t> guest_pixels(FLY_RUNTIME_RGB565_BYTES);
        fly_latest_frame_v1 meta{};
        meta.struct_size = FLY_LATEST_FRAME_V1_SIZE;
        meta.version = FLY_LATEST_FRAME_VERSION_1;
        uint64_t hostFrame = 0;
        std::map<uint64_t, std::vector<uint8_t>> hostHistory;
        std::map<uint64_t, std::vector<uint8_t>> guestHistory;
        BOOL matched = NO;
        deadline = [NSDate dateWithTimeIntervalSinceNow:4.0];
        while (deadline.timeIntervalSinceNow > 0) {
            [host stepWithButtons:0];
            fly_lan_mvp_submit_input(guest, 0);
            host_pixels = [host copyLatestRgb565FrameWithFrameIndex:&hostFrame];
            if (host_pixels.length == FLY_RUNTIME_RGB565_BYTES && hostFrame >= 20)
                hostHistory[hostFrame] = std::vector<uint8_t>(
                    static_cast<const uint8_t *>(host_pixels.bytes),
                    static_cast<const uint8_t *>(host_pixels.bytes) + host_pixels.length);
            if (fly_lan_mvp_copy_latest_frame(guest, guest_pixels.data(),
                    guest_pixels.size(), &meta) == 1 && meta.frame_index >= 20)
                guestHistory[meta.frame_index] = guest_pixels;
            const auto guestAtHost = guestHistory.find(hostFrame);
            const auto hostAtGuest = hostHistory.find(meta.frame_index);
            if ((hostFrame >= 20 && guestAtHost != guestHistory.end() &&
                 hostHistory[hostFrame] == guestAtHost->second) ||
                (meta.frame_index >= 20 && hostAtGuest != hostHistory.end() &&
                 hostAtGuest->second == guestHistory[meta.frame_index])) {
                matched = YES;
                break;
            }
            if (hostHistory.size() > 64) hostHistory.erase(hostHistory.begin());
            if (guestHistory.size() > 64) guestHistory.erase(guestHistory.begin());
            [NSThread sleepForTimeInterval:0.008];
        }
        XCTAssertTrue(matched, @"peer pictures never matched at one simulation frame (host=%llu guest=%llu)",
                      hostFrame, meta.frame_index);
        XCTAssertGreaterThan(host.pullPCM.length, 0u);
        XCTAssertEqual(fly_lan_mvp_set_paused(guest, 1), 1);
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (![host.snapshot[@"paused"] boolValue] && deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        XCTAssertTrue([host.snapshot[@"paused"] boolValue]);
        XCTAssertEqual([host.snapshot[@"state"] unsignedIntegerValue], FLY_LAN_MVP_RUNNING);
        const uint64_t beforePause = [host.snapshot[@"completedFrames"] unsignedLongLongValue];
        XCTAssertFalse([host stepWithButtons:0]);
        XCTAssertEqual([host.snapshot[@"completedFrames"] unsignedLongLongValue], beforePause);
        XCTAssertTrue([host resumeGame], @"Host Continue releases the guest's room pause");
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([host.snapshot[@"paused"] boolValue] && deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        XCTAssertFalse([host.snapshot[@"paused"] boolValue]);
        XCTAssertTrue([host stepWithButtons:0]);
        XCTAssertEqual(fly_lan_mvp_submit_input(guest, 0), 1);
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([host.snapshot[@"completedFrames"] unsignedLongLongValue] <= beforePause &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        XCTAssertGreaterThan([host.snapshot[@"completedFrames"] unsignedLongLongValue], beforePause);
        // Continue received while inactive must reconcile on becoming active,
        // even if the SwiftUI paused edge notification was already consumed.
        [surface viewDidAppear:NO];
        [surface openPauseDrawer];
        [surface applicationWillResignActive:nil];
        XCTAssertEqual(fly_lan_mvp_resume_game(guest), 1);
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([host.snapshot[@"paused"] boolValue] && deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.002];
        [surface applicationDidBecomeActive:nil];
        XCTAssertNil(viewWithId(surface.view, @"resume"), @"Foreground must reconcile remote Continue after a missed notification");

        // Remote game transitions must leave the old drawer even with its
        // display link stopped. A native return creates the same shared state.
        [surface openPauseDrawer];
        XCTestExpectation *left = [self expectationWithDescription:@"old game surface left"];
        __block BOOL didLeave = NO;
        surface.onPauseCommand = ^(NSString *command) {
            if (!didLeave) { didLeave = YES; [left fulfill]; }
        };
        XCTAssertTrue([host returnLobby]);
        [self waitForExpectations:@[left] timeout:3];
        [surface viewWillDisappear:NO];

        if ([host respondsToSelector:@selector(selectHostGameROM:canonicalID:title:completion:)]) {
            XCTestExpectation *changed = [self expectationWithDescription:@"same connection selects again"];
            [host selectHostGameROM:rom canonicalID:game.canonicalId title:game.titleEn completion:^(BOOL selected) {
                XCTAssertTrue(selected);
                [changed fulfill];
            }];
            [self waitForExpectations:@[changed] timeout:4];
            XCTAssertEqual(fly_lan_mvp_select_rom(guest, static_cast<const uint8_t *>(rom.bytes), rom.length), 1);
            XCTAssertEqual(fly_lan_mvp_confirm(guest), 1);
            deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
            while ([host.snapshot[@"state"] intValue] != FLY_LAN_MVP_RUNNING && deadline.timeIntervalSinceNow > 0)
                [NSThread sleepForTimeInterval:0.002];
            [surface viewWillDisappear:NO];
            XCTAssertFalse([host.snapshot[@"paused"] boolValue], @"An old surface cannot pause a new game, even for the same ROM");
            RunSurfaceViewController *returningSurface = [[RunSurfaceViewController alloc] init];
            returningSurface.nearbySession = YES;
            returningSurface.canonicalId = game.canonicalId;
            returningSurface.gameTitle = game.titleEn;
            [returningSurface loadViewIfNeeded];
            [returningSurface viewDidAppear:NO];
            [returningSurface openPauseDrawer];
            returningSurface.onPauseCommand = ^(NSString *command) {
                if ([command isEqual:@"game_center"]) [host setPaused:YES];
            };
            [(UIButton *)viewWithId(returningSurface.view, @"game_center") sendActionsForControlEvents:UIControlEventTouchUpInside];
            XCTAssertEqual(fly_lan_mvp_resume_game(guest), 1);
            deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
            while ([host.snapshot[@"paused"] boolValue] && deadline.timeIntervalSinceNow > 0)
                [NSThread sleepForTimeInterval:0.002];
            [returningSurface viewWillDisappear:NO];
            XCTAssertFalse([host.snapshot[@"paused"] boolValue], @"Late Room disappearance must not override the peer's newer Continue");
        }
    } @finally {
        fly_lan_mvp_destroy(guest);
        [host cancel];
    }
}

@end

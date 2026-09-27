#import <XCTest/XCTest.h>

#import "FlyNesNearbyBridge.h"
#import "BuiltinGames.h"
#include <flynes/flynes_nearby_mvp.h>
#include "NearbyPlaybackState.hpp"

#include <vector>
#include <map>

@interface NearbyMvpBridgeTests : XCTestCase
@end

@implementation NearbyMvpBridgeTests

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
    } @finally {
        fly_lan_mvp_destroy(guest);
        [host cancel];
    }
}

@end

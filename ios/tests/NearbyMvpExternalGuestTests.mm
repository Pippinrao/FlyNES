#import <XCTest/XCTest.h>
#import "FlyNesNearbyBridge.h"
#import "BuiltinGames.h"

@interface NearbyMvpExternalGuestTests : XCTestCase
@end

@implementation NearbyMvpExternalGuestTests
- (void)testJoinExternalSimulatorHostAndPlayBothStreams
{
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
        inDomains:NSUserDomainMask].firstObject;
    NSURL *inviteFile = [documents URLByAppendingPathComponent:@"nearby-cross-guest-invite.txt"];
    NSString *invite = [NSString stringWithContentsOfURL:inviteFile
        encoding:NSUTF8StringEncoding error:nil];
    if (invite.length == 0) {
        XCTSkip(@"Requires an external simulator invitation");
        return;
    }
    XCTAssertTrue([invite hasPrefix:@"flynes-lan-v1:"]);
    FlyNesNearbyBridge *guest = FlyNesNearbyBridge.sharedInstance;
    [guest cancel];
    NSError *error = nil;
    @try {
        XCTAssertTrue([guest joinInvite:invite error:&error], @"%@", error);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
        while ([guest.snapshot[@"state"] unsignedIntegerValue] != 3 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.01];
        XCTAssertEqual([guest.snapshot[@"state"] unsignedIntegerValue], 3u,
            @"reason=%@ transport=%@", guest.snapshot[@"reason"], guest.snapshot[@"transportResult"]);
        if ([guest.snapshot[@"state"] unsignedIntegerValue] != 3u) return;
        XCTAssertEqual([guest.snapshot[@"role"] unsignedIntegerValue], 2u);
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
        deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
        while ([guest.snapshot[@"peerGameKey"] length] == 0 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.01];
        XCTAssertEqualObjects(guest.snapshot[@"peerGameKey"], game.canonicalId);
        XCTAssertTrue([guest selectGuestGameROM:rom canonicalID:game.canonicalId title:game.titleEn]);
        deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
        while ([guest.snapshot[@"state"] unsignedIntegerValue] != 6 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.01];
        XCTAssertEqual([guest.snapshot[@"state"] unsignedIntegerValue], 6u);
        NSUInteger pcmBytes = 0;
        deadline = [NSDate dateWithTimeIntervalSinceNow:25.0];
        NSDate *nextProgress = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while ([guest.snapshot[@"completedFrames"] unsignedLongLongValue] < 600 &&
               deadline.timeIntervalSinceNow > 0) {
            [guest stepWithButtons:([guest.snapshot[@"completedFrames"] unsignedLongLongValue] / 30) % 2 ? 0x80 : 0];
            pcmBytes += guest.pullPCM.length;
            if (nextProgress.timeIntervalSinceNow <= 0) {
                NSLog(@"NearbyExternalGuest progress frames=%@ state=%@ reason=%@",
                    guest.snapshot[@"completedFrames"], guest.snapshot[@"state"], guest.snapshot[@"reason"]);
                nextProgress = [NSDate dateWithTimeIntervalSinceNow:5.0];
            }
            [NSThread sleepForTimeInterval:0.008];
        }
        XCTAssertGreaterThanOrEqual([guest.snapshot[@"completedFrames"] unsignedLongLongValue], 600ull,
            @"state=%@ reason=%@", guest.snapshot[@"state"], guest.snapshot[@"reason"]);
        XCTAssertGreaterThan(pcmBytes, 0u);
        XCTAssertEqual(guest.copyLatestRgb565Frame.length, 256u * 240u * 2u);
        [NSThread sleepForTimeInterval:2.0];
    } @finally {
        [guest cancel];
        [NSFileManager.defaultManager removeItemAtURL:inviteFile error:nil];
    }
}
@end

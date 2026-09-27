#import <XCTest/XCTest.h>
#import "FlyNesNearbyBridge.h"
#import "BuiltinGames.h"

@interface NearbyMvpExternalHostTests : XCTestCase
@end

@implementation NearbyMvpExternalHostTests
- (void)testExternalSimulatorGuestUsesTheSameGameAndPcm
{
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
        inDomains:NSUserDomainMask].firstObject;
    NSURL *enabledFile = [documents URLByAppendingPathComponent:@"nearby-cross-host-enabled.txt"];
    if (![NSFileManager.defaultManager fileExistsAtPath:enabledFile.path]) {
        XCTSkip(@"Requires the external simulator guest harness");
        return;
    }
    [NSFileManager.defaultManager removeItemAtURL:enabledFile error:nil];
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
    XCTAssertTrue([invite hasPrefix:@"flynes-lan-v1:"]);
    NSURL *inviteFile = [documents URLByAppendingPathComponent:@"nearby-cross-invite.txt"];
    XCTAssertTrue([invite writeToURL:inviteFile atomically:YES encoding:NSUTF8StringEncoding error:&error],
                  @"%@", error);
    @try {
        // The peer's XCTest runner may still be launching on a second simulator.
        deadline = [NSDate dateWithTimeIntervalSinceNow:180.0];
        while ([host.snapshot[@"state"] unsignedIntegerValue] != 3 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.01];
        XCTAssertEqual([host.snapshot[@"state"] unsignedIntegerValue], 3u);
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
        deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while ([host.snapshot[@"state"] unsignedIntegerValue] != 6 &&
               deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.01];
        XCTAssertEqual([host.snapshot[@"state"] unsignedIntegerValue], 6u);
        NSUInteger pcmBytes = 0;
        deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while ([host.snapshot[@"completedFrames"] unsignedLongLongValue] < 600 &&
               deadline.timeIntervalSinceNow > 0) {
            [host stepWithButtons:([host.snapshot[@"completedFrames"] unsignedLongLongValue] / 30) % 2 ? 1 : 0];
            pcmBytes += host.pullPCM.length;
            [NSThread sleepForTimeInterval:0.008];
        }
        XCTAssertGreaterThanOrEqual([host.snapshot[@"completedFrames"] unsignedLongLongValue], 600ull);
        XCTAssertGreaterThan(pcmBytes, 0u);
        XCTAssertEqual(host.copyLatestRgb565Frame.length, 256u * 240u * 2u);
        [NSThread sleepForTimeInterval:5.0];
    } @finally {
        [NSFileManager.defaultManager removeItemAtURL:inviteFile error:nil];
        [host cancel];
    }
}
@end

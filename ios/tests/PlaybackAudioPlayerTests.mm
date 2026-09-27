#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import "../app/audio/FlyNesAudioPlayer.h"
#import "FlyNesRuntimeBridge.h"
#include <atomic>
#include <memory>

@interface PlaybackAudioPlayerTests : XCTestCase
@end
@implementation PlaybackAudioPlayerTests
- (void)testRealGamePCMReachesOfflineMixerAndPlayerClock {
    XCTAssertTrue(NSThread.isMainThread);
    FlyNesRuntimeBridge *runtime = [[FlyNesRuntimeBridge alloc] init];
    XCTAssertTrue([runtime createRuntime:nil]);
    NSData *rom = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"thwaite" withExtension:@"nes"]];
    XCTAssertTrue([runtime loadRom:rom error:nil]);
    AVAudioFormat *renderFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    NSError *failure = nil;
    XCTAssertTrue([engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                                          format:renderFormat maximumFrameCount:1024 error:&failure], @"%@", failure);
    FlyNesAudioPlayer *audio = [[FlyNesAudioPlayer alloc] initWithEngine:engine];
    AVAudioPlayerNode *player = [audio valueForKey:@"player_"];
    auto nonSilent = std::make_shared<std::atomic<bool>>(false);
    AVAudioPCMBuffer *mixed = [[AVAudioPCMBuffer alloc] initWithPCMFormat:renderFormat frameCapacity:1024];
    XCTAssertTrue([audio start:&failure], @"%@", failure);
    XCTestExpectation *played = [self expectationWithDescription:@"Four seconds of game audio output"];
    __block NSUInteger frames = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *tick) {
        NSError *stepError = nil;
        XCTAssertTrue([runtime stepFrameWithButtons:(frames >= 60 && frames < 65 ? 8 : 0) error:&stepError], @"%@", stepError);
        [audio enqueuePCM:[runtime pullPCM]];
        AVAudioEngineManualRenderingStatus status = [engine renderOffline:800 toBuffer:mixed error:&stepError];
        XCTAssertEqual(status, AVAudioEngineManualRenderingStatusSuccess, @"%@", stepError);
        for (AVAudioChannelCount channel = 0; channel < mixed.format.channelCount; ++channel) {
            for (AVAudioFrameCount frame = 0; frame < mixed.frameLength; ++frame) {
                if (fabsf(mixed.floatChannelData[channel][frame]) > 0.0001f) nonSilent->store(true);
            }
        }
        if (++frames >= 240) { [tick invalidate]; [played fulfill]; }
    }];
    [self waitForExpectations:@[played] timeout:15];
    [timer invalidate];
    AVAudioTime *nodeTime = player.lastRenderTime;
    AVAudioTime *playerTime = nodeTime ? [player playerTimeForNodeTime:nodeTime] : nil;
    XCTAssertTrue(engine.running);
    XCTAssertTrue(player.playing);
    XCTAssertGreaterThan(playerTime.sampleTime, 48000);
    XCTAssertTrue(nonSilent->load(), @"Game PCM must produce nonzero samples at the mixer");
    [audio pause];
    XCTAssertFalse(player.playing);
}
@end

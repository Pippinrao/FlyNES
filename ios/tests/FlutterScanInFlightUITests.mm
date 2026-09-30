#import <XCTest/XCTest.h>

// Implemented by FlutterSourceUITests.mm. Reuse its real Files picker, absent
// Hundred precondition, preserved Single/saves, and exact-UUID removal guard.
@interface FlutterSourceUIBase : XCTestCase
@property(nonatomic, strong) XCUIApplication *app;
@property(nonatomic, copy) NSString *container;
@property(nonatomic) NSUInteger baselineCount;
- (NSString *)currentContainer;
- (NSArray<NSDictionary *> *)sources;
- (NSDictionary *)sourceNamed:(NSString *)name in:(NSArray<NSDictionary *> *)rows;
- (void)launchHall;
- (void)openSources;
- (void)pick:(NSString *)name directory:(BOOL)directory;
- (void)tap:(NSString *)label;
- (XCUIElement *)button:(NSString *)label;
- (XCUIElement *)text:(NSString *)label;
- (void)expectCount:(NSUInteger)expected;
- (void)waitFor:(BOOL (^)(void))condition reason:(NSString *)reason;
- (void)capture:(NSString *)name;
- (void)tapOwnedHundredRemove;
- (void)assertExistingSourcesRetained;
- (void)assertSingleFavoriteAndContinue;
@end

@interface FlutterScanInFlightUITests : FlutterSourceUIBase
@property(nonatomic, copy) NSString *holdRun;
@end
@implementation FlutterScanInFlightUITests
- (NSString *)marker:(NSString *)suffix {
    return [[self currentContainer] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"tmp/scan-inflight-%@-%@", self.holdRun, suffix]];
}
- (NSDictionary *)holdState {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:[self marker:@"state.plist"]];
    return [state[@"run"] isEqual:self.holdRun] ? state : @{};
}
- (void)assertReadStillHeld {
    NSDictionary *state = [self holdState];
    XCTAssertEqualObjects(state[@"held"], @YES);
    XCTAssertEqualObjects(state[@"readAttempted"], @YES);
    XCTAssertEqualObjects(state[@"readGranted"], @NO, @"Real coordinated read must be blocked, not just a fake scanning label");
    XCTAssertEqualObjects(state[@"expired"], @NO);
}
- (XCUIElement *)ownedScan:(NSString *)uuid {
    NSString *identifier = [@"source-remove-" stringByAppendingString:uuid];
    XCUIElement *scan = nil;
    for (XCUIElement *parent in [self.app.otherElements containingType:XCUIElementTypeButton identifier:identifier].allElementsBoundByIndex) {
        XCUIElementQuery *children = [parent childrenMatchingType:XCUIElementTypeButton];
        if ([children matchingIdentifier:identifier].count == 1) {
            XCUIElementQuery *actions = [children matchingPredicate:[NSPredicate predicateWithFormat:@"label == 'Scan'"]];
            if (actions.count == 1) { XCTAssertNil(scan); scan = actions.firstMatch; }
        }
    }
    XCTAssertNotNil(scan); return scan;
}
- (XCUIElement *)visibleOwnedScan:(NSString *)uuid {
    XCUIElement *scan = [self ownedScan:uuid];
    XCUIElement *viewport = self.app.scrollViews.firstMatch;
    XCTAssertTrue([scan waitForExistenceWithTimeout:10]);
    XCTAssertTrue(viewport.exists, @"Sources must expose its actual scroll viewport");
    BOOL (^visible)(void) = ^BOOL {
        return scan.exists && !CGRectIsEmpty(scan.frame) &&
            CGRectContainsRect(self.app.frame, scan.frame) &&
            CGRectContainsRect(viewport.frame, scan.frame);
    };
    for (NSUInteger n = 0; !visible() && n < 14; ++n) {
        BOOL above = !CGRectIsEmpty(scan.frame) && CGRectGetMidY(scan.frame) < CGRectGetMinY(viewport.frame);
        [[self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, above ? 0.6 : 0.8)] pressForDuration:0.1
            thenDragToCoordinate:[self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, above ? 0.8 : 0.6)]];
    }
    CGRect previous = CGRectNull; NSUInteger stable = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (stable < 3 && deadline.timeIntervalSinceNow > 0) {
        CGRect frame = scan.frame;
        stable = visible() && CGRectEqualToRect(previous, frame) ? stable + 1 : 0;
        previous = frame; [NSThread sleepForTimeInterval:0.25];
    }
    // Disabled Scan still needs a real, fully visible rectangle. Its enabled
    // state is asserted separately; hittability is required only before taps.
    XCTAssertEqual(stable, 3u, @"Exact UUID Scan must settle inside the Sources viewport");
    XCTAssertTrue(visible()); return scan;
}
- (void)testRealCoordinatedScanContinuesAcrossFlutterSettingsAndPageReturn {
    [self openSources]; [self pick:@"FlyNES-E2E-Hundred" directory:YES];
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 100];
    [self waitFor:^BOOL { return [self sourceNamed:@"FlyNES-E2E-Hundred" in:[self sources]][@"uuid"] != nil; }
           reason:@"Real imported fixture UUID persists"];
    NSString *uuid = [self sourceNamed:@"FlyNES-E2E-Hundred" in:[self sources]][@"uuid"];
    self.holdRun = NSUUID.UUID.UUIDString;
    [self.app terminate];
    self.app.launchEnvironment = @{@"FLYNES_SCAN_HOLD_RUN":self.holdRun};
    [self launchHall]; [self expectCount:self.baselineCount + 100];
    [self waitFor:^BOOL { return [[self holdState][@"phase"] isEqual:@"waiting"]; }
           reason:@"Debug-only coordinator observer is ready"];
    NSString *commandPath = [self marker:@"command.plist"];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:commandPath]);
    NSDictionary *command = @{@"run":self.holdRun, @"sourceUUID":uuid,
        @"sourceName":@"FlyNES-E2E-Hundred", @"test":self.name};
    XCTAssertTrue([command writeToFile:commandPath atomically:YES]);
    [self waitFor:^BOOL { return [[self holdState][@"phase"] isEqual:@"held"]; }
           reason:@"Real writer coordination acquired the exact owned source"];
    [self openSources];
    XCUIElement *scan = [self visibleOwnedScan:uuid];
    XCTAssertTrue(scan.enabled); XCTAssertTrue(scan.hittable); [scan tap];
    [self waitFor:^BOOL { return [[self holdState][@"readAttempted"] boolValue]; }
           reason:@"Production Scan reached the real coordinated read"];
    [self assertReadStillHeld];
    XCTAssertFalse([self visibleOwnedScan:uuid].enabled);
    [self assertReadStillHeld];
    [self capture:@"scan-inflight-real-read-blocked"];
    [self tap:@"Back"]; [self tap:@"Settings"]; [self tap:@"Audio"];
    XCTAssertTrue([[self text:@"Sound"] waitForExistenceWithTimeout:10], @"Settings must remain readable during the actual scan");
    [self assertReadStillHeld]; [self capture:@"scan-inflight-settings-readable"];
    [self tap:@"Back"];
    if (self.app.frame.size.width < 720) [self tap:@"Back"];
    [self openSources]; [self assertReadStillHeld];
    XCTAssertFalse([self visibleOwnedScan:uuid].enabled, @"Reattached page must still observe the running operation");
    [self assertReadStillHeld];
    [self capture:@"scan-inflight-return-still-running"];
    NSString *release = [self marker:@"release.txt"];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:release]);
    XCTAssertTrue([NSFileManager.defaultManager createFileAtPath:release
        contents:[self.holdRun dataUsingEncoding:NSUTF8StringEncoding] attributes:nil]);
    [self waitFor:^BOOL { return [[self holdState][@"readReturned"] boolValue] &&
        [[self holdState][@"phase"] isEqual:@"released"] && [self ownedScan:uuid].enabled; }
           reason:@"Released real read finishes scan and the reattached UI refreshes"];
    XCTAssertEqualObjects([self holdState][@"expired"], @NO);
    XCTAssertEqualObjects([self holdState][@"readGranted"], @YES);
    XCTAssertEqualObjects([self sourceNamed:@"FlyNES-E2E-Hundred" in:[self sources]][@"uuid"], uuid);
    XCTAssertEqual([[self sourceNamed:@"FlyNES-E2E-Hundred" in:[self sources]][@"error"] length], 0u);
    XCUIElement *completed = [self visibleOwnedScan:uuid];
    XCTAssertTrue(completed.enabled); XCTAssertTrue(completed.hittable);
    [self capture:@"scan-inflight-return-completed"];
    [self tapOwnedHundredRemove]; [self tap:@"Confirm"];
    [self waitFor:^BOOL { return [self sourceNamed:@"FlyNES-E2E-Hundred" in:[self sources]] == nil; }
           reason:@"Remove only the source created by this test"];
    [self tap:@"Back"]; [self expectCount:self.baselineCount];
    [self assertSingleFavoriteAndContinue]; [self assertExistingSourcesRetained];
    // Keep UUID markers as evidence. Failure teardown only terminates this app;
    // process exit or the hard deadline releases coordination, never user data.
}
@end

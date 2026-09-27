#import <XCTest/XCTest.h>

@interface NearbyLiveRoomUITests : XCTestCase
@property(nonatomic, strong) XCUIApplication *app;
@property(nonatomic, copy) NSString *container;
@property(nonatomic, copy) NSString *fixtureDirectory;
@property(nonatomic, copy) NSString *fixtureID;
@end

@implementation NearbyLiveRoomUITests

- (void)removeFixtureDirectory {
    if (!self.container.length) return;
    NSString *temporary = [self.container stringByAppendingPathComponent:@"tmp"].stringByResolvingSymlinksInPath;
    NSString *resolved = self.fixtureDirectory.stringByResolvingSymlinksInPath;
    if ([resolved.stringByDeletingLastPathComponent isEqual:temporary] &&
        [resolved.lastPathComponent hasPrefix:@"flynes-nearby-ui-"])
        [NSFileManager.defaultManager removeItemAtPath:resolved error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[self.container
        stringByAppendingPathComponent:@"tmp/nearby-ui-command.plist"] error:nil];
}

- (NSDictionary *)status {
    // XCTest can reinstall the app on launch and allocate a new data UUID.
    // Find the current run's marker each time, rather than caching a prelaunch path.
    NSString *applications = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    NSString *found = nil;
    NSDictionary *current = nil;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:applications error:nil]) {
        NSString *candidate = [applications stringByAppendingPathComponent:name];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[candidate
            stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if (![metadata[@"MCMMetadataIdentifier"] isEqual:@"com.flynes.app"]) continue;
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:[candidate
            stringByAppendingPathComponent:@"tmp/nearby-ui-state.plist"]];
        if (![snapshot[@"fixtureID"] isEqual:self.fixtureID]) continue;
        if (found) return @{}; // Never choose an arbitrary duplicate container.
        found = candidate;
        current = snapshot;
    }
    if (!found) return @{};
    self.container = found;
    self.fixtureDirectory = [[found stringByAppendingPathComponent:@"tmp"]
        stringByAppendingPathComponent:[@"flynes-nearby-ui-" stringByAppendingString:self.fixtureID]];
    return current;
}

- (void)waitForStatus:(BOOL (^)(NSDictionary *))predicate description:(NSString *)description {
    NSPredicate *condition = [NSPredicate predicateWithBlock:^BOOL(id unused, NSDictionary *bindings) {
        (void)unused; (void)bindings;
        return predicate([self status]);
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:condition object:self];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:20], XCTWaiterResultCompleted,
                   @"%@: %@", description, [self status]);
    XCTAssertEqualObjects([self status][@"error"], @"", @"Native peer fixture failed");
}

- (XCUIElement *)element:(NSString *)identifier {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:identifier].firstMatch;
}

- (void)send:(NSString *)action {
    NSDictionary *current = [self status];
    XCTAssertEqualObjects(current[@"fixtureID"], self.fixtureID,
                          @"Commands require this run's current app container");
    if (![current[@"fixtureID"] isEqual:self.fixtureID]) return;
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *command = @{@"id": identifier, @"action": action};
    XCTAssertTrue([command writeToFile:[self.container stringByAppendingPathComponent:
        @"tmp/nearby-ui-command.plist"] atomically:YES]);
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"command"] isEqual:identifier];
    } description:action];
}

- (void)launchRole:(NSString *)role {
    self.continueAfterFailure = NO;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    NSString *applications = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    XCTAssertGreaterThan(applications.length, 0u, @"Use the repository simulator test runner");
    self.fixtureID = NSUUID.UUID.UUIDString;
    self.app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    self.app.launchEnvironment = @{@"FLYNES_UI_NEARBY_ROLE": role,
                                  @"FLYNES_UI_NEARBY_FIXTURE_ID": self.fixtureID};
    self.app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US"];
    [self.app launch];
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"app"][@"state"] intValue] == 3 && [status[@"peerState"] intValue] == 3;
    } description:@"Both actual sessions connected in empty lobby"];
    XCTAssertTrue([[self element:@"open_nearby"] waitForExistenceWithTimeout:15]);
    [[self element:@"open_nearby"] tap];
    XCTAssertTrue([[self element:@"nearby_lobby_row_rom_identity"] waitForExistenceWithTimeout:10]);
}

- (void)waitForGame:(NSString *)key afterFrame:(unsigned long long)frame {
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"app"][@"state"] intValue] == 6 &&
            ![status[@"app"][@"paused"] boolValue] && [status[@"key"] isEqual:key] &&
            [status[@"app"][@"completedFrames"] unsignedLongLongValue] > frame &&
            [status[@"peerFrames"] unsignedLongLongValue] > frame;
    } description:@"Both real sessions advancing the selected game"];
    XCTAssertTrue([[self element:@"OPEN_PAUSE"] waitForExistenceWithTimeout:10]);
}

- (unsigned long long)returnToRoom {
    [[self element:@"OPEN_PAUSE"] tap];
    XCTAssertTrue([[self element:@"resume"] waitForExistenceWithTimeout:5]);
    XCTAssertEqualObjects([self element:@"game_center"].label, @"Return to room");
    XCTAssertFalse([self element:@"settings"].exists);
    XCTAssertFalse([self element:@"save"].exists);
    XCTAssertFalse([self element:@"load"].exists);
    XCTAssertFalse([self element:@"nearby_status_banner"].exists);
    [[self element:@"game_center"] tap];
    XCTAssertTrue([[self element:@"nearby_lobby_resume"] waitForExistenceWithTimeout:10]);
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"app"][@"paused"] boolValue] && [status[@"peerPaused"] boolValue];
    } description:@"Both real peers retain a paused running session"];
    return [[self status][@"app"][@"completedFrames"] unsignedLongLongValue];
}

- (void)testHostRoomRetainsCoverProgressAndPickerWhileEitherPlayerCanContinue {
    [self launchRole:@"host"];
    NSDictionary *game = [self status][@"games"][0];
    [[self element:@"nearby_lobby_choose_game"] tap];
    if ([self element:@"close_search"].exists) [[self element:@"close_search"] tap];
    XCTAssertTrue([[self element:@"category_builtin"] waitForExistenceWithTimeout:10]);
    [[self element:@"category_builtin"] tap];
    NSString *card = [@"game_card_" stringByAppendingString:game[@"key"]];
    XCTAssertTrue([[self element:card] waitForExistenceWithTimeout:15]);
    [[self element:card] tap];
    [[self element:@"launch_selected"] tap];
    [self waitForGame:game[@"key"] afterFrame:20];
    NSNumber *generation = [self status][@"playbackGeneration"];
    XCTAssertNotNil(generation);
    [self send:@"capture-cover"];
    XCTAssertEqualObjects([[self status][@"coverDirectory"] stringByResolvingSymlinksInPath],
        [self.fixtureDirectory stringByAppendingPathComponent:@"covers/v1"].stringByResolvingSymlinksInPath);
    unsigned long long pausedFrame = [self returnToRoom];
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation);
    XCTAssertEqualObjects([self element:@"nearby_lobby_row_rom_identity"].label, game[@"title"]);
    XCTAssertTrue([[self element:@"nearby_lobby_cover"] waitForExistenceWithTimeout:5]);
    [[self element:@"nearby_lobby_resume"] tap];
    [self waitForGame:game[@"key"] afterFrame:pausedFrame];
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation,
                          @"Continue must retain the original emulation instance");

    pausedFrame = [self returnToRoom];
    [[self element:@"nearby_lobby_choose_game"] tap];
    XCTAssertTrue([[self element:@"nearby_library_return_to_room"] waitForExistenceWithTimeout:10]);
    [[self element:@"nearby_library_return_to_room"] tap];
    XCTAssertTrue([[self element:@"nearby_lobby_resume"] waitForExistenceWithTimeout:10]);
    XCTAssertEqualObjects([self status][@"key"], game[@"key"]);
    XCTAssertEqual([[self status][@"app"][@"completedFrames"] unsignedLongLongValue], pausedFrame);
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation,
                          @"Cancelling game selection must preserve the current instance");
    [[self element:@"nearby_lobby_choose_game"] tap];
    XCTAssertTrue([[self element:@"nearby_library_return_to_room"] waitForExistenceWithTimeout:10]);
    [self send:@"resume"];
    [self waitForGame:game[@"key"] afterFrame:pausedFrame];
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation,
                          @"Peer Continue must preserve the current instance");
    XCTAssertFalse([self element:@"nearby_library_return_to_room"].exists);
}

- (void)testGuestPauseDrawerIsReplacedWhenRealHostChangesGame {
    [self launchRole:@"guest"];
    NSArray *games = [self status][@"games"];
    XCTAssertFalse([self element:@"nearby_lobby_choose_game"].exists);
    [self send:@"select-first"];
    [self waitForGame:games[0][@"key"] afterFrame:20];
    NSNumber *generation = [self status][@"playbackGeneration"];
    XCTAssertNotNil(generation);
    [[self element:@"OPEN_PAUSE"] tap];
    XCTAssertTrue([[self element:@"resume"] waitForExistenceWithTimeout:5]);
    XCTAssertEqualObjects([self element:@"game_center"].label, @"Return to room");
    XCTAssertFalse([self element:@"settings"].exists);
    [self send:@"change-game"];
    [self waitForGame:games[1][@"key"] afterFrame:20];
    XCTAssertNotEqualObjects([self status][@"playbackGeneration"], generation,
                             @"An actual host game switch must replace the emulation instance");
    XCTAssertFalse([self element:@"resume"].exists, @"Old pause drawer must be dismissed");
    [[self element:@"OPEN_PAUSE"] tap];
    XCTAssertTrue([[self element:@"pause_game_title"] waitForExistenceWithTimeout:5]);
    XCTAssertEqualObjects([self element:@"pause_game_title"].label, games[1][@"title"]);
}

- (void)tearDown {
    self.continueAfterFailure = YES;
    @try {
        if (self.app && self.container && self.app.state == XCUIApplicationStateRunningForeground) {
            [self send:@"cleanup"];
            XCTAssertTrue([[self status][@"cleaned"] boolValue]);
        }
    } @finally {
        if (self.app) [self.app terminate];
        [self removeFixtureDirectory];
        [super tearDown];
    }
}
@end

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

@interface NearbyLiveRoomUITests : XCTestCase
@property(nonatomic, strong) XCUIApplication *app;
@property(nonatomic, copy) NSString *container;
@property(nonatomic, copy) NSString *fixtureDirectory;
@property(nonatomic, copy) NSString *fixtureID;
@property(nonatomic) BOOL recordProductDiagnostics;
@end

// Real transport/runtime sessions, with the second native peer in this app process.
// This suite is not two-app, cross-platform, hotspot, or device acceptance evidence.
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

- (XCUIElement *)flutterButton:(NSString *)label {
    return [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
        @"label == %@ OR label BEGINSWITH %@", label, [label stringByAppendingString:@"\n"]]].firstMatch;
}

- (void)tapFlutterButton:(NSString *)label {
    XCUIElement *button = [self flutterButton:label];
    XCTAssertTrue([button waitForExistenceWithTimeout:15], @"Missing Flutter action %@", label);
    XCTAssertTrue(button.hittable, @"Flutter action %@ must be visible and operable", label);
    [button tap];
}

- (void)capture:(NSString *)name {
    [NSThread sleepForTimeInterval:0.35];
    XCTAttachment *image = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    image.name = name; image.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:image];
    XCTAttachment *tree = [XCTAttachment attachmentWithString:self.app.debugDescription];
    tree.name = [name stringByAppendingString:@"-semantics"];
    tree.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:tree];
}

- (void)openFlutterGamePicker {
    [[self element:@"nearby_lobby_choose_game"] tap];
    XCTAssertTrue([[self element:@"flutter_product_surface"] waitForExistenceWithTimeout:15]);
    XCTAssertTrue([[self flutterButton:@"Choose game"] waitForExistenceWithTimeout:15],
                  @"The native room must open Flutter with nearby selection purpose");
    XCTAssertFalse([self element:@"launch_selected"].exists, @"Legacy catalog picker must not be presented");
}

- (void)chooseFlutterGame:(NSDictionary *)game {
    [self openFlutterGamePicker];
    if ([self flutterButton:@"Close search"].exists) [self tapFlutterButton:@"Close search"];
    [self tapFlutterButton:@"Built-in"];
    [self tapFlutterButton:@"Search"];
    XCUIElement *field = self.app.textFields[@"Search games"];
    XCTAssertTrue([field waitForExistenceWithTimeout:10]);
    [field tap]; [field typeText:game[@"title"]];
    XCUIElement *done = self.app.keyboards.buttons[@"done"];
    XCTAssertTrue([done waitForExistenceWithTimeout:5]); [done tap];
    [self tapFlutterButton:game[@"title"]];
    [self capture:@"nearby-flutter-host-selected-game"];
    [self tapFlutterButton:@"Choose game"];
}

- (void)exerciseLocalInputAndRequireBothPeersAdvance:(NSString *)key {
    NSDictionary *before = [self status];
    unsigned long long frame = MAX([before[@"app"][@"completedFrames"] unsignedLongLongValue],
                                   [before[@"peerFrames"] unsignedLongLongValue]);
    XCUIElement *button = [self element:@"NES_A"];
    XCTAssertTrue([button waitForExistenceWithTimeout:5]);
    XCTAssertTrue(button.hittable);
    [button pressForDuration:0.25];
    // The fixture submits neutral input on the other peer. This checks the UI
    // input path stays operable and both sessions advance, not nonzero peer input.
    [self waitForGame:key afterFrame:frame + 10];
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
    if (self.recordProductDiagnostics)
        self.app.launchArguments = [self.app.launchArguments arrayByAddingObject:@"-flynes.test.product_diagnostics"];
    [self.app launch];
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"app"][@"state"] intValue] == 3 && [status[@"peerState"] intValue] == 3;
    } description:@"Both actual sessions connected in empty lobby"];
    XCTAssertTrue([[self element:@"flutter_product_surface"] waitForExistenceWithTimeout:25]);
    // AppleLanguages does not override a durable in-product Chinese preference.
    if ([[self flutterButton:@"设置"] waitForExistenceWithTimeout:2]) {
        [self tapFlutterButton:@"设置"];
        [self tapFlutterButton:@"游戏语言"];
        [self tapFlutterButton:@"语言"];
        [self tapFlutterButton:@"英文"];
        [self tapFlutterButton:@"Back"];
        if (self.app.frame.size.width < 720) [self tapFlutterButton:@"Back"];
    }
    [self tapFlutterButton:@"Nearby"];
    XCTAssertFalse([self element:@"open_nearby"].exists);
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
    BOOL roomVisible = [[self element:@"nearby_lobby_resume"] waitForExistenceWithTimeout:10];
    if (!roomVisible) [self capture:@"nearby-return-room-failure"];
    XCTAssertTrue(roomVisible);
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"app"][@"paused"] boolValue] && [status[@"peerPaused"] boolValue];
    } description:@"Both real peers retain a paused running session"];
    return [[self status][@"app"][@"completedFrames"] unsignedLongLongValue];
}

- (void)testFlutterHostRoomRetainsCoverProgressAndPickerWhileEitherPlayerCanContinue {
    [self launchRole:@"host"];
    NSDictionary *game = [self status][@"games"][0];
    [self chooseFlutterGame:game];
    [self waitForGame:game[@"key"] afterFrame:20];
    [self exerciseLocalInputAndRequireBothPeersAdvance:game[@"key"]];
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
    NSNumber *pausedPeerFrame = [self status][@"peerFrames"];
    [self openFlutterGamePicker];
    [self capture:@"nearby-flutter-host-cancel-picker"];
    [self tapFlutterButton:@"Return to room"];
    XCTAssertTrue([[self element:@"nearby_lobby_resume"] waitForExistenceWithTimeout:10]);
    XCTAssertEqualObjects([self status][@"key"], game[@"key"]);
    XCTAssertEqual([[self status][@"app"][@"completedFrames"] unsignedLongLongValue], pausedFrame);
    XCTAssertEqualObjects([self status][@"peerFrames"], pausedPeerFrame,
                          @"Cancelling selection must preserve the peer's paused progress too");
    XCTAssertTrue([[self status][@"peerPaused"] boolValue]);
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation,
                          @"Cancelling game selection must preserve the current instance");
    [self openFlutterGamePicker];
    XCTAssertTrue([[self flutterButton:@"Return to room"] waitForExistenceWithTimeout:10]);
    [self send:@"resume"];
    [self waitForGame:game[@"key"] afterFrame:pausedFrame];
    XCTAssertEqualObjects([self status][@"playbackGeneration"], generation,
                          @"Peer Continue must preserve the current instance");
    XCTAssertFalse([self flutterButton:@"Return to room"].exists);
    XCTAssertFalse([self element:@"flutter_product_surface"].exists,
                   @"Peer Continue must dismiss the Flutter picker and restore native play");
}

- (void)testFlutterHostChangesGameWithinTheConnectedRoom {
    [self launchRole:@"host"];
    NSArray *games = [self status][@"games"];
    XCTAssertGreaterThanOrEqual(games.count, 2u);
    [self chooseFlutterGame:games[0]];
    [self waitForGame:games[0][@"key"] afterFrame:20];
    [self exerciseLocalInputAndRequireBothPeersAdvance:games[0][@"key"]];
    NSNumber *generation = [self status][@"playbackGeneration"];
    [self returnToRoom];
    [self chooseFlutterGame:games[1]];
    [self waitForGame:games[1][@"key"] afterFrame:20];
    XCTAssertNotEqualObjects([self status][@"playbackGeneration"], generation,
                             @"Changing the ROM must replace playback, not resume the previous ROM");
    XCTAssertEqualObjects([self status][@"fixtureID"], self.fixtureID);
    XCTAssertEqual([[self status][@"app"][@"role"] intValue], 1);
    XCTAssertEqual([[self status][@"peerState"] intValue], 6);
    [self exerciseLocalInputAndRequireBothPeersAdvance:games[1][@"key"]];
    [self capture:@"nearby-flutter-host-second-game"];
    [self returnToRoom];
    XCTAssertEqualObjects([self element:@"nearby_lobby_row_rom_identity"].label, games[1][@"title"]);
    // No join/create command is sent between games. Existing fixture status has
    // no connection nonce, so this does not certify a transport-ID invariant.
}

- (NSDictionary *)productDiagnostics {
    XCTAssertEqualObjects([self status][@"fixtureID"], self.fixtureID);
    NSData *bytes = [NSData dataWithContentsOfFile:[self.container stringByAppendingPathComponent:
        @"Library/Caches/product-host-diagnostics.json"]];
    id value = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (void)testPeerDisconnectWhileFlutterPickerIsOpenRestoresOperableNativeEntry {
    self.recordProductDiagnostics = YES;
    [self launchRole:@"host"];
    NSDictionary *game = [self status][@"games"][0];
    [self chooseFlutterGame:game];
    [self waitForGame:game[@"key"] afterFrame:20];
    [self returnToRoom];
    [self openFlutterGamePicker];
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [[self productDiagnostics][@"nearbyPickerObserverCount"] isEqual:@1];
    } description:@"A single observer watches the detached room while Flutter picker is visible"];
    [self capture:@"nearby-flutter-picker-before-peer-disconnect"];

    [self send:@"disconnect-peer"];
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [status[@"peerDisconnectRequested"] boolValue] && ![status[@"cleaned"] boolValue] &&
            [status[@"app"][@"state"] intValue] == 4 && [status[@"peerState"] intValue] == 4;
    } description:@"App owner observes real peer-only transport disconnection without app cancel"];
    [self waitForStatus:^BOOL(NSDictionary *status) {
        NSDictionary *diagnostics = [self productDiagnostics];
        return [[diagnostics objectForKey:@"nearbyPickerObserverCount"] isEqual:@0] &&
            ![self element:@"flutter_product_surface"].exists &&
            [self element:@"nearby_action_create"].hittable && [self element:@"nearby_action_scan_qr"].hittable;
    } description:@"Disconnect closes Flutter picker, removes its observer and restores native entry"];
    XCTAssertFalse([self flutterButton:@"Return to room"].exists);
    [self capture:@"nearby-peer-disconnected-native-entry"];

    // Prove the entry is usable, not merely an accessibility node left by a
    // detached controller. Open and cancel the existing create-room route.
    [[self element:@"nearby_action_create"] tap];
    XCTAssertTrue([[self element:@"nearby_invite_disconnect"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue([self element:@"nearby_invite_disconnect"].hittable);
    [[self element:@"nearby_invite_disconnect"] tap];
    XCTAssertTrue([[self element:@"nearby_action_create"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue([self element:@"nearby_action_create"].hittable);
    XCTAssertEqualObjects([self productDiagnostics][@"nearbyPickerObserverCount"], @0);
    [self capture:@"nearby-entry-after-create-cancel"];
}

- (void)testGuestAutomaticallyCapturesCoverFromRealNearbyFrames {
    [self launchRole:@"guest"];
    NSDictionary *game = nil;
    for (NSDictionary *candidate in [self status][@"games"])
        if ([candidate[@"coverEligible"] boolValue]) { game = candidate; break; }
    XCTAssertNotNil(game);
    NSString *covers = [self status][@"coverDirectory"];
    XCTAssertEqual([NSFileManager.defaultManager contentsOfDirectoryAtPath:covers error:nil].count, 0u);
    [self send:@"select-cover-game"];
    [self waitForGame:game[@"key"] afterFrame:500];
    // Only production playback may write the cover: no capture-cover fixture command.
    [self waitForStatus:^BOOL(NSDictionary *status) {
        return [NSFileManager.defaultManager contentsOfDirectoryAtPath:status[@"coverDirectory"] error:nil].count > 0;
    } description:@"Nearby playback automatically persists a native-frame cover"];
    unsigned long long pausedFrame = [self returnToRoom];
    XCTAssertTrue([[self element:@"nearby_lobby_cover"] waitForExistenceWithTimeout:5]);
    [[self element:@"nearby_lobby_resume"] tap];
    [self waitForGame:game[@"key"] afterFrame:pausedFrame];
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

- (void)testFlutterNearbyRoomTitleHasVisibleLightInkOnDarkBackground {
    [self launchRole:@"host"];
    XCUIElement *title = self.app.navigationBars[@"Lobby"].staticTexts[@"Lobby"];
    XCTAssertTrue([title waitForExistenceWithTimeout:10]);
    [self capture:@"nearby-room-title-contrast"];
    XCUIScreenshot *shot = title.screenshot;
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:shot];
    attachment.name = @"nearby-room-title-contrast-crop";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    CGImageRef image = shot.image.CGImage;
    XCTAssertNotEqual(image, nullptr);
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    XCTAssertGreaterThan(width * height, 0u);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4,
        colors, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colors);
    XCTAssertNotEqual(context, nullptr);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    const uint8_t *rgba = static_cast<const uint8_t *>(pixels.bytes);
    NSUInteger lightInk = 0, darkBackground = 0;
    for (size_t index = 0; index < width * height; ++index) {
        const uint8_t *pixel = rgba + index * 4;
        if (pixel[0] >= 180 && pixel[1] >= 180 && pixel[2] >= 180) ++lightInk;
        if (pixel[0] <= 64 && pixel[1] <= 64 && pixel[2] <= 64) ++darkBackground;
    }
    // This is the actual title crop, excluding blue navigation actions. Requiring
    // both dark background and >=1% light glyph pixels detects black-on-dark
    // text without depending on a font rasterizer's exact antialiasing pixels.
    XCTAssertGreaterThan((double)darkBackground / (width * height), 0.5,
                         @"The room title must retain the approved dark surface");
    XCTAssertGreaterThan((double)lightInk / (width * height), 0.01,
                         @"Lobby needs visible light glyphs on its dark background; actual ratio %.6f",
                         (double)lightInk / (width * height));
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

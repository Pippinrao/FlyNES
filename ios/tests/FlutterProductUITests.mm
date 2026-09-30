#import <XCTest/XCTest.h>

@interface FlutterProductUIBase : XCTestCase
@end

@implementation FlutterProductUIBase
- (XCUIApplication *)launchEnglish {
    self.continueAfterFailure = NO;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US"];
    [app launch];
    XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:25]);
    return app;
}
- (void)capture:(NSString *)name app:(XCUIApplication *)app {
    // Product routes animate for at most 220 ms. Accessibility can become
    // hittable before compositing finishes; stable-page evidence must wait.
    // Controlled animation start/mid/end frames are covered separately.
    [NSThread sleepForTimeInterval:0.35];
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    shot.name = name; shot.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:shot];
    XCTAttachment *tree = [XCTAttachment attachmentWithString:app.debugDescription];
    tree.name = [name stringByAppendingString:@"-semantics"];
    tree.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:tree];
}
- (XCUIElement *)element:(NSString *)label app:(XCUIApplication *)app {
    return [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@ OR identifier == %@ OR label BEGINSWITH %@",
            label, label, [label stringByAppendingString:@"\n"]]].firstMatch;
}
- (void)tapVisible:(NSString *)label app:(XCUIApplication *)app {
    XCUIElement *item = [self element:label app:app];
    XCTAssertTrue([item waitForExistenceWithTimeout:10], @"Missing action %@", label);
    for (NSUInteger attempt = 0; !item.hittable && attempt < 3; ++attempt) [app swipeUp];
    XCTAssertTrue(item.hittable, @"Action %@ must be operable at the selected text size", label);
    [item tap];
}
- (void)setChinese:(BOOL)chinese fromChinese:(BOOL)wasChinese app:(XCUIApplication *)app {
    [self tapVisible:wasChinese ? @"设置" : @"Settings" app:app];
    [self tapVisible:wasChinese ? @"游戏语言" : @"Game & language" app:app];
    [self tapVisible:wasChinese ? @"语言" : @"Language" app:app];
    [self tapVisible:chinese ? @"Simplified Chinese" : @"英文" app:app];
    NSString *back = chinese ? @"返回" : @"Back";
    [self tapVisible:back app:app];
    if (app.frame.size.width < 720) [self tapVisible:back app:app];
    XCTAssertTrue([app.buttons[chinese ? @"搜索" : @"Search"] waitForExistenceWithTimeout:10]);
}
- (void)scrollControlsToEnd:(XCUIApplication *)app chinese:(BOOL)chinese {
    XCUIElement *reset = [self element:chinese ? @"重置操作设置" : @"Reset controls" app:app];
    // Hittable is not a stable scroll anchor. A fling can stop 1.3 points short
    // of the end; freeze the actual final row at its documented 16-point inset.
    for (NSUInteger attempt = 0; attempt < 4; ++attempt) {
        [app swipeUp];
        [NSThread sleepForTimeInterval:0.6];
        if (reset.hittable && fabs(CGRectGetMaxY(reset.frame) - (CGRectGetMaxY(app.frame) - 16)) < 0.1) return;
    }
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(reset.frame), CGRectGetMaxY(app.frame) - 16, 0.1,
        @"Controls screenshots require the real scroll endpoint, not a variable fling position");
}
- (NSDictionary *)sessionDiagnostics {
    NSString *containers = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    XCTAssertGreaterThan(containers.length, 0u, @"Use run_simulator_tests.py for durable diagnostics");
    NSString *container = nil;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:containers error:nil]) {
        NSString *candidate = [containers stringByAppendingPathComponent:name];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
            [candidate stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([metadata[@"MCMMetadataIdentifier"] isEqual:@"com.flynes.app"]) {
            XCTAssertNil(container, @"A single current application container is required");
            container = candidate;
        }
    }
    NSData *data = [NSData dataWithContentsOfFile:[container stringByAppendingPathComponent:
        @"Library/Caches/product-host-diagnostics.json"]];
    XCTAssertNotNil(data, @"Debug host diagnostics must capture real owner/session counts");
    NSDictionary *result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    XCTAssertTrue([result isKindOfClass:NSDictionary.class]);
    return result ?: @{};
}
@end

@interface FlutterProductUITests : FlutterProductUIBase
@end
@implementation FlutterProductUITests
- (void)testOrdinaryLaunchUsesFlutterProductHall {
    self.continueAfterFailure = NO;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US"];
    [app launch];
    XCTAssertTrue([app.otherElements[@"flutter_product_surface"] waitForExistenceWithTimeout:25],
                  @"Normal launch must attach the production Flutter surface without a test entry flag");
    XCTAssertTrue([app.buttons[@"Search"] waitForExistenceWithTimeout:15]);
    XCTAssertTrue(app.buttons[@"Sources"].exists);
    XCTAssertTrue(app.buttons[@"Settings"].exists);
    [self capture:@"U01-ios-hall-geometry" app:app];
    XCTAssertGreaterThan(app.frame.size.width, app.frame.size.height, @"Product hall must occupy the landscape window");
    for (NSString *label in @[@"Search", @"Sources", @"Settings"]) {
        XCTAssertTrue(CGRectContainsRect(app.frame, app.buttons[label].frame), @"%@ must remain on screen", label);
        XCTAssertTrue(app.buttons[label].hittable, @"%@ must be operable", label);
    }
    XCTAssertFalse(app.buttons[@"open_settings"].exists, @"Legacy hall must not be on the normal route");
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    shot.name = @"U01-ios-ordinary-flutter-hall-en";
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}
- (void)testFiveSettingsSectionsLicensesAndLayoutReturn {
    XCUIApplication *app = [self launchEnglish];
    [app.buttons[@"Settings"] tap];
    BOOL compact = app.frame.size.width < 720;
    NSArray *sections = @[@"Display", @"Controls", @"Audio", @"Game & language", @"About"];
    for (NSString *section in sections) {
        XCUIElement *item = [self element:section app:app];
        XCTAssertTrue([item waitForExistenceWithTimeout:10]);
        [item tap];
        [self capture:[@"U14-ios-settings-" stringByAppendingString:section] app:app];
        if (compact && ![section isEqualToString:@"About"]) [app.buttons[@"Back"] tap];
    }
    XCUIElement *licenses = [self element:@"Licenses" app:app];
    XCTAssertTrue([licenses waitForExistenceWithTimeout:5]); [licenses tap];
    if (compact) {
        XCUIElement *component = [self element:@"Nestopia UE" app:app];
        XCTAssertTrue([component waitForExistenceWithTimeout:10]); [component tap];
    }
    XCTAssertTrue([[self element:@"Copy license" app:app] waitForExistenceWithTimeout:10]);
    [self capture:@"U20-ios-license-body" app:app];
    [app.buttons[@"Back"] tap];
    if (compact) {
        [app.buttons[@"Back"] tap]; // License list -> settings About detail.
        [app.buttons[@"Back"] tap]; // About detail -> settings sections.
    }
    [[self element:@"Controls" app:app] tap];
    [[self element:@"Edit layout" app:app] tap];
    XCTAssertTrue([app.buttons[@"layout_cancel"] waitForExistenceWithTimeout:10]);
    [self capture:@"U22-ios-native-layout" app:app];
    XCUIElementQuery *rawKeys = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:
        [NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"control."]];
    XCTAssertEqual(rawKeys.count, 0u,
        @"Layout controls must show localized names, not resource keys");
    [app.buttons[@"layout_cancel"] tap];
    XCTAssertTrue([[self element:@"Edit layout" app:app] waitForExistenceWithTimeout:10]);
    XCTAssertFalse(app.buttons[@"settings_done"].exists, @"Layout must return to Flutter settings");
    [app.buttons[@"Back"] tap];
    if (compact) [app.buttons[@"Back"] tap];
    XCTAssertTrue([app.buttons[@"Search"] waitForExistenceWithTimeout:10]);
}
- (void)testFlutterLayoutSaveCancelAndRestartPreserveCommittedDraft {
    XCUIApplication *app = [self launchEnglish];
    NSString *containers = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    XCTAssertGreaterThan(containers.length, 0u);
    NSData *(^layoutBytes)(void) = ^NSData * {
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:containers error:nil]) {
            NSString *candidate = [containers stringByAppendingPathComponent:name];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[candidate
                stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([metadata[@"MCMMetadataIdentifier"] isEqual:@"com.flynes.app"])
                return [NSData dataWithContentsOfFile:[candidate stringByAppendingPathComponent:@"Documents/control_layout.v2"]];
        }
        XCTFail(@"Current app container must exist"); return nil;
    };
    void (^openLayout)(void) = ^{
        [self tapVisible:@"Settings" app:app]; [self tapVisible:@"Controls" app:app];
        [self tapVisible:@"Edit layout" app:app];
        XCTAssertTrue([app.sliders[@"layout_opacity"] waitForExistenceWithTimeout:10]);
    };
    openLayout();
    NSData *before = layoutBytes();
    NSString *originalValue = [app.sliders[@"layout_opacity"].value description];
    double target = originalValue.doubleValue > 65 ? 0.2 : 0.8;
    [app.sliders[@"layout_opacity"] adjustToNormalizedSliderPosition:target];
    XCTAssertNotEqualObjects([app.sliders[@"layout_opacity"].value description], originalValue);
    [app.buttons[@"layout_cancel"] tap];
    XCTAssertTrue([[self element:@"Edit layout" app:app] waitForExistenceWithTimeout:10]);
    XCTAssertEqualObjects(layoutBytes(), before, @"Cancelling a changed draft must write no layout bytes");
    [self tapVisible:@"Edit layout" app:app];
    XCTAssertEqualObjects([app.sliders[@"layout_opacity"].value description], originalValue);
    [app.sliders[@"layout_opacity"] adjustToNormalizedSliderPosition:target];
    NSString *savedValue = [app.sliders[@"layout_opacity"].value description];
    [app.buttons[@"layout_save"] tap];
    XCTAssertTrue([[self element:@"Edit layout" app:app] waitForExistenceWithTimeout:10]);
    NSData *committed = layoutBytes(); XCTAssertGreaterThan(committed.length, 0u);
    XCTAssertNotEqualObjects(committed, before, @"Save must persist the changed draft before returning");
    [self capture:@"U22-layout-save-return-flutter" app:app];
    [app terminate]; [app launch];
    XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:25]);
    openLayout();
    XCTAssertEqualObjects([app.sliders[@"layout_opacity"].value description], savedValue);
    XCTAssertEqualObjects(layoutBytes(), committed);
    [self capture:@"U22-layout-committed-after-process-restart" app:app];
    [app.buttons[@"layout_cancel"] tap];
    XCTAssertTrue([[self element:@"Edit layout" app:app] waitForExistenceWithTimeout:10]);
    XCTAssertFalse(app.buttons[@"settings_done"].exists);
    XCTAssertEqualObjects(layoutBytes(), committed);
}
- (void)testFlutterAudioWritesSurviveRestartAndLicenseCopyUsesPackagedBody {
    XCUIApplication *app = [self launchEnglish];
    [self tapVisible:@"Settings" app:app]; [self tapVisible:@"Audio" app:app];
    XCUIElement *sound = [self element:@"Sound" app:app];
    XCTAssertTrue([sound waitForExistenceWithTimeout:10]);
    NSString *initial = [sound.value description];
    for (NSUInteger cycle = 0; cycle < 2; ++cycle) {
        NSString *expected = [[sound.value description] isEqual:@"0"] ? @"1" : @"0";
        [sound tap];
        XCTNSPredicateExpectation *written = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithFormat:@"value == %@", expected] object:sound];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[written] timeout:10], XCTWaiterResultCompleted);
        [app terminate]; [app launch];
        XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:25]);
        [self tapVisible:@"Settings" app:app]; [self tapVisible:@"Audio" app:app];
        sound = [self element:@"Sound" app:app];
        XCTAssertTrue([sound waitForExistenceWithTimeout:10]);
        XCTAssertEqualObjects([sound.value description], expected);
        [self capture:[NSString stringWithFormat:@"U17-audio-persisted-%lu", (unsigned long)cycle] app:app];
    }
    XCTAssertEqualObjects([sound.value description], initial, @"Restore the original audio preference through UI");
    if (app.frame.size.width < 720) [self tapVisible:@"Back" app:app];
    [self tapVisible:@"About" app:app]; [self tapVisible:@"Licenses" app:app];
    if (app.frame.size.width < 720) [self tapVisible:@"Nestopia UE" app:app];
    [self tapVisible:@"Copy license" app:app];
    // Reading from the separate XCTest runner triggers iOS 16 paste consent.
    // Keep its synchronous pasteboard getter off the automation thread so the
    // real system permission sheet can be accepted without a deadlock.
    __block NSString *body = nil;
    XCTestExpectation *copied = [self expectationWithDescription:@"Packaged license copied after system consent"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        body = UIPasteboard.generalPasteboard.string; [copied fulfill];
    });
    XCUIApplication *springboard = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    XCUIElement *allowPaste = springboard.buttons[@"Allow Paste"];
    if ([allowPaste waitForExistenceWithTimeout:5]) [allowPaste tap];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[copied] timeout:10], XCTWaiterResultCompleted);
    XCTAssertGreaterThan(body.length, 500u);
    XCTAssertTrue([body containsString:@"GNU GENERAL PUBLIC LICENSE"]);
    [self capture:@"U20-license-copy-confirmed" app:app];
}
- (void)testSourcePickerCancellationReturnsToFlutter {
    XCUIApplication *app = [self launchEnglish];
    [app.buttons[@"Sources"] tap];
    XCTAssertTrue([app.buttons[@"Add file"] waitForExistenceWithTimeout:10]);
    [self capture:@"U09-ios-sources" app:app];
    [app.buttons[@"Add file"] tap];
    XCTAssertTrue([app.buttons[@"Cancel"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue(app.buttons[@"Cancel"].hittable);
    XCTAssertTrue(CGRectContainsRect(app.frame, app.buttons[@"Cancel"].frame));
    // Files may publish its folder placeholder before the registered app icon.
    // Match the existing frozen On My iPhone fixture; do not mask icon pixels.
    XCUIElement *container = app.cells[@"FlyNES, Container"];
    XCTAssertTrue([container waitForExistenceWithTimeout:10]);
    NSPredicate *iconLoaded = [NSPredicate predicateWithBlock:^BOOL(id unused, NSDictionary *bindings) {
        (void)unused; (void)bindings;
        XCUIElement *icon = container.images.firstMatch;
        return icon.exists && ![icon.identifier isEqual:@"Folder84pt"];
    }];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[[[XCTNSPredicateExpectation alloc]
        initWithPredicate:iconLoaded object:container]] timeout:30], XCTWaiterResultCompleted,
        @"System Files app icon must finish loading before comparison with the frozen reference");
    [self capture:@"U10-ios-system-file-picker" app:app];
    [app.buttons[@"Cancel"] tap];
    XCTAssertTrue([app.buttons[@"Add file"] waitForExistenceWithTimeout:10]);
    [self capture:@"U10-ios-picker-cancel-return" app:app];
    [app.buttons[@"Back"] tap];
    XCTAssertTrue([app.buttons[@"Search"] waitForExistenceWithTimeout:10]);
}
- (void)testGamePauseFlutterSettingsTwentyRoundTrips {
    [self runGamePauseRoundTripsWithLayout:NO];
}
- (void)testGamePauseFlutterSettingsNativeLayoutTwentyRoundTrips {
    [self runGamePauseRoundTripsWithLayout:YES];
}
- (void)runGamePauseRoundTripsWithLayout:(BOOL)includeLayout {
    XCUIApplication *app = [self launchEnglish];
    [app terminate];
    app.launchArguments = [app.launchArguments arrayByAddingObject:@"-flynes.test.product_diagnostics"];
    [app launch];
    XCTAssertTrue([app.buttons[@"Built-in"] waitForExistenceWithTimeout:25]);
    [app.buttons[@"Built-in"] tap];
    XCUIElement *launch = [app.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label IN %@", @[@"Start", @"Continue"]]].firstMatch;
    XCTAssertTrue([launch waitForExistenceWithTimeout:15]); [launch tap];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
    [app.buttons[@"OPEN_PAUSE"] tap];
    NSString *title = app.staticTexts[@"pause_game_title"].label;
    XCTAssertGreaterThan(title.length, 0u);
    NSDictionary *initial = [self sessionDiagnostics];
    XCTAssertGreaterThan([initial[@"gameSessionId"] length], 0u);
    XCTAssertGreaterThan([initial[@"frameSequence"] unsignedLongLongValue], 0u);
    for (NSUInteger index = 0; index < 20; ++index) {
        XCTAssertTrue([app.buttons[@"settings"] waitForExistenceWithTimeout:10]);
        [app.buttons[@"settings"] tap];
        BOOL settingsVisible = [[self element:@"Display" app:app] waitForExistenceWithTimeout:10];
        if (!settingsVisible) [self capture:@"U23-ios-settings-failure" app:app];
        XCTAssertTrue(settingsVisible);
        XCTAssertFalse(app.buttons[@"settings_done"].exists);
        NSDictionary *settings = [self sessionDiagnostics];
        XCTAssertEqualObjects(settings[@"gameSessionId"], initial[@"gameSessionId"]);
        XCTAssertEqualObjects(settings[@"romLoadCount"], initial[@"romLoadCount"]);
        XCTAssertEqualObjects(settings[@"frameSequence"], initial[@"frameSequence"]);
        XCTAssertEqualObjects(settings[@"paused"], @YES);
        XCTAssertEqualObjects(settings[@"engineCount"], @1);
        XCTAssertEqualObjects(settings[@"activeFlutterViews"], @1);
        XCTAssertEqualObjects(settings[@"coreOwnerCount"], @1);
        if (includeLayout) {
            [self tapVisible:@"Controls" app:app];
            [self tapVisible:@"Edit layout" app:app];
            XCTAssertTrue([app.buttons[@"layout_cancel"] waitForExistenceWithTimeout:10]);
            if (index == 0 || index == 19)
                [self capture:[NSString stringWithFormat:@"U22-pause-layout-%lu", (unsigned long)index] app:app];
            [app.buttons[@"layout_cancel"] tap];
            XCTAssertTrue([[self element:@"Edit layout" app:app] waitForExistenceWithTimeout:10]);
            NSDictionary *afterLayout = [self sessionDiagnostics];
            XCTAssertEqualObjects(afterLayout[@"gameSessionId"], initial[@"gameSessionId"]);
            XCTAssertEqualObjects(afterLayout[@"romLoadCount"], initial[@"romLoadCount"]);
            XCTAssertEqualObjects(afterLayout[@"frameSequence"], initial[@"frameSequence"]);
            XCTAssertEqualObjects(afterLayout[@"paused"], @YES);
            XCTAssertEqualObjects(afterLayout[@"engineCount"], @1);
            XCTAssertEqualObjects(afterLayout[@"activeFlutterViews"], @1);
            XCTAssertEqualObjects(afterLayout[@"coreOwnerCount"], @1);
            if (app.frame.size.width < 720) [app.buttons[@"Back"] tap];
        }
        if (index == 0 || index == 19) [self capture:[NSString stringWithFormat:@"U23-ios-pause-settings-%lu", (unsigned long)index] app:app];
        [app.buttons[@"Back"] tap];
        XCTAssertTrue([app.buttons[@"resume"] waitForExistenceWithTimeout:10]);
        XCTAssertEqualObjects(app.staticTexts[@"pause_game_title"].label, title);
        NSDictionary *returned = [self sessionDiagnostics];
        XCTAssertEqualObjects(returned[@"gameSessionId"], initial[@"gameSessionId"]);
        XCTAssertEqualObjects(returned[@"romLoadCount"], initial[@"romLoadCount"]);
        XCTAssertEqualObjects(returned[@"activeFlutterViews"], @0);
    }
    [app.buttons[@"game_center"] tap];
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
    [self capture:@"U24-ios-native-return-continue" app:app];
}
- (void)testRunningGameBackgroundReturnsSameSessionAndHallRebuildHasNoCore {
    XCUIApplication *app = [self launchEnglish]; [app terminate];
    app.launchArguments = [app.launchArguments arrayByAddingObject:@"-flynes.test.product_diagnostics"];
    [app launch]; XCTAssertTrue([app.buttons[@"Built-in"] waitForExistenceWithTimeout:25]);
    [app.buttons[@"Built-in"] tap];
    XCUIElement *start = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
        @"label IN %@", @[@"Start", @"Continue"]]].firstMatch;
    XCTAssertTrue([start waitForExistenceWithTimeout:15]); [start tap];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
    [app.buttons[@"OPEN_PAUSE"] tap];
    NSDictionary *before = [self sessionDiagnostics];
    XCTAssertGreaterThan([before[@"gameSessionId"] length], 0u);
    [app.buttons[@"resume"] tap];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:10]);
    XCTAssertFalse(app.buttons[@"resume"].exists);
    [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome];
    XCTNSPredicateExpectation *backgrounded = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return app.state != XCUIApplicationStateRunningForeground;
        }] object:app];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[backgrounded] timeout:10], XCTWaiterResultCompleted);
    [app activate];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
    [app.buttons[@"OPEN_PAUSE"] tap];
    NSDictionary *after = [self sessionDiagnostics];
    XCTAssertEqualObjects(after[@"gameSessionId"], before[@"gameSessionId"]);
    XCTAssertEqualObjects(after[@"romLoadCount"], before[@"romLoadCount"]);
    XCTAssertGreaterThan([after[@"frameSequence"] unsignedLongLongValue], [before[@"frameSequence"] unsignedLongLongValue]);
    XCTAssertEqualObjects(after[@"coreOwnerCount"], @1);
    XCTAssertEqualObjects(after[@"running"], @NO);
    [self capture:@"U26-running-background-same-session" app:app];
    [app.buttons[@"game_center"] tap];
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
    [app.buttons[@"Built-in"] tap];
    [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome]; [app activate];
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
    [app terminate]; [app launch];
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:25]);
    NSDictionary *rebuilt = [self sessionDiagnostics];
    XCTAssertEqualObjects(rebuilt[@"coreOwnerCount"], @0);
    XCTAssertEqualObjects(rebuilt[@"engineCount"], @1);
    XCTAssertEqualObjects(rebuilt[@"activeFlutterViews"], @1);
    XCTAssertEqualObjects(rebuilt[@"nearbyPickerObserverCount"], @0);
    XCTAssertNil(rebuilt[@"gameSessionId"], @"Process reconstruction cannot invent the previous live session");
    XCTAssertFalse(app.buttons[@"OPEN_PAUSE"].exists);
    [self capture:@"U26-flutter-hall-after-process-rebuild" app:app];
}
- (void)testPauseLanguageChangesRefreshExistingDrawerWithoutReloadingGame {
    XCUIApplication *app = [self launchEnglish];
    [app terminate];
    app.launchArguments = [app.launchArguments arrayByAddingObject:@"-flynes.test.product_diagnostics"];
    [app launch];
    XCTAssertTrue([app.buttons[@"Built-in"] waitForExistenceWithTimeout:25]);
    [app.buttons[@"Built-in"] tap];
    XCUIElement *launch = [app.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label IN %@", @[@"Start", @"Continue"]]].firstMatch;
    XCTAssertTrue([launch waitForExistenceWithTimeout:15]); [launch tap];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
    [app.buttons[@"OPEN_PAUSE"] tap];
    XCTAssertTrue([app.buttons[@"settings"] waitForExistenceWithTimeout:10]);
    NSDictionary *initial = [self sessionDiagnostics];
    XCTAssertGreaterThan([initial[@"gameSessionId"] length], 0u);
    XCTAssertGreaterThan([initial[@"frameSequence"] unsignedLongLongValue], 0u);
    XCTAssertEqualObjects(initial[@"paused"], @YES);
    XCTAssertEqualObjects(initial[@"running"], @NO);
    NSString *englishTitle = app.staticTexts[@"pause_game_title"].label;
    NSURL *manifestURL = [[NSBundle bundleForClass:self.class] URLForResource:@"builtin-games" withExtension:@"json"];
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:manifestURL]
                                                             options:0 error:nil];
    NSArray *matches = [manifest[@"games"] filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"titleEn == %@", englishTitle]];
    XCTAssertEqual(matches.count, 1u, @"Resolve the actual selected bundled title from the shared manifest");
    NSString *chineseTitle = [matches.firstObject[@"titleZhHans"] length] ? matches.firstObject[@"titleZhHans"] : englishTitle;
    for (NSNumber *target in @[@YES, @NO]) {
        BOOL chinese = target.boolValue;
        [app.buttons[@"settings"] tap];
        [self tapVisible:chinese ? @"Game & language" : @"游戏语言" app:app];
        [self tapVisible:chinese ? @"Language" : @"语言" app:app];
        [self tapVisible:chinese ? @"Simplified Chinese" : @"英文" app:app];
        NSString *back = chinese ? @"返回" : @"Back";
        [self tapVisible:back app:app];
        if (app.frame.size.width < 720) [self tapVisible:back app:app];
        XCTAssertTrue([app.buttons[@"resume"] waitForExistenceWithTimeout:10],
                      @"Settings must return to the existing paused native controller");
        [self capture:chinese ? @"U18-U23-ios-pause-language-zh" : @"U18-U23-ios-pause-language-en" app:app];
        NSDictionary *returned = [self sessionDiagnostics];
        // Collect all localization/owner failures, then restore English through
        // the real second toggle even when the first language assertion is RED.
        self.continueAfterFailure = YES;
        XCTAssertEqualObjects(app.buttons[@"resume"].label, chinese ? @"继续" : @"Resume");
        XCTAssertEqualObjects(app.buttons[@"settings"].label, chinese ? @"设置" : @"Settings");
        XCTAssertEqualObjects(app.buttons[@"game_center"].label, chinese ? @"游戏中心" : @"Game Center");
        XCTAssertEqualObjects(app.staticTexts[@"pause_game_title"].label, chinese ? chineseTitle : englishTitle);
        for (NSString *key in @[@"gameSessionId", @"romLoadCount", @"frameSequence"])
            XCTAssertEqualObjects(returned[key], initial[key], @"Language-only return must preserve %@", key);
        XCTAssertEqualObjects(returned[@"paused"], @YES);
        XCTAssertEqualObjects(returned[@"running"], @NO);
        XCTAssertEqualObjects(returned[@"engineCount"], @1);
        XCTAssertEqualObjects(returned[@"activeFlutterViews"], @0);
        XCTAssertEqualObjects(returned[@"coreOwnerCount"], @1);
        self.continueAfterFailure = NO;
    }
    [app.buttons[@"game_center"] tap];
    XCTAssertTrue([app.buttons[@"Search"] waitForExistenceWithTimeout:15]);
}
- (void)testCorePagesEnglishChineseAndSystemLargeText {
    self.continueAfterFailure = NO;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    // iOS has discrete text categories: AX XL = 40/17 (235%). Exact 200%
    // remains covered by the shared widget matrix; never label this 200%.
    for (NSString *size in @[@"UICTContentSizeCategoryL", @"UICTContentSizeCategoryAccessibilityXL"]) {
        app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US",
                                @"-UIPreferredContentSizeCategoryName", size];
        [app launch];
        XCTAssertTrue([app.buttons[@"Search"] waitForExistenceWithTimeout:25]);
        // Replay the reviewed fixture through visible controls. Nearby tests may
        // legitimately retain a different selection; do not reset app storage.
        [self tapVisible:@"Built-in" app:app];
        XCUIElement *filter = app.switches.firstMatch;
        XCTAssertTrue(filter.exists);
        if (![[filter.value description] isEqual:@"0"]) [filter tap];
        NSURL *manifestURL = [[NSBundle bundleForClass:self.class] URLForResource:@"builtin-games" withExtension:@"json"];
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:manifestURL]
                                                                 options:0 error:nil];
        NSArray *games = [manifest[@"games"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"titleEn"] caseInsensitiveCompare:b[@"titleEn"]];
        }];
        XCTAssertGreaterThan(games.count, 0u);
        NSString *fixtureTitle = games.firstObject[@"titleEn"];
        [self tapVisible:@"Search" app:app];
        XCUIElement *fixtureSearch = app.textFields[@"Search games"];
        [fixtureSearch tap]; [fixtureSearch typeText:fixtureTitle];
        [app.keyboards.buttons[@"done"] tap];
        XCUIElement *fixtureCard = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
            @"label == %@ OR label BEGINSWITH %@", fixtureTitle, [fixtureTitle stringByAppendingString:@"\n"]]].firstMatch;
        XCTAssertTrue([fixtureCard waitForExistenceWithTimeout:10]);
        XCTAssertTrue(fixtureCard.hittable); [fixtureCard tap];
        [self tapVisible:@"Close search" app:app];
        for (NSNumber *language in @[@NO, @YES]) {
            BOOL zh = language.boolValue;
            if (zh) [self setChinese:YES fromChinese:NO app:app];
            NSString *prefix = [NSString stringWithFormat:@"ios-%@-%@", zh ? @"zh" : @"en", size];
            NSString *back = zh ? @"返回" : @"Back";
            [self capture:[prefix stringByAppendingString:@"-U02-hall"] app:app];
            [self tapVisible:zh ? @"搜索" : @"Search" app:app];
            XCUIElement *field = app.textFields.firstMatch;
            XCTAssertTrue([field waitForExistenceWithTimeout:10]); [field tap]; [field typeText:@"no_match_fixture"];
            [self capture:[prefix stringByAppendingString:@"-U05-search-keyboard"] app:app];
            [self tapVisible:zh ? @"关闭搜索" : @"Close search" app:app];
            [self tapVisible:zh ? @"来源" : @"Sources" app:app];
            [self capture:[prefix stringByAppendingString:@"-U09-sources"] app:app];
            XCUIElement *builtin = [self element:zh ? @"内置" : @"Built-in" app:app];
            for (NSUInteger attempt = 0; !builtin.hittable && attempt < 4; ++attempt) [app swipeUp];
            XCTAssertTrue(builtin.hittable, @"Built-in source must be readable after scrolling");
            [self capture:[prefix stringByAppendingString:@"-U09-sources-tail"] app:app];
            [self tapVisible:back app:app];
            [self tapVisible:zh ? @"设置" : @"Settings" app:app];
            BOOL compact = app.frame.size.width < 720;
            NSArray *sections = zh ? @[@"显示", @"操作", @"音频", @"游戏语言", @"关于"]
                                    : @[@"Display", @"Controls", @"Audio", @"Game & language", @"About"];
            for (NSString *section in sections) {
                [self tapVisible:section app:app];
                [self capture:[prefix stringByAppendingFormat:@"-U14-%@", section] app:app];
                if ([section isEqual:sections[1]]) {
                    [self scrollControlsToEnd:app chinese:zh];
                    [self tapVisible:zh ? @"重置操作设置" : @"Reset controls" app:app];
                    [self capture:[prefix stringByAppendingString:@"-U21-reset-confirm"] app:app];
                    [self tapVisible:zh ? @"取消" : @"Cancel" app:app];
                    XCUIElement *reset = [self element:zh ? @"重置操作设置" : @"Reset controls" app:app];
                    XCTAssertTrue(reset.hittable);
                    [self capture:[prefix stringByAppendingString:@"-U16-controls-tail"] app:app];
                }
                if (compact && ![section isEqual:sections.lastObject]) [self tapVisible:back app:app];
            }
            [self tapVisible:zh ? @"许可" : @"Licenses" app:app];
            if (compact) [self tapVisible:@"Nestopia UE" app:app];
            XCTAssertTrue([[self element:zh ? @"复制许可" : @"Copy license" app:app] waitForExistenceWithTimeout:10]);
            [self capture:[prefix stringByAppendingString:@"-U20-license"] app:app];
            [app swipeUp];
            [self capture:[prefix stringByAppendingString:@"-U20-license-scrolled"] app:app];
            [self tapVisible:back app:app];
            if (compact) { [self tapVisible:back app:app]; [self tapVisible:back app:app]; }
            [self tapVisible:back app:app];
            if (zh) [self setChinese:NO fromChinese:YES app:app];
        }
        [app terminate];
    }
}
- (void)testStableControlsEndEnglishChinese {
    XCUIApplication *app = [self launchEnglish];
    [app terminate];
    app.launchArguments = [app.launchArguments arrayByAddingObjectsFromArray:
        @[@"-UIPreferredContentSizeCategoryName", @"UICTContentSizeCategoryL"]];
    [app launch];
    for (NSNumber *language in @[@NO, @YES]) {
        BOOL zh = language.boolValue;
        if (zh) [self setChinese:YES fromChinese:NO app:app];
        [self tapVisible:zh ? @"设置" : @"Settings" app:app];
        [self tapVisible:zh ? @"操作" : @"Controls" app:app];
        [self scrollControlsToEnd:app chinese:zh];
        NSString *prefix = [NSString stringWithFormat:@"ios-%@-UICTContentSizeCategoryL", zh ? @"zh" : @"en"];
        [self tapVisible:zh ? @"重置操作设置" : @"Reset controls" app:app];
        [self capture:[prefix stringByAppendingString:@"-U21-reset-confirm"] app:app];
        [self tapVisible:zh ? @"取消" : @"Cancel" app:app];
        [self capture:[prefix stringByAppendingString:@"-U16-controls-tail"] app:app];
        [self tapVisible:zh ? @"返回" : @"Back" app:app];
        if (app.frame.size.width < 720) [self tapVisible:zh ? @"返回" : @"Back" app:app];
        if (zh) [self setChinese:NO fromChinese:YES app:app];
    }
}
- (void)testTwentyGameReturnsAndPausedBackgroundKeepOwnersBounded {
    XCUIApplication *app = [self launchEnglish];
    [app terminate];
    app.launchArguments = [app.launchArguments arrayByAddingObject:@"-flynes.test.product_diagnostics"];
    [app launch];
    XCTAssertTrue([app.buttons[@"Built-in"] waitForExistenceWithTimeout:25]);
    [app.buttons[@"Built-in"] tap];
    NSMutableSet *sessions = [NSMutableSet set];
    for (NSUInteger index = 0; index < 20; ++index) {
        XCUIElement *launch = [app.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label IN %@", @[@"Start", @"Continue"]]].firstMatch;
        XCTAssertTrue([launch waitForExistenceWithTimeout:15]); [launch tap];
        XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
        [self tapVisible:@"NES_START" app:app];
        [app.buttons[@"OPEN_PAUSE"] tap];
        XCTAssertTrue([app.buttons[@"resume"] waitForExistenceWithTimeout:10]);
        NSDictionary *paused = [self sessionDiagnostics];
        XCTAssertEqualObjects(paused[@"coreOwnerCount"], @1);
        XCTAssertEqualObjects(paused[@"engineCount"], @1);
        XCTAssertEqualObjects(paused[@"activeFlutterViews"], @0);
        XCTAssertEqualObjects(paused[@"romLoadCount"], @1);
        XCTAssertGreaterThan([paused[@"frameSequence"] unsignedLongLongValue], 0u);
        XCTAssertFalse([sessions containsObject:paused[@"gameSessionId"]]);
        [sessions addObject:paused[@"gameSessionId"]];
        if (index % 5 == 0) {
            [self capture:[NSString stringWithFormat:@"U26-ios-game-%lu", (unsigned long)index] app:app];
            [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome]; [app activate];
            XCTAssertTrue([app.buttons[@"resume"] waitForExistenceWithTimeout:10]);
            XCTAssertEqualObjects([self sessionDiagnostics][@"frameSequence"], paused[@"frameSequence"]);
        }
        [app.buttons[@"game_center"] tap];
        XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
        NSPredicate *released = [NSPredicate predicateWithBlock:^BOOL(id ignored, NSDictionary *bindings) {
            NSDictionary *state = [self sessionDiagnostics];
            return [state[@"coreOwnerCount"] unsignedIntegerValue] == 0 &&
                   [state[@"activeFlutterViews"] unsignedIntegerValue] == 1;
        }];
        XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:released object:app];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:10], XCTWaiterResultCompleted);
    }
    [self capture:@"U24-ios-twenty-game-returns" app:app];
}

@end

@interface FlutterUpgradeUITests : FlutterProductUIBase
@end
@implementation FlutterUpgradeUITests
// Pair with ProductImportUITests/testSeedNativeToFlutterUpgradeThroughRealPicker.
// Install over that app, compare persistent bytes BEFORE launching this test.
- (void)testCoveringUpgradeKeepsImportedProgressSettingsAndAuthorization {
    XCUIApplication *app = [self launchEnglish];
    [self tapVisible:@"Favorites" app:app];
    XCTAssertTrue([[self element:@"FlyNES-E2E-Single" app:app] waitForExistenceWithTimeout:15]);
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
    [self capture:@"upgrade-flutter-favorite-continue" app:app];
    [self tapVisible:@"Sources" app:app];
    XCUIElement *source = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:
        [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"FlyNES-E2E-Single.nes"]].firstMatch;
    XCTAssertTrue([source waitForExistenceWithTimeout:15]);
    [self capture:@"upgrade-flutter-source-authorization" app:app];
    [self tapVisible:@"Back" app:app];
    [self tapVisible:@"Settings" app:app];
    [self tapVisible:@"Audio" app:app];
    XCUIElement *sound = [self element:@"Sound" app:app];
    XCTAssertTrue([sound waitForExistenceWithTimeout:10]);
    XCTAssertEqualObjects([sound.value description], @"0", @"Persisted audio-off survives covering install");
    [self capture:@"upgrade-flutter-persisted-audio" app:app];
    [self tapVisible:@"Back" app:app];
    if (app.frame.size.width < 720) [self tapVisible:@"Back" app:app];
    [app.buttons[@"Continue"] tap];
    XCTAssertTrue([app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15],
                  @"The old bookmark must still read the imported ROM and restore its checkpoint");
    [app.buttons[@"OPEN_PAUSE"] tap];
    [self capture:@"upgrade-imported-game-restored" app:app];
    [app.buttons[@"game_center"] tap];
    XCTAssertTrue([app.buttons[@"Continue"] waitForExistenceWithTimeout:15]);
}
@end

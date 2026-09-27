#import <XCTest/XCTest.h>

@interface NearbyUiParityTests : XCTestCase
@end

@implementation NearbyUiParityTests

- (XCUIApplication *)launchApp {
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US"];
    [app launch];
    return app;
}

- (XCUIElement *)element:(NSString *)identifier inApp:(XCUIApplication *)app {
    return [[app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:identifier].firstMatch;
}

- (void)openNearby:(XCUIApplication *)app {
    XCUIElement *entry = [self element:@"open_nearby" inApp:app];
    XCTAssertTrue([entry waitForExistenceWithTimeout:15]);
    [entry tap];
    XCTAssertTrue([[self element:@"nearby_root" inApp:app] waitForExistenceWithTimeout:10]);
}

- (void)testEntryOffersOnlyCreateAndScan {
    XCUIApplication *app = [self launchApp];
    [self openNearby:app];
    XCTAssertTrue([self element:@"nearby_action_create" inApp:app].exists);
    XCTAssertTrue([self element:@"nearby_action_scan_qr" inApp:app].exists);
    XCTAssertFalse([self element:@"nearby_entry_headline" inApp:app].exists);
    XCTAssertFalse([self element:@"nearby_entry_subtitle" inApp:app].exists);
    XCTAssertFalse([self element:@"nearby_action_enter_code" inApp:app].exists);
    XCTAssertFalse([self element:@"nearby_tab_friends" inApp:app].exists);
}

- (void)testGameCenterExposesIndependentMultiplayerFilter {
    XCUIApplication *app = [self launchApp];
    XCTAssertTrue([[self element:@"nearby_entry_text" inApp:app]
        waitForExistenceWithTimeout:15]);
    XCUIElement *filter = [self element:@"nearby_multiplayer_filter" inApp:app];
    XCTAssertTrue([filter waitForExistenceWithTimeout:5]);
    NSString *before = [filter.value description];
    [filter tap];
    XCTAssertNotEqualObjects([filter.value description], before);
    [filter tap];
    XCTAssertEqualObjects([filter.value description], before);
}

- (void)testScanOpensCameraDirectly {
    XCUIApplication *app = [self launchApp];
    [self openNearby:app];
    [[self element:@"nearby_action_scan_qr" inApp:app] tap];
    XCTAssertTrue([[self element:@"nearby_camera_preview" inApp:app]
        waitForExistenceWithTimeout:10]);
    XCTAssertFalse([self element:@"nearby_join_code_input" inApp:app].exists);
}

- (void)testSimulatorScannerFailureRequiresExplicitRetryAndCanExit {
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIApplication *app = [self launchApp];
    [self openNearby:app];
    [[self element:@"nearby_action_scan_qr" inApp:app] tap];
    XCUIElement *status = [self element:@"nearby_pairing_status" inApp:app];
    NSPredicate *unavailable = [NSPredicate predicateWithFormat:
        @"label == %@", @"Camera unavailable. Check permission and try again."];
    [self expectationForPredicate:unavailable evaluatedWithObject:status handler:nil];
    [self waitForExpectationsWithTimeout:10 handler:nil];
    XCUIElement *retry = [self element:@"nearby_scan_retry" inApp:app];
    XCTAssertTrue(retry.isHittable);
    XCTAssertTrue(CGRectContainsRect(app.windows.firstMatch.frame, retry.frame));
    [retry tap];
    [self expectationForPredicate:unavailable evaluatedWithObject:status handler:nil];
    [self waitForExpectationsWithTimeout:10 handler:nil];
    [[self element:@"nearby_invite_disconnect" inApp:app] tap];
    XCTAssertTrue([[self element:@"nearby_action_scan_qr" inApp:app] waitForExistenceWithTimeout:5]);
}

- (void)testLobbyHasNoEntryConfirmation {
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-flynes.test.nearby_lobby", @"-AppleLanguages", @"(en)"];
    [app launch];
    XCTAssertTrue([[self element:@"nearby_lobby_row_rom_identity" inApp:app]
        waitForExistenceWithTimeout:10]);
    XCTAssertFalse([self element:@"nearby_lobby_confirm" inApp:app].exists);
    XCTAssertTrue([self element:@"nearby_lobby_leave" inApp:app].exists);
    XCTAssertFalse(app.staticTexts[@"CONFIGURED"].exists);
    XCTAssertFalse(app.staticTexts[@"READY"].exists);
    XCTAssertFalse(app.staticTexts[@"WAITING"].exists);
    XCTAssertEqual(app.scrollViews.count, 0);
}

- (void)testRealLibraryRouteKeepsLobbyPickerAndDisconnectNavigation {
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-flynes.test.nearby_host_lobby_route", @"-AppleLanguages", @"(en)"];
    [app launch];
    XCUIElement *choose = [self element:@"nearby_lobby_choose_game" inApp:app];
    XCTAssertTrue([choose waitForExistenceWithTimeout:10]);
    XCTAssertTrue([self element:@"nearby_lobby_disconnect" inApp:app].exists);
    [choose tap];
    XCTAssertTrue([[self element:@"nearby_library_return_to_room" inApp:app]
        waitForExistenceWithTimeout:10]);
    [[self element:@"nearby_library_return_to_room" inApp:app] tap];
    XCTAssertTrue([choose waitForExistenceWithTimeout:10]);
    [app.buttons[@"nearby_lobby_disconnect"] tap];
    XCTAssertTrue([[self element:@"nearby_action_create" inApp:app]
        waitForExistenceWithTimeout:10]);
}

- (void)testActiveConnectionAtRoleEntryReturnsToEmptyLobby {
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    app.launchArguments = @[@"-flynes.test.nearby_role_connected", @"-AppleLanguages", @"(en)"];
    [app launch];
    XCUIElement *choose = [self element:@"nearby_lobby_choose_game" inApp:app];
    XCTAssertTrue([choose waitForExistenceWithTimeout:10]);
    XCTAssertEqualObjects(choose.label, @"Choose game");
    XCTAssertFalse([self element:@"nearby_lobby_confirm" inApp:app].exists);
}

@end

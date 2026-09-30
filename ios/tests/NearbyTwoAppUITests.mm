#import <XCTest/XCTest.h>

// Two separate UI runners and App processes. Pairing injects the real host QR
// payload at the native join boundary; camera decoding is outside this test.
@interface NearbyTwoAppUITests : XCTestCase
@property(nonatomic, strong) XCUIApplication *app;
@property(nonatomic, copy) NSString *runID;
@property(nonatomic, copy) NSString *role;
@property(nonatomic, copy) NSString *coordination;
@property(nonatomic, copy) NSString *container;
@property(nonatomic, copy) NSArray<NSDictionary *> *games;
@end

@implementation NearbyTwoAppUITests
- (XCUIElement *)element:(NSString *)identifier {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:identifier].firstMatch;
}
- (void)tap:(NSString *)identifier {
    XCUIElement *item = [self element:identifier];
    XCTAssertTrue([item waitForExistenceWithTimeout:15], @"Missing action %@", identifier);
    XCTAssertTrue(item.hittable, @"Action %@ must be operable", identifier); [item tap];
}
- (void)flutter:(NSString *)label {
    XCUIElement *item = [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
        @"label == %@ OR label BEGINSWITH %@", label, [label stringByAppendingString:@"\n"]]].firstMatch;
    XCTAssertTrue([item waitForExistenceWithTimeout:15]); XCTAssertTrue(item.hittable); [item tap];
}
- (NSString *)local:(NSString *)suffix {
    return [self.container stringByAppendingPathComponent:[NSString stringWithFormat:
        @"tmp/nearby-two-%@-%@", self.runID, suffix]];
}
- (NSDictionary *)status {
    NSString *applications = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    NSDictionary *found = nil;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:applications error:nil]) {
        NSString *candidate = [applications stringByAppendingPathComponent:name];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[candidate stringByAppendingPathComponent:
            @".com.apple.mobile_container_manager.metadata.plist"]];
        if (![metadata[@"MCMMetadataIdentifier"] isEqual:@"com.flynes.app"]) continue;
        NSString *path = [candidate stringByAppendingPathComponent:[NSString stringWithFormat:
            @"tmp/nearby-two-%@-state.plist", self.runID]];
        NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![state[@"run"] isEqual:self.runID] || ![state[@"role"] isEqual:self.role]) continue;
        if (found) return @{};
        found = state; self.container = candidate;
    }
    return found ?: @{};
}
- (void)wait:(BOOL (^)(void))predicate message:(NSString *)message {
    NSPredicate *condition = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return predicate();
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:condition object:self];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:60], XCTWaiterResultCompleted, @"%@", message);
}
- (void)capture:(NSString *)phase {
    [NSThread sleepForTimeInterval:0.35];
    NSString *name = [NSString stringWithFormat:@"two-app-%@-%@", self.role, phase];
    XCTAttachment *image = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    image.name = name; image.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:image];
    XCTAttachment *tree = [XCTAttachment attachmentWithString:self.app.debugDescription];
    tree.name = [name stringByAppendingString:@"-semantics"]; tree.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:tree];
}
- (void)barrier:(NSString *)phase {
    NSMutableDictionary *record = [[self status] mutableCopy]; record[@"phase"] = phase;
    NSString *own = [self.coordination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.plist", self.role, phase]];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:own]);
    XCTAssertTrue([record writeToFile:own atomically:YES]);
    NSString *otherRole = [self.role isEqual:@"host"] ? @"guest" : @"host";
    NSString *other = [self.coordination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.plist", otherRole, phase]];
    [self wait:^BOOL {
        NSDictionary *peer = [NSDictionary dictionaryWithContentsOfFile:other];
        return [peer[@"run"] isEqual:self.runID] && [peer[@"role"] isEqual:otherRole] &&
            [peer[@"phase"] isEqual:phase] && [peer[@"pid"] intValue] > 0 &&
            ![peer[@"pid"] isEqual:record[@"pid"]];
    } message:[@"Two independent Apps reach " stringByAppendingString:phase]];
}
- (void)launch:(NSString *)role {
    self.continueAfterFailure = NO; self.role = role;
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    self.runID = environment[@"FLYNES_TWO_APP_RUN"];
    self.coordination = environment[@"FLYNES_TWO_APP_COORDINATION"];
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:self.runID]);
    XCTAssertGreaterThan(self.coordination.length, 0u);
    XCTAssertEqualObjects(environment[@"FLYNES_TWO_APP_ROLE"], role);
    NSDictionary *identity = [NSDictionary dictionaryWithContentsOfFile:[self.coordination stringByAppendingPathComponent:@"identity.plist"]];
    XCTAssertEqualObjects(identity[@"run"], self.runID);
    NSData *data = [NSData dataWithContentsOfURL:[[NSBundle bundleForClass:self.class] URLForResource:@"builtin-games" withExtension:@"json"]];
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    self.games = [manifest[@"games"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *game, NSDictionary *bindings) {
        return [game[@"multiplayerProfile"][@"eligibility"] isEqual:@"SUPPORTED"] && [game[@"multiplayerProfile"][@"maxPlayers"] intValue] >= 2;
    }]];
    XCTAssertGreaterThanOrEqual(self.games.count, 2u);
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    self.app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    self.app.launchEnvironment = @{@"FLYNES_TWO_APP_RUN": self.runID, @"FLYNES_TWO_APP_ROLE": role};
    self.app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US", @"-flynes.test.product_diagnostics"];
    [self.app launch];
    [self wait:^BOOL { return [[self status][@"pid"] intValue] > 0; } message:@"Debug diagnostics must observe this real App, not an in-process test peer"];
    XCTAssertEqualObjects([self status][@"error"], @"");
    XCTAssertTrue([[self element:@"flutter_product_surface"] waitForExistenceWithTimeout:25]);
    // Dedicated task simulators must be left in English; do not alter durable preferences.
    [self flutter:@"Nearby"];
    if ([role isEqual:@"host"]) {
        [self tap:@"nearby_action_create"];
        XCTAssertTrue([[self element:@"nearby_invite_qr"] waitForExistenceWithTimeout:20]);
        [self wait:^BOOL { return [NSFileManager.defaultManager fileExistsAtPath:[self local:@"invite.txt"]]; } message:@"Host publishes its actual QR payload"];
        NSData *invite = [NSData dataWithContentsOfFile:[self local:@"invite.txt"]];
        NSString *shared = [self.coordination stringByAppendingPathComponent:@"invite.secret"];
        XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:shared]);
        XCTAssertTrue([NSFileManager.defaultManager createFileAtPath:shared contents:invite attributes:@{NSFilePosixPermissions: @0600}]);
    } else {
        [self tap:@"nearby_action_scan_qr"];
        XCTAssertTrue([[self element:@"nearby_camera_preview"] waitForExistenceWithTimeout:10]);
        NSString *shared = [self.coordination stringByAppendingPathComponent:@"invite.secret"];
        [self wait:^BOOL { return [NSFileManager.defaultManager fileExistsAtPath:shared]; } message:@"Real host invitation available"];
        NSData *invite = [NSData dataWithContentsOfFile:shared];
        XCTAssertGreaterThan(invite.length, 0u);
        XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[self local:@"join.txt"]]);
        XCTAssertTrue([NSFileManager.defaultManager createFileAtPath:[self local:@"join.txt"] contents:invite attributes:@{NSFilePosixPermissions: @0600}]);
    }
    [self wait:^BOOL { return [[self status][@"snapshot"][@"state"] intValue] == 3; } message:@"Real transport paired before any game selection"];
    XCTAssertTrue([[self element:@"nearby_lobby_row_rom_identity"] waitForExistenceWithTimeout:15]);
    XCTAssertEqual([[self status][@"replaceCount"] intValue], 1);
    [self capture:@"paired-room"]; [self barrier:@"paired"];
}
- (void)choose:(NSDictionary *)game phase:(NSString *)phase {
    [self tap:@"nearby_lobby_choose_game"];
    XCTAssertTrue([[self element:@"flutter_product_surface"] waitForExistenceWithTimeout:15]);
    if ([self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"Close search"]].count)
        [self flutter:@"Close search"];
    [self flutter:@"Built-in"]; [self flutter:@"Search"];
    XCUIElement *field = self.app.textFields[@"Search games"];
    XCTAssertTrue([field waitForExistenceWithTimeout:10]); [field tap]; [field typeText:game[@"titleEn"]];
    [self.app.keyboards.buttons[@"done"] tap]; [self flutter:game[@"titleEn"]];
    [self capture:phase]; [self flutter:@"Choose game"];
}
- (void)running:(NSDictionary *)game after:(unsigned long long)frame {
    NSString *key = [@"game:" stringByAppendingString:[game[@"romSha256"] uppercaseString]];
    [self wait:^BOOL {
        NSDictionary *status = [self status]; NSDictionary *state = status[@"snapshot"];
        return [state[@"state"] intValue] == 6 && ![state[@"paused"] boolValue] &&
            [state[@"completedFrames"] unsignedLongLongValue] > frame && [status[@"key"] isEqual:key];
    } message:@"Selected game advances in this real App"];
    XCTAssertTrue([[self element:@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
}
- (NSNumber *)input:(NSDictionary *)game {
    NSDictionary *before = [self status];
    [self pressGameControl:@"NES_A" game:game duration:0.5];
    [self running:game after:[before[@"snapshot"][@"completedFrames"] unsignedLongLongValue] + 10];
    return @([[self status][@"nonzeroInputCount"] unsignedLongLongValue] - [before[@"nonzeroInputCount"] unsignedLongLongValue]);
}
- (void)recordInputAttempt:(NSString *)identifier button:(XCUIElement *)button
                    before:(NSDictionary *)before phase:(NSString *)phase capture:(BOOL)capture {
    NSString *name = [NSString stringWithFormat:@"input-%@-%@-%llu-%@", self.role, identifier,
        [before[@"appliedInputSerial"] unsignedLongLongValue], phase];
    const BOOL exists = button.exists;
    NSMutableDictionary *evidence = [@{@"run":self.runID, @"role":self.role,
        @"control":identifier, @"phase":phase, @"before":before, @"state":[self status],
        @"buttonExists":@(exists), @"buttonHittable":@(exists && button.hittable),
        @"buttonFrame":exists ? NSStringFromCGRect(button.frame) : @"missing",
        @"screenFrame":NSStringFromCGRect(self.app.frame),
        @"orientation":@(XCUIDevice.sharedDevice.orientation)} mutableCopy];
    if (capture) {
        evidence[@"selectedButton"] = exists ? button.debugDescription : @"missing";
        NSString *tree = self.app.debugDescription;
        XCTAssertTrue([tree writeToFile:[self.coordination stringByAppendingPathComponent:
            [name stringByAppendingString:@"-semantics.txt"]] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        XCTAssertTrue([XCUIScreen.mainScreen.screenshot.PNGRepresentation writeToFile:
            [self.coordination stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES]);
    }
    // Persist before the peer's barrier timeout can terminate this runner while
    // xcresult is still finalizing. This observes one touch, never retries it.
    XCTAssertTrue([evidence writeToFile:[self.coordination stringByAppendingPathComponent:
        [name stringByAppendingString:@".plist"]] atomically:YES]);
}
- (void)pressGameControl:(NSString *)identifier game:(NSDictionary *)game duration:(NSTimeInterval)duration {
    NSDictionary *beforeState = [self status];
    NSNumber *before = beforeState[@"nonzeroInputCount"];
    XCTAssertNotNil(beforeState[@"appliedInputSerial"], @"Use the test-only core transition observer");
    NSDictionary *masks = @{@"NES_A":@1, @"NES_B":@2, @"NES_SELECT":@4, @"NES_START":@8,
        @"NES_UP":@16, @"NES_DOWN":@32, @"NES_LEFT":@64, @"NES_RIGHT":@128};
    NSNumber *mask = masks[identifier]; XCTAssertNotNil(mask);
    NSString *player = [self.role isEqual:@"host"] ? @"p1" : @"p2";
    uint64_t afterSerial = [beforeState[@"appliedInputSerial"] unsignedLongLongValue];
    XCUIElement *button = [self element:identifier];
    XCTAssertTrue([button waitForExistenceWithTimeout:10]); XCTAssertTrue(button.hittable);
    [self recordInputAttempt:identifier button:button before:beforeState phase:@"before"
        capture:([identifier isEqual:@"NES_START"] && afterSerial == 0)];
    [button pressForDuration:duration]; // XCTest releases the actual touch before returning.
    const BOOL acceptedAtReturn = [[self status][@"nonzeroInputCount"] unsignedLongLongValue] > before.unsignedLongLongValue;
    [self recordInputAttempt:identifier button:button before:beforeState phase:@"after"
        capture:!acceptedAtReturn];
    [self wait:^BOOL { return [[self status][@"nonzeroInputCount"] unsignedLongLongValue] > before.unsignedLongLongValue; }
        message:[@"Actual UI press accepted: " stringByAppendingString:identifier]];
    // A successful submission and later advancing frames do not prove that
    // this short pulse reached a core, even with the bounded transition FIFO.
    // Stop at the first missing mask/zero edge instead of navigating blindly.
    __block uint64_t releasedFrame = 0;
    NSPredicate *appliedRelease = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        BOOL pressed = NO; uint64_t pressedFrame = 0;
        for (NSDictionary *edge in [self status][@"appliedInputEdges"]) {
            if ([edge[@"serial"] unsignedLongLongValue] <= afterSerial) continue;
            if ([edge[player] isEqual:mask]) {
                pressed = YES; pressedFrame = [edge[@"frame"] unsignedLongLongValue];
            } else if (pressed && [edge[player] unsignedIntValue] == 0 &&
                       [edge[@"frame"] unsignedLongLongValue] > pressedFrame) {
                releasedFrame = [edge[@"frame"] unsignedLongLongValue]; return YES;
            }
        }
        return NO;
    }];
    XCTNSPredicateExpectation *observed = [[XCTNSPredicateExpectation alloc] initWithPredicate:appliedRelease object:nil];
    XCTWaiterResult result = [XCTWaiter waitForExpectations:@[observed] timeout:10];
    NSDictionary *evidence = @{@"control":identifier, @"role":self.role, @"mask":mask,
        @"afterSerial":@(afterSerial), @"duration":@(duration), @"releasedFrame":@(releasedFrame),
        @"state":[self status]};
    XCTAttachment *trace = [XCTAttachment attachmentWithString:evidence.description];
    trace.name = [NSString stringWithFormat:@"input-apply-%@-%@-%llu", self.role, identifier, (unsigned long long)afterSerial];
    trace.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:trace];
    if (result != XCTWaiterResultCompleted) [self capture:[@"missing-core-release-" stringByAppendingString:identifier]];
    XCTAssertEqual(result, XCTWaiterResultCompleted, @"%@ must reach actual %@ core input, then a later zero-input frame", identifier, player);
    [self running:game after:releasedFrame + 4];
}
- (void)settleGame:(NSDictionary *)game frames:(unsigned long long)frames {
    unsigned long long current = [[self status][@"snapshot"][@"completedFrames"] unsignedLongLongValue];
    [self running:game after:current + frames];
}
- (void)beginPinnedTwoHumanMatch:(NSDictionary *)game host:(BOOL)host {
    // This menu script is for exactly the licensed ROM pinned by sources.lock.json,
    // not an assumption about whichever game happens to sort first in future.
    XCTAssertEqualObjects(game[@"canonicalId"], @"builtin:super-tilt-bro");
    XCTAssertEqualObjects(game[@"romSha256"], @"6f80d56ce0b242a4faceafafea321feb1c364ab8e7937646e8580ae9289a4ec3");
    XCTAssertEqualObjects(game[@"license"][@"sourceRevision"], @"b132fd25add46f816e04be64c434386743b84b8b");
    [self running:game after:180];
    [self capture:@"first-game-title"];
    [self barrier:@"first-game-title-ready"];
    // A cold nearby generation starts at TITLE, not CONFIG. Pinned title code
    // accepts a release to MODE_SELECTION; global_init selected LOCAL0.
    if (host) [self pressGameControl:@"NES_START" game:game duration:0.15];
    [self barrier:@"first-game-title-advanced"];
    [self settleGame:game frames:90];
    [self capture:@"first-game-mode-local"];
    [self barrier:@"first-game-mode-ready"];
    // Pinned mode_selection START release chooses LOCAL and enters CONFIG.
    if (host) [self pressGameControl:@"NES_START" game:game duration:0.15];
    [self barrier:@"first-game-mode-advanced"];
    [self settleGame:game frames:90];
    [self capture:@"first-game-options-before"];
    [self barrier:@"first-game-options-ready"];
    if (host) {
        // Pinned config_screen: selected option0, AI1; DOWN twice selects AI,
        // LEFT changes EASY1 to HUMAN0. RIGHT would require three releases.
        [self pressGameControl:@"NES_DOWN" game:game duration:0.15];
        [self pressGameControl:@"NES_DOWN" game:game duration:0.15];
        [self pressGameControl:@"NES_LEFT" game:game duration:0.15];
    }
    [self barrier:@"first-game-human-configured"];
    [self capture:@"first-game-options-human"];
    [self barrier:@"first-game-human-evidence"];
    if (host) [self pressGameControl:@"NES_START" game:game duration:0.15];
    [self barrier:@"first-game-options-advanced"];
    [self settleGame:game frames:90];
    [self capture:@"first-game-character-selection"];
    [self barrier:@"first-game-characters-ready"];
    // With HUMAN0, each real controller confirms its own character on release.
    [self pressGameControl:@"NES_A" game:game duration:0.15];
    [self barrier:@"first-game-both-characters-confirmed"];
    [self settleGame:game frames:90];
    [self capture:@"first-game-stage-selection"];
    [self barrier:@"first-game-stage-ready"];
    if (host) [self pressGameControl:@"NES_START" game:game duration:0.15];
    [self barrier:@"first-game-stage-started"];
    [self settleGame:game frames:240]; // Finish the real game's opening countdown.
    [self capture:@"first-game-match-before-input"];
    [self barrier:@"first-game-match-ready"];
    // Runtime RUNNING alone cannot distinguish a ROM menu from its match. These
    // uniquely named actual images require arena/fighter review before sign-off.
}
- (void)room:(NSString *)phase {
    if (![self element:@"game_center"].exists) [self tap:@"OPEN_PAUSE"];
    XCTAssertEqualObjects([self element:@"game_center"].label, @"Return to room");
    [self tap:@"game_center"];
    XCTAssertTrue([[self element:@"nearby_lobby_resume"] waitForExistenceWithTimeout:15]);
    [self wait:^BOOL { return [[self status][@"snapshot"][@"paused"] boolValue]; } message:@"Retained paused game"];
    [self capture:phase];
}
- (void)exercise:(NSString *)role {
    [self launch:role]; BOOL host = [role isEqual:@"host"];
    NSDictionary *first = self.games[0], *second = self.games[1];
    if (host) [self choose:first phase:@"first-game-flutter-selection"];
    [self running:first after:20];
    NSNumber *firstGeneration = [self status][@"generation"];
    [self beginPinnedTwoHumanMatch:first host:host];
    NSNumber *menuInputCount = [self status][@"nonzeroInputCount"];
    [self pressGameControl:(host ? @"NES_RIGHT" : @"NES_LEFT") game:first duration:0.3];
    NSNumber *movementDelta = @([[self status][@"nonzeroInputCount"] unsignedLongLongValue] - menuInputCount.unsignedLongLongValue);
    [self capture:@"first-game-match-after-movement"];
    [self barrier:@"first-game-movement"];
    NSNumber *firstInput = [self input:first]; [self capture:@"first-game-match-after-action"]; [self barrier:@"first-input"];
    if (!host) [self wait:^BOOL { return [[self status][@"snapshot"][@"paused"] boolValue]; } message:@"Host pauses both Apps"];
    [self room:@"paused-room"]; [self barrier:@"paused"];
    unsigned long long pausedFrame = [[self status][@"snapshot"][@"completedFrames"] unsignedLongLongValue];
    if (!host) [self tap:@"nearby_lobby_resume"];
    [self running:first after:pausedFrame + 10];
    NSNumber *resumed = [self status][@"generation"];
    XCTAssertEqualObjects(firstGeneration, resumed); [self capture:@"continued"]; [self barrier:@"continued"];
    if (!host) [self wait:^BOOL { return [[self status][@"snapshot"][@"paused"] boolValue]; } message:@"Host pauses before switching"];
    [self room:@"switch-room"]; [self barrier:@"switch-room"];
    if (host) [self choose:second phase:@"second-game-flutter-selection"];
    [self running:second after:20]; NSNumber *secondInput = [self input:second];
    NSNumber *secondGeneration = [self status][@"generation"];
    XCTAssertGreaterThan(secondGeneration.unsignedLongLongValue, firstGeneration.unsignedLongLongValue);
    XCTAssertEqual([[self status][@"replaceCount"] intValue], 1, @"Game change must retain the connection");
    [self capture:@"second-game-input"]; [self barrier:@"second-input"];
    NSMutableDictionary *done = [[self status] mutableCopy];
    [done addEntriesFromDictionary:@{@"phase": @"done", @"firstInputDelta": firstInput, @"secondInputDelta": secondInput,
        @"firstGeneration": firstGeneration, @"resumedGeneration": resumed, @"secondGeneration": secondGeneration,
        @"menuInputCount": menuInputCount, @"firstMovementDelta": movementDelta,
        @"firstGameFixture": @{@"canonicalId": first[@"canonicalId"], @"romSha256": first[@"romSha256"],
                               @"sourceRevision": first[@"license"][@"sourceRevision"]},
        @"firstMatchEvidence": @"explicit-pinned-menu-sequence; arena screenshots require visual review"}];
    XCTAssertTrue([done writeToFile:[self.coordination stringByAppendingPathComponent:[role stringByAppendingString:@"-done.plist"]] atomically:YES]);
    [self barrier:@"finished"];
}
- (void)testHostFlutterSelectionAcrossTwoApps { [self exercise:@"host"]; }
- (void)testGuestInputAndContinueAcrossTwoApps { [self exercise:@"guest"]; }
@end

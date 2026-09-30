// Real Files -> production Flutter source flows. Run only on the dedicated
// simulator already upgraded in place from testSeedNativeToFlutterUpgradeThroughRealPicker.
// stage_import_fixtures.py must have staged its unchanged licensed fixtures.
// Single is an existing favorite with an autosave; Hundred must NOT be registered.
// Run with run_simulator_tests.py (FLYNES_TEST_APPLICATION_CONTAINERS). Missing
// prerequisites fail, never skip. No app state is seeded or deleted by this suite.
#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const FixtureRoot = @"FlyNES-Import-E2E-v1";
static NSString *const SingleSource = @"FlyNES-E2E-Single.nes";
static NSString *const HundredSource = @"FlyNES-E2E-Hundred";

@interface FlutterSourceUIBase : XCTestCase
@property(nonatomic, strong) XCUIApplication *app;
@property(nonatomic, copy) NSString *container;
@property(nonatomic, copy) NSArray<NSDictionary *> *baselineSources;
@property(nonatomic, copy) NSDictionary<NSString *, NSData *> *baselineSaves;
@property(nonatomic) NSUInteger baselineCount;
@property(nonatomic) BOOL ownsHundred;
@property(nonatomic) BOOL restoreSingle;
@end

@implementation FlutterSourceUIBase
- (void)waitFor:(BOOL (^)(void))condition reason:(NSString *)reason {
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return condition();
        }] object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:45], XCTWaiterResultCompleted,
                   @"%@: %@", reason, self.app.debugDescription);
}
- (void)capture:(NSString *)name {
    [NSThread sleepForTimeInterval:0.35];
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    shot.name = name; shot.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:shot];
    XCTAttachment *tree = [XCTAttachment attachmentWithString:self.app.debugDescription];
    tree.name = [name stringByAppendingString:@"-semantics"];
    tree.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:tree];
}
- (XCUIElement *)button:(NSString *)label {
    return [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
        @"label == %@ OR label BEGINSWITH %@", label, [label stringByAppendingString:@"\n"]]].firstMatch;
}
- (BOOL)enabledButton:(NSString *)label {
    XCUIElement *button = [self button:label];
    return button.exists && button.enabled;
}
- (XCUIElement *)text:(NSString *)label {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@ OR label BEGINSWITH %@", label,
            [label stringByAppendingString:@"\n"]]].firstMatch;
}
- (void)tap:(NSString *)label {
    XCUIElement *button = [self button:label];
    XCTAssertTrue([button waitForExistenceWithTimeout:15], @"Missing %@", label);
    for (NSUInteger n = 0; !button.hittable && n < 8; ++n) [self.app swipeUp];
    XCTAssertTrue(button.hittable, @"%@ must be actionable", label);
    XCTAssertFalse(CGRectIsEmpty(button.frame));
    XCTAssertTrue(CGRectContainsRect(self.app.frame, button.frame), @"%@ is clipped", label);
    [button tap];
}
- (NSString *)currentContainer {
    NSString *containers = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    XCTAssertGreaterThan(containers.length, 0u, @"Use run_simulator_tests.py");
    NSString *found = nil;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:containers error:nil]) {
        NSString *path = [containers stringByAppendingPathComponent:name];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
            [path stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([metadata[@"MCMMetadataIdentifier"] isEqual:@"com.flynes.app"]) {
            XCTAssertNil(found, @"Exactly one installed FlyNES container is required"); found = path;
        }
    }
    XCTAssertNotNil(found);
    self.container = found;
    return found;
}
- (NSDictionary *)preferences {
    [self currentContainer];
    NSDictionary *value = [NSDictionary dictionaryWithContentsOfFile:[self.container
        stringByAppendingPathComponent:@"Library/Preferences/com.flynes.app.plist"]];
    XCTAssertNotNil(value, @"Upgrade preferences must already exist");
    return value ?: @{};
}
- (NSArray<NSDictionary *> *)sources {
    id value = [self preferences][@"flynes.source_metadata_v1"];
    XCTAssertTrue([value isKindOfClass:NSArray.class]);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
- (NSDictionary *)sourceNamed:(NSString *)name in:(NSArray<NSDictionary *> *)rows {
    NSArray *matches = [rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", name]];
    XCTAssertLessThanOrEqual(matches.count, 1u, @"Duplicate source %@", name);
    return matches.firstObject;
}
- (NSDictionary<NSString *, NSData *> *)saves {
    [self currentContainer];
    NSString *root = [self.container stringByAppendingPathComponent:@"Documents/saves"];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *path in [NSFileManager.defaultManager enumeratorAtPath:root]) {
        if (![path.lastPathComponent isEqual:@"autosave.nst"]) continue;
        NSData *bytes = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:path]];
        XCTAssertGreaterThan(bytes.length, 0u, @"Legacy autosave must be readable");
        if (bytes) result[path] = bytes;
    }
    return result;
}
- (void)assertSavesRetained:(NSDictionary<NSString *, NSData *> *)before {
    NSDictionary *after = [self saves];
    for (NSString *path in before) XCTAssertEqualObjects(after[path], before[path], @"Preserve save %@", path);
}
- (void)assertExistingSourcesRetained {
    NSArray *current = [self sources];
    NSDictionary *bookmarks = [self preferences][@"flynes.source_uuid_bookmarks_v1"];
    for (NSDictionary *row in self.baselineSources) {
        NSArray *matches = [current filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"uuid == %@", row[@"uuid"]]];
        XCTAssertEqual(matches.count, 1u, @"Preserve existing source %@", row[@"name"]);
        XCTAssertEqualObjects(matches.firstObject[@"name"], row[@"name"]);
        XCTAssertEqualObjects(matches.firstObject[@"scope"], row[@"scope"]);
        if ([row[@"scope"] integerValue] != 1) XCTAssertNotNil(bookmarks[row[@"uuid"]]);
    }
    [self assertSavesRetained:self.baselineSaves];
}
- (void)launchHall {
    [self.app launch];
    XCTAssertTrue([self.app.otherElements[@"flutter_product_surface"] waitForExistenceWithTimeout:25]);
    XCTAssertTrue([[self button:@"Search"] waitForExistenceWithTimeout:15],
                  @"Upgrade fixture must use English product locale; AppleLanguages cannot override its saved preference");
    if ([self button:@"Close search"].exists) [self tap:@"Close search"];
    [self tap:@"All"];
    XCUIElement *filter = self.app.switches.firstMatch;
    XCTAssertTrue(filter.exists, @"Hall two-player filter must expose switch semantics");
    if (![[filter.value description] isEqual:@"0"]) [filter tap];
}
- (NSUInteger)gameCount {
    XCUIElement *count = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingPredicate:[NSPredicate predicateWithFormat:@"label MATCHES %@", @"[0-9]+ games · swipe to browse"]].firstMatch;
    XCTAssertTrue([count waitForExistenceWithTimeout:15]);
    return (NSUInteger)count.label.integerValue;
}
- (void)expectCount:(NSUInteger)expected {
    NSString *label = [NSString stringWithFormat:@"%lu games · swipe to browse", (unsigned long)expected];
    XCTAssertTrue([[self text:label] waitForExistenceWithTimeout:30], @"Expected canonical count %@", label);
}
- (void)search:(NSString *)query {
    if ([self button:@"Close search"].exists) [self tap:@"Close search"];
    [self tap:@"Search"];
    XCUIElement *field = self.app.textFields[@"Search games"];
    XCTAssertTrue([field waitForExistenceWithTimeout:10]);
    XCTAssertTrue(field.hittable); [field tap]; [field typeText:query];
    XCTAssertEqualObjects(field.value, query);
    XCUIElement *done = self.app.keyboards.buttons[@"done"];
    XCTAssertTrue([done waitForExistenceWithTimeout:5]); [done tap];
}
- (XCUIElement *)fixtureCard {
    XCUIElementQuery *cards = [self.app.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"FlyNES-E2E-"]];
    XCTAssertTrue([cards.firstMatch waitForExistenceWithTimeout:15]);
    XCTAssertEqual(cards.count, 1u, @"Filtered fixture must expose exactly one canonical card");
    return cards.firstMatch;
}
- (void)assertSingleFavoriteAndContinue {
    [self tap:@"Favorites"];
    [self search:@"FlyNES-E2E-Single"];
    [self expectCount:1];
    XCUIElement *card = [self fixtureCard]; XCTAssertTrue(card.hittable); [card tap];
    XCTAssertTrue([[self button:@"Continue"] waitForExistenceWithTimeout:15],
                  @"Existing Single favorite and legacy save must still resolve");
    [self capture:@"U12-flutter-source-existing-favorite-save"];
    [self tap:@"Close search"]; [self tap:@"All"];
}
- (void)openSources {
    [self tap:@"Sources"];
    XCTAssertTrue([[self button:@"Back"] waitForExistenceWithTimeout:15]);
}
- (BOOL)sourceRemovalComplete:(NSString *)uuid {
    for (NSDictionary *row in [self sources]) if ([row[@"uuid"] isEqual:uuid]) return NO;
    NSString *identifier = [@"source-remove-" stringByAppendingString:uuid];
    return ![[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:identifier].firstMatch.exists &&
        [self enabledButton:@"Back"];
}
- (XCUIElement *)pickerItem:(NSString *)name {
    NSString *stem = name.stringByDeletingPathExtension;
    return [self.app.cells matchingPredicate:[NSPredicate predicateWithFormat:
        @"identifier == %@ OR identifier == %@ OR label == %@ OR label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
        name, stem, name, stem, [name stringByAppendingString:@","], [stem stringByAppendingString:@","]]].firstMatch;
}
- (NSString *)pickerFixtureRoot { return FixtureRoot; }
- (void)cancelFilesPicker {
    // iOS16 restores the picker at On My iPhone: Browse is the back action,
    // and Cancel exists only at the picker root. Never confuse Open with cancel.
    XCUIElement *cancel = self.app.navigationBars.buttons[@"Cancel"];
    XCUIElement *browse = self.app.navigationBars.buttons[@"Browse"];
    [self waitFor:^BOOL { return cancel.exists || browse.exists; }
           reason:@"System Files picker navigation must be present"];
    if (!cancel.exists) {
        XCTAssertTrue(browse.hittable); [browse tap];
    }
    XCTAssertTrue([cancel waitForExistenceWithTimeout:10]);
    XCTAssertTrue(cancel.hittable); [cancel tap];
}
- (void)openFixtureRootInPicker {
    NSString *fixtureRoot = [self pickerFixtureRoot];
    for (NSUInteger attempt = 0; attempt < 8; ++attempt) {
        XCUIElement *root = [self pickerItem:fixtureRoot];
        if (root.exists && root.hittable) { [root tap]; return; }
        XCUIElement *local = self.app.cells[@"On My iPhone"];
        if (!local.exists) local = self.app.staticTexts[@"On My iPhone"];
        if (!local.exists) local = self.app.cells[@"On My iPad"];
        if (!local.exists) local = self.app.staticTexts[@"On My iPad"];
        if (local.exists && local.hittable) { [local tap]; continue; }
        XCUIElement *browse = self.app.tabBars.buttons[@"Browse"];
        if (browse.exists && browse.hittable && !browse.selected) { [browse tap]; continue; }
        XCUIElement *back = [self.app.navigationBars.buttons matchingPredicate:[NSPredicate predicateWithFormat:
            @"label IN %@", @[@"Browse", @"On My iPhone", @"On My iPad", fixtureRoot, @"Single", HundredSource,
                @"FlyNES-Gap-Directory", @"FlyNES-Gap-Failure", @"FlyNES-Gap-Replacement"]]].firstMatch;
        if ([back waitForExistenceWithTimeout:3] && back.hittable) { [back tap]; continue; }
        (void)[root waitForExistenceWithTimeout:3];
    }
    XCTFail(@"Stage the authorized fixture in Files' local provider first: %@", self.app.debugDescription);
}
- (void)pick:(NSString *)name directory:(BOOL)directory {
    [self tap:directory ? @"Add folder" : @"Add file"];
    [self openFixtureRootInPicker];
    if (!directory) {
        XCUIElement *single = [self pickerItem:@"Single"];
        XCTAssertTrue([single waitForExistenceWithTimeout:10]); [single tap];
    }
    XCUIElement *item = [self pickerItem:name];
    XCTAssertTrue([item waitForExistenceWithTimeout:10]); XCTAssertTrue(item.hittable); [item tap];
    XCUIElement *open = self.app.buttons[@"Open"];
    if (directory) {
        XCTAssertTrue([open waitForExistenceWithTimeout:5]); XCTAssertTrue(open.enabled);
        self.ownsHundred = YES; // Only after explicit absent-source precondition.
        [open tap];
    }
    // The production single-file picker returns immediately on tapping a file;
    // only folder selection needs the system Open action.
    [self waitFor:^BOOL {
        NSString *uuid = [self sourceNamed:name in:[self sources]][@"uuid"];
        if (!uuid) return NO;
        XCUIElement *remove = [[self.app descendantsMatchingType:XCUIElementTypeAny]
            matchingIdentifier:[@"source-remove-" stringByAppendingString:uuid]].firstMatch;
        return !self.app.buttons[@"Cancel"].exists && !self.app.buttons[@"Open"].exists &&
            remove.exists && remove.enabled && [self enabledButton:@"Back"]; }
           reason:@"Picker and application-owned import completed"];
    [self capture:directory ? @"U10-flutter-folder-imported" : @"U10-flutter-file-selected"];
}
- (void)tapOwnedHundredRemove {
    XCTAssertTrue(self.ownsHundred, @"Never remove a pre-existing source");
    NSDictionary *owned = [self sourceNamed:HundredSource in:[self sources]];
    XCTAssertTrue([owned[@"uuid"] length] > 0);
    NSString *identifier = [@"source-remove-" stringByAppendingString:owned[@"uuid"]];
    XCUIElement *candidate = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:identifier].firstMatch;
    XCTAssertTrue([candidate waitForExistenceWithTimeout:15], @"Remove must expose the exact source UUID");
    for (NSUInteger n = 0; !candidate.hittable && n < 14; ++n) {
        XCUICoordinate *start = [self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, 0.8)];
        [start pressForDuration:0.1 thenDragToCoordinate:[self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, 0.6)]];
    }
    // XCTest's native idle signal does not include a Flutter scroll simulation.
    // Wait for the exact control to stop moving before the one business tap;
    // otherwise the touch can merely stop the fling instead of activating it.
    CGRect previous = CGRectNull;
    NSUInteger stableSamples = 0;
    NSDate *scrollDeadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (stableSamples < 3 && scrollDeadline.timeIntervalSinceNow > 0) {
        CGRect current = candidate.frame;
        stableSamples = CGRectEqualToRect(previous, current) && candidate.hittable ? stableSamples + 1 : 0;
        previous = current;
        [NSThread sleepForTimeInterval:0.25];
    }
    XCTAssertEqual(stableSamples, 3u, @"Source button must have a stable hit target after Flutter scrolling");
    XCTAssertTrue(candidate.hittable, @"Only the registered source's Remove may be activated");
    XCTAssertTrue(CGRectContainsRect(self.app.frame, candidate.frame));
    [candidate tap];
    XCTAssertTrue([[self text:@"Remove source"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue([self text:@"Remove this source and its library entries? Original ROMs, saved progress and game preferences will be kept."].exists);
}
- (void)setUp {
    [super setUp]; self.continueAfterFailure = NO;
    [self currentContainer];
    self.baselineSources = [self sources]; self.baselineSaves = [self saves];
    NSDictionary *single = [self sourceNamed:SingleSource in:self.baselineSources];
    if ([NSStringFromClass(self.class) isEqual:@"FlutterSourceRecoveryUITests"]) {
        // Explicit recovery selector only, with an operator-recorded UUID from
        // this test's failed run. Ordinary tests still reject existing sources.
        NSString *marker = [self.container stringByAppendingPathComponent:@"tmp/g2-owned-source-recovery.json"];
        NSData *bytes = [NSData dataWithContentsOfFile:marker];
        XCTAssertNotNil(bytes, @"Explicit recovery ownership manifest is required");
        NSDictionary *owner = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
        NSDictionary *source = [self sourceNamed:HundredSource in:self.baselineSources];
        XCTAssertEqualObjects(owner[@"test"], @"testHundredCanonicalAliasesAndConfirmedRemovalKeepExistingSourcesAndSaves");
        XCTAssertTrue([owner[@"sourceUUID"] length] > 0);
        XCTAssertEqualObjects(source[@"uuid"], owner[@"sourceUUID"]);
        self.restoreSingle = single == nil;
        if (self.restoreSingle) XCTAssertEqualObjects(owner[@"restoreSingleThroughPicker"], @YES);
        self.baselineSources = [self.baselineSources filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"uuid != %@", owner[@"sourceUUID"]]];
        self.ownsHundred = YES;
    } else {
        XCTAssertNotNil(single, @"Complete native upgrade seeding first");
        XCTAssertNil([self sourceNamed:HundredSource in:self.baselineSources], @"Preserve existing Hundred; use the isolated upgrade simulator");
    }
    XCTAssertGreaterThan(self.baselineSaves.count, 0u, @"Upgrade fixture must retain legacy autosave bytes");
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    self.app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.flynes.app"];
    self.app.launchArguments = @[@"-AppleLanguages", @"(en)", @"-AppleLocale", @"en_US"];
    [self launchHall];
    if (!self.restoreSingle) [self assertSingleFavoriteAndContinue];
    NSURL *manifestURL = [[NSBundle bundleForClass:self.class] URLForResource:@"builtin-games" withExtension:@"json"];
    NSData *manifestBytes = manifestURL ? [NSData dataWithContentsOfURL:manifestURL] : nil;
    XCTAssertNotNil(manifestBytes, @"Shared manifest must be bundled in FlyNESUITests");
    NSDictionary *manifest = manifestBytes ? [NSJSONSerialization JSONObjectWithData:manifestBytes options:0 error:nil] : nil;
    NSUInteger minimum = [manifest[@"games"] count] + 1;
    XCTAssertGreaterThan(minimum, 1u);
    [self waitFor:^BOOL {
        XCUIElement *count = [[self.app descendantsMatchingType:XCUIElementTypeAny]
            matchingPredicate:[NSPredicate predicateWithFormat:@"label MATCHES %@", @"[0-9]+ games · swipe to browse"]].firstMatch;
        return count.exists && (NSUInteger)count.label.integerValue >= minimum;
    } reason:@"All category must finish replacing the prior single favorite result"];
    self.baselineCount = [self gameCount];
}
- (void)tearDown {
    if (self.testRun.failureCount > 0 && self.app) [self capture:@"flutter-source-failure-preserved"];
    // On failure leave only this test's added source for diagnosis; never run a
    // broad cleanup. Successful directory test removes exactly its own source.
    [self.app terminate]; [super tearDown];
}
@end

@interface FlutterSourceUITests : FlutterSourceUIBase
@end
@implementation FlutterSourceUITests
- (void)testExistingSingleImportIsIdempotentAndPickerCancellationPreservesUpgradeData {
    [self openSources]; [self tap:@"Add file"];
    [self capture:@"U10-flutter-files-before-cancel"]; [self cancelFilesPicker];
    XCTAssertTrue([[self button:@"Add file"] waitForExistenceWithTimeout:10]);
    [self tap:@"Back"]; [self expectCount:self.baselineCount];
    [self.app terminate];
    XCTAssertEqualObjects([NSSet setWithArray:[self sources]], [NSSet setWithArray:self.baselineSources]);
    [self assertExistingSourcesRetained]; [self launchHall];
    for (NSUInteger n = 0; n < 2; ++n) { [self openSources]; [self pick:SingleSource directory:NO]; [self tap:@"Back"]; [self expectCount:self.baselineCount]; }
    [self assertSingleFavoriteAndContinue]; [self.app terminate];
    NSArray *after = [self sources]; XCTAssertEqual(after.count, self.baselineSources.count);
    XCTAssertEqualObjects([self sourceNamed:SingleSource in:after][@"uuid"],
                          [self sourceNamed:SingleSource in:self.baselineSources][@"uuid"]);
    [self assertExistingSourcesRetained];
}
- (void)testHundredCanonicalAliasesAndConfirmedRemovalKeepExistingSourcesAndSaves {
    [self openSources]; [self pick:HundredSource directory:YES]; [self tap:@"Back"];
    [self expectCount:self.baselineCount + 100];
    [self search:@"FlyNES-E2E-Game-"]; [self expectCount:100];
    [self search:@"FlyNES-E2E-Game-099"]; [self expectCount:1];
    NSString *canonicalLabel = [self fixtureCard].label;
    [self search:@"FlyNES-E2E-Alias-099"]; [self expectCount:1];
    XCTAssertEqualObjects([self fixtureCard].label, canonicalLabel, @"Both aliases select the same canonical card");
    [[self fixtureCard] tap]; [self capture:@"U03-flutter-hundred-alias-canonical"];
    [self waitFor:^BOOL { return [self enabledButton:@"Continue"] || [self enabledButton:@"Start"]; }
           reason:@"Authoritative restore capability resolved for selected fixture"];
    BOOL existingProgress = [self button:@"Continue"].exists;
    // A repeat run must retain the previously generated checkpoint byte-for-byte.
    // On the first run create it through actual gameplay; never delete it to force Start.
    if (!existingProgress) {
        [self tap:@"Start"];
        XCTAssertTrue([self.app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:15]);
        XCTAssertTrue(self.app.buttons[@"NES_START"].hittable); [self.app.buttons[@"NES_START"] tap];
        [self.app.buttons[@"OPEN_PAUSE"] tap];
        XCTAssertTrue([self.app.buttons[@"game_center"] waitForExistenceWithTimeout:10]); [self.app.buttons[@"game_center"] tap];
        XCTAssertTrue([[self button:@"Sources"] waitForExistenceWithTimeout:20]);
    }
    if ([self button:@"Close search"].exists) [self tap:@"Close search"];
    [self tap:@"All"]; [self expectCount:self.baselineCount + 100];
    NSDictionary *beforeRemoval = [self saves];
    if (existingProgress) {
        XCTAssertEqual(beforeRemoval.count, self.baselineSaves.count);
        [self assertSavesRetained:self.baselineSaves];
    } else {
        XCTAssertGreaterThan(beforeRemoval.count, self.baselineSaves.count, @"First run must create its own real autosave");
    }
    [self openSources]; [self tapOwnedHundredRemove]; [self capture:@"U11-flutter-remove-confirm"];
    [self tap:@"Cancel"]; [self tap:@"Back"]; [self expectCount:self.baselineCount + 100];
    [self assertSavesRetained:beforeRemoval];
    NSString *removedUUID = [self sourceNamed:HundredSource in:[self sources]][@"uuid"];
    [self openSources]; [self tapOwnedHundredRemove]; [self tap:@"Confirm"];
    [self waitFor:^BOOL { return [self sourceRemovalComplete:removedUUID]; }
           reason:@"Only owned source removed"];
    self.ownsHundred = NO; [self capture:@"U11-flutter-source-removed"]; [self tap:@"Back"];
    [self expectCount:self.baselineCount]; [self assertSingleFavoriteAndContinue]; [self.app terminate];
    // NSUserDefaults persists through cfprefsd asynchronously; app termination
    // does not guarantee the on-disk plist has already caught up. Require the
    // exact durable state within the bound, then compare all protected bytes.
    [self waitFor:^BOOL { return [self sourceNamed:HundredSource in:[self sources]] == nil &&
        [self sources].count == self.baselineSources.count; }
           reason:@"Confirmed source removal must persist without deleting another source"];
    XCTAssertNil([self sourceNamed:HundredSource in:[self sources]]);
    XCTAssertEqual([self sources].count, self.baselineSources.count);
    [self assertExistingSourcesRetained]; [self assertSavesRetained:beforeRemoval];
    [self launchHall]; [self expectCount:self.baselineCount]; [self assertSingleFavoriteAndContinue];
}
@end

@interface FlutterSourceRecoveryUITests : FlutterSourceUIBase
@end
@implementation FlutterSourceRecoveryUITests
- (void)testRemoveOnlyExplicitlyOwnedInterruptedFixtureThroughUI {
    XCTAssertTrue(self.ownsHundred);
    if (self.restoreSingle) {
        [self openSources]; [self pick:SingleSource directory:NO]; [self tap:@"Back"];
        [self assertSingleFavoriteAndContinue];
        [self.app terminate]; [self assertSavesRetained:self.baselineSaves];
        self.baselineSources = [[self sources] filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"name != %@", HundredSource]];
        [self launchHall];
    }
    NSString *removedUUID = [self sourceNamed:HundredSource in:[self sources]][@"uuid"];
    [self openSources]; [self tapOwnedHundredRemove]; [self tap:@"Confirm"];
    [self waitFor:^BOOL { return [self sourceRemovalComplete:removedUUID]; }
           reason:@"Explicitly owned interrupted fixture removed through the product UI"];
    [self capture:@"source-interrupted-fixture-recovered"];
    [self.app terminate];
    // NSUserDefaults persists through cfprefsd asynchronously; app termination
    // does not guarantee the on-disk plist has already caught up. Require the
    // exact durable state within the bound, then compare all protected bytes.
    [self waitFor:^BOOL { return [self sourceNamed:HundredSource in:[self sources]] == nil &&
        [self sources].count == self.baselineSources.count; }
           reason:@"Confirmed source removal must persist without deleting another source"];
    XCTAssertNil([self sourceNamed:HundredSource in:[self sources]]);
    XCTAssertEqual([self sources].count, self.baselineSources.count);
    [self assertExistingSourcesRetained];
}
@end

// Additional selectors use a separate, hash-verified local-provider fixture.
// Stage with .artifacts/ios-g2/stage_source_gap_fixtures.py --udid UUID.
// Each selector rejects previously registered gap sources and keeps failure
// artifacts (including revoked directory permissions) for explicit inspection.
@interface FlutterSourceGapUITests : FlutterSourceUIBase
@property(nonatomic, copy) NSString *gapRoot;
@property(nonatomic, copy) NSDictionary *fixtureManifest;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ownedSources;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *fixtureMutations;
@property(nonatomic, copy) NSString *ownershipPath;
@end

@implementation FlutterSourceGapUITests
- (NSString *)pickerFixtureRoot { return @"FlyNES-Source-Gaps-v1"; }
- (XCUIElement *)fixtureCard {
    // Base setup also verifies the preserved Single; both names are test-only.
    XCUIElementQuery *cards = [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
        @"label BEGINSWITH %@ OR label BEGINSWITH %@", @"FlyNES-Gap-", @"FlyNES-E2E-"]];
    XCTAssertTrue([cards.firstMatch waitForExistenceWithTimeout:15]);
    XCTAssertEqual(cards.count, 1u); return cards.firstMatch;
}
- (NSString *)sha256:(NSData *)bytes {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); ++i) [value appendFormat:@"%02x", digest[i]];
    return value;
}
- (void)verifyFixtureBytes {
    NSString *resolved = self.gapRoot.stringByResolvingSymlinksInPath;
    XCTAssertEqualObjects(resolved, self.gapRoot, @"Fixture must not resolve through a symlink");
    NSDictionary *files = self.fixtureManifest[@"files"];
    XCTAssertEqual(files.count, 5u);
    NSMutableSet *observed = [NSMutableSet set];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:self.gapRoot];
    for (NSString *relative in enumerator) {
        NSString *path = [self.gapRoot stringByAppendingPathComponent:relative];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        XCTAssertNotEqualObjects(attributes[NSFileType], NSFileTypeSymbolicLink);
        if ([attributes[NSFileType] isEqual:NSFileTypeDirectory]) continue;
        if ([relative isEqual:@"manifest.json"]) continue;
        NSString *manifestKey = relative;
        XCTAssertNotNil(files[manifestKey], @"Unowned fixture file must not be changed");
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        XCTAssertNotNil(bytes); XCTAssertEqualObjects([self sha256:bytes], files[manifestKey]);
        XCTAssertFalse([observed containsObject:manifestKey], @"Original and renamed fixture must not coexist");
        [observed addObject:manifestKey];
    }
    XCTAssertEqualObjects(observed, [NSSet setWithArray:files.allKeys]);
}
- (void)setUp {
    [super setUp];
    for (NSDictionary *source in self.baselineSources) {
        XCTAssertFalse([source[@"name"] hasPrefix:@"FlyNES-Gap-"], @"Preserve interrupted gap source; inspect its ownership record before rerunning");
    }
    NSString *applications = NSProcessInfo.processInfo.environment[@"FLYNES_TEST_APPLICATION_CONTAINERS"];
    NSString *groups = [[applications.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent
        stringByAppendingPathComponent:@"Shared"] stringByAppendingPathComponent:@"AppGroup"];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *group in [NSFileManager.defaultManager contentsOfDirectoryAtPath:groups error:nil]) {
        NSString *path = [groups stringByAppendingPathComponent:group];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
            [path stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([metadata[@"MCMMetadataIdentifier"] isEqual:@"group.com.apple.FileProvider.LocalStorage"])
            [matches addObject:[[path stringByAppendingPathComponent:@"File Provider Storage"]
                stringByAppendingPathComponent:[self pickerFixtureRoot]]];
    }
    XCTAssertEqual(matches.count, 1u, @"Exactly one prepared Files local provider is required");
    self.gapRoot = matches.firstObject;
    NSData *manifest = [NSData dataWithContentsOfFile:[self.gapRoot stringByAppendingPathComponent:@"manifest.json"]];
    XCTAssertNotNil(manifest, @"Run stage_source_gap_fixtures.py on this exact simulator");
    // Mac staging uses ZipInfo.create_system=3; Windows' default is0 and has a
    // different ZIP/manifest digest even though the licensed ROM bytes agree.
    XCTAssertEqualObjects([self sha256:manifest], @"27bc1722a8552adeb55a07062e222ba96a020cfebd196538f4eb8990e9d0d26b",
        @"Exact reviewed staging manifest required");
    self.fixtureManifest = manifest ? [NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil] : nil;
    XCTAssertEqualObjects(self.fixtureManifest[@"owner"], [self pickerFixtureRoot]);
    XCTAssertEqualObjects(self.fixtureManifest[@"fixture_sha256"], @"ee51cd9562f28195ba015d9857c6c4fc9bf67cdfb213e95f655e586b92195173");
    [self verifyFixtureBytes];
    self.ownedSources = [NSMutableDictionary dictionary];
    self.fixtureMutations = [NSMutableArray array];
    self.ownershipPath = [[self currentContainer] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"tmp/source-gap-ownership-%@.plist", NSUUID.UUID.UUIDString]];
    [self assertAutosaveEnabled];
}
- (void)assertAutosaveEnabled {
    // settings_persist.cpp FLYSET01 v1: 12-byte header, 19 four-byte values,
    // locale/last-played strings, then SHA256 of all preceding bytes. Autosave
    // is field18. Validate the format/digest instead of changing user settings.
    NSData *encoded = [NSData dataWithContentsOfFile:[[self currentContainer]
        stringByAppendingPathComponent:@"Documents/settings.flyset01"]];
    XCTAssertGreaterThan(encoded.length, 12u + 19u * 4u + 32u);
    XCTAssertEqualObjects([encoded subdataWithRange:NSMakeRange(0, 8)],
        [@"FLYSET01" dataUsingEncoding:NSUTF8StringEncoding]);
    const uint8_t *bytes = (const uint8_t *)encoded.bytes;
    XCTAssertTrue(bytes[8] == 1 && bytes[9] == 0 && bytes[10] == 0 && bytes[11] == 0);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)(encoded.length - sizeof(digest)), digest);
    XCTAssertEqualObjects([NSData dataWithBytes:digest length:sizeof(digest)],
        [encoded subdataWithRange:NSMakeRange(encoded.length - sizeof(digest), sizeof(digest))]);
    const NSUInteger offset = 12u + 18u * 4u;
    XCTAssertTrue(bytes[offset] == 1 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == 0,
        @"This checkpoint test requires the existing autosave-enabled upgrade fixture; never toggle user settings");
}
- (void)recordOwned:(NSString *)name uuid:(NSString *)uuid {
    XCTAssertGreaterThan(uuid.length, 0u);
    for (NSDictionary *baseline in self.baselineSources) XCTAssertNotEqualObjects(baseline[@"uuid"], uuid);
    self.ownedSources[uuid] = name;
    NSDictionary *record = @{@"test":self.name, @"fixtureRoot":self.gapRoot,
        @"fixtureManifest":self.fixtureManifest, @"sources":self.ownedSources,
        @"plannedFixtureMutations":self.fixtureMutations};
    XCTAssertTrue([record writeToFile:self.ownershipPath atomically:YES]);
}
- (void)selectGap:(NSString *)name directory:(BOOL)directory {
    [self openFixtureRootInPicker];
    XCUIElement *item = [self pickerItem:name];
    XCTAssertTrue([item waitForExistenceWithTimeout:10]); XCTAssertTrue(item.hittable); [item tap];
    if (directory) {
        XCTAssertTrue([self.app.buttons[@"Open"] waitForExistenceWithTimeout:10]);
        XCTAssertTrue(self.app.buttons[@"Open"].enabled); [self.app.buttons[@"Open"] tap];
    }
    [self waitFor:^BOOL {
        NSString *uuid = [self sourceNamed:name in:[self sources]][@"uuid"];
        XCUIElement *scan = uuid ? [self action:@"Scan" uuid:uuid] : nil;
        return !self.app.buttons[@"Cancel"].exists && !self.app.buttons[@"Open"].exists &&
            scan.exists && scan.enabled && [self enabledButton:@"Back"];
    }
           reason:@"Real Files selection and native import complete"];
}
- (NSString *)importGap:(NSString *)name directory:(BOOL)directory {
    XCTAssertNil([self sourceNamed:name in:[self sources]], @"Only absent fixture sources may be imported");
    [self tap:directory ? @"Add folder" : @"Add file"];
    [self selectGap:name directory:directory];
    [self waitFor:^BOOL { return [self sourceNamed:name in:[self sources]][@"uuid"] != nil; }
           reason:@"Imported source UUID durably recorded"];
    NSString *uuid = [self sourceNamed:name in:[self sources]][@"uuid"];
    [self recordOwned:name uuid:uuid]; return uuid;
}
- (XCUIElement *)action:(NSString *)label uuid:(NSString *)uuid {
    NSString *identifier = [@"source-remove-" stringByAppendingString:uuid];
    XCUIElementQuery *parents = [self.app.otherElements containingType:XCUIElementTypeButton identifier:identifier];
    XCUIElement *action = nil;
    // The actual iOS tree has direct sibling Scan/Reauthorize/UUID Remove
    // controls. Require that exact parent; never use card label/y or an index.
    for (XCUIElement *parent in parents.allElementsBoundByIndex) {
        XCUIElementQuery *children = [parent childrenMatchingType:XCUIElementTypeButton];
        if ([children matchingIdentifier:identifier].count == 1) {
            XCUIElementQuery *matches = [children matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", label]];
            if (matches.count == 1) { XCTAssertNil(action); action = matches.firstMatch; }
        }
    }
    return action;
}
- (void)tapAction:(NSString *)label uuid:(NSString *)uuid {
    XCTAssertNotNil(self.ownedSources[uuid], @"Only this run's source is actionable");
    XCUIElement *action = [self action:label uuid:uuid];
    XCTAssertNotNil(action, @"%@ must belong to UUID %@", label, uuid);
    for (NSUInteger n = 0; !action.hittable && n < 14; ++n) {
        [[self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, 0.8)] pressForDuration:0.1
            thenDragToCoordinate:[self.app coordinateWithNormalizedOffset:CGVectorMake(0.7, 0.6)]];
    }
    CGRect previous = CGRectNull; NSUInteger stable = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (stable < 3 && deadline.timeIntervalSinceNow > 0) {
        CGRect frame = action.frame;
        stable = action.hittable && CGRectEqualToRect(previous, frame) ? stable + 1 : 0;
        previous = frame; [NSThread sleepForTimeInterval:0.25];
    }
    XCTAssertEqual(stable, 3u); XCTAssertTrue(action.enabled);
    XCTAssertTrue(CGRectContainsRect(self.app.frame, action.frame)); [action tap];
}
- (void)playGap:(NSString *)query screenshot:(NSString *)name {
    // Shared catalog identity hashes the complete ROM payload; the legacy save
    // folder replaces the canonical "game:" colon with an underscore. Limit a
    // repeat-run checkpoint update to this verified, currently owned fixture.
    NSDictionary *identities = @{
        @"FlyNES-Gap-Directory-Game":@[@"FlyNES-Gap-Directory", @"9e019a9f32cb841c5f1f5ca1b17e2755bff5b2db5e1d4bce54d95ed82cbf1301"],
        @"FlyNES-Gap-Recovery-Game":@[@"FlyNES-Gap-Failure", @"faea6bf67b2f0c350d2d56159b6af3c7bebe4ff48e423e7200090b0c5f40699c"],
        @"FlyNES-Gap-Zip-Game":@[@"FlyNES-Gap-Package.zip", @"30b0475bf62717785f904a82d371ecca44844299bd4482c9e4816478eb45ba5d"]};
    NSArray *identity = identities[query]; XCTAssertNotNil(identity);
    BOOL ownsFixture = [self.ownedSources.allValues containsObject:identity.firstObject] ||
        ([query isEqual:@"FlyNES-Gap-Recovery-Game"] &&
         [self.ownedSources.allValues containsObject:@"FlyNES-Gap-Replacement"]);
    XCTAssertTrue(ownsFixture, @"Only this test's exact licensed canonical save may update");
    [self verifyFixtureBytes];
    [self assertSavesRetained:self.baselineSaves];
    // content_identity.cpp normalize_sha256 canonicalizes to UPPERCASE. The
    // native autosave helper preserves that case; simulator paths distinguish it.
    NSString *canonicalSHA = [identity.lastObject uppercaseString];
    NSString *saveKey = [NSString stringWithFormat:@"game_%@/autosave.nst", canonicalSHA];
    NSDictionary *savesBefore = [self saves];
    [self search:query]; [self expectCount:1]; [[self fixtureCard] tap];
    [self waitFor:^BOOL { return [self enabledButton:@"Start"] || [self enabledButton:@"Continue"]; }
           reason:@"Imported ROM restore capability resolved"];
    [self tap:[self enabledButton:@"Continue"] ? @"Continue" : @"Start"];
    XCTAssertTrue([self.app.buttons[@"OPEN_PAUSE"] waitForExistenceWithTimeout:20], @"Actual persisted source must load the ROM");
    XCTAssertTrue(self.app.buttons[@"NES_START"].hittable); [self.app.buttons[@"NES_START"] tap];
    [self capture:name]; [self.app.buttons[@"OPEN_PAUSE"] tap];
    XCTAssertTrue([self.app.buttons[@"game_center"] waitForExistenceWithTimeout:10]);
    [self.app.buttons[@"game_center"] tap];
    XCTAssertTrue([[self button:@"Sources"] waitForExistenceWithTimeout:20]);
    [self tap:@"Close search"]; [self tap:@"All"];
    [self waitFor:^BOOL {
        NSData *updated = [self saves][saveKey];
        return updated.length > 0 && ![updated isEqual:savesBefore[saveKey]];
    } reason:@"Actual gameplay must write the exact owned canonical checkpoint"];
    NSDictionary *savesAfter = [self saves];
    NSMutableDictionary *protectedSaves = [savesBefore mutableCopy];
    [protectedSaves removeObjectForKey:saveKey];
    [self assertSavesRetained:protectedSaves];
    NSMutableSet *expectedKeys = [NSMutableSet setWithArray:savesBefore.allKeys]; [expectedKeys addObject:saveKey];
    XCTAssertEqualObjects([NSSet setWithArray:savesAfter.allKeys], expectedKeys, @"No unrelated checkpoint may appear or disappear");
    NSMutableDictionary *updatedBaseline = [self.baselineSaves mutableCopy];
    updatedBaseline[saveKey] = savesAfter[saveKey]; self.baselineSaves = updatedBaseline;
    NSString *proof = [NSString stringWithFormat:@"canonical=game:%@\nbefore=%@\nafter=%@\n",
        canonicalSHA, savesBefore[saveKey] ? [self sha256:savesBefore[saveKey]] : @"absent",
        [self sha256:savesAfter[saveKey]]];
    XCTAttachment *attachment = [XCTAttachment attachmentWithString:proof];
    attachment.name = [name stringByAppendingString:@"-owned-checkpoint"];
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
}
- (void)removeGap:(NSString *)uuid {
    NSDictionary *savesBefore = [self saves];
    [self openSources]; [self tapAction:@"Remove" uuid:uuid];
    XCTAssertTrue([[self text:@"Remove source"] waitForExistenceWithTimeout:10]); [self tap:@"Confirm"];
    [self waitFor:^BOOL { return [self sourceRemovalComplete:uuid]; }
           reason:@"Only this test's UUID removed durably"];
    [self tap:@"Back"]; [self expectCount:self.baselineCount];
    [self assertSingleFavoriteAndContinue]; [self assertExistingSourcesRetained];
    [self assertSavesRetained:savesBefore]; [self verifyFixtureBytes];
}
- (void)testFolderAuthorizationSurvivesProcessRestartAndRealRescan {
    [self openSources]; NSString *uuid = [self importGap:@"FlyNES-Gap-Directory" directory:YES];
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 1];
    [self.app terminate]; [self assertExistingSourcesRetained]; [self launchHall];
    XCTAssertEqualObjects([self sourceNamed:@"FlyNES-Gap-Directory" in:[self sources]][@"uuid"], uuid);
    [self playGap:@"FlyNES-Gap-Directory-Game" screenshot:@"gap-directory-restarted-real-rom"];
    // A content-identical rename of our own registered fixture gives rescan a
    // unique observable result, rather than accepting the old idle UI as done.
    [self verifyFixtureBytes];
    NSString *original = [self.gapRoot stringByAppendingPathComponent:@"FlyNES-Gap-Directory/FlyNES-Gap-Directory-Game.nes"];
    NSString *renamed = [self.gapRoot stringByAppendingPathComponent:@"FlyNES-Gap-Directory/FlyNES-Gap-Rescanned-Game.nes"];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:renamed]);
    [self.fixtureMutations addObject:@{@"operation":@"rename-for-rescan", @"from":original, @"to":renamed}];
    [self recordOwned:@"FlyNES-Gap-Directory" uuid:uuid];
    XCTAssertTrue([NSFileManager.defaultManager moveItemAtPath:original toPath:renamed error:nil]);
    [self openSources]; [self tapAction:@"Scan" uuid:uuid];
    [self waitFor:^BOOL { return [self action:@"Scan" uuid:uuid].exists && [self action:@"Scan" uuid:uuid].enabled &&
        [[self sourceNamed:@"FlyNES-Gap-Directory" in:[self sources]][@"error"] length] == 0; }
           reason:@"Retained directory rescans through persisted authorization"];
    [self capture:@"gap-directory-rescan-after-restart"]; [self tap:@"Back"];
    [self expectCount:self.baselineCount + 1];
    [self search:@"FlyNES-Gap-Rescanned-Game"]; [self expectCount:1];
    [self capture:@"gap-directory-new-alias-proves-rescan"];
    [self tap:@"Close search"];
    XCTAssertEqualObjects([self sha256:[NSData dataWithContentsOfFile:renamed]],
        self.fixtureManifest[@"files"][@"FlyNES-Gap-Directory/FlyNES-Gap-Directory-Game.nes"]);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:original]);
    XCTAssertTrue([NSFileManager.defaultManager moveItemAtPath:renamed toPath:original error:nil]);
    [self removeGap:uuid];
}
- (void)testZipPickerDeduplicatesAliasesAndRestartsWithReadableAuthorization {
    [self openSources]; NSString *uuid = [self importGap:@"FlyNES-Gap-Package.zip" directory:NO];
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 1];
    [self search:@"FlyNES-Gap-Zip-Game"]; [self expectCount:1]; NSString *label = [self fixtureCard].label;
    [self search:@"FlyNES-Gap-Zip-Alias"]; [self expectCount:1]; XCTAssertEqualObjects([self fixtureCard].label, label);
    [self capture:@"gap-zip-canonical-alias"]; [self tap:@"Close search"];
    [self openSources]; [self tap:@"Add file"]; [self selectGap:@"FlyNES-Gap-Package.zip" directory:NO];
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 1];
    [self.app terminate]; [self launchHall];
    XCTAssertEqualObjects([self sourceNamed:@"FlyNES-Gap-Package.zip" in:[self sources]][@"uuid"], uuid);
    XCTAssertEqual([self sources].count, self.baselineSources.count + 1);
    [self playGap:@"FlyNES-Gap-Zip-Game" screenshot:@"gap-zip-restarted-real-rom"]; [self removeGap:uuid];
}
- (void)testUnavailableOwnedDirectoryCancelAndReauthorizeRetainUUIDAndLibrary {
    [self openSources]; NSString *uuid = [self importGap:@"FlyNES-Gap-Failure" directory:YES];
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 1];
    [self playGap:@"FlyNES-Gap-Recovery-Game" screenshot:@"gap-directory-before-loss"];
    NSDictionary *savedProgress = [self saves]; [self verifyFixtureBytes];
    NSString *folder = [self.gapRoot stringByAppendingPathComponent:@"FlyNES-Gap-Failure"];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:folder error:nil];
    XCTAssertEqualObjects(attributes[NSFileType], NSFileTypeDirectory);
    NSNumber *mode = attributes[NSFilePosixPermissions]; XCTAssertNotNil(mode);
    [self.fixtureMutations addObject:@{@"operation":@"deny-read-for-reauthorization", @"path":folder,
        @"originalMode":mode, @"testMode":@0000}];
    [self recordOwned:@"FlyNES-Gap-Failure" uuid:uuid];
    XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0000} ofItemAtPath:folder error:nil]);
    // No deletion/move: only this verified fixture becomes temporarily unreadable.
    // If any assertion fails, preserve its exact permission state and evidence.
    [self openSources]; [self tapAction:@"Scan" uuid:uuid];
    [self waitFor:^BOOL { return [[self sourceNamed:@"FlyNES-Gap-Failure" in:[self sources]][@"error"] length] > 0; }
           reason:@"Actual filesystem denial must surface a source error, not an empty successful library"];
    XCTAssertTrue([[self button:@"Reauthorize"] waitForExistenceWithTimeout:10]);
    XCTAssertFalse([self button:@"Cancel scan"].exists, @"iOS must not advertise unsupported scan cancellation");
    [self capture:@"gap-directory-unavailable-old-library-retained"];
    NSDictionary *before = [self preferences];
    [self tapAction:@"Reauthorize" uuid:uuid];
    [self cancelFilesPicker];
    [self waitFor:^BOOL { return !self.app.buttons[@"Cancel"].exists &&
        [self action:@"Reauthorize" uuid:uuid].exists && [self action:@"Reauthorize" uuid:uuid].enabled; }
           reason:@"Cancelled authorization returns to the same source action"];
    [self.app terminate];
    NSDictionary *after = [self preferences];
    XCTAssertEqualObjects(after[@"flynes.source_metadata_v1"], before[@"flynes.source_metadata_v1"]);
    XCTAssertEqualObjects(after[@"flynes.source_uuid_bookmarks_v1"], before[@"flynes.source_uuid_bookmarks_v1"]);
    [self assertSavesRetained:savedProgress]; [self launchHall]; [self expectCount:self.baselineCount + 1];
    [self openSources]; [self tapAction:@"Reauthorize" uuid:uuid];
    [self selectGap:@"FlyNES-Gap-Replacement" directory:YES];
    [self waitFor:^BOOL { return [[self sourceNamed:@"FlyNES-Gap-Replacement" in:[self sources]][@"uuid"] isEqual:uuid]; }
           reason:@"Reauthorization must update the same UUID"];
    [self recordOwned:@"FlyNES-Gap-Replacement" uuid:uuid];
    XCTAssertEqual([self sources].count, self.baselineSources.count + 1);
    [self capture:@"gap-directory-same-uuid-reauthorized"];
    XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:mode} ofItemAtPath:folder error:nil]);
    [self tap:@"Back"]; [self expectCount:self.baselineCount + 1];
    [self assertSavesRetained:savedProgress];
    [self.app terminate]; [self launchHall];
    [self playGap:@"FlyNES-Gap-Recovery-Game" screenshot:@"gap-reauthorized-restarted-real-rom"];
    [self removeGap:uuid];
}
@end

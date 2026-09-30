#import <XCTest/XCTest.h>
#import "../app/platform/FlyNesProductService.h"
#import "../app/bridge/FlyNesAppBridge.h"
#import "../app/bridge/FlyNesRuntimeBridge.h"
#import "../app/platform/CatalogSourceService.h"
#import "../app/platform/BuiltinGames.h"
#include <flynes/product/control_layout.hpp>
#import <objc/runtime.h>

// Hold only this test's source read, after scanFileRecords has acquired the
// real application owner lock. Never fabricate catalog/settings results.
static NSString *heldProductScanPath;
static dispatch_semaphore_t heldProductScanEntered;
static dispatch_semaphore_t heldProductScanRelease;
static IMP originalProductCoordinateRead;
static void heldProductCoordinateRead(id coordinator, SEL selector, NSURL *url,
    NSFileCoordinatorReadingOptions options, NSError **error, void (^accessor)(NSURL *)) {
    if ([url.path isEqual:heldProductScanPath]) {
        dispatch_semaphore_signal(heldProductScanEntered);
        dispatch_semaphore_wait(heldProductScanRelease, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    ((void (*)(id, SEL, NSURL *, NSFileCoordinatorReadingOptions, NSError **, void (^)(NSURL *)))
        originalProductCoordinateRead)(coordinator, selector, url, options, error, accessor);
}

@interface ProductServiceTests : XCTestCase
@end
@implementation ProductServiceTests {
    FlyNesProductService *service_;
    FlyNesAppBridge *bridge_;
    NSUserDefaults *defaults_;
    NSURL *root_;
    NSString *suite_;
    NSInteger request_;
    NSNumber *generation_;
}
- (void)setUp {
    [super setUp];
    Class serviceClass = NSClassFromString(@"FlyNesProductService");
    XCTAssertNotNil(serviceClass, @"The iOS product owner must implement the shared Dart contract");
    if (!serviceClass) return;
    root_ = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    suite_ = [@"FlyNES.ProductTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    defaults_ = [[NSUserDefaults alloc] initWithSuiteName:suite_];
    bridge_ = [[FlyNesAppBridge alloc] init];
    XCTAssertTrue([bridge_ createWithDataRoot:root_.path cacheRoot:root_.path error:nil]);
    CatalogSourceService *sources = [[CatalogSourceService alloc] initWithBridge:bridge_ defaults:defaults_ builtinURL:nil];
    service_ = [[serviceClass alloc] initWithBridge:bridge_ sources:sources defaults:defaults_
                                           bundle:NSBundle.mainBundle documentsRoot:root_];
    generation_ = [service_ activateContext:@{@"route":@"hall", @"purpose":@"single", @"returnToken":@""}][@"hostGeneration"];
}
- (void)tearDown {
    service_.platformHandler = nil;
    service_ = nil; bridge_ = nil;
    if (suite_) [defaults_ removePersistentDomainForName:suite_];
    if (root_) [NSFileManager.defaultManager removeItemAtURL:root_ error:nil];
    [super tearDown];
}
- (NSDictionary *)call:(NSString *)method args:(NSDictionary *)args error:(NSString **)error {
    if (!service_) return nil;
    XCTestExpectation *done = [self expectationWithDescription:method];
    NSMutableDictionary *input = [args mutableCopy];
    input[@"requestId"] = @(++request_); input[@"hostGeneration"] = generation_;
    __block NSDictionary *result; __block NSString *failure;
    [service_ handleMethod:method arguments:input completion:^(NSDictionary *value, NSString *code) {
        XCTAssertTrue(NSThread.isMainThread);
        result = value; failure = code; [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:15];
    if (error) *error = failure;
    if (result) {
        XCTAssertEqualObjects(result[@"requestId"], @(request_));
        XCTAssertEqualObjects(result[@"hostGeneration"], generation_);
        XCTAssertTrue([result[@"instanceId"] length] > 0);
    }
    return result;
}
- (void)testAcknowledgedSettingsAndLayoutReadsDoNotWaitForCoordinatedScan {
    XCTAssertTrue(NSThread.isMainThread);
    NSDictionary *patch = @{@"audio_enabled":@0, @"autosave_enabled":@0, @"locale_tag":@"zh-Hans"};
    XCTAssertTrue([bridge_ applySettings:patch error:nil]);
    NSDictionary *expected = bridge_.settingsGet;
    NSString *layout = bridge_.controlLayoutGet;
    FlyNesBuiltinGame *game = FlyNesBuiltinGames.shared.all.firstObject;
    NSString *rom = [NSBundle.mainBundle pathForResource:
        [FlyNesBuiltinGames resourceNameForAssetFilename:game.assetFilename] ofType:@"nes"];
    NSURL *copy = [root_ URLByAppendingPathComponent:@"held-source.nes"];
    XCTAssertTrue([NSFileManager.defaultManager copyItemAtPath:rom toPath:copy.path error:nil]);
    heldProductScanPath = copy.path;
    heldProductScanEntered = dispatch_semaphore_create(0);
    heldProductScanRelease = dispatch_semaphore_create(0);
    SEL selector = @selector(coordinateReadingItemAtURL:options:error:byAccessor:);
    Method method = class_getInstanceMethod(NSFileCoordinator.class, selector);
    originalProductCoordinateRead = method_setImplementation(method, (IMP)heldProductCoordinateRead);
    XCTestExpectation *scan = [self expectationWithDescription:@"actual scan finishes after release"];
    FlyNesAppBridge *bridge = bridge_;
    NSUUID *uuid = NSUUID.UUID; uuid_t bytes; [uuid getUUIDBytes:bytes];
    NSData *source = [NSData dataWithBytes:bytes length:16];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [bridge scanFileRecords:@[@{@"url":copy, @"relativePath":@"held-source.nes",
            @"displayName":@"Held test source"}] sourceUUID:source sourceScope:3 incomplete:NO error:&error];
        XCTAssertTrue(ok, @"%@", error); [scan fulfill];
    });
    @try {
        XCTAssertEqual(dispatch_semaphore_wait(heldProductScanEntered,
            dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)), 0l);
        dispatch_semaphore_t release = heldProductScanRelease;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC),
            dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ dispatch_semaphore_signal(release); });
        CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
        NSDictionary *duringScan = bridge_.settingsGet;
        NSString *duringLayout = bridge_.controlLayoutGet;
        NSTimeInterval duration = CFAbsoluteTimeGetCurrent() - begin;
        XCTAssertLessThan(duration, 0.5, @"Playback return/background reads must not wait for a 1.5s source read");
        XCTAssertEqualObjects(duringScan, expected, @"Use the latest acknowledged settings, including autosave OFF");
        XCTAssertEqualObjects(duringLayout, layout);
        [self waitForExpectations:@[scan] timeout:8];
    } @finally {
        dispatch_semaphore_signal(heldProductScanRelease);
        method_setImplementation(method, originalProductCoordinateRead);
        heldProductScanPath = nil;
    }
    XCTAssertEqualObjects(bridge_.settingsGet, expected);
}

- (void)testBootstrapPreservesLegacyNavigationAndCatalogUsesRealSnapshot {
    if (!service_) return;
    [defaults_ setObject:@"FAVORITES" forKey:@"GameCenterCategory"];
    [defaults_ setObject:@"retained-choice" forKey:@"GameCenterSelected.ALL"];
    NSString *error;
    NSDictionary *boot = [self call:@"bootstrap" args:@{} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(boot[@"protocolVersion"], @1);
    XCTAssertEqualObjects(boot[@"preferences"][@"category"], @"favorites");
    XCTAssertEqualObjects(boot[@"preferences"][@"selections"][@"all"], @"retained-choice");
    NSDictionary *query = [self call:@"catalogQuery" args:@{@"category":@"all", @"query":@"", @"multiplayerOnly":@NO, @"selectedId":@"", @"locale":@"en"} error:&error];
    XCTAssertNil(error); XCTAssertTrue([query[@"total"] integerValue] > 0);
    if (!query) return;
    XCTAssertTrue([query[@"items"] count] <= 128);
    NSDictionary *item = [query[@"items"] firstObject];
    XCTAssertTrue([item[@"canonicalId"] length] > 0);
    XCTAssertNotNil(item[@"coverRevision"]); XCTAssertNotNil(item[@"variantCount"]);
    [self call:@"catalogWindow" args:@{@"catalogGeneration":query[@"catalogGeneration"], @"viewRevision":@0, @"offset":@0, @"limit":@128} error:&error];
    XCTAssertEqualObjects(error, @"snapshot_expired");
    [self call:@"catalogWindow" args:@{@"catalogGeneration":query[@"catalogGeneration"], @"viewRevision":query[@"viewRevision"], @"offset":@0, @"limit":@129} error:&error];
    XCTAssertEqualObjects(error, @"invalid_arguments");
}
- (void)testOneFieldSettingPatchPreservesOtherSettingsAndRejectsLockedOption {
    if (!service_) return;
    NSString *error;
    XCTAssertTrue([bridge_ applySettings:@{@"direction_mode":@3} error:nil]);
    NSDictionary *settings = [self call:@"patchSetting" args:@{@"key":@"audioEnabled", @"value":@NO} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(settings[@"values"][@"directionMode"], @3);
    XCTAssertEqualObjects(settings[@"values"][@"audioEnabled"], @NO);
    [self call:@"patchSetting" args:@{@"key":@"videoQualityPreset", @"value":@3} error:&error];
    XCTAssertEqualObjects(error, @"capability_locked");
    [self call:@"patchSetting" args:@{@"key":@"audioEnabled", @"value":@"false"} error:&error];
    XCTAssertEqualObjects(error, @"invalid_arguments");
}
- (void)testSaveNavigationDoesNotOverwriteSettingsAndSourcesProtectBuiltin {
    if (!service_) return;
    NSString *error;
    [defaults_ setObject:@"keep" forKey:@"unrelated"];
    [self call:@"bootstrap" args:@{} error:&error];
    NSDictionary *saved = [self call:@"saveNavigation" args:@{@"category":@"all", @"multiplayerOnly":@YES, @"selections":@{@"all":@"kept"}} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(saved[@"selections"][@"all"], @"kept");
    XCTAssertEqualObjects([defaults_ stringForKey:@"unrelated"], @"keep");
    NSDictionary *sources = [self call:@"sources" args:@{} error:&error];
    NSDictionary *builtin = [sources[@"items"] firstObject];
    XCTAssertEqualObjects(builtin[@"builtin"], @YES);
    XCTAssertTrue([builtin[@"count"] integerValue] > 0);
    if (!builtin[@"uuid"]) return;
    [self call:@"removeSource" args:@{@"uuid":builtin[@"uuid"]} error:&error];
    XCTAssertEqualObjects(error, @"source_protected");
    [self call:@"cancelScan" args:@{@"uuid":builtin[@"uuid"], @"operationId":@"missing"} error:&error];
    XCTAssertEqualObjects(error, @"cancellation_unavailable");
}
- (void)testLegacyResumeDoesNotUseLastPlayedAndLicenseIDsAreAllowlisted {
    if (!service_) return;
    NSString *error;
    [self call:@"bootstrap" args:@{} error:&error];
    NSDictionary *query = [self call:@"catalogQuery" args:@{@"category":@"all", @"query":@"", @"multiplayerOnly":@NO, @"selectedId":@"", @"locale":@"en"} error:&error];
    NSString *canonical = [query[@"items"] firstObject][@"canonicalId"];
    XCTAssertNotNil(canonical); if (!canonical) return;
    XCTAssertTrue([bridge_ markPlayedCanonicalID:canonical error:nil]);
    NSDictionary *resume = [self call:@"resumeCapability" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertEqualObjects(resume[@"state"], @"none");
    NSDictionary *licenses = [self call:@"licenses" args:@{} error:&error];
    XCTAssertTrue([licenses[@"items"] count] >= 5);
    NSString *licenseID = [licenses[@"items"] firstObject][@"id"];
    XCTAssertNotNil(licenseID); if (!licenseID) return;
    NSDictionary *text = [self call:@"licenseText" args:@{@"id":licenseID} error:&error];
    XCTAssertNil(error); XCTAssertTrue([text[@"text"] length] > 0);
    [self call:@"licenseText" args:@{@"id":@"../Info.plist"} error:&error];
    XCTAssertEqualObjects(error, @"invalid_arguments");
}
- (void)testPlatformCompletionIsPendingUntilNativeReturnAndDetachKeepsOwner {
    if (!service_) return;
    __block FlyNesProductCompletion nativeReturn;
    XCTestExpectation *entered = [self expectationWithDescription:@"native presented"];
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertEqualObjects(method, @"openNative"); XCTAssertEqualObjects(args[@"page"], @"layout");
        nativeReturn = [completion copy]; [entered fulfill];
    };
    XCTestExpectation *done = [self expectationWithDescription:@"native return"];
    __block BOOL completed = NO;
    [service_ handleMethod:@"openNative" arguments:@{@"requestId":@1, @"hostGeneration":generation_, @"page":@"layout"} completion:^(NSDictionary *result, NSString *error) {
        completed = YES; XCTAssertNil(error); XCTAssertEqualObjects(result[@"status"], @"returned"); [done fulfill];
    }];
    [self waitForExpectations:@[entered] timeout:5];
    XCTAssertFalse(completed);
    XCTAssertNotNil(nativeReturn);
    if (nativeReturn) nativeReturn(@{@"status":@"returned"}, nil);
    [self waitForExpectations:@[done] timeout:5];
    nativeReturn = nil;
    NSString *error;
    [self call:@"detach" args:@{} error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil([self call:@"settings" args:@{} error:&error]);
}
- (void)testStaleHostCannotMutateSettingsAndPickerCancelDoesNotImport {
    if (!service_) return;
    NSDictionary *before = [bridge_ settingsGet];
    [service_ activateContext:@{@"route":@"settings", @"purpose":@"single", @"returnToken":@"paused-game"}];
    NSString *error;
    [self call:@"patchSetting" args:@{@"key":@"audioEnabled", @"value":@NO} error:&error];
    XCTAssertEqualObjects(error, @"stale_host");
    XCTAssertEqualObjects([bridge_ settingsGet], before);
    generation_ = [service_ activateContext:@{@"route":@"hall", @"purpose":@"single", @"returnToken":@""}][@"hostGeneration"];
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        XCTAssertEqualObjects(method, @"pickSource"); completion(@{@"status":@"cancelled"}, nil);
    };
    NSDictionary *result = [self call:@"pickSource" args:@{@"kind":@"file"} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(result[@"status"], @"cancelled");
    XCTAssertNil([defaults_ objectForKey:@"flynes.source_metadata_v1"]);
}
- (void)testLegacyCheckpointIsRetainedAndResumeReflectsExistingAutosavePolicy {
    if (!service_) return;
    NSString *error;
    [self call:@"bootstrap" args:@{} error:&error];
    NSDictionary *row = [[bridge_ catalogSnapshotGames] firstObject];
    NSString *canonical = row[@"canonicalId"];
    XCTAssertNotNil(canonical); if (!canonical) return;
    CatalogSourceService *sources = [[CatalogSourceService alloc] initWithBridge:bridge_ defaults:defaults_ builtinURL:nil];
    NSData *rom = [sources romDataForCanonicalID:canonical error:nil];
    XCTAssertNotNil(rom); if (!rom) return;
    FlyNesRuntimeBridge *runtime = [[FlyNesRuntimeBridge alloc] init];
    XCTAssertTrue([runtime createRuntime:nil]); XCTAssertTrue([runtime loadRom:rom error:nil]);
    XCTAssertTrue([runtime stepFrameWithButtons:0 error:nil]);
    NSData *checkpoint = [runtime saveCheckpoint:nil]; XCTAssertNotNil(checkpoint);
    [runtime destroyRuntime];
    if (!checkpoint) return;
    NSString *safe = [[[canonical stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
        stringByReplacingOccurrencesOfString:@":" withString:@"_"] stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
    NSURL *directory = [[root_ URLByAppendingPathComponent:@"saves"] URLByAppendingPathComponent:safe];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *file = [directory URLByAppendingPathComponent:@"autosave.nst"];
    XCTAssertTrue([checkpoint writeToURL:file options:NSDataWritingAtomic error:nil]);
    XCTAssertTrue([bridge_ applySettings:@{@"autosave_enabled":@1} error:nil]);
    NSDictionary *resume = [self call:@"resumeCapability" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(resume[@"state"], @"available");
    XCTAssertTrue([bridge_ applySettings:@{@"autosave_enabled":@0} error:nil]);
    resume = [self call:@"resumeCapability" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertEqualObjects(resume[@"state"], @"none");
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:file], checkpoint);
}
- (void)testPresentationHandshakeUsesDartFrameNumberField {
    if (!service_) return;
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        XCTAssertEqualObjects(method, @"presentationReady");
        XCTAssertEqualObjects(args[@"token"], @"current-frame");
        XCTAssertEqualObjects(args[@"frameNumber"], @42);
        completion(@{@"accepted":@YES}, nil);
    };
    NSString *error;
    NSDictionary *result = [self call:@"presentationReady" args:@{@"token":@"current-frame", @"frameNumber":@42} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(result[@"accepted"], @YES);
}
- (void)testPickerImportDeduplicatesAndRemovalPreservesROMAndFavorite {
    if (!service_) return;
    NSString *error;
    [self call:@"bootstrap" args:@{} error:&error];
    NSDictionary *original = [[bridge_ catalogSnapshotGames] firstObject];
    NSString *canonical = original[@"canonicalId"];
    XCTAssertNotNil(canonical); if (!canonical) return;
    CatalogSourceService *sources = [[CatalogSourceService alloc] initWithBridge:bridge_ defaults:defaults_ builtinURL:nil];
    NSData *rom = [sources romDataForCanonicalID:canonical error:nil];
    XCTAssertNotNil(rom); if (!rom) return;
    NSURL *file = [root_ URLByAppendingPathComponent:@"product-import.nes"];
    XCTAssertTrue([rom writeToURL:file options:NSDataWritingAtomic error:nil]);
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        XCTAssertEqualObjects(method, @"pickSource"); completion(@{@"url":file}, nil);
    };
    for (int i = 0; i < 2; ++i) {
        NSDictionary *result = [self call:@"pickSource" args:@{@"kind":@"file"} error:&error];
        XCTAssertNil(error); XCTAssertEqualObjects(result[@"status"], @"completed");
        XCTAssertNil(result[@"url"], @"Native provider URLs must not escape through the channel");
    }
    NSDictionary *projection = [self call:@"sources" args:@{} error:&error];
    NSArray *rows = projection[@"items"];
    XCTAssertEqual(rows.count, 2u, @"Builtin and one stable imported source");
    NSDictionary *imported = rows.count > 1 ? rows[1] : nil;
    if (!imported) return;
    XCTAssertEqualObjects(imported[@"count"], @1);
    [self call:@"setFavorite" args:@{@"canonicalId":canonical, @"value":@YES} error:&error];
    XCTAssertNil(error);
    [self call:@"removeSource" args:@{@"uuid":imported[@"uuid"]} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects([NSData dataWithContentsOfURL:file], rom);
    NSDictionary *item = [self call:@"catalogItem" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(item[@"favorite"], @YES);
    XCTAssertEqualObjects(item[@"builtin"], @YES);
}
- (void)testOwnerRecreationPreservesCheckpointBookmarksIdentitySettingsAndLayout {
    if (!service_) return;
    NSString *error;
    [self call:@"bootstrap" args:@{} error:&error];
    NSDictionary *row = [[bridge_ catalogSnapshotGames] firstObject];
    NSString *canonical = row[@"canonicalId"];
    XCTAssertNotNil(canonical); if (!canonical) return;
    CatalogSourceService *sourceOwner = [[CatalogSourceService alloc] initWithBridge:bridge_ defaults:defaults_ builtinURL:nil];
    NSData *rom = [sourceOwner romDataForCanonicalID:canonical error:nil];
    XCTAssertNotNil(rom); if (!rom) return;
    NSURL *sourceFile = [root_ URLByAppendingPathComponent:@"retained-source.nes"];
    XCTAssertTrue([rom writeToURL:sourceFile options:NSDataWritingAtomic error:nil]);
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        completion(@{@"url":sourceFile}, nil);
    };
    [self call:@"pickSource" args:@{@"kind":@"file"} error:&error]; XCTAssertNil(error);
    NSDictionary *sourceProjection = [self call:@"sources" args:@{} error:&error];
    NSArray *sourceRows = sourceProjection[@"items"];
    XCTAssertEqual(sourceRows.count, 2u); if (sourceRows.count != 2) return;
    NSString *sourceUUID = sourceRows[1][@"uuid"];
    [self call:@"setFavorite" args:@{@"canonicalId":canonical, @"value":@YES} error:&error]; XCTAssertNil(error);
    [self call:@"patchSetting" args:@{@"key":@"directionMode", @"value":@3} error:&error]; XCTAssertNil(error);
    [self call:@"patchSetting" args:@{@"key":@"audioEnabled", @"value":@NO} error:&error]; XCTAssertNil(error);
    NSString *layout = @(flynes::product::ControlLayoutV2::recommended().with_opacity(0.63f).encode().c_str());
    XCTAssertTrue([bridge_ controlLayoutApply:layout error:nil]);
    FlyNesRuntimeBridge *runtime = [[FlyNesRuntimeBridge alloc] init];
    XCTAssertTrue([runtime createRuntime:nil]); XCTAssertTrue([runtime loadRom:rom error:nil]);
    XCTAssertTrue([runtime stepFrameWithButtons:1 error:nil]);
    NSData *checkpoint = [runtime saveCheckpoint:nil]; [runtime destroyRuntime];
    XCTAssertNotNil(checkpoint); if (!checkpoint) return;
    NSURL *save = FlyNesLegacyAutosaveURL(root_, canonical);
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:save.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil]);
    XCTAssertTrue([checkpoint writeToURL:save options:NSDataWritingAtomic error:nil]);
    NSDictionary *bookmarks = [[defaults_ dictionaryForKey:@"flynes.source_uuid_bookmarks_v1"] copy];
    XCTAssertEqual(bookmarks.count, 1u);
    XCTAssertTrue([defaults_ synchronize]);
    service_.platformHandler = nil; service_ = nil; sourceOwner = nil; bridge_ = nil;

    defaults_ = [[NSUserDefaults alloc] initWithSuiteName:suite_];
    bridge_ = [[FlyNesAppBridge alloc] init];
    XCTAssertTrue([bridge_ createWithDataRoot:root_.path cacheRoot:root_.path error:nil]);
    sourceOwner = [[CatalogSourceService alloc] initWithBridge:bridge_ defaults:defaults_ builtinURL:nil];
    service_ = [[NSClassFromString(@"FlyNesProductService") alloc] initWithBridge:bridge_ sources:sourceOwner
        defaults:defaults_ bundle:NSBundle.mainBundle documentsRoot:root_];
    generation_ = [service_ activateContext:@{@"route":@"hall", @"purpose":@"single", @"returnToken":@""}][@"hostGeneration"];
    [self call:@"bootstrap" args:@{} error:&error]; XCTAssertNil(error);
    XCTAssertEqualObjects([defaults_ dictionaryForKey:@"flynes.source_uuid_bookmarks_v1"], bookmarks);
    sourceProjection = [self call:@"sources" args:@{} error:&error];
    sourceRows = sourceProjection[@"items"];
    XCTAssertEqual(sourceRows.count, 2u);
    if (sourceRows.count == 2) XCTAssertEqualObjects(sourceRows[1][@"uuid"], sourceUUID);
    XCTAssertEqualObjects([sourceOwner romDataForCanonicalID:canonical error:nil], rom);
    NSDictionary *item = [self call:@"catalogItem" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertNil(error); XCTAssertEqualObjects(item[@"canonicalId"], canonical); XCTAssertEqualObjects(item[@"favorite"], @YES);
    NSDictionary *settings = [self call:@"settings" args:@{} error:&error];
    XCTAssertEqualObjects(settings[@"values"][@"directionMode"], @3);
    XCTAssertEqualObjects(settings[@"values"][@"audioEnabled"], @NO);
    XCTAssertEqualObjects([bridge_ controlLayoutGet], layout);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:save], checkpoint);
    NSDictionary *resume = [self call:@"resumeCapability" args:@{@"canonicalId":canonical} error:&error];
    XCTAssertEqualObjects(resume[@"state"], @"available");
    FlyNesRuntimeBridge *restored = [[FlyNesRuntimeBridge alloc] init];
    XCTAssertTrue([restored createRuntime:nil]); XCTAssertTrue([restored loadRom:rom error:nil]);
    XCTAssertTrue([restored loadCheckpoint:[NSData dataWithContentsOfURL:save] error:nil]);
    [restored destroyRuntime];
    // The same content also exists in the builtin source. Explicitly rescan this
    // retained UUID so a successful builtin fallback cannot mask a bad bookmark.
    NSError *sourceError = nil;
    XCTAssertTrue([sourceOwner rescanUUID:sourceUUID error:&sourceError], @"%@", sourceError);
    BOOL importedFresh = NO;
    for (NSDictionary *entry in [bridge_ catalogSnapshotGames]) {
        if ([entry[@"sourceUUID"] isEqual:sourceUUID] && [entry[@"canonicalId"] isEqual:canonical])
            importedFresh = [entry[@"freshness"] unsignedIntValue] == 1;
    }
    XCTAssertTrue(importedFresh, @"The persisted bookmark must reopen the original imported ROM");
}
- (void)testDeactivatedHostRejectsOldRequestsUntilExplicitReattachment {
    if (!service_) return;
    XCTAssertTrue([service_ respondsToSelector:@selector(deactivateContext)],
        @"Native close must revoke the Flutter host lease without destroying the owner");
    if (![service_ respondsToSelector:@selector(deactivateContext)]) return;
    NSDictionary *before = bridge_.settingsGet;
    [service_ deactivateContext];
    NSString *error;
    [self call:@"patchSetting" args:@{@"key":@"audioEnabled", @"value":@NO} error:&error];
    XCTAssertEqualObjects(error, @"stale_host"); XCTAssertEqualObjects(bridge_.settingsGet, before);
    generation_ = [service_ activateContext:@{@"route":@"hall", @"purpose":@"single", @"returnToken":@"reattached"}][@"hostGeneration"];
    XCTAssertNotNil([self call:@"settings" args:@{} error:&error]); XCTAssertNil(error);
}
- (void)testLateNativeLaunchCompletionCannotInvalidateReplacementHost {
    if (!service_) return;
    NSString *error;
    [self call:@"bootstrap" args:@{} error:&error];
    NSString *canonical = [[bridge_ catalogSnapshotGames] firstObject][@"canonicalId"];
    XCTAssertNotNil(canonical); if (!canonical) return;
    NSDictionary *titleRow = [[bridge_ productCatalogSnapshot:nil] itemForCanonicalID:canonical];
    NSDictionary *expectedTitles = @{@"titleEn":titleRow[@"titleEn"] ?: @"",
        @"titleZhHans":titleRow[@"titleZhHans"] ?: @""};
    XCTestExpectation *entered = [self expectationWithDescription:@"native game presented"];
    XCTestExpectation *returned = [self expectationWithDescription:@"old native game returned"];
    __block FlyNesProductCompletion nativeReturn;
    __block NSMutableArray *events = [NSMutableArray array];
    service_.eventHandler = ^(NSString *method, NSDictionary *event) { [events addObject:method]; };
    service_.platformHandler = ^(NSString *method, NSDictionary *args, FlyNesProductCompletion completion) {
        XCTAssertEqualObjects(method, @"launch"); nativeReturn = [completion copy]; [entered fulfill];
        XCTAssertEqualObjects(args[@"titleFields"], expectedTitles,
            @"Native pause must retain both catalog titles without querying the catalog on locale changes");
    };
    [service_ handleMethod:@"launch" arguments:@{@"canonicalId":canonical, @"purpose":@"single", @"requestId":@99, @"hostGeneration":generation_}
        completion:^(NSDictionary *result, NSString *failure) {
            XCTAssertNil(result); XCTAssertEqualObjects(failure, @"stale_host"); [returned fulfill];
        }];
    [self waitForExpectations:@[entered] timeout:15];
    generation_ = [service_ activateContext:@{@"route":@"settings", @"purpose":@"single", @"returnToken":@"new-host"}][@"hostGeneration"];
    [events removeAllObjects];
    if (nativeReturn) nativeReturn(@{@"status":@"returned"}, nil);
    [self waitForExpectations:@[returned] timeout:5];
    XCTAssertEqual(events.count, 0u, @"A stale native return must not publish invalidation to the replacement host");
    nativeReturn = nil; service_.eventHandler = nil;
}
@end

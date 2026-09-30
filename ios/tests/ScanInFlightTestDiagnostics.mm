#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if FLYNES_UI_TEST_PEER && TARGET_OS_SIMULATOR
#import "FlyNesBookmarkStore.h"
#import <objc/runtime.h>
#include <mutex>

// Test-only exclusive real file coordination. No fake scan results or input.
// The sole accepted target is the independently staged licensed Hundred folder.
static NSString *scanRun, *scanPath, *scanUUID;
static std::mutex scanStateMutex;
static NSMutableDictionary *scanState;
static IMP originalScanRead;
static NSString *scanMarker(NSString *suffix) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"scan-inflight-%@-%@", scanRun, suffix]];
}
static void scanPublish(NSDictionary *patch) {
    std::lock_guard<std::mutex> lock(scanStateMutex);
    if (!scanState) scanState = [@{@"run":scanRun, @"pid":@(NSProcessInfo.processInfo.processIdentifier)} mutableCopy];
    [scanState addEntriesFromDictionary:patch];
    [scanState writeToFile:scanMarker(@"state.plist") atomically:YES];
}
static BOOL scanReleased() {
    return [[NSString stringWithContentsOfFile:scanMarker(@"release.txt")
        encoding:NSUTF8StringEncoding error:nil] isEqual:scanRun];
}
static void observeScanRead(id owner, SEL selector, NSURL *url,
    NSFileCoordinatorReadingOptions options, NSError **error, void (^accessor)(NSURL *)) {
    NSString *target;
    { std::lock_guard<std::mutex> lock(scanStateMutex); target = scanPath; }
    if (!target || ![url.URLByStandardizingPath.path isEqual:target]) {
        ((void (*)(id, SEL, NSURL *, NSFileCoordinatorReadingOptions, NSError **, void (^)(NSURL *)))
            originalScanRead)(owner, selector, url, options, error, accessor);
        return;
    }
    scanPublish(@{@"readAttempted":@YES});
    ((void (*)(id, SEL, NSURL *, NSFileCoordinatorReadingOptions, NSError **, void (^)(NSURL *)))
        originalScanRead)(owner, selector, url, options, error, ^(NSURL *coordinated) {
            scanPublish(@{@"readGranted":@YES}); accessor(coordinated);
        });
    scanPublish(@{@"readReturned":@YES});
}

@interface ScanInFlightTestDiagnostics : NSObject
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSDate *commandDeadline;
@end
@implementation ScanInFlightTestDiagnostics
+ (void)load {
    NSString *run = NSProcessInfo.processInfo.environment[@"FLYNES_SCAN_HOLD_RUN"];
    if (![[NSUUID alloc] initWithUUIDString:run]) return;
    scanRun = run;
    Method method = class_getInstanceMethod(NSFileCoordinator.class,
        @selector(coordinateReadingItemAtURL:options:error:byAccessor:));
    originalScanRead = method_setImplementation(method, (IMP)observeScanRead);
    dispatch_async(dispatch_get_main_queue(), ^{
        static ScanInFlightTestDiagnostics *observer;
        observer = [ScanInFlightTestDiagnostics new];
        observer.commandDeadline = [NSDate dateWithTimeIntervalSinceNow:90];
        observer.timer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:observer
            selector:@selector(checkCommand) userInfo:nil repeats:YES];
        scanPublish(@{@"phase":@"waiting", @"readAttempted":@NO, @"readGranted":@NO,
            @"readReturned":@NO, @"expired":@NO});
    });
}
- (void)checkCommand {
    NSDictionary *command = [NSDictionary dictionaryWithContentsOfFile:scanMarker(@"command.plist")];
    if (!command) {
        if (self.commandDeadline.timeIntervalSinceNow <= 0) {
            [self.timer invalidate]; self.timer = nil;
            scanPublish(@{@"phase":@"expired-before-command", @"expired":@YES});
        }
        return;
    }
    [self.timer invalidate]; self.timer = nil; // Exactly one bounded command.
    NSString *uuid = command[@"sourceUUID"];
    if (![command[@"run"] isEqual:scanRun] || ![[NSUUID alloc] initWithUUIDString:uuid] ||
        ![command[@"sourceName"] isEqual:@"FlyNES-E2E-Hundred"]) {
        scanPublish(@{@"phase":@"rejected-command"}); return;
    }
    NSArray *sources = [NSUserDefaults.standardUserDefaults arrayForKey:@"flynes.source_metadata_v1"];
    NSArray *matches = [sources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"uuid == %@", uuid]];
    if (matches.count != 1 || ![matches[0][@"name"] isEqual:@"FlyNES-E2E-Hundred"] ||
        [matches[0][@"scope"] intValue] != 2) {
        scanPublish(@{@"phase":@"rejected-source"}); return;
    }
    FlyNesBookmarkStore *bookmarks = [[FlyNesBookmarkStore alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    BOOL access = NO; NSError *failure = nil;
    NSURL *url = [bookmarks resolveUUID:[[NSUUID alloc] initWithUUIDString:uuid] didStartAccess:&access error:&failure];
    NSString *path = url.URLByStandardizingPath.path;
    NSData *manifestData = [NSData dataWithContentsOfURL:[url.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"manifest.json"]];
    NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil] : nil;
    BOOL valid = url && [path isEqual:url.URLByResolvingSymlinksInPath.path] &&
        [path.lastPathComponent isEqual:@"FlyNES-E2E-Hundred"] &&
        [path.stringByDeletingLastPathComponent.lastPathComponent isEqual:@"FlyNES-Import-E2E-v1"] &&
        [manifest[@"owner"] isEqual:@"FlyNES-Import-E2E-v1"] &&
        [manifest[@"fixture_sha256"] isEqual:@"ee51cd9562f28195ba015d9857c6c4fc9bf67cdfb213e95f655e586b92195173"] &&
        [manifest[@"directory_rom_count"] intValue] == 200;
    if (!valid) {
        if (access) [bookmarks stopAccessing:url];
        scanPublish(@{@"phase":@"rejected-fixture"}); return;
    }
    { std::lock_guard<std::mutex> lock(scanStateMutex); scanPath = path; scanUUID = uuid; }
    scanPublish(@{@"phase":@"acquiring", @"sourceUUID":uuid});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileCoordinator *writer = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL entered = NO;
        // Bound even acquisition; never leave a coordinator waiting forever.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [writer cancel]; });
        NSError *error = nil;
        [writer coordinateWritingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *owned) {
            (void)owned;
            entered = YES;
            scanPublish(@{@"phase":@"held", @"held":@YES});
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
            while (!scanReleased() && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
            scanPublish(@{@"held":@NO, @"phase":@"releasing", @"expired":@(!scanReleased())});
        }];
        if (access) [bookmarks stopAccessing:url];
        scanPublish(@{@"phase":entered && !error ? @"released" : @"coordination-failed"});
    });
}
@end
#endif

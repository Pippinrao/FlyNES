#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if FLYNES_UI_TEST_PEER && TARGET_OS_SIMULATOR
#import "FlyNesNearbyBridge.h"
#import "RunSurfaceViewController.h"
#import <objc/runtime.h>
#import <os/log.h>
#include "flynes/flynes_nearby_mvp.h"
#include <cstring>
#include <mutex>

// Test-only observation of the App's existing owner. No second session, automatic
// ROM selection, input, stepping, pause or resume is created here.
static NSString *twoRun, *twoRole, *twoError;
static NSUInteger replacements, nonzeroInputs;
static BOOL attemptedJoin;
static BOOL publishedInvite;
static std::mutex appliedMutex;
static NSMutableArray<NSDictionary *> *appliedEdges;
static uint64_t appliedSerial;
static uint64_t diagnosticCallbacks, observedSubmissions;
static uint32_t lastObservedSubmittedButtons;
static uint64_t overlaySerial, displayTickSerial;
static double lastDisplayTickTime;
static NSMutableArray<NSDictionary *> *overlayEvents, *displayTickEvents;
static void (*originalOverlay)(id, SEL, uint32_t);
static void (*originalTick)(id, SEL, CFTimeInterval);
static void observedOverlay(id surface, SEL command, uint32_t buttons) {
    const double now = NSProcessInfo.processInfo.systemUptime;
    originalOverlay(surface, command, buttons);
    std::lock_guard<std::mutex> lock(appliedMutex);
    if (!overlayEvents) overlayEvents = [NSMutableArray array];
    [overlayEvents addObject:@{@"serial":@(++overlaySerial), @"time":@(now), @"buttons":@(buttons),
        @"surface":[NSString stringWithFormat:@"%p", (__bridge void *)surface],
        @"previousTickSerial":@(displayTickSerial), @"previousTickTime":@(lastDisplayTickTime)}];
    if (overlayEvents.count > 128) [overlayEvents removeObjectAtIndex:0];
}
static void observedTick(id surface, SEL command, CFTimeInterval timestamp) {
    const double now = NSProcessInfo.processInfo.systemUptime;
    NSString *identity = [NSString stringWithFormat:@"%p", (__bridge void *)surface];
    uint64_t serial;
    {
        std::lock_guard<std::mutex> lock(appliedMutex);
        serial = ++displayTickSerial; lastDisplayTickTime = now;
        // Keep the first subsequent callback on each transition itself. The
        // bounded tick ring may roll over during the existing 60s failure wait.
        for (NSUInteger index = overlayEvents.count; index > 0; --index) {
            NSDictionary *event = overlayEvents[index - 1];
            if (![event[@"surface"] isEqual:identity]) continue;
            if (event[@"nextTickSerial"]) break;
            NSMutableDictionary *finished = [event mutableCopy];
            finished[@"nextTickSerial"] = @(serial); finished[@"nextTickTime"] = @(now);
            overlayEvents[index - 1] = finished;
        }
    }
    // Never hold the observation mutex across production/session calls.
    originalTick(surface, command, timestamp);
    {
        std::lock_guard<std::mutex> lock(appliedMutex);
        if (!displayTickEvents) displayTickEvents = [NSMutableArray array];
        [displayTickEvents addObject:@{@"serial":@(serial), @"time":@(now),
            @"endTime":@(NSProcessInfo.processInfo.systemUptime),
            @"displayTimestamp":@(timestamp), @"surface":identity}];
        if (displayTickEvents.count > 128) [displayTickEvents removeObjectAtIndex:0];
    }
}
// The existing core diagnostic fires on every applied transition, including
// rollback frames. Record there, not by a timer that can miss a short pulse.
static void observeCoreInput(void *, const char *line) {
    os_log_info(OS_LOG_DEFAULT, "FlyNesNearby %{public}s", line);
    @autoreleasepool {
    NSString *text = @(line);
    const BOOL submitted = [text containsString:@"event=input_submit "];
    const BOOL applied = [text containsString:@"event=input_apply "];
    {
        std::lock_guard<std::mutex> lock(appliedMutex);
        ++diagnosticCallbacks;
        if (submitted) ++observedSubmissions;
    }
    if (!applied && !submitted) return;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *part in [text componentsSeparatedByString:@" "]) {
        NSArray *pair = [part componentsSeparatedByString:@"="];
        if (pair.count == 2) fields[pair[0]] = pair[1];
    }
    std::lock_guard<std::mutex> lock(appliedMutex);
    if (submitted) {
        lastObservedSubmittedButtons = [fields[@"buttons"] unsignedIntValue];
        return;
    }
    if (!fields[@"input_frame"] || !fields[@"p1"] || !fields[@"p2"]) return;
    if (!appliedEdges) appliedEdges = [NSMutableArray array];
    [appliedEdges addObject:@{@"serial":@(++appliedSerial),
        @"frame":@([fields[@"input_frame"] longLongValue]),
        @"p1":@([fields[@"p1"] intValue]), @"p2":@([fields[@"p2"] intValue])}];
    if (appliedEdges.count > 256) [appliedEdges removeObjectAtIndex:0];
    }
}
static NSString *twoPath(NSString *suffix) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"nearby-two-%@-%@", twoRun, suffix]];
}
static BOOL (*originalReplace)(id, SEL, NSError **);
static BOOL (*originalInput)(id, SEL, uint32_t);
static BOOL observedReplace(id owner, SEL command, NSError **error) {
    BOOL result = originalReplace(owner, command, error);
    if (result) {
        ++replacements;
        // Test-only access to the same existing owner. This installs observation
        // only; it never creates a session, advances it, or submits any input.
        Ivar storage = class_getInstanceVariable(FlyNesNearbyBridge.class, "session_");
        fly_lan_mvp_session *session = nullptr;
        if (storage) std::memcpy(&session,
            (const unsigned char *)(__bridge const void *)owner + ivar_getOffset(storage), sizeof(session));
        if (session) fly_lan_mvp_set_diagnostic_sink(session, observeCoreInput, nullptr);
        else twoError = @"Cannot observe the existing core input sink";
    }
    return result;
}
static BOOL observedInput(id owner, SEL command, uint32_t buttons) {
    BOOL result = originalInput(owner, command, buttons);
    if (result && buttons != 0) ++nonzeroInputs;
    return result;
}
@interface NearbyTwoAppDiagnostics : NSObject
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation NearbyTwoAppDiagnostics
+ (void)load {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *run = env[@"FLYNES_TWO_APP_RUN"], *role = env[@"FLYNES_TWO_APP_ROLE"];
    if (![[NSUUID alloc] initWithUUIDString:run] ||
        (![role isEqual:@"host"] && ![role isEqual:@"guest"])) return;
    twoRun = run; twoRole = role; twoError = @"";
    if (env[@"FLYNES_UI_NEARBY_ROLE"]) { twoError = @"In-process peer fixture is forbidden"; return; }
    Method replace = class_getInstanceMethod(FlyNesNearbyBridge.class, NSSelectorFromString(@"replaceSession:"));
    Method input = class_getInstanceMethod(FlyNesNearbyBridge.class, @selector(stepWithButtons:));
    Method overlay = class_getInstanceMethod(RunSurfaceViewController.class, NSSelectorFromString(@"applyOverlayButtons:"));
    Method tick = class_getInstanceMethod(RunSurfaceViewController.class, NSSelectorFromString(@"displayTick:"));
    if (!replace || !input || !overlay || !tick) { twoError = @"Cannot observe existing input/tick methods"; return; }
    originalReplace = (BOOL (*)(id, SEL, NSError **))method_setImplementation(replace, (IMP)observedReplace);
    originalInput = (BOOL (*)(id, SEL, uint32_t))method_setImplementation(input, (IMP)observedInput);
    originalOverlay = (void (*)(id, SEL, uint32_t))method_setImplementation(overlay, (IMP)observedOverlay);
    originalTick = (void (*)(id, SEL, CFTimeInterval))method_setImplementation(tick, (IMP)observedTick);
    dispatch_async(dispatch_get_main_queue(), ^{
        static NearbyTwoAppDiagnostics *observer;
        observer = [NearbyTwoAppDiagnostics new];
        observer.timer = [NSTimer timerWithTimeInterval:0.05 target:observer selector:@selector(publish) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:observer.timer forMode:NSRunLoopCommonModes];
        [observer publish];
    });
}
- (void)publish {
    FlyNesNearbyBridge *owner = FlyNesNearbyBridge.sharedInstance;
    if ([twoRole isEqual:@"host"] && owner.inviteText.length && !publishedInvite) {
        publishedInvite = YES;
        NSData *invite = [owner.inviteText dataUsingEncoding:NSUTF8StringEncoding];
        if ([NSFileManager.defaultManager fileExistsAtPath:twoPath(@"invite.txt")] ||
            ![NSFileManager.defaultManager createFileAtPath:twoPath(@"invite.txt") contents:invite
            attributes:@{NSFilePosixPermissions: @0600}]) twoError = @"Cannot publish invitation";
    }
    NSString *joinPath = twoPath(@"join.txt");
    if ([twoRole isEqual:@"guest"] && !attemptedJoin && [NSFileManager.defaultManager fileExistsAtPath:joinPath]) {
        attemptedJoin = YES;
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:joinPath error:nil];
        if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) twoError = @"Invalid join marker";
        else {
            NSString *invite = [NSString stringWithContentsOfFile:joinPath encoding:NSUTF8StringEncoding error:nil];
            NSError *error = nil;
            if (![invite hasPrefix:@"flynes-lan-v1:"] || invite.length > 1024 || ![owner joinInvite:invite error:&error])
                twoError = @"Actual host invitation could not join";
        }
    }
    BOOL stopped = [[NSString stringWithContentsOfFile:twoPath(@"stop.txt") encoding:NSUTF8StringEncoding error:nil] isEqual:twoRun];
    NSArray *edges, *touches, *ticks;
    uint64_t serial, callbacks, submissions, overlayCount, tickCount;
    uint32_t submittedButtons;
    { // Release before owner.snapshot: diagnostic callback holds session lock.
        std::lock_guard<std::mutex> lock(appliedMutex);
        edges = [appliedEdges copy] ?: @[]; serial = appliedSerial;
        callbacks = diagnosticCallbacks; submissions = observedSubmissions;
        submittedButtons = lastObservedSubmittedButtons;
        touches = [overlayEvents copy] ?: @[]; ticks = [displayTickEvents copy] ?: @[];
        overlayCount = overlaySerial; tickCount = displayTickSerial;
    }
    NSDictionary *state = @{@"run": twoRun, @"role": twoRole, @"pid": @(NSProcessInfo.processInfo.processIdentifier), @"observerStopped": @(stopped),
        @"snapshot": owner.snapshot, @"generation": @(owner.playbackGeneration), @"key": owner.canonicalId,
        @"replaceCount": @(replacements), @"nonzeroInputCount": @(nonzeroInputs), @"error": twoError,
        @"appliedInputSerial":@(serial), @"appliedInputEdges":edges,
        @"diagnosticCallbackCount":@(callbacks), @"observedInputSubmitCount":@(submissions),
        @"lastObservedSubmittedButtons":@(submittedButtons),
        @"overlayInputSerial":@(overlayCount), @"overlayInputEvents":touches,
        @"displayTickSerial":@(tickCount), @"displayTickEvents":ticks};
    [state writeToFile:twoPath(@"state.plist") atomically:YES];
    if (stopped) { [self.timer invalidate]; self.timer = nil; }
}
@end
#endif

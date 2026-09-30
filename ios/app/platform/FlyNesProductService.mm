#import "FlyNesProductService.h"
#import "CatalogSourceService.h"
#import "FlyNesAppBridge.h"
#import "FlyNesCoverStore.h"
#import "BuiltinGames.h"
#include <flynes/product/control_layout.hpp>
#include <atomic>
#include <cmath>

namespace {
void fail(NSString *code) {
    @throw [NSException exceptionWithName:@"FlyNesProductFailure" reason:code userInfo:nil];
}
NSString *text(NSDictionary *args, NSString *key) {
    id value = args[key];
    if (![value isKindOfClass:NSString.class] || [value rangeOfString:@"\0"].location != NSNotFound) fail(@"invalid_arguments");
    return value;
}
BOOL boolean(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) fail(@"invalid_arguments");
    return [value boolValue];
}
uint64_t number(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        !std::isfinite([value doubleValue]) || [value doubleValue] < 0 || std::floor([value doubleValue]) != [value doubleValue] ||
        [value doubleValue] >= 9223372036854775808.0) fail(@"invalid_arguments");
    return [value unsignedLongLongValue];
}
NSArray<NSString *> *categories() { return @[@"recent", @"favorites", @"all", @"builtin"]; }
NSDictionary<NSString *, NSString *> *settingKeys() {
    return @{@"videoQualityPreset":@"video_quality_preset", @"customRefreshPolicy":@"custom_refresh_policy",
        @"customTemporalMode":@"custom_temporal_mode", @"customSpatialMode":@"custom_spatial_mode",
        @"customPostEffect":@"custom_post_effect", @"aspectMode":@"aspect_mode", @"adaptiveProtection":@"adaptive_protection",
        @"directionMode":@"direction_mode", @"hapticLevel":@"haptic_level", @"distinctAbHaptics":@"distinct_ab_haptics",
        @"audioEnabled":@"audio_enabled", @"audioFocusPolicy":@"audio_focus_policy", @"localeTag":@"locale_tag",
        @"autosaveEnabled":@"autosave_enabled"};
}
BOOL boolSetting(NSString *key) {
    return [@[@"adaptiveProtection", @"distinctAbHaptics", @"audioEnabled", @"autosaveEnabled"] containsObject:key];
}
NSString *exceptionCode(NSException *exception) {
    return [exception.name isEqual:@"FlyNesProductFailure"] ? exception.reason : @"service_unavailable";
}
}

@implementation FlyNesProductService {
    FlyNesAppBridge *bridge_;
    CatalogSourceService *sources_;
    NSUserDefaults *defaults_;
    NSBundle *bundle_;
    NSURL *documents_;
    dispatch_queue_t worker_, sourceWorker_;
    NSString *instance_;
    std::atomic<uint64_t> generation_;
    NSDictionary *context_;
    BOOL observing_, sourceBusy_, active_;
    NSMutableSet<NSNumber *> *pendingNative_;
    NSArray<NSDictionary *> *sourceRows_;
    NSMutableDictionary<NSString *, NSDictionary *> *operations_;
    id coverObserver_;
    // Only worker_ owns these snapshot/query fields.
    FlyNesProductCatalogSnapshot *capture_;
    NSDictionary *query_;
    uint64_t revision_;
}
- (instancetype)initWithBridge:(FlyNesAppBridge *)bridge sources:(CatalogSourceService *)sources
                       defaults:(NSUserDefaults *)defaults bundle:(NSBundle *)bundle documentsRoot:(NSURL *)documentsRoot
{
    if ((self = [super init])) {
        bridge_ = bridge; sources_ = sources; defaults_ = defaults; bundle_ = bundle; documents_ = documentsRoot;
        worker_ = dispatch_queue_create("com.flynes.product", DISPATCH_QUEUE_SERIAL);
        sourceWorker_ = dispatch_queue_create("com.flynes.product.sources", DISPATCH_QUEUE_SERIAL);
        instance_ = NSUUID.UUID.UUIDString; generation_.store(1); active_ = YES;
        context_ = @{@"route":@"hall", @"purpose":@"single", @"returnToken":@""};
        pendingNative_ = [NSMutableSet set]; operations_ = [NSMutableDictionary dictionary]; sourceRows_ = @[];
        __weak FlyNesProductService *weakSelf = self;
        coverObserver_ = [NSNotificationCenter.defaultCenter addObserverForName:FlyNesCoverStoreDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
                [weakSelf invalidateDomains:@[@"catalog", @"covers"]];
            }];
    }
    return self;
}
- (void)dealloc { if (coverObserver_) [NSNotificationCenter.defaultCenter removeObserver:coverObserver_]; }
- (NSDictionary *)envelope:(NSDictionary *)payload request:(id)request generation:(uint64_t)generation
{
    NSMutableDictionary *result = [payload mutableCopy] ?: [NSMutableDictionary dictionary];
    result[@"requestId"] = request ?: @0; result[@"hostGeneration"] = @(generation); result[@"instanceId"] = instance_;
    return [result copy];
}
- (NSDictionary<NSString *, id> *)activateContext:(NSDictionary<NSString *, id> *)context
{
    NSAssert(NSThread.isMainThread, @"Product host leases are main-thread owned");
    context_ = [context copy]; active_ = YES; uint64_t lease = generation_.fetch_add(1) + 1;
    NSDictionary *event = [self envelope:@{@"context":context_} request:@0 generation:lease];
    if (observing_ && self.eventHandler) self.eventHandler(@"contextChanged", event);
    return event;
}
- (void)deactivateContext
{
    NSAssert(NSThread.isMainThread, @"Product host leases are main-thread owned");
    active_ = NO;
    generation_.fetch_add(1);
}
- (void)invalidateDomains:(NSArray<NSString *> *)domains
{
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self invalidateDomains:domains]; }); return; }
    if (active_ && observing_ && self.eventHandler)
        self.eventHandler(@"projectionChanged", [self envelope:@{@"domains":[domains copy]} request:@0 generation:generation_.load()]);
}
- (NSDictionary *)capabilities
{
    NSMutableDictionary *caps = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"videoQualityPreset.3", @"customTemporalMode.2", @"customRefreshPolicy.4", @"customRefreshPolicy.5"])
        caps[key] = @{@"available":@NO, @"reason":@"hardware_evidence_required"};
    caps[@"customRefreshPolicy.2"] = @{@"available":@NO, @"reason":@"unsupported_option"};
    caps[@"cancelScan"] = @{@"available":@NO, @"reason":@"cancellation_unavailable"};
    return caps;
}
- (NSDictionary *)navigation
{
    NSString *category = [[defaults_ stringForKey:@"GameCenterCategory"] lowercaseString] ?: @"all";
    if (![categories() containsObject:category]) category = @"all";
    NSMutableDictionary *selections = [NSMutableDictionary dictionary];
    for (NSString *key in categories()) selections[key] = [defaults_ stringForKey:[@"GameCenterSelected." stringByAppendingString:key.uppercaseString]] ?: @"";
    return @{@"category":category, @"multiplayerOnly":@([defaults_ boolForKey:@"GameCenterMultiplayerOnly"]), @"selections":selections};
}
- (NSDictionary *)settings
{
    NSDictionary *native = bridge_.settingsGet;
    if (!native.count) fail(@"read_failed");
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSDictionary *keys = settingKeys();
    for (NSString *key in keys) {
        id value = native[keys[key]];
        if (!value) fail(@"read_failed");
        values[key] = boolSetting(key) ? @([value boolValue]) : value;
    }
    NSString *recommended = @(flynes::product::ControlLayoutV2::recommended().encode().c_str());
    NSString *layout = bridge_.controlLayoutGet;
    return @{@"values":values, @"capabilities":[self capabilities],
             @"layoutSummary":layout.length == 0 ? @"unavailable" : [layout isEqual:recommended] ? @"recommended" : @"custom"};
}
- (NSDictionary *)item:(NSString *)canonical snapshot:(FlyNesProductCatalogSnapshot *)snapshot
{
    NSDictionary *row = [snapshot itemForCanonicalID:canonical];
    if (!row) fail(@"not_found");
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"canonicalId", @"titleEn", @"titleZhHans", @"available", @"unavailableReason", @"favorite", @"builtin", @"variantCount", @"multiplayerSupported"])
        item[key] = row[key];
    [item addEntriesFromDictionary:[FlyNesCoverStore.sharedInstance referenceForCanonicalId:canonical]];
    return [item copy];
}
- (FlyNesProductCatalogSnapshot *)snapshot
{
    FlyNesProductCatalogSnapshot *snapshot = [bridge_ productCatalogSnapshot:nil];
    if (!snapshot) fail(@"read_failed");
    return snapshot;
}
- (NSDictionary *)window:(uint64_t)offset limit:(uint32_t)limit
{
    if (!capture_ || !query_) fail(@"snapshot_expired");
    NSError *error = nil;
    NSDictionary *window = [capture_ project:query_ offset:offset limit:limit error:&error];
    if (!window) fail(@"invalid_arguments");
    NSMutableDictionary *result = [window mutableCopy];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *canonical in window[@"ids"]) [items addObject:[self item:canonical snapshot:capture_]];
    [result removeObjectForKey:@"ids"]; result[@"items"] = items; result[@"viewRevision"] = @(revision_);
    return result;
}
- (NSArray<NSDictionary *> *)sourceProjection
{
    FlyNesProductCatalogSnapshot *snapshot = [self snapshot];
    NSMutableDictionary<NSString *, NSMutableSet *> *counts = [NSMutableDictionary dictionary];
    for (NSDictionary *row in snapshot.rows) {
        NSString *uuid = row[@"sourceUUID"];
        if (!counts[uuid]) counts[uuid] = [NSMutableSet set];
        [counts[uuid] addObject:row[@"canonicalId"]];
    }
    NSString *builtinUUID = @"6FC22AA9-81CC-4CBB-A5F3-018A480B0001";
    NSMutableArray *result = [NSMutableArray arrayWithObject:@{@"uuid":@"builtin", @"name":@"Built-in games",
        @"type":@"builtin", @"count":@(counts[builtinUUID].count), @"status":@"completed", @"reason":@"",
        @"builtin":@YES, @"canReauthorize":@NO, @"canCancel":@NO, @"operationId":@"", @"phase":@"completed", @"completed":@0}];
    for (NSDictionary *row in sources_.sources) {
        NSString *uuid = row[@"uuid"];
        BOOL failed = [row[@"error"] length] != 0;
        [result addObject:@{@"uuid":uuid, @"name":row[@"name"], @"type":[row[@"scope"] unsignedIntValue] == 2 ? @"folder" : @"file",
            @"count":@(counts[uuid.uppercaseString].count), @"status":failed ? @"failed" : @"completed", @"reason":failed ? @"source_unavailable" : @"",
            @"builtin":@NO, @"canReauthorize":@(failed), @"canCancel":@NO, @"operationId":@"", @"phase":failed ? @"failed" : @"completed", @"completed":@0}];
    }
    return [result copy];
}
- (NSArray<NSDictionary *> *)licenseEntries
{
    NSMutableArray *entries = [NSMutableArray array];
    for (NSArray *row in @[@[@"FlyNES-GPL-2.0.txt", @"FlyNES"], @[@"Nestopia-GPL-2.0.txt", @"Nestopia UE"],
                           @[@"MMPX-MIT.txt", @"MMPX"], @[@"ScaleFX-MIT.txt", @"ScaleFX"], @[@"zlib-license.txt", @"zlib"]])
        [entries addObject:@{@"id":row[0], @"title":row[1], @"sourceUrl":@""}];
    for (FlyNesBuiltinGame *game in FlyNesBuiltinGames.shared.all) {
        if (game.licenseFile.length) [entries addObject:@{@"id":game.licenseFile, @"title":game.titleEn, @"sourceUrl":game.licenseSourceUrl ?: @""}];
    }
    return [entries copy];
}
- (NSDictionary *)perform:(NSString *)method args:(NSDictionary *)args context:(NSDictionary *)context
{
    if ([method isEqual:@"bootstrap"]) {
        NSError *error = nil;
        if (![sources_ prepareBuiltin:&error]) fail(@"read_failed");
        NSArray *rows = [self sourceProjection];
        dispatch_async(dispatch_get_main_queue(), ^{ self->sourceRows_ = rows; });
        NSString *locale = bridge_.settingsGet[@"locale_tag"] ?: @"system";
        return @{@"protocolVersion":@1, @"localePreference":locale,
            @"locale":[locale isEqual:@"system"] ? (NSLocale.preferredLanguages.firstObject ?: @"en") : locale,
            @"version":[bundle_ objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
            @"buildRevision":[bundle_ objectForInfoDictionaryKey:@"FlyNesBuildRevision"] ?: @"",
            @"context":context, @"capabilities":[self capabilities], @"preferences":[self navigation]};
    }
    if ([method isEqual:@"catalogQuery"]) {
        NSString *category = text(args, @"category"), *search = text(args, @"query"), *selected = text(args, @"selectedId");
        if (![categories() containsObject:category]) fail(@"invalid_arguments");
        boolean(args[@"multiplayerOnly"]);
        text(args, @"locale");
        capture_ = [self snapshot]; query_ = @{@"category":category, @"query":search, @"selectedId":selected, @"multiplayerOnly":args[@"multiplayerOnly"]};
        ++revision_; return [self window:0 limit:128];
    }
    if ([method isEqual:@"catalogWindow"]) {
        if (!capture_ || number(args[@"viewRevision"]) != revision_ || number(args[@"catalogGeneration"]) != capture_.generation) fail(@"snapshot_expired");
        uint64_t limit = number(args[@"limit"]); if (!limit || limit > 128) fail(@"invalid_arguments");
        return [self window:number(args[@"offset"]) limit:(uint32_t)limit];
    }
    if ([method isEqual:@"catalogItem"]) return [self item:text(args, @"canonicalId") snapshot:[self snapshot]];
    if ([method isEqual:@"resumeCapability"]) {
        NSString *canonical = text(args, @"canonicalId");
        NSDictionary *item = [self item:canonical snapshot:[self snapshot]];
        if (![item[@"available"] boolValue]) return @{@"state":@"unavailable", @"reason":@"source_unavailable"};
        if (![bridge_.settingsGet[@"autosave_enabled"] boolValue]) return @{@"state":@"none", @"reason":@""};
        NSURL *url = FlyNesLegacyAutosaveURL(documents_, canonical);
        if (!url) fail(@"resume_unavailable");
        NSError *error = nil;
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&error];
        if (!attrs && [error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError)
            return @{@"state":@"none", @"reason":@""};
        if (!attrs || ![attrs[NSFileType] isEqual:NSFileTypeRegular] || ![NSFileManager.defaultManager isReadableFileAtPath:url.path])
            return @{@"state":@"unavailable", @"reason":@"resume_unavailable"};
        return @{@"state":[attrs[NSFileSize] unsignedLongLongValue] > 0 ? @"available" : @"none", @"reason":@""};
    }
    if ([method isEqual:@"setFavorite"]) {
        NSString *canonical = text(args, @"canonicalId"); BOOL value = boolean(args[@"value"]);
        [self item:canonical snapshot:[self snapshot]];
        if (![bridge_ setFavorite:value canonicalID:canonical error:nil]) fail(@"write_failed");
        capture_ = nil; [self invalidateDomains:@[@"catalog"]];
        return @{@"canonicalId":canonical, @"favorite":@(value), @"catalogGeneration":@([self snapshot].generation)};
    }
    if ([method isEqual:@"saveNavigation"]) {
        NSString *category = text(args, @"category"); BOOL multiplayer = boolean(args[@"multiplayerOnly"]);
        NSDictionary *selections = args[@"selections"];
        if (![categories() containsObject:category] || ![selections isKindOfClass:NSDictionary.class]) fail(@"invalid_arguments");
        for (NSString *key in selections) { if (![categories() containsObject:key]) fail(@"invalid_arguments"); text(selections, key); }
        [defaults_ setObject:category.uppercaseString forKey:@"GameCenterCategory"];
        [defaults_ setBool:multiplayer forKey:@"GameCenterMultiplayerOnly"];
        for (NSString *key in selections) [defaults_ setObject:selections[key] forKey:[@"GameCenterSelected." stringByAppendingString:key.uppercaseString]];
        return [self navigation];
    }
    if ([method isEqual:@"settings"]) return [self settings];
    if ([method isEqual:@"patchSetting"]) {
        NSString *key = text(args, @"key"); id value = args[@"value"]; NSString *nativeKey = settingKeys()[key];
        if (!nativeKey) fail(@"invalid_arguments");
        if ([key isEqual:@"localeTag"]) { if (![@[@"system", @"en", @"zh-Hans"] containsObject:value]) fail(@"invalid_arguments"); }
        else if (boolSetting(key)) boolean(value);
        else {
            uint64_t maximum = [key isEqual:@"customRefreshPolicy"] ? 5 :
                [@[@"videoQualityPreset", @"customSpatialMode", @"hapticLevel"] containsObject:key] ? 4 :
                [@[@"customTemporalMode", @"customPostEffect"] containsObject:key] ? 2 : 3;
            uint64_t v = number(value); if (v < 1 || v > maximum) fail(@"invalid_arguments");
        }
        if ([self capabilities][[NSString stringWithFormat:@"%@.%@", key, value]]) fail(@"capability_locked");
        if (![bridge_ applySettings:@{nativeKey:value} error:nil]) fail(@"write_failed");
        if ([key isEqual:@"localeTag"]) [defaults_ setObject:value forKey:@"FlyNesLocaleTag"];
        [self invalidateDomains:@[@"settings"]]; return [self settings];
    }
    if ([method isEqual:@"resetControls"]) {
        if (![bridge_ applySettings:@{@"layout_preset":@1, @"direction_mode":@2, @"button_scale":@1.0,
            @"vertical_offset":@0.0, @"control_opacity":@0.78, @"joystick_scale":@1.0,
            @"dead_zone":@0.18, @"haptic_level":@2, @"distinct_ab_haptics":@1} error:nil]) fail(@"write_failed");
        NSString *layout = @(flynes::product::ControlLayoutV2::recommended().encode().c_str());
        if (![bridge_ controlLayoutApply:layout error:nil]) { [self invalidateDomains:@[@"settings"]]; fail(@"reset_incomplete"); }
        [self invalidateDomains:@[@"settings"]]; return [self settings];
    }
    if ([method isEqual:@"licenses"]) return @{@"items":[self licenseEntries]};
    if ([method isEqual:@"licenseText"]) {
        NSString *key = text(args, @"id"); BOOL known = NO;
        for (NSDictionary *row in [self licenseEntries]) if ([row[@"id"] isEqual:key]) known = YES;
        if (!known || [key containsString:@"/"] || [key containsString:@"\\"]) fail(@"invalid_arguments");
        NSURL *url = [bundle_ URLForResource:key.stringByDeletingPathExtension withExtension:key.pathExtension];
        NSString *body = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
        if (!body) fail(@"read_failed"); return @{@"text":body};
    }
    fail(@"not_implemented"); return nil;
}

/// Always resolves once and on main. The captured envelope belongs to the request's lease.
- (FlyNesProductCompletion)replyFor:(NSDictionary *)args lease:(uint64_t)lease completion:(FlyNesProductCompletion)completion
{
    __block BOOL completed = NO;
    return ^(NSDictionary *result, NSString *error) {
        dispatch_block_t finish = ^{
            if (completed) return; completed = YES;
            completion(error ? nil : [self envelope:result request:args[@"requestId"] generation:lease], error);
        };
        if (NSThread.isMainThread) finish(); else dispatch_async(dispatch_get_main_queue(), finish);
    };
}
- (void)platform:(NSString *)method args:(NSDictionary *)args lease:(uint64_t)lease completion:(FlyNesProductCompletion)reply
{
    NSAssert(NSThread.isMainThread, @"Native routes are main-thread owned");
    if (generation_.load() != lease) { reply(nil, @"stale_host"); return; }
    if (!self.platformHandler) { reply(nil, @"service_unavailable"); return; }
    BOOL route = [@[@"launch", @"openNative", @"pickSource"] containsObject:method];
    NSNumber *key = @(lease);
    if (route && [pendingNative_ containsObject:key]) { reply(nil, @"native_busy"); return; }
    if (route) [pendingNative_ addObject:key];
    __block BOOL returned = NO;
    self.platformHandler(method, args, ^(NSDictionary *result, NSString *error) {
        dispatch_block_t finish = ^{
            if (returned) return; returned = YES;
            if (route) [self->pendingNative_ removeObject:key];
            // closeHost acknowledges the very operation that revoked its lease.
            // Other callbacks cannot act on a replacement or hidden host.
            if (![method isEqual:@"closeHost"] && self->generation_.load() != lease) {
                reply(nil, @"stale_host"); return;
            }
            reply(result, error);
        };
        if (NSThread.isMainThread) finish(); else dispatch_async(dispatch_get_main_queue(), finish);
    });
}
- (void)sourceOperation:(NSString *)method args:(NSDictionary *)args URL:(NSURL *)url
                  lease:(uint64_t)lease completion:(FlyNesProductCompletion)reply
{
    if (sourceBusy_) { reply(nil, @"native_busy"); return; }
    NSString *uuid = args[@"uuid"] ?: args[@"sourceUuid"] ?: @"";
    if ([uuid isEqual:@"builtin"]) { reply(nil, @"source_protected"); return; }
    NSString *operation = NSUUID.UUID.UUIDString;
    sourceBusy_ = YES;
    if (uuid.length) operations_[uuid] = @{@"operationId":operation, @"phase":@"scanning", @"status":@"scanning", @"reason":@"", @"canCancel":@NO};
    [self invalidateDomains:@[@"sources"]];
    BOOL rescan = [method isEqual:@"scanSource"];
    if (rescan) reply(@{@"status":@"started", @"operationId":operation}, nil);
    dispatch_async(sourceWorker_, ^{
        NSError *failure = nil; BOOL success = NO;
        @try {
            if ([method isEqual:@"removeSource"]) success = [self->sources_ removeUUID:uuid error:&failure];
            else if (rescan) success = [self->sources_ rescanUUID:uuid error:&failure];
            else if (uuid.length) success = [self->sources_ reauthorizeUUID:uuid URL:url error:&failure];
            else success = [self->sources_ addURL:url directory:[args[@"kind"] isEqual:@"folder"] error:&failure] != nil;
        } @catch (NSException *) { success = NO; }
        NSArray *rows = nil;
        @try { rows = [self sourceProjection]; } @catch (NSException *) { }
        NSString *code = success ? nil : [failure.userInfo[@"scanCommitted"] boolValue] ? @"scan_partial" : @"source_unavailable";
        dispatch_async(dispatch_get_main_queue(), ^{
            self->sourceBusy_ = NO;
            if (rows) self->sourceRows_ = rows;
            if (uuid.length) self->operations_[uuid] = @{@"operationId":operation,
                @"phase":success ? @"completed" : [code isEqual:@"scan_partial"] ? @"partial" : @"failed",
                @"status":success ? @"completed" : @"failed", @"reason":code ?: @"", @"canCancel":@NO};
            [self invalidateDomains:@[@"sources", @"catalog"]];
            if (!rescan) reply(success ? @{@"status":@"completed", @"operationId":operation} : nil, code);
        });
    });
}
- (void)handleMethod:(NSString *)method arguments:(NSDictionary<NSString *, id> *)arguments completion:(FlyNesProductCompletion)completion
{
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self handleMethod:method arguments:arguments completion:completion]; }); return; }
    @try {
        if (![arguments isKindOfClass:NSDictionary.class]) fail(@"invalid_arguments");
        number(arguments[@"requestId"]); uint64_t requested = number(arguments[@"hostGeneration"]), lease = generation_.load();
        if (!active_) fail(@"stale_host");
        BOOL bootstrap = [method isEqual:@"bootstrap"], presentation = [method isEqual:@"presentationContext"];
        if (!bootstrap && !presentation && requested != lease) fail(@"stale_host");
        if ((bootstrap || presentation) && requested != 0 && requested != lease) fail(@"stale_host");
        FlyNesProductCompletion reply = [self replyFor:arguments lease:lease completion:completion];
        NSDictionary *args = [arguments copy], *context = context_;
        if (presentation) { reply(@{@"context":context}, nil); return; }
        if ([method isEqual:@"detach"]) { observing_ = NO; reply(@{@"completed":@YES}, nil); return; }
        if (bootstrap) observing_ = YES;
        if ([method isEqual:@"sources"]) {
            NSMutableArray *items = [NSMutableArray array];
            for (NSDictionary *row in sourceRows_) {
                NSMutableDictionary *item = [row mutableCopy];
                [item addEntriesFromDictionary:operations_[row[@"uuid"]] ?: @{}]; [items addObject:item];
            }
            reply(@{@"items":items, @"folderSelection":@{@"available":@YES, @"reason":@""}}, nil); return;
        }
        if ([method isEqual:@"cancelScan"]) fail(@"cancellation_unavailable");
        if ([@[@"scanSource", @"removeSource"] containsObject:method]) {
            text(args, @"uuid"); [self sourceOperation:method args:args URL:nil lease:lease completion:reply]; return;
        }
        if ([method isEqual:@"pickSource"]) {
            NSString *kind = text(args, @"kind"); if (![@[@"file", @"folder"] containsObject:kind]) fail(@"invalid_arguments");
            if (args[@"sourceUuid"]) text(args, @"sourceUuid");
            if (sourceBusy_) fail(@"native_busy");
            [self platform:method args:args lease:lease completion:^(NSDictionary *result, NSString *error) {
                if (error) { reply(nil, error); return; }
                if ([result[@"status"] isEqual:@"cancelled"]) { reply(@{@"status":@"cancelled", @"operationId":@""}, nil); return; }
                if (self->generation_.load() != lease) { reply(nil, @"stale_host"); return; }
                NSURL *url = result[@"url"];
                if (![url isKindOfClass:NSURL.class] || !url.isFileURL) { reply(nil, @"invalid_arguments"); return; }
                [self sourceOperation:method args:args URL:url lease:lease completion:reply];
            }]; return;
        }
        if ([method isEqual:@"launch"]) {
            NSString *canonical = text(args, @"canonicalId"), *purpose = text(args, @"purpose");
            if (![@[@"single", @"nearby"] containsObject:purpose]) fail(@"invalid_arguments");
            if ([pendingNative_ containsObject:@(lease)]) fail(@"native_busy");
            [pendingNative_ addObject:@(lease)];
            dispatch_async(worker_, ^{
                NSDictionary *payload = nil; NSString *failure = nil;
                @try {
                    if (self->generation_.load() != lease) fail(@"stale_host");
                    NSDictionary *item = [self item:canonical snapshot:[self snapshot]];
                    if (![item[@"available"] boolValue]) fail(@"launch_unavailable");
                    if ([purpose isEqual:@"nearby"] && ![item[@"multiplayerSupported"] boolValue]) fail(@"nearby_unavailable");
                    NSData *rom = [self->sources_ romDataForCanonicalID:canonical error:nil];
                    if (!rom.length) fail(@"launch_unavailable");
                    NSMutableDictionary *next = [args mutableCopy]; next[@"romData"] = rom;
                    next[@"titleFields"] = @{@"titleEn":item[@"titleEn"] ?: @"",
                        @"titleZhHans":item[@"titleZhHans"] ?: @""};
                    NSString *locale = self->bridge_.settingsGet[@"locale_tag"] ?: @"system";
                    if ([locale isEqual:@"system"]) locale = NSLocale.preferredLanguages.firstObject ?: @"en";
                    NSString *title = item[[locale hasPrefix:@"zh"] ? @"titleZhHans" : @"titleEn"];
                    next[@"title"] = title.length ? title : item[@"titleEn"]; payload = next;
                } @catch (NSException *error) { failure = exceptionCode(error); }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->pendingNative_ removeObject:@(lease)];
                    if (failure) { reply(nil, failure); return; }
                    [self platform:method args:payload lease:lease completion:^(NSDictionary *result, NSString *error) {
                        if (self->generation_.load() == lease) [self invalidateDomains:@[@"catalog", @"resume", @"covers"]];
                        reply(result, error);
                    }];
                });
            }); return;
        }
        if ([@[@"openNative", @"previewHaptics", @"openLink", @"copyText", @"presentationReady", @"closeHost"] containsObject:method]) {
            if ([method isEqual:@"openNative"] && ![@[@"layout", @"nearby"] containsObject:text(args, @"page")]) fail(@"invalid_arguments");
            if ([method isEqual:@"copyText"]) text(args, @"text");
            if ([method isEqual:@"openLink"]) {
                NSURLComponents *url = [NSURLComponents componentsWithString:text(args, @"url")];
                if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString] || !url.host.length) fail(@"invalid_arguments");
            }
            if ([method isEqual:@"presentationReady"]) { text(args, @"token"); number(args[@"frameNumber"]); }
            [self platform:method args:args lease:lease completion:reply]; return;
        }
        dispatch_async(worker_, ^{
            @try {
                if (self->generation_.load() != lease) fail(@"stale_host");
                reply([self perform:method args:args context:context], nil);
            } @catch (NSException *error) { reply(nil, exceptionCode(error)); }
        });
    } @catch (NSException *error) { completion(nil, exceptionCode(error)); }
}
@end

#import "RunSurfaceViewController.h"
#import "BuiltinGames.h"
#import "CatalogPresentation.h"

#import "FlyNesAppBridge.h"
#import "FlyNesRuntimeBridge.h"
#import "FlyNesNearbyBridge.h"
#import "GamepadOverlayView.h"
#import "FlyNesMetalRenderer.h"
#import "FlyNesDisplayLinkPacer.h"
#import "FlyNesAudioPlayer.h"
#import "AppLocalization.h"
#import "CoverCapturePolicy.hpp"
#import "FlyNesCoverStore.h"
#import "GameCoverPolicy.hpp"
#import <AVFoundation/AVFoundation.h>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <cmath>
#include <memory>
#include <string>

#include "flynes/product/pause_actions.hpp"
#include "PlaybackClock.hpp"
#include "NearbyPlaybackState.hpp"
#include "FrameInputLatch.hpp"

namespace {

NSString *pause_command_id(flynes::product::PauseCommand command)
{
    using flynes::product::PauseCommand;
    switch (command)
    {
    case PauseCommand::Resume:
        return @"resume";
    case PauseCommand::GameCenter:
        return @"game_center";
    case PauseCommand::Settings:
        return @"settings";
    }
    return @"resume";
}

NSString *pause_command_title(flynes::product::PauseCommand command)
{
    using flynes::product::PauseCommand;
    switch (command)
    {
    case PauseCommand::Resume:
        return FlyNesLocalizedString(@"pause.resume");
    case PauseCommand::GameCenter:
        return FlyNesLocalizedString(@"pause.game_center");
    case PauseCommand::Settings:
        return FlyNesLocalizedString(@"pause.settings");
    }
    return FlyNesLocalizedString(@"pause.resume");
}

} // namespace

@implementation RunSurfaceViewController {
    UIView *metalHost_;
    GamepadOverlayView *overlay_;
    UIButton *pauseButton_;
    UIView *pauseLayer_;
    UIStackView *pauseStack_;
    UILabel *pauseTitle_;
    FlyNesRuntimeBridge *runtime_;
    FlyNesMetalRenderer *renderer_;
    FlyNesDisplayLinkPacer *pacer_;
    FlyNesAudioPlayer *audio_;
    CAMetalLayer *metalLayer_;
    flynes::ios::PlaybackClock clock_;
    flynes::ios::CoverCaptureSession coverSession_;
    uint32_t buttons_;
    flynes::ios::FrameInputLatch input_;
    BOOL visible_;
    BOOL foreground_;
    BOOL running_;
    BOOL audioInterrupted_;
    BOOL paused_;
    BOOL drawerOpen_;
    BOOL checkpointFailed_;
    BOOL romReady_;
    BOOL videoFailureShown_;
    BOOL backgroundPauseOwned_;
    NSTimer *nearbyStateTimer_;
    uint64_t nearbyPlaybackGeneration_;
    BOOL leavingNearbySession_;
    NSString *productSessionID_;
    NSUInteger productRomLoadCount_;
}

@synthesize gameTitle = _gameTitle;

- (void)setGameTitle:(NSString *)gameTitle
{
    _gameTitle = [gameTitle copy];
    pauseTitle_.text = _gameTitle;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    productSessionID_ = NSUUID.UUID.UUIDString;
    nearbyPlaybackGeneration_ = FlyNesNearbyBridge.sharedInstance.playbackGeneration;
    self.view.backgroundColor = UIColor.blackColor;
    self.view.multipleTouchEnabled = YES;
    paused_ = NO;
    drawerOpen_ = NO;
    checkpointFailed_ = NO;
    romReady_ = NO;
    foreground_ = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;

    metalHost_ = [[UIView alloc] initWithFrame:self.view.bounds];
    metalHost_.translatesAutoresizingMaskIntoConstraints = NO;
    metalHost_.backgroundColor = UIColor.blackColor;
    CAMetalLayer *layer = [CAMetalLayer layer];
    metalLayer_ = layer;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    metalHost_.layer.sublayers = @[ layer ];
    [self.view addSubview:metalHost_];
    renderer_ = [[FlyNesMetalRenderer alloc] initWithLayer:layer];
    audio_ = [[FlyNesAudioPlayer alloc] init];
    pacer_ = [[FlyNesDisplayLinkPacer alloc] init];

    overlay_ = [[GamepadOverlayView alloc] initWithFrame:self.view.bounds];
    overlay_.translatesAutoresizingMaskIntoConstraints = NO;
    __weak __typeof__(self) weakSelf = self;
    pacer_.onTick = ^(CFTimeInterval timestamp, CFTimeInterval presentedTime) {
        (void)presentedTime;
        [weakSelf displayTick:timestamp];
    };
    overlay_.buttonsChanged = ^(uint32_t buttons) {
      RunSurfaceViewController *strong = weakSelf;
      if (strong == nil)
          return;
      [strong applyOverlayButtons:buttons];
    };
    overlay_.buttonsReleased = ^(uint32_t buttons, NSTimeInterval downTime, NSTimeInterval upTime) {
        RunSurfaceViewController *strong = weakSelf;
        if (strong && strong->running_ && !strong.nearbySession)
            strong->input_.release(buttons,downTime,upTime);
    };
    overlay_.buttonsCancelled = ^{ RunSurfaceViewController *strong = weakSelf;
        if (strong) strong->input_.clear(); };
    [self.view addSubview:overlay_];

    pauseButton_ = [UIButton buttonWithType:UIButtonTypeSystem];
    pauseButton_.translatesAutoresizingMaskIntoConstraints = NO;
    [pauseButton_ setTitle:@"II" forState:UIControlStateNormal];
    [pauseButton_ setTitleColor:[UIColor colorWithRed:0.95 green:0.94 blue:0.90 alpha:1.0]
                       forState:UIControlStateNormal];
    pauseButton_.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.72];
    pauseButton_.layer.cornerRadius = 24.0;
    pauseButton_.layer.borderWidth = 2.0;
    pauseButton_.layer.borderColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.37 alpha:1.0].CGColor;
    pauseButton_.accessibilityIdentifier = @"OPEN_PAUSE";
    pauseButton_.accessibilityLabel = FlyNesLocalizedString(@"run.pause");
    [pauseButton_ addTarget:self action:@selector(openPauseDrawer) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pauseButton_];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [metalHost_.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [metalHost_.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [metalHost_.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [metalHost_.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [overlay_.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay_.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay_.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay_.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [pauseButton_.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [pauseButton_.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [pauseButton_.widthAnchor constraintEqualToConstant:48.0],
        [pauseButton_.heightAnchor constraintEqualToConstant:48.0],
    ]];

    if (self.nearbySession) {
        NSDictionary *session = FlyNesNearbyBridge.sharedInstance.snapshot;
        romReady_ = [session[@"state"] unsignedIntValue] == 6;
        NSLog(@"FlyNesNearbyUI event=load state=%@ ready=%d generation=%llu", session[@"state"], romReady_, nearbyPlaybackGeneration_);
    } else {
        runtime_ = [[FlyNesRuntimeBridge alloc] init];
        [runtime_ createRuntime:nil];
        NSData *rom = self.romData;
        if (rom.length == 0)
            rom = [self bundledRomForCanonicalId:self.canonicalId];
        self.romData = rom;
        NSError *romError = nil;
        if (rom.length > 0) {
            productRomLoadCount_ += 1;
            romReady_ = [runtime_ loadRom:rom error:&romError];
        }
        if (romReady_) {
            [FlyNesAppBridge.sharedInstance markPlayedCanonicalID:self.canonicalId error:nil];
            [self restoreAutosave];
        } else
            [self surfaceRomOpenFailure];
    }
    [self reloadProductSettings];
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(nearbyGameResumed:)
                          name:@"flynes.nearby.resumed" object:nil];
    [notifications addObserver:self selector:@selector(applicationWillResignActive:)
                          name:UIApplicationWillResignActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(applicationDidBecomeActive:)
                          name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(audioInterruption:)
                          name:AVAudioSessionInterruptionNotification object:nil];
    [notifications addObserver:self selector:@selector(audioRouteChanged:)
                          name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)dealloc
{
    [nearbyStateTimer_ invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [pacer_ invalidate];
    [audio_ pause];
    [runtime_ destroyRuntime];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    visible_ = YES;
    [self drawFrame];
    foreground_ = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (self.nearbySession) NSLog(@"FlyNesNearbyUI event=appear ready=%d foreground=%d paused=%d drawer=%d", romReady_, foreground_, paused_, drawerOpen_);
    if (self.nearbySession) {
        [nearbyStateTimer_ invalidate];
        __weak RunSurfaceViewController *weakSelf = self;
        nearbyStateTimer_ = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *) {
            [weakSelf reconcileNearbySession];
        }];
        [NSRunLoop.mainRunLoop addTimer:nearbyStateTimer_ forMode:NSRunLoopCommonModes];
        [self reconcileNearbySession];
    }
    [self releaseBackgroundPauseIfReady];
    [self updatePlayback];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    visible_ = NO;
    if (self.nearbySession) NSLog(@"FlyNesNearbyUI event=disappear generation=%llu current=%llu", nearbyPlaybackGeneration_, FlyNesNearbyBridge.sharedInstance.playbackGeneration);
    [nearbyStateTimer_ invalidate];
    nearbyStateTimer_ = nil;
    if (self.nearbySession && !leavingNearbySession_ &&
        nearbyPlaybackGeneration_ == FlyNesNearbyBridge.sharedInstance.playbackGeneration &&
        [FlyNesNearbyBridge.sharedInstance.snapshot[@"state"] intValue] == 6)
        [FlyNesNearbyBridge.sharedInstance setPaused:YES];
    [self stopPlayback];
    [self saveAutosaveIfEnabled];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadProductSettings];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    const UIEdgeInsets insets = self.view.safeAreaInsets;
    overlay_.layoutMargins = insets;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    metalLayer_.frame = metalHost_.bounds;
    CGFloat scale = self.view.window.screen.scale > 0 ? self.view.window.screen.scale : UIScreen.mainScreen.scale;
    metalLayer_.contentsScale = scale;
    metalLayer_.drawableSize = CGSizeMake(metalHost_.bounds.size.width * scale, metalHost_.bounds.size.height * scale);
    [CATransaction commit];
    [self drawFrame];
}

- (void)reloadProductSettings
{
    NSAssert(NSThread.isMainThread, @"Playback settings are main-thread owned");
    [self refreshLocalizedPauseContent];
    NSDictionary<NSString *, id> *snapshot = FlyNesAppBridge.sharedInstance.settingsGet;
    NSNumber *direction = snapshot[@"direction_mode"];
    NSNumber *haptic = snapshot[@"haptic_level"];
    NSNumber *dead = snapshot[@"dead_zone"];
    if (direction != nil)
        overlay_.joystickMode = static_cast<FlyNesJoystickMode>(direction.unsignedIntValue);
    if (haptic != nil)
        overlay_.hapticLevel = haptic.unsignedIntValue;
    overlay_.distinctAbHaptics = [snapshot[@"distinct_ab_haptics"] boolValue];
    if (dead != nil)
        overlay_.deadZone = dead.floatValue;
    NSNumber *opacity = snapshot[@"control_opacity"];
    if (opacity) overlay_.controlOpacity = opacity.floatValue;
    overlay_.layoutUtf8 = FlyNesAppBridge.sharedInstance.controlLayoutGet;
    const NSUInteger preset = [snapshot[@"video_quality_preset"] unsignedIntegerValue];
    FlyNesSpatialMode spatial = preset == 1 ? FlyNesSpatialNearest : FlyNesSpatialSharpBilinear;
    FlyNesPostEffect post = FlyNesPostNone;
    if (preset == 4) {
        spatial = static_cast<FlyNesSpatialMode>([snapshot[@"custom_spatial_mode"] integerValue]);
        post = static_cast<FlyNesPostEffect>([snapshot[@"custom_post_effect"] integerValue]);
    }
    [renderer_ setSpatialMode:spatial postEffect:post];
    [renderer_ setAspectMode:static_cast<FlyNesAspectMode>([snapshot[@"aspect_mode"] integerValue])];
    audio_.enabled = snapshot[@"audio_enabled"] == nil || [snapshot[@"audio_enabled"] boolValue];
    audio_.focusPolicy = snapshot[@"audio_focus_policy"] ? [snapshot[@"audio_focus_policy"] unsignedIntegerValue] : 1;
    [self updatePlayback];
}

- (void)refreshLocalizedPauseContent
{
    pauseButton_.accessibilityLabel = FlyNesLocalizedString(@"run.pause");
    NSDictionary<NSString *, NSString *> *fields = self.gameTitleFields;
    if (fields == nil) {
        FlyNesBuiltinGame *game = [FlyNesBuiltinGames.shared byCanonicalId:self.canonicalId];
        if (game != nil) fields = @{@"titleEn":game.titleEn, @"titleZhHans":game.titleZhHans};
    }
    if ([fields[@"titleEn"] length] || [fields[@"titleZhHans"] length]) {
        NSString *tag = [NSUserDefaults.standardUserDefaults stringForKey:@"FlyNesLocaleTag"] ?: @"system";
        NSArray<NSString *> *preferences = [tag isEqualToString:@"system"] ? NSLocale.preferredLanguages : @[tag];
        NSString *locale = [NSBundle preferredLocalizationsFromArray:@[@"en", @"zh-Hans"]
                                                     forPreferences:preferences].firstObject ?: @"en";
        self.gameTitle = [FlyNesCatalogPresentation titleForFields:fields locale:locale][@"primary"];
    }
    // Settings keeps this drawer and its paused runtime alive. Update its existing views.
    for (UIView *view in pauseStack_.arrangedSubviews) {
        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            const auto command = static_cast<flynes::product::PauseCommand>(button.tag);
            [button setTitle:(self.nearbySession && command == flynes::product::PauseCommand::GameCenter
                ? FlyNesLocalizedString(@"nearby.action.returnToRoom") : pause_command_title(command))
                forState:UIControlStateNormal];
        } else if ([view.accessibilityIdentifier isEqualToString:@"pause_checkpoint_failed"]) {
            ((UILabel *)view).text = FlyNesLocalizedString(@"pause.checkpoint_failed");
        }
    }
}

/** Bytes of a bundled game's ROM, resolved from the shared manifest. */
- (nullable NSData *)bundledRomForCanonicalId:(nullable NSString *)canonicalId
{
    FlyNesBuiltinGame *game = [FlyNesBuiltinGames.shared byCanonicalId:canonicalId];
    if (game == nil)
        return nil;
    NSString *resource = [FlyNesBuiltinGames resourceNameForAssetFilename:game.assetFilename];
    NSString *path = [NSBundle.mainBundle pathForResource:resource ofType:@"nes"];
    if (path == nil)
        return nil;
    return [NSData dataWithContentsOfFile:path];
}

- (NSURL *)autosaveURL
{
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *documents =
        [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return FlyNesLegacyAutosaveURL(documents, self.canonicalId);
}

- (BOOL)persistAutosave:(NSData *)blob
{
    if (blob.length == 0)
        return NO;
    NSURL *url = [self autosaveURL];
    if (url == nil)
        return NO;
    NSError *error = nil;
    NSURL *directory = url.URLByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error])
        return NO;
    return [blob writeToURL:url options:NSDataWritingAtomic error:&error];
}

- (void)restoreAutosave
{
    if (!romReady_)
        return;
    NSDictionary<NSString *, id> *snapshot = FlyNesAppBridge.sharedInstance.settingsGet;
    NSNumber *enabled = snapshot[@"autosave_enabled"];
    if (enabled != nil && enabled.unsignedIntValue == 0)
        return;
    NSURL *url = [self autosaveURL];
    if (url == nil)
        return;
    NSData *blob = [NSData dataWithContentsOfURL:url];
    if (blob.length == 0)
        return;
    checkpointFailed_ = ![self restoreCheckpoint:blob error:nil];
}

- (void)surfaceRomOpenFailure
{
    NSString *message = FlyNesLocalizedString(@"library.rom_open_failed");
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    alert.view.accessibilityIdentifier = @"library_rom_open_failed";
    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:FlyNesLocalizedString(@"pause.game_center")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                              (void)action;
                                              RunSurfaceViewController *strong = weakSelf;
                                              if (strong == nil || strong.onPauseCommand == nil)
                                                  return;
                                              strong.onPauseCommand(@"game_center");
                                            }]];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)applyOverlayButtons:(uint32_t)buttons
{
    if (self.nearbySession) {
        FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
        if (!running_ || ![self isPlaybackAllowed] ||
            nearbyPlaybackGeneration_ != bridge.playbackGeneration) {
            buttons_ = 0;
            input_.clear();
            return;
        }
        buttons_ = buttons;
        // UIKit can deliver a complete press/release between display ticks.
        // The existing session FIFO owns those states; never wait for rendering
        // to sample them. A rejected latest held state is retried by displayTick.
        if (![bridge stepWithButtons:buttons_]) {
            // The owner atomically rejects peer pause/end. Inspect only failure;
            // successful UIKit edges must not pay for a snapshot projection.
            NSDictionary *snapshot = bridge.snapshot;
            if (flynes::ios::nearbyPlaybackAction([snapshot[@"state"] unsignedIntValue],
                    [snapshot[@"paused"] boolValue]) != flynes::ios::NearbyPlaybackAction::Submit) {
                buttons_ = 0;
                input_.clear();
            }
        }
        return;
    }
    buttons_ = running_ ? buttons : 0;
    input_.update(buttons_);
}

- (void)openPauseDrawer
{
    if (drawerOpen_)
        return;
    paused_ = YES;
    drawerOpen_ = YES;
    if (self.nearbySession) [FlyNesNearbyBridge.sharedInstance setPaused:YES];
    [self stopPlayback];
    overlay_.hidden = YES;
    pauseButton_.hidden = YES;
    [self saveAutosaveIfEnabled];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-flynes.test.product_diagnostics"])
        [NSNotificationCenter.defaultCenter postNotificationName:@"flynes.product.playbackDiagnostics" object:self];

    pauseLayer_ = [[UIView alloc] initWithFrame:self.view.bounds];
    pauseLayer_.translatesAutoresizingMaskIntoConstraints = NO;
    pauseLayer_.backgroundColor = UIColor.clearColor;

    UIView *scrim = [[UIView alloc] init];
    scrim.translatesAutoresizingMaskIntoConstraints = NO;
    scrim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.54];
    UITapGestureRecognizer *scrimTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resumeFromPause)];
    [scrim addGestureRecognizer:scrimTap];

    UIView *drawer = [[UIView alloc] init];
    drawer.translatesAutoresizingMaskIntoConstraints = NO;
    drawer.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:1.0];
    [pauseLayer_ addSubview:scrim];
    [pauseLayer_ addSubview:drawer];

    UIStackView *stack = [[UIStackView alloc] init];
    pauseStack_ = stack;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [drawer addSubview:stack];

    if (self.gameTitle.length > 0) {
        UILabel *title = [[UILabel alloc] init];
        pauseTitle_ = title;
        title.text = self.gameTitle;
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
        title.numberOfLines = 2;
        title.accessibilityIdentifier = @"pause_game_title";
        [stack addArrangedSubview:title];
    }

    if (checkpointFailed_)
    {
        UILabel *failure = [[UILabel alloc] init];
        failure.translatesAutoresizingMaskIntoConstraints = NO;
        failure.text = FlyNesLocalizedString(@"pause.checkpoint_failed");
        failure.accessibilityIdentifier = @"pause_checkpoint_failed";
        failure.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        failure.textColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.37 alpha:1.0];
        failure.numberOfLines = 0;
        [stack addArrangedSubview:failure];
    }

    for (const flynes::product::PauseCommand command : flynes::product::kPauseDrawerCommands)
    {
        if (self.nearbySession && command == flynes::product::PauseCommand::Settings) continue;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *commandId = pause_command_id(command);
        [button setTitle:(self.nearbySession && command == flynes::product::PauseCommand::GameCenter
            ? FlyNesLocalizedString(@"nearby.action.returnToRoom") : pause_command_title(command))
            forState:UIControlStateNormal];
        button.accessibilityIdentifier = commandId;
        button.tag = static_cast<NSInteger>(command);
        button.backgroundColor = command == flynes::product::PauseCommand::Resume
                                     ? [UIColor colorWithRed:1.0 green:0.42 blue:0.37 alpha:1.0]
                                     : [UIColor colorWithWhite:0.16 alpha:1.0];
        UIColor *titleColor = command == flynes::product::PauseCommand::Resume
                                  ? [UIColor colorWithWhite:0.07 alpha:1.0]
                                  : [UIColor colorWithWhite:0.96 alpha:1.0];
        [button setTitleColor:titleColor forState:UIControlStateNormal];
        button.layer.cornerRadius = 14.0;
        [button.heightAnchor constraintEqualToConstant:command == flynes::product::PauseCommand::Resume
                                                           ? 52.0
                                                           : 48.0]
            .active = YES;
        [button addTarget:self action:@selector(handlePauseButton:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }

    [self.view addSubview:pauseLayer_];
    [NSLayoutConstraint activateConstraints:@[
        [pauseLayer_.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [pauseLayer_.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [pauseLayer_.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [pauseLayer_.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrim.leadingAnchor constraintEqualToAnchor:pauseLayer_.leadingAnchor],
        [scrim.trailingAnchor constraintEqualToAnchor:drawer.leadingAnchor],
        [scrim.topAnchor constraintEqualToAnchor:pauseLayer_.topAnchor],
        [scrim.bottomAnchor constraintEqualToAnchor:pauseLayer_.bottomAnchor],
        [drawer.trailingAnchor constraintEqualToAnchor:pauseLayer_.trailingAnchor],
        [drawer.topAnchor constraintEqualToAnchor:pauseLayer_.topAnchor],
        [drawer.bottomAnchor constraintEqualToAnchor:pauseLayer_.bottomAnchor],
        [drawer.widthAnchor constraintEqualToConstant:320.0],
        [stack.leadingAnchor constraintEqualToAnchor:drawer.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:drawer.trailingAnchor constant:-24.0],
        [stack.centerYAnchor constraintEqualToAnchor:drawer.centerYAnchor],
    ]];
}

- (void)handlePauseButton:(UIButton *)sender
{
    const auto command = static_cast<flynes::product::PauseCommand>(sender.tag);
    NSString *commandId = pause_command_id(command);
    if (command == flynes::product::PauseCommand::Resume)
    {
        [self resumeFromPause];
        return;
    }
    if (command == flynes::product::PauseCommand::Settings)
    {
        if (self.onPauseCommand != nil)
            self.onPauseCommand(commandId);
        return;
    }
    // The explicit Room command owns its pause. A later disappearance must not
    // send another Pause after the peer has already pressed Continue.
    if (self.nearbySession) leavingNearbySession_ = YES;
    [self dismissPauseLayerKeepingPaused:YES];
    if (self.onPauseCommand != nil)
        self.onPauseCommand(commandId);
}

- (void)resumeFromPause
{
    audioInterrupted_ = NO;
    paused_ = NO;
    checkpointFailed_ = NO;
    if (self.nearbySession) {
        [FlyNesNearbyBridge.sharedInstance resumeGame];
        backgroundPauseOwned_ = NO;
    }
    [self dismissPauseLayerKeepingPaused:NO];
    [self reloadProductSettings];
    [self updatePlayback];
}

- (void)dismissPauseLayerKeepingPaused:(BOOL)keepPaused
{
    paused_ = keepPaused;
    [pauseLayer_ removeFromSuperview];
    pauseLayer_ = nil;
    pauseStack_ = nil;
    pauseTitle_ = nil;
    drawerOpen_ = NO;
    overlay_.hidden = NO;
    pauseButton_.hidden = NO;
}

- (void)nearbyGameResumed:(NSNotification *)notification
{
    [self reconcileNearbySession];
}

- (void)reconcileNearbySession
{
    if (!self.nearbySession || !visible_ || leavingNearbySession_) return;
    FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
    NSDictionary *snapshot = bridge.snapshot;
    if (nearbyPlaybackGeneration_ != bridge.playbackGeneration || [snapshot[@"state"] intValue] != 6) {
        leavingNearbySession_ = YES;
        paused_ = YES;
        [self stopPlayback];
        if (self.onPauseCommand) self.onPauseCommand(@"nearby_session_changed");
        return;
    }
    // A paused display link cannot detect peer Continue, and a background
    // notification may have been missed. Reconcile the authoritative snapshot.
    if (foreground_ && drawerOpen_ && ![snapshot[@"paused"] boolValue]) {
        [self dismissPauseLayerKeepingPaused:NO];
        backgroundPauseOwned_ = NO;
        [self updatePlayback];
    }
}

- (void)displayTick:(CFTimeInterval)timestamp
{
    NSAssert(NSThread.isMainThread, @"Playback is owned by the main run loop");
    if (!running_ || ![self isPlaybackAllowed] || !clock_.beginTick(timestamp)) return;
    if (self.nearbySession) {
        BOOL produced = NO;
        FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
        if (nearbyPlaybackGeneration_ != bridge.playbackGeneration) {
            [self stopPlayback];
            return;
        }
        auto playbackAction = [&] {
            NSDictionary *snapshot = bridge.snapshot;
            return flynes::ios::nearbyPlaybackAction(
                [snapshot[@"state"] unsignedIntValue], [snapshot[@"paused"] boolValue]);
        };
        auto leaveEndedSession = [&] {
            paused_ = YES;
            [self stopPlayback];
            if (self.onPauseCommand) self.onPauseCommand(@"game_center");
        };
        while (clock_.frameDue()) {
            const auto action = playbackAction();
            if (action == flynes::ios::NearbyPlaybackAction::Exit) {
                leaveEndedSession();
                return;
            }
            if (action == flynes::ios::NearbyPlaybackAction::Hold) {
                [overlay_ releaseAllButtons];
                buttons_ = 0;
                input_.clear();
                clock_.reset();
                [self drawFrame];
                return;
            }
            // Refresh only the actual held state. The offline minimum-tap latch
            // must not reinsert a face press after its release entered the FIFO.
            if (![bridge stepWithButtons:buttons_]) {
                if (playbackAction() == flynes::ios::NearbyPlaybackAction::Exit)
                    leaveEndedSession();
                else {
                    clock_.reset();
                    [self drawFrame];
                }
                return;
            }
            clock_.didProduceDuration(bridge.sourceFrameDuration);
            NSData *pcm = [bridge pullPCM];
            if (!audioInterrupted_) [audio_ enqueuePCM:pcm];
            produced = YES;
        }
        if (produced) {
            [self captureCoverFrame];
            NSData *pixels = [FlyNesNearbyBridge.sharedInstance copyLatestRgb565Frame];
            if (pixels.length) [renderer_ uploadRgb565:pixels width:256 height:240];
        }
        [self drawFrame];
        return;
    }
    BOOL produced = NO;
    while (clock_.frameDue()) {
        NSError *error = nil;
        if (![runtime_ stepFrameWithButtons:input_.sample(NSProcessInfo.processInfo.systemUptime) error:&error]) {
            paused_ = YES;
            [self stopPlayback];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:FlyNesLocalizedString(@"run.emulation_paused")
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            __weak __typeof__(self) weakSelf = self;
            [alert addAction:[UIAlertAction actionWithTitle:FlyNesLocalizedString(@"pause.game_center")
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    (void)action;
                    RunSurfaceViewController *strong = weakSelf;
                    if (strong.onPauseCommand) strong.onPauseCommand(@"game_center");
                }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        clock_.didProduceSamples(runtime_.lastFrameSampleCount, 48000);
        // Always drain the runtime PCM FIFO, including when sound is disabled.
        NSData *pcm = [runtime_ pullPCM];
        if (!audioInterrupted_) [audio_ enqueuePCM:pcm];
        // Sample the produced native frame, including steps display presentation skips.
        [self captureCoverFrame];
        produced = YES;
    }
    if (produced) {
        NSData *pixels = [runtime_ copyLatestRgb565Frame];
        if (pixels.length) [renderer_ uploadRgb565:pixels width:256 height:240];
    }
    [self drawFrame];
}

/// Android `CoverCaptureCoordinator`: sample the game-only native frame at
/// 2/4/6/8 seconds, score it off the main thread, and persist the best improvement.
/// The UI, control overlay, CRT output, and pause drawer are never sampled.
- (void)captureCoverFrame
{
    if (self.canonicalId.length == 0) return;
    uint64_t sequence = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    NSData *pixels = nil;
    if (self.nearbySession) {
        // Nearby owns a separate runtime; use its authoritative frame and local
        // catalog ID so the room and game center read the same saved cover.
        pixels = [FlyNesNearbyBridge.sharedInstance copyLatestRgb565FrameWithFrameIndex:&sequence];
        width = 256;
        height = 240;
    } else {
        pixels = [runtime_ copyLatestRgb565FrameWithSequence:&sequence width:&width height:&height];
    }
    if (pixels.length == 0 || width == 0 || height == 0) return;
    if (!coverSession_.note_frame(sequence)) return;
    const std::string canonical(self.canonicalId.UTF8String ?: "");
    FlyNesCoverStore *store = FlyNesCoverStore.sharedInstance;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const double score = flynes::ios::game_cover_score(
            static_cast<const uint8_t *>(pixels.bytes), pixels.length, width, height);
        if (!coverSession_.consider(score)) return;
        [store storeRgb565Frame:pixels canonicalId:@(canonical.c_str()) width:width height:height];
    });
}

- (void)drawFrame
{
    [renderer_ draw];
    if (!renderer_.permanentFailure || videoFailureShown_) return;
    paused_ = YES;
    [self stopPlayback];
    if (!visible_ || self.presentedViewController) return;
    videoFailureShown_ = YES;
    [self saveAutosaveIfEnabled];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:FlyNesLocalizedString(@"run.video_unavailable")
        message:FlyNesLocalizedString(@"run.video_unavailable.detail") preferredStyle:UIAlertControllerStyleAlert];
    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:FlyNesLocalizedString(@"pause.game_center")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            RunSurfaceViewController *strong = weakSelf;
            if (strong.onPauseCommand) strong.onPauseCommand(@"game_center");
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)isPlaybackAllowed
{
    return visible_ && foreground_ && romReady_ && !paused_ && !drawerOpen_
        && !(audioInterrupted_ && audio_.focusPolicy == 1);
}

- (void)updatePlayback
{
    if (![self isPlaybackAllowed]) { [self stopPlayback]; return; }
    if (!running_) {
        [overlay_ releaseAllButtons];
        buttons_ = 0; input_.clear();
        clock_.reset();
        running_ = YES;
        [pacer_ attachToView:metalHost_];
    }
    if (!audioInterrupted_ && audio_.enabled) {
        NSError *error = nil;
        if (![audio_ start:&error]) NSLog(@"FlyNES audio unavailable: %@", error.localizedDescription);
    } else {
        [audio_ pause];
    }
}

- (void)stopPlayback
{
    running_ = NO;
    [pacer_ invalidate];
    clock_.reset();
    buttons_ = 0; input_.clear();
    [overlay_ releaseAllButtons];
    if (!self.nearbySession) {
        [runtime_ clearInput];
        [runtime_ discardAudio];
    }
    [audio_ pause];
}

- (void)saveAutosaveIfEnabled
{
    if (self.nearbySession) return;
    if (!romReady_) return;
    NSNumber *enabled = FlyNesAppBridge.sharedInstance.settingsGet[@"autosave_enabled"];
    if (enabled != nil && !enabled.boolValue) { checkpointFailed_ = NO; return; }
    NSData *blob = [runtime_ saveCheckpoint:nil];
    checkpointFailed_ = blob == nil || ![self persistAutosave:blob];
}

- (BOOL)restoreCheckpoint:(NSData *)checkpoint error:(NSError **)error
{
    if (self.nearbySession) return NO;
    NSAssert(NSThread.isMainThread, @"Playback checkpoints are main-thread owned");
    [self stopPlayback];
    const BOOL restored = [runtime_ loadCheckpoint:checkpoint error:error];
    if (restored) {
        NSData *pixels = [runtime_ copyLatestRgb565Frame];
        if (pixels.length) [renderer_ uploadRgb565:pixels width:256 height:240];
        [self drawFrame];
    }
    [self updatePlayback];
    return restored;
}

- (BOOL)resetGame:(NSError **)error
{
    if (self.nearbySession) return NO;
    NSAssert(NSThread.isMainThread, @"Playback reset is main-thread owned");
    [self stopPlayback];
    if (self.romData.length > 0) productRomLoadCount_ += 1;
    romReady_ = self.romData.length > 0 && [runtime_ loadRom:self.romData error:error];
    // Android restarts the cover best-score gate per play session.
    coverSession_ = flynes::ios::CoverCaptureSession{};
    [self updatePlayback];
    return romReady_;
}

- (NSDictionary<NSString *, id> *)productDiagnostics
{
    uint64_t sequence = 0;
    if (runtime_) [runtime_ copyLatestRgb565FrameWithSequence:&sequence width:nullptr height:nullptr];
    return @{@"gameSessionId": productSessionID_ ?: @"", @"romLoadCount": @(productRomLoadCount_),
             @"frameSequence": @(sequence), @"paused": @(paused_ || drawerOpen_),
             @"running": @(running_)};
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    (void)notification;
    foreground_ = NO;
    if (self.nearbySession && visible_ && !paused_ && !drawerOpen_) {
        FlyNesNearbyBridge *bridge = FlyNesNearbyBridge.sharedInstance;
        NSDictionary *snapshot = bridge.snapshot;
        if ([snapshot[@"state"] unsignedIntValue] == 6 && ![snapshot[@"paused"] boolValue])
            backgroundPauseOwned_ = [bridge setPaused:YES];
    }
    [self stopPlayback];
    [self saveAutosaveIfEnabled];
}

- (void)releaseBackgroundPauseIfReady
{
    if (!backgroundPauseOwned_ || !self.nearbySession || !foreground_ || !visible_ ||
        paused_ || drawerOpen_) return;
    if ([FlyNesNearbyBridge.sharedInstance setPaused:NO]) backgroundPauseOwned_ = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    foreground_ = YES;
    [self reconcileNearbySession];
    [self releaseBackgroundPauseIfReady];
    [self reloadProductSettings];
}

- (void)audioInterruption:(NSNotification *)notification
{
    // AVAudioSession notifications can arrive off the UI thread.
    NSDictionary *info = notification.userInfo;
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        RunSurfaceViewController *strong = weakSelf;
        if (!strong) return;
        const BOOL began = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
        if (began) {
            strong->audioInterrupted_ = YES;
            [strong->audio_ pause];
            [strong->overlay_ releaseAllButtons];
            strong->buttons_ = 0; strong->input_.clear();
            [strong->runtime_ clearInput];
            [strong updatePlayback];
        } else {
            const BOOL resume = ([info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue]
                                  & AVAudioSessionInterruptionOptionShouldResume) != 0;
            strong->audioInterrupted_ = NO;
            if (!resume) [strong openPauseDrawer];
            else [strong updatePlayback];
        }
    });
}

- (void)audioRouteChanged:(NSNotification *)notification
{
    const NSUInteger reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        RunSurfaceViewController *strong = weakSelf;
        if (!strong) return;
        if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable && strong->running_) {
            [strong openPauseDrawer]; // Headphones unplugged: do not unexpectedly use the speaker.
        } else if (strong->running_) {
            [strong->audio_ flush];
        }
    });
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

@end

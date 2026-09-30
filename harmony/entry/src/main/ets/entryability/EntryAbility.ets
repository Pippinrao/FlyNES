import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resolveTestFontSizeScale } from '../ui/NearbyTestFontScale';
import { ExclusiveAppComponent, FlutterManager } from '@ohos/flutter_ohos';
import { isFlutterFoundationRoute } from '../flutter/FoundationProjection';
import { ProductStartupObservation } from '../service/ProductStartupObservation';
import nativeApp from 'libentry.so';

export default class EntryAbility extends UIAbility implements ExclusiveAppComponent<UIAbility> {
  private testPage: string = 'pages/FlutterFoundation';
  private stage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    FlutterManager.getInstance().pushUIAbility(this);
    this.applyDebugWant(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (this.applyDebugWant(want) && this.stage !== undefined) {
      this.stage.loadContent(this.testPage);
    }
  }

  private applyDebugWant(want: Want): boolean {
    const debug = this.context.applicationInfo.debug;
    const rawScale: string | undefined = want.parameters?.['flynes.test.fontSizeScale'] as
      string | undefined;
    const parsed = resolveTestFontSizeScale(rawScale, debug);
    if (parsed.accepted) {
      this.context.getApplicationContext().setFontSizeScale(parsed.scale);
      console.info(`FlyNES test fontSizeScale applied=${parsed.scale}`);
    } else if (parsed.rejection.length > 0) {
      console.info(parsed.rejection);
    }
    if (!debug) {
      return false;
    }
    const page: string | undefined = want.parameters?.['flynes.test.page'] as string | undefined;
    if (page !== undefined && page !== 'native_baseline') AppStorage.setOrCreate('ProductNativeBaseline', false);
    if (page === 'native_baseline') {
      AppStorage.setOrCreate('ProductNativeBaseline', true);
      this.testPage = 'pages/GameCenter';
    } else if (page === 'flutter_texture_probe') {
      this.testPage = 'pages/FlutterTextureProbe';
    } else if (isFlutterFoundationRoute(page, debug)) {
      this.testPage = 'pages/FlutterFoundation';
    } else if (page === 'nearby_friends') {
      this.testPage = 'pages/NearbyFriends';
    } else if (page === 'nearby_pairing') {
      this.testPage = 'pages/NearbyPairing';
    } else if (page === 'nearby_lobby') {
      this.testPage = 'pages/NearbyLobby';
    } else {
      return false;
    }
    return true;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.stage = windowStage;
    FlutterManager.getInstance().pushWindowStage(this, windowStage);
    // Open the one process-owned product instance before either page builds.
    // Flutter engine creation must not delay the native owner-ready event.
    // Page-level initialization remains the retry path when opening fails.
    try {
      nativeApp.appOpen(this.context.filesDir, this.context.cacheDir);
      ProductStartupObservation.ownerReady();
    } catch (error) {
      const detail = error instanceof Error ? error.message : 'appOpen failed';
      console.error(`FlyNES product owner preload failed: ${detail}`);
    }
    console.info(`FlyNES UI configuration fontSizeScale=${this.context.config.fontSizeScale ?? -1}`);
    try {
      const win = windowStage.getMainWindowSync();
      win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarEnable([]);
    } catch (error) {
      const detail = error instanceof Error ? error.message : 'orientation failed';
      console.error(`FlyNES landscape preference failed: ${detail}`);
    }
    // The in-process test module can select a same-package native baseline
    // before any Flutter page/engine exists. This is never read from a Release Want.
    const initialPage = AppStorage.get<boolean>('ProductNativeBaseline') === true ? 'pages/GameCenter' : this.testPage;
    windowStage.loadContent(initialPage, (error) => {
      if (error.code !== 0) {
        console.error(`FlyNES content failed to load: ${error.code}`);
      }
    });
  }

  onForeground(): void { this.context.eventHub.emit('app-foreground'); hilog.info(0, 'FlyNesNearby', 'event=ability_foreground'); }

  onBackground(): void { this.context.eventHub.emit('save-background'); hilog.info(0, 'FlyNesNearby', 'event=ability_background'); }

  onWindowStageDestroy(): void {
    FlutterManager.getInstance().popWindowStage(this);
    this.stage = undefined;
  }

  detachFromFlutterEngine(): void {}
  getAppComponent(): UIAbility { return this; }
  onDestroy(): void { FlutterManager.getInstance().popUIAbility(this); }
}

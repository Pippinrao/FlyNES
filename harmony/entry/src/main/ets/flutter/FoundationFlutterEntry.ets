import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { FlutterEngine, FlutterEntry, FlutterShellArgs, MethodChannel } from '@ohos/flutter_ohos';
import { FoundationChannelHandler } from './FoundationChannelHandler';

export class FoundationFlutterEntry extends FlutterEntry {
  private channel: MethodChannel | undefined = undefined;
  private handler: FoundationChannelHandler | undefined = undefined;
  private surfaceDetached: boolean = false;
  private pageVisible: boolean = true;
  private background: () => void = () => {
    this.handler?.cancel();
    this.suspendSurface();
    this.getFlutterEngine()?.getLifecycleChannel()?.appIsPaused();
  };
  private foreground: () => void = () => {
    if (this.pageVisible) this.resumeSurface();
  };

  private suspendSurface(): void {
    if (this.surfaceDetached) return;
    // Detach on the supported raster synchronization path before paused GPU
    // reclaim can try to make the shared IO context current on another thread.
    this.getFlutterView()?.onSurfaceDestroyed();
    this.surfaceDetached = true;
  }

  private resumeSurface(): void {
    if (!this.surfaceDetached) return;
    this.getFlutterView()?.onSurfaceCreated();
    // NotifyDestroyed disables semantics; this SDK's surface reattach omits
    // restoring it. Keep the experimental page accessible after every return.
    this.getFlutterEngine()?.getFlutterNapi()?.setSemanticsEnabled(true);
    this.surfaceDetached = false;
  }

  getFlutterShellArgs(): FlutterShellArgs {
    const args = super.getFlutterShellArgs();
    // The API20 host's platform-thread stack is too small for this debug
    // framework. The pinned engine supports its own 2 MB Flutter UI thread;
    // MethodChannel still dispatches native calls onto the platform thread.
    args.add('--merged-platform-ui-thread=disabled');
    return args;
  }

  configureFlutterEngine(engine: FlutterEngine): void {
    super.configureFlutterEngine(engine);
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'flynes/foundation');
    this.handler = new FoundationChannelHandler(this.context as common.UIAbilityContext);
    this.channel.setMethodCallHandler(this.handler);
    (this.context as common.UIAbilityContext).eventHub.on('save-background', this.background);
    (this.context as common.UIAbilityContext).eventHub.on('app-foreground', this.foreground);
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.resumeSurface();
    super.onPageShow();
    this.handler?.onPageShow();
  }
  onPageHide(): void {
    this.pageVisible = false;
    this.handler?.onPageHide();
    this.suspendSurface();
    super.onPageHide();
  }

  popSystemNavigator(): boolean {
    void router.replaceUrl({ url: 'pages/GameCenter' });
    return true;
  }

  cleanUpFlutterEngine(engine: FlutterEngine): void {
    (this.context as common.UIAbilityContext).eventHub.off('save-background', this.background);
    (this.context as common.UIAbilityContext).eventHub.off('app-foreground', this.foreground);
    this.surfaceDetached = false;
    this.pageVisible = false;
    this.handler?.dispose();
    this.handler = undefined;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    super.cleanUpFlutterEngine(engine);
  }
}

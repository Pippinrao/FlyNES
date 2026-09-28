import { common } from '@kit.AbilityKit';
import { FlutterEngine, FlutterEntry, FlutterShellArgs, MethodChannel } from '@ohos/flutter_ohos';
import { FoundationTextureHandler } from './FoundationTextureHandler';

export class FoundationTextureEntry extends FlutterEntry {
  private channel: MethodChannel | undefined = undefined;
  private handler: FoundationTextureHandler | undefined = undefined;
  private background: () => void = () => this.handler?.onHostActive(false);
  private foreground: () => void = () => this.handler?.onHostActive(true);

  getDartEntrypointFunctionName(): string { return 'textureProbeMain'; }
  getFlutterShellArgs(): FlutterShellArgs {
    const args = super.getFlutterShellArgs();
    args.add('--merged-platform-ui-thread=disabled');
    return args;
  }
  configureFlutterEngine(engine: FlutterEngine): void {
    super.configureFlutterEngine(engine);
    this.handler = new FoundationTextureHandler(this.context as common.UIAbilityContext, engine);
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'flynes/foundation_texture');
    this.channel.setMethodCallHandler(this.handler);
    const events = (this.context as common.UIAbilityContext).eventHub;
    events.on('save-background', this.background);
    events.on('app-foreground', this.foreground);
  }
  onPageShow(): void { super.onPageShow(); this.foreground(); }
  onPageHide(): void { this.background(); super.onPageHide(); }
  cleanUpFlutterEngine(engine: FlutterEngine): void {
    const events = (this.context as common.UIAbilityContext).eventHub;
    events.off('save-background', this.background);
    events.off('app-foreground', this.foreground);
    this.handler?.dispose(); this.handler = undefined;
    this.channel?.setMethodCallHandler(null); this.channel = undefined;
    super.cleanUpFlutterEngine(engine);
  }
}

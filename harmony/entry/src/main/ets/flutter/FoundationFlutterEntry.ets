import { common } from '@kit.AbilityKit';
import { FlutterEngine, FlutterEntry, MethodChannel } from '@ohos/flutter_ohos';
import { FoundationChannelHandler } from './FoundationChannelHandler';

export class FoundationFlutterEntry extends FlutterEntry {
  private channel: MethodChannel | undefined = undefined;

  configureFlutterEngine(engine: FlutterEngine): void {
    super.configureFlutterEngine(engine);
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'flynes/foundation');
    this.channel.setMethodCallHandler(new FoundationChannelHandler(this.context as common.UIAbilityContext));
  }

  cleanUpFlutterEngine(engine: FlutterEngine): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    super.cleanUpFlutterEngine(engine);
  }
}

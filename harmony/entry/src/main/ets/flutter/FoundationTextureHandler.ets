import { common } from '@kit.AbilityKit';
import { FlutterEngine, MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';
import nativePlay from 'libentry.so';
import { builtinGamesSync } from '../service/PlayService';

/** G1-only media owner. No checkpoint/history service or frame data enters Dart. */
export class FoundationTextureHandler implements MethodCallHandler {
  private context: common.UIAbilityContext;
  private engine: FlutterEngine;
  private owner: string = '';
  private texture: number = -1;
  private opened: boolean = false;
  private disposed: boolean = false;
  private hostActive: boolean = true;
  private pageActive: boolean = true;

  constructor(context: common.UIAbilityContext, engine: FlutterEngine) {
    this.context = context;
    this.engine = engine;
  }

  onHostActive(active: boolean): void {
    this.hostActive = active;
    this.applyActive();
  }

  private applyActive(): void {
    if (!this.opened) return;
    const active = this.hostActive && this.pageActive && this.texture >= 0;
    if (!active) nativePlay.textureProbeInput(0);
    nativePlay.textureProbeActive(active);
  }

  private detach(): void {
    if (this.texture < 0) return;
    nativePlay.textureProbeInput(0);
    nativePlay.textureProbeActive(false);
    // Join EGL presentation before Flutter destroys its borrowed native window.
    nativePlay.textureProbeDetach();
    this.engine.getFlutterRenderer().unregisterTexture(this.texture);
    this.texture = -1;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.detach();
    if (this.opened) nativePlay.textureProbeClose();
    this.opened = false;
    this.owner = '';
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (this.disposed) throw new Error('Texture host closed');
      const owner: Object | null = call.argument('owner');
      if (typeof owner !== 'string' || owner.length === 0) throw new Error('Texture owner required');
      if (call.method === 'attach') {
        if (owner === this.owner && this.texture >= 0) { result.success(this.texture); return; }
        this.detach();
        this.owner = owner;
        this.pageActive = true;
        if (!this.opened) {
          const games = builtinGamesSync(this.context).all();
          if (games.length === 0) throw new Error('Licensed fixture unavailable');
          nativePlay.textureProbeOpen(this.context.resourceManager.getRawFileContentSync(games[0].assetPath()));
          this.opened = true;
        }
        const renderer = this.engine.getFlutterRenderer();
        const id = renderer.getTextureId();
        const entry = renderer.registerTexture(id);
        this.texture = id;
        try {
          renderer.setTextureBufferSize(id, 256, 240);
          nativePlay.textureProbeAttach(entry.getNativeWindowId(), 256, 240);
          this.applyActive();
        } catch (error) { this.detach(); throw new Error(`${error}`); }
        result.success(id);
        return;
      }
      if (owner !== this.owner) { result.success(null); return; }
      if (call.method === 'detach') { this.detach(); result.success(null); return; }
      if (call.method === 'input') {
        const buttons: Object | null = call.argument('buttons');
        if (typeof buttons !== 'number' || !Number.isInteger(buttons) || buttons < 0 || buttons > 255) {
          throw new Error('Invalid input mask');
        }
        if (this.opened) nativePlay.textureProbeInput(this.hostActive && this.pageActive && this.texture >= 0 ? buttons : 0);
        result.success(null); return;
      }
      if (call.method === 'active') {
        const active: Object | null = call.argument('active');
        if (typeof active !== 'boolean') throw new Error('Invalid active flag');
        this.pageActive = active;
        this.applyActive(); result.success(null); return;
      }
      if (call.method === 'stats') { result.success(nativePlay.textureProbeStats()); return; }
      result.notImplemented();
    } catch (error) {
      console.error(`FlyNES texture probe failed: ${error}`);
      result.error('texture_unavailable', `${error}`, null);
    }
  }
}

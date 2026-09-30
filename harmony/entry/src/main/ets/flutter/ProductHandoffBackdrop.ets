import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

/** One short-lived compositor snapshot. It owns no game, engine or connection. */
export class ProductHandoffBackdrop {
  private static frame: image.PixelMap | undefined = undefined;
  private static generation: number = 0;
  static async capture(context: common.UIAbilityContext, current: () => boolean = () => true): Promise<number> {
    const generation = ++ProductHandoffBackdrop.generation;
    const surface = await window.getLastWindow(context);
    if (generation !== ProductHandoffBackdrop.generation || !current()) return 0;
    const next = await surface.snapshot();
    if (generation !== ProductHandoffBackdrop.generation || !current()) {
      void next.release(); return 0;
    }
    const previous = ProductHandoffBackdrop.frame;
    ProductHandoffBackdrop.frame = next;
    if (previous !== undefined) void previous.release();
    return generation;
  }
  static take(generation?: number): image.PixelMap | undefined {
    if (generation !== undefined && generation !== ProductHandoffBackdrop.generation) return undefined;
    const frame = ProductHandoffBackdrop.frame;
    ProductHandoffBackdrop.frame = undefined;
    return frame;
  }
  static clear(generation?: number): void {
    if (generation !== undefined && generation !== ProductHandoffBackdrop.generation) return;
    ProductHandoffBackdrop.generation++;
    const frame = ProductHandoffBackdrop.take();
    if (frame !== undefined) void frame.release();
  }
}

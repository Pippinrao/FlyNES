import { FlutterPage, FlutterView } from '@ohos/flutter_ohos';
import { FoundationFlutterEntry } from '../flutter/FoundationFlutterEntry';
import { ProductRouteContext } from '../flutter/ProductChannelHandler';
import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { ProductHandoffBackdrop } from '../flutter/ProductHandoffBackdrop';
import { common } from '@kit.AbilityKit';

let productHostSerial: number = 0;
let detachActiveProductView: (() => void) | undefined = undefined;

@Entry
@Component
struct FlutterFoundation {
  private flutterEntry: FoundationFlutterEntry | undefined = undefined;
  private flutterView: FlutterView | undefined = undefined;
  @State private viewId: string = '';
  @State private presented: boolean = false;
  @State private backdrop: image.PixelMap | undefined = undefined;
  private outgoingBackdrop: boolean = false;
  private viewEpoch: number = 0;
  private navigationEpoch: number = 0;
  private pageVisible: boolean = false;
  private backgrounded: boolean = false;
  private onHostBackground: () => void = () => {
    this.backgrounded = true;
    this.navigationEpoch++;
    this.releaseBackdrop();
  };
  private onHostForeground: () => void = () => { this.backgrounded = false; };
  private route: ProductRouteContext = new ProductRouteContext();
  private releaseView: () => void = () => { this.detach(); };

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.route.route = params?.['route'] as string ?? 'hall';
    this.route.purpose = params?.['purpose'] as string ?? 'single';
    this.route.returnToken = `oh-product-host-${++productHostSerial}`;
    const context = getContext(this) as common.UIAbilityContext;
    context.eventHub.on('save-background', this.onHostBackground);
    context.eventHub.on('app-foreground', this.onHostForeground);
  }

  private attach(): void {
    if (this.flutterEntry !== undefined) return;
    detachActiveProductView?.();
    detachActiveProductView = this.releaseView;
    const epoch = ++this.viewEpoch;
    this.releaseBackdrop();
    this.presented = false;
    this.backdrop = ProductHandoffBackdrop.take();
    this.flutterEntry = new FoundationFlutterEntry(getContext(this));
    this.flutterEntry.route = this.route;
    this.flutterEntry.beforeNative = () => this.prepareNativeRoute();
    this.flutterEntry.onPresented = () => {
      if (epoch !== this.viewEpoch || this.outgoingBackdrop) return;
      this.presented = true;
      this.releaseBackdrop();
    };
    this.flutterEntry.aboutToAppear();
    this.flutterView = this.flutterEntry.getFlutterView();
    this.viewId = this.flutterView?.getId() ?? '';
  }

  private async prepareNativeRoute(): Promise<void> {
    const epoch = this.viewEpoch;
    const navigation = this.navigationEpoch;
    const current = (): boolean => epoch === this.viewEpoch && navigation === this.navigationEpoch && this.pageVisible && !this.backgrounded && this.presented;
    if (!current()) throw new Error('stale_host');
    const token = await ProductHandoffBackdrop.capture(getContext(this) as common.UIAbilityContext, current);
    if (!current() || token === 0) { ProductHandoffBackdrop.clear(token); throw new Error('stale_host'); }
    const frame = ProductHandoffBackdrop.take(token);
    if (frame === undefined) throw new Error('capture_unavailable');
    this.releaseBackdrop();
    this.backdrop = frame;
    this.outgoingBackdrop = true;
  }
  onPageShow(): void { this.pageVisible = true; this.backgrounded = false; this.attach(); this.flutterEntry?.onPageShow(); }
  onPageHide(): void { this.pageVisible = false; this.detach(this.outgoingBackdrop); }
  private detach(keepBackdrop: boolean = false): void {
    this.viewEpoch++;
    this.flutterEntry?.onPageHide();
    this.viewId = '';
    this.flutterEntry?.aboutToDisappear();
    this.flutterEntry = undefined;
    this.flutterView = undefined;
    this.presented = false;
    // Keep at most one outgoing image through the platform's untouched system
    // transition. No FlutterView is retained. Return, destroy or background frees it.
    if (!keepBackdrop) this.releaseBackdrop();
    if (detachActiveProductView === this.releaseView) detachActiveProductView = undefined;
  }
  private releaseBackdrop(): void {
    const frame = this.backdrop;
    this.backdrop = undefined;
    this.outgoingBackdrop = false;
    if (frame !== undefined) void frame.release();
  }
  onBackPress(): boolean {
    this.flutterEntry?.onBackPress();
    return true;
  }
  aboutToDisappear(): void {
    this.detach();
    const context = getContext(this) as common.UIAbilityContext;
    context.eventHub.off('save-background', this.onHostBackground);
    context.eventHub.off('app-foreground', this.onHostForeground);
  }

  build() {
    Stack() {
      if (this.viewId.length > 0) {
        FlutterPage({ viewId: this.viewId })
          .accessibilityLevel(this.presented ? 'auto' : 'no-hide-descendants')
          .hitTestBehavior(this.presented ? HitTestMode.Default : HitTestMode.None)
      }
      if (!this.presented) {
        Stack() {
          if (this.backdrop !== undefined) {
            Image(this.backdrop).width('100%').height('100%').objectFit(ImageFit.Fill)
          }
        }.width('100%').height('100%').backgroundColor('#121316')
          .hitTestBehavior(HitTestMode.Block).accessibilityLevel('no-hide-descendants')
          .id('product_presentation_gate')
      }
    }.width('100%').height('100%').backgroundColor('#121316').id('flutter_foundation_host')
  }
}

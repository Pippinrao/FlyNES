import { FlutterPage, FlutterView } from '@ohos/flutter_ohos';
import { FoundationFlutterEntry } from '../flutter/FoundationFlutterEntry';

@Entry
@Component
struct FlutterFoundation {
  private flutterEntry: FoundationFlutterEntry | undefined = undefined;
  private flutterView: FlutterView | undefined = undefined;

  aboutToAppear(): void {
    this.flutterEntry = new FoundationFlutterEntry(getContext(this));
    this.flutterEntry.aboutToAppear();
    this.flutterView = this.flutterEntry.getFlutterView();
  }

  onPageShow(): void { this.flutterEntry?.onPageShow(); }
  onPageHide(): void { this.flutterEntry?.onPageHide(); }
  onBackPress(): boolean {
    this.flutterEntry?.onBackPress();
    return true;
  }
  aboutToDisappear(): void {
    this.flutterEntry?.aboutToDisappear();
    this.flutterEntry = undefined;
    this.flutterView = undefined;
  }

  build() {
    Stack() {
      FlutterPage({ viewId: this.flutterView?.getId() ?? '' })
    }.width('100%').height('100%').id('flutter_foundation_host')
  }
}

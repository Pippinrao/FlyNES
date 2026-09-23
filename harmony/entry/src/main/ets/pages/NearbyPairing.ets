import { router } from '@kit.ArkUI';
import { scanBarcode } from '@kit.ScanKit';
import nativeSession from 'libentry.so';
import { NearbyMvpPort, NearbyMvpScanFlow, NearbyMvpSnapshot } from '../service/NearbyMvpScanFlow';
import { NEARBY_TYPE } from '../ui/NearbyTypography';

class NativeMvpPort implements NearbyMvpPort {
  join(qrText: string): boolean { return nativeSession.nearbyMvpJoin(qrText); }
  snapshot(): NearbyMvpSnapshot { return nativeSession.nearbyMvpSnapshot(); }
  cancel(): boolean { return nativeSession.nearbyMvpCancel(); }
}

@Entry
@Component
struct NearbyPairing {
  @State private mode: string = 'create';
  @State private state: number = 0;
  @State private reason: number = 0;
  @State private scanning: boolean = false;
  private timerId: number = -1;
  private lobbyOpened: boolean = false;
  private autoScanLaunched: boolean = false;
  private readonly scanFlow: NearbyMvpScanFlow = new NearbyMvpScanFlow(new NativeMvpPort());

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    this.mode = params && params['mode'] === 'scan' ? 'scan' : 'create';
    if (this.mode !== 'scan') return;
    this.scanFlow.appear();
    this.timerId = setInterval(() => this.poll(), 250);
    if (!this.autoScanLaunched && (params === undefined || params['resume'] !== 'true')) {
      this.autoScanLaunched = true;
      setTimeout(() => { void this.scanQr(); }, 0);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = -1;
    // Page navigation, including the Scan Kit extension, retains the native connection.
    if (this.mode === 'scan') this.scanFlow.hideForScanner();
  }

  private poll(): void {
    this.scanFlow.poll();
    const snapshot = this.scanFlow.snapshot();
    this.state = snapshot.state;
    this.reason = snapshot.reason;
    if (snapshot.state === 3 && !this.lobbyOpened) {
      this.lobbyOpened = true;
      if (this.timerId !== -1) clearInterval(this.timerId);
      this.timerId = -1;
      void router.replaceUrl({ url: 'pages/NearbyLobby' });
    }
  }

  private async scanQr(): Promise<void> {
    const result = this.scanFlow.scan(async (): Promise<string> => {
      try {
        const scanned = await scanBarcode.startScanForResult(getContext(this));
        return scanned.originalValue;
      } catch (error) {
        throw new Error('QR scanner unavailable');
      }
    });
    this.scanning = this.scanFlow.isScanning();
    await result;
    this.scanning = this.scanFlow.isScanning();
    const snapshot = this.scanFlow.snapshot();
    this.state = snapshot.state;
    this.reason = snapshot.reason;
  }

  private leave(): void {
    if (this.mode === 'scan') this.scanFlow.dismissPage();
    void router.replaceUrl({ url: 'pages/GameCenter' });
  }

  private disconnect(): void {
    if (this.mode === 'scan') this.scanFlow.leave();
    void router.replaceUrl({ url: 'pages/NearbyFriends' });
  }

  private statusText(): Resource {
    if (this.mode !== 'scan') return $r('app.string.nearby_not_supported');
    if (this.state === 3) return $r('app.string.nearby_mvp_connected');
    if (this.state === 2) return $r('app.string.nearby_mvp_joining');
    if (this.state === 4 && this.reason === 4) return $r('app.string.nearby_mvp_expired');
    if (this.state === 4) return $r('app.string.nearby_mvp_failed');
    return $r('app.string.nearby_mvp_scan_prompt');
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹', { type: ButtonType.Normal }).id('nearby_back').width(48).height(48)
          .fontSize(26).fontColor('#F4EFE6').backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.nearby_back')).onClick(() => this.leave())
        Text(this.mode === 'scan' ? $r('app.string.nearby_screen_scan') : $r('app.string.nearby_screen_invite'))
          .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.pageTitle.size)
          .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').layoutWeight(1)
      }.width('100%').height(48)
      Row({ space: 18 }) {
        Column({ space: 8 }) {
          Text(this.mode === 'scan' ? $r('app.string.nearby_scan_headline') :
            $r('app.string.nearby_invite_headline'))
            .id('nearby_invite_headline').fontFamily('HarmonyOS Sans')
            .fontSize(NEARBY_TYPE.paneTitle.size).fontWeight(FontWeight.Medium)
            .fontColor('#F4EFE6').width('100%')
          Text(this.mode === 'scan' ? $r('app.string.nearby_scan_subtitle') :
            $r('app.string.nearby_invite_subtitle'))
            .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.muted.size)
            .fontColor('#BEB8AE').width('100%')
        }.width('44%').height('100%').justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
        Column({ space: 16 }) {
          Text(this.statusText()).id('nearby_pairing_status').fontFamily('HarmonyOS Sans')
            .fontSize(NEARBY_TYPE.body.size).fontColor('#F4EFE6').width('100%')
          if (this.mode === 'scan' && !this.scanning && this.state === 4) {
            Button($r('app.string.nearby_mvp_scan_action'), { type: ButtonType.Normal })
              .id('nearby_mvp_scan_action').height(48).fontSize(NEARBY_TYPE.action.size)
              .fontColor('#121316').backgroundColor('#FF6B5E')
              .onClick(() => { void this.scanQr(); })
          }
          if (this.mode === 'scan' && this.state === 2) {
            Button($r('app.string.nearby_action_disconnect'), { type: ButtonType.Normal })
              .id('nearby_scan_disconnect').height(48).fontSize(NEARBY_TYPE.action.size)
              .fontColor('#F4EFE6').backgroundColor('#292B31').onClick(() => this.disconnect())
          }
        }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start).padding(16)
          .backgroundColor('#1B1D22').borderRadius(12)
      }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }.id('nearby_page').width('100%').height('100%').backgroundColor('#121316')
  }
}

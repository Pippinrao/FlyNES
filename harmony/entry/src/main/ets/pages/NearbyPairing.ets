import { router } from '@kit.ArkUI';
import { scanBarcode } from '@kit.ScanKit';
import nativeSession from 'libentry.so';
import { NearbyMvpHostFlow } from '../service/NearbyMvpHostFlow';
import { nearbyScanJoinService } from '../service/NearbyScanJoinService';
import { NEARBY_TYPE } from '../ui/NearbyTypography';

@Entry
@Component
struct NearbyPairing {
  @State private mode: string = 'create';
  @State private state: number = 0;
  @State private reason: number = 0;
  @State private scanning: boolean = false;
  @State private invite: string = '';
  @State private availableWidth: number = 640;
  @State private availableHeight: number = 360;
  private timerId: number = -1;
  private lobbyOpened: boolean = false;
  private autoScanLaunched: boolean = false;
  private readonly hostFlow: NearbyMvpHostFlow = new NearbyMvpHostFlow();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    this.mode = params && params['mode'] === 'scan' ? 'scan' : 'create';
    this.timerId = setInterval(() => this.poll(), 250);
    if (this.mode === 'create') {
      const existing = nativeSession.nearbyMvpSnapshot();
      if (existing.role !== 1 || (existing.state !== 1 && existing.state !== 3)) {
        try {
          if (!this.hostFlow.start()) this.state = 4;
        } catch (_) { this.state = 4; }
      }
      this.poll();
      return;
    }
    if (!this.autoScanLaunched && (params === undefined || params['resume'] !== 'true')) {
      this.autoScanLaunched = true;
      setTimeout(() => { void this.scanQr(); }, 0);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = -1;
    // Page navigation, including the Scan Kit extension, retains the native connection.
    this.hostFlow.hidePage();
  }

  private poll(): void {
    if (this.mode === 'scan') nearbyScanJoinService.poll();
    const snapshot = this.mode === 'scan'
      ? nearbyScanJoinService.snapshot() : nativeSession.nearbyMvpSnapshot();
    this.state = snapshot.state;
    this.reason = snapshot.reason;
    if (this.mode === 'create') this.invite = this.hostFlow.invite();
    if (snapshot.state === 3 && !this.lobbyOpened) {
      this.lobbyOpened = true;
      if (this.timerId !== -1) clearInterval(this.timerId);
      this.timerId = -1;
      void router.replaceUrl({ url: 'pages/NearbyLobby' });
    }
  }

  private async scanQr(): Promise<void> {
    if (this.scanning) return;
    this.scanning = true;
    try {
      const scanned = await scanBarcode.startScanForResult(getContext(this));
      await nearbyScanJoinService.joinScannedText(scanned.originalValue);
    } catch (_) {
      this.state = 4;
    } finally {
      this.scanning = false;
      this.poll();
    }
  }

  private leave(): void {
    router.back();
  }

  private regenerate(): void {
    if (this.mode !== 'create' || this.state === 3) return;
    this.hostFlow.disconnect();
    this.invite = '';
    this.state = 0;
    try {
      if (!this.hostFlow.start()) this.state = 4;
    } catch (_) { this.state = 4; }
    this.poll();
  }

  private qrSize(): number {
    return Math.max(120, Math.min(this.availableHeight - 96, this.availableWidth * 0.44 - 32));
  }

  private disconnect(): void {
    if (this.mode === 'scan') nearbyScanJoinService.cancel();
    else this.hostFlow.disconnect();
    void router.replaceUrl({ url: 'pages/NearbyFriends' });
  }

  private statusText(): Resource {
    if (this.mode === 'create') {
      if (this.invite.length > 0) return $r('app.string.nearby_role_host_hint');
      if (this.state === 4) return $r('app.string.nearby_mvp_failed');
      return $r('app.string.nearby_mvp_joining');
    }
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
        Column() {
          if (this.mode === 'create' && this.invite.length > 0) {
            Column() {
              QRCode(this.invite).width(this.qrSize() - 24).height(this.qrSize() - 24)
                .id('nearby_invite_qr').backgroundColor(Color.White)
            }.width(this.qrSize()).height(this.qrSize()).padding(12)
              .backgroundColor(Color.White).borderRadius(4)
          } else {
            Text(this.mode === 'scan' ? $r('app.string.nearby_scan_cameraHint') :
              $r('app.string.nearby_screen_connecting'))
              .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.body.size)
              .fontColor('#BEB8AE').textAlign(TextAlign.Center)
          }
        }.width('44%').height('100%').justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center).backgroundColor('#1B1D22').borderRadius(16)
        Column({ space: this.availableHeight > 420 ? 16 : 8 }) {
          Text(this.mode === 'scan' ? $r('app.string.nearby_scan_headline') :
            $r('app.string.nearby_invite_headline'))
            .id('nearby_invite_headline').fontFamily('HarmonyOS Sans')
            .fontSize(NEARBY_TYPE.paneTitle.size).fontWeight(FontWeight.Medium)
            .fontColor('#F4EFE6').width('100%')
          if (this.availableHeight > 420) {
            Text($r('app.string.nearby_network_auto_hint'))
              .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.muted.size)
              .fontColor('#BEB8AE').width('100%').maxLines(2)
          }
          Text(this.statusText()).id('nearby_pairing_status').fontFamily('HarmonyOS Sans')
            .fontSize(NEARBY_TYPE.body.size).fontColor('#F4EFE6').width('100%')
          if (this.mode === 'create') {
            Button($r('app.string.nearby_action_regenerate'), { type: ButtonType.Normal })
              .id('nearby_invite_regenerate').height(48).fontSize(NEARBY_TYPE.action.size)
              .fontColor('#121316').backgroundColor('#FF6B5E')
              .borderRadius(12).onClick(() => this.regenerate())
          }
          if (this.mode === 'scan' && !this.scanning && this.state === 4) {
            Button($r('app.string.nearby_mvp_scan_action'), { type: ButtonType.Normal })
              .id('nearby_mvp_scan_action').height(48).fontSize(NEARBY_TYPE.action.size)
              .fontColor('#121316').backgroundColor('#FF6B5E')
              .onClick(() => { void this.scanQr(); })
          }
          if (this.state === 2 || this.mode === 'create' && this.state === 1) {
            Button($r('app.string.nearby_action_disconnect'), { type: ButtonType.Normal })
              .id('nearby_scan_disconnect').height(48).fontSize(NEARBY_TYPE.action.size)
              .fontColor('#F4EFE6').backgroundColor('#292B31')
              .borderRadius(12).onClick(() => this.disconnect())
          }
        }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start).padding({ left: 8, right: 8 })
      }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }.id('nearby_page').width('100%').height('100%').backgroundColor('#121316')
      .onAreaChange((_old: Area, area: Area) => {
        this.availableWidth = Number(area.width);
        this.availableHeight = Number(area.height);
      })
  }
}

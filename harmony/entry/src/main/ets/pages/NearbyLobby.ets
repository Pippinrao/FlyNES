import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import nativeSession, { NearbyMvpSnapshotDto } from 'libentry.so';
import { NEARBY_TYPE } from '../ui/NearbyTypography';
import { NearbyLobbyRow, nearbyLobbyDetailRows, nearbyLobbyFirstScreenRows, nearbyString } from '../service/NearbyService';
import { BuiltinGames } from '../service/BuiltinGames';
import { PlayService, RomLaunchLocator } from '../service/PlayService';
import { image } from '@kit.ImageKit';
import { CoverStore } from '../service/CoverStore';
import { nearbyRoomGame } from '../service/NearbyRoomGame';

@Entry
@Component
struct NearbyLobby {
  @State private detailsOpen: boolean = false;
  @State private detailIndex: number = 0;
  @State private mvpActive: boolean = false;
  @State private mvpState: number = 0;
  @State private mvpReason: number = 0;
  @State private localReady: number = 0;
  @State private peerReady: number = 0;
  @State private role: number = 0;
  @State private gameTitle: string = '';
  @State private gameError: boolean = false;
  @State private gamePaused: boolean = false;
  @State private cover: image.PixelMap | undefined = undefined;
  private coverKey: string = '';
  private loadingGame: string = '';
  private loadingConfigToken: string = '';
  private attemptedConfigToken: string = '';
  private lastGuestConfigured: boolean = false;
  private selectedGame: string = '';
  private timerId: number = -1;
  private playOpened: boolean = false;
  private pendingChooseGame: boolean = false;

  aboutToAppear(): void {
    const snapshot = nativeSession.nearbyMvpSnapshot();
    if (snapshot.state === 4) {
      void router.replaceUrl({ url: 'pages/NearbyFriends' });
      return;
    }
    this.mvpActive = snapshot.state === 3 || snapshot.state === 5 || snapshot.state === 6 || snapshot.state === 7;
    if (!this.mvpActive) return;
    const params = router.getParams() as Record<string, string> | undefined;
    this.gameTitle = params?.['nearbyGameTitle'] ?? nearbyRoomGame.title;
    this.selectedGame = params?.['nearbyGameKey'] ?? nearbyRoomGame.canonicalId;
    if (this.selectedGame.length > 0) nearbyRoomGame.select(this.selectedGame, this.gameTitle);
    this.updateMvp(snapshot);
    this.timerId = setInterval(() => this.pollMvp(), 50);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = -1;
  }

  private async selectHostGame(key: string, configToken: string = ''): Promise<void> {
    if (key.length === 0) return;
    if (configToken.length === 0) {
      if (this.loadingGame === key || this.selectedGame === key) return;
    } else {
      if (this.loadingConfigToken === configToken || this.attemptedConfigToken === configToken) return;
      this.loadingConfigToken = configToken;
      this.attemptedConfigToken = configToken;
    }
    this.loadingGame = key;
    this.gameError = false;
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.loadingGame = '';
      this.gameError = true;
      return;
    }
    const context = hostContext as common.UIAbilityContext;
    try {
      const locator = new RomLaunchLocator();
      locator.canonicalId = key;
      const builtin = BuiltinGames.loadSync(context).byCanonicalId(key);
      if (builtin !== undefined) {
        this.gameTitle = builtin.titleZhHans || builtin.titleEn;
      } else {
        const row = nativeSession.catalogSnapshot().find((row) => row.canonicalId === key);
        if (row === undefined) throw new Error('Local game missing');
        locator.sourceUuidHex = row.sourceUuidHex;
        locator.sourceRelativePath = row.sourceRelativePath;
        locator.packageFormat = row.packageFormat;
        locator.zipEntryName = row.originalFilename;
        this.gameTitle = row.titleZhHans || row.titleEn || row.originalFilename;
      }
      const rom = await new PlayService().readRom(context, locator);
      const latest = nativeSession.nearbyMvpSnapshot();
      if (latest.role === 1) {
        if (latest.state !== 3 || !nativeSession.nearbyMvpSelectGame(rom, key))
          throw new Error('Local game could not be selected');
      } else {
        if (latest.peerGameKey !== key || latest.peerConfigToken !== configToken || latest.state !== 5) return;
        if (!nativeSession.nearbyMvpSelectRom(rom) || !nativeSession.nearbyMvpConfirm())
          throw new Error('Local ROM does not match');
      }
      this.selectedGame = key;
      nearbyRoomGame.select(key, this.gameTitle);
    } catch (_) {
      this.gameError = true;
      console.info('FlyNesNearby event=local_game_unavailable');
    } finally {
      if (this.loadingGame === key) this.loadingGame = '';
      if (this.loadingConfigToken === configToken) this.loadingConfigToken = '';
    }
  }

  private pollMvp(): void {
    if (!this.mvpActive) return;
    const snapshot = nativeSession.nearbyMvpSnapshot();
    if (snapshot.state === 4) {
      if (this.timerId !== -1) clearInterval(this.timerId);
      this.timerId = -1;
      void router.replaceUrl({ url: 'pages/NearbyFriends' });
      return;
    }
    this.updateMvp(snapshot);
    if (this.pendingChooseGame && snapshot.state === 3) {
      this.pendingChooseGame = false;
      if (this.timerId !== -1) clearInterval(this.timerId);
      this.timerId = -1;
      void router.replaceUrl({ url: 'pages/GameCenter', params: { nearbyChooseGame: true } });
      return;
    }
    if (snapshot.state === 3 || snapshot.state === 7) {
      nearbyRoomGame.clear();
      this.selectedGame = '';
      this.gameTitle = '';
      this.gameError = false;
      this.loadingConfigToken = '';
      this.attemptedConfigToken = '';
      this.lastGuestConfigured = false;
    }
    if (snapshot.role === 2 && snapshot.state === 5) {
      const configured = snapshot.localConfigured !== 0 && snapshot.reason !== 7 && snapshot.reason !== 8;
      if (this.lastGuestConfigured && !configured) {
        this.attemptedConfigToken = '';
        this.loadingConfigToken = '';
      }
      this.lastGuestConfigured = configured;
      if (snapshot.localConfigured !== 0 && snapshot.reason !== 7 && snapshot.reason !== 8 &&
          this.attemptedConfigToken.length === 0)
        this.attemptedConfigToken = snapshot.peerConfigToken;
      if (snapshot.peerConfigToken.length > 0 && snapshot.peerConfigToken !== this.attemptedConfigToken)
        void this.selectHostGame(snapshot.peerGameKey, snapshot.peerConfigToken);
    }
    if (snapshot.state === 6) {
      this.gameTitle = nearbyRoomGame.title;
      this.selectedGame = nearbyRoomGame.canonicalId;
    }
    void this.loadCover();
    if (snapshot.state === 6 && !snapshot.paused && !this.playOpened) {
      this.playOpened = true;
      if (this.timerId !== -1) clearInterval(this.timerId);
      this.timerId = -1;
      router.replaceUrl({ url: 'pages/RunGame', params: { nearby: true, titleZhHans: this.gameTitle, canonicalId: this.selectedGame } });
    }
  }

  private updateMvp(snapshot: NearbyMvpSnapshotDto): void {
    this.gamePaused = snapshot.paused;
    this.mvpState = snapshot.state;
    this.mvpReason = snapshot.reason;
    this.localReady = snapshot.localReady;
    this.peerReady = snapshot.peerReady;
    this.role = snapshot.role;
  }

  private leave(): void {
    void router.replaceUrl({ url: 'pages/GameCenter' });
  }

  private disconnect(): void {
    if (this.mvpActive) nativeSession.nearbyMvpCancel();
    void router.replaceUrl({ url: 'pages/NearbyFriends' });
  }

  private chooseGame(): void {
    if (this.role !== 1 || (this.mvpState !== 3 && this.mvpState !== 5 && this.mvpState !== 6)) return;
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = -1;
    void router.pushUrl({ url: 'pages/GameCenter', params: { nearbyChooseGame: true } });
  }

  onPageShow(): void {
    if (this.mvpActive && this.timerId === -1) this.timerId = setInterval(() => this.pollMvp(), 50);
  }

  onPageHide(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = -1;
  }

  private async loadCover(): Promise<void> {
    const key = this.selectedGame;
    if (key === this.coverKey) return;
    this.coverKey = key;
    this.cover = undefined;
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (key.length === 0 || host === undefined) return;
    const loaded = await new CoverStore(host.filesDir).load(key);
    if (this.coverKey === key) this.cover = loaded;
    else loaded?.release();
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹', { type: ButtonType.Normal }).width(48).height(48)
          .fontFamily('HarmonyOS Sans').fontSize('26vp').fontColor('#F4EFE6').backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.nearby_back')).onClick(() => { this.leave(); })
        Text($r('app.string.nearby_lobby_title')).fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.pageTitle.size)
          .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').layoutWeight(1)
        if (this.mvpActive) {
          Button($r('app.string.nearby_action_disconnect'), { type: ButtonType.Normal })
            .id('nearby_lobby_disconnect').height(48).padding({ left: 12, right: 12 })
            .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.action.size)
            .fontColor('#F4EFE6').backgroundColor('#1B1D22')
            .onClick(() => { this.disconnect(); })
        }
      }.width('100%').constraintSize({ minHeight: 48 })
      Row({ space: 16 }) {
        Column({ space: 12 }) {
          this.fieldRow(nearbyLobbyFirstScreenRows()[1])
          this.fieldRow(nearbyLobbyFirstScreenRows()[2])
        }.width('25%').height('100%').padding(12)
          .backgroundColor('#1B1D22').borderRadius(12)
        Row({ space: 16 }) {
          Column({ space: 8 }) {
            Stack() {
              if (this.cover !== undefined) {
                Image(this.cover).width('100%').height('100%').objectFit(ImageFit.Contain)
                  .id('nearby_lobby_cover')
              } else {
                Text(this.gameTitle || $r('app.string.nearby_wait_host_game'))
                  .fontSize(NEARBY_TYPE.muted.size).fontColor('#A8B0BD')
                  .maxLines(2).textAlign(TextAlign.Center).padding(8)
              }
            }.width('100%').layoutWeight(1).backgroundColor('#12141A').borderRadius(8).clip(true)
            Text(this.gameTitle || $r('app.string.nearby_wait_host_game'))
              .id('nearby_lobby_rom_identity').fontSize(NEARBY_TYPE.body.size)
              .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').width('100%').maxLines(2)
          }.layoutWeight(1).height('100%').padding(8).backgroundColor('#23262C')
            .borderRadius(12).border({ width: 1, color: '#FF6B5E' })
          Column({ space: 12 }) {
          Text(this.gameError ? $r('app.string.nearby_local_game_missing') :
            this.mvpState === 6 && this.gamePaused ? $r('app.string.nearby_game_paused') :
            this.mvpState === 3 ? (this.role === 1 ? $r('app.string.nearby_action_goToGameCenter') :
              $r('app.string.nearby_wait_host_game')) :
            $r('app.string.nearby_screen_connecting'))
            .id('nearby_lobby_mvp_status').fontFamily('HarmonyOS Sans')
            .fontSize(NEARBY_TYPE.muted.size).fontColor(this.gameError ? '#FF6B5E' : '#BEB8AE')
            .width('100%')
          if (this.mvpState === 6) {
            this.action($r('app.string.nearby_resume_game'), 'nearby_lobby_resume', true,
              () => { nativeSession.nearbyMvpResumeGame(); this.pollMvp(); })
          }
          if (this.mvpActive && this.role === 1 && (this.mvpState === 3 || this.mvpState === 5 || this.mvpState === 6)) {
            this.action(this.gameTitle.length > 0 ? $r('app.string.nearby_change_game') :
              $r('app.string.nearby_action_goToGameCenter'), 'nearby_lobby_choose_game', this.mvpState !== 6,
              () => { this.chooseGame(); })
          }
          }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
        }.layoutWeight(1).height('100%').padding(12).backgroundColor('#1B1D22').borderRadius(12)
      }.width('100%').layoutWeight(1).padding(16)
    }.id('nearby_page').width('100%').height('100%').backgroundColor('#121316')
  }

  private rowValue(row: NearbyLobbyRow): ResourceStr {
    if (!this.mvpActive) return '—';
    if (row.label === 'nearby_lobby_rom_identity') {
      if (this.gameError) return $r('app.string.nearby_local_game_missing');
      return this.gameTitle || $r('app.string.nearby_wait_host_game');
    }
    const isFirst = row.label === 'nearby_lobby_network_owner';
    return (isFirst === (this.role === 1)) ? $r('app.string.nearby_player_local') :
      $r('app.string.nearby_player_peer');
  }

  @Builder
  fieldRow(row: NearbyLobbyRow) {
    Column({ space: 8 }) {
      Text(row.label === 'nearby_lobby_network_owner' ? 'P1' : 'P2').fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.sectionTitle.size)
        .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').width('100%')
      Text(this.rowValue(row))
        .fontFamily('HarmonyOS Sans')
        .fontSize(row.label === 'nearby_lobby_rom_identity' ? NEARBY_TYPE.body.size : NEARBY_TYPE.muted.size)
        .fontColor(row.label === 'nearby_lobby_rom_identity' ? '#F4EFE6' : '#BEB8AE').width('100%')
    }.id(row.label).layoutWeight(1)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
      .onClick(() => { if (row.label === 'nearby_lobby_rom_identity') this.chooseGame(); })
  }

  @Builder
  action(label: Resource, id: string, primary: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).id(id).width('100%').height(48)
      .padding(8).borderRadius(12)
      .labelStyle({ maxLines: 2 }).fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.action.size).fontColor(primary ? '#121316' : '#F4EFE6')
      .backgroundColor(primary ? '#FF6B5E' : '#1B1D22')
      .border({ width: 1, color: primary ? '#FF6B5E' : '#393B40' })
      .borderRadius(12)
      .onClick(action)
  }
}

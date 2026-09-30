import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { display, window } from '@kit.ArkUI';
import { Driver, ON, MatchPattern } from '@ohos.UiTest';
import nativeSession from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { nearbyRoomGame } from '../../../main/ets/service/NearbyRoomGame';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}
function writeEvidence(path: string, content: string | ArrayBuffer): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, content); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file.fd); }
}

// Test-only UDP envelope opens both simulator NATs. The real QUIC bytes,
// invitation pin/token and production native session remain end to end.
class SimulatorHostRelay {
  private external = socket.constructUDPSocketInstance();
  private local = socket.constructUDPSocketInstance();
  private timer: number = -1;
  private failure: string = '';
  async start(invite: string, port: number, token: string): Promise<void> {
    expect(/^[a-f0-9]{32}$/.test(token)).assertTrue();
    expect(port >= 1024 && port <= 65535).assertTrue();
    const fields = invite.split(':');
    expect(fields[1].startsWith('10.0.2.')).assertTrue();
    const nativeAddress: socket.NetAddress = { address: fields[1], port: Number.parseInt(fields[2], 10), family: 1 };
    const relayAddress: socket.NetAddress = { address: '10.0.2.2', port: port, family: 1 };
    const prefix = new util.TextEncoder().encodeInto(`FG2|${token}|H|`);
    await this.local.bind({ address: fields[1], port: 0, family: 1 });
    await this.external.bind({ address: fields[1], port: 0, family: 1 });
    this.external.on('message', (event: socket.SocketMessageInfo): void => {
      if (event.remoteInfo.address !== relayAddress.address || event.remoteInfo.port !== port || event.message.byteLength > 65460) return;
      void this.local.send({ data: event.message, address: nativeAddress }).catch(() => { this.failure = 'local_send'; });
    });
    this.local.on('message', (event: socket.SocketMessageInfo): void => {
      if (event.remoteInfo.address !== nativeAddress.address || event.remoteInfo.port !== nativeAddress.port || event.message.byteLength > 65460) return;
      const packet = new Uint8Array(prefix.length + event.message.byteLength);
      packet.set(prefix); packet.set(new Uint8Array(event.message), prefix.length);
      void this.external.send({ data: packet.buffer as ArrayBuffer, address: relayAddress }).catch(() => { this.failure = 'relay_send'; });
    });
    await this.external.send({ data: prefix.buffer as ArrayBuffer, address: relayAddress });
    this.timer = setInterval(() => {
      void this.external.send({ data: prefix.buffer as ArrayBuffer, address: relayAddress }).catch(() => { this.failure = 'registration'; });
    }, 500);
  }
  async close(): Promise<void> {
    if (this.timer !== -1) clearInterval(this.timer);
    await this.external.close(); await this.local.close();
    expect(this.failure).assertEqual('');
  }
}

export default function nearbyMvpExternalHostTest(): void {
  describe('NearbyMvpExternalHost', () => {
    it('real_napi_host_serves_external_product_guest', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments().parameters;
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      const driver = Driver.create();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000) !== null).assertTrue();
      const context = (await delegator.getCurrentTopAbility()).context;
      const win = await window.getLastWindow(context);
      nativeSession.nearbyMvpCancel();
      const invitePath = `${context.filesDir}/nearby-cross-host-invite.txt`;
      const relay = new SimulatorHostRelay();
      let relayStarted = false;
      try {
        const token = new Uint8Array(16); for (let i = 0; i < token.length; i++) token[i] = Math.floor(Math.random() * 256);
        expect(nativeSession.nearbyMvpHost(token)).assertTrue();
        let invite = '';
        const inviteDeadline = Date.now() + 10000;
        while (invite.length === 0 && Date.now() < inviteDeadline) { invite = nativeSession.nearbyMvpInvite(); await delay(20); }
        expect(invite.startsWith('flynes-lan-v1:')).assertTrue();
        const relayToken = args['-s simulatorRelayToken'];
        const relayPort = args['-s simulatorRelayPort'];
        if (typeof relayToken === 'string' && typeof relayPort === 'string') {
          await relay.start(invite, Number.parseInt(relayPort, 10), relayToken); relayStarted = true;
        }
        writeEvidence(invitePath, invite);
        await waitState(3, 60000);
        const connectedId = nativeSession.nearbyMvpSnapshot().sessionId;
        expect(nativeSession.nearbyMvpSnapshot().role).assertEqual(1);
        const games = BuiltinGames.loadSync(context).all().filter((game) => game.multiplayerEligibility === 'SUPPORTED' && game.multiplayerMaxPlayers === 2);
        expect(games.length >= 2).assertTrue();
        await win.getUIContext().getRouter().replaceUrl({ url: 'pages/NearbyLobby' });
        await (await driver.waitForComponent(ON.id('nearby_lobby_choose_game'), 10000)).click();
        await chooseFlutterGame(driver, games[0].titleEn, games[0].titleZhHans);
        await waitState(6, 20000);
        const firstKey = nearbyRoomGame.canonicalId;
        expect(firstKey.length > 0 && !firstKey.startsWith('builtin:')).assertTrue();
        expect(nearbyRoomGame.title === games[0].titleEn || nearbyRoomGame.title === games[0].titleZhHans).assertTrue();
        expect(nativeSession.nearbyMvpSnapshot().sessionId).assertEqual(connectedId);
        await assertControls(driver, win);
        const frames = nativeSession.nearbyMvpSnapshot().completedFrames;
        await delay(1000);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames > frames + 20).assertTrue();
        const audio = nativeSession.playRuntimeStatus();
        expect(audio.audioStarted && audio.audioConsumedSamples > 4800).assertTrue();
        console.info(`FlyNesNearby host_product_audio consumed=${audio.audioConsumedSamples}`);
        writeEvidence(`${context.filesDir}/nearby-g2-host-frame.rgb565`, nativeSession.playStep().rgb565);
        expect(nativeSession.renderStatus().presentedFrames > 30).assertTrue();
        await driver.screenCap(`${context.filesDir}/nearby-g2-oh-host.png`);
        await pauseCommand(driver, context, 'pause_continue', true);
        const paused = nativeSession.nearbyMvpSnapshot().completedFrames;
        await delay(800);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames).assertEqual(paused);
        await pauseCommand(driver, context, 'pause_continue');
        await delay(1200);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames > paused + 10).assertTrue();
        await pauseCommand(driver, context, 'pause_game_center');
        const resume = await driver.waitForComponent(ON.id('nearby_lobby_resume'), 10000);
        expect(resume !== null).assertTrue();
        const held = nativeSession.nearbyMvpSnapshot().completedFrames;
        await delay(600);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames).assertEqual(held);
        expect(nearbyRoomGame.canonicalId).assertEqual(firstKey);
        await resume.click(); await delay(1200);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames > held + 10).assertTrue();
        expect(nativeSession.nearbyMvpSnapshot().sessionId).assertEqual(connectedId);
        await pauseCommand(driver, context, 'pause_game_center');
        await (await driver.waitForComponent(ON.id('nearby_lobby_choose_game'), 10000)).click();
        await chooseFlutterGame(driver, games[1].titleEn, games[1].titleZhHans);
        await waitState(6, 20000); await delay(3000);
        expect(nearbyRoomGame.canonicalId !== firstKey).assertTrue();
        expect(nearbyRoomGame.title === games[1].titleEn || nearbyRoomGame.title === games[1].titleZhHans).assertTrue();
        expect(nativeSession.nearbyMvpSnapshot().sessionId).assertEqual(connectedId);
        expect(nativeSession.nearbyMvpSnapshot().completedFrames > 30).assertTrue();
        expect(nativeSession.playRuntimeStatus().audioConsumedSamples > 0).assertTrue();
        console.info('FlyNesNearby host_flutter_lobby_switch second_game=PASS same_session=true');
        await delay(5000);
      } catch (error) {
        await driver.screenCap(`${context.filesDir}/nearby-g2-host-failed.png`);
        throw error as Error;
      } finally {
        nativeSession.nearbyMvpCancel();
        if (relayStarted) await relay.close();
      }
    });
  });
}

async function waitState(wanted: number, timeout: number): Promise<void> {
  const deadline = Date.now() + timeout;
  while (nativeSession.nearbyMvpSnapshot().state !== wanted && Date.now() < deadline) await delay(20);
  expect(nativeSession.nearbyMvpSnapshot().state).assertEqual(wanted);
}
async function clickText(driver: Driver, labels: string[]): Promise<void> {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    for (const label of labels) {
      const control = await driver.findComponent(ON.text(label).type('Button'));
      if (control !== null && await control.isEnabled()) { await control.click(); return; }
    }
    await delay(100);
  }
  throw new Error(`Flutter control unavailable: ${labels[0]}`);
}
async function chooseFlutterGame(driver: Driver, title: string, chinese: string): Promise<void> {
  expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
  await clickText(driver, ['Built-in', '内置']);
  let card = await driver.findComponent(ON.text(title, MatchPattern.STARTS_WITH).type('Button'));
  if (card === null) card = await driver.findComponent(ON.text(chinese, MatchPattern.STARTS_WITH).type('Button'));
  if (card === null) {
    const grid = await driver.waitForComponent(ON.type('Scroll'), 5000);
    card = await grid.scrollSearch(ON.text(chinese, MatchPattern.STARTS_WITH).type('Button'), true, 100);
  }
  expect(card !== null).assertTrue(); await card.click(); await delay(400);
  await clickText(driver, ['Choose game', '选择游戏']);
  expect(await driver.waitForComponent(ON.text('II'), 20000) !== null).assertTrue();
  console.info(`FlyNesNearby flutter_chooser title=${title} production_launch=true`);
}
async function assertControls(driver: Driver, win: window.Window): Promise<void> {
  expect(await driver.waitForComponent(ON.text('II'), 15000) !== null).assertTrue();
  const rect = win.getWindowProperties().windowRect;
  const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
  const settings = nativeSession.settingsGet();
  const hit = nativeSession.hitMapFromLayout(rect.width, rect.height, display.getDefaultDisplaySync().densityDPI / 160,
    avoid.leftRect.width, avoid.rightRect.width, avoid.topRect.height, avoid.bottomRect.height,
    nativeSession.controlLayoutGet(), Math.max(0, Math.min(2, settings.directionMode - 1)), settings.deadZone);
  const names = ['START', 'SELECT', 'START', 'START', 'A', 'B', 'RIGHT'];
  const bits = [8, 4, 8, 8, 1, 2, 128];
  for (let i = 0; i < names.length; i++) {
    const target = hit.controls.find((control) => control.control === names[i]);
    expect(target !== undefined).assertTrue();
    let sampled = false;
    const timer = setInterval(() => { sampled = sampled || (nativeSession.playStep().appliedButtons & bits[i]) !== 0; }, 10);
    try { await driver.longClick(Math.round(rect.left + target!.centerX), Math.round(rect.top + target!.centerY)); }
    finally { clearInterval(timer); }
    expect(sampled).assertTrue(); await delay(names[i] === 'START' ? 1200 : 150);
  }
}
async function pauseCommand(driver: Driver, context: common.Context, resource: string, hold: boolean = false): Promise<void> {
  const pause = await driver.findComponent(ON.text('II'));
  if (pause !== null) await pause.click();
  expect(await driver.waitForComponent(ON.text(context.resourceManager.getStringByNameSync('pause_resume')), 5000) !== null).assertTrue();
  await delay(300);
  if (hold) return;
  const drawer = await driver.waitForComponent(ON.type('Scroll'), 5000);
  const name = resource === 'pause_continue' ? 'pause_resume' : 'nearby_lobby_title';
  const command = await drawer.scrollSearch(ON.text(context.resourceManager.getStringByNameSync(name)), true, 200);
  expect(command !== null).assertTrue(); await command.click();
}

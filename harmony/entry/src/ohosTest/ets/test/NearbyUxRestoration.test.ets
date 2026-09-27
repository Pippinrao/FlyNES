import { describe, it, expect } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON, Component } from '@ohos.UiTest';
import { parseTestFontSizeScale, resolveTestFontSizeScale } from '../../../main/ets/ui/NearbyTestFontScale';

async function openPage(page: string, scale: string): Promise<Driver> {
  const want: Want = {
    bundleName: 'com.flynes.emu',
    abilityName: 'EntryAbility',
    parameters: { 'flynes.test.page': page, 'flynes.test.fontSizeScale': scale }
  };
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
  const driver: Driver = Driver.create();
  await driver.waitForIdle(300, 4000);
  await driver.delayMs(800);
  return driver;
}

async function control(driver: Driver, id: string): Promise<Component> {
  const component: Component = await driver.waitForComponent(ON.id(id), 5000);
  if (!component) throw new Error(`Missing visible control: ${id}`);
  return component;
}

async function assertFits(driver: Driver, id: string, tap: boolean = true): Promise<void> {
  const page = await (await control(driver, 'nearby_page')).getBounds();
  const item = await (await control(driver, id)).getBounds();
  expect(item.left >= page.left && item.right <= page.right).assertTrue();
  expect(item.top >= page.top && item.bottom <= page.bottom).assertTrue();
  if (tap) expect(px2vp(item.bottom - item.top) >= 47.5).assertTrue();
}

function localized(name: string): string {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
    .createModuleContext('entry').resourceManager.getStringByNameSync(name);
}

async function capture(driver: Driver, label: string): Promise<void> {
  expect(await driver.waitForIdle(200, 1500)).assertTrue();
  // Route transitions render asynchronously after the UI thread becomes idle.
  await driver.delayMs(350);
  const directory = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
  expect(await driver.screenCap(`${directory}/flynes-ux-${label}.png`)).assertTrue();
}

export default function nearbyUxRestorationTest() {
  describe('NearbyUxRestoration', () => {
    it('approved_entry_has_two_roles_without_legacy_actions', 0, async () => {
      const driver: Driver = await openPage('nearby_friends', '1');
      await assertFits(driver, 'nearby_action_create');
      await assertFits(driver, 'nearby_action_scanQr');
      await assertFits(driver, 'nearby_card_cta_create');
      await assertFits(driver, 'nearby_card_cta_scan');
      const oldCode = await driver.waitForComponent(ON.id('nearby_action_enterCode'), 500);
      expect(oldCode === null || oldCode === undefined).assertTrue();
    });
    it('invite_places_a_large_square_qr_left_of_the_explanation', 0, async () => {
      const driver: Driver = await openPage('nearby_pairing', '1');
      const page = await (await control(driver, 'nearby_page')).getBounds();
      const qr = await (await control(driver, 'nearby_invite_qr')).getBounds();
      const title = await (await control(driver, 'nearby_invite_headline')).getBounds();
      expect(qr.right - qr.left >= (page.right - page.left) * 0.28).assertTrue();
      expect(Math.abs((qr.right - qr.left) - (qr.bottom - qr.top)) <= 2).assertTrue();
      expect(title.left > qr.right).assertTrue();
      await assertFits(driver, 'nearby_invite_regenerate');
      await assertFits(driver, 'nearby_scan_disconnect');
    });
    it('invite_actions_fit_at_double_font_scale', 0, async () => {
      const driver: Driver = await openPage('nearby_pairing', '2');
      await assertFits(driver, 'nearby_invite_qr', false);
      await assertFits(driver, 'nearby_invite_regenerate');
      await assertFits(driver, 'nearby_scan_disconnect');
    });
    for (const scale of ['1', '1.3', '2']) {
      it(`single_screen_landscape_${scale}`, 0, async () => {
        const driver: Driver = await openPage('nearby_friends', scale);
        for (const id of ['nearby_action_create', 'nearby_action_scanQr']) {
          await assertFits(driver, id);
        }
        await capture(driver, `entry-${scale}`);
        const oldCode = await driver.waitForComponent(ON.id('nearby_action_enterCode'), 200);
        const oldFriends = await driver.waitForComponent(ON.id('nearby_tab_friends'), 200);
        expect(oldCode === null || oldCode === undefined).assertTrue();
        expect(oldFriends === null || oldFriends === undefined).assertTrue();
      });
    }

    for (const scale of ['1', '1.3', '2']) {
    it(`unconnected_lobby_has_core_fields_without_host_action_${scale}`, 0, async () => {
      const driver: Driver = await openPage('nearby_lobby', scale);
      for (const id of ['nearby_lobby_rom_identity', 'nearby_lobby_network_owner', 'nearby_lobby_seat']) {
        await assertFits(driver, id, false);
      }
      const hostAction = await driver.waitForComponent(ON.id('nearby_lobby_choose_game'), 200);
      expect(hostAction === null || hostAction === undefined).assertTrue();
      await capture(driver, `lobby-${scale}`);
      const details = await driver.waitForComponent(ON.id('nearby_lobby_details'), 200);
      expect(details === null || details === undefined).assertTrue();
    });
    }
  });

  describe('NearbyWantParser', () => {
    it('debug_want_accepts_supported_scales_only', 0, () => {
      expect(parseTestFontSizeScale('1.3').accepted).assertTrue();
      expect(parseTestFontSizeScale('1.3').scale).assertEqual(1.3);
      expect(parseTestFontSizeScale('1.2').accepted).assertFalse();
      expect(resolveTestFontSizeScale('1.3', false).accepted).assertFalse();
      expect(resolveTestFontSizeScale('1.3', true).accepted).assertTrue();
    });
  });
}

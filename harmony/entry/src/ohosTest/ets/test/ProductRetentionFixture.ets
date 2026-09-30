import { expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { Component, Driver, MatchPattern, ON } from '@ohos.UiTest';
import nativeApp from 'libentry.so';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';
import { ProductCatalog } from '../../../main/ets/flutter/ProductCatalog';
import { FoundationFlutterEntry } from '../../../main/ets/flutter/FoundationFlutterEntry';

export class NavigationEntry {
  key: string = '';
  exists: boolean = false;
  value: preferences.ValueType = '';
}
export const navigationKeys: string[] = ['category', 'multiplayerOnly', 'selected.all',
  'selected.recent', 'selected.favorites', 'selected.builtin'];

export function saveNavigation(context: common.Context): NavigationEntry[] {
  const store = preferences.getPreferencesSync(context, { name: 'game_center_ui' });
  return navigationKeys.map((key) => {
    const row = new NavigationEntry(); row.key = key; row.exists = store.hasSync(key);
    row.value = store.getSync(key, key === 'multiplayerOnly' ? false : ''); return row;
  });
}
export async function restoreNavigation(context: common.Context, rows: NavigationEntry[]): Promise<void> {
  const store = preferences.getPreferencesSync(context, { name: 'game_center_ui' });
  for (const row of rows) {
    if (row.exists) store.putSync(row.key, row.value); else store.deleteSync(row.key);
  }
  await store.flush();
  expect(JSON.stringify(saveNavigation(context))).assertEqual(JSON.stringify(rows));
}
export function writeEvidence(path: string, value: Object): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, JSON.stringify(value)); fileIo.fsyncSync(file.fd); }
  finally { fileIo.closeSync(file.fd); }
}
export function readBytes(path: string): ArrayBuffer {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const bytes = new ArrayBuffer(Number(fileIo.statSync(file.fd).size));
    expect(fileIo.readSync(file.fd, bytes)).assertEqual(bytes.byteLength); return bytes;
  } finally { fileIo.closeSync(file.fd); }
}
export function writeBytes(path: string, bytes: ArrayBuffer): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, bytes); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file.fd); }
}
export function sameBytes(a: ArrayBuffer, b: ArrayBuffer): boolean {
  if (a.byteLength !== b.byteLength) return false;
  const aa = new Uint8Array(a); const bb = new Uint8Array(b);
  for (let i = 0; i < aa.length; i++) if (aa[i] !== bb[i]) return false;
  return true;
}
export async function normalHall(driver: Driver): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
  expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000) !== null).assertTrue();
  const context = (await delegator.getCurrentTopAbility()).context;
  await new ProductCatalog(context).initialize();
  await hallReady(driver);
  return context;
}
export async function hallReady(driver: Driver): Promise<void> {
  for (let i = 0; i < 150; i++) {
    if (await driver.findComponent(ON.id('product_presentation_gate')) === null &&
        await driver.findComponent(ON.id('history-manual-save')) === null) {
      for (const label of ['Start', '开始', 'Continue', '继续']) {
        const action = await driver.findComponent(ON.text(label).type('Button'));
        if (action !== null && await action.isEnabled()) return;
      }
    }
    await driver.delayMs(100);
  }
  throw new Error('Current Flutter hall did not become interactive');
}
export async function textControl(driver: Driver, labels: string[], type: string = 'Button'): Promise<Component> {
  for (let attempt = 0; attempt < 100; attempt++) {
    for (const label of labels) {
      const item = await driver.findComponent(ON.text(label, MatchPattern.STARTS_WITH).type(type));
      if (item !== null) return item;
    }
    await driver.delayMs(100);
  }
  throw new Error(`Control missing: ${labels[0]}`);
}
export function assertNoGameOrRoom(): void {
  expect(PlayService.lifecycleSnapshot().activeOwners).assertEqual(0);
  expect(FoundationFlutterEntry.activeHostCount()).assertEqual(1);
  let closed = false;
  try { nativeApp.playRuntimeStatus(); } catch (_) { closed = true; }
  expect(closed).assertTrue();
  const room = nativeApp.nearbyMvpSnapshot();
  expect(room.state).assertEqual(0); expect(room.role).assertEqual(0);
  expect(room.localConfigured).assertEqual(0); expect(room.peerConfigured).assertEqual(0);
}
export async function romFor(context: common.UIAbilityContext, catalog: ProductCatalog, id: string): Promise<ArrayBuffer> {
  const row = await catalog.row(id);
  const locator = new RomLaunchLocator(); locator.canonicalId = row.canonicalId;
  locator.sourceUuidHex = row.sourceUuidHex; locator.sourceRelativePath = row.sourceRelativePath;
  locator.packageFormat = row.packageFormat; locator.zipEntryName = row.originalFilename;
  return await new PlayService().readRom(context, locator);
}

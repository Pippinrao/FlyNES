import { SettingsDto } from 'libentry.so';

/** DocumentSelectMode.FOLDER public device/API restrictions; syscap alone is insufficient. */
export function folderSelectionAvailable(deviceType: string, api: number, syscap: boolean): boolean {
  if (!syscap) return false;
  return deviceType === '2in1' ? api >= 13 :
    (deviceType === 'phone' || deviceType === 'tablet') && api >= 26;
}

export function productMap(entries: Array<[string, Object]>): Record<string, Object> {
  const value: Record<string, Object> = {};
  for (const entry of entries) value[entry[0]] = entry[1];
  return value;
}

export class ProductHostLease {
  generation: number = 0;
  token: string = '';
  private active: boolean = false;
  acquire(token: string): number {
    if (this.active) throw new Error('host_busy');
    this.token = token;
    this.active = true;
    return ++this.generation;
  }
  release(generation: number): boolean {
    if (!this.accepts(generation)) return false;
    this.active = false;
    return true;
  }
  accepts(generation: number): boolean { return this.active && generation === this.generation; }
}

export function patchProductSetting(current: SettingsDto, key: string, value: Object): SettingsDto {
  const next: SettingsDto = {
    aspectMode: current.aspectMode, videoQualityPreset: current.videoQualityPreset,
    customRefreshPolicy: current.customRefreshPolicy, customTemporalMode: current.customTemporalMode,
    customSpatialMode: current.customSpatialMode, customPostEffect: current.customPostEffect,
    adaptiveProtection: current.adaptiveProtection, layoutPreset: current.layoutPreset,
    directionMode: current.directionMode, buttonScale: current.buttonScale,
    verticalOffset: current.verticalOffset, controlOpacity: current.controlOpacity,
    joystickScale: current.joystickScale, deadZone: current.deadZone,
    hapticLevel: current.hapticLevel, distinctAbHaptics: current.distinctAbHaptics,
    audioEnabled: current.audioEnabled, audioFocusPolicy: current.audioFocusPolicy,
    autosaveEnabled: current.autosaveEnabled, localeTag: current.localeTag, lastPlayedId: current.lastPlayedId
  };
  if (key === 'localeTag') {
    if (value !== 'system' && value !== 'en' && value !== 'zh-Hans') throw new Error('invalid_setting');
    next.localeTag = value as string;
    return next;
  }
  if (key === 'adaptiveProtection' || key === 'distinctAbHaptics' || key === 'audioEnabled' || key === 'autosaveEnabled') {
    if (typeof value !== 'boolean') throw new Error('invalid_setting');
    const flag = value ? 1 : 0;
    if (key === 'adaptiveProtection') next.adaptiveProtection = flag;
    if (key === 'distinctAbHaptics') next.distinctAbHaptics = flag;
    if (key === 'audioEnabled') next.audioEnabled = flag;
    if (key === 'autosaveEnabled') next.autosaveEnabled = flag;
    return next;
  }
  if (typeof value !== 'number' || !Number.isInteger(value)) throw new Error('invalid_setting');
  const number = value as number;
  if ((key === 'videoQualityPreset' && number === 3) ||
      (key === 'customRefreshPolicy' && (number === 4 || number === 5)) ||
      (key === 'customTemporalMode' && number === 2)) throw new Error('capability_locked');
  switch (key) {
    case 'videoQualityPreset': if (![1, 2, 4].includes(number)) throw new Error('invalid_setting'); next.videoQualityPreset = number; break;
    case 'customRefreshPolicy': if (![1, 3].includes(number)) throw new Error('invalid_setting'); next.customRefreshPolicy = number; break;
    case 'customTemporalMode': if (number !== 1) throw new Error('invalid_setting'); next.customTemporalMode = number; break;
    case 'customSpatialMode': if (number < 1 || number > 4) throw new Error('invalid_setting'); next.customSpatialMode = number; break;
    case 'customPostEffect': if (number < 1 || number > 2) throw new Error('invalid_setting'); next.customPostEffect = number; break;
    case 'aspectMode': if (number < 1 || number > 3) throw new Error('invalid_setting'); next.aspectMode = number; break;
    case 'directionMode': if (number < 1 || number > 3) throw new Error('invalid_setting'); next.directionMode = number; break;
    case 'hapticLevel': if (number < 1 || number > 4) throw new Error('invalid_setting'); next.hapticLevel = number; break;
    case 'audioFocusPolicy': if (number < 1 || number > 3) throw new Error('invalid_setting'); next.audioFocusPolicy = number; break;
    default: throw new Error('invalid_setting');
  }
  return next;
}

import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import nativePlay, { HistoryRow } from 'libentry.so';
import { SaveHistoryService } from '../service/SaveHistoryService';

@Component
export struct SaveHistoryPanel {
  history: SaveHistoryService | undefined = undefined;
  initialAction: string = '';
  onClose: () => void = () => {};
  onRestored: () => void = () => {};
  onRestarted: () => void = () => {};
  @State private rows: HistoryRow[] = [];
  @State private selected: HistoryRow | undefined = undefined;
  @State private picture: image.PixelMap | undefined = undefined;
  @State private note: string = '';
  @State private confirmation: string = '';
  @State private failed: boolean = false;
  @State private interval: number = 2;

  aboutToAppear(): void {
    this.refresh();
    this.confirmation = this.initialAction;
    this.interval = [0, 30000, 60000, 120000, 300000].indexOf(this.history?.intervalMs ?? 60000);
  }
  aboutToDisappear(): void { this.picture?.release(); this.picture = undefined; }
  private refresh(): void {
    try {
      this.rows = this.history?.list() ?? [];
      const previous = this.selected?.id ?? 0;
      this.choose(this.rows.find((row) => row.id === previous) ?? this.rows[0]);
    } catch (_) { this.failed = true; }
  }
  private choose(row: HistoryRow | undefined): void {
    this.selected = row;
    this.note = row?.label ?? '';
    this.picture?.release(); this.picture = undefined;
    if (row === undefined || this.history === undefined) return;
    try {
      const bytes = this.history.thumbnail(row.id);
      if (bytes.byteLength === 256 * 240 * 2) {
        this.picture = image.createPixelMapSync(bytes, { size: { width: 256, height: 240 },
          srcPixelFormat: image.PixelMapFormat.RGB_565, pixelFormat: image.PixelMapFormat.RGB_565, editable: false });
      }
    } catch (_) { this.failed = true; }
  }
  private kind(row: HistoryRow): Resource {
    if (row.kind === 1) return $r('app.string.history_manual_kind');
    if (row.kind === 2) return $r('app.string.history_protection');
    if (row.kind === 3) return $r('app.string.history_legacy');
    return $r('app.string.history_auto');
  }
  private edit(remove: boolean, toggle: boolean = false): void {
    const row = this.selected;
    if (row === undefined) return;
    try {
      this.history?.edit(row.id, this.note.trim().slice(0, 120), toggle ? !row.pinned : row.pinned, remove);
      this.failed = false; this.refresh();
    } catch (_) { this.failed = true; }
  }
  private confirm(): void {
    const action = this.confirmation;
    this.confirmation = '';
    try {
      if (action === 'restart') { this.history?.restart(); this.onRestarted(); return; }
      if (action === 'delete') this.edit(true);
      if (action === 'restore' && this.selected !== undefined) {
        this.history?.restore(this.selected.id); this.onRestored(); this.onClose(); return;
      }
      this.refresh();
    } catch (_) { this.failed = true; }
  }
  private setIntervalChoice(index: number): void {
    const value = [0, 30000, 60000, 120000, 300000][index];
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const options = preferences.getPreferencesSync(host, { name: 'save_history' });
      options.putSync('intervalMs', value); options.flushSync();
      const settings = nativePlay.settingsGet(); settings.autosaveEnabled = value > 0 ? 1 : 0;
      nativePlay.settingsApply(settings);
      if (this.history !== undefined) this.history.intervalMs = value;
      this.interval = index;
    } catch (_) { this.failed = true; }
  }
  build() {
    Stack() {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Text($r('app.string.history_title')).fontSize(22).fontColor('#F4EFE6').layoutWeight(1)
          Button($r('app.string.history_close')).id('history-close').onClick(() => this.onClose())
        }.width('100%')
        if (this.failed) { Text($r('app.string.history_failed')).fontColor('#FF9B8C').fontSize(14) }
        Row({ space: 16 }) {
          List({ space: 8 }) {
            ForEach(this.rows, (row: HistoryRow) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(new Date(row.createdMs).toLocaleString()).fontSize(15).fontColor('#F4EFE6')
                  Row({ space: 8 }) {
                    Text(this.kind(row)).fontColor('#C5CCD6').fontSize(13)
                    Text(`${Math.floor(row.playedMs / 60000)}:${`${Math.floor(row.playedMs / 1000) % 60}`.padStart(2, '0')}`).fontColor('#C5CCD6').fontSize(13)
                  }
                  if (row.label.length > 0) { Text(row.label).fontColor('#F4EFE6').maxLines(2) }
                  if (row.isHead) { Text($r('app.string.history_current')).fontColor('#FF9B8C').fontSize(13) }
                  if (row.pinned) { Text($r('app.string.history_pin')).fontColor('#FF9B8C').fontSize(13) }
                }.alignItems(HorizontalAlign.Start).width('100%').padding(12)
                  .backgroundColor(this.selected?.id === row.id ? '#414754' : '#25282F').borderRadius(10)
              }.id(`history-row-${row.id}`).onClick(() => this.choose(row))
            }, (row: HistoryRow) => `${row.id}`)
          }.id('history-list').width('45%').height('100%')
          Scroll() {
            Column({ space: 8 }) {
              if (this.picture !== undefined) { Image(this.picture).id('history-preview').width('100%').height(150).objectFit(ImageFit.Contain).backgroundColor('#000000') }
              if (this.selected !== undefined) {
                TextInput({ text: this.note, placeholder: $r('app.string.history_note') }).fontColor('#F4EFE6').placeholderColor('#A8B0BD').backgroundColor('#25282F').maxLength(120).onChange((value: string) => this.note = value)
                Button($r('app.string.history_restore')).id('history-restore').width('100%').onClick(() => this.confirmation = 'restore')
                Row({ space: 8 }) {
                  Button($r('app.string.history_save_note')).layoutWeight(1).onClick(() => this.edit(false))
                  Button(this.selected.pinned ? $r('app.string.history_unpin') : $r('app.string.history_pin')).layoutWeight(1).onClick(() => this.edit(false, true))
                }.width('100%')
                Button($r('app.string.history_delete')).enabled(!this.selected.isHead && !this.selected.pinned && this.selected.kind !== 2)
                  .width('100%').onClick(() => this.confirmation = 'delete')
              } else { Text($r('app.string.history_empty')).fontColor('#C5CCD6') }
              Text($r('app.string.history_interval')).fontColor('#C5CCD6')
              Select([{ value: $r('app.string.history_off') }, { value: $r('app.string.history_30s') },
                { value: $r('app.string.history_1m') }, { value: $r('app.string.history_2m') }, { value: $r('app.string.history_5m') }])
                .selected(this.interval).onSelect((index: number) => this.setIntervalChoice(index))
              Text($r('app.string.history_policy')).fontColor('#C5CCD6').fontSize(12)
            }.width('100%')
          }.layoutWeight(1).height('100%')
        }.layoutWeight(1).width('100%')
      }.width('100%').height('100%').padding(18).backgroundColor('#1B1D22')
      if (this.confirmation.length > 0) {
        Column().width('100%').height('100%').backgroundColor('#BB000000').onClick(() => {})
        Column({ space: 16 }) {
          Text($r('app.string.history_confirm_title')).fontSize(20).fontColor('#F4EFE6')
          Text(this.confirmation === 'restart' ? $r('app.string.history_confirm_restart') :
            this.confirmation === 'delete' ? $r('app.string.history_confirm_delete') : $r('app.string.history_confirm_restore')).fontColor('#C5CCD6')
          Row({ space: 12 }) {
            Button($r('app.string.history_cancel')).onClick(() => this.confirmation = '')
            Button($r('app.string.history_confirm')).id('history-confirm').onClick(() => this.confirm())
          }
        }.width('70%').padding(24).backgroundColor('#25282F').borderRadius(16)
      }
    }.width('100%').height('100%')
  }
}

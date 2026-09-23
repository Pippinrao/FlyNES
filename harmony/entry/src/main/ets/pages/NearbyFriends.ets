import { router } from '@kit.ArkUI';
import { NEARBY_TYPE } from '../ui/NearbyTypography';

@Entry
@Component
struct NearbyFriends {
  @State private availableHeight: number = 360;

  @Builder
  roleCard(label: Resource, hint: Resource, id: string, icon: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Text(icon).fontSize(30).fontColor('#FF6B5E')
        Text(label).fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.sectionTitle.size)
          .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').maxLines(2)
        Text(hint).fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.muted.size)
          .fontColor('#BEB8AE').maxLines(2)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start).padding(18)
    }
    .id(id).layoutWeight(1).height('100%')
    .borderRadius(16).border({ width: 1, color: '#805D59' })
    .backgroundColor('#1B1D22').onClick(action)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button('‹', { type: ButtonType.Normal })
          .id('nearby_back').width(48).height(48)
          .fontSize(26).fontColor('#F4EFE6').backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.nearby_back'))
          .onClick(() => { router.back(); })
        Text($r('app.string.nearby_title'))
          .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.pageTitle.size)
          .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').layoutWeight(1)
      }.width('100%').height(48)
      if (this.availableHeight > 270) {
        Text($r('app.string.nearby_entry_headline')).id('nearby_entry_headline')
          .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.paneTitle.size)
          .fontWeight(FontWeight.Medium).fontColor('#F4EFE6').width('100%')
        Text($r('app.string.nearby_entry_subtitle')).id('nearby_entry_subtitle')
          .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.muted.size)
          .fontColor('#BEB8AE').width('100%').maxLines(2)
        Text($r('app.string.nearby_network_auto_hint'))
          .fontFamily('HarmonyOS Sans').fontSize(NEARBY_TYPE.muted.size)
          .fontColor('#BEB8AE').width('100%').maxLines(2)
      }
      Row({ space: 16 }) {
        this.roleCard($r('app.string.nearby_action_create'), $r('app.string.nearby_role_host_hint'),
          'nearby_action_create', '▣', () => {
            void router.pushUrl({ url: 'pages/NearbyPairing', params: { mode: 'create' } });
          })
        this.roleCard($r('app.string.nearby_action_scanQr'), $r('app.string.nearby_role_guest_hint'),
          'nearby_action_scanQr', '▢', () => {
            void router.pushUrl({ url: 'pages/NearbyPairing', params: { mode: 'scan' } });
          })
      }.width('100%').layoutWeight(1)
    }.id('nearby_page').width('100%').height('100%').padding(16)
      .backgroundColor('#121316')
      .onAreaChange((_old: Area, area: Area) => { this.availableHeight = Number(area.height); })
  }
}

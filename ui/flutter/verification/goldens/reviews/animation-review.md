# Bounded animation review — 2026-09-30

24 actual 960x540 component frames; A01 press/release, A10 entrance, A11 switch, A12 removal, A13 progress, A14 notice entrance, A17 reduced-motion switch. Not all A01-A17; no native/device certification, no golden promotion.

All 24 PNGs were opened individually with view_image. A13 three replacement PNGs were reopened individually after palette correction. Independently ran flutter test --no-pub test/product_motion_test.dart test/product_sources_test.dart: 21/21 passed.

## Remaining integration findings (outside the repaired component fixtures)

- **P2** ui/flutter/lib/design_system/product_dialogs.dart:8 — Remaining A17 integration gap: route snapshots durations at construction and paints animation unconditionally. Enabling reduced motion during an existing dialog transition does not force terminal paint. Current fixture only opens with reduced motion already enabled.
- **P2** ui/flutter/lib/features/product/product_hall.dart:73 — Remaining A17 integration gap: category AnimatedContainer (also tile line504) changes duration only when reduced motion turns on mid-animation; no decorative reset or final-paint override as added to ProductSwitch. Not exercised in component-focused mid-transition test.

## Closed visual finding

Explicit progressIndicatorTheme uses approved selected track and accent fill. Reopened all three recaptured A13 PNGs individually; teal removed, stable geometry and 10/50/90 percent stages retained.

## Evidence limits and observations

- A01 distinct frames and reverse endpoint hash pairing now establish painted fill interpolation, not merely configured durations.
- A17 three identical images equal A11-end by hash; expected because fixture uses reduced motion from scene construction. The separate test covers enabling reduced motion mid-transition for switch/progress/notice/rows.
- A11 transition-start thumb changes to target dark color immediately while track still dark; brief low contrast only, complete bright track outline remains. Settled off-state is not captured here.
- No blocking regressions found in the repaired notice pointer/focus/semantics retirement, outgoing-row focus exclusion, source-operation error persistence, or component A17 terminal painting.
- Timing attributed to controlled-clock capture script, not inferred from still images. No image was accepted solely from existence or hash.

## Per-image review and SHA-256

| Image | Time (ms) | Observation | SHA-256 |
|---|---:|---|---|
| A01-press-end.png | 80 | Pressed fill reaches lighter coral; no clipping, scale jump or text movement. | `4e6260c0858a187163a0efaf9887024ae2edee8ae51a4bc1cb9c2fbf62b3d95b` |
| A01-press-middle.png | 40 | Fill visibly lightens partway; label position, button size and corners remain fixed. | `a09c0ebf0b3b9029b93baba0962797964954afc3c4ab5e31db20c362967eb94d` |
| A01-press-start.png | 0 | Coral Continue button begins at resting fill; label and rounded bounds intact. | `6558951138f34d87c59e8d20670a3d7d4bdea5039d2fd12b6beb317929ee59d8` |
| A01-release-end.png | 120 | Resting coral exactly restored; matches press start. | `6558951138f34d87c59e8d20670a3d7d4bdea5039d2fd12b6beb317929ee59d8` |
| A01-release-middle.png | 60 | Fill returns through intermediate coral; stable label and geometry. | `a09c0ebf0b3b9029b93baba0962797964954afc3c4ab5e31db20c362967eb94d` |
| A01-release-start.png | 0 | Pressed lighter coral matches press end; stable geometry. | `4e6260c0858a187163a0efaf9887024ae2edee8ae51a4bc1cb9c2fbf62b3d95b` |
| A10-end.png | 180 | Opaque dark dialog, complete title and explanatory line; no clipping. Fixture has no action buttons, so actions not visually covered. | `c53080d9ba2bf807f82f43c62bba406a8faf9dadae8464a39429296b98f6bb75` |
| A10-middle.png | 90 | Dialog title and body fade/scale in; backdrop Sources is visible through partially transparent dialog as expected for fade. | `55a0b884d522fa0c4ee69e2e227e002cfd3d304f5a5e737d439510b92badd59e` |
| A10-start.png | 0 | Only Sources backdrop visible at zero opacity of entering dialog; no stray dialog content. | `68eab0b6028aeda0dafd9aac807206f3bbc20cd4a46b9bb03a1fdecabbfb089d` |
| A11-end.png | 150 | Thumb right, coral track, complete outline; no clipping. | `a24101d3c9f84224b277d5ec7335138762c868e0f9a3cb2e605acef8d5467d51` |
| A11-middle.png | 75 | Thumb at intermediate horizontal position; track partway to coral; outline continuous. | `32ac55aa0cd9613e3cdcf98901ce23eda4ee014d3a2d11dc68a9a27b315b71a1` |
| A11-start.png | 0 | Toggle starts at left with dark track and bright outline; thumb already target dark color, temporarily low contrast against track. | `68a85fce8360d30df83bd2d4c23a60f0b28ef039b0528b6b006bd56848b24ad5` |
| A12-end.png | 180 | Only retained first row remains; no outgoing text, residual stripe or blank row. | `e810a2a3d7a7043348f9f8bdc60da1fe246dc6ab9c63d11411a7a9b9f777e329` |
| A12-middle.png | 90 | Outgoing second row fades and collapses; temporary clipped corners are the expected SizeTransition crop, no overlap onto first row. | `781f72502eb251c72ee17569b31b56a718f3f25f49fe3e5eb570cf879ca43c30` |
| A12-start.png | 0 | Both full-height rows visible with complete labels; first row stable. | `51ccc829462e918b983ef1057934eabf262b461c744d0afd7b1860a8e8cfbae8` |
| A13-end.png | 120 | Coral fill at 90%; dark selected inactive track, stable line geometry. Teal palette issue closed after individual re-review. | `0026e52171f994db9ca10db7b9113ece109ccf1a7813ff891e7483723c116bb5` |
| A13-middle.png | 60 | Coral fill at 50%; dark selected inactive track, stable line geometry. Teal palette issue closed after individual re-review. | `94444da4b3533c5d28e0242d4a1fd5bb77ea1b2eba30fd01e76aa157ecf6ea99` |
| A13-start.png | 0 | Coral fill at 10%; dark selected inactive track, stable line geometry. Teal palette issue closed after individual re-review. | `33fda83ec3a11d492195a789023711b143c9f16a09c3107703dfacddb24461eb` |
| A14-end.png | 160 | Notice fully readable, complete text, no clipping or overlap. This fixture covers entrance only. | `be5c7231fc6e3811316f19be7e3ff4a81cfc22e6ced097674e62d02864751716` |
| A14-middle.png | 80 | Saved successfully fades into allocated top row; retained text stationary and no overlap. | `6119055177e7d70cf9d55a8f694ac5ab3ff4e87aa8eafc38f8156ed99ed2bb88` |
| A14-start.png | 0 | Notice text invisible at transition start; retained text remains readable and stationary. | `4fc6f2458ea9d4e9f29625360aafd4b48feba15646416b5ce036dee66d0f0d59` |
| A17-end.png | 0 | Same terminal checked image; no delayed movement or fade. | `a24101d3c9f84224b277d5ec7335138762c868e0f9a3cb2e605acef8d5467d51` |
| A17-middle.png | 0 | Same terminal checked image; intentional zero-duration reduced-motion fixture. | `a24101d3c9f84224b277d5ec7335138762c868e0f9a3cb2e605acef8d5467d51` |
| A17-start.png | 0 | Reduced-motion switch is already at terminal checked position and coral fill. | `a24101d3c9f84224b277d5ec7335138762c868e0f9a3cb2e605acef8d5467d51` |



## Additional 24-frame review — 2026-09-30

24 additional frames A02/A03/A06/A07/A08/A09, including route returns; all opened individually. No golden promotion. Still not all A01-A17.

Both previous races closed: explicit choose saves intent before async observation; context reacquisition clears absorbed dirty domains before adoptHost. Reviewed navigation-races-green.log 26/26; no independent rerun this followup.

- **P2** ui/flutter/verification/g2_animation_capture.dart:62 — Missing Chinese subtitle glyphs in all nine A02/A03/A06 frames. G2CJK is loaded but show() applies Roboto without fallback; correct capture fallback and recapture. Not evidence of device font failure.
- **P2** ui/flutter/lib/features/product/product_hall.dart:393 — A03 detail cover/placeholder updates directly while only title crossfades. Start frame mixes B cover with A title. Include cover in 120ms detail crossfade with stable geometry.

- A07/A08 English and Material glyphs readable; no fallback-font invisibility observed.
- A02 selection, A03 title, A06 reveal, routes, and settings sections show meaningful intermediate states. Some endpoint captures still show independent pointer ripple.
- A09 license transition is not covered; only settings section captured.
- Three samples cannot rule out every between-frame flash; sampled routes show no white or unrelated-page flash.
- Earlier A17 integration findings are historical and parent fixes have since been inspected; not reopened here.

| Image | Time (ms) | Observation | SHA-256 |
|---|---:|---|---|
| A02-end.png | 160 | B fully selected, A neutral; bounds stable; pointer ripple independent. Missing Chinese glyphs. | `e4dc52fae2cbf2be8f4126ef97855bfeb59d4eba4d5e2813a7addd5a4b1058ae` |
| A02-middle.png | 80 | Selection border/background between A and B; stable bounds, pointer ripple on B. Missing Chinese glyphs. | `8e0299315fdc931f08de6356a97c0a5ffe96afd5e843c259b2953c1cbbdd178e` |
| A02-start.png | 0 | A selection border at 0ms; B cover already appears beside outgoing A title. Missing Chinese subtitle glyphs. | `ab9ccef30759905e2d500abd217c6297b8d51900b7cecce51e8289113c8984eb` |
| A03-end.png | 120 | B title and cover consistent; no clipping; Chinese subtitle tofu remains. | `92f77ac83f9c8ccc4d45deaaa7419e8743e7b1f0975172833ad6130d52f7665b` |
| A03-middle.png | 60 | Title A/B crossfade visible; B cover remains fully opaque; Chinese subtitle tofu. | `a588872dbad9bafac984decc41a89ae6b0d02195b310e89ce9967fddcd433a90` |
| A03-start.png | 0 | B cover placeholder fully painted while title still says A: missing cover crossfade. Chinese subtitle tofu. | `ab9ccef30759905e2d500abd217c6297b8d51900b7cecce51e8289113c8984eb` |
| A06-end.png | 160 | Field, caret, clear/close fully visible; library fits remaining height; subtitle tofu. | `1adb921c1b7d7829318618ba1316de48d7f434e9d248cd59a104a9c1252cc42c` |
| A06-middle.png | 80 | Search height and opacity partially revealed; intentional crop of field, no library overlap; subtitle tofu. | `ece27bc9871b07b9764ee08191642e567f27ff50aa181dd65c5019b0a268e4b8` |
| A06-start.png | 0 | Zero-height search; hall intact; Chinese subtitle tofu remains. | `e4dc52fae2cbf2be8f4126ef97855bfeb59d4eba4d5e2813a7addd5a4b1058ae` |
| A07-end.png | 220 | Opaque settings, five sections readable, no old hall residue. | `5bd2c2b79eaffd221fb605cc2790c05c0e607b534c2ba987cf9da085a54bc577` |
| A07-middle.png | 110 | Settings fading/translating over hall; expected transparency overlap, no scale or white flash. | `f83701eca7f3f8f3c4d605fc021d9573357e6bdba9e84ba1d3d19a75e7ca7bbc` |
| A07-return-end.png | 180 | Same hall selection/geometry restored, no settings residue. | `369ed39e7b110b0852903af5783394cfb4dfebb3d46ac4f66d611a186bb92d94` |
| A07-return-middle.png | 90 | Settings fading/translating over same hall; no unrelated page/white flash. | `057783f9f8e2a3cde5c88397d3ed1e932267ee8857b690cacf008b25846df731` |
| A07-return-start.png | 0 | Complete settings retained as return starts. | `5bd2c2b79eaffd221fb605cc2790c05c0e607b534c2ba987cf9da085a54bc577` |
| A07-start.png | 0 | Original hall intact; English/icons readable, no blank frame. | `369ed39e7b110b0852903af5783394cfb4dfebb3d46ac4f66d611a186bb92d94` |
| A08-end.png | 220 | Opaque Sources; explanation and both add actions complete; empty list supplied by fixture. | `ea28ac0433b5b894988b71a7a22ce49c15654a161a9de3fa9bd7e27b2d7ad60d` |
| A08-middle.png | 110 | Sources fades/translates over hall, no scale; English/actions/icons readable. | `907e89c32a5093b7e7d51d306a5e56052f7a5ac0447b91e06d93c96567d6f43b` |
| A08-return-end.png | 180 | Same hall selection/geometry restored, no Sources residue. | `369ed39e7b110b0852903af5783394cfb4dfebb3d46ac4f66d611a186bb92d94` |
| A08-return-middle.png | 90 | Sources fades/translates over same hall; no unrelated page/white flash. | `76fab754add0b43065ee708ede941922a5fe8b9c0895c8079b27976b2bd425d8` |
| A08-return-start.png | 0 | Complete Sources retained as return starts. | `ea28ac0433b5b894988b71a7a22ce49c15654a161a9de3fa9bd7e27b2d7ad60d` |
| A08-start.png | 0 | Original hall intact, no blank frame. | `369ed39e7b110b0852903af5783394cfb4dfebb3d46ac4f66d611a186bb92d94` |
| A09-end.png | 120 | Only Sound/Audio focus fields remain; no clipping; pointer ripple independent of content fade. | `5d465bab0f09290d7a5d904dd5ee1c55bffae72ac2006dcae6c78536b1c25374` |
| A09-middle.png | 60 | Display/audio fields crossfade at same origin; navigation/divider fixed. | `7948ad6ff25c8f5ab7676aa151a41a880688048a850716758ada16f3b8186aa3` |
| A09-start.png | 0 | Audio destination selected, outgoing display fields retained; navigation fixed. | `9cf4347c805f2c4b28a36d6edae21f68ab1d44a723de816c5aaed52fab4cf3f3` |



## Current recapture: 15 frames reviewed

15 frames independently reopened after full current capture: changed A02/A03/A06 and new A04/A05. No product edits, builds, device actions, or golden promotion.

Both earlier capture findings closed: CJK subtitle glyphs render and detail cover/placeholder participates in 120ms fade. A04 decode fade and A05 category/result frames show meaningful intermediate states.

Older report sections remain historical. New current entries replace changed frame hashes and preserve previous SHA256. This is bounded animation evidence, not all A01-A17 certification.

| Image | Time (ms) | Observation | SHA-256 |
|---|---:|---|---|
| A04-start.png | 0 | start frame: Decoded synthetic cover fades over title placeholder from 0 to full opacity in 120ms; retained 2:1 aspect with vertical letterboxing inside fixed 320x200 footprint. No geometry jump. | 9b98f816d3980c768441cd3212e2b73d9979c33700edb327667468f5850fd3ee |
| A04-middle.png | 60 | middle frame: Decoded synthetic cover fades over title placeholder from 0 to full opacity in 120ms; retained 2:1 aspect with vertical letterboxing inside fixed 320x200 footprint. No geometry jump. | 230b0e30057104c42cbc02b13e099d5b63746b1ee5818fbd59fa3c1f6d23005c |
| A04-end.png | 120 | end frame: Decoded synthetic cover fades over title placeholder from 0 to full opacity in 120ms; retained 2:1 aspect with vertical letterboxing inside fixed 320x200 footprint. No geometry jump. | 2b973f43c41c5bf514b270dacb537a15a197423819d7cadefc1187646b6ff727 |
| A02-start.png | 0 | start frame: A-to-B selection border/background transitions with stable card bounds; Chinese subtitle now readable. Pointer ripple is independent. | bec255752e63da2ec4769dc551f2e4686bf004933872f283d4d3375a0636c3ac |
| A03-start.png | 0 | start frame: Cover placeholder and title now retain A at start, fade through intermediate state, and finish B at 120ms with fixed geometry; Chinese subtitle readable. Previous two findings closed. | bec255752e63da2ec4769dc551f2e4686bf004933872f283d4d3375a0636c3ac |
| A03-middle.png | 60 | middle frame: Cover placeholder and title now retain A at start, fade through intermediate state, and finish B at 120ms with fixed geometry; Chinese subtitle readable. Previous two findings closed. | 32b35db261d0492f9135f3dcb3bc50181de6cd84b07ee2c3c010fe64fd9a06df |
| A02-middle.png | 80 | middle frame: A-to-B selection border/background transitions with stable card bounds; Chinese subtitle now readable. Pointer ripple is independent. | 8695c2ccce3e53cd2869a6268734f1d1aa0eb88c3dc0a870f6f461e7d274f305 |
| A03-end.png | 120 | end frame: Cover placeholder and title now retain A at start, fade through intermediate state, and finish B at 120ms with fixed geometry; Chinese subtitle readable. Previous two findings closed. | 3bab3fe98f473ebc4b2f1cbb858f7f7005c9956af109fe678a816c02e5f126e7 |
| A02-end.png | 160 | end frame: A-to-B selection border/background transitions with stable card bounds; Chinese subtitle now readable. Pointer ripple is independent. | 7df91e9143ccf947a544e9aae63563dc98883595f70cd638ba93afa0e6f82c86 |
| A05-start.png | 0 | start frame: Category indicator transitions All-to-Favorites while results fade into fixed grid; start grid is transparent, intermediate partially visible, end opaque. No whole-page slide; this fixture does not certify multiplayer filter separately. | 2c5bdda73326b6df5a8ea820b9a0fd4bc064598fd944521cdb359ae1024d94ad |
| A05-middle.png | 75 | middle frame: Category indicator transitions All-to-Favorites while results fade into fixed grid; start grid is transparent, intermediate partially visible, end opaque. No whole-page slide; this fixture does not certify multiplayer filter separately. | 9a34afe7fd43685fd5ec9fec6b26dec45fd774c0f9a2bd3d2378f724b38695c2 |
| A05-end.png | 150 | end frame: Category indicator transitions All-to-Favorites while results fade into fixed grid; start grid is transparent, intermediate partially visible, end opaque. No whole-page slide; this fixture does not certify multiplayer filter separately. | 4665f48074c4f2a57a43c957f61101834dfce3f259e79397d850549c8ce29278 |
| A06-start.png | 0 | start frame: Search height/opacity reveal starts hidden, midpoint crops field within expanding viewport, endpoint shows complete field/caret/clear/close. Chinese subtitle readable; library remains bounded. | 4665f48074c4f2a57a43c957f61101834dfce3f259e79397d850549c8ce29278 |
| A06-middle.png | 80 | middle frame: Search height/opacity reveal starts hidden, midpoint crops field within expanding viewport, endpoint shows complete field/caret/clear/close. Chinese subtitle readable; library remains bounded. | 67540a8971d85c4a2d93fa7f55accff75ac310405ddca90c03d572fcf7314475 |
| A06-end.png | 160 | end frame: Search height/opacity reveal starts hidden, midpoint crops field within expanding viewport, endpoint shows complete field/caret/clear/close. Chinese subtitle readable; library remains bounded. | 411a09e54f637cddc0052493f41e6fb2c018d679e599345ce4fde429f14f9844 |

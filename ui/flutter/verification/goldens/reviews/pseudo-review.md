# Independent pseudolocalization review

18/18 current PNGs reviewed; PSEUDO01 and PSEUDO02 resolved. One changed hall PNG reopened; 17 byte-identical image reviews retained.

## Resolved findings

- **PSEUDO01**: Both native bootstraps now expose raw localePreference; ProductController prefers it over resolved locale. Adapter-shaped en-XA/system regression covers the prior mismatch. Explicit locales and kDebugMode-only pseudo gating remain intact.
- **PSEUDO02**: Reopened corrected 200% hall PNG: both title lines fit, Favorite visible semantic height is 48 px, primary remains 88 px. In short large-text layouts categories use a horizontal strip with fixed tools; all four category controls remain in the scrollable strip. This is an acceptable compact-layout adaptation.

No product edits, builds, devices or golden promotion. Native activation was checked by source and adapter-shaped test inspection, not live OS execution. Normal-matrix follow-up remains separate.

## Evidence

| Manifest ID | Status | PNG SHA-256 | Geometry SHA-256 | Semantics SHA-256 |
|---|---|---|---|---|
| hall-800x360-en-XA-100 | reviewed | `e2d6ad8bb35a252e69b8fbd2d92732949362deb6d04bbdd238b5bd6c95ef2769` | `edc73127e40a6cde115bcd79bef5727fed597fbc75fce46a97c55cacf619cf4b` | `45efcff17abf69a65c373d006750bf29f722000360db33af6ae3a0dd8000d816` |
| search-800x360-en-XA-100 | reviewed | `4f7e8d918b9cb6eac676b962987ddb2eedfa78f84a57610ef28d4dd23cc40e0a` | `fd8dc8ec7760315fe2a292e25c51c3e2206627e67b7e8e673e35371f82337b19` | `6796ae0d62dc2611f708c251be8882384f7384d53f803a2339ec1d8028adc8e5` |
| sources-800x360-en-XA-100 | reviewed | `462f4f0c6f985567b1294cd17f0c1c144dbbc8053df45c32e6072a38f9a23c59` | `23cc437649e56cf1535988d0984ac9f610976d1b35955e01841265dde2b39843` | `1dea7c08e1b3a1b4a02ec14651a286858757c22482c8b3980a348ae04996d6ff` |
| display-800x360-en-XA-100 | reviewed | `0df533a2660c41080b9a608fdaddf109ba7159cba741b4689e17b95a0548f2b9` | `f59e1ace0c9e04b1c9c217b086b9c61202d98f2345bd1dbfabe2f631d3212396` | `5d2c73b4764bfc2bff9c3085ea6fb4aebb1dcca44ded3c8e1f809203660bce77` |
| controls-800x360-en-XA-100 | reviewed | `daef1d1e19e8cec37137ab44753fe8128350e36207b414f5e0a8502f7861d961` | `dde8d1673dc4e886d2899ca532b59dbd85e874cc7b24235157ecfb0bae14f07a` | `60130aa5d172dd1d7e4ac579fc97497dfe55ee58df957c3da84884dd83a2ea72` |
| audio-800x360-en-XA-100 | reviewed | `109a15666a57aa719b9eda6c4e60fb738c64b1ef1e3216f77417f4459d5765b2` | `66ca7d019946964bb11147b410b87a4f00d911635c64d9afaae0720238152729` | `b4ce9f7ceacc9a918a263ef34d33a6dc301255b248481b3ebcab1c3afe2d61f8` |
| game-800x360-en-XA-100 | reviewed | `42798b601bf7a3c8c7691eafce5387050ec54dc377848a3cbed5d8ad2f053471` | `5bd7838e075fb96daec4d1ae8c290b07159a12f76225422d1ca65a1b12b06115` | `35a70283543e5f304d918e491f25cf5fe70b36036042d82a3cd0b16f759e625e` |
| about-800x360-en-XA-100 | reviewed | `bccc7d870fc9e49becf50495d712b1ba9165aa0ed3a6817b2240075c667ad5a0` | `7cd63eb00aadb9aca985bd96456f6dae40e6bba02c3e4fe289d71b197757b7d1` | `282e93ed635664a6399ba9d70c3b052ec6bca6a57a192137707ff05d34a3e9bb` |
| licenses-800x360-en-XA-100 | reviewed | `0d9dd30e48a4701abbd0f4a5a94a7d92ed6f543154fb2e33a91c7ce1c65e4f9a` | `8b5ef18a0def93b11a0056936b9e499cdfd9a50cae6bc69bce996486f14f6b73` | `6db6d49482c03dfd3e56c60898d007b4251d3a6d569a62f4d0b2ef7ed0474ec9` |
| hall-800x360-en-XA-200 | reviewed | `47ada8608e47a5eacd8bf00a2b9bf8bd38696ef10f583d6acfce8f0c4d3cd088` | `1476741cfa0a940147c546897247838b9120968e96e4dea709cffce97413fe87` | `aa066f08e668bc8218402b79a18a4526cb80025e11b4f8acc5acc69bcd110905` |
| search-800x360-en-XA-200 | reviewed | `97120c102073792afb4b95d2da47df4fee77a3c9b0f42bb30b3a8fbf031a1744` | `62a5bfebcebb91af284568c9709a5e553c5dd4286b4c73fe83d5ae77208b856a` | `5caf95a9ebf578bfb2d412af86271b872245dda79f6302b926b75b2ec302de19` |
| sources-800x360-en-XA-200 | reviewed | `a851b26cf1f3ed239605c680ec225f69f6e1f20fafbd5ce0aa544e558abff752` | `7afc93815e109bc730095fe73fc28bf286cf6810b59683acb56e0ac71bf5c72c` | `d403ea5f9a39cbdbd918bb08818d4f690731e1e89b018b4a5ebc40a29c9d4db6` |
| display-800x360-en-XA-200 | reviewed | `1cfa427126fa54fe997d5e9e3e652a12d2adfd607957bb6097595bb086518ba6` | `d0cf193e89f7386bae0d44f28d4e5c363e432344c0023ff3594545ffa7c51ba9` | `b0d0f39273a7184de45dba8849bcf068f17d5602974e59918e231c03ec04ccf8` |
| controls-800x360-en-XA-200 | reviewed | `9c7cc0ed289511f42c9374c1b8159fe279c76ba66bc6df7409275f42680325d2` | `3fcc856477b859cf8399a5086410cb0fcc96bfa36623b9f64c3b1d6ae2487a62` | `89c14733d6f466a5859bc9139d5c112d3adee8f12602acc9ec1ff9ed88a1b5fb` |
| audio-800x360-en-XA-200 | reviewed | `bef257b9e746a1fce77d13619e7685f71ebc96f1fe5ccded9d3253321790e76b` | `5bddb065448dd6d8fbcd05a4132752676e13730129bcd858b90397d70f84da09` | `7c7b18911225ddc39af30708afbe9751bc7541f278b6096937a7be731990660d` |
| game-800x360-en-XA-200 | reviewed | `666a01ff6f7ad03b598beb5fe40d0b7b5465803bffcab75ceeeca57af7b69a80` | `764a443b6d7158b33b9966693c9b43de6356e31cfb504bcb8dccded8fb2a2676` | `ac472c943ed8e96108abf614dcc39405d5354dcb78038d54fff74d58d313fd31` |
| about-800x360-en-XA-200 | reviewed | `19a7498502722db87f5d9e755e298d71e7f73343094edc4bd2bc14664f366d05` | `e2adf40c723abdf8bfc187cb141203cb51474d1802771b6aa0f48a81b9fdef7b` | `2d06820f765a7705562d17532c63fb1246e5d850ac1a4998c273b9cbe3bcfacc` |
| licenses-800x360-en-XA-200 | reviewed | `6b795b8478748a83d05e7cf4bf3263a21049df7fe74b875235178b2055556fb5` | `3b6a6588cf16a2425961e2b4c55b7257ffc8b4f0dd68cc9e1bbf7a3be7a83218` | `bf58283d766082f75dba307c7f7471bfe2cab70725d2a1f29fb05c44cc37d29a` |

## Semantics-only recapture review

2026-09-29T20:10:10.601502+00:00: all 18 PNG and geometry hashes remain byte-identical; all 18 normalized semantic hashes match the prior review. Current raw semantic hashes updated above; prior hashes retained in the JSON audit. No golden promotion.

## Post-W5 recapture closure

2026-09-29T20:30:34.759653+00:00: all 18 current entries bound to current hashes. Sixteen remain byte-identical visually/geometrically with identical full normalized semantics; controls at100/200 match the separately opened U16/U22 summary delta. Expected semantic text verified for all18. Prior hashes retained in JSON; no golden promotion.

# G2 state capture independent review

42 reviewed; 0 needs fix. V01–V04 resolved in the current recapture.

Reviewed UTC: 2026-09-29T19:04:01.669099+00:00

22 changed PNGs reopened individually; 20 prior PNG reviews carried forward only after byte-identical comparison. All 42 expected-text sets and recorded button targets revalidated. PNG, geometry and semantic hashes below bind this review to the current evidence. Prior hashes and findings are retained in state-review.json.

No product edits, builds, device actions or golden promotion. This review does not certify native behavior, pseudolocalization, animation trajectories or full G2 completion.

## Resolved findings

- **V01**: Both failed-read captures now present Library unavailable with Retry and no assertion of an empty library.
- **V02**: Recovered Start has coral enabled fill and enabled/tap semantics; callback-derived disabled state and keyed tween reset prevent the observed stale fill.
- **V03**: All six captured active phases disable Scan in paint and semantics. Source code also includes ingesting; observation remains enabled.
- **V04**: A fixed 8 px gap separates summary/ellipsis from Two-player. Narrow safe-area state and all 24 hall/search matrix PNGs reopened.

## Missing states in this 42-capture set

- **M01**: This set does not demonstrate a successfully decoded cover versus a failed-cover fallback, a visible search input/clear/close state, or populated search results. The hall-search state renders empty results with the search input closed.
- **M02**: No builtin-source protected row, completed cancellation, failed targeted reauthorization with the original row retained, failed removal with the row retained, or successful removal/addition result is pictured. Picker cancellation and removal confirmation are present.
- **M03**: No expanded custom-axis chooser, audio-focus chooser, reset completion result, applied language-change result, or About version/build/absent-link state is included. The locked preset, reset confirmation, failed audio write and language chooser are present.
- **M04**: No long license scroll position, narrow-window dialog, keyboard-visible/back-order state, or terminal read-retry recovery for every failure family is included. Wide dialogs and short license text are readable.
- **M05**: These are individual state captures; they do not establish start/middle/end animation timing, interruption handling, success-message lifetime, or reduced-motion behavior.

## Evidence hashes

| State | Status | PNG SHA-256 | Geometry SHA-256 | Semantics SHA-256 |
|---|---|---|---|---|
| startup-loading | reviewed | `5085a8850c1dd96deebd0c30e486dfe079973edb0c417e68da5ce2ff8024f61f` | `3a5b5120adaaee59600e5f6c50598d25a527ef320a1297e7281ababfe6df4886` | `f330208d7af80ead4f2171a228553f301404722afcf650364e716aa899e0d260` |
| startup-error | reviewed | `a23d7a79591b57e50c65a4d8fa9b491ec71a3d51bbdd4080fd40b80f2c310bbc` | `fc5fc685e3b84f6b8a59a83007eba9c03d23983452235a72be61d318de700ba5` | `a9070f61e4cedb7d030e415c0ef086d28676a034085e2df54338bf63c90c3fe2` |
| startup-retry-success | reviewed | `619482bc7e6c4108d8be1e24681da97fd21dd992637247331d17b36a9fd8e942` | `be7a28fe318756f493396d0aace33c335b3d90f6e7c6fbb49d0992110ff2d159` | `fedb9ed3747450dc943d7521f37effd1ec906cf1a1b78ee38b96ab6d7f9fe242` |
| head-none | reviewed | `619482bc7e6c4108d8be1e24681da97fd21dd992637247331d17b36a9fd8e942` | `be7a28fe318756f493396d0aace33c335b3d90f6e7c6fbb49d0992110ff2d159` | `3d6df3472b4f8a9aefb2829b17533ad83c98db6064472be2b8269a991aecd91d` |
| head-available | reviewed | `59f3a0bed6a3da4bc2127d024c85b65c40dd43ca0c882fcaae340c3c8d75bf6b` | `be7a28fe318756f493396d0aace33c335b3d90f6e7c6fbb49d0992110ff2d159` | `48356d11af3242c2562fa5b29cc8789212ecc13210d501eb796790c630c312fe` |
| head-querying | reviewed | `61437dc97200555bb14c9479b5fd5769c5720d6dc0bfb4f7b6ff0cb28347d519` | `be7a28fe318756f493396d0aace33c335b3d90f6e7c6fbb49d0992110ff2d159` | `953a45e8faaae2120c64f1405ea40bf65ecc724d1393ecec1a55785bcc9bd9ab` |
| head-unavailable | reviewed | `716009ae06d7936b5a5e37b3e8b9d074b00e82e6454664e6622a8bc1efdc2f30` | `e692622b3579bae359670d7cfdff2968b06890b371ad8ddfcc4ada2bdc18ad12` | `4d33ddb34203c3aaceba3fb87e6fa202bf774a3f666a9ad7b7a8bc4c6d839c76` |
| head-source-unavailable | reviewed | `7a65b143a883bba17edc26af0e4459a07e7138b558dbda4cad67400be6a9749b` | `0e12be71993f781a80a31de79cea4f947a51554ed5bb578fdaace422784b193a` | `6c4383092cf8189833a044c4da9b5a831c8f2fca42e0cf191b6f4f1956d2900c` |
| head-nearby | reviewed | `62905b03ae3dd5d8b2c2d484f958e00931cee77507d8ea5cab989ebd0d2d5b1a` | `be7a28fe318756f493396d0aace33c335b3d90f6e7c6fbb49d0992110ff2d159` | `48d44cdeeb050b78783210a8217882e7c944c61f623d9b44760ffba9c983a0f4` |
| hall-recent | reviewed | `c81ba86ed57d37dec49d5770b28097608e77fd0d7660fca7af02d61238d63bd8` | `04978864cdeb4d2af8d4674a206b56f9fb0edb5d4a2091f706bfda71a81ff252` | `12fe1ccc78bd01ac1a1cbb821ad860b0254ab116c1c5c58b970c6e6230ef18be` |
| hall-favorites | reviewed | `3653dc4e5f8b20166061055280ba5d889ffbcd359e3e771e809acf74b5a6a282` | `4f0fa16629a3ecb6b6109bd5a2f3cc46507d2990aee2015e4bd9cbcfda707172` | `6ea433de930d58b600a01debeadf73656c98bf3a1349aac894e02f5ba9b0e276` |
| hall-search | reviewed | `37071b9ecab0bcc106f2cf1a657663c8e146f8451ceaba612c9746b56720e728` | `a9c205256d38cac22598140d83ad80ee6facfd3e27af4212ed1769703bf949bb` | `5fa97d8a6faf703c390178de03b21888f70aa1c130ea57c9f13a953648a668a7` |
| hall-two-player | reviewed | `e670a323f7a516489d31c33158b11a4fa43b9fc1ad34b6a91b01b1b60f05cea5` | `b6980910f0fd526f478ab3a44cd088c2fa568d4773a325939d1bc0543e08bfd9` | `178047c6bcf046a012b4e39260d6a126fcde13fe751bd42b81a63c39671f916b` |
| hall-all | reviewed | `145d0e2b4d92d1f111ff98e73c985d39e167a02069a52c3b5266e8de95ebc720` | `9c48db515b1d7329231d5ef17ac2f47a9db6d6f66702ff739806e1faf38d6581` | `4fb7ab1a52d3641a2fff274de7aa9a212e4d4bb986075faa44d46e2cd3ad69e2` |
| hall-catalog-failure | reviewed | `a23d7a79591b57e50c65a4d8fa9b491ec71a3d51bbdd4080fd40b80f2c310bbc` | `fc5fc685e3b84f6b8a59a83007eba9c03d23983452235a72be61d318de700ba5` | `ee89bf9ec9809b535bde49558f2777af57e88a08520fea1f09a516a4aa07928e` |
| source-queued | reviewed | `f27ff05faee3ebd3795caaf1223f5616fbd650292de34a8ddcc69f4c0d1bebd7` | `279bb7aafd3fe327afc196026b33607bc56b8dfe3698e4166fb3d0418a3133cf` | `e00dfe89587c0f5d534feb4e2b87a09d878b54edba964851641e0a7aa41c4c80` |
| source-enumerating | reviewed | `5546e8ea9884b733394b210ecad09347bdb1ce7dcf638956d20ce7852c8d9715` | `309cf00715a2226188cb5e1a9c2afb42a3ec07fac60549f2bf9d137334c5a609` | `bf817ef73d205a9f0ef0a24facb4fc7c277ec13fa15ecdb02651a8c61cd92f57` |
| source-scanning-known | reviewed | `79f9401da7d7a9ac2391c126180b47fd5914c918654e20c1b116e9b6e0ce3ba8` | `ab824e2b60463ed82eab71bb5e00c3de9eadfbf04345964aa419f97e9fa6abe1` | `0a712a0958eb08283b2b2875a9f6094299949878af7226fe3d7bce6dcbf8ec0d` |
| source-scanning-unknown | reviewed | `6465a0ba29e6512b05cd18c8595a85fd23d22ca925729f523f66e7dac9af2536` | `309cf00715a2226188cb5e1a9c2afb42a3ec07fac60549f2bf9d137334c5a609` | `17206e54d955567682baf32870ef7b8fd611e3c5f61099a7248c2c86554f1853` |
| source-cancelling | reviewed | `707a736b43eb92402a6e7dc68354e53879ffaab72aea0e74d6034fac23e5e722` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `9c49be8a1adace1c96589b4a62d2ce61b4de268a9a3e32e5872f4b5a4fc6c1c6` |
| source-committing | reviewed | `bf4e8118ec2cce5a501f5e9bf3bc691a5eae829aa93e82908353a452ff0ae0b9` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `f6fc4625f0b5650a046eb64bac95920f3ae468ddd663c2c7e5e8dbbf72187dbe` |
| source-completed | reviewed | `f14ae06a7d01fbe4a4415d86545327da7cdb69975d073b68497ff2b1a5b1b9cf` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `efc0dfc9dd444b5314fc7351c9f076e1e7a6714f138e1d231f09dcb7df6f2389` |
| source-partial | reviewed | `efccbcda5fd81e9b9e1c15b3d77b7912c45c6f26267324cd6bdeb82c1b377d18` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `be2c7c698fc3bb82a55973a9b2612d21314d27fcd97b23b757afaedd4d486b7a` |
| source-failed | reviewed | `f3d2e71c0f57b06cd0200c959cba97ec9fbd3444067f960e449e03bdaa08a449` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `31b8deb1725461c7f0ced61d143502d75df2b89da86fe92c15dc42fe9f53b6f7` |
| source-permission-lost | reviewed | `393b5d6261e1336b06f7d753582668b3979711f5f681e82fc852ae0cd878431c` | `33e625a77102ccfbc8d43d589290e81fbe0b472cf11e8aa01a64d346277481ef` | `6aa7e62e99ba261822a49958eaa6ceb058b9fa0155dc31f72e88f4c1bfcfa5d7` |
| source-committed-refresh-failure | reviewed | `01b0d0feb81add634cb8a0401d5819418273c98635a8bd0811533be002f2d8d6` | `d413f30bd9e600ba96567453fef365dd025fc7ed529a58de3e3790d532b7d6a2` | `0c1b621d9047d6cd6f16ad26695807c0e77524f8778ffca366ed610486ef0ec6` |
| source-remove-confirm | reviewed | `d2012387eaaa79fa07d6b3b125beb8880fd0598fd807af4d9b2be7e901d76be3` | `0f90c904fdb23489bd699337827dc0da262a698a3c875acf3a8267a657027974` | `899bfae3e881d8512594654b2b46750d81ae18185394cb42c5ad823d454801a2` |
| source-picker-cancelled | reviewed | `f14ae06a7d01fbe4a4415d86545327da7cdb69975d073b68497ff2b1a5b1b9cf` | `8c3b47ff866ccf9d83a75ced61db8d78905f701c9f5cfef5bc23b67e4674843e` | `efc0dfc9dd444b5314fc7351c9f076e1e7a6714f138e1d231f09dcb7df6f2389` |
| settings-custom-axes | reviewed | `4bf944f949de6a7ba775eaa4c95f6b0d31cc2c791aa56f91bf437481cbcce29d` | `ebd7ea6fa89fb353892a3a43434af645f253b5d2c0c184ab351704d507becfc9` | `9e859852f6da16cfc37d87aa783fae51267d2b1fe8eaad587145b80eaba1ba29` |
| settings-locked-option | reviewed | `2dbb2a33cf1849087a695a80fb350f8949cfffc2c80d2d4f5cf5d39b914ad507` | `b3aa56914b813fe7726a17fd6bac9afe9ba572c9dccbdf4a47562ee8da565eb3` | `b3e2205046526403c4ba8a0a7b723bf64ddab5e5dd9507b59a13b4946045de5f` |
| controls-bottom | reviewed | `a8126668d364a6fb7f97c232d5d3196382ab2348afcf34059390de71733cdeca` | `4362e6b201e31c01222e0a1821e22f185fe9f727c4b0775dbe2231fbcbe9fcab` | `d635bebdd95540a0764f5f32419cc37b7cb05259cbb7c9c82643d3490d2a875c` |
| controls-reset-confirm | reviewed | `36573c753d093134c0203b0b74f9360637b67e34dc88685cbd4475d57628314e` | `596d909f9c7676cefb0a44d2b98678d2555df9c5f8cff86b80d4a89b7e8309c2` | `61209562c7bec8d02a0f91534493dcfd054e9992a687f17ac96ee65570ee7dcb` |
| audio-write-failure | reviewed | `1e2adce4c6cb1e9ee258903908583b66bff6a1a866624d26c00b03f9e6fee318` | `40f7dc3ceb13e988003946aa4e36459d805b8e2df83865e78e143e0ca652576a` | `c563a78f9354375af6462df4356a89a80d5496d2ace8a789e3d75b1e5cd04817` |
| locale-chooser | reviewed | `abf8dc030a89ab99b462ebb56d032c3aaf1229ce4ff605874302789385e35308` | `7fdc4f34104a16f34d910a64e41c36d63d7bebe4477b467d05bb3bdde813df49` | `c5700fd520ee210a42d2efa46d39c91abe943877b345385550124ea793367e4c` |
| license-read-failure | reviewed | `94bab0277abc9634113c39f291c62c272827cfaf562b59f6d5dd7f5ec998100b` | `024b648517a834cd264225057a724250cb9069864974227c478822cac7528014` | `499e35a02e82fed5d132179cdbb19532889cac1d805478cff6d8789ff1536498` |
| license-copy-confirmation | reviewed | `8ad1fa15eb85eeafe6355ff217472e9527334ee74afbd064087dbd47b1efee11` | `ee399fc59395777bb4ff209d93a903f40a42e881ed5a739d35d27dc2403b142e` | `5e554729cabded0ea5a5f465474f865f714149bdde3ac6d21c0d028a2681ae22` |
| narrow-safe-settings-list | reviewed | `0129fe988b500d707dfb54f25e209b969c5a8361712ba20a55d379d89cb53572` | `e0064886b076358aa8c22a78d853fba49c90518f046042be3761f4a56ad9f62e` | `b75dee870228c7afbcf9730a4e43e57fcabaa45f9c4a21dcdc4dd0fae248a94f` |
| narrow-safe-settings-detail | reviewed | `a295d98864d75c677ba7a0be4feddc4a7d6780259af57a0c780a9f3c1a432d63` | `d39a52a630edb73e8f522c56fca3de1b92ca1e59cd269809df7425a1e9bc1234` | `aadb7768c8372d81c68b254eab6e1afeb0d09dc439678fa59075426ab2fba1bb` |
| narrow-safe-licenses-list | reviewed | `faf0682833643e43a61bfb48653857e42880e7efd231b8deac14b5546836edde` | `84df4188ac06daada507a6f068cd2716a7d4af03a65e0115be6afdc22f4297f5` | `b4042f05111f5b38e9ec4f921d0a6cf941ac39e8eb1d598e5fc3b2892c8ba594` |
| narrow-safe-licenses-detail | reviewed | `38428fc53840c1b871d5e08c078b894cb1cc20b4eb4cbd782d40168780f5eb99` | `99eec1533a961f331d623345ba09571663e962d4e348f181c01ba971e5a00f5b` | `c307bb53e73895bc48f26cb6cc482da13c07f0de3c339ddbdfd3f3679cdf0d84` |
| narrow-safe-sources | reviewed | `f6db9d5a69ff0a2d2f4c39edb43f3a5ae205f843d9b0713fca369f2b16a68f7c` | `c98ea83611dee5ca5fd781136ee48733621e45fc5c697a091d630940691be821` | `4b239819402962d790473ac760284e3bc30402cb4a92de5cb2f1a2dbc0b6d6e7` |
| narrow-safe-hall | reviewed | `7a8bfbf2979018dd48829d65b977704cd6bd52c6c2fb4cc56f193c142391827c` | `61ef94f3745be757b9d7b4663d26f3345e13f4faa95b01c58a3d9e1b3f1dd5d7` | `8fcaaee35137ea71840186e9016077d71aaa7469bf8e0501c44fa5bf39bfcbb6` |

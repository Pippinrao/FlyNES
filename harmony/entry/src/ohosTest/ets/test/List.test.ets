import productProcessRetentionTest from './ProductProcessRetention.test';
import productHistoryReturnTest from './ProductHistoryReturn.test';
import productSourceObservationTest from './ProductSourceObservation.test';
import productSourceFixtureTest from './ProductSourceFixture.test';
import productTransitionRecordingTest from './ProductTransitionRecording.test';
import productTransitionFramesTest from './ProductTransitionFrames.test';
import productRenderObservationTest from './ProductRenderObservation.test';
import saveHistoryPlayTest from './SaveHistoryPlay.test';
import productG2Test, { productG2FaultTest } from './ProductG2.test';
import g1NativeSavePerformanceTest from './G1NativeSavePerformance.test';
import g1StartupObservationTest from './G1StartupObservation.test';
import g1MemoryRoundTripsTest from './G1MemoryRoundTrips.test';
import saveHistoryUpgradeTest from './SaveHistoryUpgrade.test';
import flutterFoundationTest from './FlutterFoundation.test';
import flutterTextureProbeTest from './FlutterTextureProbe.test';
import saveHistoryUiTest from './SaveHistoryUi.test';
import smokeTest from './Smoke.test';
import saveHistoryTest from './SaveHistory.test';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import controlLayoutWarningsTest from './ControlLayoutWarnings.test';
import licenseModelTest from './LicenseModel.test';
import pauseParamsTest from './PauseParams.test';
import settingsHelpersTest from './SettingsHelpers.test';
import checkpointStoreTest from './CheckpointStore.test';
import catalogProductServiceTest from './CatalogProductService.test';
import nearbyServiceTest from './NearbyService.test';
import nearbyUxRestorationTest from './NearbyUxRestoration.test';
import nearbyMvpScanFlowTest from './NearbyMvpScanFlow.test';
import nearbyMvpCrossAppTest from './NearbyMvpCrossApp.test';
import nearbyMvpExternalHostTest from './NearbyMvpExternalHost.test';
import nearbyMvpProductPlayTest from './NearbyMvpProductPlay.test';
import nearbyMvpHostTest from './NearbyMvpHost.test';
import nearbyMvpHostFlowTest from './NearbyMvpHostFlow.test';
import nearbyLanNetworkTest from './NearbyLanNetwork.test';
import nearbyWifiConnectorTest from './NearbyWifiConnector.test';
import nearbyScanJoinServiceTest from './NearbyScanJoinService.test';
import builtinPlaySmokeTest from './BuiltinPlaySmoke.test';
import builtinGameplayAcceptanceTest from './BuiltinGameplayAcceptance.test';

export default function testsuite() {
  if (abilityDelegatorRegistry.getArguments().parameters['-s productRetentionPhase'] !== undefined) {
    productProcessRetentionTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s productHistoryRun'] !== undefined) {
    productHistoryReturnTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s productG2FaultsOnly'] === 'true') {
    productG2FaultTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s renderObservation'] !== undefined) {
    productRenderObservationTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s transitionFrames'] !== undefined) {
    productTransitionFramesTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s transitionRecording'] !== undefined) {
    productTransitionRecordingTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s sourceFixtureLoad'] !== undefined) {
    productSourceFixtureTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s sourceObservationLabel'] !== undefined) {
    productSourceObservationTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s productG2Only'] === 'true') {
    productG2Test();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s memoryRoundTripsOnly'] === 'true') {
    g1MemoryRoundTripsTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s g1StartupObservation'] === 'true') {
    g1StartupObservationTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s g1NativePerformance'] === 'true') {
    g1NativeSavePerformanceTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s flutterTextureOnly'] === 'true') {
    flutterTextureProbeTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s saveHistoryUpgradePhase'] !== undefined) {
    saveHistoryUpgradeTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s flutterFoundationOnly'] === 'true') {
    flutterFoundationTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s saveHistoryUiOnly'] === 'true') {
    saveHistoryUiTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s saveHistoryOnly'] === 'true') {
    saveHistoryTest();
    saveHistoryPlayTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyProductPlayOnly'] === 'true') {
    nearbyMvpProductPlayTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyServiceOnly'] === 'true') {
    nearbyServiceTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyMvpOnly'] === 'true') {
    nearbyMvpScanFlowTest();
    nearbyMvpHostTest();
    nearbyMvpHostFlowTest();
    nearbyLanNetworkTest();
    nearbyWifiConnectorTest();
    nearbyScanJoinServiceTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyCrossOnly'] === 'true') {
    nearbyMvpCrossAppTest();
    return;
  }
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyExternalHostOnly'] === 'true') {
    nearbyMvpExternalHostTest();
    return;
  }
  // Targeted physical-device UX checks must not initialize unrelated ROM fixtures
  // before Hypium applies its class filter.
  if (abilityDelegatorRegistry.getArguments().parameters['-s nearbyUxOnly'] === 'true') {
    nearbyUxRestorationTest();
    return;
  }
  saveHistoryTest();
  smokeTest();
  controlLayoutWarningsTest();
  licenseModelTest();
  pauseParamsTest();
  settingsHelpersTest();
  checkpointStoreTest();
  catalogProductServiceTest();
  nearbyServiceTest();
  nearbyMvpScanFlowTest();
  nearbyMvpHostTest();
  nearbyMvpHostFlowTest();
  nearbyLanNetworkTest();
  nearbyWifiConnectorTest();
  nearbyScanJoinServiceTest();
  nearbyUxRestorationTest();
  builtinPlaySmokeTest();
  builtinGameplayAcceptanceTest();
}

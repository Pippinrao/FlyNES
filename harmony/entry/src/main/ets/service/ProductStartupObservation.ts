import systemDateTime from '@ohos.systemDateTime';

/** Process-local completion events, never inferred from a visible card. */
export class ProductStartupObservation {
  static nativeOwnerReadyMs: number = -1;
  static catalogReadyMs: number = -1;
  static ownerReady(): void {
    if (ProductStartupObservation.nativeOwnerReadyMs < 0)
      ProductStartupObservation.nativeOwnerReadyMs = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false);
  }
  static catalogReady(): void {
    if (ProductStartupObservation.catalogReadyMs < 0)
      ProductStartupObservation.catalogReadyMs = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false);
  }
}

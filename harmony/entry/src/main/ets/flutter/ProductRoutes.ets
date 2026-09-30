import { router } from '@kit.ArkUI';

/** Old URLs stay callable for explicit baselines, never for ordinary product routing. */
export function redirectProductRoute(route: string): boolean {
  if (AppStorage.get<boolean>('ProductNativeBaseline') === true) return false;
  const params = router.getParams() as Record<string, Object> | undefined;
  void router.replaceUrl({ url: 'pages/FlutterFoundation', params: {
    route: route, purpose: params?.['nearbyChooseGame'] === true ? 'nearby' : 'single'
  } });
  return true;
}

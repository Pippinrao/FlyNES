import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { join } from 'path';
import { verifyFlutterHarStage } from './flutter-har-guard';

// A host build may consume only the exact mode and bytes staged by Build-Ohos.
hvigor.getRootNode().afterNodeEvaluate(node => {
  const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  verifyFlutterHarStage(join(__dirname, '.artifacts/flutter-har'), context.getBuildMode());
});

export default {
  system: appTasks,
  plugins: []
}

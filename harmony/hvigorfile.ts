import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

// G1 currently stages debug-only Flutter HARs. Never let a release build silently
// package that engine; release support must supply independently built HARs first.
hvigor.getRootNode().afterNodeEvaluate(node => {
  const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  if (context.getBuildMode() !== 'debug') {
    throw new Error('Flutter foundation currently supports debug builds only. Run tools/flutter/Build-Ohos.ps1; release requires release Flutter HARs.');
  }
});

export default {
  system: appTasks,
  plugins: []
}

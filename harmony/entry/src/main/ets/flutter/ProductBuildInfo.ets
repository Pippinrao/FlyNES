import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

class ProductBuildRecord {
  buildRevision: string = '';
}

export async function productBuildRevision(context: common.UIAbilityContext): Promise<string> {
  try {
    const raw = await context.resourceManager.getRawFileContent('build-revision.json');
    const body = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(raw);
    const record = JSON.parse(body) as ProductBuildRecord;
    return /^[a-f0-9]{40}(-dirty\.[a-f0-9]{12})?$/.test(record.buildRevision) ? record.buildRevision : '';
  } catch (_) { return ''; }
}

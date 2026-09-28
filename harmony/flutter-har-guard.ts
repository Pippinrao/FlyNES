import { readFileSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';

const sdkRevision = '244a0e8abb3085e8675589b13e219af8c41cb7aa';
const names = ['flutter_embedding.har', 'arm64_v8a.har', 'x86_64.har', 'flutter_module.har'];
interface HarRecord { name: string; sha256: string; }
interface HarManifest { schemaVersion: number; mode: string; sdkRevision: string; files: HarRecord[]; }

/** Refuse a mode switch or interrupted staging before Hvigor packages mixed engines. */
export function verifyFlutterHarStage(directory: string, buildMode: string): void {
  const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'), 'utf8')) as HarManifest;
  if (manifest.schemaVersion !== 1 || manifest.sdkRevision !== sdkRevision) {
    throw new Error('Flutter HAR SDK revision or manifest schema mismatch. Run tools/flutter/Build-Ohos.ps1.');
  }
  if (!['debug', 'profile', 'release'].includes(buildMode) || manifest.mode !== buildMode) {
    throw new Error(`Flutter HAR mode mismatch: host=${buildMode}, staged=${manifest.mode}. Run Build-Ohos.ps1 -Mode ${buildMode}.`);
  }
  if (!Array.isArray(manifest.files) || manifest.files.length !== names.length ||
      !names.every(name => manifest.files.filter(file => file.name === name).length === 1)) {
    throw new Error('Flutter HAR manifest must identify exactly four HAR files.');
  }
  for (const name of names) {
    const record = manifest.files.find(file => file.name === name)!;
    const actual = createHash('sha256').update(readFileSync(join(directory, name))).digest('hex');
    if (typeof record.sha256 !== 'string' || actual !== record.sha256.toLowerCase()) {
      throw new Error(`Flutter HAR hash mismatch: ${name}. Run tools/flutter/Build-Ohos.ps1.`);
    }
  }
}

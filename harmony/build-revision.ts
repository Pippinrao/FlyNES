import { execFileSync } from 'child_process';
import { createHash } from 'crypto';
import { existsSync, lstatSync, readFileSync, readlinkSync, writeFileSync } from 'fs';
import { join } from 'path';

interface SourceIdentity {
  revision: string;
  fingerprint: string;
  dirty: boolean;
}

function sourceIdentity(repo: string): SourceIdentity {
  const git = (args: string[]): string => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8' });
  const revision = git(['rev-parse', '--verify', 'HEAD']).trim();
  if (!/^[a-f0-9]{40}$/.test(revision)) throw new Error('Invalid Git source revision');
  const files = [...new Set(git(['ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0').filter(Boolean))].sort();
  const submodules = new Map<string, string>();
  for (const entry of git(['ls-files', '--stage', '-z']).split('\0')) {
    const separator = entry.indexOf('\t');
    if (separator < 0) continue;
    const fields = entry.substring(0, separator).split(' ');
    if (fields[0] === '160000' && fields[2] === '0') submodules.set(entry.substring(separator + 1), fields[1]);
  }
  let dirty = git(['status', '--porcelain', '--untracked-files=all', '--ignore-submodules=none']).length > 0;
  const hash = createHash('sha256');
  hash.update(`checkout:${revision}\0`);
  for (const file of files) {
    hash.update(`${Buffer.byteLength(file)}:${file}\0`);
    const absolute = join(repo, file);
    try {
      const stat = lstatSync(absolute);
      if (stat.isSymbolicLink()) hash.update(`link:${readlinkSync(absolute)}`);
      else if (stat.isFile()) hash.update(readFileSync(absolute));
      else if (submodules.has(file)) {
        const expected = submodules.get(file);
        hash.update(`gitlink:${expected}\0`);
        if (existsSync(join(absolute, '.git'))) {
          const nested = sourceIdentity(absolute);
          hash.update(`submodule:${nested.revision}:${nested.fingerprint}`);
          dirty = dirty || nested.dirty || nested.revision !== expected;
        } else {
          hash.update('submodule-uninitialized');
          dirty = true;
        }
      } else hash.update('directory');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
      hash.update('deleted');
    }
    hash.update('\0');
  }
  return { revision, fingerprint: hash.digest('hex'), dirty };
}

/** Deterministic source identity, regenerated for every host build configuration. */
export function writeBuildRevision(repo: string, output: string): string {
  const identity = sourceIdentity(repo);
  const revision = identity.revision;
  const sourceFingerprint = identity.fingerprint;
  const dirty = identity.dirty;
  const buildRevision = revision + (dirty ? `-dirty.${sourceFingerprint.substring(0, 12)}` : '');
  writeFileSync(output, JSON.stringify({ schemaVersion: 1, buildRevision, sourceRevision: revision, sourceFingerprint, dirty }) + '\n');
  return buildRevision;
}

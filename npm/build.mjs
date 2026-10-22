#!/usr/bin/env node
// Builds the npm packages for a release from GoReleaser's output.
//
//   node npm/build.mjs --version 1.5.0 [--dist dist] [--out dist/npm] [--scope @horac3]
//
// Reads <dist>/artifacts.json (written by GoReleaser), and for every built binary writes a platform package
// <scope>/claude-kit-<platform>-<arch> containing only that binary, with "os"/"cpu" set so npm installs it only
// on matching machines. Then writes the main "claude-kit" launcher package, listing every platform package as an
// optional dependency pinned to the same version. Publishing happens in the release workflow, platform packages first.
import { cpSync, chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => (a.startsWith('--') ? [...acc, [a.slice(2), all[i + 1]]] : acc), []),
);
const version = (args.version || '').replace(/^v/, '');
if (!/^\d+\.\d+\.\d+(-[\w.]+)?$/.test(version)) {
  console.error('usage: node npm/build.mjs --version X.Y.Z [--dist dist] [--out dist/npm] [--scope @horac3]');
  process.exit(2);
}
const dist = resolve(args.dist || join(repo, 'dist'));
const out = resolve(args.out || join(dist, 'npm'));
// Platform packages live in the launcher's own scope unless overridden (tests use --scope).
const launcherName = JSON.parse(readFileSync(join(here, 'claude-kit', 'package.json'), 'utf8')).name;
const scope = args.scope || launcherName.split('/')[0];
if (!scope.startsWith('@')) throw new Error(`launcher package must be scoped, got ${launcherName}`);

const GOOS = { linux: 'linux', darwin: 'darwin', windows: 'win32' };
const GOARCH = { amd64: 'x64', arm64: 'arm64' };

const artifacts = JSON.parse(readFileSync(join(dist, 'artifacts.json'), 'utf8')).filter(
  (a) => a.type === 'Binary' && a.extra?.ID !== 'skip',
);
if (artifacts.length === 0) throw new Error(`no binaries in ${join(dist, 'artifacts.json')}`);

const platforms = {};
for (const a of artifacts) {
  const os = GOOS[a.goos];
  const cpu = GOARCH[a.goarch];
  if (!os || !cpu) continue;
  const name = `${scope}/claude-kit-${os}-${cpu}`;
  const dir = join(out, `claude-kit-${os}-${cpu}`);
  const exe = os === 'win32' ? 'claude-kit.exe' : 'claude-kit';
  const src = resolve(repo, a.path);
  if (!existsSync(src)) throw new Error(`binary not found: ${src}`);
  mkdirSync(join(dir, 'bin'), { recursive: true });
  cpSync(src, join(dir, 'bin', exe));
  if (os !== 'win32') chmodSync(join(dir, 'bin', exe), 0o755);
  writeFileSync(
    join(dir, 'package.json'),
    JSON.stringify(
      {
        name,
        version,
        description: `claude-kit binary for ${os}-${cpu}. Install "@horac3/claude-kit" instead; it picks this up automatically.`,
        repository: { type: 'git', url: 'git+https://github.com/horac3/claude-kit.git' },
        license: 'MIT',
        os: [os],
        cpu: [cpu],
        files: ['bin/'],
        preferUnplugged: true,
      },
      null,
      2,
    ) + '\n',
  );
  cpSync(join(repo, 'LICENSE'), join(dir, 'LICENSE'));
  platforms[name] = version;
}

const mainDir = join(out, 'claude-kit');
cpSync(join(here, 'claude-kit'), mainDir, { recursive: true });
const mainPkg = JSON.parse(readFileSync(join(here, 'claude-kit', 'package.json'), 'utf8'));
mainPkg.version = version;
mainPkg.optionalDependencies = Object.fromEntries(Object.entries(platforms).sort());
writeFileSync(join(mainDir, 'package.json'), JSON.stringify(mainPkg, null, 2) + '\n');
cpSync(join(repo, 'LICENSE'), join(mainDir, 'LICENSE'));
cpSync(join(here, 'README.md'), join(mainDir, 'README.md'));
chmodSync(join(mainDir, 'bin', 'claude-kit.js'), 0o755);

console.log(`claude-kit ${version}: ${Object.keys(platforms).length} platform packages + launcher in ${out}`);
for (const n of Object.keys(mainPkg.optionalDependencies)) console.log(`  ${n}`);

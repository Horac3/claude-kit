#!/usr/bin/env node
// claude-kit npm launcher: runs the prebuilt Go binary for this platform.
// The binary comes from a per-platform optional dependency (e.g. @horac3/claude-kit-linux-x64),
// so npm downloads only the one that matches this machine, with no install scripts.
'use strict';

const { spawnSync } = require('node:child_process');
const pkg = require('../package.json');

const key = `${process.platform}-${process.arch}`; // e.g. linux-x64, darwin-arm64, win32-x64
const exe = process.platform === 'win32' ? 'claude-kit.exe' : 'claude-kit';

function resolveBinary() {
  if (process.env.CLAUDE_KIT_BINARY) return process.env.CLAUDE_KIT_BINARY;
  const name = Object.keys(pkg.optionalDependencies || {}).find((n) => n.endsWith(`-${key}`));
  if (!name) return null;
  try {
    return require.resolve(`${name}/bin/${exe}`);
  } catch {
    return null;
  }
}

const bin = resolveBinary();
if (!bin) {
  const supported = Object.keys(pkg.optionalDependencies || {}).map((n) => n.replace(/^.*claude-kit-/, '')).join(', ');
  console.error(
    `claude-kit: no prebuilt binary for ${key}.\n` +
      `Supported: ${supported || 'none listed'}.\n` +
      'If you installed with --no-optional or --omit=optional, reinstall without it.\n' +
      'Alternatives: go install github.com/horac3/claude-kit/cmd/claude-kit@latest, ' +
      'or a binary from https://github.com/horac3/claude-kit/releases',
  );
  process.exit(1);
}

const result = spawnSync(bin, process.argv.slice(2), {
  stdio: 'inherit',
  env: { ...process.env, CLAUDE_KIT_VIA: 'npm' },
});
if (result.error) {
  console.error(`claude-kit: could not run ${bin}: ${result.error.message}`);
  process.exit(1);
}
if (result.signal) process.kill(process.pid, result.signal);
process.exit(result.status ?? 1);

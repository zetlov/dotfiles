import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  createMonitorProfileCommand,
  createMonitorProfileProbeCommand,
  getMonitorProfileForCount,
  monitorProfiles,
  probeMonitorProfiles,
} from './monitor-profiles';

test('getMonitorProfileForCount recognizes only managed topologies', () => {
  assert.equal(getMonitorProfileForCount(3), 'all');
  assert.equal(getMonitorProfileForCount(2), 'left-center');
  assert.equal(getMonitorProfileForCount(1), 'right-only');
  assert.equal(getMonitorProfileForCount(0), null);
  assert.equal(getMonitorProfileForCount(4), null);
});

test('monitorProfiles exposes the three user-facing choices', () => {
  assert.deepEqual(monitorProfiles, [
    { name: 'all', label: '3 displays' },
    { name: 'left-center', label: 'Left + center' },
    { name: 'right-only', label: 'Right only' },
  ]);
});

test('createMonitorProfileCommand builds a fixed PowerShell invocation', () => {
  assert.deepEqual(createMonitorProfileCommand('left-center'), {
    program:
      'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    args: [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      '& "$env:LOCALAPPDATA\\dotfiles\\monitor-profiles\\' +
        'Switch-MonitorProfile.ps1" -Name left-center',
    ],
  });
});

test('createMonitorProfileCommand rejects arbitrary profile names', () => {
  assert.throws(
    () => createMonitorProfileCommand('../unexpected'),
    /Unknown monitor profile/,
  );
});

test('createMonitorProfileProbeCommand checks the managed switch script', () => {
  assert.deepEqual(createMonitorProfileProbeCommand(), {
    program:
      'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    args: [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      'if (Test-Path -LiteralPath ' +
        '"$env:LOCALAPPDATA\\dotfiles\\monitor-profiles\\' +
        'Switch-MonitorProfile.ps1" -PathType Leaf) ' +
        '{ exit 0 } else { exit 1 }',
    ],
  });
});

test('probeMonitorProfiles returns true only for a successful probe', async () => {
  assert.equal(
    await probeMonitorProfiles(async () => ({ code: 0 })),
    true,
  );
  assert.equal(
    await probeMonitorProfiles(async () => ({ code: 1 })),
    false,
  );
  assert.equal(
    await probeMonitorProfiles(async () => ({ code: null })),
    false,
  );
});

test('probeMonitorProfiles treats execution errors as unavailable', async () => {
  assert.equal(
    await probeMonitorProfiles(async () => {
      throw new Error('unavailable');
    }),
    false,
  );
});

test('the generated command matches the Zebar shell allowlist', () => {
  const pack = JSON.parse(
    readFileSync(new URL('../zpack.json', import.meta.url), 'utf8'),
  );
  const allowedCommand = pack.widgets[0].privileges.shellCommands.find(
    (entry: { argsRegex: string }) => entry.argsRegex.includes('-Name'),
  );
  const command = createMonitorProfileCommand('right-only');

  assert.equal(command.program, allowedCommand.program);
  assert.match(
    command.args.join(' '),
    new RegExp(allowedCommand.argsRegex),
  );
});

test('the probe command matches the Zebar shell allowlist', () => {
  const pack = JSON.parse(
    readFileSync(new URL('../zpack.json', import.meta.url), 'utf8'),
  );
  const allowedCommand = pack.widgets[0].privileges.shellCommands.find(
    (entry: { argsRegex: string }) => entry.argsRegex.includes('Test-Path'),
  );
  const command = createMonitorProfileProbeCommand();

  assert.equal(command.program, allowedCommand.program);
  assert.match(
    command.args.join(' '),
    new RegExp(allowedCommand.argsRegex),
  );
});

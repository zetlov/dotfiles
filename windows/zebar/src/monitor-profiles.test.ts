import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  createMonitorProfileCommand,
  getMonitorProfileForCount,
  monitorProfiles,
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

test('the generated command matches the Zebar shell allowlist', () => {
  const pack = JSON.parse(
    readFileSync(new URL('../zpack.json', import.meta.url), 'utf8'),
  );
  const allowedCommand = pack.widgets[0].privileges.shellCommands[1];
  const command = createMonitorProfileCommand('right-only');

  assert.equal(command.program, allowedCommand.program);
  assert.match(
    command.args.join(' '),
    new RegExp(allowedCommand.argsRegex),
  );
});

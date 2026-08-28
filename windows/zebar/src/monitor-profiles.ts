export const monitorProfiles = [
  { name: 'all', label: '3 displays' },
  { name: 'left-center', label: 'Left + center' },
  { name: 'right-only', label: 'Right only' },
] as const;

export type MonitorProfileName = (typeof monitorProfiles)[number]['name'];

const powershellPath =
  'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
const switchScriptPath =
  '$env:LOCALAPPDATA\\dotfiles\\monitor-profiles\\' +
  'Switch-MonitorProfile.ps1';

function createPowerShellCommand(command: string): {
  readonly program: string;
  readonly args: readonly string[];
} {
  return {
    program: powershellPath,
    args: [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ],
  };
}

function isMonitorProfileName(name: string): name is MonitorProfileName {
  return monitorProfiles.some(profile => profile.name === name);
}

export function getMonitorProfileForCount(
  monitorCount: number,
): MonitorProfileName | null {
  if (monitorCount === 3) return 'all';
  if (monitorCount === 2) return 'left-center';
  if (monitorCount === 1) return 'right-only';
  return null;
}

export function createMonitorProfileCommand(name: string): {
  readonly program: string;
  readonly args: readonly string[];
} {
  if (!isMonitorProfileName(name)) {
    throw new Error(`Unknown monitor profile: ${name}`);
  }
  return createPowerShellCommand(`& "${switchScriptPath}" -Name ${name}`);
}

export function createMonitorProfileProbeCommand(): {
  readonly program: string;
  readonly args: readonly string[];
} {
  return createPowerShellCommand(
    `if (Test-Path -LiteralPath "${switchScriptPath}" -PathType Leaf) ` +
      '{ exit 0 } else { exit 1 }',
  );
}

export async function probeMonitorProfiles(
  execute: (
    program: string,
    args: readonly string[],
  ) => Promise<{ readonly code: number | null }>,
): Promise<boolean> {
  const command = createMonitorProfileProbeCommand();
  try {
    const result = await execute(command.program, command.args);
    return result.code === 0;
  } catch {
    return false;
  }
}

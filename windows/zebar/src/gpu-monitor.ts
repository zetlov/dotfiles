import { clampPercent } from './view-model';

export const NVIDIA_SMI_PROGRAM = 'C:\\Windows\\System32\\nvidia-smi.exe';
export const NVIDIA_SMI_ARGS = [
  '--query-gpu=utilization.gpu,temperature.gpu',
  '--format=csv,noheader,nounits',
  '--id=0',
  '--loop-ms=2000',
] as const;

export interface GpuShellProcess {
  readonly kill: () => void;
  readonly onExit: (
    callback: (status: { exitCode: number | null; signal: number | null }) => void,
  ) => void;
  readonly onStderr: (callback: (line: string) => void) => void;
  readonly onStdout: (callback: (line: string) => void) => void;
}

export type SpawnGpuProcess = (
  program: string,
  args: readonly string[],
) => Promise<GpuShellProcess>;

export interface GpuMetrics {
  readonly temperature: number;
  readonly usage: number;
}

export function parseGpuMetrics(line: string): GpuMetrics | null {
  const normalized = line.trim();
  if (!normalized) return null;

  const fields = normalized.split(',').map(field => field.trim());
  if (fields.length !== 2) return null;

  const usage = Number(fields[0]);
  const temperature = Number(fields[1]);
  if (
    !Number.isFinite(usage) || usage < 0 || usage > 100 ||
    !Number.isFinite(temperature) || temperature < 0 || temperature > 150
  ) return null;

  return {
    usage: clampPercent(usage),
    temperature: Math.round(temperature),
  };
}

export function startGpuMonitor(
  onMetrics: (metrics: GpuMetrics | null) => void,
  spawn: SpawnGpuProcess,
): () => void {
  let stopped = false;
  let process: GpuShellProcess | undefined;

  void spawn(NVIDIA_SMI_PROGRAM, NVIDIA_SMI_ARGS)
    .then(startedProcess => {
      if (stopped) {
        startedProcess.kill();
        return;
      }

      process = startedProcess;
      startedProcess.onStdout(line => {
        const metrics = parseGpuMetrics(line);
        if (!stopped && metrics !== null) onMetrics(metrics);
      });
      startedProcess.onExit(() => {
        if (process === startedProcess) process = undefined;
        if (!stopped) onMetrics(null);
      });
    })
    .catch(() => {
      process = undefined;
      if (!stopped) onMetrics(null);
    });

  return () => {
    stopped = true;
    process?.kill();
    process = undefined;
  };
}

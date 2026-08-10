import assert from 'node:assert/strict';
import test from 'node:test';
import {
  NVIDIA_SMI_ARGS,
  NVIDIA_SMI_PROGRAM,
  parseGpuMetrics,
  startGpuMonitor,
  type GpuShellProcess,
} from './gpu-monitor';

test('parseGpuMetrics accepts safe NVIDIA usage and temperature output', () => {
  assert.deepEqual(parseGpuMetrics('47, 62\n'), { usage: 47, temperature: 62 });
  assert.deepEqual(parseGpuMetrics('100, 0'), { usage: 100, temperature: 0 });
  assert.equal(parseGpuMetrics('-1, 50'), null);
  assert.equal(parseGpuMetrics('101, 50'), null);
  assert.equal(parseGpuMetrics('50, 151'), null);
  assert.equal(parseGpuMetrics('not supported'), null);
});

test('startGpuMonitor uses the pinned command and stops its process', async () => {
  let stdout: ((line: string) => void) | undefined;
  let killed = false;
  const process: GpuShellProcess = {
    kill: () => { killed = true; },
    onExit: () => undefined,
    onStderr: () => undefined,
    onStdout: callback => { stdout = callback; },
  };
  const calls: Array<{ program: string; args: readonly string[] }> = [];
  const values: Array<{ usage: number; temperature: number } | null> = [];

  const stop = startGpuMonitor(values.push.bind(values), async (program, args) => {
    calls.push({ program, args });
    return process;
  });
  await Promise.resolve();
  stdout?.('73, 61');

  assert.deepEqual(calls, [{ program: NVIDIA_SMI_PROGRAM, args: NVIDIA_SMI_ARGS }]);
  assert.deepEqual(values, [{ usage: 73, temperature: 61 }]);
  stop();
  stop();
  assert.equal(killed, true);
});

test('startGpuMonitor clears stale usage when the process exits', async () => {
  let exit: ((status: {
    exitCode: number | null;
    signal: number | null;
  }) => void) | undefined;
  const values: Array<{ usage: number; temperature: number } | null> = [];
  startGpuMonitor(values.push.bind(values), async () => ({
    kill: () => undefined,
    onExit: callback => { exit = callback; },
    onStderr: () => undefined,
    onStdout: () => undefined,
  }));
  await Promise.resolve();
  exit?.({ exitCode: 1, signal: null });

  assert.deepEqual(values, [null]);
});

test('startGpuMonitor reports unavailable when spawning fails', async () => {
  const values: Array<{ usage: number; temperature: number } | null> = [];
  startGpuMonitor(values.push.bind(values), async () => {
    throw new Error('unavailable');
  });
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(values, [null]);
});

test('startGpuMonitor kills a process that resolves after cleanup', async () => {
  let resolveProcess: ((process: GpuShellProcess) => void) | undefined;
  let killed = false;
  const spawned = new Promise<GpuShellProcess>(resolve => { resolveProcess = resolve; });
  const stop = startGpuMonitor(() => undefined, async () => spawned);

  stop();
  resolveProcess?.({
    kill: () => { killed = true; },
    onExit: () => undefined,
    onStderr: () => undefined,
    onStdout: () => undefined,
  });
  await spawned;
  await new Promise(resolve => setImmediate(resolve));

  assert.equal(killed, true);
});

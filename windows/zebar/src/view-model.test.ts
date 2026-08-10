import assert from 'node:assert/strict';
import test from 'node:test';
import {
  clampPercent,
  getMediaProgress,
  getMediaText,
  getNetworkPresentation,
  sortWorkspaces,
} from './view-model';

test('sortWorkspaces orders numeric names before named workspaces', () => {
  const workspaces = sortWorkspaces([
    { name: 'vert' },
    { name: '10' },
    { name: '2' },
    { name: '1' },
  ]);

  assert.deepEqual(
    workspaces.map(workspace => workspace.name),
    ['1', '2', '10', 'vert'],
  );
});

test('clampPercent returns a safe integer range', () => {
  assert.equal(clampPercent(54.7), 55);
  assert.equal(clampPercent(-10), 0);
  assert.equal(clampPercent(150), 100);
  assert.equal(clampPercent(Number.NaN), 0);
});

test('getNetworkPresentation distinguishes Windows connection types', () => {
  assert.deepEqual(getNetworkPresentation('wifi', 'Home'), {
    className: 'wifi',
    label: 'Home',
  });
  assert.equal(getNetworkPresentation('ethernet', null).label, 'Ethernet');
  assert.equal(getNetworkPresentation(undefined, undefined).label, 'Offline');
});

test('getMediaText handles missing metadata', () => {
  assert.equal(getMediaText('Track', 'Artist'), 'Track — Artist');
  assert.equal(getMediaText('Track', ''), 'Track');
  assert.equal(getMediaText('', ''), 'Unknown track');
});

test('getMediaProgress clamps playback into a safe percentage', () => {
  assert.equal(getMediaProgress(45, 180), 25);
  assert.equal(getMediaProgress(-1, 180), 0);
  assert.equal(getMediaProgress(220, 180), 100);
  assert.equal(getMediaProgress(10, 0), 0);
  assert.equal(getMediaProgress(Number.NaN, 180), 0);
});

import './index.css';
import {
  Cable,
  Cpu,
  Gpu,
  MemoryStick,
  Pause,
  Play,
  SkipBack,
  SkipForward,
  Volume2,
  VolumeX,
  Wifi,
  WifiOff,
} from 'lucide-solid';
import { createSignal, For, onCleanup, Show } from 'solid-js';
import { createStore } from 'solid-js/store';
import { render } from 'solid-js/web';
import * as zebar from 'zebar';
import {
  clampPercent,
  getMediaProgress,
  getMediaText,
  getNetworkPresentation,
  sortWorkspaces,
} from './view-model';
import { startGpuMonitor } from './gpu-monitor';

const providers = zebar.createProviderGroup({
  audio: { type: 'audio' },
  cpu: { type: 'cpu', refreshInterval: 2000 },
  clock: {
    type: 'date',
    formatting: 'HH:mm:ss',
    refreshInterval: 1000,
  },
  date: {
    type: 'date',
    formatting: 'yyyy/MM/dd (ccc)',
    refreshInterval: 1000,
  },
  glazewm: { type: 'glazewm' },
  media: { type: 'media' },
  memory: { type: 'memory', refreshInterval: 2000 },
  network: { type: 'network', refreshInterval: 7000 },
  systray: { type: 'systray' },
});

function App() {
  const [output, setOutput] = createStore(providers.outputMap);
  const [gpuMetrics, setGpuMetrics] = createSignal<{
    readonly temperature: number;
    readonly usage: number;
  } | null>(null);
  providers.onOutput(outputMap => setOutput(outputMap));
  onCleanup(startGpuMonitor(
    setGpuMetrics,
    (program, args) => zebar.shellSpawn(program, [...args]),
  ));

  const adjustVolume = (delta: number) => {
    const volume = output.audio?.defaultPlaybackDevice?.volume;
    if (volume === undefined) return;
    void output.audio?.setVolume(clampPercent(volume + delta));
  };

  return (
    <main class="bar-shell">
      <section class="cluster left-cluster">
        <Show when={output.glazewm}>
          {glazewm => (
            <div class="island workspaces" aria-label="Workspaces">
              <For each={sortWorkspaces(glazewm().currentWorkspaces)}>
                {workspace => (
                  <button
                    class="workspace-button"
                    classList={{
                      displayed: workspace.isDisplayed,
                      focused: workspace.hasFocus,
                    }}
                    onClick={() =>
                      void glazewm().runCommand(
                        `focus --workspace ${workspace.name}`,
                      )
                    }
                    title={`Workspace ${workspace.name}`}
                    aria-current={workspace.hasFocus ? 'page' : undefined}
                  >
                    {workspace.displayName ?? workspace.name}
                  </button>
                )}
              </For>
            </div>
          )}
        </Show>

        <Show when={output.media?.currentSession}>
          {session => (
            <div class="island media-card">
              <div class="media-controls">
                <button
                  class="icon-button media-control"
                  onClick={() => void output.media?.previous()}
                  title="Previous track"
                  aria-label="Previous track"
                >
                  <SkipBack size={13} strokeWidth={2.2} />
                </button>
                <button
                  class="icon-button media-control media-play"
                  onClick={() => void output.media?.togglePlayPause()}
                  title={session().isPlaying ? 'Pause' : 'Play'}
                  aria-label={session().isPlaying ? 'Pause' : 'Play'}
                >
                  <Show when={session().isPlaying} fallback={<Play size={13} fill="currentColor" />}>
                    <Pause size={13} fill="currentColor" />
                  </Show>
                </button>
                <button
                  class="icon-button media-control"
                  onClick={() => void output.media?.next()}
                  title="Next track"
                  aria-label="Next track"
                >
                  <SkipForward size={13} strokeWidth={2.2} />
                </button>
              </div>
              <div class="media-copy">
                <span class="media-text">
                  {getMediaText(session().title, session().artist)}
                </span>
                <span class="media-progress" aria-hidden="true">
                  <span
                    class="media-progress-fill"
                    style={{
                      width: `${getMediaProgress(
                        session().position,
                        session().endTime,
                      )}%`,
                    }}
                  />
                </span>
              </div>
            </div>
          )}
        </Show>
      </section>

      <div class="island clock-card">
        <span class="clock-time">{output.clock?.formatted ?? '--:--:--'}</span>
        <span class="clock-divider" aria-hidden="true" />
        <span class="clock-date">{output.date?.formatted ?? '----/--/--'}</span>
      </div>

      <section class="cluster right-cluster">
        <Show when={output.systray?.icons.length}>
          <div class="island tray-card">
            <For each={output.systray?.icons ?? []}>
              {icon => (
                <button
                  class="icon-button tray-button"
                  onClick={event => {
                    event.preventDefault();
                    output.systray?.onLeftClick(icon.id);
                  }}
                  onContextMenu={event => {
                    event.preventDefault();
                    output.systray?.onRightClick(icon.id);
                  }}
                  title={icon.tooltip}
                >
                  <img src={icon.iconUrl} alt="" />
                </button>
              )}
            </For>
          </div>
        </Show>

        <div class="island stat-card">
          <span
            class="metric"
            title="CPU usage"
            aria-label={`CPU ${clampPercent(output.cpu?.usage ?? 0)} percent`}
          >
            <Cpu size={13} />
            <span>{clampPercent(output.cpu?.usage ?? 0)}%</span>
          </span>
          <span class="metric-separator" aria-hidden="true" />
          <Show when={gpuMetrics()}>
            {metrics => (
              <>
                <span
                  class="metric"
                  title="GPU usage and temperature"
                  aria-label={
                    `GPU ${metrics().usage} percent, ` +
                    `${metrics().temperature} degrees Celsius`
                  }
                >
                  <Gpu size={13} />
                  <span>{metrics().usage}% {metrics().temperature}&deg;C</span>
                </span>
                <span class="metric-separator" aria-hidden="true" />
              </>
            )}
          </Show>
          <span
            class="metric"
            title="Memory usage"
            aria-label={`Memory ${clampPercent(output.memory?.usage ?? 0)} percent`}
          >
            <MemoryStick size={13} />
            <span>{clampPercent(output.memory?.usage ?? 0)}%</span>
          </span>
        </div>

        {(() => {
          const network = () =>
            getNetworkPresentation(
              output.network?.defaultInterface?.type,
              output.network?.defaultGateway?.ssid,
            );
          return (
            <div class={`island network-card ${network().className}`}>
              {network().className === 'wifi' ? (
                <Wifi size={14} />
              ) : network().className === 'ethernet' ? (
                <Cable size={14} />
              ) : network().className === 'vpn' ? (
                <Wifi size={14} />
              ) : (
                <WifiOff size={14} />
              )}
              <span class="ellipsis">{network().label}</span>
            </div>
          );
        })()}

        <Show when={output.audio?.defaultPlaybackDevice}>
          {device => (
            <button
              class="island volume-card"
              onWheel={event => {
                event.preventDefault();
                adjustVolume(event.deltaY < 0 ? 5 : -5);
              }}
              onClick={() =>
                void output.audio?.setMute(!device().isMuted, {
                  deviceId: device().deviceId,
                })
              }
              title={device().name}
              aria-label={device().isMuted ? 'Unmute audio' : 'Mute audio'}
            >
              {device().isMuted ? <VolumeX size={14} /> : <Volume2 size={14} />}
              <span>{clampPercent(device().volume)}%</span>
            </button>
          )}
        </Show>
      </section>
    </main>
  );
}

const root = document.getElementById('root');
if (!root) throw new Error('Zebar root element is missing.');
render(() => <App />, root);

import './index.css';
import {
  Battery,
  BatteryCharging,
  Cable,
  Volume2,
  VolumeX,
  Wifi,
  WifiOff,
} from 'lucide-solid';
import { For, Show } from 'solid-js';
import { createStore } from 'solid-js/store';
import { render } from 'solid-js/web';
import * as zebar from 'zebar';
import {
  clampPercent,
  getNetworkPresentation,
  getSurfaceWorkspaces,
} from './view-model';

const providers = zebar.createProviderGroup({
  audio: { type: 'audio' },
  battery: { type: 'battery', refreshInterval: 30000 },
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
  network: { type: 'network', refreshInterval: 7000 },
  systray: { type: 'systray' },
});

function SurfaceApp() {
  const [output, setOutput] = createStore(providers.outputMap);
  providers.onOutput(outputMap => setOutput(outputMap));

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
              <For each={getSurfaceWorkspaces(glazewm().currentWorkspaces)}>
                {workspace => (
                  <button
                    class="workspace-button"
                    classList={{
                      displayed: workspace.isDisplayed,
                      focused: workspace.hasFocus,
                    }}
                    onClick={() => void glazewm().runCommand(
                      `focus --workspace ${workspace.name}`,
                    )}
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

        <Show when={output.battery}>
          {battery => (
            <div
              class="island volume-card"
              title={`Battery ${clampPercent(battery().chargePercent)}%`}
              aria-label={`Battery ${clampPercent(battery().chargePercent)} percent`}
            >
              {battery().isCharging
                ? <BatteryCharging size={14} />
                : <Battery size={14} />}
              <span>{clampPercent(battery().chargePercent)}%</span>
            </div>
          )}
        </Show>

        {(() => {
          const network = () => getNetworkPresentation(
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
              onClick={() => void output.audio?.setMute(!device().isMuted, {
                deviceId: device().deviceId,
              })}
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
render(() => <SurfaceApp />, root);

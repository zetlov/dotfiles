export interface WorkspaceSummary {
  readonly displayName?: string | null;
  readonly hasFocus?: boolean;
  readonly isDisplayed?: boolean;
  readonly name: string;
}

export interface NetworkPresentation {
  readonly className: 'ethernet' | 'offline' | 'vpn' | 'wifi';
  readonly label: string;
}

export function sortWorkspaces<T extends WorkspaceSummary>(
  workspaces: readonly T[],
): T[] {
  return [...workspaces].sort((left, right) => {
    const leftNumber = Number(left.name);
    const rightNumber = Number(right.name);
    const leftIsNumber = Number.isInteger(leftNumber);
    const rightIsNumber = Number.isInteger(rightNumber);

    if (leftIsNumber && rightIsNumber) {
      return leftNumber - rightNumber;
    }
    if (leftIsNumber) return -1;
    if (rightIsNumber) return 1;
    return left.name.localeCompare(right.name);
  });
}

export function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(100, Math.max(0, Math.round(value)));
}

export function getNetworkPresentation(
  interfaceType: string | null | undefined,
  ssid: string | null | undefined,
): NetworkPresentation {
  if (interfaceType === 'wifi') {
    return { className: 'wifi', label: ssid?.trim() || 'Wi-Fi' };
  }
  if (interfaceType === 'ethernet') {
    return { className: 'ethernet', label: 'Ethernet' };
  }
  if (interfaceType === 'proprietary_virtual') {
    return { className: 'vpn', label: 'VPN' };
  }
  return { className: 'offline', label: 'Offline' };
}

export function getMediaText(
  title: string | null | undefined,
  artist: string | null | undefined,
): string {
  const normalizedTitle = title?.trim() || 'Unknown track';
  const normalizedArtist = artist?.trim();
  return normalizedArtist
    ? `${normalizedTitle} — ${normalizedArtist}`
    : normalizedTitle;
}

export function getMediaProgress(position: number, endTime: number): number {
  if (!Number.isFinite(position) || !Number.isFinite(endTime) || endTime <= 0) {
    return 0;
  }
  return clampPercent((position / endTime) * 100);
}

import QtQuick
import Quickshell.Services.Mpris

Item {
    id: root

    readonly property var activePlayer: pickPlayer()
    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property string title: hasPlayer ? (activePlayer.trackTitle || "Unknown Title") : ""
    readonly property string artist: hasPlayer ? (activePlayer.trackArtist || activePlayer.identity || "Unknown Artist") : ""
    readonly property string album: hasPlayer ? (activePlayer.trackAlbum || "") : ""
    readonly property string artUrl: hasPlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property real position: hasPlayer ? activePlayer.position : 0
    readonly property real length: hasPlayer ? activePlayer.length : 0
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property string currentText: formatTime(position)
    readonly property string totalText: formatTime(length)
    readonly property bool canGoNext: hasPlayer && activePlayer.canGoNext
    readonly property bool canGoPrevious: hasPlayer && activePlayer.canGoPrevious
    readonly property bool canToggle: hasPlayer && activePlayer.canTogglePlaying

    function pickPlayer() {
        const players = Mpris.players.values;
        if (!players || players.length === 0)
            return null;

        const playing = players.find(player => player.playbackState === MprisPlaybackState.Playing);
        if (playing)
            return playing;

        const spotify = players.find(player => {
            const identity = (player.identity || "").toLowerCase();
            const entry = (player.desktopEntry || "").toLowerCase();
            return identity.includes("spotify") || entry.includes("spotify");
        });
        if (spotify)
            return spotify;

        return players[0];
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0)
            return "0:00";

        const total = Math.floor(seconds);
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return `${mins}:${secs.toString().padStart(2, "0")}`;
    }

    function toggle() {
        if (canToggle)
            activePlayer.togglePlaying();
    }

    function next() {
        if (canGoNext)
            activePlayer.next();
    }

    function previous() {
        if (canGoPrevious)
            activePlayer.previous();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.isPlaying && root.hasPlayer
        onTriggered: root.activePlayer.positionChanged()
    }
}

import QtQuick
import Quickshell.Io

Item {
    id: root

    property string title: ""
    property string artist: ""
    property string album: ""
    property int duration: 0
    property real position: 0
    property string status: "Waiting"
    property string plainLyrics: ""
    property string syncedLyrics: ""
    property bool instrumental: false
    property string lastQuery: ""

    readonly property bool hasLyrics: plainLyrics !== "" || syncedLyrics !== ""
    readonly property string displayText: {
        if (plainLyrics)
            return plainLyrics;
        if (syncedLyrics)
            return syncedLyrics.replace(/\[[0-9:.]+\]\s*/g, "");
        if (instrumental)
            return "Instrumental";
        return status;
    }
    readonly property string currentLine: currentSyncedLine()

    onTitleChanged: scheduleRefresh()
    onArtistChanged: scheduleRefresh()
    onAlbumChanged: scheduleRefresh()
    onDurationChanged: scheduleRefresh()

    function scheduleRefresh() {
        refreshTimer.restart();
    }

    function clearLyrics(message) {
        plainLyrics = "";
        syncedLyrics = "";
        instrumental = false;
        status = message;
    }

    function refresh() {
        const cleanTitle = title.trim();
        const cleanArtist = artist.trim();
        if (!cleanTitle || !cleanArtist) {
            clearLyrics("No media");
            return;
        }

        const query = `${cleanArtist}|${cleanTitle}|${album}|${duration}`;
        if (query === lastQuery && (hasLyrics || status === "Not found"))
            return;

        lastQuery = query;
        clearLyrics("Loading lyrics...");
        if (!lyricsProcess.running)
            lyricsProcess.running = true;
    }

    function parseTimestamp(line) {
        const match = line.match(/^\[([0-9]+):([0-9]+(?:\.[0-9]+)?)\]/);
        if (!match)
            return -1;

        return parseInt(match[1], 10) * 60 + parseFloat(match[2]);
    }

    function currentSyncedLine() {
        if (!syncedLyrics)
            return "";

        const lines = syncedLyrics.split("\n");
        let current = "";
        for (const line of lines) {
            const start = parseTimestamp(line);
            if (start < 0)
                continue;
            if (start > position)
                break;
            current = line.replace(/^\[[0-9:.]+\]\s*/, "");
        }
        return current;
    }

    Timer {
        id: refreshTimer

        interval: 500
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: lyricsProcess

        command: [
            "sh",
            "-c",
            "curl -fsS --max-time 8 --get 'https://lrclib.net/api/get' --data-urlencode \"track_name=$1\" --data-urlencode \"artist_name=$2\" --data-urlencode \"album_name=$3\" --data-urlencode \"duration=$4\"",
            "lyrics",
            root.title,
            root.artist,
            root.album,
            String(root.duration)
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw)
                    return;

                try {
                    const payload = JSON.parse(raw);
                    root.instrumental = payload.instrumental === true;
                    root.plainLyrics = payload.plainLyrics || "";
                    root.syncedLyrics = payload.syncedLyrics || "";
                    root.status = root.hasLyrics || root.instrumental ? "Loaded" : "Not found";
                } catch (error) {
                    root.clearLyrics("Failed to parse lyrics");
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.clearLyrics("Lyrics not found");
        }
    }
}

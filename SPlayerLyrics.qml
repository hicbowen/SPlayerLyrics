import QtQuick
import Quickshell.Services.Mpris
import QtWebSockets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "splayer-lyrics"
    popoutWidth: 380
    popoutHeight: 540

    property string host: pluginData.host || "localhost"
    property int port: Number(pluginData.port || 25885)
    property bool preferWordLyrics: pluginData.preferWordLyrics === undefined ? true : pluginData.preferWordLyrics
    property bool showTranslation: pluginData.showTranslation || false
    property int lookaheadMs: Number(pluginData.lookaheadMs || 300)
    property int maxTextWidth: Number(pluginData.maxWidth || 320)
    property bool hideWhenDisconnected: pluginData.hideWhenDisconnected || false

    readonly property string socketUrl: "ws://" + host + ":" + port
    readonly property int compactIconSize: Math.round(Theme.iconSize * 0.6)
    readonly property int compactIconYOffset: 1
    readonly property int iconPillWidth: compactIconSize + 18
    readonly property int iconPillHeight: compactIconSize + 4
    readonly property bool connected: socket.status === WebSocket.Open
    readonly property bool connecting: socket.status === WebSocket.Connecting

    property bool isPlaying: false
    property string songName: ""
    property string artistName: ""
    property string albumName: ""
    property real syncedProgressMs: 0
    property real durationMs: 0
    property double progressAnchorMs: Date.now()
    property var lrcData: []
    property var yrcData: []
    property string currentLyric: ""
    property int reconnectAttempt: 0
    property bool intentionalReconnect: false
    property bool _forceUpdate: false

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string currentTitle: activePlayer ? activePlayer.trackTitle : ""
    readonly property string currentArtist: activePlayer ? activePlayer.trackArtist : ""
    readonly property string currentAlbum: activePlayer ? activePlayer.trackAlbum : ""
    readonly property real currentDuration: activePlayer ? activePlayer.length : 0

    Component.onCompleted: {
        updateVisibilityOverride();
        reconnectSoon(0);
    }

    Component.onDestruction: {
        socket.active = false;
    }

    onSocketUrlChanged: reconnectSoon(0)
    onHideWhenDisconnectedChanged: updateVisibilityOverride()
    onConnectedChanged: updateVisibilityOverride()
    onPreferWordLyricsChanged: updateCurrentLyric()
    onShowTranslationChanged: updateCurrentLyric()
    onLookaheadMsChanged: updateCurrentLyric()

    function updateVisibilityOverride() {
        if (hideWhenDisconnected && !connected)
            setVisibilityOverride(false);
        else
            clearVisibilityOverride();
    }

    function reconnectSoon(delayMs) {
        intentionalReconnect = true;
        socket.active = false;
        reconnectTimer.interval = Math.max(1, delayMs);
        reconnectTimer.restart();
    }

    function scheduleReconnect() {
        reconnectAttempt += 1;
        var delay = Math.min(10000, Math.pow(2, Math.min(reconnectAttempt, 4) - 1) * 1000);
        reconnectSoon(delay);
    }

    function sendJson(message) {
        if (socket.status !== WebSocket.Open)
            return;
        socket.sendTextMessage(JSON.stringify(message));
    }

    function resetPlaybackData() {
        isPlaying = false;
        songName = "";
        artistName = "";
        albumName = "";
        syncedProgressMs = 0;
        durationMs = 0;
        progressAnchorMs = Date.now();
        lrcData = [];
        yrcData = [];
        currentLyric = "";
    }

    function handleMessage(rawMessage) {
        if (rawMessage === "PONG")
            return;

        var message = null;
        try {
            message = JSON.parse(rawMessage);
        } catch (error) {
            console.warn("SPlayerLyrics: ignored invalid WebSocket message", error);
            return;
        }

        var data = message.data || {};
        if (message.type === "song-info") {
            handleSongInfo(data);
        } else if (message.type === "song-change") {
            handleSongChange(data);
        } else if (message.type === "lyric-change") {
            lrcData = data.lrcData || [];
            yrcData = data.yrcData || [];
            updateCurrentLyric();
        } else if (message.type === "progress-change") {
            setProgressMs(Number(data.currentTime || 0));
            if (data.duration !== undefined)
                durationMs = Number(data.duration || 0);
        } else if (message.type === "status-change") {
            isPlaying = !!data.status;
            progressAnchorMs = Date.now();
            updateCurrentLyric();
        } else if (message.type === "welcome") {
            sendJson({ type: "get-song-info" });
        } else if (message.type === "control-response") {
            refreshSongInfoTimer.restart();
        } else if (message.type === "error") {
            console.warn("SPlayerLyrics: SPlayer WebSocket error:", data.message || "unknown error");
        }
    }

    function handleSongInfo(data) {
        songName = data.playName || data.name || "";
        artistName = data.artistName || data.artists || "";
        albumName = data.albumName || data.album || "";
        isPlaying = data.playStatus === "play" || data.playStatus === true;
        lrcData = data.lrcData || [];
        yrcData = data.yrcData || [];
        durationMs = normalizeTimeMs(data.duration || 0);

        var currentTime = Number(data.currentTime || 0);
        if (currentTime > 0 && currentTime < 100000)
            currentTime *= 1000;
        setProgressMs(currentTime);
    }

    function handleSongChange(data) {
        songName = data.name || "";
        artistName = data.artist || "";
        albumName = data.album || "";
        durationMs = Number(data.duration || 0);
        syncedProgressMs = 0;
        progressAnchorMs = Date.now();
        lrcData = [];
        yrcData = [];
        currentLyric = "";
        refreshSongInfoTimer.restart();
    }

    function normalizeTimeMs(value) {
        var time = Number(value || 0);
        if (time > 0 && time < 100000)
            time *= 1000;
        return Math.max(0, time);
    }

    function setProgressMs(value) {
        syncedProgressMs = Math.max(0, value);
        progressAnchorMs = Date.now();
        updateCurrentLyric();
    }

    function adjustedTimeMs() {
        var elapsed = isPlaying ? Date.now() - progressAnchorMs : 0;
        return syncedProgressMs + elapsed + lookaheadMs;
    }

    function activeLyrics() {
        if (preferWordLyrics && yrcData && yrcData.length > 0)
            return yrcData;
        return lrcData || [];
    }

    function lineText(line) {
        if (!line)
            return "";

        var text = "";
        var words = line.words || [];
        for (var i = 0; i < words.length; i++)
            text += words[i].word || "";

        if (!text)
            text = line.lyric || line.text || "";

        if (showTranslation && line.translatedLyric)
            text += " / " + line.translatedLyric;

        return text.trim();
    }

    function currentLyricLineIndex() {
        var lyrics = activeLyrics();
        if (!lyrics || lyrics.length === 0)
            return -1;

        var time = adjustedTimeMs();
        var fallbackIndex = -1;
        for (var i = 0; i < lyrics.length; i++) {
            var line = lyrics[i];
            var startTime = Number(line.startTime || 0);
            var endTime = Number(line.endTime || 0);
            if (endTime <= startTime) {
                var nextLine = lyrics[i + 1];
                endTime = nextLine ? Number(nextLine.startTime || startTime + 10000) : startTime + 10000;
            }

            if (time >= startTime && time < endTime)
                return i;
            if (time >= startTime)
                fallbackIndex = i;
        }

        return fallbackIndex;
    }

    function currentLyricLine() {
        var lyrics = activeLyrics();
        var index = currentLyricLineIndex();
        if (!lyrics || index < 0 || index >= lyrics.length)
            return null;
        return lyrics[index];
    }

    function nextLyricLine() {
        var lyrics = activeLyrics();
        var index = currentLyricLineIndex();
        if (!lyrics || index < 0 || index + 1 >= lyrics.length)
            return null;
        return lyrics[index + 1];
    }

    function hasWordTiming(line) {
        if (!line || !line.words || line.words.length === 0)
            return false;

        for (var i = 0; i < line.words.length; i++) {
            var word = line.words[i];
            var startTime = Number(word.startTime || 0);
            var endTime = Number(word.endTime || 0);
            if ((word.word || "") !== "" && endTime > startTime)
                return true;
        }

        return false;
    }

    function currentWordIndex(line) {
        if (!hasWordTiming(line))
            return -1;

        var time = adjustedTimeMs();
        var index = -1;
        for (var i = 0; i < line.words.length; i++) {
            var word = line.words[i];
            var startTime = Number(word.startTime || 0);
            var endTime = Number(word.endTime || 0);
            if (endTime <= startTime)
                continue;
            if (time >= startTime && time < endTime)
                return i;
            if (time >= endTime)
                index = i;
        }

        return index;
    }

    function updateCurrentLyric() {
        var lyrics = activeLyrics();
        if (!lyrics || lyrics.length === 0) {
            currentLyric = "";
            return;
        }

        var time = adjustedTimeMs();
        var fallback = "";
        for (var i = 0; i < lyrics.length; i++) {
            var line = lyrics[i];
            var startTime = Number(line.startTime || 0);
            var endTime = Number(line.endTime || 0);
            if (endTime <= startTime) {
                var nextLine = lyrics[i + 1];
                endTime = nextLine ? Number(nextLine.startTime || startTime + 10000) : startTime + 10000;
            }

            if (time >= startTime && time < endTime) {
                currentLyric = lineText(line);
                return;
            }

            if (time >= startTime)
                fallback = lineText(line);
        }

        currentLyric = fallback;
    }

    function displayText() {
        if (!connected)
            return connecting ? "SPlayer 连接中" : "SPlayer 未连接";
        if (currentLyric)
            return currentLyric;
        if (songName && artistName)
            return songName + " - " + artistName;
        if (songName)
            return songName;
        return "SPlayer";
    }

    function formatSeconds(seconds) {
        if (!seconds || seconds <= 0)
            return "0:00";
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = Math.floor(seconds % 60);
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }

    function playerAction(action) {
        if (!connected)
            return;

        sendJson({
            type: "control",
            data: {
                command: action
            }
        });
        refreshSongInfoTimer.restart();
    }

    Timer {
        id: reconnectTimer
        repeat: false
        onTriggered: {
            if (socket.status !== WebSocket.Open) {
                socket.url = root.socketUrl;
                intentionalReconnect = false;
                socket.active = true;
            }
        }
    }

    Timer {
        id: refreshSongInfoTimer
        interval: 450
        repeat: false
        onTriggered: sendJson({ type: "get-song-info" })
    }

    Timer {
        interval: 200
        repeat: true
        running: root.connected && root.isPlaying
        onTriggered: root.updateCurrentLyric()
    }

    Timer {
        interval: 100
        repeat: true
        running: root.connected && root.isPlaying && root.hasWordTiming(root.currentLyricLine())
        onTriggered: root._forceUpdate = !root._forceUpdate
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.connected
        onTriggered: socket.sendTextMessage("PING")
    }

    WebSocket {
        id: socket
        active: false

        onStatusChanged: {
            if (status === WebSocket.Open) {
                reconnectAttempt = 0;
                sendJson({ type: "get-song-info" });
            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                resetPlaybackData();
                if (!intentionalReconnect)
                    scheduleReconnect();
            }
        }

        onTextMessageReceived: message => root.handleMessage(message)
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            TextMetrics {
                id: displayMetrics
                text: root.displayText()
                font.pixelSize: Theme.fontSizeSmall
            }

            Item {
                width: root.iconPillWidth
                height: root.iconPillHeight
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.connected ? Theme.primary : Theme.surfaceVariantText
                }

                DankIcon {
                    name: root.connected ? "lyrics" : "music_off"
                    size: root.compactIconSize
                    color: "#ffffff"
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.compactIconYOffset
                }
            }

            StyledText {
                text: root.displayText()
                width: Math.min(displayMetrics.advanceWidth + 2, root.maxTextWidth)
                font.pixelSize: Theme.fontSizeSmall
                color: root.connected ? Theme.surfaceText : Theme.surfaceVariantText
                elide: Text.ElideRight
                maximumLineCount: 1
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Item {
                width: root.widgetThickness
                height: root.iconPillHeight + root.compactIconYOffset * 2

                Rectangle {
                    width: Math.min(root.iconPillWidth, parent.width)
                    height: root.iconPillHeight
                    radius: height / 2
                    color: root.connected ? Theme.primary : Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.compactIconYOffset

                    DankIcon {
                        name: root.connected ? "lyrics" : "music_off"
                        size: root.compactIconSize
                        color: "#ffffff"
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: root.compactIconYOffset
                    }
                }
            }

            Item {
                id: verticalLyricClip

                width: root.widgetThickness
                height: 72
                clip: true

                readonly property string displayText: root.currentLyric ? root.currentLyric : "SPlayer"
                readonly property real overflow: Math.max(0, verticalText.implicitHeight - height)

                onDisplayTextChanged: {
                    verticalText.y = 0;
                    scrollAnim.restart();
                }

                StyledText {
                    id: verticalText

                    text: verticalLyricClip.displayText
                    width: parent.width
                    y: 0

                    font.pixelSize: Math.max(8, Theme.fontSizeSmall - 1)
                    color: root.connected ? Theme.surfaceText : Theme.surfaceVariantText
                    wrapMode: Text.WrapAnywhere
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 8
                }

                SequentialAnimation {
                    id: scrollAnim
                    running: verticalLyricClip.overflow > 0
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: 900
                    }

                    NumberAnimation {
                        target: verticalText
                        property: "y"
                        to: -verticalLyricClip.overflow
                        duration: Math.max(1600, verticalLyricClip.overflow * 70)
                        easing.type: Easing.InOutQuad
                    }

                    PauseAnimation {
                        duration: 900
                    }

                    NumberAnimation {
                        target: verticalText
                        property: "y"
                        to: 0
                        duration: 250
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "SPlayerLyrics"

            Item {
                width: parent.width
                implicitHeight: nowPlayingCard.height + controlsCard.height + lyricCard.height + connectionCard.height + Theme.spacingM * 3

                Rectangle {
                    id: nowPlayingCard

                    width: parent.width
                    height: nowPlayingContent.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.connected ? Theme.withAlpha(Theme.primary, 0.08) : Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)

                    Row {
                        id: nowPlayingContent

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Theme.spacingM
                        }
                        spacing: Theme.spacingM

                        Column {
                            width: coverControls.visible ? parent.width - coverControls.width - parent.spacing : parent.width
                            spacing: Theme.spacingS

                            Row {
                                spacing: Theme.spacingS
                                width: parent.width

                                DankIcon {
                                    name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "play_circle" : "pause_circle"
                                    size: 20
                                    color: root.activePlayer ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.activePlayer ? "Now Playing - " + (root.activePlayer.identity || "Unknown Player") : "No Active Player"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: root.activePlayer ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: root.currentTitle || "-"
                                font.pixelSize: Theme.fontSizeLarge + 2
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                visible: root.activePlayer
                            }

                            Column {
                                width: parent.width
                                spacing: 2
                                visible: root.activePlayer

                                Row {
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: "person"
                                        size: 14
                                        color: Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: root.currentArtist || "Unknown Artist"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                    }
                                }

                                Row {
                                    spacing: Theme.spacingXS
                                    visible: root.currentAlbum !== ""

                                    DankIcon {
                                        name: "album"
                                        size: 14
                                        color: Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: root.currentAlbum
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                visible: root.activePlayer && root.currentDuration > 0

                                DankSeekbar {
                                    id: progressSeekbar

                                    width: parent.width
                                    height: 20
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    activePlayer: root.activePlayer
                                }

                                Timer {
                                    interval: 50
                                    running: root.activePlayer !== null
                                    repeat: true
                                    onTriggered: {
                                        if (progressSeekbar && root.activePlayer) {
                                            try {
                                                var pos = root.activePlayer.position || 0;
                                                var len = Math.max(1, root.activePlayer.length || 1);
                                                progressSeekbar.value = Math.min(1, pos / len);
                                            } catch (error) {
                                            }
                                        }
                                        root._forceUpdate = !root._forceUpdate;
                                    }
                                }

                                Row {
                                    width: parent.width

                                    StyledText {
                                        id: currentTime

                                        text: {
                                            void root._forceUpdate;
                                            if (!root.activePlayer)
                                                return "0:00";
                                            var rawPos = Math.max(0, root.activePlayer.position || 0);
                                            var pos = root.activePlayer.length ? rawPos % Math.max(1, root.activePlayer.length) : rawPos;
                                            return root.formatSeconds(pos);
                                        }
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: Theme.surfaceVariantText
                                    }

                                    Item {
                                        width: Math.max(0, parent.width - currentTime.implicitWidth - endTime.implicitWidth)
                                        height: 1
                                    }

                                    StyledText {
                                        id: endTime

                                        text: root.activePlayer && root.activePlayer.length ? root.formatSeconds(Math.max(0, root.activePlayer.length || 0)) : "0:00"
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        Column {
                            id: coverControls

                            width: 88
                            spacing: Theme.spacingS
                            visible: root.activePlayer
                            anchors.verticalCenter: parent.verticalCenter

                            DankAlbumArt {
                                id: coverArt

                                width: 80
                                height: 80
                                visible: root.activePlayer && (root.activePlayer.trackArtUrl || "") !== ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                activePlayer: root.activePlayer
                                showAnimation: true
                            }

                            Item {
                                width: 80
                                height: 80
                                visible: !coverArt.visible
                                anchors.horizontalCenter: parent.horizontalCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.primary, 0.10)
                                }

                                DankIcon {
                                    name: "music_note"
                                    size: 30
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                }
                            }

                        }
                    }
                }

                Rectangle {
                    id: controlsCard

                    width: parent.width
                    height: 58
                    y: nowPlayingCard.height + Theme.spacingM
                    radius: Theme.cornerRadius
                    color: root.connected ? Theme.withAlpha(Theme.primary, 0.08) : Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingL

                        Rectangle {
                            width: 34
                            height: 34
                            radius: height / 2
                            color: previousMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"
                            opacity: root.connected ? 1 : 0.45
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                name: "skip_previous"
                                size: 22
                                color: Theme.primary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: previousMouse

                                anchors.fill: parent
                                enabled: root.connected
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playerAction("prev")
                            }
                        }

                        Rectangle {
                            width: 42
                            height: 42
                            radius: height / 2
                            color: root.connected ? Theme.primary : Theme.surfaceVariantText
                            opacity: root.connected ? 1 : 0.45
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                name: root.isPlaying ? "pause" : "play_arrow"
                                size: 26
                                color: "#ffffff"
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.connected
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playerAction("toggle")
                            }
                        }

                        Rectangle {
                            width: 34
                            height: 34
                            radius: height / 2
                            color: nextMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"
                            opacity: root.connected ? 1 : 0.45
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                name: "skip_next"
                                size: 22
                                color: Theme.primary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: nextMouse

                                anchors.fill: parent
                                enabled: root.connected
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playerAction("next")
                            }
                        }
                    }
                }

                Rectangle {
                    id: lyricCard

                    width: parent.width
                    height: 100
                    y: controlsCard.y + controlsCard.height + Theme.spacingM
                    radius: Theme.cornerRadius
                    color: root.connected ? Theme.withAlpha(Theme.primary, 0.06) : Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "lyrics"
                                size: 18
                                color: root.connected ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Current Lyric"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: root.connected ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Column {
                            id: lyricContent

                            width: parent.width
                            spacing: Theme.spacingXS

                            readonly property var activeLine: {
                                void root._forceUpdate;
                                return root.currentLyricLine();
                            }
                            readonly property var followingLine: {
                                void root._forceUpdate;
                                return root.nextLyricLine();
                            }
                            readonly property bool showWordLyrics: root.hasWordTiming(activeLine)
                            readonly property int activeWordIndex: {
                                void root._forceUpdate;
                                return root.currentWordIndex(activeLine);
                            }

                            Flow {
                                id: wordFlow

                                width: parent.width
                                spacing: 0
                                visible: lyricContent.showWordLyrics

                                Repeater {
                                    model: lyricContent.activeLine && lyricContent.activeLine.words ? lyricContent.activeLine.words : []

                                    StyledText {
                                        readonly property int wordStartTime: Number(modelData.startTime || 0)
                                        readonly property int wordEndTime: Number(modelData.endTime || 0)
                                        readonly property bool hasTiming: wordEndTime > wordStartTime
                                        readonly property bool isPast: {
                                            void root._forceUpdate;
                                            return hasTiming && wordEndTime <= root.adjustedTimeMs();
                                        }
                                        readonly property bool isCurrent: hasTiming && index === lyricContent.activeWordIndex

                                        text: modelData.word || ""
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: isPast || isCurrent ? Font.Bold : Font.Normal
                                        color: isPast || isCurrent ? Theme.primary : Theme.surfaceText
                                    }
                                }
                            }

                            StyledText {
                                width: parent.width
                                visible: !lyricContent.showWordLyrics
                                text: root.currentLyric || (root.connected ? "Waiting for lyrics..." : "SPlayer disconnected")
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.connected ? Theme.surfaceText : Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                visible: lyricContent.followingLine !== null && lyricContent.showWordLyrics
                                text: root.lineText(lyricContent.followingLine)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rectangle {
                    id: connectionCard

                    width: parent.width
                    height: 92
                    y: lyricCard.y + lyricCard.height + Theme.spacingM
                    radius: Theme.cornerRadius
                    color: root.connected ? Theme.withAlpha(Theme.primary, 0.06) : Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.connected ? "wifi" : "wifi_off"
                                size: 18
                                color: root.connected ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.connected ? "Connected" : (root.connecting ? "Connecting" : "Disconnected")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: root.connected ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: "WebSocket: " + root.socketUrl
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        StyledText {
                            width: parent.width
                            text: "Control: WebSocket control"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }
        }
    }

}

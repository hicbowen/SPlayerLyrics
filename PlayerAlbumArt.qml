/*
 * Adapted from Dux Shell v1.6.3's DankAlbumArt.qml.
 * MIT License
 * Copyright (c) 2025 Avenge Media LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property MprisPlayer activePlayer
    property string artUrl: ""
    property color accentColor: Theme.primary
    property string lastValidArtUrl: ""
    readonly property string rawArtUrl: {
        const player = activePlayer;
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;
        const metadata = player.metadata;
        return metadata && metadata["mpris:artUrl"] ? metadata["mpris:artUrl"].toString() : "";
    }
    readonly property string curArt: artUrl || lastValidArtUrl || rawArtUrl
    property string _prevArt: ""
    property bool _fadePending: false
    property string _srcOverride: ""
    readonly property string _mainSrc: _srcOverride !== "" ? _srcOverride : curArt
    readonly property int albumArtStatus: mainArt.imageStatus
    property real albumSize: Math.min(width, height) * 0.88
    property bool showAnimation: true
    property real animationScale: 1.0

    readonly property bool onScreen: visible && (Window.window?.visible ?? false)
    readonly property bool playing: activePlayer?.playbackState === MprisPlaybackState.Playing

    onActivePlayerChanged: lastValidArtUrl = ""

    onCurArtChanged: {
        _srcOverride = "";
        if (_prevArt !== "" && _prevArt !== curArt) {
            fadeArt.imageSource = _prevArt;
            fadeArt.opacity = 1;
            _fadePending = true;
            fadeSafety.restart();
            Qt.callLater(_maybeStartFade);
        }
        _prevArt = curArt;
    }

    function _maybeStartFade() {
        if (!_fadePending)
            return;
        if (mainArt.imageStatus !== Image.Ready && mainArt.imageStatus !== Image.Error)
            return;
        _fadePending = false;
        fadeSafety.stop();
        fadeOut.restart();
    }

    Timer {
        id: fadeSafety
        interval: 1200
        onTriggered: {
            if (root._fadePending) {
                root._fadePending = false;
                fadeOut.restart();
            }
        }
    }

    NumberAnimation {
        id: fadeOut
        target: fadeArt
        property: "opacity"
        from: 1
        to: 0
        duration: 300
        easing.type: Easing.InOutQuad
    }

    MediaBlobHalo {
        anchors.fill: parent
        z: 0
        accentColor: root.accentColor
        animationScale: root.animationScale
        playing: root.playing && root.showAnimation && root.albumArtStatus === Image.Ready
    }

    DankCircularImage {
        id: mainArt
        width: root.albumSize
        height: root.albumSize
        anchors.centerIn: parent
        z: 1
        imageSource: root._mainSrc
        fallbackIcon: "album"
        border.color: root.accentColor
        border.width: 2

        onImageStatusChanged: {
            if (imageStatus === Image.Ready && imageSource !== "")
                root.lastValidArtUrl = imageSource;
            else if (imageStatus === Image.Error && root._srcOverride === "" && root.rawArtUrl !== "" && root.rawArtUrl !== imageSource)
                root._srcOverride = root.rawArtUrl;
            root._maybeStartFade();
        }
    }

    Loader {
        readonly property bool wantsAnimatedArt: root.onScreen && root.playing && AppleMusicArtService.animatedArtUrl !== ""

        width: root.albumSize
        height: root.albumSize
        anchors.centerIn: parent
        z: 1
        active: wantsAnimatedArt && MultimediaService.available
        source: "file://" + Theme.shellDir + "/Widgets/DankAnimatedAlbumArt.qml"

        onWantsAnimatedArtChanged: {
            if (wantsAnimatedArt)
                MultimediaService.ensureProbed();
        }
    }

    DankCircularImage {
        id: fadeArt
        width: root.albumSize
        height: root.albumSize
        anchors.centerIn: parent
        z: 2
        fallbackIcon: ""
        border.color: root.accentColor
        border.width: 2
        opacity: 0
        visible: opacity > 0
    }
}

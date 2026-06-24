import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "splayerLyrics"

    StyledText {
        width: parent.width
        text: "SPlayerLyrics"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Connect to SPlayer's local WebSocket API and show the current lyric in DankBar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "host"
        label: "Host"
        description: "SPlayer WebSocket host."
        placeholder: "localhost"
        defaultValue: "localhost"
    }

    StringSetting {
        settingKey: "port"
        label: "Port"
        description: "SPlayer WebSocket port. The default is 25885."
        placeholder: "25885"
        defaultValue: "25885"
    }

    ToggleSetting {
        settingKey: "preferWordLyrics"
        label: "Prefer Word Lyrics"
        description: "Use SPlayer yrcData when available, otherwise fall back to lrcData."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showTranslation"
        label: "Show Translation"
        description: "Append translated lyrics when SPlayer provides them."
        defaultValue: false
    }

    SliderSetting {
        settingKey: "lookaheadMs"
        label: "Lyric Lookahead"
        description: "Advance lyric matching slightly to compensate for display latency."
        minimum: 0
        maximum: 1000
        defaultValue: 300
        unit: "ms"
    }

    SliderSetting {
        settingKey: "maxWidth"
        label: "Maximum Bar Width"
        description: "Clamp lyric text width so it does not stretch the bar."
        minimum: 120
        maximum: 640
        defaultValue: 320
        unit: "px"
    }

    ToggleSetting {
        settingKey: "hideWhenDisconnected"
        label: "Hide When Disconnected"
        description: "Hide the bar pill while SPlayer WebSocket is unavailable."
        defaultValue: false
    }
}

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "micControl"

    ToggleSetting {
        settingKey: "onlyWhenActive"
        label: I18n.trFor("micControl", "Auto-hide")
        description: I18n.trFor("micControl", "On: the icon only appears while an app is using the microphone (like KDE Plasma). Off: always visible.")
        defaultValue: true
    }
}

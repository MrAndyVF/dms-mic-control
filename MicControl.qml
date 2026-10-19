pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "mic-control"

    property bool onlyWhenActive: pluginData.onlyWhenActive ?? true

    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool muted: getMuted(source)

    // Physical and virtual inputs (EasyEffects source included)
    readonly property var inputs: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && (n.properties["media.class"] || "").startsWith("Audio/Source"))
        .sort((a, b) => (b === source) - (a === source))

    // easyeffects_source is a passthrough null sink: PipeWire ignores its own mute and volume.
    // Controls on it go to the physical mic EasyEffects reads from instead.
    property string eeInputDevice: ""

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/easyeffects/db/easyeffectsrc"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const content = text();
            const dev = content.match(/^inputDevice=(.*)$/m);
            root.eeInputDevice = /^useDefaultInputDevice=true$/m.test(content) || !dev ? "" : dev[1].trim();
        }
    }

    // Nodes whose audio really changes when this input is muted or adjusted
    function controlTargets(node) {
        if (!node)
            return [];
        if (node.audio)
            return [node];
        if (node.name !== "easyeffects_source")
            return [];
        const physical = inputs.filter(n => n.audio);
        const configured = physical.find(n => n.name === eeInputDevice);
        // EasyEffects set to follow the default input: we can't tell which mic it uses, so cover all
        return configured ? [configured] : physical;
    }

    function inputLabel(node) {
        const targets = controlTargets(node);
        const name = AudioService.displayName(node);
        return !node.audio && targets.length === 1 ? name + "  →  " + AudioService.displayName(targets[0]) : name;
    }

    function getMuted(node) {
        const targets = controlTargets(node);
        return targets.length > 0 && targets.every(n => n.audio.muted);
    }

    function getVolume(node) {
        return controlTargets(node)[0]?.audio.volume ?? 0;
    }

    function setMuted(node, value) {
        for (const n of controlTargets(node))
            n.audio.muted = value;
    }

    function setVolume(node, value) {
        for (const n of controlTargets(node))
            n.audio.volume = Math.max(0, Math.min(1, value));
    }

    readonly property var recorders: Pipewire.nodes.values.filter(n => (n.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream && !isInternalStream(n))
    readonly property bool inUse: recorders.length > 0

    // EasyEffects, cava and level meters read the mic all the time; they don't count as "in use"
    function isInternalStream(node) {
        const p = node.properties || {};
        const s = [node.name, p["application.name"], p["media.name"]].join(" ").toLowerCase();
        return /cava|easyeffects|^ee_|peak detect|monitor/.test(s);
    }

    function appName(node) {
        const p = node.properties || {};
        return p["application.name"] || p["media.name"] || node.name;
    }

    function toggleMute() {
        setMuted(source, !muted);
    }

    function changeVolume(step) {
        if (!source)
            return;
        setMuted(source, false);
        setVolume(source, getVolume(source) + step / 100);
    }

    // PluginComponent opens the popout on left click unless pillClickAction is set,
    // so the right click temporarily clears it to reuse the stock popout positioning.
    function openMenu() {
        const action = pillClickAction;
        pillClickAction = null;
        triggerPopout();
        pillClickAction = action;
    }

    // Hover-to-open would otherwise call pillClickAction and mute the mic
    function triggerHoverPopout(widgetHostId) {
    }

    readonly property bool shouldShow: !onlyWhenActive || inUse
    onShouldShowChanged: setVisibilityOverride(shouldShow)
    Component.onCompleted: setVisibilityOverride(shouldShow)

    PwObjectTracker {
        // Virtual nodes expose no properties until tracked, so track every non-stream node
        objects: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream).concat(root.recorders)
    }

    pillClickAction: () => root.toggleMute()
    pillRightClickAction: () => root.openMenu()

    horizontalBarPill: pillIcon
    verticalBarPill: pillIcon

    Component {
        id: pillIcon

        DankIcon {
            name: root.muted ? "mic_off" : "mic"
            size: root.iconSize
            color: root.muted ? (root.inUse ? Theme.error : Theme.surfaceVariantText) : (root.inUse ? Theme.primary : Theme.surfaceText)

            WheelHandler {
                onWheel: event => root.changeVolume(event.angleDelta.y > 0 ? 5 : -5)
            }
        }
    }

    popoutWidth: 400

    popoutContent: Component {
        PopoutComponent {
            headerText: I18n.trFor("micControl", "Microphone")
            detailsText: root.inUse ? I18n.trFor("micControl", "In use by: %1").arg(root.recorders.map(n => root.appName(n)).filter((v, i, a) => a.indexOf(v) === i).join(", ")) : I18n.trFor("micControl", "No app is using it")
            showCloseButton: true
            spacing: Theme.spacingS

            StyledText {
                text: I18n.trFor("micControl", "Inputs")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Repeater {
                model: root.inputs
                delegate: NodeRow {
                    required property var modelData
                    node: modelData
                    label: root.inputLabel(modelData)
                    isDefault: modelData === root.source
                    selectable: true
                }
            }

            StyledText {
                visible: root.inUse
                text: I18n.trFor("micControl", "Apps")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Repeater {
                model: root.recorders
                delegate: NodeRow {
                    required property var modelData
                    node: modelData
                    label: root.appName(modelData)
                    iconName: "graphic_eq"
                }
            }
        }
    }

    component NodeRow: Rectangle {
        id: row

        required property PwNode node
        property string label: ""
        property string iconName: "mic"
        property bool isDefault: false
        property bool selectable: false
        readonly property bool nodeMuted: root.getMuted(node)
        readonly property real nodeVolume: root.getVolume(node)

        width: parent?.width ?? 0
        implicitHeight: rowColumn.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: selectArea.containsMouse ? Theme.primaryHoverLight : Theme.surfaceLight
        border.color: isDefault ? Theme.primary : Theme.outlineLight
        border.width: isDefault ? 2 : 1

        // Clicking the card makes it the default input
        MouseArea {
            id: selectArea
            anchors.fill: parent
            enabled: row.selectable && !row.isDefault
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Pipewire.preferredDefaultAudioSource = row.node
        }

        Column {
            id: rowColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM

            StyledText {
                width: parent.width
                text: row.label + (row.isDefault ? "  ·  " + I18n.trFor("micControl", "Default") : "")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: row.isDefault ? Font.Medium : Font.Normal
                color: row.isDefault ? Theme.primary : Theme.surfaceText
                elide: Text.ElideRight
            }

            Row {
                width: parent.width

                DankActionButton {
                    id: muteButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: row.nodeMuted ? "mic_off" : row.iconName
                    iconColor: row.nodeMuted ? Theme.error : Theme.surfaceText
                    buttonSize: 32
                    iconSize: 18
                    onClicked: root.setMuted(row.node, !row.nodeMuted)
                }

                DankSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - muteButton.width
                    enabled: root.controlTargets(row.node).length > 0
                    minimum: 0
                    maximum: 100
                    value: Math.min(100, Math.round(row.nodeVolume * 100))
                    valueOverride: Math.round(row.nodeVolume * 100)
                    showValue: true
                    unit: "%"
                    thumbOutlineColor: Theme.surfaceVariant
                    trackColor: Theme.ccSliderTrackColor
                    trackOpacity: Theme.ccSliderTrackOpacity
                    onSliderValueChanged: newValue => {
                        root.setVolume(row.node, newValue / 100);
                        if (newValue > 0 && row.nodeMuted)
                            root.setMuted(row.node, false);
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Decenza

// Layout widget (Decenza-Descendant): the UGS grind suggestion for the current
// profile and active bean on the active equipment. Tapping opens GeniusGrindDialog
// to try another bean or profile and apply the result.
LayoutWidgetItem {
    id: root

    property var suggestion: ({})
    property var _activeBag: null

    readonly property string labelText: TranslationManager.translate("geniusGrind.label", "Genius Grind")
    readonly property string profileTitle: String(ProfileService.currentProfileSummary.title || "")
    readonly property string valueText: {
        const setting = String(root.suggestion.setting || "")
        if (setting.length === 0) return "—"
        return setting + (root.suggestion.basis === "auto" ? "*" : "")
    }
    readonly property string requestKey: EquipmentService.activePackageId + "|" + BagService.activeBagId
                                          + "|" + root.profileTitle

    onRequestKeyChanged: BagService.requestInventory()
    Component.onCompleted: BagService.requestInventory()

    function requestSuggestion(): void {
        root.suggestion = ({})
        const bag = root._activeBag
        const packageId = EquipmentService.activePackageId
        if (!bag || root.profileTitle.length === 0 || packageId <= 0 || !EquipmentService.ready)
            return
        EquipmentService.requestGeniusSuggestion(packageId, String(bag.roasterName || ""),
                                                  String(bag.coffeeName || ""),
                                                  String(bag.roastDate || ""), root.profileTitle)
    }

    Connections {
        target: BagService
        function onInventoryReady(bags) {
            let found = null
            for (let i = 0; i < bags.length; ++i) {
                if (Number(bags[i].id) === Number(BagService.activeBagId)) found = bags[i]
            }
            root._activeBag = found
            root.requestSuggestion()
        }
        function onBagsChanged() {
            BagService.requestInventory()
        }
    }

    Connections {
        target: EquipmentService
        function onGeniusSuggestionReady(suggestion) {
            const bag = root._activeBag
            if (!bag || suggestion.packageId !== EquipmentService.activePackageId
                || suggestion.beanBrand !== String(bag.roasterName || "")
                || suggestion.beanType !== String(bag.coffeeName || "")
                || suggestion.roastDate !== String(bag.roastDate || "")
                || suggestion.profileTitle !== root.profileTitle)
                return
            root.suggestion = suggestion
        }
        function onGrindCalibrationChanged(packageId) {
            root.requestSuggestion()
        }
    }

    implicitWidth: root.isCompact ? col.implicitWidth : tile.implicitWidth
    implicitHeight: root.isCompact ? col.implicitHeight : tile.implicitHeight

    function openDialog(): void {
        geniusDialog.openFor(Number(BagService.activeBagId), root.profileTitle)
    }

    // --- Bars: label over value ---
    ColumnLayout {
        id: col
        visible: root.isCompact
        anchors.centerIn: parent
        width: parent.width
        spacing: 0
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.labelText
            color: root.zoneTextColor
            font: Theme.labelFont
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.valueText
            color: root.zoneTextColor
            font.pixelSize: Theme.scaled(21)
            font.bold: true
        }
    }

    AccessibleMouseArea {
        visible: root.isCompact
        anchors.fill: parent
        accessibleName: root.labelText + ": " + root.valueText
        onAccessibleClicked: root.openDialog()
    }

    // --- Centre: an action tile matching the compiled tiles (CustomItem full mode),
    // with the number where their icon sits ---
    Item {
        id: tile
        visible: !root.isCompact
        anchors.fill: parent
        implicitWidth: Math.max(Theme.scaled(150), tileLabel.implicitWidth + Theme.scaled(24))
        implicitHeight: Theme.scaled(120)

        readonly property color baseFill: root.zoneFillOverride.a > 0 ? root.zoneFillOverride
                                                                      : Theme.actionTileColor
        readonly property color fill: Theme.glassChrome ? Theme.chromeFill(tile.baseFill) : tile.baseFill
        readonly property color contentColor: Theme.contentColorOn(tile.fill, Theme.primaryContrastColor)

        Rectangle {
            anchors.fill: parent
            color: tileTap.isPressed ? Qt.darker(tile.fill, 1.2) : tile.fill
            radius: Theme.cardRadius
            border.width: Theme.hasBackgroundPreset ? 1 : 0
            border.color: Theme.borderColor
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingSmall

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: Theme.scaled(48)
                verticalAlignment: Text.AlignVCenter
                text: root.valueText
                color: tile.contentColor
                font.pixelSize: Theme.scaled(40)
                font.bold: true
                Accessible.ignored: true
            }
            Text {
                id: tileLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.labelText
                color: tile.contentColor
                font: Theme.bodyFont
                Accessible.ignored: true
            }
        }

        AccessibleTapHandler {
            id: tileTap
            anchors.fill: parent
            accessibleName: root.labelText + ": " + root.valueText
            onAccessibleClicked: root.openDialog()
        }
    }

    GeniusGrindDialog {
        id: geniusDialog
    }
}

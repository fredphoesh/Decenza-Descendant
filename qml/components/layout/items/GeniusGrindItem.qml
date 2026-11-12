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
    readonly property string valueText: String(root.suggestion.setting || "") || "—"
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
        EquipmentService.requestGrindSuggestion(packageId, String(bag.roasterName || ""),
                                                String(bag.coffeeName || ""),
                                                String(bag.roastDate || ""), root.profileTitle)
    }

    Connections {
        target: BagService
        function onInventoryReady(bags) {
            let found = null
            for (let i = 0; i < bags.length; ++i) {
                if (bags[i].id === BagService.activeBagId) found = bags[i]
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
        function onGrindSuggestionReady(suggestion) {
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

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
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
            font.families: Theme.fontFamilies
            font.pixelSize: Theme.scaled(root.isCompact ? 21 : 32)
            font.bold: true
        }
    }

    AccessibleMouseArea {
        anchors.fill: parent
        accessibleName: root.labelText + ": " + root.valueText
        onAccessibleClicked: geniusDialog.openFor(BagService.activeBagId, root.profileTitle)
    }

    GeniusGrindDialog {
        id: geniusDialog
    }
}

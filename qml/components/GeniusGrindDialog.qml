pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Decenza

// Genius Grind (Decenza-Descendant): the UGS grind suggestion for a chosen bean and
// profile on the active equipment, with Apply to load both and set the grind.
// The suggestion itself is EquipmentService.requestGeniusSuggestion, built on the same
// calibrated UGS engine the recipe wizard uses.
DecenzaDialog {
    id: root

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - Theme.scaled(40) : Theme.scaled(420), Theme.scaled(460))
    modal: true
    padding: 0
    header: null
    footer: null
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var bags: []
    property var profileTitles: []
    property double bagId: -1
    property string profileTitle: ""
    property var suggestion: ({})
    property bool suggestionPending: false
    // Which choice list is open in place: "", "bean" or "profile".
    property string expanded: ""

    // Apply runs bag activation, then profile load, then the grind write.
    property bool applying: false
    property double _pendingBagId: -1
    property string _pendingProfileRequest: ""
    property string _pendingGrindRequest: ""
    property string _applySetting: ""

    readonly property var selectedBag: {
        for (let i = 0; i < root.bags.length; ++i) {
            if (Number(root.bags[i].id) === root.bagId) return root.bags[i]
        }
        return null
    }
    readonly property string suggestedSetting: String(root.suggestion.setting || "")
    // A star marks a number not backed by a reference or rated shot.
    readonly property string displaySetting: root.suggestedSetting.length === 0 ? "—"
        : root.suggestedSetting + (root.suggestion.basis === "auto" ? "*" : "")

    function bagLabel(bag: var): string {
        if (!bag) return ""
        const coffee = String(bag.coffeeName || "")
        const roaster = String(bag.roasterName || "")
        if (coffee.length > 0 && roaster.length > 0) return roaster + " · " + coffee
        return coffee.length > 0 ? coffee : roaster
    }

    function chartedProfileTitles(): var {
        const directions = ProfileService.grindDirections
        const profiles = ProfileService.availableProfiles
        const out = []
        const seen = {}
        for (let i = 0; i < profiles.length; ++i) {
            const title = String(profiles[i].title || "")
            if (title.length === 0 || seen[title]) continue
            if (directions[title] === undefined && title !== root.profileTitle) continue
            seen[title] = true
            out.push(title)
        }
        out.sort(function(a, b) { return a.localeCompare(b) })
        return out
    }

    function openFor(currentBagId: double, currentProfileTitle: string): void {
        root.bagId = currentBagId
        root.profileTitle = currentProfileTitle
        root.profileTitles = root.chartedProfileTitles()
        root.suggestion = ({})
        root.applying = false
        root.expanded = ""
        BagService.requestInventory()
        root.open()
        root.requestSuggestion()
    }

    function requestSuggestion(): void {
        root.suggestion = ({})
        const bag = root.selectedBag
        const packageId = EquipmentService.activePackageId
        if (!bag || root.profileTitle.length === 0 || packageId <= 0 || !EquipmentService.ready) {
            root.suggestionPending = false
            return
        }
        root.suggestionPending = true
        EquipmentService.requestGeniusSuggestion(packageId, String(bag.roasterName || ""),
                                                  String(bag.coffeeName || ""),
                                                  String(bag.roastDate || ""), root.profileTitle)
    }

    function statusText(): string {
        if (root.suggestionPending)
            return TranslationManager.translate("geniusGrind.working", "Working it out…")
        if (EquipmentService.activePackageId <= 0)
            return TranslationManager.translate("geniusGrind.noEquipment", "Set up your grinder under Equipment first")
        if (!root.selectedBag)
            return TranslationManager.translate("geniusGrind.noBean", "Choose a bean")
        if (root.suggestedSetting.length === 0) {
            switch (String(root.suggestion.reason || "")) {
            case "profileNotOnChart":
                return TranslationManager.translate("geniusGrind.reason.profileNotOnChart",
                    "This profile is not on the UGS chart.")
            case "notCalibrated":
                return TranslationManager.translate("geniusGrind.reason.notCalibrated",
                    "Your grinder's span is not calibrated yet. Mark a fine and a coarse anchor shot of one bean.")
            case "outsideRange":
                return TranslationManager.translate("geniusGrind.reason.outsideRange",
                    "This profile is outside the range your anchors cover.")
            default:
                return TranslationManager.translate("geniusGrind.reason.noReference",
                    "No reference shot for this bean yet. On the review screen of a shot you are happy with, tap \"Use as bean reference\".")
            }
        }
        const anchorName = String(root.suggestion.anchorProfileName || "")
        const anchorSetting = String(root.suggestion.anchorSetting || "")
        const shot = anchorName.length > 0 && anchorSetting.length > 0 ? anchorName + " @ " + anchorSetting : ""
        switch (String(root.suggestion.basis || "")) {
        case "reference":
            return TranslationManager.translate("geniusGrind.basis.reference", "Based on your reference shot: %1").arg(shot)
        case "rating":
            return TranslationManager.translate("geniusGrind.basis.rating",
                "Based on your best-rated shot: %1. No reference shot for this bean yet.").arg(shot)
        default:
            return TranslationManager.translate("geniusGrind.basis.auto",
                "* There is no reference shot for this bean. Based on Decenza's automatic choice: %1").arg(shot)
        }
    }

    function startApply(): void {
        if (root.suggestedSetting.length === 0 || !root.selectedBag) return
        root.applying = true
        root._applySetting = root.suggestedSetting
        if (root.bagId !== BagService.activeBagId) {
            root._pendingBagId = root.bagId
            BagService.requestActivateBag(root.bagId)
        } else {
            root.applyProfile()
        }
    }

    function applyProfile(): void {
        if (root.profileTitle !== String(ProfileService.currentProfileSummary.title || "")) {
            const filename = ProfileService.findProfileByTitle(root.profileTitle)
            if (filename.length > 0) {
                root._pendingProfileRequest = ProfileService.loadProfile(filename)
                if (root._pendingProfileRequest.length > 0) return
            }
            root.failApply()
            return
        }
        root.applyGrind()
    }

    function applyGrind(): void {
        if (!RecipeContext.ready) {
            root.failApply()
            return
        }
        root._pendingGrindRequest = RecipeContext.newRequestId()
        RecipeContext.setPreference(root._pendingGrindRequest, "grindDialIn",
                                    { "dyeGrinderSetting": root._applySetting },
                                    RecipeContext.revision)
    }

    function failApply(): void {
        root.applying = false
        root._pendingBagId = -1
        root._pendingProfileRequest = ""
        root._pendingGrindRequest = ""
        HomePresetActions.failed(TranslationManager.translate(
            "idle.operationFailed", "The selection could not be changed. Please try again."))
    }

    onClosed: {
        root.applying = false
        root._pendingBagId = -1
        root._pendingProfileRequest = ""
        root._pendingGrindRequest = ""
    }

    Connections {
        target: BagService
        function onInventoryReady(bags) {
            root.bags = bags
            // No active bean, or it is gone: start from the most recently used one.
            if (!root.selectedBag && bags.length > 0) root.bagId = Number(bags[0].id)
            if (root.visible && !root.suggestionPending && root.suggestedSetting.length === 0)
                root.requestSuggestion()
        }
        function onBagActivated(bagId, success, bag, reason) {
            if (!root.applying || bagId !== root._pendingBagId) return
            root._pendingBagId = -1
            if (success) root.applyProfile()
            else root.failApply()
        }
    }

    Connections {
        target: ProfileService
        function onOperationCompleted(requestId, operation, filename, success, reason, result) {
            if (!root.applying || requestId !== root._pendingProfileRequest) return
            root._pendingProfileRequest = ""
            if (success) root.applyGrind()
            else root.failApply()
        }
    }

    Connections {
        target: RecipeContext
        function onPreferenceCompleted(requestId, name, success, preferences, reason) {
            if (!root.applying || requestId !== root._pendingGrindRequest) return
            root._pendingGrindRequest = ""
            root.applying = false
            if (success) root.close()
            else root.failApply()
        }
    }

    Connections {
        target: EquipmentService
        function onGeniusSuggestionReady(suggestion) {
            const bag = root.selectedBag
            if (!bag || suggestion.packageId !== EquipmentService.activePackageId
                || suggestion.beanBrand !== String(bag.roasterName || "")
                || suggestion.beanType !== String(bag.coffeeName || "")
                || suggestion.roastDate !== String(bag.roastDate || "")
                || suggestion.profileTitle !== root.profileTitle)
                return
            root.suggestionPending = false
            root.suggestion = suggestion
        }
        function onGrindCalibrationChanged(packageId) {
            if (root.visible) root.requestSuggestion()
        }
    }

    background: Rectangle {
        color: Theme.surfaceColor
        radius: Theme.cardRadius
        border.width: 1
        border.color: Theme.primaryContrastColor
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMedium

        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.scaled(16)
            Layout.leftMargin: Theme.scaled(20)
            Layout.rightMargin: Theme.scaled(20)
            text: TranslationManager.translate("geniusGrind.title", "Genius Grind")
            font: Theme.titleFont
            color: Theme.textColor
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.displaySetting
            font.pixelSize: Theme.scaled(56)
            font.bold: true
            color: root.suggestedSetting.length > 0 ? Theme.primaryColor : Theme.textSecondaryColor
            Accessible.role: Accessible.StaticText
            Accessible.name: TranslationManager.translate("geniusGrind.suggestedGrind", "Suggested grind")
                             + ": " + (root.suggestedSetting.length > 0 ? root.suggestedSetting : root.statusText())
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.scaled(20)
            Layout.rightMargin: Theme.scaled(20)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: text.length > 0
            text: root.statusText()
            font: Theme.bodyFont
            color: Theme.textSecondaryColor
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.scaled(20)
            Layout.rightMargin: Theme.scaled(20)
            columns: 2
            columnSpacing: Theme.spacingMedium
            rowSpacing: Theme.scaled(8)

            Text {
                text: TranslationManager.translate("geniusGrind.bean", "Bean")
                font: Theme.labelFont
                color: Theme.textSecondaryColor
            }
            AccessibleButton {
                Layout.fillWidth: true
                text: root.selectedBag ? root.bagLabel(root.selectedBag)
                                       : TranslationManager.translate("geniusGrind.chooseBean", "Choose a bean")
                accessibleName: TranslationManager.translate("geniusGrind.changeBean", "Change bean") + ": " + text
                enabled: !root.applying
                onClicked: root.expanded = root.expanded === "bean" ? "" : "bean"
            }

            Text {
                text: TranslationManager.translate("geniusGrind.profile", "Profile")
                font: Theme.labelFont
                color: Theme.textSecondaryColor
            }
            AccessibleButton {
                Layout.fillWidth: true
                text: root.profileTitle.length > 0 ? root.profileTitle
                                                   : TranslationManager.translate("geniusGrind.chooseProfile", "Choose a profile")
                accessibleName: TranslationManager.translate("geniusGrind.changeProfile", "Change profile") + ": " + text
                enabled: !root.applying
                onClicked: root.expanded = root.expanded === "profile" ? "" : "profile"
            }
        }

        // The choices open in place: a picker popup over this popup did not reach
        // the screen on the user's Windows build.
        ListView {
            id: choiceList
            Layout.fillWidth: true
            Layout.leftMargin: Theme.scaled(20)
            Layout.rightMargin: Theme.scaled(20)
            Layout.preferredHeight: Math.min(contentHeight, Theme.scaled(260))
            visible: root.expanded !== ""
            clip: true
            spacing: Theme.scaled(4)
            model: root.expanded === "bean" ? root.bags
                 : root.expanded === "profile" ? root.profileTitles : []
            delegate: AccessibleButton {
                id: choice
                required property var modelData
                width: choiceList.width
                readonly property bool isBean: root.expanded === "bean"
                readonly property bool isCurrent: choice.isBean
                    ? Number(choice.modelData.id) === root.bagId
                    : String(choice.modelData) === root.profileTitle
                text: choice.isBean ? root.bagLabel(choice.modelData) : String(choice.modelData)
                accessibleName: choice.text
                primary: choice.isCurrent
                onClicked: {
                    if (choice.isBean) root.bagId = Number(choice.modelData.id)
                    else root.profileTitle = String(choice.modelData)
                    root.expanded = ""
                    root.requestSuggestion()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.scaled(20)
            Layout.rightMargin: Theme.scaled(20)
            Layout.bottomMargin: Theme.scaled(20)
            spacing: Theme.spacingMedium

            AccessibleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.scaled(50)
                text: TranslationManager.translate("common.button.cancel", "Cancel")
                accessibleName: TranslationManager.translate("geniusGrind.cancel", "Cancel without changes")
                onClicked: root.close()
            }
            AccessibleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.scaled(50)
                primary: true
                enabled: root.suggestedSetting.length > 0 && !root.applying
                text: TranslationManager.translate("geniusGrind.apply", "Apply")
                accessibleName: TranslationManager.translate("geniusGrind.applyDescription",
                    "Apply this bean, profile and grind")
                onClicked: root.startApply()
            }
        }
    }
}

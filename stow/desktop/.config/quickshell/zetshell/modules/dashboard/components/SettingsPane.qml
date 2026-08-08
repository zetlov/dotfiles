import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject fileSearchConfig: null
    readonly property var normalizedDraft: ({
        "roots": uniqueTrimmedStrings(draftRoots),
        "includeQuicklinkDirectories": draftIncludeQuicklinkDirectories,
        "exclude": uniqueTrimmedStrings(draftExclude),
        "excludeExtensions": normalizedExtensions(draftExcludeExtensions),
        "maxItems": normalizedPositiveInt(draftMaxItemsText, defaultMaxItems),
        "rootSearchMinQuery": normalizedNonNegativeInt(draftRootSearchMinQueryText, defaultRootSearchMinQuery)
    })
    readonly property string savedSnapshot: snapshotFor({
        "roots": fileSearchConfig && Array.isArray(fileSearchConfig.roots) ? fileSearchConfig.roots : [],
        "includeQuicklinkDirectories": fileSearchConfig ? !!fileSearchConfig.includeQuicklinkDirectories : true,
        "exclude": fileSearchConfig && Array.isArray(fileSearchConfig.exclude) ? fileSearchConfig.exclude : [],
        "excludeExtensions": fileSearchConfig && Array.isArray(fileSearchConfig.excludeExtensions) ? fileSearchConfig.excludeExtensions : [],
        "maxItems": fileSearchConfig ? fileSearchConfig.maxItems : defaultMaxItems,
        "rootSearchMinQuery": fileSearchConfig ? fileSearchConfig.rootSearchMinQuery : defaultRootSearchMinQuery
    })
    readonly property string draftSnapshot: snapshotFor(normalizedDraft)
    readonly property bool dirty: draftSnapshot !== savedSnapshot
    readonly property int defaultMaxItems: 15000
    readonly property int defaultRootSearchMinQuery: 2
    property var draftRoots: []
    property var draftExclude: []
    property var draftExcludeExtensions: []
    property bool draftIncludeQuicklinkDirectories: true
    property bool pendingServiceSync: false
    property string draftMaxItemsText: String(defaultMaxItems)
    property string draftRootSearchMinQueryText: String(defaultRootSearchMinQuery)

    function uniqueTrimmedStrings(values) {
        if (!Array.isArray(values))
            return [];

        const unique = [];
        for (const value of values) {
            const text = String(value || "").trim();
            if (!text || unique.indexOf(text) !== -1)
                continue;

            unique.push(text);
        }
        return unique;
    }

    function normalizedPositiveInt(text, fallbackValue) {
        const parsed = parseInt(String(text || ""), 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : fallbackValue;
    }

    function normalizedNonNegativeInt(text, fallbackValue) {
        const parsed = parseInt(String(text || ""), 10);
        return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallbackValue;
    }

    function snapshotFor(payload) {
        return JSON.stringify({
            "roots": uniqueTrimmedStrings(payload.roots),
            "includeQuicklinkDirectories": !!payload.includeQuicklinkDirectories,
            "exclude": uniqueTrimmedStrings(payload.exclude),
            "excludeExtensions": normalizedExtensions(payload.excludeExtensions),
            "maxItems": normalizedPositiveInt(payload.maxItems, defaultMaxItems),
            "rootSearchMinQuery": normalizedNonNegativeInt(payload.rootSearchMinQuery, defaultRootSearchMinQuery)
        });
    }

    function normalizedExtensions(values) {
        const normalized = [];
        for (const value of uniqueTrimmedStrings(values)) {
            let text = value.toLowerCase();
            if (!text.startsWith("."))
                text = "." + text;

            if (normalized.indexOf(text) !== -1)
                continue;

            normalized.push(text);
        }
        return normalized;
    }

    function syncDraftFromService() {
        if (!fileSearchConfig)
            return ;

        draftRoots = Array.isArray(fileSearchConfig.roots) ? fileSearchConfig.roots.slice() : [];
        draftExclude = Array.isArray(fileSearchConfig.exclude) ? fileSearchConfig.exclude.slice() : [];
        draftExcludeExtensions = Array.isArray(fileSearchConfig.excludeExtensions) ? fileSearchConfig.excludeExtensions.slice() : [];
        draftIncludeQuicklinkDirectories = !!fileSearchConfig.includeQuicklinkDirectories;
        draftMaxItemsText = String(fileSearchConfig.maxItems || defaultMaxItems);
        draftRootSearchMinQueryText = String(fileSearchConfig.rootSearchMinQuery !== undefined ? fileSearchConfig.rootSearchMinQuery : defaultRootSearchMinQuery);
        pendingServiceSync = false;
    }

    function syncDraftFromServiceIfAllowed() {
        if (pendingServiceSync || !dirty)
            syncDraftFromService();

    }

    function addRoot() {
        const text = rootInputRow.value.trim();
        if (!text)
            return ;

        draftRoots = draftRoots.concat([text]);
        rootInputRow.clear();
    }

    function removeRoot(index) {
        draftRoots = draftRoots.filter((_, itemIndex) => {
            return itemIndex !== index;
        });
    }

    function addExclude() {
        const text = excludeInputRow.value.trim();
        if (!text)
            return ;

        draftExclude = draftExclude.concat([text]);
        excludeInputRow.clear();
    }

    function removeExclude(index) {
        draftExclude = draftExclude.filter((_, itemIndex) => {
            return itemIndex !== index;
        });
    }

    function addExcludeExtension() {
        const text = excludeExtensionInputRow.value.trim();
        if (!text)
            return ;

        draftExcludeExtensions = draftExcludeExtensions.concat([text]);
        excludeExtensionInputRow.clear();
    }

    function removeExcludeExtension(index) {
        draftExcludeExtensions = draftExcludeExtensions.filter((_, itemIndex) => {
            return itemIndex !== index;
        });
    }

    function save() {
        if (!fileSearchConfig)
            return ;

        pendingServiceSync = true;
        fileSearchConfig.saveConfig(normalizedDraft);
    }

    function resetDraft() {
        syncDraftFromService();
    }

    Component.onCompleted: syncDraftFromService()
    radius: 20
    color: theme ? theme.cardColor : "transparent"
    border.width: 1
    border.color: theme ? theme.faintBorder : "transparent"
    clip: true

    Connections {
        function onRootsChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onExcludeChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onIncludeQuicklinkDirectoriesChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onExcludeExtensionsChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onMaxItemsChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onRootSearchMinQueryChanged() {
            if (!root.fileSearchConfig.saveBusy)
                root.syncDraftFromServiceIfAllowed();

        }

        function onSaveBusyChanged() {
            if (!root.fileSearchConfig.saveBusy && root.fileSearchConfig.saveError)
                root.pendingServiceSync = false;

        }

        target: root.fileSearchConfig
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 44
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: contentColumn

            width: parent.width
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            spacing: 16

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 92
                radius: 18
                color: root.theme.darkSurface
                border.width: 1
                border.color: root.dirty ? root.theme.attentionBorder : root.theme.faintBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: "File Search Settings"
                            color: root.theme.primaryText
                            font.pixelSize: 18
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.fileSearchConfig ? root.fileSearchConfig.saveBusy ? "Saving changes..." : root.fileSearchConfig.saveMessage.length > 0 ? root.fileSearchConfig.saveMessage : "Update roots, excludes, and root-search behavior for launcher file results." : "Loading configuration..."
                            color: root.fileSearchConfig && root.fileSearchConfig.saveError ? root.theme.dangerText : root.dirty ? root.theme.accentWarm : root.theme.mutedText
                            font.pixelSize: root.theme.fontSm
                            font.family: root.theme.fontFamilyMono
                            wrapMode: Text.Wrap
                        }

                    }

                    RowLayout {
                        spacing: 10

                        ActionButton {
                            label: "Reset"
                            enabled: root.dirty && !root.fileSearchConfig.saveBusy
                            accent: false
                            onClicked: root.resetDraft()
                        }

                        ActionButton {
                            label: root.fileSearchConfig && root.fileSearchConfig.saveBusy ? "Saving" : "Save"
                            enabled: root.dirty && !root.fileSearchConfig.saveBusy
                            accent: true
                            onClicked: root.save()
                        }

                    }

                }

            }

            SectionCard {
                Layout.fillWidth: true
                title: "Indexed Roots"
                detail: "Files are indexed from these directories. Use ~ paths to keep them portable."

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.draftRoots

                        delegate: ListChip {
                            required property string modelData

                            Layout.fillWidth: true
                            label: modelData
                            onRemoveClicked: root.removeRoot(index)
                        }

                    }

                    AddRow {
                        id: rootInputRow

                        placeholderText: "~/dotfiles"
                        onSubmit: root.addRoot()
                    }

                }

            }

            SectionCard {
                Layout.fillWidth: true
                title: "Index Behavior"
                detail: "Choose whether quicklink directories join the index and how aggressively files appear in root search."

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ToggleRow {
                        label: "Include Quicklink Directories"
                        description: "Directory quicklinks from quicklinks.json are added as index roots."
                        checked: root.draftIncludeQuicklinkDirectories
                        onToggled: root.draftIncludeQuicklinkDirectories = !root.draftIncludeQuicklinkDirectories
                    }

                    NumericRow {
                        label: "Max Indexed Items"
                        description: "Hard cap for indexed files and folders."
                        textValue: root.draftMaxItemsText
                        onValueEdited: (value) => {
                            return root.draftMaxItemsText = value;
                        }
                    }

                    NumericRow {
                        label: "Root Search Min Query"
                        description: "Minimum query length before files join the normal launcher results."
                        textValue: root.draftRootSearchMinQueryText
                        onValueEdited: (value) => {
                            return root.draftRootSearchMinQueryText = value;
                        }
                    }

                }

            }

            SectionCard {
                Layout.fillWidth: true
                title: "Excluded Directory Names"
                detail: "Any directory with these exact names is skipped while indexing."

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.draftExclude

                        delegate: ListChip {
                            required property string modelData

                            Layout.fillWidth: true
                            label: modelData
                            onRemoveClicked: root.removeExclude(index)
                        }

                    }

                    AddRow {
                        id: excludeInputRow

                        placeholderText: "vendor"
                        onSubmit: root.addExclude()
                    }

                }

            }

            SectionCard {
                Layout.fillWidth: true
                title: "Ignored File Extensions"
                detail: "Files with these extensions are skipped during indexing. Add values like .log or .zip."

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.draftExcludeExtensions

                        delegate: ListChip {
                            required property string modelData

                            Layout.fillWidth: true
                            label: modelData
                            onRemoveClicked: root.removeExcludeExtension(index)
                        }

                    }

                    AddRow {
                        id: excludeExtensionInputRow

                        placeholderText: ".log"
                        onSubmit: root.addExcludeExtension()
                    }

                }

            }

        }

    }

    component SectionCard: Rectangle {
        id: sectionCard

        required property string title
        required property string detail
        default property alias sectionChildren: contentColumn.data

        radius: 18
        color: root.theme.darkSurface
        border.width: 1
        border.color: root.theme.faintBorder
        implicitHeight: sectionLayout.implicitHeight + 28

        ColumnLayout {
            id: sectionLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: sectionCard.title
                color: root.theme.primaryText
                font.pixelSize: root.theme.fontMd
                font.bold: true
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: sectionCard.detail
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                wrapMode: Text.Wrap
            }

            ColumnLayout {
                id: contentColumn

                Layout.fillWidth: true
                spacing: 10
            }

        }

    }

    component ActionButton: Rectangle {
        property string label: ""
        property bool accent: false

        signal clicked()

        implicitWidth: Math.max(88, buttonText.implicitWidth + 28)
        implicitHeight: 36
        radius: 18
        color: accent ? root.theme.attentionFill : root.theme.darkControl
        border.width: 1
        border.color: accent ? root.theme.attentionBorder : root.theme.faintBorder
        opacity: enabled ? 1 : 0.45

        Text {
            id: buttonText

            anchors.centerIn: parent
            text: parent.label
            color: root.theme.primaryText
            font.pixelSize: root.theme.fontSm
            font.bold: true
            font.family: root.theme.fontFamilyMono
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }

    }

    component ListChip: Rectangle {
        id: chip

        required property string label

        signal removeClicked()

        Layout.fillWidth: true
        implicitHeight: 38
        radius: 18
        color: root.theme.cardColor
        border.width: 1
        border.color: root.theme.faintBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: chip.label
                color: root.theme.primaryText
                font.pixelSize: root.theme.fontMd
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: root.theme.faintBorder

                Text {
                    anchors.centerIn: parent
                    text: "x"
                    color: root.theme.bodyText
                    font.pixelSize: root.theme.fontXs
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.ListChip.removeClicked()
                }

            }

        }

    }

    component AddRow: RowLayout {
        id: addRow

        property alias value: addInput.text
        property alias placeholderText: inputPlaceholder.text

        signal submit()

        function clear() {
            addInput.text = "";
        }

        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: 18
            color: root.theme.cardColor
            border.width: 1
            border.color: addInput.activeFocus ? root.theme.attentionBorder : root.theme.faintBorder

            TextInput {
                id: addInput

                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.primaryText
                selectionColor: root.theme.attentionFill
                selectedTextColor: root.theme.primaryText
                font.pixelSize: root.theme.fontMd
                font.family: root.theme.fontFamilyMono
                onAccepted: addRow.submit()
            }

            Text {
                id: inputPlaceholder

                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: addInput.text.length === 0
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontMd
                font.family: root.theme.fontFamilyMono
            }

        }

        ActionButton {
            label: "Add"
            accent: false
            enabled: addInput.text.trim().length > 0
            onClicked: addRow.submit()
        }

    }

    component ToggleRow: Rectangle {
        id: toggleRow

        required property string label
        required property string description
        required property bool checked

        signal toggled()

        Layout.fillWidth: true
        implicitHeight: 64
        radius: 16
        color: root.theme.cardColor
        border.width: 1
        border.color: checked ? root.theme.attentionBorder : root.theme.faintBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: toggleRow.label
                    color: root.theme.primaryText
                    font.pixelSize: root.theme.fontMd
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: toggleRow.description
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    wrapMode: Text.Wrap
                }

            }

            ActionButton {
                label: toggleRow.checked ? "On" : "Off"
                accent: toggleRow.checked
                onClicked: toggleRow.toggled()
            }

        }

    }

    component NumericRow: Rectangle {
        id: numericRow

        required property string label
        required property string description
        required property string textValue

        signal valueEdited(string value)

        Layout.fillWidth: true
        implicitHeight: 72
        radius: 16
        color: root.theme.cardColor
        border.width: 1
        border.color: root.theme.faintBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: numericRow.label
                    color: root.theme.primaryText
                    font.pixelSize: root.theme.fontMd
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: numericRow.description
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    wrapMode: Text.Wrap
                }

            }

            Rectangle {
                implicitWidth: 92
                implicitHeight: 38
                radius: 16
                color: root.theme.darkControl
                border.width: 1
                border.color: numericInput.activeFocus ? root.theme.attentionBorder : root.theme.faintBorder

                TextInput {
                    id: numericInput

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.theme.primaryText
                    selectionColor: root.theme.attentionFill
                    selectedTextColor: root.theme.primaryText
                    font.pixelSize: root.theme.fontMd
                    font.family: root.theme.fontFamilyMono
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: numericRow.textValue
                    onTextChanged: numericRow.valueEdited(text)
                }

            }

        }

    }

}

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// NotesPanel.qml — sticky notes for quick jotting.
// Open: the 󰎚 bar button, right-click the clipboard notch, Super+Shift+N, or `qs ipc call notes toggle`.
// Drag it by the header anywhere on screen; position saved in notes-pos.json.
// Notes autosave to ~/.local/share/quickshell/notes.json (kept out of the dotfiles repo).

PanelWindow {
	id: notesPanel
	screen: notesPanel.pinnedScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : undefined)
	visible: true
	exclusionMode: ExclusionMode.Ignore
	anchors { top: true; bottom: true; left: true; right: true }
	WlrLayershell.namespace: "quickshell-notes"
	// clicks only land on the note; everywhere else passes through to your windows
	mask: Region { item: root.notesVisible ? noteCard : null }
	property var pinnedScreen: null
	readonly property int cardW: 370
	readonly property int cardH: 520
	readonly property string posFile: dataDir + "/notes-pos.json"
	property bool placed: false
	property bool posLoaded: false
	function defaultPos() {
		noteCard.x = width - cardW - 6 - root.barInsetRight
		noteCard.y = root.barPosition === "top" ? root.barInsetTop + root.barGapV : height - cardH - root.barInsetBottom - root.barGapV
	}
	function clampPos() {
		if (width <= 0 || height <= 0) return
		noteCard.x = Math.max(0, Math.min(width - cardW, noteCard.x))
		noteCard.y = Math.max(0, Math.min(height - cardH, noteCard.y))
	}
	function placeCard() {
		if (placed || !posLoaded || width <= 0 || height <= 0) return
		var ok = false
		try {
			var t = notesPosFile.text()
			if (t && t.trim().length > 0) {
				var p = JSON.parse(t)
				if (typeof p.x === "number" && typeof p.y === "number") { noteCard.x = p.x; noteCard.y = p.y; ok = true }
			}
		} catch (e) {}
		if (!ok) defaultPos()
		clampPos()
		placed = true
	}
	function savePos() { notesPosFile.setText(JSON.stringify({ x: Math.round(noteCard.x), y: Math.round(noteCard.y) })) }
	onWidthChanged: { placeCard(); clampPos() }
	onHeightChanged: { placeCard(); clampPos() }
	Connections {
		target: root
		function onNotesVisibleChanged() { if (root.notesVisible) notesPanel.pinnedScreen = root.focusedScreen }
	}
	FileView {
		id: notesPosFile
		path: notesPanel.posFile
		onLoaded: { notesPanel.posLoaded = true; notesPanel.placeCard() }
		onLoadFailed: { notesPanel.posLoaded = true; notesPanel.placeCard() }
	}
	color: "transparent"
	focusable: true
	WlrLayershell.keyboardFocus: root.notesVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None


	readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/quickshell"
	readonly property string dataFile: dataDir + "/notes.json"
	// Sticky-paper pastels: butter, blush, mint, sky, peach, lilac
	readonly property var paperColors: ["#f9e2af", "#f5c2e7", "#a6e3a1", "#89dceb", "#fab387", "#cba6f7"]
	readonly property color ink: "#2a2438"

	property var notes: []
	property int current: 0
	property bool ready: false
	property bool syncing: false
	property bool dirty: false
	property bool confirmDelete: false
	property real nowTick: Date.now()

	readonly property var cur: notes.length > 0 && current < notes.length ? notes[current] : null
	readonly property color paper: cur ? paperColors[(cur.color || 0) % paperColors.length] : paperColors[0]

	// ── Data ────────────────────────────────────────────────────────────
	function makeNote(ci) {
		return { id: Date.now() + Math.floor(Math.random() * 1000), text: "", color: ci, updated: Date.now() }
	}
	function loadNotes() {
		if (ready) return
		var list = []
		try {
			var t = notesFile.text()
			if (t && t.trim().length > 0) {
				var parsed = JSON.parse(t)
				if (Array.isArray(parsed))
					list = parsed.filter(function(n) { return n && typeof n.text === "string" })
			}
		} catch (e) {
			console.warn("notes: could not parse notes.json —", e)
		}
		if (list.length === 0) list = [makeNote(0)]
		notes = list
		current = 0
		ready = true
		syncEditor()
	}
	function persist() {
		if (!ready) return
		notesFile.setText(JSON.stringify(notes, null, 2))
	}
	function commitEditor() {
		if (!dirty || !cur) return
		dirty = false
		var n = notes.slice()
		n[current] = Object.assign({}, n[current], { text: editor.text, updated: Date.now() })
		notes = n
	}
	function flush() {
		saveTimer.stop()
		commitEditor()
		persist()
	}
	function syncEditor() {
		syncing = true
		editor.text = cur ? cur.text : ""
		editor.cursorPosition = editor.length
		syncing = false
		dirty = false
		confirmDelete = false
	}
	function setColor(ci) {
		commitEditor()
		var n = notes.slice()
		n[current] = Object.assign({}, n[current], { color: ci, updated: Date.now() })
		notes = n
		persist()
	}
	function addNote() {
		commitEditor()
		var n = notes.slice()
		n.unshift(makeNote(cur ? ((cur.color || 0) + 1) % paperColors.length : 0))
		notes = n
		current = 0
		syncEditor()
		persist()
		tabs.positionViewAtBeginning()
		editor.forceActiveFocus()
	}
	function deleteCurrent() {
		if (!cur) return
		var hasText = (dirty ? editor.text : cur.text).trim().length > 0
		if (hasText && !confirmDelete) {
			confirmDelete = true
			confirmReset.restart()
			return
		}
		dirty = false
		var n = notes.slice()
		n.splice(current, 1)
		if (n.length === 0) n.push(makeNote(0))
		notes = n
		current = Math.min(current, n.length - 1)
		syncEditor()
		persist()
	}
	function select(i) {
		if (i < 0 || i >= notes.length || i === current) return
		commitEditor()
		current = i
		syncEditor()
		tabs.positionViewAtIndex(i, ListView.Contain)
		persist()
	}
	function preview(n) {
		var t = (n.text || "").trim().split("\n")[0]
		if (t.length === 0) return "Empty"
		return t.length > 14 ? t.substring(0, 13) + "…" : t
	}
	function ago(ms) {
		var s = Math.max(0, Math.floor((nowTick - ms) / 1000))
		if (s < 45) return "just now"
		if (s < 3600) return Math.round(s / 60) + "m ago"
		if (s < 86400) return Math.round(s / 3600) + "h ago"
		return Qt.formatDateTime(new Date(ms), "MMM d")
	}
	function handleKey(event) {
		if (event.key === Qt.Key_Escape) {
			root.notesVisible = false
			event.accepted = true
		} else if (event.modifiers & Qt.ControlModifier) {
			if (event.key === Qt.Key_N) { addNote(); event.accepted = true }
			else if (event.key === Qt.Key_W) { deleteCurrent(); event.accepted = true }
			else if (event.key === Qt.Key_Tab) { select((current + 1) % notes.length); event.accepted = true }
			else if (event.key === Qt.Key_Backtab) { select((current - 1 + notes.length) % notes.length); event.accepted = true }
		}
	}

	Process {
		id: mkdirProc
		command: ["mkdir", "-p", notesPanel.dataDir]
		running: true
	}
	FileView {
		id: notesFile
		path: notesPanel.dataFile
		onLoaded: notesPanel.loadNotes()
		onLoadFailed: notesPanel.loadNotes()
	}
	Timer {
		id: saveTimer
		interval: 450
		repeat: false
		onTriggered: { notesPanel.commitEditor(); notesPanel.persist() }
	}
	Timer {
		id: confirmReset
		interval: 2200
		repeat: false
		onTriggered: notesPanel.confirmDelete = false
	}
	Timer {
		interval: 30000
		running: root.notesVisible
		repeat: true
		triggeredOnStart: true
		onTriggered: notesPanel.nowTick = Date.now()
	}

	// ── UI ──────────────────────────────────────────────────────────────
	Item {
		id: noteCard
		width: notesPanel.cardW
		height: notesPanel.cardH
		focus: root.notesVisible
		opacity: root.notesVisible ? 1 : 0
		scale: root.notesVisible ? 1 : 0.94
		visible: opacity > 0
		Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
		Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
		// drag the note by its header (the strip with the title)
		MouseArea {
			id: noteDrag
			x: 0; y: 0
			width: parent.width
			height: 52
			cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
			drag.target: noteCard
			drag.axis: Drag.XAndYAxis
			drag.minimumX: 0
			drag.minimumY: 0
			drag.maximumX: notesPanel.width - noteCard.width
			drag.maximumY: notesPanel.height - noteCard.height
			drag.threshold: 2
			onReleased: notesPanel.savePos()
		}
		Keys.onPressed: function(event) { notesPanel.handleKey(event) }

		Rectangle {
			anchors.fill: parent
			radius: 20
			color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.95)
			border.width: 1
			border.color: Qt.rgba(root.walColor4.r, root.walColor4.g, root.walColor4.b, 0.45)

			ColumnLayout {
				anchors.fill: parent
				anchors.margins: 16
				spacing: 12

				// Header
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Text {
						text: "󰎚"
						color: root.walColor4
						font.pixelSize: 20
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: "Sticky Notes"
						color: root.walColor5
						font.pixelSize: 15
						font.bold: true
						font.family: "JetBrainsMono Nerd Font"
						Layout.fillWidth: true
					}
					Rectangle {
						width: countText.implicitWidth + 12
						height: 20
						radius: 10
						color: Qt.rgba(root.walColor4.r, root.walColor4.g, root.walColor4.b, 0.2)
						Text {
							id: countText
							anchors.centerIn: parent
							text: notesPanel.notes.length
							color: root.walColor4
							font.pixelSize: 10
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
						}
					}
					Rectangle {
						width: 28; height: 28; radius: 8
						color: addMa.containsMouse
							? Qt.rgba(root.walColor2.r, root.walColor2.g, root.walColor2.b, 0.25)
							: root.card(0.35)
						Behavior on color { ColorAnimation { duration: 120 } }
						Text {
							anchors.centerIn: parent
							text: "󰐕"
							color: root.walColor2
							font.pixelSize: 15
							font.family: "JetBrainsMono Nerd Font"
						}
						MouseArea {
							id: addMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: notesPanel.addNote()
						}
					}
				}

				// Note tabs
				ListView {
					id: tabs
					Layout.fillWidth: true
					Layout.preferredHeight: 28
					orientation: ListView.Horizontal
					spacing: 6
					clip: true
					boundsBehavior: Flickable.StopAtBounds
					model: notesPanel.notes
					delegate: Rectangle {
						required property var modelData
						required property int index
						readonly property bool active: index === notesPanel.current
						readonly property color pc: notesPanel.paperColors[(modelData.color || 0) % notesPanel.paperColors.length]
						height: 28
						width: tabRow.implicitWidth + 20
						radius: 14
						color: active ? pc : (tabMa.containsMouse ? root.hover(0.08) : root.card(0.35))
						Behavior on color { ColorAnimation { duration: 150 } }
						Row {
							id: tabRow
							anchors.centerIn: parent
							spacing: 6
							Rectangle {
								width: 8; height: 8; radius: 4
								anchors.verticalCenter: parent.verticalCenter
								color: active ? notesPanel.ink : pc
							}
							Text {
								anchors.verticalCenter: parent.verticalCenter
								text: notesPanel.preview(modelData)
								color: active ? notesPanel.ink : root.walForeground
								font.pixelSize: 10
								font.bold: active
								font.family: "JetBrainsMono Nerd Font"
							}
						}
						MouseArea {
							id: tabMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: notesPanel.select(index)
						}
					}
					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.NoButton
						onWheel: function(wheel) {
							tabs.contentX = Math.max(0, Math.min(tabs.contentWidth - tabs.width,
								tabs.contentX - wheel.angleDelta.y))
						}
					}
				}

				// Paper
				Item {
					Layout.fillWidth: true
					Layout.fillHeight: true

					Rectangle {
						id: paperRect
						anchors.fill: parent
						anchors.topMargin: 8
						radius: 8
						color: notesPanel.paper
						Behavior on color { ColorAnimation { duration: 250 } }

						// soft bottom shade so the paper feels lifted
						Rectangle {
							anchors.fill: parent
							radius: parent.radius
							gradient: Gradient {
								GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.18) }
								GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.0) }
								GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
							}
						}

						Text {
							anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 16 }
							text: notesPanel.cur ? "edited " + notesPanel.ago(notesPanel.cur.updated) : ""
							color: Qt.rgba(0.16, 0.14, 0.22, 0.5)
							font.pixelSize: 9
							font.family: "JetBrainsMono Nerd Font"
						}

						ScrollView {
							id: scroller
							anchors {
								fill: parent
								topMargin: 30
								leftMargin: 6
								rightMargin: 6
								bottomMargin: 26
							}
							clip: true
							TextArea {
								id: editor
								wrapMode: TextArea.Wrap
								color: notesPanel.ink
								selectionColor: Qt.rgba(0, 0, 0, 0.18)
								selectedTextColor: notesPanel.ink
								placeholderText: "Jot something down…"
								placeholderTextColor: Qt.rgba(0.16, 0.14, 0.22, 0.4)
								font.family: "JetBrainsMono Nerd Font"
								font.pixelSize: 13
								selectByMouse: true
								padding: 10
								background: null
								Keys.onPressed: function(event) { notesPanel.handleKey(event) }
								onTextChanged: {
									if (notesPanel.syncing || !notesPanel.ready) return
									notesPanel.dirty = true
									notesPanel.confirmDelete = false
									saveTimer.restart()
								}
							}
						}

						Text {
							anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 8; rightMargin: 30 }
							text: editor.length + " chars"
							color: Qt.rgba(0.16, 0.14, 0.22, 0.45)
							font.pixelSize: 9
							font.family: "JetBrainsMono Nerd Font"
						}

						// folded corner
						Canvas {
							id: corner
							width: 22; height: 22
							anchors { right: parent.right; bottom: parent.bottom }
							property color tint: notesPanel.paper
							onTintChanged: requestPaint()
							onPaint: {
								var ctx = getContext("2d")
								ctx.clearRect(0, 0, width, height)
								ctx.fillStyle = root.walBackground
								ctx.beginPath()
								ctx.moveTo(width, 0); ctx.lineTo(width, height); ctx.lineTo(0, height)
								ctx.closePath(); ctx.fill()
								ctx.fillStyle = Qt.darker(tint, 1.18)
								ctx.beginPath()
								ctx.moveTo(0, 0); ctx.lineTo(width, 0); ctx.lineTo(0, height)
								ctx.closePath(); ctx.fill()
							}
						}
					}

					// tape strip
					Rectangle {
						width: 70; height: 18
						radius: 2
						anchors.horizontalCenter: parent.horizontalCenter
						anchors.top: parent.top
						rotation: -3
						color: Qt.rgba(1, 1, 1, 0.42)
						border.width: 1
						border.color: Qt.rgba(1, 1, 1, 0.55)
					}
				}

				// Toolbar
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Repeater {
						model: notesPanel.paperColors.length
						delegate: Rectangle {
							required property int index
							readonly property bool chosen: notesPanel.cur && (notesPanel.cur.color || 0) === index
							width: 20; height: 20; radius: 10
							color: notesPanel.paperColors[index]
							border.width: chosen ? 2 : 0
							border.color: root.walForeground
							scale: dotMa.containsMouse ? 1.15 : 1.0
							Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
							MouseArea {
								id: dotMa
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: notesPanel.setColor(index)
							}
						}
					}
					Item { Layout.fillWidth: true }
					Rectangle {
						width: 30; height: 28; radius: 8
						color: copyMa.containsMouse ? root.hover(0.1) : root.card(0.35)
						Text {
							anchors.centerIn: parent
							text: "󰆏"
							color: root.walColor5
							font.pixelSize: 14
							font.family: "JetBrainsMono Nerd Font"
						}
						MouseArea {
							id: copyMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								if (editor.text.length > 0)
									Quickshell.execDetached(["wl-copy", editor.text])
							}
						}
					}
					Rectangle {
						width: notesPanel.confirmDelete ? delText.implicitWidth + 20 : 30
						height: 28
						radius: 8
						color: notesPanel.confirmDelete || delMa.containsMouse
							? Qt.rgba(root.walColor1.r, root.walColor1.g, root.walColor1.b, 0.22)
							: root.card(0.35)
						Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
						Text {
							id: delText
							anchors.centerIn: parent
							text: notesPanel.confirmDelete ? "󰆴 sure?" : "󰆴"
							color: root.walColor1
							font.pixelSize: notesPanel.confirmDelete ? 11 : 14
							font.bold: notesPanel.confirmDelete
							font.family: "JetBrainsMono Nerd Font"
						}
						MouseArea {
							id: delMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: notesPanel.deleteCurrent()
						}
					}
				}

				// Hints
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 22
					radius: 8
					color: root.card(0.3)
					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 10
						anchors.rightMargin: 10
						Text { text: "^N new"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "^W delete"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "^Tab next"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "esc close"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
					}
				}
			}
		}
	}

	Connections {
		target: root
		function onNotesVisibleChanged() {
			if (root.notesVisible) {
				notesPanel.nowTick = Date.now()
				focusTimer.start()
			} else {
				notesPanel.flush()
			}
		}
	}
	Timer {
		id: focusTimer
		interval: 50
		repeat: false
		onTriggered: {
			notesPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive
			releaseTimer.start()
		}
	}
	Timer {
		id: releaseTimer
		interval: 100
		repeat: false
		onTriggered: {
			editor.forceActiveFocus()
			editor.cursorPosition = editor.length
			notesPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
		}
	}
}

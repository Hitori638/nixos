import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// WorkspaceOverview.qml — every occupied workspace as a mini-map of its windows.
// Open: right-click the workspaces notch, Super+Tab, or `qs ipc call overview toggle`.
// Click a window to jump to it, click a workspace card to switch, 1–9 to switch, Esc to close.

PanelWindow {
	id: overview
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: root.overviewVisible || fade.running
	anchors { top: true; bottom: true; left: true; right: true }
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:overview"
	WlrLayershell.keyboardFocus: root.overviewVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	property var monitors: ({})
	property var clients: []
	property int activeWs: 1
	property var workspaces: []          // [{ id, windows: [...] }]
	property string hoverTitle: ""
	property real shown: root.overviewVisible ? 1 : 0
	Behavior on shown { NumberAnimation { id: fade; duration: 180; easing.type: Easing.OutCubic } }

	readonly property var palette: [root.walColor5, root.walColor13, root.walColor2, root.walColor4,
	                                root.walColor6, root.walColor12, root.walPeach, root.walColor1]
	function classColor(cls) {
		var h = 0
		for (var i = 0; i < cls.length; i++) h = (h * 31 + cls.charCodeAt(i)) >>> 0
		return palette[h % palette.length]
	}

	function refresh() { if (!loadProc.running) loadProc.running = true }

	// Match a hyprctl client to Quickshell's Hyprland toplevel (for live previews)
	function toplevelFor(addr) {
		try {
			var want = ("" + addr).toLowerCase().replace(/^0x/, "")
			var vals = Hyprland.toplevels.values
			for (var i = 0; i < vals.length; i++) {
				var a = ("" + vals[i].address).toLowerCase().replace(/^0x/, "")
				if (a === want) return vals[i]
			}
		} catch (e) {}
		return null
	}

	function parse(text) {
		var data
		try { data = JSON.parse(text) } catch (e) { console.warn("overview: bad hyprctl json", e); return }
		var mons = {}
		for (var i = 0; i < data.m.length; i++) {
			var m = data.m[i]
			var sc = m.scale || 1
			var w = m.width / sc, h = m.height / sc
			if (m.transform % 2 === 1) { var t = w; w = h; h = t }
			mons[m.id] = { x: m.x, y: m.y, w: w, h: h }
		}
		monitors = mons
		activeWs = data.a && data.a.id ? data.a.id : 1
		var byWs = {}
		for (var j = 0; j < data.c.length; j++) {
			var c = data.c[j]
			if (!c.mapped || c.hidden || !c.workspace || c.workspace.id <= 0) continue
			var id = c.workspace.id
			if (!byWs[id]) byWs[id] = []
			var mon = mons[c.monitor] || { x: 0, y: 0, w: 1920, h: 1080 }
			byWs[id].push({
				address: c.address,
				cls: c["class"] || c.initialClass || "app",
				title: c.title || c.initialTitle || "",
				rx: Math.max(0, (c.at[0] - mon.x) / mon.w),
				ry: Math.max(0, (c.at[1] - mon.y) / mon.h),
				rw: Math.min(1, c.size[0] / mon.w),
				rh: Math.min(1, c.size[1] / mon.h),
				floating: c.floating,
				focused: c.focusHistoryID === 0
			})
		}
		if (!byWs[activeWs]) byWs[activeWs] = []
		var list = []
		for (var k in byWs) {
			// floating windows on top
			byWs[k].sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
			list.push({ id: parseInt(k), windows: byWs[k] })
		}
		list.sort(function(a, b) { return a.id - b.id })
		workspaces = list
	}

	Process {
		id: loadProc
		command: ["bash", "-c", "printf '{\"m\":'; hyprctl monitors -j; printf ',\"c\":'; hyprctl clients -j; printf ',\"a\":'; hyprctl activeworkspace -j; printf '}'"]
		stdout: StdioCollector {
			onStreamFinished: overview.parse(this.text)
		}
	}
	Timer { id: refreshDebounce; interval: 120; onTriggered: overview.refresh() }
	Connections {
		target: Hyprland
		enabled: root.overviewVisible
		function onRawEvent(event) {
			var n = event.name
			if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
				|| n === "workspace" || n === "workspacev2" || n === "windowtitle" || n === "changefloatingmode")
				refreshDebounce.restart()
		}
	}
	Connections {
		target: root
		function onOverviewVisibleChanged() {
			if (root.overviewVisible) { overview.hoverTitle = ""; overview.refresh(); keyCatcher.forceActiveFocus() }
		}
	}

	readonly property int columns: workspaces.length <= 4 ? Math.max(1, workspaces.length) : (workspaces.length <= 6 ? 3 : 4)
	readonly property real cardW: Math.min(workspaces.length <= 2 ? 460 : 360, (width - 120 - (columns - 1) * 16) / columns)

	Item {
		id: keyCatcher
		anchors.fill: parent
		focus: true
		opacity: overview.shown
		Keys.onPressed: function(event) {
			if (event.key === Qt.Key_Escape) { root.overviewVisible = false; event.accepted = true }
			else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) { root.focusWorkspace(event.key - Qt.Key_0); event.accepted = true }
			else if (event.key === Qt.Key_0) { root.focusWorkspace(10); event.accepted = true }
		}

		// dim backdrop — click to close
		Rectangle {
			anchors.fill: parent
			color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.55)
			MouseArea { anchors.fill: parent; onClicked: root.overviewVisible = false }
		}

		Rectangle {
			id: sheet
			anchors.centerIn: parent
			width: grid.width + 48
			height: col.implicitHeight + 40
			radius: 22
			color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.96)
			border.width: 1
			border.color: Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.45)
			scale: 0.94 + 0.06 * overview.shown
			MouseArea { anchors.fill: parent } // swallow clicks so the backdrop doesn't close

			ColumnLayout {
				id: col
				anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20 }
				spacing: 14

				RowLayout {
					Layout.fillWidth: true
					spacing: 10
					Text {
						text: "󱂬"
						color: root.walColor13
						font.pixelSize: 20
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: "Workspaces"
						color: root.walColor5
						font.pixelSize: 16
						font.bold: true
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: {
							var n = 0
							for (var i = 0; i < overview.workspaces.length; i++) n += overview.workspaces[i].windows.length
							return n + " window" + (n === 1 ? "" : "s") + " · " + overview.workspaces.length + " workspace" + (overview.workspaces.length === 1 ? "" : "s")
						}
						color: root.walColor8
						font.pixelSize: 11
						font.family: "JetBrainsMono Nerd Font"
						Layout.fillWidth: true
					}
					Rectangle {
						width: prevRow.implicitWidth + 16
						height: 22
						radius: 11
						color: root.overviewPreviews
							? Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.22)
							: (prevMa.containsMouse ? root.hover(0.08) : root.card(0.35))
						Row {
							id: prevRow
							anchors.centerIn: parent
							spacing: 5
							Text {
								text: root.overviewPreviews ? "󰈈" : "󰈉"
								color: root.overviewPreviews ? root.walColor13 : root.walColor8
								font.pixelSize: 12
								font.family: "JetBrainsMono Nerd Font"
							}
							Text {
								text: "Live previews"
								color: root.overviewPreviews ? root.walColor13 : root.walColor8
								font.pixelSize: 10
								font.family: "JetBrainsMono Nerd Font"
							}
						}
						MouseArea {
							id: prevMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.toggleOverviewPreviews()
						}
					}
					Text {
						text: "click to jump · 1–9 switch · esc close"
						color: root.walColor8
						opacity: 0.7
						font.pixelSize: 10
						font.family: "JetBrainsMono Nerd Font"
					}
				}

				Grid {
					id: grid
					columns: overview.columns
					spacing: 16
					Layout.alignment: Qt.AlignHCenter
					Repeater {
						model: overview.workspaces
						delegate: WsCard {
							required property var modelData
							ws: modelData
						}
					}
				}

				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 26
					radius: 8
					color: root.card(0.3)
					Text {
						anchors.centerIn: parent
						width: parent.width - 20
						horizontalAlignment: Text.AlignHCenter
						text: overview.hoverTitle !== "" ? overview.hoverTitle : "Hover a window to see its title"
						color: overview.hoverTitle !== "" ? root.walForeground : root.walColor8
						font.pixelSize: 11
						font.family: "JetBrainsMono Nerd Font"
						elide: Text.ElideMiddle
					}
				}
			}
		}
	}

	component WsCard: Rectangle {
		id: wcard
		property var ws
		readonly property bool current: ws.id === overview.activeWs
		width: overview.cardW
		height: map.height + 52
		radius: 16
		color: cardMa.containsMouse ? root.hover(0.05) : root.card(0.35)
		border.width: current ? 2 : 1
		border.color: current ? root.walColor5 : Qt.rgba(root.walColor8.r, root.walColor8.g, root.walColor8.b, 0.3)
		Behavior on color { ColorAnimation { duration: 120 } }

		MouseArea {
			id: cardMa
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: root.focusWorkspace(wcard.ws.id)
		}

		RowLayout {
			id: head
			anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
			spacing: 8
			Rectangle {
				width: 26; height: 22; radius: 8
				color: wcard.current ? root.walColor5 : root.card(0.45)
				Text {
					anchors.centerIn: parent
					text: wcard.ws.id
					color: wcard.current ? root.walBackground : root.walForeground
					font.pixelSize: 11
					font.bold: true
					font.family: "JetBrainsMono Nerd Font"
				}
			}
			Text {
				text: wcard.ws.windows.length === 0 ? "empty" : wcard.ws.windows.length + " window" + (wcard.ws.windows.length === 1 ? "" : "s")
				color: root.walColor8
				font.pixelSize: 10
				font.family: "JetBrainsMono Nerd Font"
				Layout.fillWidth: true
			}
			Text {
				visible: wcard.current
				text: "current"
				color: root.walColor5
				font.pixelSize: 9
				font.bold: true
				font.family: "JetBrainsMono Nerd Font"
			}
		}

		// mini-map of the workspace
		Rectangle {
			id: map
			anchors { top: head.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
			width: wcard.width - 24
			height: width * 9 / 16
			radius: 10
			color: root.card(0.45)
			clip: true

			Text {
				anchors.centerIn: parent
				visible: wcard.ws.windows.length === 0
				text: "nothing here"
				color: root.walColor8
				opacity: 0.6
				font.pixelSize: 10
				font.family: "JetBrainsMono Nerd Font"
			}

			Repeater {
				model: wcard.ws.windows
				delegate: Rectangle {
					id: win
					required property var modelData
					readonly property color tint: overview.classColor(modelData.cls)
					x: modelData.rx * map.width + 2
					y: modelData.ry * map.height + 2
					width: Math.max(18, modelData.rw * map.width - 4)
					height: Math.max(14, modelData.rh * map.height - 4)
					radius: 6
					color: Qt.rgba(tint.r, tint.g, tint.b, winMa.containsMouse ? 0.38 : 0.22)
					border.width: winMa.containsMouse || modelData.focused ? 2 : 1
					border.color: Qt.rgba(tint.r, tint.g, tint.b, winMa.containsMouse || modelData.focused ? 1 : 0.6)
					z: winMa.containsMouse ? 10 : (modelData.floating ? 2 : 1)
					Behavior on color { ColorAnimation { duration: 100 } }

					readonly property string iconSrc: root.iconFor(modelData.cls)
					readonly property var toplevel: root.overviewPreviews ? overview.toplevelFor(modelData.address) : null
					readonly property bool hasPreview: previewLoader.item ? previewLoader.item.hasContent : false

					// live window preview
					Loader {
						id: previewLoader
						anchors.fill: parent
						anchors.margins: 2
						active: root.overviewVisible && win.toplevel !== null
						source: "OverviewPreview.qml"
						onLoaded: item.toplevel = Qt.binding(function() { return win.toplevel })
						clip: true
					}
					// app badge in the corner while a preview is showing
					Rectangle {
						visible: win.hasPreview
						anchors { left: parent.left; bottom: parent.bottom; margins: 4 }
						width: 20; height: 20; radius: 6
						color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.85)
						z: 3
						Image {
							anchors.centerIn: parent
							width: 14; height: 14
							source: win.iconSrc
							sourceSize: Qt.size(28, 28)
							asynchronous: true
						}
					}

					Column {
						anchors.centerIn: parent
						spacing: 2
						width: parent.width - 8
						visible: !win.hasPreview
						Item {
							width: Math.min(32, Math.max(18, win.height * 0.35))
							height: width
							anchors.horizontalCenter: parent.horizontalCenter
							visible: win.height > 26
							Image {
								id: icon
								anchors.fill: parent
								source: win.iconSrc
								sourceSize: Qt.size(64, 64)
								fillMode: Image.PreserveAspectFit
								asynchronous: true
								visible: status === Image.Ready
							}
							Rectangle {
								anchors.fill: parent
								radius: 7
								visible: icon.status !== Image.Ready
								color: win.tint
								Text {
									anchors.centerIn: parent
									text: win.modelData.cls.charAt(0).toUpperCase()
									color: root.walBackground
									font.pixelSize: 12
									font.bold: true
									font.family: "JetBrainsMono Nerd Font"
								}
							}
						}
						Text {
							width: parent.width
							visible: win.height > 46 && win.width > 50
							horizontalAlignment: Text.AlignHCenter
							text: root.prettyName(win.modelData.cls)
							color: root.walForeground
							font.pixelSize: 9
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
							elide: Text.ElideRight
						}
					}

					MouseArea {
						id: winMa
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onEntered: overview.hoverTitle = root.prettyName(win.modelData.cls) + "  —  " + win.modelData.title
						onExited: if (overview.hoverTitle.indexOf(root.prettyName(win.modelData.cls) + "  —  ") === 0) overview.hoverTitle = ""
						onClicked: root.focusWindow(win.modelData.address, wcard.ws.id)
					}
				}
			}
		}

		Text {
			anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12; bottomMargin: 8 }
			text: {
				var seen = [], w = wcard.ws.windows
				for (var i = 0; i < w.length; i++) if (seen.indexOf(w[i].cls) < 0) seen.push(w[i].cls)
				return seen.join(" · ")
			}
			color: root.walColor8
			font.pixelSize: 9
			font.family: "JetBrainsMono Nerd Font"
			elide: Text.ElideRight
			visible: false
		}
	}
}

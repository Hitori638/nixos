import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// EqPanel.qml — sound panel. Right-click the volume notch to open.
//   Output / Microphone: pick the device, set its volume, mute it (wpctl)
//   Equalizer: 10-band PipeWire filter-chain managed by ~/.config/scripts/eq.sh — it sits in
//   front of whatever output is the default (smart filter), state in root.eq* / state/eq.

PanelWindow {
	id: eqPanel
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: true
	exclusionMode: ExclusionMode.Ignore
	anchors {
		bottom: root.barPosition !== "top"
		right: true
		top: root.barPosition === "top"
	}
	margins {
		bottom: root.eqVisible ? root.barGapV : -(implicitHeight + 20)
		right: (6) + root.barInsetRight
		top: root.eqVisible ? root.barGapV : -(implicitHeight + 20)
	}
	implicitWidth: 470
	implicitHeight: card.implicitHeight
	color: "transparent"
	focusable: true
	WlrLayershell.keyboardFocus: root.eqVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

	Behavior on margins.bottom {
		NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
	}
	Behavior on margins.top {
		NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
	}

	readonly property var freqLabels: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
	readonly property var presetNames: ["Flat", "Bass", "Treble", "Vocal", "Rock", "Electronic", "Loudness"]
	readonly property real maxDb: 12
	property var sinks: []
	property var sources: []
	readonly property var outDev: pickDefault(sinks)
	readonly property var inDev: pickDefault(sources)
	readonly property string sinkName: outDev ? outDev.desc : ""
	readonly property string devScript: root.homePath + "/.config/scripts/audio-devices.sh"
	property var pendingVol: ({})       // id → percent, flushed by volFlush
	property real holdUntil: 0          // ignore polled volumes right after a local change

	// band label: +3 / -1.5 / 0
	function fmtDb(g) {
		var v = Math.round((g || 0) * 10) / 10
		return (v > 0 ? "+" : "") + v
	}
	function pickDefault(list) {
		for (var i = 0; i < list.length; i++) if (list[i].def) return list[i]
		return list.length ? list[0] : null
	}
	function devIcon(d) {
		if (!d) return "󰓃"
		if (d.kind === "source") return d.muted ? "󰍭" : "󰍬"
		if (d.muted) return "󰝟"
		switch (d.type) {
		case "bluetooth": return "󰂰"
		case "hdmi": return "󰍹"
		case "usb": case "headphones": return "󰋋"
		case "speaker": return "󰓃"
		default: return "󰕾"
		}
	}
	function shortName(desc) {
		var t = ("" + desc).replace(/ (Analog|Digital) Stereo.*$/i, "").replace(/ Stereo$/i, "")
		t = t.replace(/^(Family \w+ |Rembrandt |Raven |Renoir )/, "").replace(/ \(.*\)$/, "")
		return t.length > 22 ? t.substring(0, 21) + "…" : t
	}
	function refresh() { if (!devProc.running) devProc.running = true }
	function setDefault(d) {
		if (!d) return
		Quickshell.execDetached(["wpctl", "set-default", d.id])
		var list = (d.kind === "sink" ? sinks : sources).slice()
		for (var i = 0; i < list.length; i++) { var x = Object.assign({}, list[i]); x.def = x.id === d.id; list[i] = x }
		if (d.kind === "sink") sinks = list; else sources = list
		refreshSoon.restart()
	}
	function updateDev(d, patch) {
		var list = (d.kind === "sink" ? sinks : sources).slice()
		for (var i = 0; i < list.length; i++) if (list[i].id === d.id) { var x = Object.assign({}, list[i]); for (var k in patch) x[k] = patch[k]; list[i] = x }
		if (d.kind === "sink") sinks = list; else sources = list
	}
	function setDevVolume(d, v) {
		if (!d) return
		v = Math.max(0, Math.min(100, Math.round(v)))
		updateDev(d, { vol: v })
		var pv = pendingVol; pv[d.id] = v; pendingVol = pv
		holdUntil = Date.now() + 1200
		if (!volFlush.running) volFlush.start()
	}
	function toggleMute(d) {
		if (!d) return
		Quickshell.execDetached(["wpctl", "set-mute", d.id, "toggle"])
		updateDev(d, { muted: !d.muted })
		holdUntil = Date.now() + 1200
	}

	Process {
		id: devProc
		command: [eqPanel.devScript]
		stdout: StdioCollector {
			onStreamFinished: {
				if (Date.now() < eqPanel.holdUntil) return
				var sk = [], sr = []
				var lines = this.text.split("\n")
				for (var i = 0; i < lines.length; i++) {
					var f = lines[i].split("|")
					if (f.length < 7) continue
					var d = { kind: f[0], id: f[1], def: f[2] === "1", vol: parseInt(f[3]) || 0,
					          muted: f[4] === "1", type: f[5], desc: f.slice(6).join("|") }
					if (d.kind === "sink") sk.push(d); else sr.push(d)
				}
				eqPanel.sinks = sk
				eqPanel.sources = sr
			}
		}
	}
	Timer {
		interval: 2000
		running: root.eqVisible
		repeat: true
		triggeredOnStart: true
		onTriggered: eqPanel.refresh()
	}
	Timer { id: refreshSoon; interval: 400; onTriggered: eqPanel.refresh() }
	Timer {
		id: volFlush
		interval: 60
		onTriggered: {
			var pv = eqPanel.pendingVol
			for (var id in pv) Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", id, pv[id] + "%"])
			eqPanel.pendingVol = ({})
		}
	}

	// one device row: chips to choose the device + volume slider with mute
	component DeviceBlock: ColumnLayout {
		id: blk
		property string title: ""
		property var list: []
		property var dev: null
		property color accent: root.walColor5
		Layout.fillWidth: true
		spacing: 7
		RowLayout {
			Layout.fillWidth: true
			spacing: 6
			Text {
				text: blk.title
				color: root.walColor8
				font.pixelSize: 9
				font.bold: true
				font.letterSpacing: 0.8
				font.family: "JetBrainsMono Nerd Font"
			}
			Text {
				visible: blk.list.length === 0
				text: "none found"
				color: root.walColor8
				opacity: 0.6
				font.pixelSize: 9
				font.family: "JetBrainsMono Nerd Font"
			}
			Item { Layout.fillWidth: true }
		}
		Flow {
			Layout.fillWidth: true
			spacing: 6
			visible: blk.list.length > 1
			Repeater {
				model: blk.list
				delegate: Rectangle {
					required property var modelData
					readonly property bool sel: modelData.def
					width: chipRow.implicitWidth + 18
					height: 24
					radius: 12
					color: sel ? Qt.rgba(blk.accent.r, blk.accent.g, blk.accent.b, 0.22) : (chipMa.containsMouse ? root.hover(0.5) : root.card(0.3))
					border.width: sel ? 1 : 0
					border.color: Qt.rgba(blk.accent.r, blk.accent.g, blk.accent.b, 0.6)
					Row {
						id: chipRow
						anchors.centerIn: parent
						spacing: 5
						Text {
							text: eqPanel.devIcon(Object.assign({}, modelData, { muted: false }))
							color: sel ? blk.accent : root.walColor8
							font.pixelSize: 12
							font.family: "JetBrainsMono Nerd Font"
						}
						Text {
							text: eqPanel.shortName(modelData.desc)
							color: sel ? root.walForeground : root.walColor8
							font.pixelSize: 10
							font.bold: sel
							font.family: "JetBrainsMono Nerd Font"
						}
					}
					MouseArea {
						id: chipMa
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: eqPanel.setDefault(modelData)
					}
				}
			}
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: 10
			visible: blk.dev !== null
			Text {
				text: eqPanel.devIcon(blk.dev)
				color: blk.dev && blk.dev.muted ? root.walColor8 : blk.accent
				font.pixelSize: 16
				font.family: "JetBrainsMono Nerd Font"
				Layout.preferredWidth: 20
				MouseArea {
					anchors.fill: parent
					anchors.margins: -4
					cursorShape: Qt.PointingHandCursor
					onClicked: eqPanel.toggleMute(blk.dev)
				}
			}
			Item {
				Layout.fillWidth: true
				height: 18
				readonly property int v: blk.dev ? blk.dev.vol : 0
				readonly property bool m: blk.dev ? blk.dev.muted : false
				Rectangle {
					id: track
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width
					height: 6
					radius: 3
					color: root.card(0.45)
					Rectangle {
						width: parent.width * Math.min(100, parent.parent.v) / 100
						height: parent.height
						radius: 3
						color: parent.parent.m ? root.walColor8 : blk.accent
					}
				}
				Rectangle {
					x: track.width * Math.min(100, parent.v) / 100 - width / 2
					anchors.verticalCenter: parent.verticalCenter
					width: 14; height: 14; radius: 7
					color: root.walForeground
					border.width: 2
					border.color: parent.m ? root.walColor8 : blk.accent
				}
				MouseArea {
					anchors.fill: parent
					anchors.topMargin: -6
					anchors.bottomMargin: -6
					cursorShape: Qt.PointingHandCursor
					property real acc: 0
					onPressed: function(mouse) { eqPanel.setDevVolume(blk.dev, mouse.x / width * 100) }
					onPositionChanged: function(mouse) { if (pressed) eqPanel.setDevVolume(blk.dev, mouse.x / width * 100) }
					onWheel: function(wheel) {
						acc += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 4
						var n = acc >= 0 ? Math.floor(acc / 120) : Math.ceil(acc / 120)
						if (n === 0) return
						acc -= n * 120
						eqPanel.setDevVolume(blk.dev, (blk.dev ? blk.dev.vol : 0) + n * 5)
					}
				}
			}
			Text {
				text: blk.dev ? (blk.dev.muted ? "muted" : blk.dev.vol + "%") : ""
				color: root.walColor8
				font.pixelSize: 11
				font.family: "JetBrainsMono Nerd Font"
				Layout.preferredWidth: 42
				horizontalAlignment: Text.AlignRight
			}
		}
	}

	Item {
		anchors.fill: parent
		focus: root.eqVisible
		Keys.onPressed: function(event) {
			if (event.key === Qt.Key_Escape) { root.eqVisible = false; event.accepted = true }
			else if (event.key === Qt.Key_E) { root.setEqEnabled(!root.eqEnabled); event.accepted = true }
			else if (event.key === Qt.Key_0) { root.applyEqPreset("Flat"); event.accepted = true }
			else if (event.key === Qt.Key_M) { eqPanel.toggleMute(eqPanel.inDev); event.accepted = true }
		}

		Rectangle {
			id: card
			width: parent.width
			anchors.bottom: parent.bottom
			implicitHeight: col.implicitHeight + 32
			radius: 18
			color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.95)
			border.width: 1
			border.color: Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.45)

			ColumnLayout {
				id: col
				anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
				spacing: 12

				// ── Header ──────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Text {
						text: "󰺢"
						color: root.walColor13
						font.pixelSize: 20
						font.family: "JetBrainsMono Nerd Font"
					}
					ColumnLayout {
						spacing: 0
						Layout.fillWidth: true
						Text {
							text: "Sound"
							color: root.walColor5
							font.pixelSize: 15
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
						}
						Text {
							text: eqPanel.sinkName !== "" ? "→ " + eqPanel.sinkName : "default output"
							color: root.walColor8
							font.pixelSize: 9
							font.family: "JetBrainsMono Nerd Font"
							elide: Text.ElideRight
							Layout.fillWidth: true
						}
					}
					Text {
						text: root.eqEnabled ? "EQ ON" : "EQ OFF"
						color: root.eqEnabled ? root.walColor2 : root.walColor8
						font.pixelSize: 10
						font.bold: true
						font.family: "JetBrainsMono Nerd Font"
					}
					Rectangle {
						width: 44; height: 24; radius: 12
						color: root.eqEnabled ? root.walColor13 : Qt.rgba(0.3, 0.3, 0.3, 0.5)
						Behavior on color { ColorAnimation { duration: 200 } }
						Rectangle {
							width: 20; height: 20; radius: 10; y: 2
							x: root.eqEnabled ? 22 : 2
							color: root.walBackground
							Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
						}
						MouseArea {
							anchors.fill: parent
							cursorShape: Qt.PointingHandCursor
							onClicked: root.setEqEnabled(!root.eqEnabled)
						}
					}
				}

				// ── Output + microphone ─────────────────────────────────
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: devCol.implicitHeight + 24
					radius: 14
					color: root.card(0.3)
					ColumnLayout {
						id: devCol
						anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
						spacing: 12
						DeviceBlock {
							title: "OUTPUT"
							list: eqPanel.sinks
							dev: eqPanel.outDev
							accent: root.walColor5
						}
						Rectangle { Layout.fillWidth: true; height: 1; color: root.card(0.5) }
						DeviceBlock {
							title: "MICROPHONE"
							list: eqPanel.sources
							dev: eqPanel.inDev
							accent: root.walPeach
						}
					}
				}

				// ── Equalizer ───────────────────────────────────────────
				Text {
					text: "EQUALIZER" + (root.eqEnabled ? "" : "  ·  off — switch it on at the top")
					color: root.walColor8
					font.pixelSize: 9
					font.bold: true
					font.letterSpacing: 0.8
					font.family: "JetBrainsMono Nerd Font"
				}

				// ── Bands ───────────────────────────────────────────────
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 214
					radius: 14
					color: root.card(0.35)
					opacity: root.eqEnabled ? 1 : 0.55
					Behavior on opacity { NumberAnimation { duration: 200 } }

					Item {
						id: bandArea
						anchors.fill: parent
						anchors.margins: 12
						readonly property real colW: width / 10
						readonly property real trackTop: 20
						readonly property real trackH: height - 44

						// dB grid
						Repeater {
							model: [12, 6, 0, -6, -12]
							delegate: Item {
								required property var modelData
								width: bandArea.width
								y: bandArea.trackTop + bandArea.trackH * (0.5 - modelData / (2 * eqPanel.maxDb))
								Rectangle {
									width: parent.width
									height: 1
									color: modelData === 0
										? Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.35)
										: Qt.rgba(root.walColor8.r, root.walColor8.g, root.walColor8.b, 0.15)
								}
							}
						}

						// response curve through the knobs
						Canvas {
							id: curve
							anchors.fill: parent
							property var gains: root.eqGains
							property color stroke: root.walColor13
							onGainsChanged: requestPaint()
							onStrokeChanged: requestPaint()
							onWidthChanged: requestPaint()
							onPaint: {
								var ctx = getContext("2d")
								ctx.clearRect(0, 0, width, height)
								if (!gains || gains.length < 10) return
								var pts = []
								for (var i = 0; i < 10; i++)
									pts.push({ x: bandArea.colW * (i + 0.5),
									           y: bandArea.trackTop + bandArea.trackH * (0.5 - gains[i] / (2 * eqPanel.maxDb)) })
								ctx.beginPath()
								ctx.moveTo(pts[0].x, pts[0].y)
								for (var j = 1; j < pts.length; j++) {
									var mx = (pts[j - 1].x + pts[j].x) / 2
									ctx.bezierCurveTo(mx, pts[j - 1].y, mx, pts[j].y, pts[j].x, pts[j].y)
								}
								ctx.strokeStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.55)
								ctx.lineWidth = 2
								ctx.stroke()
								ctx.lineTo(pts[9].x, bandArea.trackTop + bandArea.trackH / 2)
								ctx.lineTo(pts[0].x, bandArea.trackTop + bandArea.trackH / 2)
								ctx.closePath()
								ctx.fillStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.10)
								ctx.fill()
							}
						}

						Repeater {
							model: 10
							delegate: Item {
								id: band
								required property int index
								readonly property real gain: root.eqGains[index] || 0
								readonly property color tint: gain >= 0 ? root.walColor13 : root.walColor6
								x: bandArea.colW * index
								width: bandArea.colW
								height: bandArea.height

								Text {
									anchors.horizontalCenter: parent.horizontalCenter
									y: 0
									text: eqPanel.fmtDb(band.gain)
									color: band.gain === 0 ? root.walColor8 : band.tint
									font.pixelSize: 9
									font.bold: band.gain !== 0
									font.family: "JetBrainsMono Nerd Font"
								}
								Rectangle {
									id: track
									anchors.horizontalCenter: parent.horizontalCenter
									y: bandArea.trackTop
									width: 4
									height: bandArea.trackH
									radius: 2
									color: root.card(0.5)
									Rectangle {
										readonly property real mid: track.height / 2
										readonly property real off: track.height * band.gain / (2 * eqPanel.maxDb)
										width: parent.width
										radius: 2
										y: off >= 0 ? mid - off : mid
										height: Math.abs(off)
										color: band.tint
									}
								}
								Rectangle {
									id: knob
									anchors.horizontalCenter: parent.horizontalCenter
									y: bandArea.trackTop + bandArea.trackH * (0.5 - band.gain / (2 * eqPanel.maxDb)) - height / 2
									width: bandMa.containsMouse || bandMa.pressed ? 18 : 14
									height: width
									radius: width / 2
									color: root.walForeground
									border.width: 3
									border.color: band.tint
									Behavior on width { NumberAnimation { duration: 100 } }
								}
								Text {
									anchors.horizontalCenter: parent.horizontalCenter
									anchors.bottom: parent.bottom
									text: eqPanel.freqLabels[band.index]
									color: bandMa.containsMouse ? root.walForeground : root.walColor8
									font.pixelSize: 9
									font.family: "JetBrainsMono Nerd Font"
								}
								MouseArea {
									id: bandMa
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.SizeVerCursor
									function setFromY(y) {
										var rel = (y - bandArea.trackTop) / bandArea.trackH
										var g = (0.5 - rel) * 2 * eqPanel.maxDb
										root.setEqGain(band.index, Math.round(Math.max(-eqPanel.maxDb, Math.min(eqPanel.maxDb, g)) * 2) / 2)
									}
									onPressed: function(mouse) { setFromY(mouse.y) }
									onPositionChanged: function(mouse) { if (pressed) setFromY(mouse.y) }
									onDoubleClicked: root.setEqGain(band.index, 0)
									onWheel: function(wheel) { root.setEqGain(band.index, band.gain + (wheel.angleDelta.y > 0 ? 0.5 : -0.5)) }
								}
							}
						}
					}
				}

				// ── Presets ─────────────────────────────────────────────
				Flow {
					Layout.fillWidth: true
					spacing: 6
					Repeater {
						model: eqPanel.presetNames
						delegate: Rectangle {
							required property string modelData
							readonly property bool active: root.eqPreset === modelData
							width: presetText.implicitWidth + 20
							height: 26
							radius: 13
							color: active
								? Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.25)
								: (presetMa.containsMouse ? root.hover(0.08) : root.card(0.35))
							border.width: active ? 1 : 0
							border.color: Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.6)
							Behavior on color { ColorAnimation { duration: 120 } }
							Text {
								id: presetText
								anchors.centerIn: parent
								text: modelData
								color: active ? root.walColor13 : root.walForeground
								font.pixelSize: 10
								font.bold: active
								font.family: "JetBrainsMono Nerd Font"
							}
							MouseArea {
								id: presetMa
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.applyEqPreset(modelData)
							}
						}
					}
					Rectangle {
						visible: root.eqPreset === "Custom"
						width: customText.implicitWidth + 20
						height: 26
						radius: 13
						color: Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.25)
						Text {
							id: customText
							anchors.centerIn: parent
							text: "Custom"
							color: root.walColor13
							font.pixelSize: 10
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
						}
					}
				}

				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 22
					radius: 8
					color: root.card(0.3)
					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 10
						anchors.rightMargin: 10
						Text { text: "drag / scroll bands"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "double-click = 0 dB"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "e on/off · esc close"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
					}
				}
			}
		}
	}

	Connections {
		target: root
		function onEqVisibleChanged() { if (root.eqVisible) focusTimer.start() }
	}
	Timer {
		id: focusTimer
		interval: 50
		onTriggered: {
			eqPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive
			releaseTimer.start()
		}
	}
	Timer {
		id: releaseTimer
		interval: 100
		onTriggered: eqPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
	}
}

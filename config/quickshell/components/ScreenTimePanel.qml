import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// ScreenTimePanel.qml — click the battery notch. Tracking runs in shell.qml (root.st*)
// every 5 s and is stored in ~/.local/share/quickshell/screentime.json (35 days kept).
//   Total / chart : time you were at the computer (not idle 2 min, not locked)
//   Active        : per app — focused, visible on any monitor, or playing media
//   Open          : per app — has a window open on any workspace (or is playing media)

PanelWindow {
	id: stPanel
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: true
	exclusionMode: ExclusionMode.Ignore
	anchors {
		bottom: root.barPosition !== "top"
		right: true
		top: root.barPosition === "top"
	}
	margins {
		bottom: root.screenTimeVisible ? root.barGapV : -(implicitHeight + 20)
		right: (6) + root.barInsetRight
		top: root.screenTimeVisible ? root.barGapV : -(implicitHeight + 20)
	}
	implicitWidth: 400
	implicitHeight: card.implicitHeight
	color: "transparent"
	focusable: true
	WlrLayershell.keyboardFocus: root.screenTimeVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

	Behavior on margins.bottom {
		NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
	}
	Behavior on margins.top {
		NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
	}

	property int mode: 0          // 0 = day, 1 = week
	property int dayOffset: 0     // 0 = today, 1 = yesterday …
	property int weekOffset: 0    // week view: 0 = last 7 days, 1 = the 7 before … (history keeps ~5 weeks)
	property string battery: ""
	property int metric: 0        // 0 = active, 1 = open
	property bool expanded: false
	readonly property int collapsedCount: 5

	readonly property var palette: [root.walColor5, root.walColor13, root.walColor2, root.walColor4,
	                                root.walColor6, root.walColor12, root.walPeach, root.walColor1]

	function keyFor(offset) {
		var d = new Date()
		d.setDate(d.getDate() - offset)
		return Qt.formatDate(d, "yyyy-MM-dd")
	}
	function dayData(offset) {
		var x = root.stData[keyFor(offset)]
		return x ? x : { apps: {}, hours: [] }
	}
	// wall-clock screen time (per-app times overlap, so they don't add up to this)
	function dayTotal(offset) {
		var d = dayData(offset), t = 0
		if (d.hours && d.hours.length) {
			for (var h = 0; h < d.hours.length; h++) t += d.hours[h] || 0
			return t
		}
		for (var k in d.apps) t += d.apps[k]
		return t
	}
	function appsOf(offset) {
		var d = dayData(offset)
		return (metric === 1 ? d.open : d.apps) || {}
	}
	function fmt(secs) {
		secs = Math.round(secs)
		var h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
		if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
		if (m > 0) return m + "m"
		return secs + "s"
	}

	// recomputed whenever stData / view changes
	readonly property var view: {
		var dummy = root.stData   // dependency
		var dummy2 = metric
		var apps = {}, total = 0
		var days = mode === 0 ? [dayOffset] : [0, 1, 2, 3, 4, 5, 6].map(function(i) { return weekOffset * 7 + i })
		for (var i = 0; i < days.length; i++) {
			var a = appsOf(days[i])
			for (var k in a) apps[k] = (apps[k] || 0) + a[k]
			total += dayTotal(days[i])
		}
		var list = []
		for (var c in apps) list.push({ cls: c, secs: apps[c] })
		list.sort(function(x, y) { return y.secs - x.secs })
		var bars = []
		if (mode === 0) {
			var hrs = dayData(dayOffset).hours || []
			for (var h = 0; h < 24; h++) bars.push({ label: h % 6 === 0 ? (h < 10 ? "0" + h : "" + h) : "", value: hrs[h] || 0, day: -1 })
		} else {
			for (var o = weekOffset * 7 + 6; o >= weekOffset * 7; o--) {
				var d = new Date(); d.setDate(d.getDate() - o)
				bars.push({ label: Qt.formatDate(d, "ddd").substring(0, 2), date: Qt.formatDate(d, "ddd, MMM d"), value: dayTotal(o), day: o })
			}
		}
		var max = 1
		for (var b = 0; b < bars.length; b++) max = Math.max(max, bars[b].value)
		return { total: total, apps: list, bars: bars, max: max, avg: mode === 1 ? total / 7 : 0 }
	}
	readonly property string subtitle: {
		if (mode === 1) {
			var a = new Date(); a.setDate(a.getDate() - (weekOffset * 7 + 6))
			var b = new Date(); b.setDate(b.getDate() - weekOffset * 7)
			var range = weekOffset === 0 ? "last 7 days" : Qt.formatDate(a, "MMM d") + " – " + Qt.formatDate(b, "MMM d")
			var prev = 0
			for (var i = 0; i < 7; i++) prev += dayTotal((weekOffset + 1) * 7 + i)
			var cmp = prev > 0 ? " · " + (view.total >= prev ? "+" : "−") + fmt(Math.abs(view.total - prev)) + " vs week before" : ""
			return range + " · avg " + fmt(view.avg) + " / day" + cmp
		}
		if (dayOffset === 0) {
			var y = dayTotal(1)
			if (y <= 0) return "today"
			var diff = view.total - y
			return "today · " + (diff >= 0 ? "+" : "−") + fmt(Math.abs(diff)) + " vs yesterday"
		}
		if (dayOffset === 1) return "yesterday"
		var d = new Date(); d.setDate(d.getDate() - dayOffset)
		return Qt.formatDate(d, "dddd, MMM d")
	}

	Process {
		id: batProc
		command: ["bash", "-c", "c=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); s=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); t=''; if command -v upower >/dev/null; then t=$(upower -i $(upower -e | grep BAT | head -1) 2>/dev/null | awk -F: '/time to (empty|full)/ {gsub(/^ +/,\"\",$2); print $2; exit}'); fi; echo \"${c:-?}|${s:-Unknown}|$t\""]
		stdout: SplitParser {
			onRead: data => {
				var p = data.trim().split("|")
				var s = p[0] + "% · " + p[1]
				if (p[2]) s += " · " + p[2] + (p[1] === "Charging" ? " to full" : " left")
				stPanel.battery = s
			}
		}
	}
	Timer {
		interval: 30000
		running: root.screenTimeVisible
		repeat: true
		triggeredOnStart: true
		onTriggered: if (!batProc.running) batProc.running = true
	}

	Item {
		anchors.fill: parent
		focus: root.screenTimeVisible
		Keys.onPressed: function(event) {
			if (event.key === Qt.Key_Escape) { root.screenTimeVisible = false; event.accepted = true }
			else if (event.key === Qt.Key_Left) { if (stPanel.mode === 1) stPanel.weekOffset = Math.min(4, stPanel.weekOffset + 1); else stPanel.dayOffset = Math.min(34, stPanel.dayOffset + 1); event.accepted = true }
			else if (event.key === Qt.Key_Right) { if (stPanel.mode === 1) stPanel.weekOffset = Math.max(0, stPanel.weekOffset - 1); else stPanel.dayOffset = Math.max(0, stPanel.dayOffset - 1); event.accepted = true }
			else if (event.key === Qt.Key_Tab) { stPanel.mode = 1 - stPanel.mode; event.accepted = true }
			else if (event.key === Qt.Key_O) { stPanel.metric = 1 - stPanel.metric; event.accepted = true }
			else if (event.key === Qt.Key_Space) { stPanel.expanded = !stPanel.expanded; event.accepted = true }
		}

		Rectangle {
			id: card
			width: parent.width
			anchors.bottom: parent.bottom
			implicitHeight: col.implicitHeight + 32
			radius: 18
			color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.95)
			border.width: 1
			border.color: Qt.rgba(root.walColor2.r, root.walColor2.g, root.walColor2.b, 0.45)

			ColumnLayout {
				id: col
				anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
				spacing: 12

				// ── Header ──────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Text {
						text: "󱎫"
						color: root.walColor2
						font.pixelSize: 20
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: "Screen Time"
						color: root.walColor5
						font.pixelSize: 15
						font.bold: true
						font.family: "JetBrainsMono Nerd Font"
						Layout.fillWidth: true
					}
					Rectangle {
						width: 116; height: 26; radius: 13
						color: root.card(0.35)
						Row {
							anchors.centerIn: parent
							spacing: 2
							Repeater {
								model: ["Day", "Week"]
								delegate: Rectangle {
									required property string modelData
									required property int index
									width: 54; height: 22; radius: 11
									color: stPanel.mode === index ? Qt.rgba(root.walColor2.r, root.walColor2.g, root.walColor2.b, 0.25) : "transparent"
									Text {
										anchors.centerIn: parent
										text: modelData
										color: stPanel.mode === index ? root.walColor2 : root.walColor8
										font.pixelSize: 10
										font.bold: stPanel.mode === index
										font.family: "JetBrainsMono Nerd Font"
									}
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: stPanel.mode = index
									}
								}
							}
						}
					}
				}

				// battery line (the panel opens from the battery notch)
				RowLayout {
					Layout.fillWidth: true
					spacing: 6
					Text {
						text: "󰁹"
						color: root.walColor2
						font.pixelSize: 12
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: stPanel.battery
						color: root.walColor8
						font.pixelSize: 10
						font.family: "JetBrainsMono Nerd Font"
						Layout.fillWidth: true
						elide: Text.ElideRight
					}
					Text {
						visible: root.stIdle
						text: "idle · paused"
						color: root.walColor4
						font.pixelSize: 9
						font.family: "JetBrainsMono Nerd Font"
					}
				}

				// ── Total ───────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Text {
						text: "󰅁"
						opacity: (stPanel.mode === 1 ? stPanel.weekOffset < 4 : stPanel.dayOffset < 34) ? 1 : 0.25
						color: arrowL.containsMouse ? root.walForeground : root.walColor8
						font.pixelSize: 16
						font.family: "JetBrainsMono Nerd Font"
						MouseArea {
							id: arrowL
							anchors.fill: parent
							anchors.margins: -6
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: if (stPanel.mode === 1) stPanel.weekOffset = Math.min(4, stPanel.weekOffset + 1); else stPanel.dayOffset = Math.min(34, stPanel.dayOffset + 1)
						}
					}
					ColumnLayout {
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						spacing: 0
						Text {
							text: stPanel.fmt(stPanel.view.total)
							color: root.walForeground
							font.pixelSize: 28
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
						}
						Text {
							text: stPanel.subtitle
							color: root.walColor8
							font.pixelSize: 10
							font.family: "JetBrainsMono Nerd Font"
							Layout.fillWidth: true
							elide: Text.ElideRight
						}
					}
					Rectangle {
						// jump straight back to today / this week
						id: stNowBtn
						visible: (stPanel.mode === 1 ? stPanel.weekOffset : stPanel.dayOffset) > 0
						implicitWidth: nowLbl.implicitWidth + 14
						implicitHeight: 20
						radius: 10
						color: nowMa.containsMouse ? Qt.rgba(root.walColor5.r, root.walColor5.g, root.walColor5.b, 0.30) : Qt.rgba(root.walColor5.r, root.walColor5.g, root.walColor5.b, 0.16)
						Text {
							id: nowLbl
							anchors.centerIn: parent
							text: stPanel.mode === 1 ? "this week" : "today"
							color: root.walColor5
							font.pixelSize: 9
							font.bold: true
							font.family: "JetBrainsMono Nerd Font"
						}
						MouseArea {
							id: nowMa
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: { stPanel.weekOffset = 0; stPanel.dayOffset = 0 }
						}
					}
					Text {
						text: "󰅂"
						opacity: (stPanel.mode === 1 ? stPanel.weekOffset : stPanel.dayOffset) > 0 ? 1 : 0.25
						color: arrowR.containsMouse ? root.walForeground : root.walColor8
						font.pixelSize: 16
						font.family: "JetBrainsMono Nerd Font"
						MouseArea {
							id: arrowR
							anchors.fill: parent
							anchors.margins: -6
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: if (stPanel.mode === 1) stPanel.weekOffset = Math.max(0, stPanel.weekOffset - 1); else stPanel.dayOffset = Math.max(0, stPanel.dayOffset - 1)
						}
					}
				}

				// ── Chart ───────────────────────────────────────────────
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 118
					radius: 12
					color: root.card(0.35)
					Item {
						id: chart
						anchors.fill: parent
						anchors.margins: 10
						readonly property int n: stPanel.view.bars.length
						readonly property real gap: n > 10 ? 3 : 10
						readonly property real barW: (width - (n - 1) * gap) / n
						property string hoverText: ""
						Text {
							anchors.top: parent.top
							anchors.right: parent.right
							text: chart.hoverText
							color: root.walForeground
							font.pixelSize: 9
							font.family: "JetBrainsMono Nerd Font"
						}
						Repeater {
							model: stPanel.view.bars
							delegate: Item {
								required property var modelData
								required property int index
								x: index * (chart.barW + chart.gap)
								width: chart.barW
								height: chart.height
								readonly property bool selected: stPanel.mode === 1 && modelData.day === stPanel.dayOffset
								Rectangle {
									anchors.bottom: barLabel.top
									anchors.bottomMargin: 4
									width: parent.width
									height: Math.max(2, (parent.height - 34) * modelData.value / stPanel.view.max)
									radius: Math.min(width / 2, 4)
									color: barMa.containsMouse || parent.selected ? root.walColor2
										: Qt.rgba(root.walColor2.r, root.walColor2.g, root.walColor2.b, modelData.value > 0 ? 0.55 : 0.15)
									Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
								}
								Text {
									id: barLabel
									anchors.bottom: parent.bottom
									anchors.horizontalCenter: parent.horizontalCenter
									text: modelData.label
									color: root.walColor8
									font.pixelSize: 9
									font.family: "JetBrainsMono Nerd Font"
								}
								MouseArea {
									id: barMa
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: stPanel.mode === 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
									onEntered: chart.hoverText = (stPanel.mode === 0
										? (index < 10 ? "0" : "") + index + ":00 · "
										: modelData.date + " · ") + stPanel.fmt(modelData.value)
									onExited: chart.hoverText = ""
									onClicked: if (stPanel.mode === 1) { stPanel.dayOffset = modelData.day; stPanel.mode = 0 }
								}
							}
						}
					}
				}

				// ── Apps ────────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: 8
					Text {
						text: stPanel.view.apps.length === 0 ? "No activity recorded yet" : "Most used"
						color: root.walColor8
						font.pixelSize: 10
						font.bold: true
						font.letterSpacing: 0.5
						font.family: "JetBrainsMono Nerd Font"
					}
					Text {
						text: stPanel.metric === 0 ? "focused · on screen · playing" : "window open anywhere"
						color: root.walColor8
						opacity: 0.6
						font.pixelSize: 9
						font.family: "JetBrainsMono Nerd Font"
						elide: Text.ElideRight
						Layout.fillWidth: true
					}
					Rectangle {
						width: 112; height: 22; radius: 11
						color: root.card(0.35)
						Row {
							anchors.centerIn: parent
							spacing: 2
							Repeater {
								model: ["Active", "Open"]
								delegate: Rectangle {
									required property string modelData
									required property int index
									width: 54; height: 18; radius: 9
									color: stPanel.metric === index ? Qt.rgba(root.walColor13.r, root.walColor13.g, root.walColor13.b, 0.25) : "transparent"
									Text {
										anchors.centerIn: parent
										text: modelData
										color: stPanel.metric === index ? root.walColor13 : root.walColor8
										font.pixelSize: 9
										font.bold: stPanel.metric === index
										font.family: "JetBrainsMono Nerd Font"
									}
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: stPanel.metric = index
									}
								}
							}
						}
					}
				}
				Flickable {
					id: appFlick
					Layout.fillWidth: true
					readonly property int rowH: 36
					readonly property int shown: stPanel.expanded ? stPanel.view.apps.length : Math.min(stPanel.collapsedCount, stPanel.view.apps.length)
					// expanded list scrolls after 8 rows instead of growing forever
					Layout.preferredHeight: Math.min(shown, 8) * rowH
					contentHeight: appCol.implicitHeight
					clip: true
					interactive: contentHeight > height
					boundsBehavior: Flickable.StopAtBounds
					Column {
						id: appCol
						width: appFlick.width
						Repeater {
							model: stPanel.view.apps.slice(0, appFlick.shown)
							delegate: Item {
								required property var modelData
								required property int index
								readonly property color tint: stPanel.palette[index % stPanel.palette.length]
								width: appCol.width
								height: appFlick.rowH
								RowLayout {
									anchors.fill: parent
									anchors.rightMargin: appFlick.interactive ? 6 : 0
									spacing: 10
									Rectangle {
										width: 30; height: 30; radius: 9
										color: Qt.rgba(tint.r, tint.g, tint.b, 0.18)
										Image {
											id: appIcon
											anchors.centerIn: parent
											width: 20; height: 20
											source: root.iconFor(modelData.cls)
											sourceSize: Qt.size(40, 40)
											asynchronous: true
											visible: status === Image.Ready
										}
										Text {
											anchors.centerIn: parent
											visible: appIcon.status !== Image.Ready
											text: modelData.cls.charAt(0).toUpperCase()
											color: tint
											font.pixelSize: 13
											font.bold: true
											font.family: "JetBrainsMono Nerd Font"
										}
									}
									ColumnLayout {
										Layout.fillWidth: true
										spacing: 3
										RowLayout {
											Layout.fillWidth: true
											Text {
												text: root.prettyName(modelData.cls)
												color: root.walForeground
												font.pixelSize: 11
												font.bold: true
												font.family: "JetBrainsMono Nerd Font"
												elide: Text.ElideRight
												Layout.fillWidth: true
											}
											Text {
												text: stPanel.fmt(modelData.secs)
												color: tint
												font.pixelSize: 11
												font.bold: true
												font.family: "JetBrainsMono Nerd Font"
											}
										}
										Rectangle {
											Layout.fillWidth: true
											height: 4
											radius: 2
											color: root.card(0.4)
											Rectangle {
												width: parent.width * (stPanel.view.apps.length ? modelData.secs / stPanel.view.apps[0].secs : 0)
												height: parent.height
												radius: 2
												color: tint
												Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
											}
										}
									}
								}
							}
						}
					}
					// thin scroll indicator
					Rectangle {
						visible: appFlick.interactive
						x: appFlick.width - 3
						y: appFlick.contentY + appFlick.height * appFlick.visibleArea.yPosition
						width: 3
						height: appFlick.height * appFlick.visibleArea.heightRatio
						radius: 1.5
						color: root.walColor8
						opacity: 0.5
					}
				}
				// show more / less
				Rectangle {
					visible: stPanel.view.apps.length > stPanel.collapsedCount
					Layout.fillWidth: true
					Layout.preferredHeight: 24
					radius: 8
					color: moreMa.containsMouse ? root.hover(0.5) : root.card(0.25)
					Text {
						anchors.centerIn: parent
						text: stPanel.expanded ? "󰅃  Show less" : "󰅀  Show all " + stPanel.view.apps.length + " apps"
						color: root.walColor13
						font.pixelSize: 10
						font.bold: true
						font.family: "JetBrainsMono Nerd Font"
					}
					MouseArea {
						id: moreMa
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: { stPanel.expanded = !stPanel.expanded; appFlick.contentY = 0 }
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
						Text { text: "←→ day"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "tab day/week · o active/open"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
						Item { Layout.fillWidth: true }
						Text { text: "esc close"; color: root.walColor8; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font"; opacity: 0.7 }
					}
				}
			}
		}
	}

	Connections {
		target: root
		function onScreenTimeVisibleChanged() {
			if (root.screenTimeVisible) {
				stPanel.mode = 0
				stPanel.dayOffset = 0
				stPanel.weekOffset = 0
				stPanel.expanded = false
				root.stSave()
				focusTimer.start()
			}
		}
	}
	Timer {
		id: focusTimer
		interval: 50
		onTriggered: {
			stPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive
			releaseTimer.start()
		}
	}
	Timer {
		id: releaseTimer
		interval: 100
		onTriggered: stPanel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
	}
}

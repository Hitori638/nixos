import Quickshell
import Quickshell.Wayland
import QtQuick

// BlastOverlay.qml — the pomodoro "BOOM": fullscreen flash, shockwaves, debris.
// Click-through overlay layer; shown for ~1.8s whenever root.pomoBlast is set.

PanelWindow {
	id: blastWin
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: root.pomoBlast
	anchors { top: true; bottom: true; left: true; right: true }
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell:blast"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
	mask: Region {}

	Timer {
		running: root.pomoBlast
		interval: 1800
		onTriggered: root.pomoBlast = false
	}

	Loader {
		anchors.fill: parent
		active: root.pomoBlast
		sourceComponent: Item {
			id: stage
			readonly property real span: Math.max(width, height)

			Rectangle {
				id: flash
				anchors.fill: parent
				color: root.walColor4
				opacity: 0.0
			}

			Repeater {
				model: 3
				delegate: Rectangle {
					id: ring
					required property int index
					anchors.centerIn: parent
					width: 10
					height: 10
					radius: width / 2
					color: "transparent"
					border.width: 6
					border.color: index === 0 ? root.walColor4 : (index === 1 ? root.walPeach : root.walColor1)
					opacity: 0.0
					Component.onCompleted: ringSeq.start()
					SequentialAnimation {
						id: ringSeq
						PauseAnimation { duration: ring.index * 70 }
						ParallelAnimation {
							NumberAnimation { target: ring; property: "width"; to: stage.span * 1.4; duration: 650; easing.type: Easing.OutCubic }
							NumberAnimation { target: ring; property: "height"; to: stage.span * 1.4; duration: 650; easing.type: Easing.OutCubic }
							NumberAnimation { target: ring; property: "opacity"; from: 0.85; to: 0.0; duration: 650 }
						}
					}
				}
			}

			Repeater {
				model: 40
				delegate: Rectangle {
					id: piece
					property real angle: Math.random() * Math.PI * 2
					property real dist: 140 + Math.random() * (Math.min(stage.width, stage.height) * 0.55)
					x: stage.width / 2
					y: stage.height / 2
					width: 6 + Math.random() * 10
					height: width
					radius: Math.random() > 0.5 ? width / 2 : 2
					color: [root.walColor1, root.walPeach, root.walColor4, "#4a3624", root.walColor5][Math.floor(Math.random() * 5)]
					opacity: 0.0
					rotation: Math.random() * 360
					Component.onCompleted: pieceSeq.start()
					SequentialAnimation {
						id: pieceSeq
						PauseAnimation { duration: Math.random() * 80 }
						ParallelAnimation {
							NumberAnimation { target: piece; property: "x"; to: stage.width / 2 + Math.cos(piece.angle) * piece.dist; duration: 550 + Math.random() * 250; easing.type: Easing.OutCubic }
							NumberAnimation { target: piece; property: "y"; to: stage.height / 2 + Math.sin(piece.angle) * piece.dist; duration: 550 + Math.random() * 250; easing.type: Easing.OutCubic }
							NumberAnimation { target: piece; property: "opacity"; from: 1.0; to: 0.0; duration: 750; easing.type: Easing.InCubic }
							NumberAnimation { target: piece; property: "rotation"; to: piece.rotation + (Math.random() > 0.5 ? 1 : -1) * 360; duration: 750 }
						}
					}
				}
			}

			Text {
				id: boomText
				anchors.centerIn: parent
				text: root.pomoPhase === "focus" ? "BACK TO IT" : "BOOM"
				color: root.walColor1
				font.pixelSize: Math.min(stage.width, stage.height) * (root.pomoPhase === "focus" ? 0.13 : 0.22)
				font.bold: true
				font.family: "JetBrainsMono Nerd Font"
				style: Text.Outline
				styleColor: "#000000"
				opacity: 0.0
				scale: 0.4
			}

			Component.onCompleted: masterSeq.start()
			SequentialAnimation {
				id: masterSeq
				ParallelAnimation {
					NumberAnimation { target: flash; property: "opacity"; from: 0.0; to: 0.85; duration: 60 }
					NumberAnimation { target: boomText; property: "opacity"; from: 0.0; to: 1.0; duration: 140 }
					NumberAnimation { target: boomText; property: "scale"; from: 0.4; to: 1.15; duration: 240; easing.type: Easing.OutBack }
				}
				NumberAnimation { target: flash; property: "opacity"; to: 0.0; duration: 380 }
				ParallelAnimation {
					NumberAnimation { target: boomText; property: "opacity"; to: 0.0; duration: 450 }
					NumberAnimation { target: boomText; property: "scale"; to: 1.4; duration: 450 }
				}
			}
		}
	}
}

import Quickshell
import Quickshell.Wayland
import QtQuick

// PomoZen.qml — tiny click-through timer pill at the top while a focus session hides the bar.
PanelWindow {
	id: zen
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: pill.opacity > 0
	exclusionMode: ExclusionMode.Ignore
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "quickshell-pomozen"
	anchors { top: true }
	margins { top: 8 }
	implicitWidth: pill.width + 4
	implicitHeight: pill.height + 4
	color: "transparent"
	mask: Region {}            // never takes clicks

	Rectangle {
		id: pill
		anchors.centerIn: parent
		width: row.implicitWidth + 24
		height: 26
		radius: 13
		color: Qt.rgba(root.walBackground.r, root.walBackground.g, root.walBackground.b, 0.82)
		border.width: 1
		border.color: Qt.rgba(root.pomoColor.r, root.pomoColor.g, root.pomoColor.b, 0.45)
		opacity: root.pomoZen && !root.barShown ? 0.9 : 0
		Behavior on opacity { NumberAnimation { duration: 300 } }
		Row {
			id: row
			anchors.centerIn: parent
			spacing: 8
			Text { text: "󰔟"; color: root.pomoColor; font.pixelSize: 13; font.family: "JetBrainsMono Nerd Font"; anchors.verticalCenter: parent.verticalCenter }
			Text { text: root.pomoText; color: root.walForeground; font.pixelSize: 12; font.bold: true; font.family: "JetBrainsMono Nerd Font"; anchors.verticalCenter: parent.verticalCenter }
			Text { text: "focus · 󰂛"; color: root.walColor8; font.pixelSize: 10; font.family: "JetBrainsMono Nerd Font"; anchors.verticalCenter: parent.verticalCenter }
		}
		// thin progress line along the bottom
		Rectangle {
			anchors.bottom: parent.bottom; anchors.bottomMargin: 3
			x: 12; height: 2; radius: 1
			width: (parent.width - 24) * Math.max(0, Math.min(1, root.pomoProgress))
			color: root.pomoColor
			opacity: 0.8
		}
	}
}

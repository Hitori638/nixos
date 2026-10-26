import Quickshell
import Quickshell.Wayland
import QtQuick

// BarReveal.qml — an invisible 3 px strip on the bar's edge while the bar is auto-hidden.
// Touch it with the pointer and the bar slides in (root.barPeek).

PanelWindow {
	id: strip
	screen: Quickshell.screens.length > 0 ? (root.focusedScreen ?? Quickshell.screens[0]) : undefined
	visible: root.barMode === "auto" && !root.barShown
	exclusionMode: ExclusionMode.Ignore
	WlrLayershell.layer: WlrLayer.Top
	WlrLayershell.namespace: "quickshell-bar-reveal"
	anchors {
		top: root.barPosition !== "bottom"
		bottom: root.barPosition !== "top"
		left: root.barPosition !== "right"
		right: root.barPosition !== "left"
	}
	implicitHeight: 3
	implicitWidth: 3
	color: "transparent"

	MouseArea {
		anchors.fill: parent
		hoverEnabled: true
		onEntered: root.barPeekNow()
	}
}

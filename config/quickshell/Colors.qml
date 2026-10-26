pragma Singleton
import QtQuick

// Colors.qml — shared palette for components that don't read root.wal* directly
// (e.g. NotificationPopup). Follows the shell's colour theme (UIState.pal, set by shell.qml);
// falls back to Catppuccin Mocha / Latte until that's available.

QtObject {
	readonly property bool light: UIState.lightMode
	readonly property var p: UIState.pal

	readonly property color bg:      p ? p.bg      : (light ? "#eff1f5" : "#1e1e2e")
	readonly property color fg:      p ? p.fg      : (light ? "#4c4f69" : "#cdd6f4")
	readonly property color accent:  p ? p.pink    : (light ? "#ea76cb" : "#f5c2e7")
	readonly property color accent2: p ? p.mauve   : (light ? "#8839ef" : "#cba6f7")
	readonly property color green:   p ? p.green   : (light ? "#40a02b" : "#a6e3a1")
	readonly property color red:     p ? p.red     : (light ? "#d20f39" : "#f38ba8")
	readonly property color yellow:  p ? p.yellow  : (light ? "#df8e1d" : "#f9e2af")
	readonly property color teal:    p ? p.teal    : (light ? "#179299" : "#94e2d5")
	readonly property color surface: p ? p.surface : (light ? "#ccd0da" : "#313244")
	readonly property color dim:     p ? p.dim     : (light ? "#8c8fa1" : "#7f849c")

	function a(c, o) {
		return Qt.rgba(c.r, c.g, c.b, o)
	}
}

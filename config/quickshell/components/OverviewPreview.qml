import Quickshell
import Quickshell.Wayland
import QtQuick

// Live preview of one window for the workspace overview. Loaded through a Loader so
// that, if this Quickshell build or the GPU can't capture windows, only the preview
// is missing — the overview falls back to the app icon.
ScreencopyView {
	property var toplevel: null
	captureSource: toplevel && toplevel.wayland ? toplevel.wayland : null
	live: true
}

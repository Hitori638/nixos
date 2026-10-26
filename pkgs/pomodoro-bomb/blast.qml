import QtQuick
import QtQuick.Window

// blast.qml — standalone fullscreen "explosion" overlay.
//
// Deliberately its own top-level app (run via blast_main.py, spawned as a
// separate process by the pomodoro-bomb app) rather than a Window created
// in-process from bomb.qml. Every window opened by a single QGuiApplication
// shares one WM class/app_id, and there's no per-Window override for that
// in QtQuick — so a dynamically-created overlay window in the same process
// as the pomodoro window would match the SAME Hyprland window rules as the
// pomodoro window itself (fixed 180x100 size, pinned to a corner, etc.),
// which is exactly what caused the blast to render tiny and corner-pinned.
// Running as a separate process gives it its own class ("pomodoro-bomb-blast")
// so it can be targeted with its own window rules instead.
//
// Self-terminates via Qt.quit() once the animation finishes.

Window {
    id: blastWin
    title: "pomodoro-bomb-blast"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: true
    width: Screen.width
    height: Screen.height
    x: 0
    y: 0

    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"
    readonly property color yellow: "#f9e2af"
    readonly property color textCol: "#cdd6f4"

    Rectangle {
        id: flash
        anchors.fill: parent
        color: blastWin.yellow
        opacity: 0.0
    }

    Repeater {
        id: shockwaves
        model: 3
        delegate: Rectangle {
            id: ring
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: width / 2
            color: "transparent"
            border.width: 6
            border.color: index === 0 ? blastWin.yellow : (index === 1 ? blastWin.peach : blastWin.red)
            opacity: 0.0
            Component.onCompleted: ringSeq.start()
            SequentialAnimation {
                id: ringSeq
                PauseAnimation { duration: index * 70 }
                ParallelAnimation {
                    NumberAnimation { target: ring; property: "width"; to: Math.max(blastWin.width, blastWin.height) * 1.4; duration: 650; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ring; property: "height"; to: Math.max(blastWin.width, blastWin.height) * 1.4; duration: 650; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ring; property: "opacity"; from: 0.85; to: 0.0; duration: 650 }
                }
            }
        }
    }

    Repeater {
        id: debris
        model: 40
        delegate: Rectangle {
            id: piece
            property real angle: Math.random() * Math.PI * 2
            property real dist: 140 + Math.random() * (Math.min(blastWin.width, blastWin.height) * 0.55)
            x: blastWin.width / 2
            y: blastWin.height / 2
            width: 6 + Math.random() * 10
            height: width
            radius: Math.random() > 0.5 ? width / 2 : 2
            color: [blastWin.red, blastWin.peach, blastWin.yellow, "#4a3624", blastWin.textCol][Math.floor(Math.random() * 5)]
            opacity: 0.0
            rotation: Math.random() * 360
            Component.onCompleted: pieceSeq.start()
            SequentialAnimation {
                id: pieceSeq
                PauseAnimation { duration: Math.random() * 80 }
                ParallelAnimation {
                    NumberAnimation { target: piece; property: "x"; to: blastWin.width / 2 + Math.cos(piece.angle) * piece.dist; duration: 550 + Math.random() * 250; easing.type: Easing.OutCubic }
                    NumberAnimation { target: piece; property: "y"; to: blastWin.height / 2 + Math.sin(piece.angle) * piece.dist; duration: 550 + Math.random() * 250; easing.type: Easing.OutCubic }
                    NumberAnimation { target: piece; property: "opacity"; from: 1.0; to: 0.0; duration: 750; easing.type: Easing.InCubic }
                    NumberAnimation { target: piece; property: "rotation"; to: piece.rotation + (Math.random() > 0.5 ? 1 : -1) * 360; duration: 750 }
                }
            }
        }
    }

    Text {
        id: boomText
        anchors.centerIn: parent
        text: "BOOM"
        color: blastWin.red
        font.pixelSize: Math.min(parent.width, parent.height) * 0.22
        font.bold: true
        font.family: "monospace"
        style: Text.Outline
        styleColor: "#000000"
        opacity: 0.0
        scale: 0.4
    }

    Component.onCompleted: masterSeq.start()
    SequentialAnimation {
        id: masterSeq
        ParallelAnimation {
            NumberAnimation { target: flash; property: "opacity"; from: 0.0; to: 1.0; duration: 60 }
            NumberAnimation { target: boomText; property: "opacity"; from: 0.0; to: 1.0; duration: 140 }
            NumberAnimation { target: boomText; property: "scale"; from: 0.4; to: 1.15; duration: 240; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: flash; property: "opacity"; to: 0.0; duration: 380 }
        ParallelAnimation {
            NumberAnimation { target: boomText; property: "opacity"; to: 0.0; duration: 450 }
            NumberAnimation { target: boomText; property: "scale"; to: 1.4; duration: 450 }
        }
        PauseAnimation { duration: 350 }
        ScriptAction { script: Qt.quit() }
    }
}

#!/usr/bin/env python3
"""
blast_main.py — standalone entry point for the fullscreen "explosion"
overlay (blast.qml). Spawned as its own process by the main pomodoro-bomb
app (see NotifyProxy.spawnBlast in main.py) specifically so it gets its own
window class ("pomodoro-bomb-blast") distinct from the main timer window's
("pomodoro-bomb") — otherwise it would inherit the timer window's Hyprland
rules (fixed 180x100 size, corner pin, etc.), since every window opened by
one QGuiApplication shares the same class/app_id.
"""
import sys
from pathlib import Path

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("pomodoro-bomb-blast")
    app.setDesktopFileName("pomodoro-bomb-blast")

    engine = QQmlApplicationEngine()
    qml_path = Path(__file__).resolve().parent / "blast.qml"
    engine.load(str(qml_path))

    if not engine.rootObjects():
        return 1

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

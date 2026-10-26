#!/usr/bin/env python3
"""
pomodoro-bomb: a standalone, solo-purpose pomodoro timer window
styled as a bundle of dynamite, for Hyprland/NixOS desktops.

Left-click  : start / pause
Right-click : reset current phase
Scroll      : adjust minutes for the current (paused) phase

Cycle: 30 min work + 5 min break, and after every 3rd work session a
15 min long break instead — then the cycle repeats.

On phase end, a fullscreen blast animation plays (see bomb.qml) along with
a synthesized explosion sound (generated once, cached, played via whatever
audio-playback CLI is available on PATH).

Usage:
    python main.py [--work 30] [--break 5] [--long-break 15] [--long-every 3]
"""
import argparse
import math
import random
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

from PySide6.QtCore import QObject, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine


def _explosion_wav_path() -> Path:
    cache_dir = Path.home() / ".cache" / "pomodoro-bomb"
    cache_dir.mkdir(parents=True, exist_ok=True)
    # Versioned name so an old cached sound never gets reused after the
    # synthesis changes.
    return cache_dir / "explosion-boom-v2.wav"


def _ensure_explosion_wav(path: Path) -> None:
    """Synthesize a deep "BOOOOOM" (pitch-dropping sub thump + low-passed
    rolling rumble, no hissy top end) and cache it to disk. Pure stdlib."""
    if path.exists():
        return

    rate = 44100
    duration = 2.6
    n_samples = int(rate * duration)
    rng = random.Random(1337)  # fixed seed: same boom every time, cache-friendly

    def lp_coeff(cutoff_hz: float) -> float:
        return 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / rate)

    a_rumble = lp_coeff(140.0)   # rumble: only the low end of the noise survives
    a_body = lp_coeff(600.0)     # short muffled "body" at the very start

    r1 = r2 = r3 = 0.0           # 3-stage low-pass for the rumble
    b1 = b2 = 0.0                # 2-stage low-pass for the body
    phase = 0.0
    samples = []

    for i in range(n_samples):
        t = i / rate
        noise = rng.uniform(-1.0, 1.0)

        # 1) Sub thump: sine sweeping 95 Hz -> ~32 Hz, the core "BOOM".
        freq = 32.0 + 63.0 * math.exp(-t * 3.5)
        phase += 2.0 * math.pi * freq / rate
        thump_env = min(1.0, t / 0.006) * math.exp(-t * 1.6)
        thump = math.sin(phase) * thump_env

        # 2) Rolling rumble: heavily low-passed noise with a slow tail.
        r1 += a_rumble * (noise - r1)
        r2 += a_rumble * (r1 - r2)
        r3 += a_rumble * (r2 - r3)
        rumble_env = min(1.0, t / 0.03) * math.exp(-t * 1.1)
        rumble = r3 * 9.0 * rumble_env

        # 3) Muffled initial impact (no hiss — capped at ~600 Hz).
        b1 += a_body * (noise - b1)
        b2 += a_body * (b1 - b2)
        body = b2 * 3.0 * math.exp(-t * 18.0)

        x = 1.0 * thump + 0.9 * rumble + 0.5 * body
        # Soft saturation: adds harmonics so the boom is audible even on
        # small speakers that can't reproduce the 30-60 Hz fundamentals.
        samples.append(math.tanh(x * 1.8))

    # Fade out the last 80 ms, then normalize to ~-1 dBFS.
    fade = int(rate * 0.08)
    for k in range(fade):
        samples[-fade + k] *= 1.0 - k / fade
    peak = max(abs(s) for s in samples) or 1.0
    gain = 0.89 / peak

    frames = bytearray()
    for s in samples:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767))

    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(bytes(frames))


class NotifyProxy(QObject):
    """Exposed to QML as `notifyProxy` — fires a desktop notification and
    plays the explosion sound effect when a phase completes."""

    # Playback commands tried in order; first one found on PATH wins.
    _PLAYERS = (
        ["paplay"],
        ["pw-play"],
        ["aplay", "-q"],
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet"],
    )

    def __init__(self):
        super().__init__()
        self._wav_path: Path | None = _explosion_wav_path()
        try:
            _ensure_explosion_wav(self._wav_path)
        except OSError:
            self._wav_path = None  # fail silently; blast animation still plays
        self._blast_script = Path(__file__).resolve().parent / "blast_main.py"

    @Slot(bool, bool)
    def notifyPhaseChange(self, is_break: bool, is_long_break: bool) -> None:
        if is_long_break:
            title = "Long break"
            body = "Three fuses burned — take a proper rest."
        elif is_break:
            title = "Break time"
            body = "Fuse reset — pomodoro's lit again."
        else:
            title = "Back to work"
            body = "Break's over, get back to it."
        try:
            subprocess.Popen(
                ["notify-send", "-a", "pomodoro-bomb", title, body],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            pass  # notify-send not installed; fail silently

    @Slot()
    def playExplosion(self) -> None:
        if not self._wav_path:
            return
        for player in self._PLAYERS:
            exe = player[0]
            if shutil.which(exe) is None:
                continue
            try:
                subprocess.Popen(
                    [*player, str(self._wav_path)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return
            except OSError:
                continue
        # No known player found on PATH; fail silently.

    @Slot()
    def spawnBlast(self) -> None:
        """Launch the fullscreen blast overlay as its own process, so it
        gets its own window class ("pomodoro-bomb-blast") distinct from
        this app's ("pomodoro-bomb") — see blast.qml for why that matters."""
        if not self._blast_script.exists():
            return
        try:
            subprocess.Popen(
                [sys.executable, str(self._blast_script)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Solo-purpose bomb-styled pomodoro timer")
    parser.add_argument("--work", type=int, default=30, help="work minutes (default 30)")
    parser.add_argument("--break", dest="brk", type=int, default=5, help="short break minutes (default 5)")
    parser.add_argument("--long-break", dest="long_brk", type=int, default=15,
                        help="long break minutes (default 15)")
    parser.add_argument("--long-every", dest="long_every", type=int, default=3,
                        help="work sessions before a long break (default 3)")
    parser.add_argument("--hat", action="store_true", help="show the festive santa hat")
    args = parser.parse_args()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("pomodoro-bomb")
    app.setDesktopFileName("pomodoro-bomb")

    engine = QQmlApplicationEngine()

    notify_proxy = NotifyProxy()
    engine.rootContext().setContextProperty("notifyProxy", notify_proxy)

    qml_path = Path(__file__).resolve().parent / "bomb.qml"
    engine.load(str(qml_path))

    if not engine.rootObjects():
        return 1

    root = engine.rootObjects()[0]
    root.setProperty("workMinutes", args.work)
    root.setProperty("breakMinutes", args.brk)
    root.setProperty("longBreakMinutes", args.long_brk)
    root.setProperty("sessionsBeforeLongBreak", max(1, args.long_every))
    root.setProperty("festiveHat", args.hat)
    root.setProperty("remainingSeconds", args.work * 60)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

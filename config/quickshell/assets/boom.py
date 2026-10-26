#!/usr/bin/env python3
"""boom.py — plays the pomodoro explosion. Synthesises the sound once (noise
crack + low rumble, stdlib only) into ~/.cache/quickshell/explosion.wav, then
plays it with the first player found on PATH."""
import math
import random
import shutil
import struct
import subprocess
import wave
from pathlib import Path

wav = Path.home() / ".cache" / "quickshell" / "explosion.wav"

if not wav.exists():
    wav.parent.mkdir(parents=True, exist_ok=True)
    rate, dur = 44100, 0.9
    rng = random.Random(1337)
    frames = bytearray()
    for i in range(int(rate * dur)):
        t = i / rate
        s = 0.75 * rng.uniform(-1, 1) * math.exp(-t * 6) + 0.5 * math.sin(2 * math.pi * 55 * t) * math.exp(-t * 3)
        frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
    with wave.open(str(wav), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(bytes(frames))

for player in (["pw-play"], ["paplay"], ["aplay", "-q"], ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet"]):
    if shutil.which(player[0]):
        subprocess.Popen([*player, str(wav)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        break

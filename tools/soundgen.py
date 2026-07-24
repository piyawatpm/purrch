#!/usr/bin/env python3
"""Generates the two sounds the cat makes, so nothing has to be downloaded.

meow.wav   -- a short two-formant chirp with a rising-then-falling pitch, closer
              to the "mrrp?" a cat greets you with than a full meow.
crunch.wav -- three soft bites for the feeding animation.
"""

import math
import os
import random
import struct
import wave

RATE = 44100


def write_wav(path, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.82)) * 32767))
                      for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def meow(seconds=0.62):
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        u = t / seconds
        f0 = 480 + 300 * math.sin(math.pi * min(1.0, u * 1.15))    # rise then fall
        phase += math.tau * f0 / RATE
        # a couple of formants give it a vocal, non-beepy timbre
        s = (math.sin(phase) + 0.5 * math.sin(2 * phase + 0.6)
             + 0.28 * math.sin(3 * phase + 1.2) + 0.12 * math.sin(5 * phase))
        vib = 1.0 + 0.05 * math.sin(math.tau * 18 * t)
        env = min(1.0, u / 0.10) * min(1.0, (1.0 - u) / 0.45)
        out.append(s * env * vib * 0.5)
    return out


def crunch(seconds=0.75):
    """Three soft bites: short noise bursts through a lowpass, not a click track."""
    n = int(RATE * seconds)
    out = []
    lp = 0.0
    rnd = random.Random(19)
    bites = [0.02, 0.28, 0.52]
    for i in range(n):
        t = i / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.30
        env = 0.0
        for b in bites:
            if b <= t < b + 0.14:
                u = (t - b) / 0.14
                env = max(env, (1 - u) ** 2 * (1.0 if u > 0.04 else u / 0.04))
        out.append(lp * env * 0.9)
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "Sources", "PetApp", "Resources", "Sounds")
    os.makedirs(out, exist_ok=True)
    write_wav(os.path.join(out, "meow.wav"), meow())
    write_wav(os.path.join(out, "crunch.wav"), crunch())
    print("wrote meow.wav, crunch.wav ->", out)


if __name__ == "__main__":
    main()

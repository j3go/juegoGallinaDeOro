#!/usr/bin/env python3
"""Synthesizes every sound effect and the battle music of Golden Chicken (pure Python, no deps).

    python3 tools/gen_audio.py            # writes assets/sounds/*.wav and assets/music/battle_theme.ogg
    python3 tools/gen_audio.py --sfx      # only the sound effects
    python3 tools/gen_audio.py --music    # only the music (needs ffmpeg for the .ogg)

Everything is generated from oscillators, noise and simple filters, so it can be tweaked and
regenerated freely (no third-party audio, no licences). Each sound is a function below.
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave
from array import array

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "sounds")
MUSIC_DIR = os.path.join(ROOT, "assets", "music")
SR = 44100
TAU = math.tau


# --- Building blocks -------------------------------------------------------------------------

def buf(seconds, sr=SR):
    return array("f", bytes(4 * int(seconds * sr)))


def mix_into(dst, src, start=0, gain=1.0):
    n = min(len(src), len(dst) - start)
    for i in range(max(0, -start), n):
        dst[start + i] += src[i] * gain


def osc(freq, seconds, shape="sine", sr=SR, phase=0.0):
    """`freq` is a number or a function of time (seconds)."""
    n = int(seconds * sr)
    out = array("f", bytes(4 * n))
    f = freq if callable(freq) else (lambda t, v=freq: v)
    ph = phase
    for i in range(n):
        t = i / sr
        ph = (ph + f(t) / sr) % 1.0
        if shape == "sine":
            v = math.sin(TAU * ph)
        elif shape == "saw":
            v = 2.0 * ph - 1.0
        elif shape == "square":
            v = 1.0 if ph < 0.5 else -1.0
        elif shape == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        else:  # soft square: round, buzzy
            v = math.tanh(4.0 * math.sin(TAU * ph))
        out[i] = v
    return out


def noise(seconds, sr=SR, rng=None):
    r = rng or random
    return array("f", (r.uniform(-1.0, 1.0) for _ in range(int(seconds * sr))))


def env(x, attack, decay_curve, sr=SR):
    """Linear attack then `decay_curve(t)` (t in seconds after the attack)."""
    a = max(1, int(attack * sr))
    for i in range(len(x)):
        x[i] *= (i / a) if i < a else decay_curve((i - a) / sr)
    return x


def exp_decay(rate):
    return lambda t: math.exp(-rate * t)


def fade_out(x, seconds, sr=SR):
    n = min(len(x), int(seconds * sr))
    for i in range(n):
        x[len(x) - n + i] *= 1.0 - i / n
    return x


def svf(x, cutoff, q=0.7, mode="low", sr=SR):
    """State-variable filter (2x oversampled so high cutoffs stay stable).
    `cutoff` is a number or a function of time."""
    c = cutoff if callable(cutoff) else (lambda t, v=cutoff: v)
    low = band = high = 0.0
    damp = 1.0 / max(q, 0.05)
    out = array("f", bytes(4 * len(x)))
    for i in range(len(x)):
        fc = min(c(i / sr), sr * 0.3)
        f = 2.0 * math.sin(math.pi * fc / (2.0 * sr))
        for _ in range(2):
            low += f * band
            high = x[i] - low - damp * band
            band += f * high
        out[i] = low if mode == "low" else band if mode == "band" else high
    return out


def drive(x, amount):
    for i in range(len(x)):
        x[i] = math.tanh(x[i] * amount)
    return x


def gain(x, g):
    for i in range(len(x)):
        x[i] *= g
    return x


def loopify(x, fade=0.08, sr=SR):
    """Crossfades the tail into the head so the sound loops without a click."""
    n = int(fade * sr)
    out = x[: len(x) - n]
    for i in range(n):
        w = i / n
        out[i] = out[i] * w + x[len(x) - n + i] * (1.0 - w)
    return out


def normalize(x, peak=0.89):
    m = max(1e-9, max(abs(v) for v in x))
    return gain(x, peak / m)


def write_wav(name, x, sr=SR, peak=0.89):
    normalize(x, peak)
    path = os.path.join(SFX_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))
    print("  ", os.path.relpath(path, ROOT), "%.2fs" % (len(x) / sr))


# --- Sound effects ---------------------------------------------------------------------------

def fart(seed, seconds, base, squeak=1.6):
    """Buzzy low tone with an irregular flutter ("prrrt") and a squeaky end."""
    rng = random.Random(seed)
    jitter = [rng.uniform(-1, 1) for _ in range(64)]
    flutter_rate = rng.uniform(18, 30)

    def pitch(t):
        k = t / seconds
        wobble = jitter[int(t * 40) % 64] * 0.12
        end = 1.0 + (squeak - 1.0) * max(0.0, (k - 0.8) / 0.2) ** 2
        return base * (1.0 - 0.25 * k) * (1.0 + wobble) * end

    tone = osc(pitch, seconds, "soft")
    buzz = osc(lambda t: pitch(t) * 2.01, seconds, "saw")
    hiss = noise(seconds, rng=rng)
    out = buf(seconds)
    ph = 0.0
    for i in range(len(out)):
        t = i / SR
        ph += (flutter_rate * (1.0 + 0.3 * jitter[int(t * 25) % 64])) / SR
        flap = 0.55 + 0.45 * abs(math.sin(math.pi * ph))
        # Sputters: random dropouts in the last third.
        if t > seconds * 0.6 and jitter[int(t * 60) % 64] > 0.55:
            flap *= 0.25
        out[i] = (tone[i] * 0.7 + buzz[i] * 0.25 + hiss[i] * 0.18) * flap
    out = svf(out, lambda t: 380 + 520 * math.exp(-3 * t), 1.4)
    env(out, 0.015, lambda t: 1.0 if t < seconds * 0.75 else max(0.0, 1.0 - (t - seconds * 0.75) / (seconds * 0.25)))
    return drive(out, 2.2)


def whoosh(seconds, f_from, f_to, q=1.2, seed=1):
    n = noise(seconds, rng=random.Random(seed))
    out = svf(n, lambda t: f_from * (f_to / f_from) ** (t / seconds), q, "band")
    return env(out, seconds * 0.35, lambda t: max(0.0, 1.0 - t / (seconds * 0.65)))


def knock(freq, seconds=0.25, partial=2.4):
    a = osc(lambda t: freq * (1.0 - 0.2 * min(t * 8, 1)), seconds)
    b = osc(freq * partial, seconds)
    out = buf(seconds)
    for i in range(len(out)):
        t = i / SR
        out[i] = a[i] * math.exp(-18 * t) + b[i] * 0.5 * math.exp(-40 * t)
    return out


def clicks(seconds, count, seed, spread=0.06):
    rng = random.Random(seed)
    out = buf(seconds)
    for k in range(count):
        start = int((k * spread / count + rng.uniform(0, 0.01)) * SR)
        burst = svf(noise(0.012, rng=rng), 3500, 0.8, "high")
        env(burst, 0.0005, exp_decay(400))
        mix_into(out, burst, start, rng.uniform(0.6, 1.0))
    return out


def thud(seconds=0.3, f0=110, f1=45):
    body = osc(lambda t: f1 + (f0 - f1) * math.exp(-20 * t), seconds)
    env(body, 0.002, exp_decay(10))
    dirt = svf(noise(seconds), 400, 0.7)
    env(dirt, 0.001, exp_decay(25))
    mix_into(body, dirt, 0, 0.5)
    return body


def egg_crack():
    out = buf(0.4)
    mix_into(out, clicks(0.4, 5, 11, 0.07), 0, 1.0)
    crunch = svf(noise(0.15), 1800, 1.5, "band")
    env(crunch, 0.002, exp_decay(30))
    mix_into(out, crunch, int(0.01 * SR), 0.6)
    mix_into(out, thud(0.2, 160, 80), 0, 0.5)
    return out


def egg_splat():
    out = buf(0.45)
    wet = svf(noise(0.4), lambda t: 1600 * math.exp(-6 * t) + 250, 2.5, "band")
    env(wet, 0.003, exp_decay(9))
    mix_into(out, wet, 0, 1.0)
    mix_into(out, clicks(0.2, 3, 5, 0.03), 0, 0.5)
    mix_into(out, thud(0.25, 140, 60), 0, 0.6)
    return out


def egg_bonk():
    out = buf(0.7)
    mix_into(out, knock(520, 0.35), 0, 1.0)
    mix_into(out, clicks(0.2, 4, 3, 0.05), int(0.01 * SR), 0.7)
    # Cartoon "boing" wobble right after the hit.
    wob = osc(lambda t: 260 * (1 + 0.35 * math.sin(TAU * 13 * t) * math.exp(-5 * t)), 0.5)
    env(wob, 0.01, exp_decay(6))
    mix_into(out, wob, int(0.05 * SR), 0.45)
    return out


def slide_whistle_down(seconds=0.55):
    s = osc(lambda t: 1500 * (380 / 1500) ** (t / seconds) * (1 + 0.02 * math.sin(TAU * 7 * t)), seconds)
    return env(s, 0.02, lambda t: max(0.0, 1.0 - t / seconds) ** 0.5)


def knockdown():
    out = buf(0.9)
    mix_into(out, egg_bonk(), 0, 1.0)
    mix_into(out, slide_whistle_down(), int(0.12 * SR), 0.5)
    mix_into(out, thud(0.3), int(0.6 * SR), 0.7)
    return out


def egg_plop():
    out = buf(0.4)
    a = osc(lambda t: 240 * math.exp(-5 * t) + 90, 0.15)
    env(a, 0.002, exp_decay(22))
    mix_into(out, a, 0, 1.0)
    mix_into(out, a, int(0.13 * SR), 0.35)  # little bounce
    mix_into(out, svf(env(noise(0.05), 0.001, exp_decay(80)), 900, 0.8), 0, 0.3)
    return out


def coin():
    out = buf(0.55)
    for k, (f, start, length) in enumerate([(988, 0.0, 0.09), (1319, 0.07, 0.45)]):
        tone = osc(f, length, "square")
        tone2 = osc(f * 2.0, length, "sine")
        mix_into(tone, tone2, 0, 0.4)
        env(tone, 0.003, exp_decay(5 if k else 25))
        mix_into(out, svf(tone, 5000, 0.7), int(start * SR), 0.6)
    sparkle = osc(lambda t: 2637 + 600 * math.sin(TAU * 30 * t), 0.4)
    env(sparkle, 0.05, exp_decay(9))
    mix_into(out, sparkle, int(0.1 * SR), 0.15)
    return out


def metal_shing(seconds=0.6):
    out = buf(seconds)
    for f, g, d in [(2730, 1.0, 7), (3910, 0.7, 9), (5140, 0.5, 11), (6820, 0.35, 14), (1840, 0.4, 6)]:
        tone = osc(lambda t, f=f: f * (1 + 0.002 * math.sin(TAU * 6 * t)), seconds)
        env(tone, 0.004, exp_decay(d))
        mix_into(out, tone, 0, g)
    return out


def kunai_throw():
    out = buf(0.6)
    mix_into(out, whoosh(0.3, 2600, 700, 1.5, 7), 0, 1.0)
    mix_into(out, metal_shing(0.55), int(0.02 * SR), 0.45)
    return out


def kunai_whir_loop():
    seconds = 0.4  # 8 whirls at 20 Hz: loops seamlessly
    n = svf(noise(seconds + 0.05, rng=random.Random(4)), 1900, 2.0, "band")
    for i in range(len(n)):
        n[i] *= 0.35 + 0.65 * abs(math.sin(math.pi * 20 * i / SR))
    return loopify(n, 0.05)


def kunai_thunk():
    out = buf(0.7)
    mix_into(out, thud(0.25, 200, 90), 0, 1.0)
    mix_into(out, knock(900, 0.12, 2.9), 0, 0.6)
    # Twang: the kunai vibrating in the wood.
    tw = osc(lambda t: 620 * (1 + 0.05 * math.sin(TAU * 22 * t)), 0.6, "tri")
    env(tw, 0.004, exp_decay(6))
    mix_into(out, tw, int(0.01 * SR), 0.35)
    return out


def kunai_hit():
    out = buf(0.5)
    slash = svf(noise(0.12), 4000, 0.8, "high")
    env(slash, 0.003, exp_decay(30))
    mix_into(out, slash, 0, 0.7)
    mix_into(out, knock(330, 0.3, 1.7), int(0.01 * SR), 1.0)
    mix_into(out, metal_shing(0.4), 0, 0.25)
    return out


def explosion(big=1.0):
    seconds = 2.2
    rng = random.Random(9)
    out = buf(seconds)
    body = svf(noise(seconds, rng=rng), lambda t: 200 + 3200 * math.exp(-4 * t), 0.8)
    env(body, 0.004, exp_decay(2.2))
    mix_into(out, body, 0, 1.0)
    sub = osc(lambda t: 30 + 60 * math.exp(-6 * t), seconds)
    env(sub, 0.002, exp_decay(2.5))
    mix_into(out, sub, 0, 1.1 * big)
    # Debris crackles falling after the blast.
    for _ in range(26):
        c = svf(noise(0.02, rng=rng), 2500, 0.8, "high")
        env(c, 0.001, exp_decay(250))
        mix_into(out, c, int(rng.uniform(0.15, 1.6) * SR), rng.uniform(0.1, 0.4))
    return drive(out, 1.8)


def formant_voice(pitch, seconds, formants, buzz=0.9, seed=0):
    """Cartoon voice: a glottal buzz shaped by a few band-pass formants."""
    src = osc(pitch, seconds, "saw")
    breath = noise(seconds, rng=random.Random(seed))
    for i in range(len(src)):
        src[i] = src[i] * buzz + breath[i] * (1.0 - buzz)
    out = buf(seconds)
    for f, q, g in formants:
        mix_into(out, svf(src, f, q, "band"), 0, g)
    return out


def bok(pitch=620, seconds=0.11, seed=0):
    v = formant_voice(lambda t: pitch * (1.0 + 0.5 * min(t / 0.03, 1.0) - 0.4 * t / seconds), seconds,
                      [(850, 5, 1.0), (2300, 6, 0.6), (3500, 8, 0.3)], 0.85, seed)
    return env(v, 0.005, lambda t: max(0.0, 1.0 - t / (seconds * 0.9)))


def bagawk(seed=0):
    out = buf(0.5)
    mix_into(out, bok(560, 0.08, seed), 0, 0.8)
    gawk = formant_voice(lambda t: 700 + 500 * math.sin(math.pi * min(t / 0.22, 1.0)), 0.28,
                         [(950, 4, 1.0), (2100, 5, 0.7), (3300, 8, 0.3)], 0.8, seed + 1)
    env(gawk, 0.01, lambda t: max(0.0, 1.0 - t / 0.27))
    mix_into(out, gawk, int(0.1 * SR), 1.0)
    return out


def clucks(pattern, seed):
    out = buf(1.2)
    pos = 0.0
    rng = random.Random(seed)
    for kind in pattern:
        snd = bok(rng.uniform(560, 700), 0.1, rng.randint(0, 99)) if kind == "b" else bagawk(rng.randint(0, 99))
        mix_into(out, snd, int(pos * SR), 1.0)
        pos += 0.15 if kind == "b" else 0.42
    return out[: int(min(pos + 0.1, 1.2) * SR)]


def rooster_crow():
    out = buf(1.5)
    syllables = [(0.0, 0.16, 620, 700), (0.2, 0.16, 680, 760), (0.4, 0.18, 760, 820), (0.62, 0.7, 900, 600)]
    for k, (start, length, f0, f1) in enumerate(syllables):
        v = formant_voice(lambda t, f0=f0, f1=f1, length=length: (f0 + (f1 - f0) * t / length) * (1 + 0.03 * math.sin(TAU * 7 * t)),
                          length, [(1000, 4, 1.0), (2400, 5, 0.6), (3600, 7, 0.3)], 0.8, k)
        env(v, 0.015, lambda t, length=length: max(0.0, 1.0 - t / length) ** 0.6)
        mix_into(out, v, int(start * SR), 1.0)
    return out


def wing_flaps(count=3, spacing=0.11):
    out = buf(count * spacing + 0.2)
    rng = random.Random(21)
    for k in range(count):
        f = svf(noise(0.09, rng=rng), 700, 0.9)
        env(f, 0.01, exp_decay(30))
        mix_into(out, f, int(k * spacing * SR), 1.0 - k * 0.15)
    return out


def flap_loop():
    seconds = 0.4  # one flap per loop, roughly the flying wingbeat
    rng = random.Random(22)
    out = buf(seconds)
    f = svf(noise(0.14, rng=rng), 650, 0.9)
    env(f, 0.02, exp_decay(18))
    mix_into(out, f, 0, 1.0)
    air = svf(noise(seconds, rng=rng), 400, 0.7)
    mix_into(out, air, 0, 0.12)
    return out


def teleport(up=True):
    seconds = 0.55
    f0, f1 = (300, 2000) if up else (2000, 350)
    s = osc(lambda t: f0 * (f1 / f0) ** (t / seconds) * (1 + 0.08 * math.sin(TAU * 14 * t)), seconds, "tri")
    env(s, 0.01, lambda t: max(0.0, 1.0 - t / seconds) ** 0.7)
    out = buf(0.8)
    mix_into(out, s, 0, 1.0)
    rng = random.Random(5 if up else 6)
    for k in range(7):
        tone = osc(rng.choice([1568, 2093, 2637, 3136]), 0.15)
        env(tone, 0.003, exp_decay(25))
        mix_into(out, tone, int(rng.uniform(0.05, 0.5) * SR), 0.25)
    if not up:
        pop = osc(lambda t: 700 * math.exp(-15 * t) + 150, 0.1)
        env(pop, 0.001, exp_decay(40))
        mix_into(out, pop, int(0.5 * SR), 1.0)
    return out


def boing():
    s = osc(lambda t: (190 + 140 * min(t / 0.25, 1.0)) * (1 + 0.3 * math.sin(TAU * 15 * t) * math.exp(-6 * t)), 0.5)
    return env(s, 0.005, exp_decay(6))


def slap():
    out = buf(0.35)
    crack = svf(noise(0.06), 2500, 0.8, "high")
    env(crack, 0.001, exp_decay(70))
    mix_into(out, crack, 0, 1.0)
    mix_into(out, thud(0.2, 180, 90), 0, 0.7)
    mix_into(out, whoosh(0.12, 600, 1800, 1.0, 3), 0, 0.3)
    return out


def grab_zip():
    out = buf(0.35)
    z = osc(lambda t: 400 * (3.0 ** (t / 0.07)) if t < 0.07 else 1200, 0.09, "saw")
    env(z, 0.003, lambda t: max(0.0, 1.0 - t / 0.08))
    mix_into(out, svf(z, 3000, 0.8), 0, 0.6)
    rustle = svf(noise(0.25), 2000, 1.0, "band")
    env(rustle, 0.02, exp_decay(12))
    mix_into(out, rustle, int(0.03 * SR), 0.6)
    mix_into(out, bok(420, 0.09, 3), int(0.04 * SR), 0.5)  # "hup!"
    return out


def throw_down():
    out = buf(0.8)
    mix_into(out, whoosh(0.35, 400, 1400, 1.2, 9), 0, 0.8)
    mix_into(out, thud(0.35, 120, 40), int(0.32 * SR), 1.0)
    mix_into(out, clicks(0.2, 3, 8, 0.05), int(0.33 * SR), 0.3)
    return out


def dizzy_birds():
    out = buf(1.1)
    rng = random.Random(31)
    t = 0.0
    while t < 0.95:
        f = rng.uniform(2600, 3400)
        chirp = osc(lambda x, f=f: f * (1 + 0.35 * x / 0.06), 0.06)
        env(chirp, 0.004, lambda x: max(0.0, 1.0 - x / 0.06))
        mix_into(out, chirp, int(t * SR), rng.uniform(0.5, 1.0))
        t += rng.uniform(0.08, 0.16)
    return out


def fanfare():
    out = buf(1.0)
    notes = [(523, 0.0, 0.1), (659, 0.1, 0.1), (784, 0.2, 0.1), (1047, 0.3, 0.6)]
    for f, start, length in notes:
        tone = buf(length)
        for det in (0.997, 1.003):
            mix_into(tone, osc(f * det, length, "saw"), 0, 0.5)
        tone = svf(tone, 2600, 0.9)
        env(tone, 0.02, lambda t, length=length: 1.0 if t < length - 0.08 else max(0.0, (length - t) / 0.08))
        mix_into(out, tone, int(start * SR), 1.0)
    return out


def fuse_loop():
    seconds = 0.6
    rng = random.Random(41)
    hiss = svf(noise(seconds + 0.05, rng=rng), 5000, 0.7, "high")
    gain(hiss, 0.4)
    for _ in range(18):
        c = env(noise(0.006, rng=rng), 0.0005, exp_decay(500))
        mix_into(hiss, c, int(rng.uniform(0, seconds) * SR), rng.uniform(0.4, 1.0))
    return loopify(hiss, 0.05)


def egg_whistle_loop():
    seconds = 1.2
    n = svf(noise(seconds + 0.1, rng=random.Random(51)), lambda t: 1100 + 350 * math.sin(TAU * t / 0.6), 1.6, "band")
    tone = osc(lambda t: 1500 + 60 * math.sin(TAU * t / 0.6), seconds + 0.1)
    mix_into(n, tone, 0, 0.12)
    return loopify(n, 0.1)


def erratic_loop():
    seconds = 1.2  # 4 "woo-woo" cycles
    s = osc(lambda t: 850 + 300 * math.sin(TAU * 3.3333 * t), seconds + 0.1, "tri")
    n = svf(noise(seconds + 0.1, rng=random.Random(61)), 1200, 1.2, "band")
    mix_into(s, n, 0, 0.5)
    return loopify(s, 0.1)


def make_sfx():
    os.makedirs(SFX_DIR, exist_ok=True)
    print("Sound effects:")
    for k, (seconds, base) in enumerate([(0.55, 95), (0.8, 80), (0.45, 120)]):
        write_wav("fart_%d" % (k + 1), fart(k + 1, seconds, base))
    write_wav("fart_big", fart(7, 1.3, 58, 2.2))
    write_wav("egg_whistle_loop", egg_whistle_loop(), peak=0.6)
    write_wav("egg_erratic_loop", erratic_loop(), peak=0.6)
    write_wav("fuse_loop", fuse_loop(), peak=0.6)
    write_wav("egg_crack", egg_crack())
    write_wav("egg_splat", egg_splat())
    write_wav("egg_bonk", egg_bonk())
    write_wav("egg_plop", egg_plop(), peak=0.6)
    write_wav("knockdown", knockdown())
    write_wav("coin", coin(), peak=0.7)
    write_wav("kunai_throw", kunai_throw())
    write_wav("kunai_whir_loop", kunai_whir_loop(), peak=0.6)
    write_wav("kunai_thunk", kunai_thunk())
    write_wav("kunai_hit", kunai_hit())
    write_wav("explosion", explosion())
    write_wav("cluck_1", clucks("bb", 1))
    write_wav("cluck_2", clucks("g", 2))
    write_wav("cluck_3", clucks("bbbg", 3))
    write_wav("rooster", rooster_crow())
    write_wav("wing_flaps", wing_flaps())
    write_wav("flap_loop", flap_loop(), peak=0.7)
    write_wav("teleport_out", teleport(True))
    write_wav("teleport_in", teleport(False))
    write_wav("boing", boing(), peak=0.7)
    write_wav("slap", slap())
    write_wav("grab_zip", grab_zip())
    write_wav("throw_down", throw_down())
    write_wav("dizzy_birds", dizzy_birds(), peak=0.6)
    write_wav("fanfare", fanfare(), peak=0.7)


# --- Music: calm comic war march ------------------------------------------------------------------
# A slow, sneaky march: oom-pah tuba, pizzicato offbeats and a cheeky clarinet (piccolo the second
# time), over soft distant brush drums, wind, far-off cannon booms and a bugle call in the distance.

MSR = 32000
BPM = 88
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 24  # 4 intro + 8 tune + 8 tune again (piccolo) + 4 turnaround

# One chord per bar (root MIDI note, kind): "M" major, "7" dominant seventh, "m" minor.
TUNE_CHORDS = [(53, "M"), (48, "7"), (53, "M"), (48, "7"), (46, "M"), (53, "M"), (48, "7"), (53, "M")]
INTRO_CHORDS = [(53, "M"), (48, "7"), (53, "M"), (48, "7")]
OUTRO_CHORDS = [(46, "M"), (53, "M"), (50, "m"), (48, "7")]
# Eight-bar tune in F: (beat offset, length in beats, MIDI note). Short notes = staccato.
TUNE = [
    (0, 0.4, 72), (1, 0.4, 69), (2, 0.4, 65), (2.5, 0.4, 67), (3, 0.9, 69),
    (4, 0.4, 70), (5, 0.4, 67), (6, 0.4, 64), (6.5, 0.4, 65), (7, 0.9, 67),
    (8, 0.4, 72), (9, 0.4, 69), (10, 0.4, 77), (10.5, 0.4, 76), (11, 0.4, 74), (11.5, 0.4, 72),
    (12, 0.7, 70), (12.75, 0.2, 69), (13, 0.4, 67), (14, 1.6, 72),
    (16, 0.4, 74), (16.5, 0.4, 74), (17, 0.4, 70), (18, 0.4, 74), (18.5, 0.4, 77), (19, 0.9, 74),
    (20, 0.4, 72), (20.5, 0.4, 72), (21, 0.4, 69), (22, 1.4, 65),
    (24, 0.4, 67), (24.5, 0.4, 69), (25, 0.4, 70), (25.5, 0.4, 71), (26, 0.9, 72), (27, 0.4, 64),
    (28, 0.9, 65), (30, 0.2, 72), (30.5, 0.4, 65),
]
# Far-away bugle call (start of the second tune, while the melody rests).
BUGLE = [(0, 0.5, 60), (0.5, 0.5, 65), (1, 0.5, 69), (1.5, 1.5, 72), (3.5, 0.5, 69), (4, 2.5, 65)]
# Tuba walking down chromatically into the loop point: "bum... bum... bum... bwaaa".
TURNAROUND = [(0, 0.9, 43), (1, 0.9, 42), (2, 0.9, 41), (3, 1.0, 40)]


def note_hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def chord_notes(root, kind):
    third = 3 if kind == "m" else 4
    notes = [root, root + third, root + 7]
    if kind == "7":
        notes.append(root + 10)
    return notes


def m_osc(freq, seconds, shape):
    return osc(freq, seconds, shape, MSR)


def tail_env(seconds, release):
    return lambda t: 1.0 if t < seconds - release else max(0.0, (seconds - t) / release)


def tuba(midi, seconds, level):
    """Round, slightly comic brass bass: scoops up into the note, soft square, low-passed."""
    f = note_hz(midi)
    out = m_osc(lambda t: f * (1.0 - 0.06 * math.exp(-40 * t)), seconds, "soft")
    out = svf(out, lambda t: 260 + 500 * math.exp(-8 * t), 0.9, "low", MSR)
    env(out, 0.025, lambda t: math.exp(-1.6 * t) * tail_env(seconds, 0.06)(t), MSR)
    return gain(out, level)


def pizz(midi, level):
    seconds = 0.35
    out = buf(seconds, MSR)
    for det in (0.997, 1.003):
        mix_into(out, m_osc(note_hz(midi) * det, seconds, "saw"), 0, 0.5)
    out = svf(out, lambda t: 300 + 2500 * math.exp(-30 * t), 0.8, "low", MSR)
    env(out, 0.002, exp_decay(14), MSR)
    return gain(out, level)


def reed(midi, seconds, level, bright=1.0, prev=None):
    """Clarinet-ish woody square with delayed vibrato; slides up from the previous note."""
    f = note_hz(midi)
    f0 = note_hz(prev) if prev is not None else f

    def pitch(t):
        glide = f0 + (f - f0) * min(t / 0.035, 1.0)
        return glide * (1.0 + 0.007 * min(t / 0.25, 1.0) * math.sin(TAU * 5.2 * t))

    out = m_osc(pitch, seconds, "square")
    out = svf(out, 1300 * bright, 0.7, "low", MSR)
    env(out, 0.015, tail_env(seconds, 0.05), MSR)
    return gain(out, level)


def whistle(midi, seconds, level, prev=None):
    """Piccolo / whistle: pure tone with breath and a quick slide."""
    f = note_hz(midi)
    f0 = note_hz(prev) if prev is not None else f
    tone = m_osc(lambda t: (f0 + (f - f0) * min(t / 0.03, 1.0)) * (1.0 + 0.01 * math.sin(TAU * 6 * t)), seconds, "sine")
    breath = svf(noise(seconds, MSR), f, 2.0, "band", MSR)
    mix_into(tone, breath, 0, 0.12)
    env(tone, 0.012, tail_env(seconds, 0.04), MSR)
    return gain(tone, level)


def bugle(midi, seconds, level):
    out = buf(seconds, MSR)
    for det in (0.998, 1.002):
        mix_into(out, m_osc(note_hz(midi) * det, seconds, "saw"), 0, 0.5)
    out = svf(out, 1100, 0.8, "low", MSR)
    env(out, 0.04, tail_env(seconds, 0.15), MSR)
    return gain(out, level)


def soft_kick():
    seconds = 0.5
    s = m_osc(lambda t: 48 + 50 * math.exp(-25 * t), seconds, "sine")
    env(s, 0.004, exp_decay(7), MSR)
    return s


def brush(level=1.0, seconds=0.12):
    n = svf(noise(seconds, MSR), 3500, 0.6, "band", MSR)
    env(n, 0.003, exp_decay(30), MSR)
    return gain(n, level)


def cannon(seed):
    """Distant artillery: muffled thump plus a long low rumble."""
    seconds = 3.0
    rng = random.Random(seed)
    boom = m_osc(lambda t: 35 + 40 * math.exp(-6 * t), seconds, "sine")
    env(boom, 0.01, exp_decay(3.5), MSR)
    rumble = svf(noise(seconds, MSR, rng), 140, 0.7, "low", MSR)
    env(rumble, 0.03, exp_decay(1.4), MSR)
    mix_into(boom, rumble, 0, 1.6)
    return boom


def wind(seconds, seed):
    rng = random.Random(seed)
    w = svf(noise(seconds, MSR, rng), lambda t: 380 + 220 * math.sin(TAU * t / 9.0) + 120 * math.sin(TAU * t / 3.7), 1.4, "band", MSR)
    return w


def reverb(x, wet=0.22, size=1.0):
    """Small Schroeder reverb: four combs in parallel, two allpasses in series."""
    out = array("f", bytes(4 * len(x)))
    for delay_ms, fb in [(29.7, 0.8), (37.1, 0.78), (41.1, 0.76), (43.7, 0.74)]:
        d = int(delay_ms * size * MSR / 1000)
        line = array("f", bytes(4 * d))
        p = 0
        for i in range(len(x)):
            y = line[p]
            line[p] = x[i] + y * fb
            p = (p + 1) % d
            out[i] += y * 0.25
    for delay_ms in (5.0, 1.7):
        d = int(delay_ms * MSR / 1000)
        line = array("f", bytes(4 * d))
        p = 0
        g = 0.7
        for i in range(len(out)):
            y = line[p]
            v = out[i] + y * g
            line[p] = v
            out[i] = y - v * g
            p = (p + 1) % d
    for i in range(len(x)):
        out[i] = x[i] + out[i] * wet
    return out


def make_music():
    total = BARS * BAR
    length = total + 4
    bass = buf(length, MSR)
    offbeat = buf(length, MSR)
    melody = buf(length, MSR)
    drums = buf(length, MSR)
    far = buf(length, MSR)  # distant stuff: gets heavy filtering and reverb
    at = lambda seconds: int(seconds * MSR)

    chords = INTRO_CHORDS + TUNE_CHORDS + TUNE_CHORDS + OUTRO_CHORDS
    kick, tap, ghost = soft_kick(), brush(0.8), brush(0.3, 0.08)
    for bar, (root, kind) in enumerate(chords):
        start = bar * BAR
        notes = chord_notes(root, kind)
        last = bar == BARS - 1
        # Oom-pah: tuba root on 1, fifth on 3 (the last bar walks down chromatically instead).
        if last:
            for offset, beats, midi in TURNAROUND:
                mix_into(bass, tuba(midi, beats * BEAT, 0.9), at(start + offset * BEAT))
        else:
            mix_into(bass, tuba(root - 12, BEAT * 0.8, 0.9), at(start))
            mix_into(bass, tuba(root - 5 if root - 5 >= 40 else root + 7 - 12, BEAT * 0.8, 0.75), at(start + 2 * BEAT))
        # Pah: pizzicato chord on 2 and 4 (from bar 3 of the intro on).
        if bar >= 2 and not last:
            for beat in (1, 3):
                for k, midi in enumerate(notes[1:]):
                    mix_into(offbeat, pizz(midi + 12, 0.35), at(start + beat * BEAT + k * 0.006))
        # Soft march drums: kick on 1 and 3, brush taps on 2 and 4, a ruffle every other bar.
        if bar >= 1:
            for beat in (0, 2):
                mix_into(drums, kick, at(start + beat * BEAT), 0.35)
            for beat in (1, 3):
                mix_into(drums, tap, at(start + beat * BEAT), 0.5)
            if bar % 2 == 1:
                for k in range(3):
                    mix_into(drums, ghost, at(start + 3 * BEAT - (3 - k) * BEAT / 6), 0.5)

    # The tune twice: clarinet first, then piccolo an octave up (after the far bugle call).
    first, second = 4 * BAR, 12 * BAR
    prev = None
    for offset, beats, midi in TUNE:
        mix_into(melody, reed(midi, beats * BEAT, 0.55, 1.0, prev), at(first + offset * BEAT))
        prev = midi
    prev = None
    for offset, beats, midi in TUNE:
        if offset < 8:
            continue  # the bugle plays here
        mix_into(melody, whistle(midi + 12, beats * BEAT, 0.42, prev), at(second + offset * BEAT))
        mix_into(melody, reed(midi - 12, beats * BEAT, 0.22, 0.7), at(second + offset * BEAT))  # bassoon-ish double
        prev = midi + 12
    for offset, beats, midi in BUGLE:
        mix_into(far, bugle(midi, beats * BEAT, 0.6), at(second + offset * BEAT))
    # Turnaround: the clarinet's lazy "wah-wah" over the walking tuba.
    for offset, beats, midi in [(0, 1.5, 70), (2, 1.5, 69), (8, 0.9, 67), (9, 0.9, 66), (10, 0.9, 65), (11, 1.0, 64)]:
        mix_into(melody, reed(midi, beats * BEAT, 0.4, 0.8), at(20 * BAR + offset * BEAT))

    # War ambience: wind all along and distant cannon booms now and then.
    mix_into(far, wind(length, 7), 0, 0.5)
    for k, bar_pos in enumerate([1.3, 7.6, 14.2, 19.5, 22.8]):
        mix_into(far, cannon(k), at(bar_pos * BAR), 0.55)

    far = reverb(svf(far, 900, 0.7, "low", MSR), 0.6, 1.6)
    mix = buf(length, MSR)
    for layer, level in [(bass, 0.4), (offbeat, 0.55), (melody, 0.65), (drums, 0.4), (far, 0.5)]:
        mix_into(mix, layer, 0, level)
    mix = svf(mix, 55, 0.7, "high", MSR)  # thin out the sub-bass so it stays relaxed
    mix = reverb(mix, 0.3)
    # Fold the tail past the loop point back onto the start so the loop is seamless.
    n = at(total)
    for i in range(len(mix) - n):
        mix[i] += mix[n + i]
    mix = mix[:n]
    normalize(mix, 0.7)

    os.makedirs(MUSIC_DIR, exist_ok=True)
    out = os.path.join(MUSIC_DIR, "battle_theme.ogg")
    with tempfile.TemporaryDirectory() as tmp:
        tmp_wav = os.path.join(tmp, "battle_theme.wav")
        with wave.open(tmp_wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(MSR)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in mix))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp_wav, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    print("Music:\n  ", os.path.relpath(out, ROOT), "%.1fs loop" % total)


if __name__ == "__main__":
    random.seed(2024)
    only = set(sys.argv[1:])
    if not only or "--sfx" in only:
        make_sfx()
    if not only or "--music" in only:
        make_music()

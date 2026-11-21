#!/usr/bin/env python3
"""Генератор музыки и звуков «Шароломки» — всё синтезируется кодом, внешних ассетов нет.

    pip install numpy soundfile
    python3 tools/gen_audio.py          # пишет audio/*.ogg

Музыка: спокойный бесшовный луп ~46 с (84 BPM, ля минор: Am–F–C–G), пэд + щипковое арпеджио
(Карплус — Стронг) + бас + мягкие ударные + колокольчики во второй половине + свёрточная реверберация.
Звуки: короткие, громкость выровнена; высоту тона игра слегка варьирует сама.
"""
import os
import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def note(n):
    """MIDI → Гц."""
    return 440.0 * 2 ** ((n - 69) / 12.0)


def env(n, a, d, s, r, length):
    """ADSR-огибающая длиной length сэмплов (a, d, r — в секундах, s — уровень)."""
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    e = np.zeros(length)
    sustain = max(0, length - a - d - r)
    seg = [np.linspace(0, 1, a, endpoint=False), np.linspace(1, s, d, endpoint=False),
           np.full(sustain, s), np.linspace(s, 0, r)]
    x = np.concatenate(seg)[:length]
    e[: len(x)] = x
    return e


def pluck(freq, dur):
    """Щипковая струна Карплуса — Стронга."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    decay = 0.996
    for i in range(n):
        out[i] = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = decay * 0.5 * (buf[i % period] + nxt)
    return out * np.exp(-np.linspace(0, 3.0, n))


def lowpass(x, cutoff):
    """Однополюсный фильтр нижних частот."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def reverb(x, seconds=2.2, wet=0.28):
    """Свёрточная реверберация с затухающим шумом (через FFT)."""
    n = int(seconds * SR)
    ir = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 7, n))
    ir = lowpass(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x) + n]
    out = np.zeros(len(x) + n)
    out[: len(x)] = x * (1 - wet)
    return out + y * wet


def tri(phase):
    return 2 * np.abs(2 * (phase - np.floor(phase + 0.5))) - 1


def save(name, x, stereo=None, quality=0.45):
    peak = np.max(np.abs(x if stereo is None else stereo)) or 1.0
    data = (x if stereo is None else stereo) / peak * 0.89
    sf.write(os.path.join(OUT, name + ".ogg"), data, SR, format="OGG", subtype="VORBIS")


# ------------------------------------------------------------------ музыка

def music():
    bpm = 84
    beat = 60.0 / bpm
    bars = 16
    total = int(bars * 4 * beat * SR)
    tail = int(2.5 * SR)
    L = np.zeros(total + tail)
    R = np.zeros(total + tail)
    # аккорды по 2 такта: Am, F, C, G (×2)
    chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]] * 2
    t_bar = 4 * beat
    for ci, ch in enumerate(chords):
        start = int(ci * 2 * t_bar * SR)
        length = int(2 * t_bar * SR)
        t = np.arange(length) / SR
        e = env(length, 1.2, 0.5, 0.8, 1.4, length)
        # пэд: две расстроенные треугольные волны на ноту
        pad = np.zeros(length)
        for n in ch:
            f = note(n)
            pad += tri(t * f * 0.998) + tri(t * f * 1.003) * 0.8
        pad = lowpass(pad * e, 1400) * 0.10
        L[start:start + length] += pad * 1.05
        R[start:start + length] += pad * 0.95
        # бас: синус на тонике, четверти
        root = note(ch[0] - 12)
        for b in range(8):
            s = start + int(b * beat * SR)
            n = int(beat * 0.9 * SR)
            tb = np.arange(n) / SR
            bass = np.sin(2 * np.pi * root * tb) * env(n, 0.01, 0.1, 0.6, 0.25, n) * 0.22
            L[s:s + n] += bass
            R[s:s + n] += bass
        # арпеджио: восьмые вверх-вниз по аккорду + октава
        arp = ch + [ch[0] + 12, ch[1] + 12] + ch[::-1]
        for k in range(16):
            s = start + int(k * beat / 2 * SR)
            n = int(beat * 1.6 * SR)
            p = pluck(note(arp[k % len(arp)] + 12), n / SR) * 0.16
            pan = 0.5 + 0.35 * np.sin(k * 0.9)
            L[s:s + n] += p * (1 - pan)
            R[s:s + n] += p * pan
    # ударные: мягкая бочка на 1 и 3, тихий хай-хэт на слабые доли
    for b in range(bars * 4):
        s = int(b * beat * SR)
        if b % 2 == 0:
            n = int(0.25 * SR)
            tk = np.arange(n) / SR
            f = 110 * np.exp(-tk * 18) + 45
            kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tk * 14) * 0.28
            L[s:s + n] += kick
            R[s:s + n] += kick
        s2 = s + int(beat / 2 * SR)
        n = int(0.05 * SR)
        hat = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 8, n)) * 0.025
        hat = hat - lowpass(hat, 6000)
        L[s2:s2 + n] += hat * 0.8
        R[s2:s2 + n] += hat * 1.2
    # колокольчики во второй половине: простая мелодия
    melody = [76, None, 74, 72, None, 71, 72, None, 69, None, 71, 72, 74, None, 72, None]
    for i, m in enumerate(melody):
        if m is None:
            continue
        s = int((8 * t_bar + i * t_bar / 2) * SR)
        n = int(1.4 * SR)
        tm = np.arange(n) / SR
        f = note(m)
        bell = (np.sin(2 * np.pi * f * tm) + 0.4 * np.sin(2 * np.pi * f * 2.76 * tm)) * np.exp(-tm * 3.2) * 0.09
        L[s:s + n] += bell * 0.8
        R[s:s + n] += bell * 1.0
    L = reverb(L)
    R = reverb(R)
    # бесшовный луп: хвост прибавляем к началу
    out_l = L[:total].copy()
    out_r = R[:total].copy()
    rest = len(L) - total
    out_l[:rest] += L[total:]
    out_r[:rest] += R[total:]
    save("music_calm", None, stereo=np.stack([out_l, out_r], axis=1))


# ------------------------------------------------------------------ звуки

def tone(freqs, dur, decay, amp=1.0, harmonics=(1.0,)):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for k, h in enumerate(harmonics):
            out += np.sin(2 * np.pi * f * (k + 1) * t) * h
    return out * np.exp(-t * decay) * amp


def seq(parts, gap):
    total = int((gap * (len(parts) - 1)) * SR) + max(len(p) for p in parts)
    out = np.zeros(total)
    for i, p in enumerate(parts):
        s = int(i * gap * SR)
        out[s:s + len(p)] += p
    return out


def sfx():
    # удар по квадрату — короткий мягкий «тик»
    hit = tone([1250], 0.06, 70, harmonics=(1.0, 0.3)) + rng.normal(0, 1, int(0.06 * SR)) * np.exp(-np.linspace(0, 12, int(0.06 * SR))) * 0.15
    save("hit", hit)
    # разрушение — «поп»: падающий тон + шумовой всплеск
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    f = 700 * np.exp(-t * 14) + 160
    pop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 22)
    noise = rng.normal(0, 1, n) * np.exp(-t * 40) * 0.5
    save("break", pop + lowpass(noise, 3000))
    # выстрел — восходящий свип + щипок
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f = 260 + 900 * (t / t[-1]) ** 1.5
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.005, 0.05, 0.5, 0.1, n)
    pl = np.zeros(n)
    p = pluck(note(76), 0.18)
    pl[: len(p)] = p
    save("launch", sweep * 0.7 + pl * 0.6)
    # начало прицела — короткий щелчок
    save("aim", tone([2100], 0.03, 160, harmonics=(1.0, 0.5)))
    # U-балл — двойной колокольчик
    bell = (1.0, 0.0, 0.35)
    save("u", seq([tone([note(88)], 0.5, 6, harmonics=bell), tone([note(95)], 0.6, 5, harmonics=bell)], 0.09))
    # золото — фанфара-арпеджио
    save("gold", seq([tone([note(m)], 0.45, 7, harmonics=(1.0, 0.4, 0.2)) for m in (72, 76, 79, 84)], 0.07))
    # покупка — монетка
    save("buy", seq([tone([1046], 0.08, 30, harmonics=(1.0, 0.5, 0.25)), tone([1568], 0.18, 18, harmonics=(1.0, 0.5, 0.25))], 0.06))
    # цель карты — джингл
    jingle = seq([tone([note(m)], 0.5, 5, harmonics=(1.0, 0.3)) for m in (67, 72, 76, 79)], 0.12)
    chord = tone([note(72), note(76), note(79), note(84)], 1.4, 2.2, harmonics=(1.0, 0.25)) * 0.5
    goal = np.zeros(len(jingle) + len(chord))
    goal[: len(jingle)] += jingle
    goal[int(0.48 * SR): int(0.48 * SR) + len(chord)] += chord
    save("goal", reverb(goal, 1.2, 0.2))
    # нажатие кнопки
    save("tap", tone([1600], 0.02, 220))
    # финал — восходящая гамма
    save("finale", reverb(seq([tone([note(m)], 0.35, 8, harmonics=(1.0, 0.3)) for m in (60, 64, 67, 71, 72, 76, 79, 84)], 0.06), 1.0, 0.2))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music()
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")

#!/usr/bin/env python3
"""摸鱼炸弹人的原创 CC0 芯片乐循环和短句。

只用方波、三角波和噪声。循环是整数小节，接缝处做很短的等功率交叉淡化，
让前后采样挨在一起，而不是硬切一刀。
大厅、对局、缩圈都是大调、明亮、轻快的街机底，不走小调压迫感。
在仓库根目录运行：python3 tools/gen_audio.py
"""

from __future__ import annotations

import math
import os
import struct
import subprocess
import wave

SR = 22050
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "audio")


def midi_hz(n: int) -> float:
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


class Lfsr:
    def __init__(self, seed: int) -> None:
        self.s = seed & 0x7FFF or 1

    def next(self) -> float:
        bit = ((self.s >> 0) ^ (self.s >> 1)) & 1
        self.s = (self.s >> 1) | (bit << 14)
        return 1.0 if bit else -1.0


def _env(local: float, dur: float, kind: str) -> float:
    if kind == "noise":
        return math.exp(-local * 32.0)
    attack = 0.01 if kind != "tri" else 0.014
    release = 0.028 if kind == "tri" else 0.02
    release = min(release, dur * 0.4)
    if local < attack:
        return local / attack
    if local > dur - release:
        return max(0.0, (dur - local) / release)
    return 1.0


def _voice(phase: float, kind: str, duty: float) -> float:
    p = phase % 1.0
    tri = 4.0 * abs(p - 0.5) - 1.0
    pulse = 1.0 if p < duty else -1.0
    if kind == "tri":
        return tri
    if kind == "lead":
        # 大厅音色圆一点：方波里混进三角波。
        return 0.62 * (1.0 if p < 0.5 else -1.0) + 0.38 * tri
    return pulse


def render_events(events: list, seconds: float, seed: int, lp: float, loop: bool) -> list:
    n = int(round(seconds * SR))
    buf = [0.0] * n
    lfsr = Lfsr(seed)
    phases = [0.0] * len(events)
    prepared = []
    for ev in events:
        start, dur, midi, kind, amp, duty = ev
        s0 = int(start * SR)
        s1 = min(n, int((start + dur) * SR))
        freq = 0.0 if kind == "noise" or midi < 0 else midi_hz(int(midi))
        if freq > 700.0:
            amp *= 0.78
        if freq > 900.0:
            amp *= 0.7
        prepared.append((s0, s1, freq, kind, amp, duty))
    for i in range(n):
        sample = 0.0
        t = i / SR
        for ni, (s0, s1, freq, kind, amp, duty) in enumerate(prepared):
            if i < s0 or i >= s1:
                continue
            local = t - (s0 / SR)
            dur = (s1 - s0) / SR
            env = _env(local, max(dur, 1e-4), kind)
            if kind == "noise":
                v = lfsr.next()
            else:
                phases[ni] += freq / SR
                v = _voice(phases[ni], kind, duty)
            sample += v * amp * env
        buf[i] = sample
    buf = _lowpass(buf, lp)
    buf = _highpass(buf, 0.996)
    if loop:
        buf = _loop_crossfade(buf, int(0.018 * SR))
    else:
        buf = _edge_fade(buf, int(0.004 * SR), int(0.02 * SR))
    return _normalize(buf, 0.82 if loop else 0.78)


def _lowpass(x: list, a: float) -> list:
    y = [0.0] * len(x)
    acc = 0.0
    for i, s in enumerate(x):
        acc += a * (s - acc)
        y[i] = acc
    return y


def _highpass(x: list, r: float) -> list:
    y = [0.0] * len(x)
    prev_y = 0.0
    prev_x = 0.0
    for i, s in enumerate(x):
        prev_y = s - prev_x + r * prev_y
        prev_x = s
        y[i] = prev_y
    return y


def _loop_crossfade(x: list, fade: int) -> list:
    """Blend the tail over the head, then drop the tail.

    Playback jumps from the new last sample (original n-fade-1) to the new
    first sample (original n-fade). Those are neighbors, so the seam is a
    normal step instead of a click.
    """
    n = len(x)
    fade = max(2, min(fade, n // 8))
    out = x[: n - fade]
    for i in range(fade):
        a = i / float(fade)
        w_in = math.sin(0.5 * math.pi * a)
        w_tail = math.cos(0.5 * math.pi * a)
        out[i] = x[i] * w_in + x[n - fade + i] * w_tail
    return out


def _edge_fade(x: list, attack: int, release: int) -> list:
    n = len(x)
    out = x[:]
    attack = min(attack, n // 4)
    release = min(release, n // 3)
    for i in range(attack):
        out[i] *= i / float(attack)
    for i in range(release):
        out[n - 1 - i] *= i / float(release)
    if n:
        out[0] = 0.0
        out[-1] = 0.0
    return out


def _normalize(x: list, peak_target: float) -> list:
    peak = max(abs(s) for s in x) or 1e-6
    g = peak_target / peak
    return [max(-1.0, min(1.0, s * g)) for s in x]


def quarter(bpm: float) -> float:
    return 60.0 / bpm


def add_melody_at(events: list, notes: list, bpm: float, kind: str, amp: float, duty: float) -> None:
    step = quarter(bpm) / 2.0
    for i, midi in enumerate(notes):
        if midi < 0:
            continue
        events.append((i * step, step * 0.92, midi, kind, amp, duty))


def add_bouncy_bass(events: list, roots: list, bpm: float, amp: float) -> None:
    """根音和纯五度交替，大调，不往低音砸。"""
    q = quarter(bpm)
    step = q / 2.0
    for b, root in enumerate(roots):
        pattern = [root, root + 7, root, root + 7, root, root + 7, root + 12, root + 7]
        for i, midi in enumerate(pattern):
            events.append((b * q * 4.0 + i * step, step * 0.86, midi, "tri", amp, 0.5))


def add_sunny_pads(events: list, roots: list, bpm: float, amp: float) -> None:
    q = quarter(bpm)
    bar = q * 4.0
    for i, root in enumerate(roots):
        events.append((i * bar, bar * 0.92, root + 12, "tri", amp, 0.5))
        events.append((i * bar, bar * 0.92, root + 12 + 4, "tri", amp * 0.55, 0.5))
        events.append((i * bar, bar * 0.92, root + 12 + 7, "tri", amp * 0.42, 0.5))


def add_chip_hats(events: list, bars: int, bpm: float, quiet: float, accent: float) -> None:
    step = quarter(bpm) / 2.0
    for i in range(bars * 8):
        amp = accent if i % 4 == 2 else quiet
        events.append((i * step, 0.04, 0, "noise", amp, 0.5))


def loop_seconds(bars: int, bpm: float) -> float:
    return bars * 4.0 * quarter(bpm)


def lobby_events() -> list:
    # C 大调，8 小节，116 BPM。上行多，落在主音。
    melody = [
        72, 76, 79, 76, 74, 76, 72, 67,
        72, 74, 76, 79, 76, 74, 72, 76,
        79, 76, 74, 72, 74, 76, 79, 81,
        79, 76, 74, 72, 67, 72, 76, 72,
        72, 76, 79, 81, 79, 76, 74, 72,
        74, 76, 79, 76, 74, 72, 71, 72,
        76, 79, 76, 74, 72, 74, 76, 79,
        76, 74, 72, 71, 72, 76, 79, 72,
    ]
    # C G F C | F C G C，全是大三和弦的根音。
    roots = [48, 55, 53, 48, 53, 48, 55, 48]
    events: list = []
    add_melody_at(events, melody, 116.0, "lead", 0.2, 0.5)
    add_sunny_pads(events, roots, 116.0, 0.11)
    add_bouncy_bass(events, roots, 116.0, 0.16)
    add_chip_hats(events, 8, 116.0, 0.02, 0.045)
    return events


def match_melody() -> list:
    # G 大调。连续八分音符，少休止，听着在往前跳。
    return [
        67, 71, 74, 79, 76, 74, 71, 67,
        74, 76, 79, 78, 79, 74, 71, 74,
        72, 76, 79, 76, 74, 72, 71, 67,
        71, 74, 76, 79, 76, 74, 71, 67,
        79, 78, 76, 74, 76, 79, 81, 79,
        74, 76, 79, 76, 74, 71, 67, 71,
        72, 74, 76, 79, 76, 74, 72, 71,
        67, 71, 74, 76, 79, 76, 74, 67,
    ]


def match_events() -> list:
    # G D C G | C G D G。128 BPM，比大厅跳，但仍是大调。
    roots = [55, 50, 48, 55, 48, 55, 50, 55]
    events: list = []
    add_melody_at(events, match_melody(), 128.0, "lead", 0.18, 0.5)
    add_sunny_pads(events, roots, 128.0, 0.09)
    add_bouncy_bass(events, roots, 128.0, 0.15)
    add_chip_hats(events, 8, 128.0, 0.022, 0.05)
    return events


def sudden_events() -> list:
    # 和对局同一套大调和弦，再快一点，高音用大三度叠上去，不用不协和告警。
    roots = [55, 50, 48, 55, 48, 55, 50, 55]
    melody = match_melody()
    events: list = []
    add_melody_at(events, melody, 138.0, "lead", 0.17, 0.5)
    sparkle = [n + 4 if n >= 0 else -1 for n in melody]
    add_melody_at(events, sparkle, 138.0, "lead", 0.06, 0.5)
    add_sunny_pads(events, roots, 138.0, 0.08)
    add_bouncy_bass(events, roots, 138.0, 0.14)
    add_chip_hats(events, 8, 138.0, 0.028, 0.06)
    return events


def win_events() -> list:
    # C 大调上行，短、亮。
    events = []
    notes = [72, 76, 79, 84]
    for i, midi in enumerate(notes):
        dur = 0.7 if i == len(notes) - 1 else 0.16
        events.append((i * 0.15, dur, midi, "lead", 0.22, 0.5))
        events.append((i * 0.15, dur, midi - 12, "tri", 0.1, 0.5))
    events.append((0.0, 1.15, 60, "tri", 0.12, 0.5))
    events.append((0.0, 1.15, 64, "tri", 0.08, 0.5))
    events.append((0.0, 1.15, 67, "tri", 0.06, 0.5))
    return events


def lose_events() -> list:
    # 还是往下走，但停在大调音级上，轻、短，不沉。
    events = []
    notes = [76, 74, 72, 67]
    t = 0.0
    for i, midi in enumerate(notes):
        dur = 0.42 if i == len(notes) - 1 else 0.2
        events.append((t, dur, midi, "lead", 0.18, 0.5))
        events.append((t, dur, midi - 12, "tri", 0.08, 0.5))
        t += 0.18
    events.append((0.0, 0.95, 60, "tri", 0.1, 0.5))
    events.append((0.0, 0.95, 64, "tri", 0.06, 0.5))
    return events


def sweep(dur: float, f0: float, f1: float, amp: float, duty: float, noise: float, seed: int) -> list:
    n = int(dur * SR)
    lfsr = Lfsr(seed)
    phase = 0.0
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        k = t / dur
        env = math.exp(-3.2 * k) * (1.0 - k)
        env = max(0.0, env)
        freq = f0 * ((f1 / f0) ** k)
        phase += freq / SR
        pulse = 1.0 if (phase % 1.0) < duty else -1.0
        tri = 4.0 * abs((phase % 1.0) - 0.5) - 1.0
        nz = lfsr.next() if noise else 0.0
        out[i] = amp * env * ((1.0 - noise) * (0.75 * pulse + 0.25 * tri) + noise * nz)
    return _edge_fade(_normalize(_lowpass(out, 0.4), 0.8), int(0.003 * SR), int(0.012 * SR))


def boom() -> list:
    dur = 0.34
    n = int(dur * SR)
    lfsr = Lfsr(0xB00B)
    phase = 0.0
    sine = 0.0
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        # 底频抬高一点，爆炸仍是一声脆响，而不是闷雷。
        freq = 220.0 * math.exp(-t * 12.0) + 78.0
        phase += freq / SR
        pulse = 1.0 if (phase % 1.0) < 0.5 else -1.0
        sine += (90.0 * math.exp(-t * 8.0) + 36.0) / SR
        thump = math.sin(2.0 * math.pi * sine)
        nz = lfsr.next()
        env_tone = math.exp(-t * 10.0)
        env_noise = math.exp(-t * 16.0)
        click = math.exp(-t * 90.0)
        out[i] = 0.42 * env_tone * pulse + 0.48 * env_tone * thump + 0.55 * env_noise * nz + 0.32 * click * nz
    return _edge_fade(_normalize(_lowpass(out, 0.58), 0.9), int(0.001 * SR), int(0.018 * SR))


def tone_blip(notes: list, step: float, dur: float, amp: float, duty: float) -> list:
    total = step * (len(notes) - 1) + dur + 0.02
    n = int(total * SR)
    out = [0.0] * n
    for idx, midi in enumerate(notes):
        s0 = int(idx * step * SR)
        length = int(dur * SR)
        phase = 0.0
        freq = midi_hz(midi)
        for i in range(length):
            j = s0 + i
            if j >= n:
                break
            local = i / SR
            env = _env(local, dur, "lead")
            phase += freq / SR
            out[j] += amp * env * _voice(phase, "lead", duty)
    out = _lowpass(out, 0.42)
    return _edge_fade(_normalize(out, 0.75), int(0.003 * SR), int(0.012 * SR))


def place_bomb() -> list:
    a = tone_blip([62, 50], 0.045, 0.07, 0.7, 0.25)
    return a


def kick() -> list:
    body = sweep(0.08, 420.0, 140.0, 0.85, 0.5, 0.12, 0x51C4)
    return body


def death() -> list:
    # 下行，但停在比较亮的音区。
    return tone_blip([81, 76, 72, 67], 0.06, 0.09, 0.65, 0.5)


def pickup() -> list:
    return tone_blip([76, 81], 0.055, 0.08, 0.65, 0.5)


def ui_click() -> list:
    return tone_blip([91], 0.0, 0.035, 0.45, 0.5)


def enter_room() -> list:
    return tone_blip([76, 79, 83], 0.07, 0.09, 0.55, 0.5)


def ready() -> list:
    return tone_blip([79, 84], 0.06, 0.08, 0.5, 0.5)


def write_wav(path: str, samples: list) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-32767, min(32767, round(s * 32767.0))))
            frames += struct.pack("<h", v)
        handle.writeframes(frames)


def to_ogg(wav_path: str, ogg_path: str, quality: int) -> None:
    subprocess.check_call(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            wav_path,
            "-c:a",
            "libvorbis",
            "-q:a",
            str(quality),
            "-ar",
            str(SR),
            "-ac",
            "1",
            ogg_path,
        ]
    )
    os.remove(wav_path)


def stats(name: str, samples: list) -> None:
    peak = max(abs(s) for s in samples)
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    seam = abs(samples[0] - samples[-1])
    adj = max(abs(samples[i] - samples[i - 1]) for i in range(1, len(samples)))
    print(
        f"{name:16} {len(samples) / SR:6.2f}秒  峰值 {peak:.2f}  均方根 {rms:.3f}  "
        f"接缝 {seam:.4f}  最大步进 {adj:.4f}"
    )


def emit(rel: str, samples: list, quality: int) -> None:
    dest = os.path.join(OUT, rel)
    wav = dest + ".tmp.wav"
    stats(rel, samples)
    write_wav(wav, samples)
    to_ogg(wav, dest, quality)


def main() -> None:
    beds = [
        ("bgm/lobby.ogg", render_events(lobby_events(), loop_seconds(8, 116.0), 11, 0.46, True), 4),
        ("bgm/match.ogg", render_events(match_events(), loop_seconds(8, 128.0), 22, 0.5, True), 4),
        ("bgm/sudden_death.ogg", render_events(sudden_events(), loop_seconds(8, 138.0), 33, 0.52, True), 4),
        ("bgm/win.ogg", render_events(win_events(), 1.2, 44, 0.48, False), 4),
        ("bgm/lose.ogg", render_events(lose_events(), 1.05, 55, 0.46, False), 4),
        ("sfx/place_bomb.ogg", place_bomb(), 2),
        ("sfx/boom.ogg", boom(), 3),
        ("sfx/kick.ogg", kick(), 2),
        ("sfx/death.ogg", death(), 2),
        ("sfx/pickup.ogg", pickup(), 2),
        ("sfx/ui_click.ogg", ui_click(), 1),
        ("sfx/enter_room.ogg", enter_room(), 2),
        ("sfx/ready.ogg", ready(), 2),
    ]
    for rel, samples, quality in beds:
        emit(rel, samples, quality)


if __name__ == "__main__":
    main()

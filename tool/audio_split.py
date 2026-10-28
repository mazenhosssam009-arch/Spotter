"""Cuts one recording of N lines (with a pause between lines) into N clips.
Used by make_egyptian_voice_gemini.py; pure Python, no extra packages.

How: the loudness is measured every 10 ms; the N-1 LONGEST quiet stretches are taken as
the gaps between lines (short quiet bits inside a line are always shorter than the pause
the voice was asked to leave), and every clip is trimmed with a little silence kept around it.
"""

import array

FRAME_MS = 10
MIN_GAP_MS = 120  # quieter than this long can be a gap between lines
PAD_MS = 60  # silence kept before / after every clip


def _frames(pcm, rate):
    a = array.array("h")
    a.frombytes(pcm[: len(pcm) // 2 * 2])
    n = rate * FRAME_MS // 1000
    return a, n, [max((abs(x) for x in a[i:i + n]), default=0) for i in range(0, len(a), n)]


def split(pcm, rate, count):
    """list of [count] PCM byte strings, or None when the recording has too few pauses"""
    a, n, peak = _frames(pcm, rate)
    if not peak:
        return None
    loud = sorted(peak)[int(len(peak) * 0.95)]
    quiet = max(250, loud * 0.06)  # below 6% of the loud level = silence
    silent = [p < quiet for p in peak]

    # quiet stretches inside the speech (not the silence before the first / after the last word)
    first = silent.index(False) if False in silent else 0
    last = len(silent) - 1 - silent[::-1].index(False) if False in silent else len(silent) - 1
    gaps, start = [], None
    for i in range(first, last + 1):
        if silent[i] and start is None:
            start = i
        elif not silent[i] and start is not None:
            if (i - start) * FRAME_MS >= MIN_GAP_MS:
                gaps.append((start, i))
            start = None
    if len(gaps) < count - 1:
        return None
    cuts = sorted(sorted(gaps, key=lambda g: g[1] - g[0], reverse=True)[: count - 1])

    pad = PAD_MS // FRAME_MS
    bounds, s = [], first
    for g0, g1 in cuts:
        bounds.append((s, g0))
        s = g1
    bounds.append((s, last + 1))
    out = []
    for b0, b1 in bounds:
        b0, b1 = max(0, b0 - pad), min(len(peak), b1 + pad)
        out.append(a[b0 * n: b1 * n].tobytes())
    return out


def seconds(pcm, rate):
    return len(pcm) / 2 / rate

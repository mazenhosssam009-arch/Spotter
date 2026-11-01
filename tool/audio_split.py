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


def drop_end_noise(pcm, rate):
    """Gemini sometimes ends its audio with ~150 ms of full-scale noise (a loud hiss after the
    line): cut it off and fade the new end so the cut does not click"""
    a, n, peak = _frames(pcm, rate)
    j = len(peak)
    while j > 0 and len(peak) - j < 2 and peak[j - 1] < 30000:  # a quieter last frame or two
        j -= 1
    k = j
    while k > 0 and peak[k - 1] >= 30000:
        k -= 1
    if j - k < 3:
        return pcm
    out = a[:k * n]
    fade = min(rate // 50, len(out))
    for i in range(fade):
        out[len(out) - 1 - i] = int(out[len(out) - 1 - i] * i / fade)
    return out.tobytes()


def trim_strays(pcm, rate):
    """[pcm] without the short sounds that [strays] finds at its start / end (60 ms of the pause
    before / after the speech is kept, the new end fades out so the cut does not click)"""
    head, tail = strays(pcm, rate)
    if not head and not tail:
        return pcm
    a, n, peak = _frames(pcm, rate)
    quiet = max(250, max(peak) * 0.06)
    keep = 60 // FRAME_MS
    start, end = 0, len(peak)
    if head:  # skip the click, then the pause after it
        i = 0
        while peak[i] < quiet:
            i += 1
        while peak[i] >= quiet:
            i += 1
        while peak[i] < quiet:
            i += 1
        start = max(0, i - keep)
    if tail:  # the same from the end
        j = len(peak) - 1
        while peak[j] < quiet:
            j -= 1
        while peak[j] >= quiet:
            j -= 1
        while peak[j] < quiet:
            j -= 1
        end = min(len(peak), j + 1 + keep)
    out = a[start * n:end * n]
    fade = min(rate // 50, len(out))
    for i in range(fade):
        out[len(out) - 1 - i] = int(out[len(out) - 1 - i] * i / fade)
    return out.tobytes()


def strays(pcm, rate, max_ms=160, gap_ms=200):
    """(start_ms, end_ms) of a short sound cut off from the speech by a silence at the very start /
    end of a clip: a sliver of the neighbouring line when a cut was put in the wrong pause.
    0 = none. Real short words (about 300 ms) are not counted."""
    a, n, peak = _frames(pcm, rate)
    if not peak:
        return 0, 0
    loud = max(peak) or 1
    quiet = max(250, loud * 0.06)
    runs, i = [], 0
    while i < len(peak):
        if peak[i] >= quiet:
            j = i
            while j < len(peak) and peak[j] >= quiet:
                j += 1
            runs.append([i, j])
            i = j
        else:
            i += 1
    merged = []
    for r in runs:  # sounds less than 150 ms apart belong together
        if merged and (r[0] - merged[-1][1]) * FRAME_MS < 150:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    head = tail = 0
    if len(merged) >= 2:
        f, s = merged[0], merged[1]
        if (f[1] - f[0]) * FRAME_MS <= max_ms and (s[0] - f[1]) * FRAME_MS >= gap_ms:
            head = (f[1] - f[0]) * FRAME_MS
        l, p = merged[-1], merged[-2]
        if (l[1] - l[0]) * FRAME_MS <= max_ms and (l[0] - p[1]) * FRAME_MS >= gap_ms:
            tail = (l[1] - l[0]) * FRAME_MS
    return head, tail

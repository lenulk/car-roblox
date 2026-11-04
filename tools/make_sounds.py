"""Generate simple synthetic placeholder sound effects for Garage Tycoon.

Usage:  python tools/make_sounds.py
Output: assets/sounds_draft/*.wav  (16-bit mono, 44.1 kHz)

The files are procedural (sines + noise), so there is no copyright issue. Upload them in
Roblox Creator Hub (Audio), then paste the resulting ids into src/shared/Config/Sounds.luau.
"""

import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds_draft"
rng = np.random.default_rng(7)


def t(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def env_exp(n: int, decay: float) -> np.ndarray:
    """Fast attack (2 ms), exponential decay (decay = seconds to -60 dB)."""
    x = np.arange(n) / RATE
    e = np.exp(-6.9 * x / decay)
    attack = min(n, int(0.002 * RATE))
    e[:attack] *= np.linspace(0, 1, attack)
    return e


def filt(x: np.ndarray, low: float | None = None, high: float | None = None) -> np.ndarray:
    """Brick-wall FFT band filter: keeps frequencies between `low` and `high` Hz."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    if low is not None:
        spec[freqs < low] = 0
    if high is not None:
        spec[freqs > high] = 0
    return np.fft.irfft(spec, len(x))


def tone(freq: float, seconds: float, decay: float) -> np.ndarray:
    tt = t(seconds)
    return np.sin(2 * np.pi * freq * tt) * env_exp(len(tt), decay)


def place(buf: np.ndarray, sound: np.ndarray, at: float) -> None:
    start = int(at * RATE)
    end = min(len(buf), start + len(sound))
    buf[start:end] += sound[: end - start]


def fade_ends(x: np.ndarray, ms: float = 5) -> np.ndarray:
    n = int(ms / 1000 * RATE)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def normalize(x: np.ndarray, peak: float = 0.85) -> np.ndarray:
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def save(name: str, x: np.ndarray, loop: bool = False) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Loops are already seamless; fading their ends would add a dip at every repeat.
    data = (np.clip(normalize(x if loop else fade_ends(x)), -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print(f"{name}.wav  {len(data) / RATE:.2f}s")


def hammer_strike() -> np.ndarray:
    # Metallic clank: inharmonic partials with fast decay + a short noise transient.
    n = int(0.35 * RATE)
    out = np.zeros(n)
    for freq, amp, decay in [(740, 1.0, 0.16), (1190, 0.7, 0.12), (1930, 0.5, 0.09), (3120, 0.3, 0.06)]:
        out += amp * tone(freq, 0.35, decay)
    click = filt(rng.standard_normal(int(0.03 * RATE)), low=1500) * env_exp(int(0.03 * RATE), 0.012)
    place(out, click * 1.4, 0)
    return out


def wrench() -> np.ndarray:
    # Ratchet: a short run of clicks.
    out = np.zeros(int(0.5 * RATE))
    for i, at in enumerate([0.0, 0.07, 0.14, 0.23, 0.31]):
        n = int(0.05 * RATE)
        click = filt(rng.standard_normal(n), low=1200, high=6000) * env_exp(n, 0.02)
        ping = tone(1700 + 80 * (i % 2), 0.05, 0.03)
        place(out, click + 0.6 * ping, at)
    return out


def spray() -> np.ndarray:
    # Looping hiss. The tail is cross-faded into the head so the loop has no click.
    seconds, fade = 1.6, 0.2
    n = int(seconds * RATE)
    f = int(fade * RATE)
    raw = filt(rng.standard_normal(n + f), low=2500, high=11000)
    raw *= 0.8 + 0.2 * np.sin(2 * np.pi * 9 * np.arange(n + f) / RATE)  # slight flutter
    body = raw[:n].copy()
    ramp = np.linspace(0, 1, f)
    body[:f] = body[:f] * ramp + raw[n : n + f] * (1 - ramp)
    return body


def greet() -> np.ndarray:
    # Soft two-note chime.
    out = np.zeros(int(0.7 * RATE))
    place(out, tone(660, 0.5, 0.28) + 0.3 * tone(1320, 0.5, 0.18), 0.0)
    place(out, tone(880, 0.5, 0.3) + 0.3 * tone(1760, 0.5, 0.2), 0.14)
    return out


def crate_drop() -> np.ndarray:
    # Dull wooden thud: falling sine + low-passed noise.
    n = int(0.4 * RATE)
    tt = t(0.4)
    freq = 55 + 110 * np.exp(-tt * 18)
    thump = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * env_exp(n, 0.2)
    knock = filt(rng.standard_normal(n), high=900) * env_exp(n, 0.07)
    return thump + 0.8 * knock


def shopper_buy() -> np.ndarray:
    # Two quick bright pings (register-like).
    out = np.zeros(int(0.5 * RATE))
    place(out, tone(1568, 0.3, 0.2) + 0.4 * tone(3136, 0.3, 0.1), 0.0)
    place(out, tone(2093, 0.4, 0.28) + 0.4 * tone(4186, 0.4, 0.12), 0.09)
    return out


def repair_done() -> np.ndarray:
    # Rising arpeggio C-E-G-C.
    out = np.zeros(int(1.0 * RATE))
    for i, freq in enumerate([523.25, 659.25, 783.99, 1046.5]):
        place(out, tone(freq, 0.6, 0.35) + 0.25 * tone(freq * 2, 0.6, 0.2), 0.11 * i)
    return out


def purchase() -> np.ndarray:
    # "Cha-ching": noisy ring then two high pings.
    out = np.zeros(int(0.8 * RATE))
    n = int(0.08 * RATE)
    place(out, filt(rng.standard_normal(n), low=3000) * env_exp(n, 0.05) * 0.8, 0.0)
    place(out, tone(1976, 0.5, 0.3) + 0.4 * tone(3951, 0.5, 0.15), 0.07)
    place(out, tone(2637, 0.6, 0.4) + 0.4 * tone(5274, 0.6, 0.18), 0.17)
    return out


def place_wrap(buf: np.ndarray, sound: np.ndarray, at: float) -> None:
    """Like place(), but anything past the end wraps to the start (for seamless loops)."""
    idx = (int(at * RATE) + np.arange(len(sound))) % len(buf)
    np.add.at(buf, idx, sound)


def circ_swell(n: int, count: int, depth: float) -> np.ndarray:
    """Slow random amplitude swells that are exactly periodic over n samples."""
    x = np.arange(n) / n
    s = np.zeros(n)
    for k in range(1, count + 1):
        s += rng.uniform(0.5, 1) / k * np.sin(2 * np.pi * (k + rng.integers(0, 3)) * x + rng.uniform(0, 6.28))
    s /= np.max(np.abs(s))
    return 1 + depth * s


def loop_start(x: np.ndarray) -> np.ndarray:
    """Rotate a circular signal so it starts where the step from the last sample is smallest."""
    step = np.abs(x - np.roll(x, 1)) / np.max(np.abs(x))
    quiet = np.abs(x) < 0.1 * np.max(np.abs(x))
    step[~quiet] = np.inf
    return np.roll(x, -int(np.argmin(step)))


def crowd_loop() -> np.ndarray:
    # Stadium murmur, built circularly (FFT filters + wrapped placement) so the seam is click-free.
    n = int(6.0 * RATE)
    bed = filt(rng.standard_normal(n), low=200, high=3000) * circ_swell(n, 6, 0.35)
    bed /= np.max(np.abs(bed))
    out = 0.6 * bed
    for _ in range(90):
        ln = int(rng.uniform(0.12, 0.45) * RATE)
        centre = rng.uniform(300, 1200)
        f0 = rng.uniform(100, 260)
        tt = np.arange(ln) / RATE
        buzz = sum(np.sin(2 * np.pi * f0 * (1 + 0.1 * np.sin(2 * np.pi * 5 * tt)) * h * tt) / h for h in range(1, 12))
        voice = filt(buzz + 0.8 * rng.standard_normal(ln), low=centre * 0.7, high=centre * 1.4)
        voice *= np.hanning(ln) * rng.uniform(0.04, 0.12) / (np.max(np.abs(voice)) + 1e-9)
        place_wrap(out, voice, rng.uniform(0, 6.0))
    return loop_start(out)


def crowd_cheer() -> np.ndarray:
    # Roar: fast swell (0.3 s) then decay, with extra 1-4 kHz energy and a few "whoo" glides.
    n = int(2.5 * RATE)
    tt = t(2.5)
    env = np.minimum(tt / 0.3, 1) ** 1.5 * np.exp(-np.maximum(tt - 0.3, 0) / 0.9)
    roar = filt(rng.standard_normal(n), low=200, high=4500)
    bright = filt(rng.standard_normal(n), low=1000, high=4000)
    out = (roar + 0.9 * bright) * env * circ_swell(n, 5, 0.2)
    out /= np.max(np.abs(out))
    for _ in range(7):
        at = rng.uniform(0.05, 1.0)
        ln = int(rng.uniform(0.5, 0.9) * RATE)
        x = np.arange(ln) / RATE
        start = rng.uniform(350, 600)
        freq = start * (1 + 0.8 * (1 - np.exp(-x * 6))) * (1 + 0.02 * np.sin(2 * np.pi * 6 * x))
        ph = 2 * np.pi * np.cumsum(freq) / RATE
        whoo = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.15 * filt(rng.standard_normal(ln), low=800, high=3000)) * np.abs(np.sin(np.pi * x / x[-1])) ** 1.5
        place(out, whoo * rng.uniform(0.12, 0.25), at)
    return out


def crowd_gasp() -> np.ndarray:
    # Collective "ohh": breathy noise whose band-pass centre falls 900 -> 400 Hz.
    seconds = 1.6
    n = int(seconds * RATE)
    out = np.zeros(n)
    hop, win = int(0.02 * RATE), int(0.08 * RATE)
    for start in range(0, n - win, hop):
        centre = 900 - 500 * min(start / RATE / 1.2, 1)
        seg = filt(rng.standard_normal(win), low=centre * 0.7, high=centre * 1.35) * np.hanning(win)
        out[start : start + win] += seg
    tt = t(seconds)
    env = np.minimum(tt / 0.05, 1) * np.exp(-np.maximum(tt - 0.05, 0) * 6.9 / 1.2)
    return out * env


def square_beep(freq: float, seconds: float) -> np.ndarray:
    """Sine plus low-level odd harmonics, flat sustain, fast decay at the end."""
    tt = t(seconds)
    x = sum(np.sin(2 * np.pi * freq * h * tt) / h * 0.6 for h in (3, 5, 7)) + np.sin(2 * np.pi * freq * tt)
    env = np.ones(len(tt))
    a, d = int(0.004 * RATE), int(0.06 * RATE)
    env[:a] = np.linspace(0, 1, a)
    env[-d:] = np.linspace(1, 0, d) ** 2
    return x * env


def countdown_beep() -> np.ndarray:
    # Race start-light beep, 880 Hz.
    return square_beep(880, 0.35)


def countdown_go() -> np.ndarray:
    # "Go" beep, one octave higher and longer.
    return square_beep(1760, 0.8)


def engine_core(n: int, period: int) -> np.ndarray:
    """Harmonic-rich firing pulse train with per-cycle gain jitter plus rasp noise.

    Everything is periodic in `period` samples (or circular over n when n is a multiple of it),
    so with n = whole cycles the result loops without a seam.
    """
    i = np.arange(n)
    ph = 2 * np.pi * i / period
    pulses = sum(np.sin(h * ph + 0.6 * np.sin(h * 1.7)) / h**1.4 for h in range(1, 26))
    cycles = int(np.ceil(n / period)) + 1
    gains = 1 + 0.12 * rng.standard_normal(cycles)
    gains[-1] = gains[0]
    jitter = np.interp(i / period, np.arange(cycles), gains)
    rasp = filt(rng.standard_normal(n), low=300, high=3000) * (0.5 + 0.5 * np.cos(ph))
    out = pulses * jitter + 0.18 * rasp * np.max(np.abs(pulses)) / np.max(np.abs(rasp))
    return out * (1 + 0.06 * np.sin(2 * np.pi * 3 * i / n))


def race_engine() -> np.ndarray:
    # Steady ~110 Hz engine; length is a whole number of cycles (401 samples each) so it loops.
    period = 401
    return loop_start(engine_core(220 * period, period))


def engine_sputter() -> np.ndarray:
    # Misfiring engine: irregular dropouts plus a few low pops.
    n = int(1.2 * RATE)
    out = engine_core(n, 450)
    gate = np.ones(n)
    for at, ln in [(0.15, 0.09), (0.38, 0.14), (0.62, 0.07), (0.8, 0.18)]:
        a, b = int(at * RATE), int((at + ln) * RATE)
        gate[a:b] = rng.uniform(0.0, 0.1)
    gate = np.convolve(gate, np.ones(200) / 200, mode="same")
    out *= gate * (0.6 + 0.4 * circ_swell(n, 3, 0.5))
    for at in [0.2, 0.55, 0.9]:
        ln = int(0.07 * RATE)
        pop = filt(rng.standard_normal(ln), high=500) * env_exp(ln, 0.04)
        place(out, pop * rng.uniform(1.5, 2.5) * np.max(np.abs(out)), at)
    return out


def engine_blow() -> np.ndarray:
    # Explosion: sharp crack, deep boom, metallic debris clicks.
    n = int(2.5 * RATE)
    out = np.zeros(n)
    crack = rng.standard_normal(int(0.25 * RATE))
    place(out, crack * env_exp(len(crack), 0.08), 0.0)
    ln = int(2.2 * RATE)
    boom = filt(rng.standard_normal(ln), high=150) * env_exp(ln, 1.8)
    boom = boom / np.max(np.abs(boom)) * 2.5
    thump = np.sin(2 * np.pi * np.cumsum(40 + 50 * np.exp(-t(2.2) * 5)) / RATE) * env_exp(ln, 1.4)
    place(out, boom + 1.5 * thump, 0.01)
    for _ in range(9):
        c = int(rng.uniform(0.01, 0.04) * RATE)
        click = filt(rng.standard_normal(c), low=2500, high=9000) * env_exp(c, 0.012)
        place(out, click * rng.uniform(0.3, 0.8), rng.uniform(0.05, 0.6))
    return out


if __name__ == "__main__":
    save("hammerStrike", hammer_strike())
    save("wrench", wrench())
    save("spray", spray(), loop=True)
    save("greet", greet())
    save("crateDrop", crate_drop())
    save("shopperBuy", shopper_buy())
    save("repairDone", repair_done())
    save("purchase", purchase())
    save("crowdLoop", crowd_loop(), loop=True)
    save("crowdCheer", crowd_cheer())
    save("crowdGasp", crowd_gasp())
    save("countdownBeep", countdown_beep())
    save("countdownGo", countdown_go())
    save("raceEngine", race_engine(), loop=True)
    save("engineSputter", engine_sputter())
    save("engineBlow", engine_blow())

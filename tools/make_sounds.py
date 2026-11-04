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


if __name__ == "__main__":
    save("hammerStrike", hammer_strike())
    save("wrench", wrench())
    save("spray", spray(), loop=True)
    save("greet", greet())
    save("crateDrop", crate_drop())
    save("shopperBuy", shopper_buy())
    save("repairDone", repair_done())
    save("purchase", purchase())

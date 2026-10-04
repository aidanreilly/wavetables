# wavetables: design

Date: 2026-10-04

## Summary

A 16-voice wavetable drone synth for norns, derived from
[sines](https://github.com/aidanreilly/sines). The sine/FM engine is replaced
by three `VOsc` wavetable oscillators per voice scanning the Synthesis
Technology E350 ROM banks, with per-voice LFOs driving the morph position and a
per-voice variable-slope lowpass ladder. The bitcrush and amplitude envelope
sections of sines are retained. crow support is removed.

The script is `wavetables.lua`, the engine is `Engine_Wavetables` in
`lib/wavetables_engine.sc`.

## Goal

Smooth morphing wavetables with the morph modulation reachable from the front
panel rather than the params menu. A held chord should keep evolving without
anyone touching a control, which is what the per-VCO LFO drift is for.

The UI follows sines closely: 16 level sliders on screen and on the grid, E2
to pick a voice and E3 to set its level, K2 to flip into a param editor, 16n
faders mapped to the 16 volumes.

### Success criteria

1. All 16 voices audible, morphing, at under 50% reported norns CPU with
   `vco drift` at maximum.
2. Morph position sweeps and LFO motion are free of clicks and zipper noise,
   including across the top of a bank where position wraps.
3. Every on-screen control is reachable in one page with no paging gesture.
4. The three E350 banks ship in the repo and are credited.

### Non-goals

- crow output. All crow code from sines is deleted, not disabled.
- FM. `fm_index` and the carrier/modulator pair are deleted.
- Preset compatibility with sines. Nearly every param id changes.
- Per-voice `vco drift`. It is a global character control.

## Wavetable data

Source files are the WaveEdit banks `ROM A.wav`, `ROM B.wav`, `ROM C.wav`,
each 16384 frames, mono, 16-bit, 44.1 kHz, which is exactly 64 waves of 256
samples. They are the ROM banks of the Synthesis Technology E350 Morphing
Terrarium (https://synthtech.com/eurorack/E350/), exported via WaveEdit.

They ship in the repo as `lib/waves/rom_a.wav`, `rom_b.wav`, `rom_c.wav`,
renamed only to drop the spaces. Attribution goes in `lib/waves/README.md`
and in the top-level README.

### Buffer layout

`VOsc` requires its buffers to be consecutively numbered, identically sized,
and in wavetable format. One `Buffer.allocConsecutive` block holds all three
banks:

- 195 buffers of 512 floats, about 390 KB.
- 65 buffers per bank, not 64. Slot 65 holds a copy of wave 1.
- Bank offsets 0, 65, 130.
- `bufpos = bank_offset + (pos % 64)` where `pos` is 0 to 64 exclusive.

`lfo_depth` can drive `pos` negative. SC's `%` is a true modulo rather than C's
remainder, so it returns a non-negative result for a positive modulus and the
wrap works in both directions without a guard.

The 65th buffer exists because `bufpos` interpolates `buf[n]` against
`buf[n+1]`. Without it the top of each bank is a dead end at wave 63, and a
cycling LFO either stalls there or bleeds into the next bank's unrelated
waves. With it, `pos % 64` wraps seamlessly and wave 64 crossfades back into
wave 1.

### Loading

Loading happens language-side with `SoundFile`, which avoids async
server-buffer-read sequencing entirely:

```
SoundFile.openRead(path)
  -> readData(FloatArray.newClear(16384))
  -> slice into 64 chunks of 256
  -> Signal.newFrom(chunk).asWavetable      // 512 floats
  -> buffers[n].loadCollection(wavetable)
```

The engine locates the WAV files relative to its own source file with
`PathName(this.class.filenameSymbol.asString).pathOnly`, so no norns paths are
hardcoded. `server.sync` runs after each bank.

## Engine architecture

One `\wtvoice` SynthDef instantiated 16 times onto a shared stereo bus, into a
`Limiter` output stage. This is the same topology as sines.

### Voice signal chain

```
for k in 1..3:
  voice_phase = (i-1)/16 * lfo_spread
  vco_phase   = (k-1)/3  * vco_drift
  vco_rate    = lfo_rate * (1 + (k-2) * 0.03 * vco_drift)
  pos_k       = base_pos + lfo_depth * LFO(vco_rate, voice_phase + vco_phase)
  freq_k      = f * 2 ** ((k-2) * detune / 1200)
  osc_k       = VOsc.ar(bank_off + (pos_k % 64), freq_k, (k-1)*2pi/3, 1/3)

sum = osc_1 + osc_2 + osc_3
  -> Decimator(sample_rate, bit_depth)
  -> variable-slope ladder LPF(cutoff, res, slope)
  -> * EnvGen(Env.circle(...), levelBias: env_bias)
  -> * Lag.ar(K2A.ar(vol), amp_slew)
  -> Pan2(Lag.ar(K2A.ar(pan), pan_lag))
  -> bus -> Limiter -> out
```

Three separate `VOsc` instances, not one `VOsc3`. `VOsc3` takes a single
`bufpos` for all three oscillators and exposes no `phase` argument, so
per-VCO morph modulation is unreachable through it. Three `VOsc` cost about
the same (the three interpolated table reads happen either way) and give each
VCO its own morph position, its own LFO, and its own waveform phase.

The fixed phase offsets of 0, 2pi/3 and 4pi/3 stop the three VCOs summing
coherently at `detune` 0, so the detune knob does not shift perceived level.
The `1/3` on `mul` keeps the summed voice at single-oscillator amplitude.

### Oscillator placement note

Bitcrush sits before the filter. The ladder then smooths the quantization
noise and the slope control doubles as a grit control, which is the more
usable order for sustained tones.

### LFO

One phase source per VCO, shaped arithmetically, because SC's LFO UGens
disagree on phase units (`SinOsc` radians, `LFTri` 0 to 4, `LFSaw` 0 to 2,
`LFPulse` no iphase). Driving them directly would break the `lfo_spread` and
`vco_drift` phase fans whenever the shape changed.

```
ramp = LFSaw.kr(rate, iphase).range(0, 1)      // the only phase definition
sine = sin(ramp * 2pi)
tri  = (ramp * 4 - 2).fold(-1, 1)
up   = ramp * 2 - 1
down = 1 - ramp * 2
sqr  = (ramp < 0.5) * 2 - 1
rand = LFNoise1.kr(rate)                        // free-running, no phase
out  = Select.kr(shape, [sine, tri, up, down, sqr, rand])
```

All six run at control rate and `Select` picks one. Across the engine that is
288 kr oscillators, about 4.5 audio-rate oscillators' worth.

`vco_drift` does two things from one knob. It fans the three LFO phases a
third of a cycle apart, and it detunes their rates by up to 3%. The rate
detuning matters more for drones: unequal rates mean the three morph positions
diverge and reconverge without repeating. At 0 the three VCOs morph in
lockstep and the voice behaves like a single oscillator.

### Variable-slope ladder LPF

Four cascaded `OnePole` stages per voice with the four taps crossfaded by a
continuous `slope` control, giving 6, 12, 18 and 24 dB/oct and everything
between.

```
coef = exp(-2pi * cutoff * SampleDur.ir)        // kr, one exp per block
fb   = LocalIn.ar(1)                            // last block's tap 4
t1 = OnePole.ar(in - softclip(fb * res * 4), coef)
t2 = OnePole.ar(t1, coef)
t3 = OnePole.ar(t2, coef)
t4 = OnePole.ar(t3, coef)
LocalOut.ar(t4)
out = SelectX.ar(slope_idx, [t1, t2, t3, t4])   // slope_idx 0..3 continuous
```

`SelectX` is at audio rate because the taps are audio-rate signals;
`slope_idx` is its control-rate index. The Lua param is in dB/oct and the
engine maps it as `slope_idx = slope_db / 6 - 1`, so 6 dB/oct selects tap 1
and 24 dB/oct selects tap 4.

`OnePole` takes a coefficient rather than Hz, so the conversion is explicit
and runs at control rate: 16 `exp` calls per 64-sample block rather than 1024.

Resonance uses a `LocalIn`/`LocalOut` feedback path, which is a one-block
delay. Resonance tuning therefore drifts slightly at high cutoff. That is the
normal tradeoff for a ladder built in a UGen graph and it is accepted here.
`softclip` is used rather than `tanh` because it is piecewise and cheap.

### Voice gating

sines runs all 16 voices unconditionally even at zero level. This design calls
`.run(false)` on a voice held at zero level for 0.5 s, and `.run(true)`
immediately on the way back up. The hold stops the gate chattering when a
fader or grid column is swept through zero. The release side is not delayed,
so there is no attack latency. Typical use is 4 to 8 voices audible, so this
roughly halves real-world CPU. It is the largest single lever in the budget.

### Engine commands

Per-voice, signature `"if"` (voice index, value): `vol`, `hz`, `pan`, `bank`,
`wave`, `lfo_rate`, `lfo_depth`, `lfo_shape`, `cutoff`, `res`, `slope`,
`detune`, `amp_atk`, `amp_rel`, `env_bias`, `env_delay`, `env_delay_rand`,
`amp_slew`, `hz_lag`, `pan_lag`.

Per-voice, signature `"ii"`: `sample_rate`, `bit_depth`. Retained from sines.

Global, signature `"f"`, applied to all 16 voices: `lfo_spread`, `vco_drift`.

## CPU and memory budget

norns is a Pi 3 class part, 4x Cortex-A53 at 1.2 GHz. scsynth's audio graph is
single-threaded, so the engine gets one core. At 48 kHz that is 25,000 cycles
per sample frame, of which roughly half is safely usable once softcut, matron
and the OS are accounted for. Call the ceiling 12,500 cycles.

| Component | Count | Est. cycles/frame |
|---|---|---|
| `VOsc` | 48 | 1,440 to 2,880 |
| `OnePole` stages | 64 | 384 |
| Slope crossfade (`SelectX`) | 16 | 160 |
| Resonance feedback + `softclip` | 16 | 192 |
| `Decimator` | 16 | 160 |
| `EnvGen` | 16 | 160 |
| `Pan2` + bus writes | 16 | 192 |
| `Limiter` | 1 | 60 |
| kr LFOs + filter coefficients | 64 | 25 |
| **Total** | | **2,800 to 4,200** |

That is 22% to 34% of the safe ceiling. The empirical anchor is that sines
already runs 32 oscillators plus the same per-voice tail on this hardware
without trouble; this design is roughly 2 to 2.5x that load.

### The risk is cache, not arithmetic

390 KB of wavetable data against 512 KB of L2 shared across four cores and
32 KB of L1 data cache per core. With 16 voices x 3 VCOs at 48 different morph
positions, each reading two adjacent tables, the hot working set reaches 96
tables, around 190 KB. That is L2-resident but thrashes L1, so oscillators pay
L2 latency on table reads. This is what pushes `VOsc` toward the 60-cycle end
of the estimate.

Note that `vco drift` is both the control that spreads the VCOs apart and the
control that widens the cache footprint. At drift 0 the three VCOs share two
tables and the footprint drops threefold.

### Budget protections in the design

1. Control-rate `bufpos`. The morph updates once per 64-sample block, a 750 Hz
   update rate at 1/64 the cost of audio rate.
2. Control-rate filter coefficients, as above.
3. Voice gating, as above.

### Fallbacks if measurement says it is tight

In order of preference: gate silent voices (already planned), reduce the
`vco drift` range so VCOs share tables, add a global 2-VCO mode (32
oscillators), halve the wavetables to 128 samples (195 KB, comfortably
L2-resident, at the cost of high harmonics).

### Verification tasks, before any UI work

These come first because a failure in either changes the voice architecture.

1. **scsynth buffer count.** The design needs 195 free buffers. Confirm
   norns' scsynth `-b` setting and what softcut already claims.
2. **`VOsc` with a kr `bufpos`.** Confirm `VOsc` ramps a control-rate `bufpos`
   across the block rather than stepping it. If it steps, a `Lag.ar` is
   required and the oscillator cost rises.
3. **CPU reading** from the norns menu with all 16 voices at full level and
   `vco drift` at maximum.

## UI

### Screen

`max_slider_size` drops from 32 to 16. Level sliders run from y=62 up to y=46.
Six text rows fit at y = 5, 12, 19, 26, 33, 40. Column geometry is unchanged
from sines: label at x=0, value at x=24, second label at x=62, second value at
x=89.

```
note: C3     dtun: 0          row 0
bank: A      wave: 23.4       row 1
lfor: 0.08   lfod: 0.45       row 2
cutf: 820    slop: 12dB       row 3
res:  0.2    detu: 7c         row 4
smpl: hifi   env:  drone      row 5
   ||||.|||..||||.|           16 levels, 16px
```

When the `z_tuning` mod is active, row 0 shows the tuning name and root
frequency in place of note and cents, as sines does, and E2/E3 on that row do
nothing.

`set_active()` generalises from sines' hardcoded 5-element `current_state`
table to a loop over six rows, dimming unselected rows to level 2 and lighting
the selected row to 15.

### Controls

| Control | Slider mode | Ctrl mode (K2) |
|---|---|---|
| E1 | unused | select row 0-5 |
| E2 | select voice | edit left column |
| E3 | voice level | edit right column |
| K2 | to ctrl mode | to slider mode |
| K3 | play mode: fader / env follower | same |

Grid: 16 columns of levels, unchanged. 16n: mapped to the 16 volumes through
the existing `lib/16n.lua` and the virtual fader params, unchanged.

### Params menu

Demoted from the screen: env delay, env delay rand, pan, attack, decay, bias,
bit depth, sample rate, lfo shape, and the globals `lfo spread` and
`vco drift`. The `smpl` preset row reaches the 13-entry bitcrush table on
screen, so per-voice bit depth and sample rate are the fine adjustment behind
it, as in sines.

### Param ranges

Global: `lfo_spread` 0 to 1, `vco_drift` 0 to 1, plus sines' `scale_mode`,
`root_note`, `amp_slew`, `global_pan`, the 16n config group, the faders config
group, and the env delay group.

Per voice, new: `bank` option A/B/C, `wave` 0 to 64 continuous,
`lfo_rate` 0.001 to 20 Hz exponential, `lfo_depth` 0 to 32 wave positions,
`lfo_shape` option of the six shapes, `cutoff` 20 to 20000 Hz exponential,
`res` 0 to 1, `slope` continuous 6 to 24 dB/oct, `detune` 0 to 50 cents.

Per voice, retained from sines: `vol`, `note`, `cents`, `pan`, `env`,
`attack`, `decay`, `env_bias`, `env_delay`, `env_delay_rand`,
`sample_bitrate`, `bit_depth`, `smpl_rate`.

### Deleted from sines

`fm_index` and all FM machinery. `crow_config`, `crow_out_vo`,
`crow_out_pairs`, the `crow_outs` chord table, `set_crow`, `set_crow_notes`,
`set_crow_note_out_pairs`, `hz_to_1voct`, and the crow branches inside
`init`, `set_notes`, `enc` and `redraw_screen`.

`z_tuning` mod support stays. It is independent of the engine and already
written.

## Repo layout

```
wavetables/
  wavetables.lua
  lib/wavetables_engine.sc        Engine_Wavetables
  lib/16n.lua                     unchanged from sines
  lib/waves/rom_a.wav             E350 ROM bank A, 64 x 256
  lib/waves/rom_b.wav
  lib/waves/rom_c.wav
  lib/waves/README.md             E350 attribution
  README.md
  LICENSE                         Apache 2.0, retained from sines
  docs/superpowers/specs/
```

sines is Apache 2.0, so this keeps that license and copyright notice, with the
README stating the derivation. sines' `data/*.pset` files do not carry over;
the repo ships with no presets.

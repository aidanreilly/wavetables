# wavetables

A 16-voice wavetable drone synth for [monome norns](https://monome.org/docs/norns/).

Each voice uses three wavetable oscillators and a low-pass filter. Use LFOs to move through the waves.

<img width="800" alt="iso_all_sq" src="https://github.com/user-attachments/assets/c1e3c3da-8fbb-4a93-a880-6622b7415ec4" />

## Install

Ensure norns is up to date. Visit <http://norns.local> and run `;install https://github.com/aidanreilly/wavetables` in the maiden console.

Then `SYSTEM => RESET` to pick up the SuperCollider engine, and restart.

You can add @catfact's `z_tuning` mod for microtuning. Install it with `;install https://github.com/catfact/z_tuning`. Enable it under `SYSTEM => MODS`, then reset and restart. With the mod enabled, the top screen row shows the selected tuning and its root frequency in place of `note` and `fine`, and `fine tune` no longer applies.

## Play

Select a root note and scale in the norns params menu. 16 frequencies from that scale are spread across the voices.

Raise a few voice levels, set `bank` and `wave` to taste, then bring up `lfod` and `lfor` to set the wave morph. `osc spread` in the params menu fans the three oscillators in each voice apart so they morph independently.

### Controls

`K2` flips the screen between the voice level sliders and the param editor, so the six rows of per-voice params are reachable without the norns params menu.

| Control | Slider mode | Ctrl mode |
| --- | --- | --- |
| `E1` | unused | select row |
| `E2` | select voice | edit left param |
| `E3` | voice level, or wave in wave mode | edit right param |
| `K2` | to ctrl mode | to slider mode |
| `K3` | latch faders to level / wave | same |

**Per-voice params**

- `bank` selects a wavetable bank, and `wave` sets the starting wave within it.
- `lfo rate`, `lfo depth`, and `lfo shape` set the speed, range, and pattern of wavetable morphing.
- `fine tune` offsets the voice pitch from its note value; `detune` spreads the voice's three oscillators either side of that pitch. Both are in cents.
- `cutoff` and `slope` set the low-pass filter frequency and steepness.
- `smpl bitrate` selects the sample rate and bit depth for lo-fi processing.
- `env` sets the amplitude envelope; `pan` positions the voice in stereo.
- `vol` sets the voice's level.

**Global params**

- `root note` and `scale mode` set the notes assigned across the voices. A MIDI note on sets `root note`.
- `lfo spread` offsets the morph LFO phase from one voice to the next, so the 16 voices do not morph in lockstep. At 0 they all sit at the same point in the sweep.
- `osc spread` offsets the morph LFO phase and rate across the three oscillators within each voice. It applies the same spread in every voice.
- `amp slew` sets how fast a voice's level follows a change, whether from a fader, `E3`, or the params menu.
- `fader play mode` switches the faders between setting levels and playing them.
- `lfo shape (all)` and `global env delay rand` write the same value into all 16 per-voice params, which you can then change individually.
- `global panning` sets every voice to centre, or alternates the voices left and right.
- `auto bind 16n` binds an attached 16n to the voices. Set it to no to ignore incoming CC. `16n param jumps` decides whether a fader takes its voice straight to the fader position, or waits until the fader comes near the voice's current value.

### Wave mode

`K3` latches what the faders drive. In wave mode, each fader scans its voice through the 64 waves in its bank. This lets you morph several voices at once by hand. If you have no 16n, `E3` scans the selected voice.

### Play mode

`fader play mode` turns the faders into struck keys. Move one and its voice sounds; stop moving and the voice falls silent. A fast sweep is loud and a slow nudge is quiet.

`play sensitivity` sets how much movement counts as full level, and `play release hold` how long a voice waits before falling silent.

**16n** faders drive the 16 voice levels, or their wave positions in wave mode, or play the voices in play mode.

## Credits

Based on [sines](https://github.com/aidanreilly/sines). Included wavetable ROMs are from [Synth Tech WaveEdit](https://synthtech.com/waveedit/). `lib/16n.lua` by @p3r7.

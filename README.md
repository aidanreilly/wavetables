# wavetables

A 16-voice wavetable drone synth for [monome norns](https://monome.org/docs/norns/).

Each voice uses three wavetable oscillators and a low-pass filter. Use LFOs to move through the waves.

<img width="800" alt="iso_all_sq" src="https://github.com/user-attachments/assets/c1e3c3da-8fbb-4a93-a880-6622b7415ec4" />

## Install

Ensure norns is up to date. Visit <http://norns.local> and run `;install https://github.com/aidanreilly/wavetables` in the maiden console.

Then `SYSTEM => RESET` to pick up the SuperCollider engine, and restart.

You can add @catfact's `z_tuning` mod for microtuning. Install it with `;install https://github.com/catfact/z_tuning`. Enable it under `SYSTEM => MODS`, then reset and restart.

## Play

Select a root note and scale in the norns params menu. 16 frequencies from that scale are spread across the voices.

Raise a few voice levels, set `bank` and `wave` to taste, then bring up `lfod` and `lfor` to set the morph moving. `osc drift` in the params menu detunes the three oscillators in each voice apart so they morph independently. As they slide past each other they land on waves that reinforce or cancel, so a voice swells and thins over minutes without you touching it. Low drift holds a voice steady, high drift lets the drone breathe.

### Controls

| Control | Param |
| --- | --- |
| `E1` | select row |
| `E2` | select voice |
| `E3` | voice level, or wave in wave mode |
| `K2` | to params |
| `K3` | latch faders to level / wave |

Main params:

- `root note` and `scale mode` set the notes assigned across the 16 voices.
- `bank` selects a wavetable bank, and `wave` sets the starting wave within it.
- `lfo rate`, `lfo depth`, and `lfo shape` set the speed, range, and pattern of wavetable morphing.
- `lfo spread` offsets the morph LFO phase across voices; `osc drift` offsets phase and rate across the three oscillators in each voice.
- `osc detune` sets the pitch spread between a voice's three oscillators; `note detune` offsets the voice pitch from its overall note value.
- `cutoff` and `slope` set the low-pass filter frequency and steepness.
- `sample bitrate` selects the sample rate and bit depth for lo-fi processing.
- `env` sets the amplitude envelope; `pan` positions a voice in stereo.
- `vol` sets a voice's level.
- `fader play mode` in the params menu switches the faders between setting
levels and playing them.

Open the norns params menu for global settings such as `lfo spread`, `osc drift`, pan, and play mode.

### Wave mode

`K3` latches what the faders drive. In wave mode, each fader scans its voice through the 64 waves in its bank. This lets you morph several voices at once by hand. If you have no 16n, `E3` scans the selected voice.

### Play mode

`fader play mode` turns the faders into struck keys. Move one and its voice sounds; stop moving and the voice falls silent. A fast sweep is loud and a slow nudge is quiet.

`play sensitivity` sets how much movement counts as full level, and `play release hold` how long a voice waits before falling silent.

**16n** faders drive the 16 voice levels, or their wave positions in wave mode, or play the voices in play mode.

## Credits

Based on [sines](https://github.com/aidanreilly/sines). Included wavetable ROMs are from [Synth Tech WaveEdit](https://synthtech.com/waveedit/). `lib/16n.lua` by @p3r7.

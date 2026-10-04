# wavetables

A 16-voice wavetable drone synth for monome norns.

Each voice is three wavetable oscillators scanning 3 wavetable ROM banks, with per-oscillator LFO drift on the morph position and a variable-slope lowpass filter.

## Install

Ensure norns is up to date. Visit <http://norns.local> and run `;install https://github.com/aidanreilly/wavetables` in the maiden console.

Then `SYSTEM => RESET` to pick up the SuperCollider engine, and restart.

Optional: @catfact's `z_tuning` mod enables microtuning. Install with `;install https://github.com/catfact/z_tuning`, enable it in `SYSTEM => MODS`, then reset and restart.

## Play

Select a root note and scale in the params menu. 16 frequencies from that scale are spread across the voices.

Raise a few voice levels, set `bank` and `wave` to taste, then bring up `lfod` and `lfor` to set the morph moving. `vco drift` in the params menu fans the three oscillators in each voice apart so they morph independently.

### Controls

|  | Levels | Params (K2) |
| --- | --- | --- |
| `E1` |  | select row |
| `E2` | select voice | edit left column |
| `E3` | voice level, or wave in wave mode | edit right column |
| `K2` | to params | to levels |
| `K3` | latch faders to level / wave | same |

`fader play mode` in the params menu switches the faders between setting
levels and playing them. See below.

Rows: `note`/`dtun`, `bank`/`wave`, `lfor`/`lfod`, `cutf`/`slop`,
`shap`/`detu`, `smpl`/`env`.

Everything else, including `lfo spread`, `vco drift`, pan, play mode and the
envelope controls, is in the params menu.

### Wave mode

`K3` latches what the faders drive. In wave mode each fader scans its own voice through the 64 waves of that voice's bank, so you can morph several voices at once by hand, and `E3` scans the selected voice if you have no 16n.

### Play mode

`fader play mode` turns the faders into struck keys. Move one and its voice sounds; stop moving and the voice falls silent. A fast sweep is loud and a slow nudge is quiet.

`play sensitivity` sets how much movement counts as full level, and `play release hold` how long a voice waits before falling silent.

**16n** faders drive the 16 voice levels, or their wave positions in wave mode, or play the voices in play mode.

## Credits

Based on [sines](https://github.com/aidanreilly/sines). Included wavetable ROMs are from [Synth Tech WaveEdit](https://synthtech.com/waveedit/). `lib/16n.lua` by @p3r7.

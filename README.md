# wavetables

A 16-voice wavetable drone synth for monome norns.

Each voice is three wavetable oscillators scanning the Synthesis Technology
E350 ROM banks, with per-oscillator LFO drift on the morph position and a
variable-slope lowpass filter. Hold a chord and it keeps moving.

## Install

Ensure norns is up to date. Visit <http://norns.local> and install
`wavetables` from the maiden project manager, or run
`;install https://github.com/aidanreilly/wavetables` in the maiden console.

Then `SYSTEM => RESET` to pick up the SuperCollider engine, and restart.

Optional: @catfact's `z_tuning` mod enables microtuning. Install with
`;install https://github.com/catfact/z_tuning`, enable it in
`SYSTEM => MODS`, then reset and restart.

## Play

Select a root note and scale in the params menu. 16 frequencies from that
scale are spread across the voices.

Raise a few voice levels, set `bank` and `wave` to taste, then bring up
`lfod` and `lfor` to set the morph moving. `vco drift` in the params menu
fans the three oscillators in each voice apart so they morph independently.

### Controls

| | Levels | Params (K2) |
|---|---|---|
| `E1` | | select row |
| `E2` | select voice | edit left column |
| `E3` | voice level | edit right column |
| `K2` | to params | to levels |
| `K3` | play mode: fader / env follower | same |

Rows: `note`/`dtun`, `bank`/`wave`, `lfor`/`lfod`, `cutf`/`slop`,
`shap`/`detu`, `smpl`/`env`.

Everything else, including `lfo spread`, `vco drift`, pan and the envelope
controls, is in the params menu.

**grid** 16 columns of voice levels.

**16n** faders mapped to the 16 voice levels by default.

## Wavetables

The wavetables are the ROM banks of the
[Synthesis Technology E350 Morphing Terrarium](https://synthtech.com/eurorack/E350/),
included under `lib/waves`. See `lib/waves/README.md`.

## Credits

Derived from [sines](https://github.com/aidanreilly/sines) by @oootini,
which is where the voice architecture, envelope table, bitcrush and 16n
support come from. Apache 2.0, as sines is.

`lib/16n.lua` by @p3r7.

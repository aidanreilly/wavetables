-- Param definitions

local fmt = include("wavetables/lib/formatters")
local wavemap = include("wavetables/lib/wavemap")

local P = {}

P.NUM_VOICES = 16

P.booting = false

local function scale_names()
  local t = {}
  for i = 1, #MusicUtil.SCALES do
    table.insert(t, string.lower(MusicUtil.SCALES[i].name))
  end
  return t
end

local function build_scale()
  local notes = MusicUtil.generate_scale_of_length(
    params:get("root_note"), params:get("scale_mode"), P.NUM_VOICES)
  local missing = P.NUM_VOICES - #notes
  for _ = 1, missing do
    table.insert(notes, notes[P.NUM_VOICES - missing])
  end
  return notes
end

local function set_notes()
  local notes = build_scale()
  for i = 1, P.NUM_VOICES do
    params:set("note" .. i, notes[i])
  end
end

local function voice_hz(i)
  local n = params:get("note" .. i)
  local hz = MusicUtil.note_num_to_freq(n)
  if not z_tuning then
    hz = hz * (2 ^ (params:get("cents" .. i) / 1200))
  end
  return hz
end

local function send_hz(i)
  engine.hz(i - 1, voice_hz(i))
end

function P.add_all()
  params:add_option("scale_mode", "scale mode", scale_names(), 5)
  params:set_action("scale_mode", function() set_notes() end)

  params:add{ type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60,
    formatter = function(p) return MusicUtil.note_num_to_name(p:get(), true) end,
    action = function() set_notes() end }

  params:add_control("amp_slew", "amp slew",
    controlspec.new(0.01, 10, "lin", 0.01, 1.5, "s"))
  params:set_action("amp_slew", function(x)
    for i = 1, P.NUM_VOICES do engine.amp_slew(i - 1, x) end
  end)

  -- Both spreads are single global params with no per-voice counterpart. One
  -- engine command sets the SynthDef arg on all 16 synths, so a pset stores
  -- one value each. Unlike lfo_shape_global below, which fans out into the
  -- per-voice params and can then be overridden voice by voice.
  params:add_control("lfo_spread", "lfo spread",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.5))
  params:set_action("lfo_spread", function(x) engine.lfo_spread(x) end)

  params:add_control("osc_spread", "osc spread",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.25))
  params:set_action("osc_spread", function(x) engine.osc_spread(x) end)

  params:add_option("lfo_shape_global", "lfo shape (all)", fmt.LFO_SHAPES, 1)
  params:set_action("lfo_shape_global", function(x)
    if P.booting then return end
    for i = 1, P.NUM_VOICES do params:set("lfo_shape" .. i, x) end
  end)

  params:add_group("16n config", 2)
  params:add_option("16n_auto", "auto bind 16n", { "yes", "no" }, 1)
  params:add_option("16n_params_jump", "16n param jumps", { "yes", "no" }, 2)

  -- Play mode
  params:add_group("faders config", 3)
  params:add{ type = "number", id = "play_mode", name = "fader play mode",
    min = 0, max = 1, default = 0,
    formatter = function(p)
      return p:get() == 1 and "play" or "level"
    end }
  params:add_control("play_sensitivity", "play sensitivity",
    controlspec.new(4, 64, "lin", 1, 24, "cc/tick"))
  params:add_control("play_hold", "play release hold",
    controlspec.new(0.07, 2.0, "lin", 0.01, 0.3, "s"))

  params:add_group("panning", 1)
  params:add{ type = "number", id = "global_pan", name = "global panning",
    min = 0, max = 1, default = 0,
    formatter = function(p) return p:get() == 1 and "l/r" or "centre" end,
    action = function(x)
      if P.booting then return end
      for i = 1, P.NUM_VOICES do
        if x == 0 then params:set("pan" .. i, 0)
        elseif i % 2 == 0 then params:set("pan" .. i, 1)
        else params:set("pan" .. i, -1) end
      end
    end }

  params:add_group("env delay", P.NUM_VOICES + 1)
  params:add_control("env_delay_rand_global", "global env delay rand",
    controlspec.new(0.0, 1.0, "lin", 0.1, 0.0))
  params:set_action("env_delay_rand_global", function(x)
    if P.booting then return end
    for i = 1, P.NUM_VOICES do params:set("env_delay_rand" .. i, x) end
  end)
  for i = 1, P.NUM_VOICES do
    params:add_control("env_delay_rand" .. i, i .. "n env delay rand",
      controlspec.new(0.0, 1.0, "lin", 0.1, 0.0))
    params:set_action("env_delay_rand" .. i, function(x)
      engine.env_delay_rand(i - 1, x)
    end)
  end

  for i = 1, P.NUM_VOICES do
    params:add_group(i .. "n voice", 20)

    params:add_control("vol" .. i, i .. "n vol",
      controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
    params:set_action("vol" .. i, function(x) engine.vol(i - 1, x) end)

    params:add{ type = "number", id = "note" .. i, name = i .. "n note",
      min = 0, max = 127, default = 60,
      formatter = function(p) return MusicUtil.note_num_to_name(p:get(), true) end,
      action = function() send_hz(i) end }

    params:add_control("cents" .. i, i .. "n fine tune",
      controlspec.new(-200, 200, "lin", 1, 0, "cents"))
    params:set_action("cents" .. i, function() send_hz(i) end)

    -- Fans the three oscillators in pitch. Morph spread is osc_spread
    params:add_control("detune" .. i, i .. "n detune",
      controlspec.new(0, 50, "lin", 1, 7, "cents"))
    params:set_action("detune" .. i, function(x) engine.detune(i - 1, x) end)

    params:add{ type = "number", id = "bank" .. i, name = i .. "n bank",
      min = 1, max = wavemap.NUM_BANKS, default = 1,
      formatter = function(p) return fmt.bank(p:get()) end,
      action = function(x) engine.bank(i - 1, x) end }

    params:add_control("wave" .. i, i .. "n wave",
      controlspec.new(0, wavemap.WAVES_PER_BANK, "lin", 0.01, 0))
    params:set_action("wave" .. i, function(x) engine.wave(i - 1, x) end)

    params:add_control("lfo_rate" .. i, i .. "n lfo rate",
      controlspec.new(0.001, 20, "exp", 0, 0.08, "hz"))
    params:set_action("lfo_rate" .. i, function(x) engine.lfo_rate(i - 1, x) end)

    params:add_control("lfo_depth" .. i, i .. "n lfo depth",
      -- quantum 0.001: one detent moves ~0.03 waves, fine enough to set
      -- a slow shimmer by hand; encoder acceleration covers the range
      controlspec.new(0, 32, "lin", 0.001, 0, "", 0.001))
    params:set_action("lfo_depth" .. i, function(x) engine.lfo_depth(i - 1, x) end)

    params:add_option("lfo_shape" .. i, i .. "n lfo shape", fmt.LFO_SHAPES, 1)
    params:set_action("lfo_shape" .. i, function(x)
      engine.lfo_shape(i - 1, x - 1)   -- Select.kr is zero-based
    end)

    params:add_control("cutoff" .. i, i .. "n cutoff",
      controlspec.new(20, 20000, "exp", 0, 20000, "hz"))
    params:set_action("cutoff" .. i, function(x) engine.cutoff(i - 1, x) end)

    -- Stored in dB/oct
    params:add_control("slope" .. i, i .. "n slope",
      controlspec.new(6, 24, "lin", 0.1, 24, "db/oct"))
    params:set_action("slope" .. i, function(x)
      engine.slope_idx(i - 1, (x / 6) - 1)
    end)

    params:add{ type = "number", id = "sample_bitrate" .. i,
      name = i .. "n smpl bitrate", min = 1, max = #fmt.SAMPLE_BITRATES,
      default = 1,
      formatter = function(p) return fmt.smpl(p:get()) end,
      action = function(x)
        local e = fmt.SAMPLE_BITRATES[x]
        params:set("smpl_rate" .. i, e[2])
        params:set("bit_depth" .. i, e[3])
      end }

    params:add_control("bit_depth" .. i, i .. "n bit depth",
      controlspec.new(1, 24, "lin", 1, 24, "bits"))
    params:set_action("bit_depth" .. i, function(x)
      engine.bit_depth(i - 1, math.floor(x))
    end)

    params:add_control("smpl_rate" .. i, i .. "n sample rate",
      controlspec.new(480, 48000, "lin", 100, 48000, "hz"))
    params:set_action("smpl_rate" .. i, function(x)
      engine.smpl_rate(i - 1, math.floor(x))
    end)

    params:add{ type = "number", id = "env" .. i, name = i .. "n env",
      min = 1, max = #fmt.ENVS, default = 1,
      formatter = function(p) return fmt.env(p:get()) end,
      action = function(x)
        local e = fmt.ENVS[x]
        params:set("env_bias" .. i, e[2])
        params:set("attack" .. i, e[3])
        params:set("decay" .. i, e[4])
      end }

    params:add_control("attack" .. i, i .. "n attack",
      controlspec.new(0.01, 15.0, "lin", 0.01, 1.0, "s"))
    params:set_action("attack" .. i, function(x) engine.amp_atk(i - 1, x) end)

    params:add_control("decay" .. i, i .. "n decay",
      controlspec.new(0.01, 15.0, "lin", 0.01, 1.0, "s"))
    params:set_action("decay" .. i, function(x) engine.amp_rel(i - 1, x) end)

    params:add_control("env_bias" .. i, i .. "n bias",
      controlspec.new(0.0, 1.0, "lin", 0.1, 1.0))
    params:set_action("env_bias" .. i, function(x) engine.env_bias(i - 1, x) end)

    params:add{ type = "number", id = "env_delay" .. i,
      name = i .. "n env delay", min = 0, max = 2000, default = 0,
      formatter = function(p) return fmt.env_delay(p:get()) .. " s" end,
      action = function(x) engine.env_delay(i - 1, x / 1000) end }

    params:add{ type = "number", id = "pan" .. i, name = i .. "n pan",
      min = -1, max = 1, default = 0,
      formatter = function(p) return fmt.pan(p:get()) end,
      action = function(x) engine.pan(i - 1, x) end }
  end

  params:add_group("virtual faders", P.NUM_VOICES)
  for i = 1, P.NUM_VOICES do
    params:add{ type = "number", id = "fader" .. i, name = "fader " .. i,
      min = 0, max = 127, default = 0,
      action = function(v)
        if P.booting then return end
        if P.fader_callback then P.fader_callback(i, v) end
      end }
  end
end

-- 16n fader value to a wave position. No catch-up: in wave mode moving a
-- fader selects its voice, so the wave jumps straight to the fader.
function P.fader_to_wave(v)
  local waves = wavemap.WAVES_PER_BANK
  return util.clamp(util.linlin(0, 127, 0, waves, v), 0, waves)
end

P.set_notes = set_notes
P.voice_hz = voice_hz

return P

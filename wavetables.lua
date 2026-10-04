--- wavetables v0.1.0
-- @oootini
-- E350 wavetable drone synth
--
-- derived from sines
--
-- ▼ controls ▼
-- E2 - select voice
-- E3 - voice level
-- K2 - toggle levels/params
-- K3 - toggle fader/follow
--
-- 16n
-- n - voice level
--
-- z_tuning
-- params > edit > Z_TUNING

engine.name = "Wavetables"

_mods = require "core/mods"
MusicUtil = require "musicutil"

_16n = include "wavetables/lib/16n"
local P = include "wavetables/lib/params_def"
local ui = include "wavetables/lib/ui"
local gate = include "wavetables/lib/voicegate"

local NUM_VOICES = 16
local FPS = 14

local edit = 0            -- selected voice, zero-based
local row = 1             -- selected param row, 1 to 6
local ctrl = false        -- false: levels, true: params
local sliders = {}
local screen_dirty = true

local g = grid.connect()
local monobright = false

local redraw_clock, gate_clock, follow_clock
local fader_abs = {}
local fader_follow = {}
local prev_16n = {}

-- 16n -----------------------------------------------------------------

local function slider_crossing(i, v)
  local prev = prev_16n[i]
  if prev == nil then return true end
  if params:string("16n_params_jump") == "yes" then return true end
  return math.abs(v - prev) < 10
end

local function fader_callback(i, v)
  edit = i - 1
  if slider_crossing(i, v) then
    params:set("vol" .. i, util.linlin(0, 127, 0.0, 1.0, v))
    prev_16n[i] = v
  end
  screen_dirty = true
end

local function _16n_slider_callback(msg)
  if params:string("16n_auto") == "no" then return end
  if msg.type == "cc" then
    local id = _16n.cc_2_slider_id(msg.cc)
    if id then params:set("fader" .. id, msg.val) end
  end
end

-- env follower --------------------------------------------------------

local function follow_countdown(i, abs)
  if params:get("reset_style") == 1 then
    return math.max(0, (fader_follow[i] or 0) - 1)
  end
  return abs
end

-- lifecycle -----------------------------------------------------------

function init()
  print("wavetables: E350 wavetable drone")

  if util.string_starts(g.name, "monome 64 m64")
    or util.string_starts(g.name, "monome 128 m128")
    or util.string_starts(g.name, "monome 256 m256") then
    monobright = true
  end

  P.fader_callback = fader_callback
  P.add_all()

  -- Suppress the fan-out params while restoring, or the bang overwrites
  -- every per-voice value the pset just loaded. See P.booting.
  P.booting = true
  params:read()
  params:bang()
  P.booting = false

  for i = 1, NUM_VOICES do
    sliders[i] = params:get("vol" .. i) * ui.MAX_SLIDER
    fader_abs[i] = 0
    fader_follow[i] = 0
    prev_16n[i] = util.linlin(0.0, 1.0, 0, 127, params:get("vol" .. i))
  end

  _16n.init(_16n_slider_callback)

  if _mods.is_enabled("z_tuning") then
    z_tuning = require("z_tuning/lib/mod")
    z_tuning.set_tuning_change_callback(function()
      for i = 1, NUM_VOICES do
        engine.hz(i - 1, P.voice_hz(i))
      end
    end)
  end

  redraw_clock = clock.run(function()
    while true do
      clock.sleep(1 / FPS)
      for i = 1, NUM_VOICES do
        sliders[i] = params:get("vol" .. i) * ui.MAX_SLIDER
      end
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
    end
  end)

  -- Voice gating. Parks silent voices so they stop costing oscillators.
  gate_clock = clock.run(function()
    local t = 0
    while true do
      clock.sleep(0.1)
      t = t + 0.1
      for i = 1, NUM_VOICES do
        local change = gate.update(i, params:get("vol" .. i), t)
        if change ~= nil then
          engine.voice_run(i - 1, change and 1 or 0)
        end
      end
    end
  end)

  -- env delay randomisation and the fader env follower, from sines
  follow_clock = clock.run(function()
    while true do
      clock.sleep(1 / FPS)
      for i = 1, NUM_VOICES do
        local r = params:get("env_delay_rand" .. i)
        if r > 0 then
          engine.env_delay_rand(i - 1, math.random() * r)
        end
        fader_abs[i] = params:get("fader" .. i)
        fader_follow[i] = follow_countdown(i, fader_abs[i])
        if params:get("play_mode") == 1 then
          if math.abs(fader_follow[i] - fader_abs[i]) > 10 then
            params:set("vol" .. i,
              util.linexp(0, 127, 0.0001, 1.0, fader_follow[i]))
          end
        end
      end
    end
  end)
end

function cleanup()
  if redraw_clock then clock.cancel(redraw_clock) end
  if gate_clock then clock.cancel(gate_clock) end
  if follow_clock then clock.cancel(follow_clock) end
end

-- controls ------------------------------------------------------------

function enc(n, delta)
  if n == 1 then
    if ctrl then
      row = ((row - 1 + delta) % ui.row_count()) + 1
    end
  elseif n == 2 then
    if ctrl then
      local prefix = ui.ROWS[row].left[2]
      params:delta(prefix .. (edit + 1), delta)
    else
      edit = (edit + delta) % NUM_VOICES
    end
  elseif n == 3 then
    if ctrl then
      local prefix = ui.ROWS[row].right[2]
      params:delta(prefix .. (edit + 1), delta)
    else
      local v = sliders[edit + 1] + (delta * 2)
      params:set("vol" .. (edit + 1),
        util.linlin(0, ui.MAX_SLIDER, 0.0, 1.0, v))
    end
  end
  screen_dirty = true
end

function key(n, z)
  if z ~= 1 then return end
  if n == 2 then
    ctrl = not ctrl
  elseif n == 3 then
    params:set("play_mode", params:get("play_mode") == 0 and 1 or 0)
  end
  screen_dirty = true
end

function redraw()
  ui.redraw({
    edit = edit, row = row, ctrl = ctrl,
    sliders = sliders, play_mode = params:get("play_mode"),
  })
  ui.redraw_grid(g, { edit = edit, sliders = sliders, monobright = monobright })
end

g.key = function(x, y, z)
  if z == 1 then
    params:set("vol" .. x, util.linlin(0, g.rows, 0.0, 1.0, g.rows - y))
    edit = x - 1
    screen_dirty = true
  end
end

m = midi.connect()
m.event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    params:set("root_note", d.note)
  end
  screen_dirty = true
end

-- Screen drawing.
--
-- The design put everything on one page, which means six text rows rather
-- than sines' four. That is paid for by halving the level sliders from 32px
-- to 16px: rows sit at y 5 to 40, sliders run from y 62 up to y 44.
--
-- There is no grid renderer. Grid support was removed on request, and with
-- it the 7/8-level cap an 8-row grid imposed on the level sliders.

local fmt = include("wavetables/lib/formatters")
local wavemap = include("wavetables/lib/wavemap")

local ui = {}

ui.MAX_SLIDER = 16
ui.SLIDER_BASE_Y = 62
-- A slider is drawn from SLIDER_BASE_Y up to BASE - 2 - level, so the 2px
-- stub at zero reproduces the baseline tick sines draws. TOP_Y is where a
-- full-level slider reaches, and no text row may sit at or below it.
ui.SLIDER_TOP_Y = ui.SLIDER_BASE_Y - 2 - ui.MAX_SLIDER
ui.ROW_Y = { 5, 12, 19, 26, 33, 40 }

-- The row the wave-mode marker lights. Row 2 is bank/wave, so lighting it
-- says what the faders are currently driving.
ui.WAVE_ROW = 2

-- Column geometry, unchanged from sines.
local LABEL_X, VALUE_X = 0, 24
local LABEL2_X, VALUE2_X = 62, 89

-- Slider geometry, unchanged from sines.
local SLIDER_X0, SLIDER_DX = 32, 4

-- Row 4's left cell held `res` until resonance was measured and dropped. It
-- now holds lfo shape, so all three LFO controls sit on screen beside rate
-- and depth.
ui.ROWS = {
  { left = { "note:", "note" },   right = { "dtun:", "cents" } },
  { left = { "bank:", "bank" },   right = { "wave:", "wave" } },
  { left = { "lfor:", "lfo_rate" }, right = { "lfod:", "lfo_depth" } },
  { left = { "cutf:", "cutoff" }, right = { "slop:", "slope" } },
  { left = { "shap:", "lfo_shape" }, right = { "detu:", "detune" } },
  { left = { "smpl:", "sample_bitrate" }, right = { "env:", "env" } },
}

-- How each param renders on screen.
local RENDER = {
  note = function(v) return MusicUtil.note_num_to_name(v, true) end,
  cents = function(v) return tostring(math.floor(v + 0.5)) end,
  bank = fmt.bank,
  wave = fmt.wave,
  lfo_rate = fmt.lfo_rate,
  lfo_depth = fmt.lfo_depth,
  cutoff = fmt.cutoff,
  slope = fmt.slope,
  lfo_shape = fmt.lfo_shape,
  detune = fmt.detune,
  sample_bitrate = fmt.smpl,
  env = fmt.env,
}

function ui.row_count()
  return #ui.ROWS
end

-- Row 1 becomes a read-only tuning display when the z_tuning mod is active.
--
-- The spec requires it, and params_def already ignores `cents` under
-- z_tuning, so showing note and dtun there would put a value on screen that
-- moves under E3 and changes no pitch.
function ui.row_is_tuning(r)
  return r == 1 and z_tuning ~= nil
end

-- Draws row 1 as tuning name and root frequency. Both are clipped to the
-- 7-character column budget the formatters are held to.
local function draw_tuning_row(y, level)
  local name = "?"
  local state = z_tuning.get_tuning_state and z_tuning.get_tuning_state()
  if state and state.selected_tuning then
    name = tostring(state.selected_tuning)
  end

  screen.level(2)
  screen.move(LABEL_X, y)
  screen.text("ztun:")
  screen.level(level)
  screen.move(VALUE_X, y)
  screen.text(string.sub(name, 1, 7))

  screen.level(2)
  screen.move(LABEL2_X, y)
  screen.text("root:")
  screen.level(level)
  screen.move(VALUE2_X, y)
  screen.text(string.format("%.0fhz", params:get("zt_root_freq") or 0))
end

-- Brightness per row. In ctrl mode the selected row is lit and the rest are
-- dim; in slider mode every row is dim because the sliders have focus.
--
-- Wave mode additionally lights the bank/wave row, in either view. A latched
-- mode has to show itself: unlike a held key you can leave it on and come
-- back to it.
function ui.levels(row, ctrl, wave_mode)
  local lv = {}
  for i = 1, #ui.ROWS do
    local lit = (ctrl and i == row) or (wave_mode and i == ui.WAVE_ROW)
    lv[i] = lit and 15 or 2
  end
  return lv
end

-- Slider height for a voice, in pixels. Level mode reads vol; wave mode
-- reads wave, so the slider bank doubles as a wavetable position display.
function ui.slider_value(voice, wave_mode)
  if wave_mode then
    return util.linlin(0, wavemap.WAVES_PER_BANK, 0, ui.MAX_SLIDER,
      params:get("wave" .. voice))
  end
  return params:get("vol" .. voice) * ui.MAX_SLIDER
end

-- `override` replaces the value text entirely. Nothing clears a cell
-- between draws, so a second string at the same position would overprint
-- the first rather than replace it.
local function draw_cell(label_x, value_x, y, label, prefix, voice, level, override)
  screen.level(2)
  screen.move(label_x, y)
  screen.text(label)
  screen.level(level)
  screen.move(value_x, y)
  if override then
    screen.text(override)
  else
    screen.text(RENDER[prefix](params:get(prefix .. voice)))
  end
end

function ui.redraw(state)
  local voice = state.edit + 1
  local lv = ui.levels(state.row, state.ctrl, state.wave_mode)

  screen.aa(1)
  screen.line_width(2.0)
  screen.clear()

  for r, row in ipairs(ui.ROWS) do
    local y = ui.ROW_Y[r]
    if ui.row_is_tuning(r) then
      draw_tuning_row(y, lv[r])
      goto continue
    end
    -- The env cell reads [flw] instead of the envelope name when the fader
    -- play mode is the env follower, as sines does.
    local right_override = nil
    if r == 6 and state.play_mode == 1 then right_override = "[flw]" end
    draw_cell(LABEL_X, VALUE_X, y, row.left[1], row.left[2], voice, lv[r])
    draw_cell(LABEL2_X, VALUE2_X, y, row.right[1], row.right[2], voice, lv[r],
      right_override)
    ::continue::
  end

  for i = 0, 15 do
    screen.level(i == state.edit and 15 or 2)
    screen.move(SLIDER_X0 + i * SLIDER_DX, ui.SLIDER_BASE_Y)
    screen.line(SLIDER_X0 + i * SLIDER_DX,
      ui.SLIDER_BASE_Y - 2 - state.sliders[i + 1])
    screen.stroke()
  end

  screen.update()
end

return ui

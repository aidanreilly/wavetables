-- Screen and grid drawing.
--
-- The design put everything on one page, which means six text rows rather
-- than sines' four. That is paid for by halving the level sliders from 32px
-- to 16px: rows sit at y 5 to 40, sliders run from y 62 up to y 44.

local fmt = include("wavetables/lib/formatters")

local ui = {}

ui.MAX_SLIDER = 16
ui.SLIDER_BASE_Y = 62
-- A slider is drawn from SLIDER_BASE_Y up to BASE - 2 - level, so the 2px
-- stub at zero reproduces the baseline tick sines draws. TOP_Y is where a
-- full-level slider reaches, and no text row may sit at or below it.
ui.SLIDER_TOP_Y = ui.SLIDER_BASE_Y - 2 - ui.MAX_SLIDER
ui.ROW_Y = { 5, 12, 19, 26, 33, 40 }

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

-- Brightness per row. In ctrl mode the selected row is lit and the rest are
-- dim; in slider mode every row is dim because the sliders have focus.
function ui.levels(row, ctrl)
  local lv = {}
  for i = 1, #ui.ROWS do
    lv[i] = (ctrl and i == row) and 15 or 2
  end
  return lv
end

local function draw_cell(label_x, value_x, y, label, prefix, voice, level)
  screen.level(2)
  screen.move(label_x, y)
  screen.text(label)
  screen.level(level)
  screen.move(value_x, y)
  local render = RENDER[prefix]
  screen.text(render(params:get(prefix .. voice)))
end

function ui.redraw(state)
  local voice = state.edit + 1
  local lv = ui.levels(state.row, state.ctrl)

  screen.aa(1)
  screen.line_width(2.0)
  screen.clear()

  for r, row in ipairs(ui.ROWS) do
    local y = ui.ROW_Y[r]
    draw_cell(LABEL_X, VALUE_X, y, row.left[1], row.left[2], voice, lv[r])
    draw_cell(LABEL2_X, VALUE2_X, y, row.right[1], row.right[2], voice, lv[r])
  end

  -- The env row shows [flw] instead of the envelope name when the fader
  -- play mode is the env follower, as sines does.
  if state.play_mode == 1 then
    screen.level(lv[6])
    screen.move(VALUE2_X, ui.ROW_Y[6])
    screen.text("[flw]")
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

function ui.redraw_grid(g, state)
  local scale = ui.MAX_SLIDER / g.rows
  g:all(0)
  for x = 1, g.cols do
    local lit = math.ceil((state.sliders[x] or 0) / scale)
    for n = 0, lit - 1 do
      local y = g.rows - n
      if y >= 1 then
        -- monobright grids have no intermediate levels, so the selected
        -- column cannot be shown by brightness there.
        if state.monobright then
          g:led(x, y, 15)
        else
          g:led(x, y, x == (state.edit + 1) and 8 or 4)
        end
      end
    end
  end
  g:refresh()
end

return ui

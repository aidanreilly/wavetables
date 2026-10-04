-- Play the 16n fader
--
-- Move a fader and the voice sounds
-- Stop moving and it falls silent

local fp = {}

-- CC delta that count as playing rather than jitter
fp.THRESHOLD = 2
-- CC units of movement in one tick that give full level
fp.SENSITIVITY = 24
-- Idle ticks before the voice is released
fp.HOLD_TICKS = 4

local last = {}
local countdown = {}
local threshold = fp.THRESHOLD
local sensitivity = fp.SENSITIVITY
local hold_ticks = fp.HOLD_TICKS

function fp.reset()
  last = {}
  countdown = {}
end

function fp.configure(opts)
  opts = opts or {}
  hold_ticks = opts.hold_ticks or hold_ticks
  sensitivity = opts.sensitivity or sensitivity
  threshold = opts.threshold or threshold
end

-- Returns a level in 0..1 to apply to the voice
function fp.update(i, cc)
  local prev = last[i]
  last[i] = cc

  if prev == nil then
    countdown[i] = 0
    return nil
  end

  local moved = math.abs(cc - prev)

  if moved >= threshold then
    countdown[i] = hold_ticks
    local level = moved / sensitivity
    if level > 1 then level = 1 end
    return level
  end

  local n = countdown[i] or 0
  if n > 0 then
    n = n - 1
    countdown[i] = n
    if n == 0 then return 0 end
  end

  return nil
end

return fp

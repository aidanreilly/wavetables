-- Play the fader.
--
-- Move a fader and the voice sounds; stop moving and it falls silent, as if
-- the fader were a key being released. The fader itself stays wherever you
-- left it, anywhere in 0-127, and that position is deliberately ignored.
--
-- The level comes from how far the CC moved in one tick, so moving fast is
-- loud and moving slowly is quiet, like velocity. A 16n has no touch
-- sensing, so "let go" can only ever be read as "stopped moving", which
-- makes this a struck gesture rather than a sustaining one: holding a fader
-- still releases the voice instead of holding it open.
--
-- This replaces the version carried over from sines, which never worked.
-- There, fader_follow was only ever written from follow_countdown, which
-- returned max(0, fader_follow - 1): a decay from its own previous value,
-- starting at zero. Nothing ever loaded it from the fader, so with the fader
-- at 100 it still measured 0 after 40 ticks. In "return" mode it wrote zero
-- fourteen times a second forever and overwrote anything E3 set; in the
-- default "zeroed" mode it never wrote at all. The missing piece was edge
-- detection, which is what the delta here provides.

local fp = {}

-- CC units of movement in one tick that count as playing rather than jitter.
fp.THRESHOLD = 2
-- CC units of movement in one tick that give full level.
fp.SENSITIVITY = 24
-- Idle ticks before the voice is released.
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

-- Returns a level in 0..1 to apply to the voice, or nil for nothing to say.
--
-- Returning nil rather than a level matters: it is what lets E3 and any
-- other edit survive between strikes. The release reports 0 exactly once,
-- then goes quiet again.
function fp.update(i, cc)
  local prev = last[i]
  last[i] = cc

  -- first sight of a fader establishes a reference, it does not play
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

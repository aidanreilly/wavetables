-- Voice gating.
--
-- A silent voice still costs three oscillators, four filter stages and a
-- decimator, so a voice held at zero is parked with run(false) on the
-- server. Typical use is four to eight voices audible, which roughly halves
-- real CPU against the 16-voice worst case.
--
-- Gating off waits out a hold, because a fader or grid column swept through
-- zero would otherwise chatter the gate. Gating on is immediate, so there is
-- no attack latency.

local gate = {}

gate.HOLD = 0.5

local on = {}
local zero_since = {}

function gate.reset()
  on = {}
  zero_since = {}
end

-- Returns true to gate on, false to gate off, nil for no change.
function gate.update(i, level, now)
  if level > 0 then
    zero_since[i] = nil
    if not on[i] then
      on[i] = true
      return true
    end
    return nil
  end

  -- level is zero
  if not on[i] then return nil end
  if zero_since[i] == nil then
    zero_since[i] = now
    return nil
  end
  if (now - zero_since[i]) >= gate.HOLD then
    on[i] = false
    zero_since[i] = nil
    return false
  end
  return nil
end

function gate.is_on(i)
  return on[i] == true
end

return gate

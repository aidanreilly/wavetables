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

-- Floor for the hold. The real hold is max(HOLD, amp_slew * 1.2), set
-- through set_slew, because parking a voice stops its node computing and
-- that truncates whatever is left of the amplitude fade.
gate.HOLD = 0.5

local on = {}
local zero_since = {}
local hold = gate.HOLD

function gate.reset()
  on = {}
  zero_since = {}
end

-- Lag's time constant is its 60 dB convergence time, so a voice is still at
-- 0.001^(t/slew) of its old level t seconds in: 10% of the way through a
-- 1.5 s slew at 0.5 s, and 71% through a 10 s slew. Waiting 1.2x the slew
-- puts the park comfortably past audibility.
function gate.set_slew(seconds)
  hold = math.max(gate.HOLD, (seconds or 0) * 1.2)
end

function gate.hold()
  return hold
end

-- Returns true to gate on, false to gate off, nil for no change.
function gate.update(i, level, now)
  -- An unknown voice is RUNNING, not stopped: the engine creates all 16
  -- synths running and nothing sends voice_run at init. Treating unknown as
  -- stopped meant a voice left at zero since boot was never parked, which
  -- is the commonest case there is.
  if on[i] == nil then on[i] = true end

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
  if (now - zero_since[i]) >= hold then
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

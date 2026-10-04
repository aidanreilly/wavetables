-- Voice gating for silent voice

local gate = {}

gate.HOLD = 0.5

local on = {}
local zero_since = {}
local hold = gate.HOLD

function gate.reset()
  on = {}
  zero_since = {}
end

function gate.set_slew(seconds)
  hold = math.max(gate.HOLD, (seconds or 0) * 1.2)
end

function gate.hold()
  return hold
end

-- Returns true to gate on, false to gate off, nil for no change.
function gate.update(i, level, now)

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

-- Screen value formatting. The norns screen gives each value column about
-- 38px, which is six characters at the default font, so everything here is
-- abbreviated to fit and the test pins that width.

-- include, not require: norns resolves script-relative paths through
-- include, and the test stub maps include back onto require.
local wavemap = include("wavetables/lib/wavemap")

local fmt = {}

-- name, sample rate, bit depth. Carried over from sines unchanged.
fmt.SAMPLE_BITRATES = {
  { "hifi",    48000, 24 },
  { "clean1",  44100, 12 },
  { "clean2",  32000, 10 },
  { "clean3",  28900, 10 },
  { "grunge1", 34800, 6 },
  { "grunge2", 30700, 6 },
  { "grunge3", 28600, 6 },
  { "lofi1",   24050, 5 },
  { "lofi2",   20950, 4 },
  { "lofi3",   15850, 3 },
  { "crush1",  10000, 3 },
  { "crush2",  6000,  2 },
  { "crush3",  800,   1 },
}

-- name, env bias, attack, decay. Carried over from sines unchanged.
-- A bias of 1.0 holds the envelope open, which is what makes a drone.
fmt.ENVS = {
  { "drone",   1.0, 1.0,  1.0 },
  { "am1",     0.0, 0.001, 0.01 },
  { "am2",     0.0, 0.001, 0.02 },
  { "am3",     0.3, 0.001, 0.05 },
  { "pulse1",  0.0, 0.001, 0.2 },
  { "pulse2",  0.0, 0.001, 0.5 },
  { "pulse3",  0.0, 0.001, 0.8 },
  { "pulse4",  0.3, 0.001, 1.0 },
  { "ramp1",   0.0, 1.5,  0.01 },
  { "ramp2",   0.0, 2.0,  0.01 },
  { "ramp3",   0.0, 3.0,  0.01 },
  { "ramp4",   0.3, 4.0,  0.01 },
  { "evolve1", 0.3, 10.0, 10.0 },
  { "evolve2", 0.3, 15.0, 11.0 },
  { "evolve3", 0.3, 20.0, 12.0 },
  { "evolve4", 0.4, 25.0, 15.0 },
}

-- Order matters: the index is passed straight to Select.kr in the engine.
fmt.LFO_SHAPES = { "sine", "tri", "up", "down", "sqr", "rand" }

function fmt.bank(n)
  return wavemap.BANK_NAMES[n] or "?"
end

function fmt.wave(x)
  return string.format("%.1f", x)
end

function fmt.lfo_rate(hz)
  if hz < 10 then return string.format("%.2f", hz) end
  return string.format("%.1f", hz)
end

function fmt.lfo_depth(x)
  return string.format("%.2f", x)
end

function fmt.cutoff(hz)
  -- Round FIRST, then branch. Two reasons. Strict Lua (matron) raises
  -- "number has no integer representation" on string.format("%d", 820.37),
  -- where LuaJIT truncates silently, and cutoff is an exp controlspec whose
  -- encoder clicks land on values like 12008.000000000002. Rounding before
  -- the comparison also keeps 999.6 reading as 1.0k rather than 1000.
  local r = math.floor(hz + 0.5)
  if r < 1000 then return string.format("%d", r) end
  if r < 10000 then return string.format("%.1fk", r / 1000) end
  return string.format("%dk", math.floor(r / 1000 + 0.5))
end

function fmt.slope(db)
  return string.format("%ddb", math.floor(db + 0.5))
end

function fmt.detune(cents)
  return string.format("%dc", math.floor(cents + 0.5))
end

function fmt.smpl(n)
  local e = fmt.SAMPLE_BITRATES[n]
  return e and e[1] or "?"
end

function fmt.env(n)
  local e = fmt.ENVS[n]
  return e and e[1] or "?"
end

function fmt.pan(x)
  if x < 0 then return "L" elseif x > 0 then return "R" end
  return "C"
end

function fmt.env_delay(ms)
  return string.format("%.2f", ms / 1000)
end

function fmt.lfo_shape(n)
  return fmt.LFO_SHAPES[n] or "?"
end

return fmt

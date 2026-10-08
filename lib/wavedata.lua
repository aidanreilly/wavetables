-- The wavetable banks, read in Lua for drawing.
--
-- The engine loads the same files into buffers; this copy is decimated to
-- one point per screen pixel. No norns dependency, so it can be tested
-- with a plain lua.

local wavedata = {}

wavedata.POINTS = 64

local FILES = { "rom_a.wav", "rom_b.wav", "rom_c.wav" }
local WAVES, WAVE_LEN = 64, 256

local banks = {}

-- Finds the data chunk of a 16-bit mono WAV and returns its samples as
-- floats in [-1, 1].
local function read_wav(path)
  local f = assert(io.open(path, "rb"), "wavedata: cannot open " .. path)
  local s = f:read("a")
  f:close()

  local pos = 13   -- first chunk after "RIFF" size "WAVE"
  while pos + 8 <= #s do
    local id, size = string.unpack("<c4I4", s, pos)
    pos = pos + 8
    if id == "data" then
      local out = {}
      for i = 0, (size // 2) - 1 do
        out[i + 1] = string.unpack("<i2", s, pos + i * 2) / 32768
      end
      return out
    end
    pos = pos + size + (size % 2)
  end
  error("wavedata: no data chunk in " .. path)
end

-- Returns banks[bank][wave][point]. Each bank has 65 waves, the last a
-- copy of wave 1, matching the engine's slots so position 64 reads wave 1.
function wavedata.load(dir)
  local out = {}
  local step = WAVE_LEN // wavedata.POINTS
  for b, name in ipairs(FILES) do
    local samples = read_wav(dir .. name)
    assert(#samples == WAVES * WAVE_LEN,
      "wavedata: " .. name .. " has " .. #samples .. " samples")
    local bank = {}
    for w = 1, WAVES do
      local wave = {}
      for j = 1, wavedata.POINTS do
        wave[j] = samples[(w - 1) * WAVE_LEN + (j - 1) * step + 1]
      end
      bank[w] = wave
    end
    bank[WAVES + 1] = bank[1]
    out[b] = bank
  end
  return out
end

function wavedata.set_banks(b)
  banks = b
end

function wavedata.init(dir)
  banks = wavedata.load(dir)
end

-- The wave at a fractional morph position, blended between neighbouring
-- waves the way VOsc blends its buffers.
function wavedata.shape(bank, pos)
  local waves = banks[bank]
  if waves == nil then return nil end
  pos = math.max(0, math.min(WAVES, pos))
  local lo = math.floor(pos)
  local frac = pos - lo
  local a = waves[lo + 1]
  local b = waves[math.min(lo + 2, WAVES + 1)]
  local out = {}
  for j = 1, wavedata.POINTS do
    out[j] = a[j] + (b[j] - a[j]) * frac
  end
  return out
end

return wavedata

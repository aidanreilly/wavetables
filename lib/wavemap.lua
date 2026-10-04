-- Morph position to buffer position.
--
-- The three wavetable banks live in one consecutive 195-buffer set, because
-- VOsc requires consecutively numbered buffers. Each bank gets 65 slots rather
-- than 64: VOsc interpolates buf[n] against buf[n+1], so without a 65th
-- slot holding a copy of wave 1 the top of a bank is a dead end and a
-- cycling LFO would read the next bank's unrelated waves.
--
-- Lua's % is a floored modulo, so a negative position from a deep LFO
-- wraps correctly with no guard. SC's % behaves the same way, which is why
-- the engine can use the identical expression.

local wavemap = {}

wavemap.WAVES_PER_BANK = 64
wavemap.SLOTS_PER_BANK = 65
wavemap.NUM_BANKS = 3
wavemap.BANK_NAMES = { "A", "B", "C" }

function wavemap.bank_offset(bank)
  return (bank - 1) * wavemap.SLOTS_PER_BANK
end

function wavemap.wrap(pos)
  return pos % wavemap.WAVES_PER_BANK
end

function wavemap.bufpos(bank, pos)
  return wavemap.bank_offset(bank) + wavemap.wrap(pos)
end

function wavemap.total_slots()
  return wavemap.NUM_BANKS * wavemap.SLOTS_PER_BANK
end

return wavemap

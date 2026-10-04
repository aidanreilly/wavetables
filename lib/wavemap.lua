-- Morph position to wavetable buffer position

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

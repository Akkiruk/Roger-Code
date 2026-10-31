-- rng.lua
-- ChaCha20 random numbers and SHA-256, so a round's shuffle is strong, replayable and checkable.
-- A round starts from a secret seed. The table shows sha256(seed) before the cards are dealt and the seed afterwards,
-- so a player can check nothing was changed. State is plain numbers and survives a reboot through serial().

local bit = bit32 or require("lib.casino.bit32_shim")
local band, bor, bxor, rshift, lshift, rrotate = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift, bit.rrotate

local M = {}
local Rng = {}
Rng.__index = Rng

local MOD = 4294967296

local function add32(a, b)
  return (a + b) % MOD
end

local function rotl(x, n)
  return bor(lshift(x, n), rshift(x, 32 - n)) % MOD
end

-- ------------------------------------------------------------------ SHA-256

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

--- SHA-256 of a string, as lowercase hex.
function M.sha256(message)
  local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local length = #message
  local bits = length * 8
  local padded = message .. "\128" .. string.rep("\0", (55 - length) % 64) .. string.rep("\0", 4)
    .. string.char(math.floor(bits / 16777216) % 256, math.floor(bits / 65536) % 256,
      math.floor(bits / 256) % 256, bits % 256)

  for chunk = 1, #padded, 64 do
    local w = {}
    for i = 1, 16 do
      local a, b, c, d = padded:byte(chunk + (i - 1) * 4, chunk + (i - 1) * 4 + 3)
      w[i] = a * 16777216 + b * 65536 + c * 256 + d
    end
    for i = 17, 64 do
      local x, y = w[i - 15], w[i - 2]
      local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
      local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
      local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bit.bnot(e), g))
      local t1 = (hh + s1 + ch + K[i] + w[i]) % MOD
      local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local t2 = (s0 + maj) % MOD
      hh, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
    end
    h[1], h[2], h[3], h[4] = add32(h[1], a), add32(h[2], b), add32(h[3], c), add32(h[4], d)
    h[5], h[6], h[7], h[8] = add32(h[5], e), add32(h[6], f), add32(h[7], g), add32(h[8], hh)
  end

  local parts = {}
  for i = 1, 8 do parts[i] = string.format("%08x", h[i]) end
  return table.concat(parts)
end

-- ------------------------------------------------------------------ ChaCha20

local function quarter(s, a, b, c, d)
  s[a] = add32(s[a], s[b]); s[d] = rotl(bxor(s[d], s[a]), 16)
  s[c] = add32(s[c], s[d]); s[b] = rotl(bxor(s[b], s[c]), 12)
  s[a] = add32(s[a], s[b]); s[d] = rotl(bxor(s[d], s[a]), 8)
  s[c] = add32(s[c], s[d]); s[b] = rotl(bxor(s[b], s[c]), 7)
end

local function refill(self)
  local input = {
    0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
    self.key[1], self.key[2], self.key[3], self.key[4],
    self.key[5], self.key[6], self.key[7], self.key[8],
    self.block % MOD, 0, 0, 0,
  }
  local s = {}
  for i = 1, 16 do s[i] = input[i] end
  for _ = 1, 10 do
    quarter(s, 1, 5, 9, 13); quarter(s, 2, 6, 10, 14); quarter(s, 3, 7, 11, 15); quarter(s, 4, 8, 12, 16)
    quarter(s, 1, 6, 11, 16); quarter(s, 2, 7, 12, 13); quarter(s, 3, 8, 9, 14); quarter(s, 4, 5, 10, 15)
  end
  for i = 1, 16 do s[i] = add32(s[i], input[i]) end
  self.words = s
  self.block = self.block + 1
end

--- A generator from a 64-hex-digit seed, at a position (block, pos), both optional.
function M.new(seedHex, block, pos)
  assert(#seedHex == 64, "seed must be 64 hex digits")
  local key = {}
  for i = 1, 8 do
    key[i] = tonumber(seedHex:sub((i - 1) * 8 + 1, i * 8), 16)
  end
  local self = setmetatable({ seed = seedHex, key = key, block = block or 0, pos = pos or 16 }, Rng)
  if self.pos < 16 then
    self.block = self.block - 1
    refill(self)
  end
  return self
end

--- A uniform 32-bit integer.
function Rng:u32()
  if self.pos >= 16 then
    refill(self)
    self.pos = 0
  end
  self.pos = self.pos + 1
  return self.words[self.pos]
end

--- A uniform integer in [0, n), with no modulo bias.
function Rng:below(n)
  local limit = MOD - (MOD % n)
  local value = self:u32()
  while value >= limit do
    value = self:u32()
  end
  return value % n
end

--- Where the generator is, as plain numbers for a journal.
function Rng:serial()
  return { seed = self.seed, block = self.block, pos = self.pos }
end

function M.restore(saved)
  return M.new(saved.seed, saved.block, saved.pos)
end

--- A fresh seed from everything unpredictable the computer can see.
function M.freshSeed(extra)
  local parts = {
    tostring(os.epoch and os.epoch("utc") or os.time()),
    tostring(os.clock()),
    tostring(os.getComputerID and os.getComputerID() or 0),
    tostring(math.random(0, 2147483646)),
    tostring(math.random(0, 2147483646)),
    tostring({}),
    tostring(extra or ""),
  }
  return M.sha256(table.concat(parts, "|"))
end

return M

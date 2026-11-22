local layout = require("editor.layout")
local MODULE_NAME = layout.MODULE_NAME
local DEFAULTS = layout.DEFAULTS
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local rd32, rd16, rd8 = core.readInteger, core.readSmallInteger, core.readByte
local wr32, wr16 = core.writeInteger, core.writeSmallInteger

local function scan(pattern, purpose)
  local ok, address = pcall(core.AOBScan, pattern)
  if not ok or address == nil or address == 0 then
    error(MODULE_NAME .. ": could not find " .. purpose)
  end
  return address
end

-- The end of the executable's section an address lies in (for the code patterns here, the code
-- section). The image starts on a 64 KiB boundary with its "MZ" header; its "PE" header and
-- section table, all in that first page, give the sections. Found from the address itself, so no
-- address of the game is assumed; nil if no header turns up within 64 MiB below it. Each boundary
-- is first tested with the framework's scanner, which steps over memory that is not there, and only
-- read once its first page holds the header. Without a usable section table the image's end is
-- used (it also spans the game's large data sections, so it is slower).
local found = {}             -- { first, stop } of each section found
local missed = {}            -- 64 KiB boundaries below which no header turned up
local function sectionEnd(inside)
  for _, range in ipairs(found) do
    if inside >= range[1] and inside < range[2] then return range[2] end
  end
  local start = inside - inside % 0x10000
  if missed[start] then return nil end
  local base = start
  for _ = 1, 0x400 do
    if base < 0x10000 then break end
    local mz = core.scanForAOB("4D 5A", base, base + 0x10)
    local lfanew = mz == base and (rd32(base + 0x3C) & 0xFFFFFFFF) or 0
    local pe = base + lfanew
    if lfanew > 0 and lfanew < 0xF00 and (rd32(pe) & 0xFFFFFFFF) == 0x4550 and (rd16(pe + 4) & 0xFFFF) == 0x14C then
      local imageStop = base + (rd32(pe + 0x50) & 0xFFFFFFFF)   -- OptionalHeader.SizeOfImage
      if imageStop > inside then
        local first, stop = base, imageStop
        local count = rd16(pe + 6) & 0xFFFF                     -- FileHeader.NumberOfSections
        local table_ = pe + 0x18 + (rd16(pe + 0x14) & 0xFFFF)   -- after the optional header
        if table_ + count * 40 <= base + 0x1000 then
          for index = 0, count - 1 do
            local section = table_ + index * 40
            local from = base + (rd32(section + 12) & 0xFFFFFFFF)                    -- VirtualAddress
            local size = math.max(rd32(section + 8) & 0xFFFFFFFF, rd32(section + 16) & 0xFFFFFFFF)
            if inside >= from and inside < from + size then
              first, stop = from, from + size
              break
            end
          end
        end
        found[#found + 1] = { first, stop }
        return stop
      end
    end
    base = base - 0x10000
  end
  missed[start] = true
  log(WARNING, string.format("no executable header found below 0x%X; pattern checks scan to the "
    .. "framework's default end", inside))
  return nil
end

-- scan, and also refused when the pattern matches a second time further on in the executable's
-- section that holds it (its last byte), so the second look doesn't wander through the game's data
-- or the rest of the process.
local function scanUnique(pattern, purpose)
  local address = scan(pattern, purpose)
  local stop = sectionEnd(address)
  local again
  if stop ~= nil then
    again = core.scanForAOB(pattern, address + 1, stop - 1)
  else
    again = core.scanForAOB(pattern, address + 1)
  end
  -- Only a match inside the section counts: the framework's scanner checks its end between memory
  -- regions, so a merged region could reach past it.
  if again ~= nil and again ~= 0 and (stop == nil or again < stop) then
    error(string.format("%s: %s matches twice (0x%X, 0x%X)", MODULE_NAME, purpose, address, again))
  end
  return address
end

local function expectBytes(address, bytes, purpose)
  for index, byte in ipairs(bytes) do
    if (rd8(address + index - 1) & 0xFF) ~= byte then
      error(string.format("%s: %s at 0x%X is not the code this module knows", MODULE_NAME, purpose,
        address))
    end
  end
end

local function readOperand(base, site, purpose)
  expectBytes(base + site[1], site[2], purpose)
  return rd32(base + site[1] + #site[2])
end

local function readCallTarget(base, offset, purpose)
  expectBytes(base + offset, { 0xE8 }, purpose)
  return base + offset + 5 + rd32(base + offset + 1)
end

local function setting(config, group, name)
  local section = config[group]
  if type(section) == "table" and section[name] ~= nil then
    return section[name]
  end
  return DEFAULTS[group][name]
end

local function bytesOf(value)
  local out = {}
  for index, byte in ipairs(core.itob(value)) do
    out[index] = string.format("%02X", byte & 0xFF)
  end
  return table.concat(out, " ")
end

local function item(itemTable, index, offset)
  return itemTable + index * MENU_ITEM_SIZE + (offset or 0)
end

local function writeCString(address, text)
  local bytes = { string.byte(text, 1, -1) }
  bytes[#bytes + 1] = 0
  core.writeBytes(address, bytes)
end

-- A zero-terminated list of dwords (pairs flattened) in allocated memory.
local function dwordList(values)
  local list = core.allocate((#values + 1) * 4, true)
  for i, value in ipairs(values) do wr32(list + (i - 1) * 4, value) end
  wr32(list + #values * 4, 0)
  return list
end

local function jumpTo(site, target, size)
  local bytes = { 0xE9, core.itob(core.getRelativeAddress(site, target, -5)) }
  for _ = 6, size do bytes[#bytes + 1] = 0x90 end
  return bytes
end

return {
  scan = scan,
  scanUnique = scanUnique,
  sectionEnd = sectionEnd,
  expectBytes = expectBytes,
  readOperand = readOperand,
  readCallTarget = readCallTarget,
  setting = setting,
  bytesOf = bytesOf,
  item = item,
  writeCString = writeCString,
  dwordList = dwordList,
  jumpTo = jumpTo,
  rd32 = rd32,
  rd16 = rd16,
  rd8 = rd8,
  wr32 = wr32,
  wr16 = wr16,
}

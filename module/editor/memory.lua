local layout = require("editor.layout")
local MODULE_NAME = layout.MODULE_NAME
local DEFAULTS = layout.DEFAULTS
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local rd32, rd16, rd8 = core.readInteger, core.readSmallInteger, core.readByte
local wr32, wr16 = core.writeInteger, core.writeSmallInteger

-- End of the executable section containing an intentional multi-hit pattern.
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
      local count = rd16(pe + 6) & 0xFFFF
      local table_ = pe + 0x18 + (rd16(pe + 0x14) & 0xFFFF)
      if table_ + count * 40 > base + 0x1000 then break end
      for index = 0, count - 1 do
        local section = table_ + index * 40
        local first = base + (rd32(section + 12) & 0xFFFFFFFF)
        local size = math.max(rd32(section + 8) & 0xFFFFFFFF, rd32(section + 16) & 0xFFFFFFFF)
        if inside >= first and inside < first + size then
          if (rd32(section + 36) & 0x20000000) == 0 then return nil end
          local stop = first + size
          found[#found + 1] = { first, stop }
          return stop
        end
      end
    end
    base = base - 0x10000
  end
  missed[start] = true
  return nil
end

local function scanUnique(pattern, purpose)
  local found, address = pcall(core.AOBScan, pattern)
  if not found then
    error(string.format("%s: %s not found", MODULE_NAME, purpose))
  end
  return address
end

-- Up to `most` matches of `pattern`, in the executable section that holds the first one.
local function scanAll(pattern, most)
  local sites = {}
  local ok, at = pcall(core.scanForAOB, pattern)
  local stop = ok and at ~= nil and at ~= 0 and sectionEnd(at) or nil
  if stop == nil then return sites end
  while ok and at ~= nil and at ~= 0 and at < stop and #sites < most do
    sites[#sites + 1] = at
    ok, at = pcall(core.scanForAOB, pattern, at + 1, stop - 1)
  end
  return sites
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

-- The native menu initializers that follow registration of modal 0x3E.
local menuInitializers, menuInitializersProblem
local function menuInitializer(offset)
  if menuInitializers == nil and menuInitializersProblem == nil then
    local found, address = pcall(core.AOBScan,
      "68 ? ? ? ? 68 ? ? ? ? 68 ? ? ? ? 6A 3E B9 ? ? ? ? E8 ? ? ? ? 68 ? ? ? ? E8 ? ? ? ? 59 C3 CC CC CC CC CC CC CC CC CC")
    if found then menuInitializers = address else menuInitializersProblem = "not found" end
  end
  if not menuInitializers then error("the menu initializer sequence " .. menuInitializersProblem) end
  return menuInitializers + offset
end

local function menuTable(site, index, pattern, purpose)
  if not core.matchesAOB("68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? C3", site) then
    error(purpose .. " initializer has unexpected instructions")
  end
  local constructor = readCallTarget(site, 10, purpose)
  local address = rd32(site + 1)
  if not core.matchesAOB("51 53 8B D9 33 C9 56 8B 74 24 10 89 33", constructor)
      or not core.matchesAOB(pattern, address + index * MENU_ITEM_SIZE) then
    error(purpose .. " initializer references an unexpected constructor or item table")
  end
  return address, rd32(site + 6), constructor
end

local function setting(config, group, name)
  local section = config[group]
  if type(section) == "table" and section[name] ~= nil then
    return section[name]
  end
  return DEFAULTS[group][name]
end

local function choice(value, valid, default, option)
  if valid then return value end
  if value ~= nil then
    local name = MODULE_NAME .. "." .. option
    if type(value) ~= "string" then
      log(ERROR, string.format("%s: expected a string, using '%s'.", name, default))
    else
      log(WARNING, string.format("%s: unknown choice '%s', using '%s'.", name, value, default))
    end
  end
  return default
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
  core.writeString(address, text .. "\0")
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
  scan = scanUnique,
  menuInitializer = menuInitializer,
  menuTable = menuTable,
  scanUnique = scanUnique,
  scanAll = scanAll,
  expectBytes = expectBytes,
  readOperand = readOperand,
  readCallTarget = readCallTarget,
  setting = setting,
  choice = choice,
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

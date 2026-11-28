local layout = require("editor.layout")
local K = layout.K
local PICTURE_SIZE = layout.PICTURE_SIZE
local TEXTURES_DATA = layout.TEXTURES_DATA
local memory = require("editor.memory")
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32

---------------------------------------------------------------------------------------
-- Sprites: where a picture's pixels lie within its frame
---------------------------------------------------------------------------------------

-- The bounding box of a picture's visible pixels, from the game's loaded picture data (TGX
-- with one byte per pixel for sprites: n literal bytes, a repeated byte, n transparent, new
-- line). nil while the gm is not loaded.
local function makeSpriteBoxes(G)
  local cache = {}
  return function(gm, picture)
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local frame = first + picture - 1
    local key = frame
    if cache[key] ~= nil then return cache[key] end
    local width = rd16(G.pictureHeights - 2 + frame * PICTURE_SIZE)
    local height = rd16(G.pictureHeights + frame * PICTURE_SIZE)
    local data = rd32(G.pictureOffsets + frame * 4) + rd32(G.textures + TEXTURES_DATA)
    if width <= 0 or height <= 0 then return nil end
    local chunk, chunkStart = nil, 0
    local function byte(offset)
      if chunk == nil or offset >= chunkStart + #chunk then
        chunkStart = offset
        chunk = core.readBytes(data + offset, 4096)
      end
      return chunk[offset - chunkStart + 1] & 0xFF
    end
    local left, top, right, bottom = width, height, -1, -1
    local x, y, offset = 0, 0, 0
    local function mark(n)
      if x < left then left = x end
      if x + n - 1 > right then right = x + n - 1 end
      if y < top then top = y end
      if y > bottom then bottom = y end
    end
    while y < height and offset < width * height * 4 do
      local token = byte(offset)
      offset = offset + 1
      local n, flag = (token & 0x1F) + 1, token >> 5
      if flag == 0 then
        mark(n)
        offset, x = offset + n, x + n
      elseif flag == 4 then
        x, y = 0, y + 1
      elseif flag == 2 then
        mark(n)
        offset, x = offset + 1, x + n
      elseif flag == 1 then
        x = x + n
      else
        break
      end
    end
    local box = nil
    if right >= left then
      box = { x = left, y = top, width = right - left + 1, height = bottom - top + 1 }
    end
    cache[key] = box
    return box
  end
end

-- A picture for the blit routine from raw screen pixels (the game's own pixel values, the
-- same for both pixel formats): pixels[y * width + x + 1] or nil for see-through.
local function storeRawPicture(width, height, pixels)
  local count = width * height
  local base = core.allocate(0x14 + count * 3, true)
  local words, mask = {}, {}
  for index = 1, count do
    local value = pixels[index]
    words[index * 2 - 1], words[index * 2] = (value or 0) & 0xFF, ((value or 0) >> 8) & 0xFF
    mask[index] = value ~= nil and 255 or 0
  end
  wr32(base, width)
  wr32(base + 4, height)
  wr32(base + 8, base + 0x14)
  wr32(base + 0xC, base + 0x14)
  wr32(base + 0x10, base + 0x14 + count * 2)
  core.writeBytes(base + 0x14, words)
  core.writeBytes(base + 0x14 + count * 2, mask)
  return base
end

-- Rocks as the map renderer draws them: per footprint tile (getBuildingSizeIndexMappingData:
-- the tile's offset and picture number for the map's current turn) the picture
-- first + base + tile picture + rotation step * tiles - 1 of the rock gm, a 30 x 16 diamond
-- (512 bytes of pixels) and above it a TGX picture of the tall part. The tiles are laid out
-- with renderMap's transform for the turn and composed into one picture, cached.
local function makeRockPictures(G)
  local footprint = core.exposeCode(G.footprint, 3, 1)
  local cache, tiles = {}, {}

  local function tile(frame)
    if tiles[frame] ~= nil then return tiles[frame] end
    local header = G.pictureHeights - 2 + frame * PICTURE_SIZE
    local width, height = rd16(header), rd16(header + 2)
    local tileY, partX = rd16(header + 10), rd8(header + 13) & 0xFF
    if width <= 0 or height <= 0 then return nil end
    local data = rd32(G.pictureOffsets + frame * 4) + rd32(G.textures + TEXTURES_DATA)
    local canvas = math.max(32, partX + width)
    local pixels = {}
    local diamond = core.readBytes(data, K.TILE_DIAMOND_BYTES)
    local i = 1
    for row, n in ipairs(K.TILE_DIAMOND) do
      local left = 16 - n // 2
      for k = 0, n - 1 do
        pixels[(tileY + row - 1) * canvas + left + k + 1] = (diamond[i] & 0xFF) | ((diamond[i + 1] & 0xFF) << 8)
        i = i + 2
      end
    end
    -- The tall part: n literal pixels, a repeated pixel, n see-through, new line.
    local chunk, chunkStart = nil, 0
    local function byte(offset)
      if chunk == nil or offset >= chunkStart + #chunk then
        chunkStart = offset
        chunk = core.readBytes(data + K.TILE_DIAMOND_BYTES + offset, 4096)
      end
      return chunk[offset - chunkStart + 1] & 0xFF
    end
    local x, y, offset = 0, 0, 0
    while y < height and offset < width * height * 4 do
      local token = byte(offset)
      offset = offset + 1
      local n, flag = (token & 0x1F) + 1, token >> 5
      if flag == 0 then
        for _ = 1, n do
          pixels[y * canvas + partX + x + 1] = byte(offset) | (byte(offset + 1) << 8)
          offset, x = offset + 2, x + 1
        end
      elseif flag == 4 then
        x, y = 0, y + 1
      elseif flag == 2 then
        local value = byte(offset) | (byte(offset + 1) << 8)
        offset = offset + 2
        for _ = 1, n do
          pixels[y * canvas + partX + x + 1] = value
          x = x + 1
        end
      elseif flag == 1 then
        x = x + n
      else
        break
      end
    end
    local result = { width = canvas, height = math.max(height, tileY + 16), tileY = tileY, pixels = pixels }
    tiles[frame] = result
    return result
  end

  -- size: footprint tiles per side (1 .. 4); base: the rock's first picture. Other objects
  -- made of tiles the same way (buildings) give their gm, and `fixed`: no turned sets.
  return function(size, base, rotation, gm, fixed)
    gm = gm or G.rockGm
    local tileMap = G.tileMap
    local turn = rd32(tileMap + K.TILE_MAP.orientation)
    if rd32(tileMap + K.TILE_MAP.mode) ~= 5 then turn = turn + rotation end
    local step = fixed and 0 or (turn % 8) // 2
    local view = rd32(tileMap + K.TILE_MAP.orientation)
    local key = string.format("%d/%d/%d/%d/%d", size, base, step, view, gm)
    if cache[key] ~= nil then return cache[key] end
    local first = rd32(G.firstPictures + gm * 4)
    local t = K.TURN[view]
    if first <= 0 or t == nil then return nil end
    local parts, left, top, right, bottom = {}, math.huge, math.huge, -math.huge, -math.huge
    for k = 0, size * size - 1 do
      footprint(tileMap, k, size)
      local dx, dy = rd32(tileMap + K.TILE_MAP.tileX), rd32(tileMap + K.TILE_MAP.tileY)
      local picture = rd32(tileMap + K.TILE_MAP.tilePicture)
      local part = tile(first + base + picture + step * size * size - 1)
      if part == nil then return nil end
      local d, s = dx - dy, dx + dy
      local x = t.xd * d + t.xs * s
      local y = t.yd * d + t.ys * s - part.tileY
      parts[#parts + 1] = { part = part, x = x, y = y, order = y + part.tileY }
      left, top = math.min(left, x), math.min(top, y)
      right, bottom = math.max(right, x + part.width), math.max(bottom, y + part.height)
    end
    table.sort(parts, function(a, b) return a.order < b.order end)
    local width, height = right - left, bottom - top
    local pixels = {}
    for _, p in ipairs(parts) do
      local ox, oy = p.x - left, p.y - top
      for index, value in pairs(p.part.pixels) do
        local px, py = (index - 1) % p.part.width, (index - 1) // p.part.width
        pixels[(oy + py) * width + ox + px + 1] = value
      end
    end
    local picture = { address = storeRawPicture(width, height, pixels), width = width, height = height, pixels = pixels }
    cache[key] = picture
    return picture
  end
end

return {
  makeSpriteBoxes = makeSpriteBoxes,
  storeRawPicture = storeRawPicture,
  makeRockPictures = makeRockPictures,
}

local layout = require("editor.layout")
local K = layout.K
local C = layout.C
local MAP_LAYER = layout.MAP_LAYER
local TEXTURES_MODE = layout.TEXTURES_MODE
local TEXTURES_DIRECT_PALETTE = layout.TEXTURES_DIRECT_PALETTE
local MAX_STAGE = layout.MAX_STAGE
local PLACED_STAGE = layout.PLACED_STAGE
local TREES_IN_LANDSCAPE = layout.TREES_IN_LANDSCAPE
local TREE = layout.TREE
local FELLED_PICTURE_BASE = layout.FELLED_PICTURE_BASE
local SHRUB_PALETTES = layout.SHRUB_PALETTES
local FELLED_PALETTE = layout.FELLED_PALETTE
local memory = require("editor.memory")
local scan = memory.scan
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16

-- The tree a tree or shrub tool would plant, drawn at the tile under the mouse the way renderMap
-- draws trees; a felled one from the felled tree pictures. data.treePreview, when the pipette
-- sets it, is the exact tree to show.
function C.makeTreePreview(G, O, data)
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local mouseSetup, flatSetup = core.exposeCode(R.mouseSetup, 1, 1), core.exposeCode(R.flatSetup, 1, 1)
  local origin = scan(K.AOB_TREE_ORIGIN, "the tree origins")
  local originStride = rd32(origin + K.TREE_ORIGIN.stride)
  local originX, originY = rd32(origin + K.TREE_ORIGIN.x), rd32(origin + K.TREE_ORIGIN.y)
  local inUse = G.firstTree - (G.landscape + TREES_IN_LANDSCAPE + G.treeSize)
  local blank = {}
  for i = 1, G.treeSize do blank[i] = 0 end
  local cache = {}

  -- The picture a new tree of this type and stage starts with, as createTree gets it: the type's
  -- own update function, run once on a free tree slot (put back as it was afterwards).
  local function picture(treeType, stage)
    local key = treeType * 16 + stage
    if cache[key] ~= nil then return cache[key] end
    cache[key] = false
    local update = rd32(G.updateTree + treeType * 4)
    if update == 0 or (rd8(update) & 0xFF) ~= 0xA1 then return false end   -- `mov eax,[current tree]`
    local current = rd32(update + 1)
    for slot = G.treeSlots, 1, -1 do
      local tree = G.landscape + TREES_IN_LANDSCAPE + slot * G.treeSize
      if rd16(tree + inUse) == 0 then
        local saved = core.readBytes(tree, G.treeSize)
        core.writeBytes(tree, blank)
        wr16(tree + TREE.TYPE, treeType)
        wr16(tree + K.TREE_GM, rd16(G.typeGm + treeType * 4))
        wr32(tree + TREE.STAGE, stage)
        local before = rd32(current)
        wr32(current, slot)
        local ok = pcall(core.exposeCode(update, 0, 0))
        wr32(current, before)
        local result = rd32(tree + K.TREE_PICTURE)
        core.writeBytes(tree, saved)
        if ok and result > 0 then cache[key] = result end
        return cache[key]
      end
    end
    return false
  end

  local function surface(x, y, tile)
    local vp = R.viewport
    local turn = K.SCREEN_TURN[rd32(T + K.TILE_MAP.orientation)]
    if turn == nil or rd32(vp + K.VIEWPORT.zoomedOut) ~= 0 then return nil end
    local bias = rd32(vp + K.VIEWPORT.bias) == 0 and 0 or 0x40
    local C2 = rd32(vp + K.VIEWPORT.x) // K.TILE_WIDTH
    local R2 = (rd32(vp + K.VIEWPORT.y) + bias) // K.TILE_HEIGHT
    local d, s = x - y, x + y
    local drawX = turn.cx + turn.xd * d + turn.xs * s - K.TILE_WIDTH * C2
    local drawY = bias + turn.cy + turn.yd * d + turn.ys * s - K.TILE_HEIGHT * R2
    local lift = K.FLAT_HEIGHT_OFFSET
    if rd32(R.flatView) == 0 then lift = rd32(T + K.HEIGHT_OFFSETS + (rd8(T + R.height + tile) & 0xFF) * 4) end
    return drawX, drawY - lift
  end

  return function()
    if rd32(R.gameMode) ~= K.MAP_EDITOR or rd32(G.onMap) == 0 then return end
    local command = rd32(G.subtype)
    local treeType = G.plantTypes[command]
    if treeType == nil then return end
    local gm, shown, palette = rd16(G.typeGm + treeType * 4), nil, SHRUB_PALETTES[treeType] or 0
    local exact = data.treePreview
    if exact ~= nil and exact.command == command then
      shown = exact.picture
    else
      local stage = PLACED_STAGE
      if O.growth then stage = math.max(0, math.min(MAX_STAGE, rd32(G.brush) - 1)) end
      local logs = data.felledLogs ~= nil and rd32(data.felledLogs) or 0
      if logs > 0 and logs < K.RANDOM_STANDING and data.felledCommand ~= nil and rd32(data.felledCommand) == command then
        local felledStage = math.max(stage, K.SMALLEST_FELLED_STAGE)
        shown, palette = FELLED_PICTURE_BASE[math.min(felledStage, 4)] - logs, FELLED_PALETTE
      else
        shown = picture(treeType, stage)
      end
    end
    if not shown then return end
    -- The tile under the mouse, as the click handlers work it out.
    if rd32(R.flatView) ~= 0 then flatSetup(R.viewport) else mouseSetup(R.viewport) end
    local x, y = rd32(R.mouseX), rd32(R.mouseY)
    if x < 0 or y < 0 or x >= K.MAP_SIZE or y >= K.MAP_SIZE then return end
    -- Not where the tree cannot go: placeTree's tests on the tile, and the mask.
    if rd8(R.validTiles + y * K.MAP_SIZE + x) == 0 then return end
    local tile = rd32(R.rows + y * 12) + x
    local logic = rd32(T + R.logic + tile * 4) & 0xFFFFFFFF
    if logic & K.TREE_REFUSED ~= 0 or logic & K.TREE_FOOT_REFUSED ~= 0 or rd16(T + R.organism + tile * 2) ~= 0 then
      return
    end
    if not C.maskPeek(T, R, tile) then return end
    local drawX, drawY = surface(x, y, tile)
    if drawX == nil then return end
    -- Where renderMap puts a tree: tile + (14, 6) - the origin of the tree's gm.
    local sx = drawX + K.TREE_DRAW_X - rd16(originX + gm * originStride)
    local sy = drawY + K.TREE_DRAW_Y - rd16(originY + gm * originStride)
    local t = G.textures
    local mode, direct = rd32(t + TEXTURES_MODE), rd32(t + TEXTURES_DIRECT_PALETTE)
    local sprite, spritePalette = rd32(G.sprite), rd32(G.spritePalette)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    wr32(t + TEXTURES_DIRECT_PALETTE, 1)
    wr32(G.sprite, gm)
    wr32(G.spritePalette, palette)
    renderGM(t, gm, shown, sx, sy)
    wr32(G.sprite, sprite)
    wr32(G.spritePalette, spritePalette)
    wr32(t + TEXTURES_DIRECT_PALETTE, direct)
    wr32(t + TEXTURES_MODE, mode)
  end
end

return true

local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_IMAGE = layout.ITEM_IMAGE
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local TYPE_GROUP_START = layout.TYPE_GROUP_START
local TYPE_BLOCK = layout.TYPE_BLOCK
local TYPE_END = layout.TYPE_END
local TYPE_GROUP_MEMBER_MASK = layout.TYPE_GROUP_MEMBER_MASK
local TYPE_GROUP_MEMBER = layout.TYPE_GROUP_MEMBER
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local RENDER_IMAGE = layout.RENDER_IMAGE
local IMAGE_INDEX_MASK = layout.IMAGE_INDEX_MASK
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local K = layout.K
local C = layout.C
local IMAGE_SIZE = layout.IMAGE_SIZE
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_LINE = layout.TOOLTIP_LINE
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local PICTURE_SIZE = layout.PICTURE_SIZE
local TEXTURES_MODE = layout.TEXTURES_MODE
local TEXTURES_DATA = layout.TEXTURES_DATA
local PANEL_BOTTOM = layout.PANEL_BOTTOM
local PANEL_GAP = layout.PANEL_GAP
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local readOperand = memory.readOperand
local readCallTarget = memory.readCallTarget
local bytesOf = memory.bytesOf
local item = memory.item
local writeCString = memory.writeCString
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local buttonPictures = require("editor.images").buttonPictures
local resolveRocks = require("editor.native").resolveRocks
local sprites = require("editor.sprites")
local storeRawPicture = sprites.storeRawPicture
local makeRockPictures = sprites.makeRockPictures

---------------------------------------------------------------------------------------
-- Castle mode: the build menu
---------------------------------------------------------------------------------------

-- The build menu's item table (found by its minimap item), its constructor, its tabs and
-- buttons, and what the building counts need.
function C.resolve(G)
  local B = {}
  B.table = scan(K.AOB_BUILD_MINIMAP, "the build menu") - K.BUILD_MINIMAP_ITEM * MENU_ITEM_SIZE
  local count = 0
  while rd32(item(B.table, count, ITEM_TYPE)) ~= TYPE_END do
    count = count + 1
    if count > K.BUILD_MOST_ITEMS then error(MODULE_NAME .. ": the build menu is not the one this module knows") end
  end
  B.count = count
  B.site = scan("68 " .. bytesOf(B.table) .. " B9 ? ? ? ? E8", "the build menu's constructor")
  B.menu = rd32(B.site + 6)
  B.constructor = readCallTarget(B.site, 10, "the Menu constructor")
  local minimap = item(B.table, K.BUILD_MINIMAP_ITEM)
  B.minimapX, B.minimapWidth = rd32(minimap + ITEM_X), rd32(minimap + ITEM_WIDTH)

  -- Buttons by tab and command: item index, image table index, the action their group gives.
  B.buttons, B.blockEnd = {}, {}
  local block, groupAction = 0, nil
  for i = 0, count - 1 do
    local itemType = rd32(item(B.table, i, ITEM_TYPE))
    if itemType == TYPE_BLOCK then
      if block == 0 then B.firstBlock = i else B.blockEnd[block] = B.blockEnd[block] or i end
      block = rd32(item(B.table, i, ITEM_PARAM))
    elseif itemType == TYPE_GROUP_START then
      groupAction = rd32(item(B.table, i, ITEM_ACTION))
    elseif (itemType & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
      local param = rd32(item(B.table, i, ITEM_PARAM))
      B.buttons[block] = B.buttons[block] or {}
      if B.buttons[block][param] == nil then
        local action = rd32(item(B.table, i, ITEM_ACTION))
        if action == 0 then action = groupAction end
        B.buttons[block][param] = { index = i, image = rd32(item(B.table, i, ITEM_IMAGE)) & IMAGE_INDEX_MASK,
          action = action }
      end
    end
  end
  if block ~= 0 then B.blockEnd[block] = B.blockEnd[block] or count end
  for _, need in ipairs(K.BUILD_NEEDED) do
    local tab = B.buttons[need[1]]
    if B.blockEnd[need[1]] == nil or tab == nil or tab[need[2]] == nil then
      error(string.format("%s: button %d of build menu tab %d is missing", MODULE_NAME, need[2], need[1]))
    end
  end
  -- Every building button's group hands its command to the same toolbar action.
  B.toolbar = B.buttons[K.TAB_TOWERS][K.FIRST_TOWER].action

  G.gameMode = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND)
  B.buildings = rd32(scan(K.AOB_BUILDINGS_STATE, "the building list") + 2)
  B.currentPlayer = rd32(scan(K.AOB_CURRENT_PLAYER, "the current player") + 1)
  local loop = scan(K.AOB_PLAYER_LOOP, "the building list walk")
  B.firstState = B.buildings + rd32(loop + 2)
  B.ownerFromState = rd8(loop + K.PLAYER_LOOP_OWNER) & 0xFF
  B.buildingSize = readOperand(loop, K.PLAYER_LOOP_STRIDE, "the building list walk")
  local slots = scan(K.AOB_BUILDING_SLOTS, "the building list's size")
  if rd32(slots + K.BUILDING_SLOTS.first) ~= B.firstState then
    error(MODULE_NAME .. ": the building list is not where the module expects it")
  end
  B.capacity = (rd32(slots + K.BUILDING_SLOTS.past) - B.firstState) // B.buildingSize
  -- Which building types are a player's buildings: the game's own list of buildings an enemy
  -- can be sent to destroy (`add eax, -first / cmp eax, last / ja <counted> / movzx eax, byte
  -- [eax + table] / jmp [eax*4 + jumps]`).
  local list = scan(K.AOB_PLAYER_BUILDINGS, "the player building types")
  B.typeFromState = rd8(list + 3) & 0xFF
  local first = -C.signedByte(list + 6)
  local last = first + (rd8(list + 9) & 0xFF)
  local counted = list + 12 + (rd8(list + 11) & 0xFF)
  local bytes, jumps = rd32(list + 15), rd32(list + 22)
  local types = {}
  for buildingType = 0, 255 do
    local yes = buildingType ~= 0
    if buildingType >= first and buildingType <= last then
      yes = rd32(jumps + (rd8(bytes + buildingType - first) & 0xFF) * 4) == counted
    end
    types[buildingType + 1] = yes and 1 or 0
  end
  B.playerTypes = core.allocate(256, true)
  core.writeBytes(B.playerTypes, types)
  return B
end

-- The building counts above the minimap: three lines in the tooltip style, drawn on the map
-- surface (the minimap's right edge, just above the panel). Its box is kept in data.laneExtra
-- (menu coordinates), so the floating panels keep clear of it (editor/lane.lua).
function C.makeCounts(G, B, counts, data)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local buffers = { core.allocate(96, true), core.allocate(96, true), core.allocate(96, true) }
  return function()
    local player = rd32(B.currentPlayer)
    local texts = {
      string.format("Buildings: %d/%d", rd32(counts), B.capacity),
      string.format("Player buildings, all players: %d", rd32(counts + 4)),
      string.format("Player buildings, player %d: %d", player, rd32(counts + 8)),
    }
    local widest = 0
    for i, text in ipairs(texts) do
      writeCString(buffers[i], text)
      widest = math.max(widest, textWidth(G.textManager, buffers[i], #text, TOOLTIP_FONT))
    end
    local width = widest + 2 * TOOLTIP_PADDING
    local height = #texts * TOOLTIP_LINE + TOOLTIP_PADDING
    if data ~= nil then
      data.laneExtra.counts = { x = B.minimapX + B.minimapWidth - width, y = PANEL_BOTTOM - PANEL_GAP - height,
        w = width, h = height }
    end
    local right = rd32(B.menu + MENU_X) + B.minimapX + B.minimapWidth + rd32(G.cameraX)
    local left = right - width
    local bottom = rd32(B.menu + MENU_Y) + PANEL_BOTTOM - PANEL_GAP + rd32(G.cameraY)
    local top = bottom - height
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, left, top, right, bottom, BOX_BLEND)
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    for i = 1, #texts do
      shadowedText(G.textManager, buffers[i], left + TOOLTIP_PADDING,
        top + TOOLTIP_PADDING // 2 + (i - 1) * TOOLTIP_LINE, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    end
    wr32(G.textLayer, layer)
  end
end

-- The Barrier button in the Ruins tab: the game's "no workers" sign, on the screen like the
-- tab's other buttons, on a box while under the mouse; its name in a box if the sign cannot
-- be had.
function C.makeBarrier(G)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local blit = core.exposeCode(G.blit, 3, 0)
  local buffer = core.allocate(32, true)
  local gm = nil
  local ok, names = pcall(function()
    return { scan(K.AOB_GM_NO_WORKERS, "the gm list"), scan(K.AOB_GM_CHECK_BOXES, "the gm list") }
  end)
  local boxes = rd32(G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE)
  if ok and (names[1] - names[2]) == (K.NO_WORKERS_GM - boxes) * K.GM_RECORD_SIZE then gm = K.NO_WORKERS_GM end
  local sign = nil                         -- the sign, cut out of its picture once it is loaded

  -- The picture's pixels (16-bit TGX: n literal pixels, a repeated pixel, n see-through, new
  -- line), cropped to the first run of rows with anything in them (the sign, not the mark
  -- under it).
  local function cut()
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local frame = first + K.NO_WORKERS_PICTURE - 1
    local header = G.pictureHeights - 2 + frame * PICTURE_SIZE
    local width, height = rd16(header), rd16(header + 2)
    if width <= 0 or height <= 0 then return nil end
    local data = core.readBytes(rd32(G.pictureOffsets + frame * 4) + rd32(G.textures + TEXTURES_DATA), width * height * 3)
    local rows, x, y, i = {}, 0, 0, 1
    local function word(at) return (data[at] & 0xFF) | ((data[at + 1] & 0xFF) << 8) end
    while y < height and i <= #data do
      local token = data[i] & 0xFF
      i = i + 1
      local n, flag = (token & 0x1F) + 1, token >> 5
      if flag == 0 then
        for _ = 1, n do
          rows[y] = rows[y] or {}
          rows[y][x] = word(i)
          i, x = i + 2, x + 1
        end
      elseif flag == 2 then
        local value = word(i)
        i = i + 2
        rows[y] = rows[y] or {}
        for _ = 1, n do rows[y][x], x = value, x + 1 end
      elseif flag == 1 then
        x = x + n
      elseif flag == 4 then
        x, y = 0, y + 1
      else
        break
      end
    end
    local top = 0
    while top < height and rows[top] == nil do top = top + 1 end
    local bottom = top
    while bottom + 1 < height and rows[bottom + 1] ~= nil do bottom = bottom + 1 end
    local left, right = width, -1
    for row = top, bottom do
      for column in pairs(rows[row] or {}) do left, right = math.min(left, column), math.max(right, column) end
    end
    if right < left then return nil end
    local w, h, pixels = right - left + 1, bottom - top + 1, {}
    for row = top, bottom do
      for column, value in pairs(rows[row] or {}) do pixels[(row - top) * w + column - left + 1] = value end
    end
    return { address = storeRawPicture(w, h, pixels), width = w, height = h }
  end

  return function(barrier)
    local x, y = rd32(G.itemX), rd32(G.itemY)
    local width, height = rd32(barrier + ITEM_WIDTH), rd32(barrier + ITEM_HEIGHT)
    if gm ~= nil and sign == nil then sign = cut() end
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, K.SCREEN_LAYER)
    if sign == nil or rd32(G.hover) ~= 0 then roundedBox(G.pencil, x, y, x + width - 1, y + height - 1, BOX_BLEND) end
    if sign ~= nil then
      blit(sign.address, x + (width - sign.width) // 2, y + (height - sign.height) // 2)
      wr32(G.pencil + PENCIL_TARGET, target)
      return
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    writeCString(buffer, K.BARRIER_LABEL)
    local textX = x + (width - textWidth(G.textManager, buffer, #K.BARRIER_LABEL, TOOLTIP_FONT)) // 2
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, K.SCREEN_LAYER)
    shadowedText(G.textManager, buffer, textX, y + (height - TOOLTIP_LINE) // 2, ALIGN_LEFT, TOOLTIP_COLOUR, 0,
      TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)
  end
end

-- A picture made smaller (a whole number of times) to fit box, each pixel the average of its
-- block when at least half of the block is drawn.
function C.shrink(G, picture, box)
  local f = math.max(1, math.ceil(picture.width / box.width), math.ceil(picture.height / box.height))
  if f == 1 then return picture end
  local wide = rd32(G.pixelFormat) == 0x565
  local gShift, gMask, rShift = wide and 5 or 5, wide and 0x3F or 0x1F, wide and 11 or 10
  local w, h = picture.width // f, picture.height // f
  local pixels, source = {}, picture.pixels
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local n, r, g, b = 0, 0, 0, 0
      for dy = 0, f - 1 do
        local row = (y * f + dy) * picture.width + x * f + 1
        for dx = 0, f - 1 do
          local v = source[row + dx]
          if v ~= nil then
            n = n + 1
            r, g, b = r + ((v >> rShift) & 0x1F), g + ((v >> gShift) & gMask), b + (v & 0x1F)
          end
        end
      end
      if n * 2 >= f * f then
        pixels[y * w + x + 1] = ((r // n) << rShift) | ((g // n) << gShift) | (b // n)
      end
    end
  end
  return { address = storeRawPicture(w, h, pixels), width = w, height = h }
end

-- Pictures of buildings for the castle panels: composed from the building's tiles like the
-- tunnel entrance and made smaller; base: the first picture (nil: the building's own). Answers
-- nil while the pictures are not loaded, false when the gm has no such pictures.
function C.buildingPictures(G, B)
  local sprites = scan(K.AOB_BUILDING_SPRITES, "the building pictures")
  local convert = core.exposeCode(readCallTarget(sprites, 0, "the building types"), 2, 1)
  local firstPicture = core.exposeCode(readCallTarget(sprites, K.BUILDING_SPRITES.sprite, "the building pictures"), 2, 1)
  local gms = rd32(sprites + K.BUILDING_SPRITES.gms)
  -- getBuildingSizeForCommandBuildingType is stdcall: called as a thiscall with no `this`.
  local sizeOf = core.exposeCode(scan(K.AOB_BUILDING_SIZE, "the building sizes"), 2, 1)
  if G.footprint == nil then resolveRocks(G) end
  local tilePicture = makeRockPictures(G)
  local cache = {}
  return function(command, base)
    local key = command .. "/" .. tostring(base)
    if cache[key] ~= nil then return cache[key] end
    local gm = rd32(gms + (convert(B.buildings, command) & 0xFFFF) * 4)
    base = base or firstPicture(B.buildings, command)
    local size = sizeOf(0, command)
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local after = rd32(G.firstPictures + (gm + 1) * 4)
    if size < 1 or size > 13 or (after > first and base + size * size - 1 > after - first) then
      cache[key] = false
      return false
    end
    local picture = tilePicture(size, base, 0, gm, true)
    if picture == nil then return nil end
    cache[key] = C.shrink(G, picture, K.VARIANT_THUMB)
    return cache[key]
  end
end

-- What a castle panel shows for the chosen tool: rows of commands with a game picture and a
-- label each; `when` says for which chosen tools (nil: whenever its tab is open). An entry
-- with `images` stands for the chosen tool itself (its picture by command); one with `flag`
-- is a way of placing it, chosen while the flag holds its `value`.
function C.makeEntries(G, panel, rows)
  return function(command)
    for _, row in ipairs(rows) do
      if row.when == nil or row.when[command] then
        local list = {}
        for i, entry in ipairs(row) do
          local param, image = entry.command, entry.image
          if entry.images ~= nil then param, image = command, entry.images[command] end
          local chosen = command == param
          if entry.tool ~= nil then param = entry.tool end   -- the button that chooses this tool
          if entry.flag ~= nil then chosen = chosen and rd32(entry.flag) == entry.value end
          if entry.lock ~= nil then chosen = chosen and rd32(entry.lock) == param end
          list[i] = { item = panel.items[i], image = image, label = entry.label, param = param, chosen = chosen,
            minWidth = entry.minWidth }
          if entry.compose ~= nil then
            local picture = entry.compose()
            if picture == nil then return {} end              -- its pictures are not loaded yet
            if picture then list[i].image, list[i].picture = nil, picture end   -- false: the menu's
          end
        end
        return list
      end
    end
    return {}
  end
end

-- Player 0's shield: a click sets the current player to 0 the way the game's shields set theirs
-- (every player flag cleared, flag 0 set); drawn in its chosen look while player 0 is current.
function C.shieldZero(G, click, draw)
  local choice = scan(K.AOB_PLAYER_CHOICE, "the player shields")
  local flags, current = rd32(choice + K.PLAYER_CHOICE.flags), rd32(choice + K.PLAYER_CHOICE.current)
  local pictures = buttonPictures("shield0")
  local chosen = core.allocate(4, true)
  for _, at in ipairs({ click, draw }) do
    wr32(at + ITEM_X, K.SHIELD_ZERO.x)
    wr32(at + ITEM_Y, K.SHIELD_ZERO.y)
    wr32(at + ITEM_TEXT, 0)
    wr16(at + ITEM_CONTROL, -1)
  end
  wr32(click + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(click + ITEM_WIDTH, pictures.width)
  wr32(click + ITEM_HEIGHT, pictures.height)
  wr32(click + ITEM_RENDER_TYPE, RENDER_NONE)
  wr32(click + ITEM_ACTION, C.luaPad(function()
    if rd32(G.gameMode) ~= K.MAP_EDITOR then return end
    for p = 0, K.SHIELD_ZERO.players - 1 do wr32(flags + p * 4, 0) end
    wr32(flags, 1)
    wr32(current, 0)
  end, "the player 0 shield"))
  wr16(click + ITEM_HIDDEN, 1)
  local button = core.allocateAssembly(templates.flagPictureButton, {
    NORMAL = pictures.normal, HOVERED = pictures.hover, CHOSEN = pictures.chosen, FLAG = chosen,
    HOVER = click + ITEM_HOVERED, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET, ITEM_X = G.itemX,
    ITEM_Y = G.itemY, BLIT = G.blit,
  })
  wr32(draw + ITEM_TYPE, TYPE_CLICKABLE)     -- no size, so never under the mouse
  wr32(draw + ITEM_WIDTH, 0)
  wr32(draw + ITEM_HEIGHT, 0)
  wr32(draw + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(draw + ITEM_RENDER, core.allocateAssembly(templates.shieldZero, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, CLICK = click, ITEM_HIDDEN = ITEM_HIDDEN,
    CURRENT = current, CHOSEN = chosen, BUTTON = button,
  }))
  wr16(draw + ITEM_HIDDEN, 0)
end

-- The tooltip of the keep crest under the mouse: what the crest is and what a click does, in a
-- box above the crest (below it near the top of the screen), drawn on the map surface after the
-- crests. hovered: player, active, and the crest's place on the map surface (x, y, w, h).
function C.crestTooltip(G)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local buffers = {}
  for i = 1, math.max(#K.CREST_TOOLTIP.active, #K.CREST_TOOLTIP.other) do buffers[i] = core.allocate(96, true) end
  return function(hovered, camY)
    local who = "player " .. hovered.player
    local lines = {}
    for i, text in ipairs(hovered.active and K.CREST_TOOLTIP.active or K.CREST_TOOLTIP.other) do
      lines[i] = text:gsub("{player}", who)
    end
    local widest = 0
    for i, text in ipairs(lines) do
      writeCString(buffers[i], text)
      widest = math.max(widest, textWidth(G.textManager, buffers[i], #text, TOOLTIP_FONT))
    end
    local width = widest + 2 * TOOLTIP_PADDING
    local height = #lines * TOOLTIP_LINE + TOOLTIP_PADDING
    local left = hovered.x + hovered.w // 2 - width // 2
    local bottom = hovered.y - K.CREST_TOOLTIP.gap
    if bottom - height < camY then bottom = hovered.y + hovered.h + K.CREST_TOOLTIP.gap + height end
    local top = bottom - height
    roundedBox(G.pencil, left, top, left + width, bottom, BOX_BLEND)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    for i = 1, #lines do
      shadowedText(G.textManager, buffers[i], left + TOOLTIP_PADDING, top + TOOLTIP_PADDING // 2 + (i - 1) * TOOLTIP_LINE,
        ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    end
    wr32(G.textLayer, layer)
  end
end

-- The keep crests, drawn every frame in castle mode of the map editor; also keeps each player's
-- active keep where the map maker left it: a newly placed keep does not take it over (the game
-- makes every new keep the active one), and a removed active keep hands over to another keep of
-- the same player (the game leaves the player without one).
function C.keepCrests(G, B, data, at)
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local site = scan(K.AOB_KEEP_ENTRY_CALL, "the keep's entry")
  local gameState = rd32(site + K.KEEP_ENTRY.state)
  local entryFn = readCallTarget(site, K.KEEP_ENTRY.call, "the keep's entry")
  if entryFn ~= scan(K.AOB_EARLIER_BUILDING, "the keep's entry") then
    error(MODULE_NAME .. ": placeKeep does not call the function this module knows")
  end
  local stride = readOperand(entryFn, K.KEEP_ENTRY.strideAt, "the keep's entry")
  local setEntry = core.exposeCode(entryFn, 4, 1)   -- this + keep, player, category (ret 0xC)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local blit = core.exposeCode(G.blit, 3, 0)
  local inside = core.exposeCode(G.isMouseInside, 5, 1)
  local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = R.keyState }), 1, 0)
  local zero = buttonPictures("shield0")
  local first = B.buildings + K.BUILDING.first
  local size = B.buildingSize
  local stateOff = B.firstState - (first + size)
  local function building(id) return first + id * size end
  local function count() return rd32(B.buildings + K.MAX_BUILDINGS) end
  local function alive(id)
    local state = rd16(building(id) + stateOff) & 0xFFFF
    return state ~= 0 and state ~= K.BUILDING_REMOVED
  end
  local function entry(player, category)
    return gameState + K.KEEP_ENTRY.first + player * stride + category * K.KEEP_ENTRY.entry
  end
  -- Each player's shield: the gm picture its shield button shows (selected: picture + 8).
  local crest = {}
  for i = 0, B.count - 1 do
    local player = -9 - rd32(item(B.table, i, ITEM_PARAM))
    if player >= 1 and player <= K.PLAYERS and crest[player] == nil
        and (rd32(item(B.table, i, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER
        and rd32(item(B.table, i, ITEM_RENDER_TYPE)) == RENDER_IMAGE then
      local image = G.buttonImages + (rd32(item(B.table, i, ITEM_IMAGE)) & IMAGE_INDEX_MASK) * IMAGE_SIZE
      crest[player] = { gm = rd32(image), picture = rd32(image + 4) }
    end
  end
  local rects = {}
  for i = 1, K.CREST.rects do rects[i] = C.takeRect(data) end
  local explain = data.crestTooltip and C.crestTooltip(G) or nil

  local function keepsNow()
    local list = {}
    for id = 1, count() - 1 do
      local b = building(id)
      if alive(id) and K.KEEP_TYPES[rd16(b + K.BUILDING.type) & 0xFFFF] then
        list[#list + 1] = { id = id, owner = rd16(b + K.BUILDING.owner), b = b }
      end
    end
    return list
  end
  local function isKeepOf(id, player)
    if id <= 0 or id >= count() or not alive(id) then return false end
    local b = building(id)
    return K.KEEP_TYPES[rd16(b + K.BUILDING.type) & 0xFFFF] ~= nil and rd16(b + K.BUILDING.owner) == player
  end
  -- A part placed together with a keep (placeKeep gives them one uidWhenPlaced): its campfire
  -- area or its stockpile.
  local function partOf(keep, kind)
    local uid, owner = rd32(building(keep) + K.BUILDING.uid), rd16(building(keep) + K.BUILDING.owner)
    for id = 1, count() - 1 do
      local b = building(id)
      if alive(id) and rd16(b + K.BUILDING.type) == kind and rd32(b + K.BUILDING.uid) == uid
          and rd16(b + K.BUILDING.owner) == owner then
        return id
      end
    end
    return nil
  end
  local function clear(player)
    for _, category in ipairs({ 0, K.KEEP_ENTRY.campfire }) do
      for d = 0, K.KEEP_ENTRY.dwords - 1 do wr32(entry(player, category) + d * 4, 0) end
    end
  end
  -- The player's stockpile entry follows the active keep. The game keeps the first stockpile
  -- ever placed there, and at the start of a match it removes the active keep together with the
  -- stockpile in that entry: with another keep's stockpile there, the active keep's own stockpile
  -- stayed and blocked the AI's castle plan, and the eraser took the active keep along with that
  -- other stockpile.
  -- A keep placed without its stockpile leaves the entry as it is.
  local function syncStockpile(keep, player)
    local stock = partOf(keep, K.STOCKPILE_TYPE)
    if stock == nil or rd32(entry(player, K.KEEP_ENTRY.stockpile)) == stock then return end
    for d = 0, K.KEEP_ENTRY.dwords - 1 do wr32(entry(player, K.KEEP_ENTRY.stockpile) + d * 4, 0) end
    setEntry(gameState, stock, player, K.KEEP_ENTRY.stockpile)
  end
  local function activate(keep, player)
    setEntry(gameState, keep, player, 0)
    local fire = partOf(keep, K.CAMPGROUND_TYPE)
    if fire ~= nil then setEntry(gameState, fire, player, K.KEEP_ENTRY.campfire) end
    syncStockpile(keep, player)
  end

  -- Where renderMap draws a tile on the map surface (as the tree preview works it out).
  local function surface(x, y, tile)
    local vp = R.viewport
    local turn = K.SCREEN_TURN[rd32(T + K.TILE_MAP.orientation)]
    if turn == nil or rd32(vp + K.VIEWPORT.zoomedOut) ~= 0 then return nil end
    local bias = rd32(vp + K.VIEWPORT.bias) == 0 and 0 or 0x40
    local column = rd32(vp + K.VIEWPORT.x) // K.TILE_WIDTH
    local row = (rd32(vp + K.VIEWPORT.y) + bias) // K.TILE_HEIGHT
    local d, sum = x - y, x + y
    local drawX = turn.cx + turn.xd * d + turn.xs * sum - K.TILE_WIDTH * column
    local drawY = bias + turn.cy + turn.yd * d + turn.ys * sum - K.TILE_HEIGHT * row
    local lift = K.FLAT_HEIGHT_OFFSET
    if rd32(R.flatView) == 0 then lift = rd32(T + K.HEIGHT_OFFSETS + (rd8(T + R.height + tile) & 0xFF) * 4) end
    return drawX, drawY - lift
  end

  local known, knownStock, wasEditor, wasDown = {}, {}, false, true
  local function tick()
    if rd32(R.gameMode) ~= K.MAP_EDITOR then
      wasEditor = false
      return
    end
    local keeps = keepsNow()
    -- The active keeps stay as the map maker left them.
    if not wasEditor then
      wasEditor = true
      for p = 0, K.PLAYERS do
        known[p] = rd32(entry(p, 0))
        if isKeepOf(known[p], p) then syncStockpile(known[p], p) end   -- maps made before this
        knownStock[p] = rd32(entry(p, K.KEEP_ENTRY.stockpile))
      end
    else
      for p = 0, K.PLAYERS do
        local now, before = rd32(entry(p, 0)), known[p]
        if before ~= nil and before > 0 then
          if not isKeepOf(before, p) then
            -- the active keep is gone: the player's next keep, else none
            local other = nil
            for _, keep in ipairs(keeps) do
              if other == nil and keep.owner == p then other = keep.id end
            end
            if other ~= nil then activate(other, p) else clear(p) end
          elseif now ~= before then
            activate(before, p)                     -- a new keep took over: give it back
          end
        end
        -- a first keep, or a stockpile entry changed under it (a separate stockpile placed first)
        local active, stock = rd32(entry(p, 0)), rd32(entry(p, K.KEEP_ENTRY.stockpile))
        if (active ~= known[p] or stock ~= knownStock[p]) and isKeepOf(active, p) then syncStockpile(active, p) end
        known[p], knownStock[p] = active, rd32(entry(p, K.KEEP_ENTRY.stockpile))
      end
    end

    local down = (asyncKey(K.LEFT_BUTTON) % 0x10000) >= 0x8000
    local pressed = down and not wasDown
    wasDown = down
    local menuX, menuY = rd32(B.menu + MENU_X), rd32(B.menu + MENU_Y)
    local camX, camY = rd32(G.cameraX), rd32(G.cameraY)
    local t = G.textures
    local mode, target = rd32(t + TEXTURES_MODE), rd32(G.pencil + PENCIL_TARGET)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    -- An error must not leave the menu drawing onto the map surface.
    local ok, problem = pcall(function()
    local used, hovered = 0, nil
    for _, keep in ipairs(keeps) do
      local p = keep.owner
      local half = (rd32(keep.b + K.BUILDING.size) & 0xFF) // 2
      local x, y = rd16(keep.b + K.BUILDING.x) + half, rd16(keep.b + K.BUILDING.y) + half
      if p >= 0 and p <= K.PLAYERS and (p == 0 or crest[p] ~= nil)
          and x >= 0 and y >= 0 and x < K.MAP_SIZE and y < K.MAP_SIZE then
        local drawX, drawY = surface(x, y, rd32(R.rows + y * 12) + x)
        if drawX ~= nil then
          local active = rd32(entry(p, 0)) == keep.id
          local w, h = zero.width, zero.height
          local sx, sy = drawX + K.TILE_WIDTH // 2 - w // 2, drawY - K.CREST.lift - h
          if p == 0 then
            blit(active and zero.chosen or zero.normal, sx, sy)
          else
            renderGM(t, crest[p].gm, crest[p].picture + (active and K.CREST.selected or 0), sx, sy)
          end
          local screenX, screenY = sx - camX, sy - camY
          used = used + 1
          if rects[used] ~= nil then C.markRect(rects[used], screenX - menuX, screenY - menuY, w, h) end
          local over = inside(G.mouse, screenX, screenY, w, h) ~= 0
          if over then hovered = { player = p, keep = keep.id, x = sx, y = sy, w = w, h = h } end
          if pressed and over then
            pressed = false
            if active then clear(p) else activate(keep.id, p) end
            known[p] = rd32(entry(p, 0))
          end
        end
      end
    end
    if hovered ~= nil and explain ~= nil then
      hovered.active = rd32(entry(hovered.player, 0)) == hovered.keep   -- after a click this frame
      explain(hovered, camY)
    end
    end)
    wr32(G.pencil + PENCIL_TARGET, target)
    wr32(t + TEXTURES_MODE, mode)
    if not ok then error(problem, 0) end
  end
  wr32(at + ITEM_TYPE, TYPE_CLICKABLE)       -- no size, so never under the mouse
  wr32(at + ITEM_WIDTH, 0)
  wr32(at + ITEM_HEIGHT, 0)
  wr32(at + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(at + ITEM_RENDER, C.luaPad(tick, "the keep crests"))
  wr32(at + ITEM_TEXT, 0)
  wr16(at + ITEM_CONTROL, -1)
  wr16(at + ITEM_HIDDEN, 0)
end

return true

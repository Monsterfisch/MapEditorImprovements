local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local K = layout.K
local C = layout.C
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local PANEL_BOTTOM = layout.PANEL_BOTTOM
local PANEL_GAP = layout.PANEL_GAP
local memory = require("editor.memory")
local scan = memory.scan
local writeCString = memory.writeCString
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local lane = require("editor.lane")
local patchJump = require("editor.menu_install").patchJump

-- Wall tools (features 35): the words the crenellation hook reads, made once.
function C.wallWords()
  if C.wallState == nil then
    C.wallState = { height = core.allocate(4, true), low = core.allocate(4, true), mode = core.allocate(4, true) }
  end
  return C.wallState
end

-- The game code the wall tools change: placeWalls' wall heights (high, low), its crenellations'
-- join point, the stairs' first step and the per-step drop in the three functions that walk a
-- dragged wall, and the two tests in validateWallBuildPath that refuse a crenellation not
-- touching a wall.
function C.wallSites()
  if C.wallSiteCache ~= nil then return C.wallSiteCache end
  local W = K.WALL_SITES
  local heights = scan(W.heights.aob, "the wall heights")
  local crenel = scan(W.crenel.aob, "the crenellation heights")
  local sites = {
    high = heights + W.heights.high, low = heights + W.heights.low,
    join = crenel + W.crenel.join, live = rd32(crenel + W.crenel.live),
    first = scan(W.first.aob, "the first stair") + W.first.at,
    steps = {},
    free1 = scan(W.free1.aob, "the crenellation test"), free2 = scan(W.free2.aob, "the crenellation test") + W.free2.at,
  }
  for _, step in ipairs(W.steps) do
    sites.steps[#sites.steps + 1] = scan(step.aob, "the stairs' step") + step.at
  end
  if rd8(sites.high) & 0xFF ~= K.WALL_DEFAULT[K.HIGH_WALL] or rd8(sites.low) & 0xFF ~= K.WALL_DEFAULT[K.LOW_WALL]
      or rd8(sites.first) & 0xFF ~= K.STAIR_STEP then
    error(MODULE_NAME .. ": the wall heights are not the game's own")
  end
  for _, at in ipairs(sites.steps) do
    if rd32(at) ~= K.STAIR_STEP then error(MODULE_NAME .. ": the stairs' step is not the game's own") end
  end
  C.wallSiteCache = sites
  return sites
end

-- Crenellations may stand free in the map editor, and the crenellation choice / height slider
-- sets their height at the point all of placeWalls' crenellation heights meet (Smarter Walls'
-- own height jumps there too).
function C.patchWallTools(self, G, data)
  local S = C.wallSites()
  local W = C.wallWords()
  local R = C.resolvePipette(G)
  local yes1 = S.free1 + 6 + C.signedByte(S.free1 + 5)
  patchJump(self, S.free1, 6, core.allocateAssembly(templates.crenelFree1, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, YES = yes1, REFUSE = S.free1 + 6,
  }))
  local yes2 = S.free2 + 4 + C.signedByte(S.free2 + 3)
  patchJump(self, S.free2, 5, core.allocateAssembly(templates.crenelFree2, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, YES = yes2, REFUSE = S.free2 + 5,
  }))
  if S.live ~= R.height then error(MODULE_NAME .. ": placeWalls' height layer is not the tile map's") end
  patchJump(self, S.join, 7, C.assemble("crenelHeight", {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HEIGHT = W.height, LOW = W.low,
    BASE = R.defaultHeight, LIVE = R.height, BACK = S.join + 7,
  }))
  -- The bytes the sliders rewrite go back to the game's own on disable.
  self.saved = self.saved or {}
  for _, at in ipairs({ S.high, S.low, S.first }) do
    table.insert(self.saved, { address = at, bytes = core.readBytes(at, 1) })
  end
  for _, at in ipairs(S.steps) do table.insert(self.saved, { address = at, bytes = core.readBytes(at, 4) }) end
end

-- The slider above the wall panel: Wall Height (0-255) for the high and low wall and the
-- crenellations, Steepness (0-16) for stairs. Values are kept per tool until the map editor is
-- left; a tool nobody moved the slider of builds the game's own way.
function C.wallControls(G, B, data, click, paint, reset)
  local S = C.wallSites()
  local W = C.wallWords()
  local R = C.resolvePipette(G)
  local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = R.keyState }), 1, 0)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local buffer = core.allocate(64, true)
  local rect = C.takeRect(data)
  local P = K.WALL_SLIDER
  local GB = setmetatable({ menu = B.menu }, { __index = G })   -- G with the build menu
  local laneOwner = { items = { click, reset } }   -- what editor/lane.lua places
  local values, drag, applied = {}, false, {}
  local function width(text)
    writeCString(buffer, text)
    return textWidth(G.textManager, buffer, #text, TOOLTIP_FONT)
  end
  local function crenelDefault()
    local mode = rd32(W.mode)
    return (mode == K.CRENEL_LOW or mode == K.CRENEL_LOW_DAMAGED) and K.CRENEL_LOW_HEIGHT or K.CRENEL_HIGH_HEIGHT
  end
  local function default(tool)
    if tool == K.CRENEL_WALL then return crenelDefault() end
    return K.WALL_DEFAULT[tool]
  end
  local function range(tool) return 0, tool == K.STAIRS and K.STAIR_STEP or 0xFF end
  local function write(at, value, size)
    if applied[at] == value then return end
    applied[at] = value
    if size == 4 then core.writeCodeInteger(at, value) else core.writeCodeByte(at, value) end
  end
  local function apply()
    write(S.high, values[K.HIGH_WALL] or K.WALL_DEFAULT[K.HIGH_WALL], 1)
    write(S.low, values[K.LOW_WALL] or K.WALL_DEFAULT[K.LOW_WALL], 1)
    local step = values[K.STAIRS] or K.STAIR_STEP
    write(S.first, step, 1)
    for _, at in ipairs(S.steps) do write(at, step, 4) end
    local mode = rd32(W.mode)
    local low = (mode == K.CRENEL_LOW or mode == K.CRENEL_LOW_DAMAGED) and 1 or 0
    local height = values[K.CRENEL_WALL]
    if height == nil and mode ~= 0 and mode ~= K.CRENEL_DAMAGED then height = crenelDefault() end
    wr32(W.height, height or 0)
    wr32(W.low, low)
    -- The crenellation choices that are damaged ones: the damaged look while they are chosen.
    if data.damagedWalls ~= nil and rd32(G.subtype) == K.CRENEL_WALL then
      local damaged = mode == K.CRENEL_LOW_DAMAGED or mode == K.CRENEL_HIGH_DAMAGED
      wr32(data.damagedWalls, damaged and 1 or 0)
    end
  end
  local function valueAt(tool)
    local lo, hi = range(tool)
    local left = rd32(B.menu + MENU_X) + rd32(click + ITEM_X)
    local w = math.max(1, rd32(click + ITEM_WIDTH))
    local value = lo + ((C.mouseX(G) - left) * (hi - lo) + w // 2) // w
    return math.max(lo, math.min(hi, value))
  end
  wr32(click + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(click + ITEM_RENDER_TYPE, RENDER_NONE)
  wr32(click + ITEM_TEXT, 0)
  wr16(click + ITEM_CONTROL, -1)
  wr16(click + ITEM_HIDDEN, 1)
  wr32(click + ITEM_ACTION, C.luaPad(function()
    local tool = rd32(G.subtype)
    if K.WALL_DEFAULT[tool] == nil and tool ~= K.CRENEL_WALL then return end
    values[tool] = valueAt(tool)
    drag = true
  end, "the wall height slider"))
  -- Reset: the chosen tool builds the game's own height (or steepness) again.
  wr32(reset + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(reset + ITEM_RENDER_TYPE, RENDER_NONE)
  wr32(reset + ITEM_TEXT, 0)
  wr16(reset + ITEM_CONTROL, -1)
  wr16(reset + ITEM_HIDDEN, 1)
  wr32(reset + ITEM_ACTION, C.luaPad(function()
    values[rd32(G.subtype)] = nil
    drag = false
  end, "the wall height reset"))

  local function frame()
    if rd32(G.gameMode) ~= K.MAP_EDITOR then
      values, drag = {}, false
      wr32(W.mode, 0)
      apply()
      wr16(click + ITEM_HIDDEN, 1)
      wr16(reset + ITEM_HIDDEN, 1)
      return
    end
    local tool = rd32(G.subtype)
    if drag then
      if (asyncKey(K.LEFT_BUTTON) % 0x10000) < 0x8000 then
        drag = false
      elseif K.WALL_DEFAULT[tool] ~= nil or tool == K.CRENEL_WALL then
        values[tool] = valueAt(tool)
      end
    end
    apply()
    wr16(click + ITEM_HIDDEN, 1)
    wr16(reset + ITEM_HIDDEN, 1)
    if rd32(G.activeTab) ~= K.TAB_CASTLE or (K.WALL_DEFAULT[tool] == nil and tool ~= K.CRENEL_WALL) then return end

    local value = values[tool] or default(tool)
    local label = string.format("%s %d", tool == K.STAIRS and "Steepness:" or "Wall Height:", value)
    local labelWidth = width(tool == K.STAIRS and "Steepness: 16" or "Wall Height: 255")
    local resetWidth = width(P.reset) + 2 * TOOLTIP_PADDING
    local total = TOOLTIP_PADDING + labelWidth + TOOLTIP_PADDING + P.track + TOOLTIP_PADDING + resetWidth
      + TOOLTIP_PADDING
    -- Above the wall panel when it is shown (clear of its box), else where it would be; placed in
    -- the band like the panels (editor/lane.lua).
    local panel = tool == K.CRENEL_WALL and data.crenelPanel or data.wallPanel
    local panelTop = PANEL_BOTTOM - P.panelRoom
    local extra = {}
    if panel ~= nil and panel.items ~= nil and panel.items[1] ~= nil and rd16(panel.items[1] + ITEM_HIDDEN) == 0 then
      panelTop = rd32(panel.items[1] + ITEM_Y)
      local l, r, b = nil, nil, panelTop
      for _, address in ipairs(panel.items) do
        if rd16(address + ITEM_HIDDEN) == 0 then
          local x = rd32(address + ITEM_X)
          l = l == nil and x or math.min(l, x)
          r = r == nil and x + rd32(address + ITEM_WIDTH) or math.max(r, x + rd32(address + ITEM_WIDTH))
          b = math.max(b, panelTop + rd32(address + ITEM_HEIGHT))
        end
      end
      extra[1] = { x = l - PANEL_GAP, y = panelTop - PANEL_GAP, w = r - l + 2 * PANEL_GAP, h = b - panelTop + 2 * PANEL_GAP }
    end
    local left, top = lane.spot(GB, data, laneOwner, total, P.height, panelTop - 3 * PANEL_GAP, extra)
    local bottom = top + P.height
    local menuX = rd32(B.menu + MENU_X)
    local trackX = left + TOOLTIP_PADDING + labelWidth + TOOLTIP_PADDING
    wr32(click + ITEM_X, trackX)
    wr32(click + ITEM_Y, top)
    wr32(click + ITEM_WIDTH, P.track)
    wr32(click + ITEM_HEIGHT, P.height)
    wr16(click + ITEM_HIDDEN, 0)
    local resetX = trackX + P.track + TOOLTIP_PADDING
    wr32(reset + ITEM_X, resetX)
    wr32(reset + ITEM_Y, top + 2)
    wr32(reset + ITEM_WIDTH, resetWidth)
    wr32(reset + ITEM_HEIGHT, P.height - 4)
    wr16(reset + ITEM_HIDDEN, 0)
    C.markRect(rect, left - PANEL_GAP, top - PANEL_GAP, total + 2 * PANEL_GAP, P.height + 2 * PANEL_GAP)

    local offsetX = menuX - rd32(B.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(B.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left, offsetY + top, offsetX + left + total, offsetY + bottom, BOX_BLEND)
    local middle = offsetY + top + P.height // 2
    local l = offsetX + trackX
    roundedBox(G.pencil, l, middle - P.trackHeight // 2, l + P.track, middle + P.trackHeight // 2, BOX_BLEND)
    local lo, hi = range(tool)
    local filled = l + ((value - lo) * P.track) // math.max(1, hi - lo)
    colourBox(G.pencil, l, middle - 1, filled, middle + 1, white)
    colourBox(G.pencil, filled - 2, middle - P.trackHeight // 2 - 3, filled + 2, middle + P.trackHeight // 2 + 3, white)
    local rl, rt = offsetX + resetX, offsetY + top + 2
    roundedBox(G.pencil, rl, rt, rl + resetWidth, rt + P.height - 4, BOX_BLEND)
    if rd16(reset + ITEM_HOVERED) ~= 0 then
      roundedBox(G.pencil, rl, rt, rl + resetWidth, rt + P.height - 4, BOX_BLEND)
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    writeCString(buffer, label)
    shadowedText(G.textManager, buffer, offsetX + left + TOOLTIP_PADDING, middle - P.textRaise, ALIGN_LEFT,
      TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    writeCString(buffer, P.reset)
    shadowedText(G.textManager, buffer, offsetX + resetX + TOOLTIP_PADDING, middle - P.textRaise, ALIGN_LEFT,
      TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)
  end
  wr32(paint + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
  wr32(paint + ITEM_WIDTH, 0)
  wr32(paint + ITEM_HEIGHT, 0)
  wr32(paint + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(paint + ITEM_RENDER, C.luaPad(frame, "the wall height slider"))
  wr32(paint + ITEM_TEXT, 0)
  wr16(paint + ITEM_CONTROL, -1)
  wr16(paint + ITEM_HIDDEN, 0)
end

return true

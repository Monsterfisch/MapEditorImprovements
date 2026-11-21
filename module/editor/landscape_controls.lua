local layout = require("editor.layout")
local templates = layout.templates
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_MENU = layout.ITEM_MENU
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local K = layout.K
local C = layout.C
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local MAP_LAYER = layout.MAP_LAYER
local memory = require("editor.memory")
local rd32 = memory.rd32
local rd16 = memory.rd16
local wr32 = memory.wr32
local images = require("editor.images")
local loadPicture = images.loadPicture
local storePicture = images.storePicture
local patchJump = require("editor.menu_install").patchJump

-- The undo and redo buttons (items added as "undo" and "redo") in the screen's top left
-- corner, drawn on the map surface like the tooltips. Shown in the map editor only.
function C.undoButtons(G, added, guarded, actions)
  if G.blit == nil then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local blit = core.exposeCode(G.blit, 3, 0)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  if actions.pictures == nil then
    actions.pictures = {}
    for _, kind in ipairs({ "undo", "redo" }) do
      local normal, hover, off = loadPicture(kind), loadPicture(kind .. "_hover"), loadPicture(kind .. "_off")
      local width = math.max(normal.width, hover.width, off.width)
      local height = math.max(normal.height, hover.height, off.height)
      actions.pictures[kind] = { width = width, height = height, normal = storePicture(normal, width, height),
        hover = storePicture(hover, width, height), off = storePicture(off, width, height) }
    end
  end
  local B, left = K.UNDO_BUTTONS, K.UNDO_BUTTONS.left
  for _, kind in ipairs({ "undo", "redo" }) do
    local button, P, x = added[kind], actions.pictures[kind], left
    left = left + P.width + B.gap
    wr32(button + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(button + ITEM_Y, K.FAR_AWAY)
    wr32(button + ITEM_WIDTH, P.width)
    wr32(button + ITEM_HEIGHT, P.height)
    wr32(button + ITEM_ACTION, C.luaPad(actions[kind], "the " .. kind .. " button"))
    wr32(button + ITEM_RENDER, C.luaPad(function()
      if kind == "undo" then actions.tick() end
      local menu = rd32(button + ITEM_MENU)
      if menu == 0 or not actions.editor() then
        wr32(button + ITEM_Y, K.FAR_AWAY)
        return
      end
      wr32(button + ITEM_X, x - rd32(menu + MENU_X))
      wr32(button + ITEM_Y, B.top - rd32(menu + MENU_Y))
      local sx, sy = x + rd32(G.cameraX), B.top + rd32(G.cameraY)
      local picture = P.off
      if actions.available[kind]() then
        picture = rd16(button + ITEM_HOVERED) ~= 0 and P.hover or P.normal
      end
      local target = rd32(G.pencil + PENCIL_TARGET)
      wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
      roundedBox(G.pencil, sx - B.padding, sy - B.padding, sx + P.width - 1 + B.padding,
        sy + P.height - 1 + B.padding, BOX_BLEND)
      blit(picture, sx, sy)
      wr32(G.pencil + PENCIL_TARGET, target)
    end, "the " .. kind .. " button"))
    wr32(button + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(button + ITEM_TEXT, 0)
    guarded[#guarded + 1] = button
    guarded[#guarded + 1] = 0
  end
end

-- Herds of the brush size while the herd panel's check box is on.
local function patchHerds(self, G, data)
  for _, herd in pairs(G.herds) do
    patchJump(self, herd.site, K.HERD.size, core.allocateAssembly(templates.herdSize, {
      MASK = herd.mask, UNIT = herd.unit, BASE = herd.base, HERD_SYNC = data.herdSync, BRUSH = G.brush,
      BACK = herd.site + K.HERD.size,
    }))
  end
end

return {
  patchHerds = patchHerds,
}

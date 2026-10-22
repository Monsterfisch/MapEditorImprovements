--[[
  Map Editor Improvements

  Two changes to the map editor, each a setting of its own:

  1. Map counts. The landscape editor's buttons show how many of a thing the map has: the
     Animals category button the units and animals (UnitsState's unit count), the Rocks
     button the rocks (the rock id counter), the deer, lion, rabbit and camel buttons of the
     Animals menu the counters their update functions add to every tick. The Vegetation
     button's count (LandscapeState's organism count) goes after the button's description
     line while the mouse is on it. A red "i" button above the key button switches the
     numbers on and off.
  2. Always keep the menu up to date. The main loop redraws the menu only while
     GameCore.countdown (kept at 1 while the mouse is over the menu, counted down otherwise)
     is set; otherwise, in the landscape editor, it only redraws the minimap. The branch that
     makes that choice is pointed at a stub that also takes the full redraw in the map
     editor (GameMode2 == 1). The countdown itself is left alone, so nothing else that reads
     it changes.

  The counts use no code patches. The landscape editor's menu items are a static table handed
  to the Menu constructor by a CRT initializer (push table / mov ecx, menu / call Menu::Menu).
  A copy of that table with the "i" button added is built, its counted buttons' render
  functions replaced by wrappers that run the game's button renderer and then draw the number
  with the game's own number drawing (the one the siege engines' ammunition count uses), and
  the push pointed at the copy. If the menu has been built already, it is built again.

  Every address is found by pattern scan or read out of the instruction that uses it, so the
  module runs on Stronghold Crusader.exe and Stronghold_Crusader_Extreme.exe alike.
]]

local MODULE_NAME = "map-editor-improvements"

local DEFAULTS = {
  counts = { enabled = true, shown = true },
  menu = { always_update = true },
}

---------------------------------------------------------------------------------------
-- What the game's code and data look like where this module touches them
---------------------------------------------------------------------------------------

-- The landscape editor's item table, found by its key button (item 11: a group member placed
-- by user control 146, command 152). The bytes in between are its action, 0 until the Menu
-- constructor has copied the group's action in.
local AOB_ITEM_TABLE = "03 00 00 02 00 00 00 80 92 00 00 00 00 00 00 00 00 00 00 00 ? ? ? ? 98 00 00 00"
local KEY_BUTTON_ITEM = 11
local ITEM_COUNT = 99                    -- items before the end marker

-- MenuItem (0x50 bytes)
local MENU_ITEM_SIZE = 0x50
local ITEM_TYPE, ITEM_X, ITEM_Y = 0x00, 0x04, 0x08
local ITEM_ACTION, ITEM_PARAM, ITEM_RENDER = 0x14, 0x18, 0x1C
local ITEM_IMAGE, ITEM_RENDER_TYPE, ITEM_TEXT = 0x20, 0x24, 0x2C
local TYPE_CLICKABLE, TYPE_GROUP_START, TYPE_END = 3, 0x01000000, 0x66
local TYPE_GROUP_MEMBER_MASK, TYPE_GROUP_MEMBER = 0xFF000000, 0x02000000
local RENDER_IMAGE = 3

-- Item 9 is the line that shows the description of the button under the mouse.
local HOVER_TEXT_ITEM = 9
local HOVER_TEXT_POSITION = { 20, 422 }

-- The "i" button: interface_buttons.gm1 picture 28 (image table index 197), the game's own
-- red "i"; the renderer shows picture 29 while the mouse is on it. It goes in front of the
-- general buttons group, above the key button, and the description line moves right.
local INFO_IMAGE = 197
local INFO_BUTTON = { 22, 424 }
local INFO_ITEM_INDEX = 10
local HOVER_TEXT_MOVED_X = 56

-- Button commands (item param) and what they count.
local DEER, LION, RABBIT, CAMEL = 220, 221, 222, 223
local VEGETATION, ANIMALS, ROCKS = 234, 235, 237

-- MenuItemRenderFunction_MapEditorLandscaping_GeneralButtons: the hover flag and the item
-- position globals (width and height follow the position).
local BUTTON_RENDER = {
  hover = { 0x01, { 0x8B, 0x35 } },
  y = { 0xEF, { 0x8B, 0x15 } },
  x = { 0xF8, { 0xA1 } },
}
local BUTTON_WIDTH, BUTTON_HEIGHT = 0x08, 0x0C   -- from the x global

-- The description line's renderer: mov eax,[esp+4] / push eax / mov ecx, state / call / ret,
-- and in the function it calls, the store that moves the text onto the map layer.
local HOVER_RENDER_BYTES = { 0x8B, 0x44, 0x24, 0x04, 0x50, 0xB9 }
local HOVER_RENDER_STATE = 0x06
local HOVER_RENDER_CALL = 0x0A
local HOVER_TEXT_LAYER = { 0x68, { 0xC7, 0x05 } }  -- mov dword [textManager.layer], 1

-- The siege engine button's ammunition count: renderNumber2(count, x, y, 1, white, 0, 0x11,
-- 0, 0) on the text manager. The number style the counts copy.
local AOB_AMMO_COUNT = "6A 00 6A 00 6A 11 6A 00 99 68 FF FF FF 00 2B C2 6A 01 D1 F8 83 C7 53 57 "
  .. "03 C3 50 8B 04 B5 ? ? ? ? 50 B9 ? ? ? ? E8"
local AMMO_WIDTH = { -0x05, { 0xA1 } }   -- mov eax, [item width]
local AMMO_TEXT_MANAGER = { 0x23, { 0xB9 } }
local AMMO_RENDER_NUMBER = 0x28
local NUMBER_FONT, NUMBER_COLOUR = 0x11, 0xFFFFFF
local NUMBER_FROM_BOTTOM = 11

-- TextManager::renderInGameTextWithShadow, for the separator in the description line.
local AOB_SHADOWED_TEXT = "8B 44 24 20 8B 54 24 18 53 55 8B 6C 24 2C 56 57 55 50"
local TEXT_FONT, TEXT_COLOUR = 0x12, 0xB8EEFB   -- the description line's own style
local SEPARATOR = ": "

-- Menu: the item the mouse is on (the one whose description is shown).
local MENU_HOVERED_ITEM = 0x38

-- The counters.
local AOB_UNITS = "81 3D ? ? ? ? ? ? 00 00 7C 03 ? EB 01 ? 6A 1D E8"            -- unit limit test
local UNITS_OPERAND = 2
local AOB_TREES = "8D 43 2A 50 57 68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 8B 15"         -- debug overlay
local TREES_OPERAND = 0x16
local AOB_ROCKS = "89 35 ? ? ? ? 0F BF 80 ? ? ? ? 8B 0C 85 ? ? ? ? FF D1"          -- new rock
local ROCKS_OPERAND = 2
local AOB_DEER = "0F BF BE ? ? ? ? BA 01 00 00 00 01 15 ? ? ? ? 66 89 9E"          -- deer update
local DEER_OPERAND = 0x0E
local AOB_LIONS = "0F BF BE ? ? ? ? B9 01 00 00 00 01 0D ? ? ? ? 66 89 9E"         -- lion update
local LIONS_OPERAND = 0x0E
local AOB_RABBITS = "51 8B 15 ? ? ? ? 83 05 ? ? ? ? 01 53 56 8B F2"                -- rabbit update
local RABBITS_OPERAND = 0x09
local AOB_CAMELS = "83 05 ? ? ? ? 01 53 55 56 57 8B 3D"                            -- camel update
local CAMELS_OPERAND = 0x02

-- The main loop, where it picks between redrawing the menu and redrawing only the minimap:
-- cmp [GameCore.countdown], ebx / jne <full redraw> (ebx is 0 here).
local AOB_MENU_REDRAW = "83 3D ? ? ? ? 04 89 1D ? ? ? ? 0F 84 ? ? ? ? 39 1D ? ? ? ? 0F 85 ? ? ? ? 39 1D"
local MENU_REDRAW_SITE = 0x13
local MENU_REDRAW_SIZE = 12

-- GameMode2: 1 in the map editor.
local AOB_GAME_MODE = "83 3D ? ? ? ? 01 75 0D 6A 04 B9 ? ? ? ? E8 ? ? ? ? C3"
local GAME_MODE_OPERAND = 2

---------------------------------------------------------------------------------------
-- Injected code
---------------------------------------------------------------------------------------

-- Render function for a counted button: draw the button, then its number at the bottom.
local COUNTED_BUTTON = [[
mov eax,[esp+4]
push eax
call BUTTON_RENDER
add esp,4
cmp byte [SHOWN],0
je done
mov eax,[esp+4]
mov ecx,COUNTERS
scan_next:
mov edx,[ecx]
test edx,edx
je done
cmp edx,eax
je found_it
add ecx,8
jmp scan_next
found_it:
mov edx,[ecx+4]
push 0
push 0
push NUMBER_FONT
push 0
push NUMBER_COLOUR
push 1
mov eax,[ITEM_Y]
add eax,[ITEM_HEIGHT]
sub eax,NUMBER_FROM_BOTTOM
push eax
mov eax,[ITEM_WIDTH]
sar eax,1
add eax,[ITEM_X]
push eax
push dword [edx]
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
done:
ret
]]

-- Render function for the description line: draw it, and while the mouse is on the
-- Vegetation button add ": <count>" behind the text. The game's type 1 line is drawn on the
-- map layer at the item position plus the camera offset, which it leaves in the position
-- globals; the text manager's cursor is left at the end of the text.
local DESCRIPTION_LINE = [[
mov eax,[esp+4]
push eax
call HOVER_RENDER
add esp,4
cmp byte [SHOWN],0
je done
cmp dword [HOVER_STATE],1
jne done
cmp dword [MENU+MENU_HOVERED_ITEM],VEGETATION_ITEM
jne done
mov dword [TEXT_LAYER],1
push 0
push 1
push TEXT_FONT
push 0
push TEXT_COLOUR
push 0
push dword [ITEM_Y]
push dword [ITEM_X]
push SEPARATOR
mov ecx,TEXT_MANAGER
call SHADOWED_TEXT
push 0
push 1
push TEXT_FONT
push 0
push TEXT_COLOUR
push 0
push dword [ITEM_Y]
push dword [ITEM_X]
push dword [TREES]
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
mov dword [TEXT_LAYER],0
done:
ret
]]

-- Action of the "i" button.
local TOGGLE = [[
xor byte [SHOWN],1
ret
]]

-- Replaces cmp [countdown], ebx / jne FULL in the main loop.
local MENU_REDRAW = [[
cmp dword [COUNTDOWN],0
jne full
cmp dword [GAME_MODE],1
jne partial
full:
jmp FULL
partial:
jmp PARTIAL
]]

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local rd32, rd8 = core.readInteger, core.readByte
local wr32 = core.writeInteger

local function scan(pattern, purpose)
  local ok, address = pcall(core.AOBScan, pattern)
  if not ok or address == nil then
    error(MODULE_NAME .. ": could not find " .. purpose)
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

---------------------------------------------------------------------------------------
-- Map counts
---------------------------------------------------------------------------------------

local function resolveCounts()
  local G = {}
  G.table = scan(AOB_ITEM_TABLE, "the landscape editor's menu") - KEY_BUTTON_ITEM * MENU_ITEM_SIZE
  local index = 0
  while rd32(item(G.table, index, ITEM_TYPE)) ~= TYPE_END do
    index = index + 1
    if index > ITEM_COUNT then break end
  end
  if index ~= ITEM_COUNT then
    error(MODULE_NAME .. ": the landscape editor's menu is not the one this module knows")
  end
  if rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_TYPE)) ~= TYPE_CLICKABLE
      or rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_X)) ~= HOVER_TEXT_POSITION[1]
      or rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_Y)) ~= HOVER_TEXT_POSITION[2] then
    error(MODULE_NAME .. ": the landscape editor's description line is not where the module expects it")
  end

  G.site = scan("68 " .. bytesOf(G.table) .. " B9 ? ? ? ? E8", "the landscape editor menu's constructor")
  G.menu = rd32(G.site + 6)
  G.constructor = readCallTarget(G.site, 10, "the Menu constructor")

  -- The counted buttons, and the render function their groups give them.
  G.buttons = {}
  local groupRender = nil
  for i = 0, ITEM_COUNT - 1 do
    local itemType = rd32(item(G.table, i, ITEM_TYPE))
    if itemType == TYPE_GROUP_START then
      groupRender = rd32(item(G.table, i, ITEM_RENDER))
    elseif (itemType & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
      local param = rd32(item(G.table, i, ITEM_PARAM))
      if G.buttons[param] == nil then
        local render = rd32(item(G.table, i, ITEM_RENDER))
        if render == 0 then render = groupRender end
        G.buttons[param] = { index = i, render = render }
      end
    end
  end
  for _, param in ipairs({ DEER, LION, RABBIT, CAMEL, VEGETATION, ANIMALS, ROCKS }) do
    if G.buttons[param] == nil then
      error(string.format("%s: button %d is missing from the landscape editor's menu", MODULE_NAME, param))
    end
  end
  G.buttonRender = G.buttons[ANIMALS].render
  for _, param in ipairs({ DEER, LION, RABBIT, CAMEL, ROCKS }) do
    if G.buttons[param].render ~= G.buttonRender then
      error(MODULE_NAME .. ": the landscape editor's buttons are drawn by an unknown function")
    end
  end
  G.hover = readOperand(G.buttonRender, BUTTON_RENDER.hover, "the editor button renderer")
  G.itemY = readOperand(G.buttonRender, BUTTON_RENDER.y, "the editor button renderer")
  G.itemX = readOperand(G.buttonRender, BUTTON_RENDER.x, "the editor button renderer")

  G.hoverRender = rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_RENDER))
  expectBytes(G.hoverRender, HOVER_RENDER_BYTES, "the description line renderer")
  G.hoverState = rd32(G.hoverRender + HOVER_RENDER_STATE)
  local describe = readCallTarget(G.hoverRender, HOVER_RENDER_CALL, "the description line renderer")
  G.textLayer = readOperand(describe, HOVER_TEXT_LAYER, "the description line renderer")

  local ammo = scan(AOB_AMMO_COUNT, "the ammunition count")
  if readOperand(ammo, AMMO_WIDTH, "the ammunition count") ~= G.itemX + BUTTON_WIDTH then
    error(MODULE_NAME .. ": the item position globals are not laid out as the module expects")
  end
  G.textManager = readOperand(ammo, AMMO_TEXT_MANAGER, "the ammunition count")
  G.renderNumber = readCallTarget(ammo, AMMO_RENDER_NUMBER, "the number drawing")
  G.shadowedText = scan(AOB_SHADOWED_TEXT, "the text drawing")

  G.counters = {
    [ANIMALS] = rd32(scan(AOB_UNITS, "the unit count") + UNITS_OPERAND),
    [ROCKS] = rd32(scan(AOB_ROCKS, "the rock count") + ROCKS_OPERAND),
    [DEER] = rd32(scan(AOB_DEER, "the deer count") + DEER_OPERAND),
    [LION] = rd32(scan(AOB_LIONS, "the lion count") + LIONS_OPERAND),
    [RABBIT] = rd32(scan(AOB_RABBITS, "the rabbit count") + RABBITS_OPERAND),
    [CAMEL] = rd32(scan(AOB_CAMELS, "the camel count") + CAMELS_OPERAND),
  }
  G.trees = rd32(scan(AOB_TREES, "the tree count") + TREES_OPERAND)
  return G
end

-- Copies the item table with the "i" button inserted, and points the counted buttons and
-- the description line at the wrappers.
local function buildTable(G, shown)
  local newTable = core.allocate((ITEM_COUNT + 2) * MENU_ITEM_SIZE, true)
  core.writeBytes(newTable, core.readBytes(G.table, INFO_ITEM_INDEX * MENU_ITEM_SIZE))
  core.writeBytes(item(newTable, INFO_ITEM_INDEX + 1),
    core.readBytes(item(G.table, INFO_ITEM_INDEX), (ITEM_COUNT + 1 - INFO_ITEM_INDEX) * MENU_ITEM_SIZE))
  local function moved(index)
    if index < INFO_ITEM_INDEX then return index end
    return index + 1
  end

  local shownFlag = core.allocate(4, true)
  wr32(shownFlag, shown and 1 or 0)

  local order = { ANIMALS, ROCKS, DEER, LION, RABBIT, CAMEL }
  local counters = core.allocate((#order + 1) * 8, true)
  for i, param in ipairs(order) do
    wr32(counters + (i - 1) * 8, param)
    wr32(counters + (i - 1) * 8 + 4, G.counters[param])
  end
  wr32(counters + #order * 8, 0)

  local counted = core.allocateAssembly(COUNTED_BUTTON, {
    BUTTON_RENDER = G.buttonRender, SHOWN = shownFlag, COUNTERS = counters,
    NUMBER_FONT = NUMBER_FONT, NUMBER_COLOUR = NUMBER_COLOUR, NUMBER_FROM_BOTTOM = NUMBER_FROM_BOTTOM,
    ITEM_X = G.itemX, ITEM_Y = G.itemY, ITEM_WIDTH = G.itemX + BUTTON_WIDTH,
    ITEM_HEIGHT = G.itemX + BUTTON_HEIGHT, TEXT_MANAGER = G.textManager, RENDER_NUMBER = G.renderNumber,
  })
  for _, param in ipairs(order) do
    wr32(item(newTable, moved(G.buttons[param].index), ITEM_RENDER), counted)
  end

  local description = core.allocateAssembly(DESCRIPTION_LINE, {
    HOVER_RENDER = G.hoverRender, SHOWN = shownFlag, HOVER_STATE = G.hoverState, MENU = G.menu,
    MENU_HOVERED_ITEM = MENU_HOVERED_ITEM,
    VEGETATION_ITEM = item(newTable, moved(G.buttons[VEGETATION].index)),
    TEXT_LAYER = G.textLayer, TEXT_FONT = TEXT_FONT, TEXT_COLOUR = TEXT_COLOUR,
    ITEM_X = G.itemX, ITEM_Y = G.itemY, SEPARATOR = core.registerString(SEPARATOR),
    TEXT_MANAGER = G.textManager, SHADOWED_TEXT = G.shadowedText, RENDER_NUMBER = G.renderNumber,
    TREES = G.trees,
  })
  wr32(item(newTable, HOVER_TEXT_ITEM, ITEM_RENDER), description)
  wr32(item(newTable, HOVER_TEXT_ITEM, ITEM_X), HOVER_TEXT_MOVED_X)

  local info = item(newTable, INFO_ITEM_INDEX)
  wr32(info + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(info + ITEM_X, INFO_BUTTON[1])
  wr32(info + ITEM_Y, INFO_BUTTON[2])
  wr32(info + ITEM_ACTION, core.allocateAssembly(TOGGLE, { SHOWN = shownFlag }))
  wr32(info + ITEM_RENDER, G.imageButton)
  wr32(info + ITEM_IMAGE, INFO_IMAGE)
  wr32(info + ITEM_RENDER_TYPE, RENDER_IMAGE)
  wr32(info + ITEM_TEXT, 0)              -- no description, the usual hover sound

  return newTable, shownFlag
end

-- Points the menu's constructor at the new table. Should the menu already have been built,
-- it is built again the same way.
local function installTable(G, newTable)
  core.writeCodeInteger(G.site + 1, newTable)
  local construct = core.exposeCode(G.constructor, 2, 1)
  local function ensure()
    if rd32(G.menu) == G.table then
      construct(G.menu, newTable)
    end
  end
  ensure()
  hooks.registerHookCallback("afterInit", ensure)
end

local AOB_IMAGE_BUTTON = "56 33 F6 39 ? ? ? ? ? 57 74 05"

local function enableCounts(self, shown)
  local G = resolveCounts()
  G.imageButton = scan(AOB_IMAGE_BUTTON, "the image button renderer")
  local newTable, shownFlag = buildTable(G, shown)
  installTable(G, newTable)
  self.shownFlag = shownFlag
  log(INFO, string.format("%s: map counts on (menu 0x%X, items 0x%X -> 0x%X)", MODULE_NAME, G.menu,
    G.table, newTable))
end

---------------------------------------------------------------------------------------
-- Always keep the menu up to date
---------------------------------------------------------------------------------------

local function enableRedraw(self)
  local site = scan(AOB_MENU_REDRAW, "the main loop's menu redraw") + MENU_REDRAW_SITE
  expectBytes(site, { 0x39, 0x1D }, "the menu redraw test")
  expectBytes(site + 6, { 0x0F, 0x85 }, "the menu redraw test")
  local stub = core.allocateAssembly(MENU_REDRAW, {
    COUNTDOWN = rd32(site + 2),
    GAME_MODE = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND),
    FULL = site + MENU_REDRAW_SIZE + rd32(site + 8),
    PARTIAL = site + MENU_REDRAW_SIZE,
  })
  self.saved = { address = site, bytes = core.readBytes(site, MENU_REDRAW_SIZE) }
  core.writeCode(site, { 0xE9, core.itob(core.getRelativeAddress(site, stub, -5)),
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90 })
  log(INFO, string.format("%s: menu always kept up to date (0x%X)", MODULE_NAME, site))
end

---------------------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------------------

local function enable(self, config)
  config = config or {}
  if setting(config, "counts", "enabled") == true then
    local ok, problem = pcall(enableCounts, self, setting(config, "counts", "shown") == true)
    if not ok then log(WARNING, tostring(problem) .. "; the map counts stay off") end
  end
  if setting(config, "menu", "always_update") == true then
    local ok, problem = pcall(enableRedraw, self)
    if not ok then log(WARNING, tostring(problem) .. "; the menu is redrawn as usual") end
  end
end

local function disable(self, config)
  if self.saved ~= nil then
    core.writeCode(self.saved.address, self.saved.bytes)
    self.saved = nil
  end
  if self.shownFlag ~= nil then
    wr32(self.shownFlag, 0)
  end
end

return {
  enable = enable,
  disable = disable,
}

--[[
  Map Editor Improvements

  Two changes to the map editor, each a setting of its own:

  1. Map counts. In the landscape editor:
     - Pointing at the Animals, Vegetation or Rocks category button shows a tooltip with how
       many the map has against the game's limit: units and animals (UnitsState's unit count
       against the limit the editor tests before placing more), herds and troops (used group
       slots), trees and shrubs (used tree slots) and rocks (used rock slots).
     - The deer, lion, rabbit and camel buttons of the Animals menu show the counters their
       update functions add to every tick; the plant buttons of the Vegetation menu show how
       many trees or shrubs of their type stand on the map.
     A red "i" button above the key button switches all of it on and off.
  2. Always keep the menu up to date. The main loop redraws the menu only while
     GameCore.countdown (kept at 1 while the mouse is over the menu, counted down otherwise)
     is set; otherwise, in the landscape editor, it only redraws the minimap. The branch that
     makes that choice is pointed at a stub that also takes the full redraw in the map
     editor (GameMode2 == 1). The countdown itself is left alone, so nothing else that reads
     it changes.

  The counts use no code patches. The landscape editor's menu items are a static table handed
  to the Menu constructor by a CRT initializer (push table / mov ecx, menu / call Menu::Menu).
  A copy of that table is built with items added: the "i" button; at the end of the part of
  the menu that is always shown, an invisible item that draws the tooltip on top of
  everything before it; and at the end of the Animals and Vegetation tabs an invisible item
  that draws the numbers of the tab's buttons, after all of them, so no neighbouring picture
  covers a number. The numbers use the game's own number style (the one the siege engines'
  ammunition count uses). The push is pointed at the copy, and if the menu has been built
  already, it is built again.

  Slots in use are counted once a frame, in assembly, while the counts are shown: the tree,
  rock and group arrays are walked the way the game's own "find a free slot" functions walk
  them, whose code also gives the slot counts and sizes. The tooltip itself is drawn from lua,
  and only while the mouse is on one of the three category buttons.

  The description line and the "i" button lie above the panel, over the map. The game draws
  there on the map surface, at the item position plus the camera offset (see its description
  line renderer), and the "i" is drawn the same way.

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
local ITEM_TYPE, ITEM_X, ITEM_Y, ITEM_WIDTH, ITEM_HEIGHT = 0x00, 0x04, 0x08, 0x0C, 0x10
local ITEM_ACTION, ITEM_PARAM, ITEM_RENDER = 0x14, 0x18, 0x1C
local ITEM_IMAGE, ITEM_RENDER_TYPE, ITEM_TEXT = 0x20, 0x24, 0x2C
local TYPE_CLICKABLE, TYPE_GROUP_START, TYPE_BLOCK, TYPE_END = 3, 0x01000000, 0x64, 0x66
local TYPE_GROUP_MEMBER_MASK, TYPE_GROUP_MEMBER = 0xFF000000, 0x02000000
local RENDER_SIMPLE, RENDER_IMAGE = 1, 3
local ITEM_HOVERED, ITEM_MENU = 0x32, 0x4C
local MENU_X, MENU_Y = 0x04, 0x08        -- the menu's position on screen
local MENU_SCROLL = 0x14                 -- subtracted from x when drawing

-- Item 9 is the line that shows the description of the button under the mouse.
local HOVER_TEXT_ITEM = 9
local HOVER_TEXT_POSITION = { 20, 422 }

-- The "i" button: interface_buttons.gm1 picture 28 (image table index 197), the game's own
-- red "i"; the renderer shows picture 29 while the mouse is on it. It goes in front of the
-- general buttons group, above the key button, and the description line moves right.
local INFO_IMAGE = 197
local INFO_BUTTON = { 22, 424 }
local INFO_BEFORE_ITEM = 10
local HOVER_TEXT_MOVED_X = 56

-- Button commands (item param).
local DEER, LION, RABBIT, CAMEL = 220, 221, 222, 223
local VEGETATION, ANIMALS, ROCKS = 234, 235, 237

-- MenuItemRenderFunction_MapEditorLandscaping_GeneralButtons: the item position globals
-- (width follows the position) and the store that switches the texture renderer to the
-- screen (0) before drawing; 1 draws on the map surface.
local BUTTON_RENDER = {
  y = { 0xEF, { 0x8B, 0x15 } },
  x = { 0xF8, { 0xA1 } },
  drawMode = { 0xC8, { 0xC7, 0x05 } },
}
local BUTTON_WIDTH = 0x08                -- from the x global

-- The description line's renderer: mov eax,[esp+4] / push eax / mov ecx, state / call / ret,
-- and in the function it calls, the camera offset it adds for the map layer.
local HOVER_RENDER_BYTES = { 0x8B, 0x44, 0x24, 0x04, 0x50, 0xB9 }
local HOVER_RENDER_CALL = 0x0A
local CAMERA_X = { 0x5C, { 0x03, 0x0D } }   -- add ecx, [camera x]
local CAMERA_Y = { 0x62, { 0x03, 0x3D } }   -- add edi, [camera y]

-- The siege engine button's ammunition count: renderNumber2(count, x, y, 1, white, 0, 0x11,
-- 0, 0) on the text manager. The number style the counts copy.
local AOB_AMMO_COUNT = "6A 00 6A 00 6A 11 6A 00 99 68 FF FF FF 00 2B C2 6A 01 D1 F8 83 C7 53 57 "
  .. "03 C3 50 8B 04 B5 ? ? ? ? 50 B9 ? ? ? ? E8"
local AMMO_WIDTH = { -0x05, { 0xA1 } }   -- mov eax, [item width]
local AMMO_TEXT_MANAGER = { 0x23, { 0xB9 } }
local AMMO_RENDER_NUMBER = 0x28
local NUMBER_FONT, NUMBER_COLOUR = 0x11, 0xFFFFFF
local NUMBER_FROM_BOTTOM = 11

-- The Save dialog's file name box renderer: the pencil and its translucent rounded box, the
-- text width, the shadowed text. The tooltip is drawn with these.
local AOB_NAME_BOX = "A1 ? ? ? ? 8B 0D ? ? ? ? 8B 15 ? ? ? ? 56 57 6A 05 03 C8 51 8B 0D ? ? ? ? 03 "
  .. "D1 52 50 51 B9 ? ? ? ?"
local NAME_BOX = {
  pencil = { 0x23, { 0xB9 } },
  roundedBox = 0x28,
  widthUntilCursor = 0x32,
  textManager = { 0x9C, { 0xB9 } },
  shadowedText = 0xA1,
}
local WIDTH_UNTIL_CURSOR_CALL = 0x22     -- inside it: the text width up to a length
local PENCIL_TARGET = 0x0C               -- 0 screen, 1 map surface
local BOX_BLEND = 5

-- handleMenuItems, where it asks whether the mouse is over an item: the mouse and its
-- "is the mouse in this box" test. (The ui module patches the function's start.)
local AOB_MENU_ITEM = "8B 56 10 8B 46 4C 8B 4E 0C 52 8B 50 08 03 56 08 8B 40 04 03 46 04 51 52 50 B9"
local MENU_ITEM_MOUSE = { 0x19, { 0xB9 } }
local MENU_ITEM_IS_INSIDE = 0x1E

-- The tooltip.
local TOOLTIP_FONT, TOOLTIP_COLOUR = 0x12, 0xB8EEFB  -- the description line's own style
local TOOLTIP_LINE, TOOLTIP_PADDING, TOOLTIP_GAP = 16, 6, 4
local ALIGN_RIGHT = -1                   -- the text ends at x

-- The free slot searches. Slots run from 1 to the last one they test.
-- LandscapeState::createTree: the first slot's "in use" word, the last slot, the slot size.
local AOB_NEW_TREE = "51 BA 01 00 00 00 55 89 4C 24 04 8B EA 8D 81 ? ? ? ? 66 83 38 00 74 17 81 FD ? ? ? ?"
local NEW_TREE = { first = 0x0F, last = 0x1B, size = { 0x23, { 0x05 } } }
local TREE_TYPE_FROM_IN_USE = 0x02       -- the tree type word follows the "in use" word
local TREE_TYPES = 32
-- LandscapeState::createRock
local AOB_NEW_ROCK = "BA 01 00 00 00 56 8B F2 8D 81 ? ? ? ? 8B FF 66 83 38 00 74 19 81 FE ? ? ? ?"
local NEW_ROCK = { first = 0x0A, last = 0x18, size = { 0x24, { 0x83, 0xC0 } } }
-- TribesState::findFreeTribe: the slot size, the "in use" word, the slot after the last one.
local AOB_NEW_GROUP = "53 55 56 B8 01 00 00 00 57 8B E9 A3 ? ? ? ? 33 DB 8B C8 69 C9 ? ? ? ? 66 39 5C 29 ? "
  .. "74 ? 83 C0 01 3D ? ? ? ?"
local NEW_GROUP = { size = 0x16, inUse = 0x1E, limit = 0x25 }
-- A caller of it, for the TribesState object.
local AOB_GROUPS = "69 FF ? ? 00 00 EB 04 8B 6C 24 10 6A 00 55 B9 ? ? ? ? E8"
local GROUPS_OBJECT, GROUPS_CALL = 0x10, 0x14
-- The tree creator's caller passes LandscapeState; the organism counter lies at +8 of it.
local AOB_TREES = "8D 43 2A 50 57 68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 8B 15"   -- debug overlay
local TREES_OPERAND = 0x16
local LANDSCAPE_ORGANISMS = 0x08
-- LandscapeState::commandToTreeType(command): which tree type a plant button places.
local AOB_TREE_TYPE = "8B 44 24 04 83 C0 D8 83 F8 74 0F 87"

-- The unit count, and the limit the editor tests it against before placing more.
local AOB_UNITS = "81 3D ? ? ? ? ? ? 00 00 7C 03 ? EB 01 ? 6A 1D E8"
local UNITS_OPERAND, UNITS_LIMIT = 2, 6

-- The animal counters, from the animals' update functions.
local AOB_DEER = "0F BF BE ? ? ? ? BA 01 00 00 00 01 15 ? ? ? ? 66 89 9E"
local DEER_OPERAND = 0x0E
local AOB_LIONS = "0F BF BE ? ? ? ? B9 01 00 00 00 01 0D ? ? ? ? 66 89 9E"
local LIONS_OPERAND = 0x0E
local AOB_RABBITS = "51 8B 15 ? ? ? ? 83 05 ? ? ? ? 01 53 56 8B F2"
local RABBITS_OPERAND = 0x09
local AOB_CAMELS = "83 05 ? ? ? ? 01 53 55 56 57 8B 3D"
local CAMELS_OPERAND = 0x02

-- The main loop, where it picks between redrawing the menu and redrawing only the minimap:
-- cmp [GameCore.countdown], ebx / jne <full redraw> (ebx is 0 here).
local AOB_MENU_REDRAW = "83 3D ? ? ? ? 04 89 1D ? ? ? ? 0F 84 ? ? ? ? 39 1D ? ? ? ? 0F 85 ? ? ? ? 39 1D"
local MENU_REDRAW_SITE = 0x13
local MENU_REDRAW_SIZE = 12

-- GameMode2: 1 in the map editor.
local AOB_GAME_MODE = "83 3D ? ? ? ? 01 75 0D 6A 04 B9 ? ? ? ? E8 ? ? ? ? C3"
local GAME_MODE_OPERAND = 2

local AOB_IMAGE_BUTTON = "56 33 F6 39 ? ? ? ? ? 57 74 05"

---------------------------------------------------------------------------------------
-- Injected code
---------------------------------------------------------------------------------------

-- Counts the used tree slots (also by tree type), rock slots and group slots.
local COUNT_SLOTS = [[
push esi
push edi
mov edi,TYPE_COUNTS
mov ecx,TREE_TYPES
xor eax,eax
rep stosd
xor edx,edx
mov esi,FIRST_TREE
mov ecx,TREE_SLOTS
tree_loop:
cmp word [esi],0
je tree_next
inc edx
movzx eax,word [esi+TREE_TYPE_FROM_IN_USE]
and eax,TREE_TYPES-1
inc dword [TYPE_COUNTS+eax*4]
tree_next:
add esi,TREE_SIZE
dec ecx
jnz tree_loop
mov [TOTALS],edx
xor edx,edx
mov esi,FIRST_ROCK
mov ecx,ROCK_SLOTS
rock_loop:
cmp word [esi],0
je rock_next
inc edx
rock_next:
add esi,ROCK_SIZE
dec ecx
jnz rock_loop
mov [TOTALS+4],edx
xor edx,edx
mov esi,FIRST_GROUP
mov ecx,GROUP_SLOTS
group_loop:
cmp word [esi],0
je group_next
inc edx
group_next:
add esi,GROUP_SIZE
dec ecx
jnz group_loop
mov [TOTALS+8],edx
pop edi
pop esi
ret
]]

-- Render function for the description line, the first item drawn every frame: count, then
-- draw the line as before.
local DESCRIPTION_LINE = [[
cmp byte [SHOWN],0
je skip
call COUNT_SLOTS
skip:
jmp HOVER_RENDER
]]

-- Render function for the last item of a tab: the numbers of the tab's counted buttons, drawn
-- after every button of the tab so no neighbouring picture covers them. The item's param is
-- a list of (button item, counter) pairs ending in 0. A button's place on screen is worked
-- out the way the menu's render pass does it (menu position - scroll + item position); its
-- size is what the render pass took from the picture.
local TAB_NUMBERS = [[
cmp byte [SHOWN],0
je done
push esi
mov esi,[esp+8]
next_button:
mov eax,[esi]
test eax,eax
je finished
mov ecx,[eax+ITEM_MENU]
mov edx,[ecx+MENU_X]
sub edx,[ecx+MENU_SCROLL]
add edx,[eax+ITEM_X]
mov ecx,[ecx+MENU_Y]
add ecx,[eax+ITEM_Y]
add ecx,[eax+ITEM_HEIGHT]
sub ecx,NUMBER_FROM_BOTTOM
mov eax,[eax+ITEM_WIDTH]
sar eax,1
add edx,eax
mov eax,[esi+4]
push 0
push 0
push NUMBER_FONT
push 0
push NUMBER_COLOUR
push 1
push ecx
push edx
push dword [eax]
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
add esi,8
jmp next_button
finished:
pop esi
done:
ret
]]

-- Render function for the "i": like the description line, on the map surface at the item
-- position plus the camera offset.
local INFO_BUTTON_RENDER = [[
mov eax,[CAMERA_X]
add [ITEM_X],eax
mov eax,[CAMERA_Y]
add [ITEM_Y],eax
mov dword [DRAW_MODE],1
jmp IMAGE_BUTTON
]]

-- Render function for the tooltip item: hand over to lua while the mouse is on a category
-- button.
local TOOLTIP = [[
cmp byte [SHOWN],0
je quiet
cmp word [ANIMALS_HOVER],0
jne show
cmp word [VEGETATION_HOVER],0
jne show
cmp word [ROCKS_HOVER],0
je quiet
show:
jmp PAD
quiet:
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

local rd32, rd16, rd8 = core.readInteger, core.readSmallInteger, core.readByte
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

local function writeCString(address, text)
  local bytes = { string.byte(text, 1, -1) }
  bytes[#bytes + 1] = 0
  core.writeBytes(address, bytes)
end

---------------------------------------------------------------------------------------
-- Map counts: finding things
---------------------------------------------------------------------------------------

local function resolveMenu(G)
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

  -- The buttons by command, the render function their groups give them, the block each one
  -- is in (the tab id of the 0x64 marker before it, 0 for the part that is always shown), and
  -- where the always shown part ends.
  G.buttons, G.blockEnd = {}, {}
  local groupRender, block = nil, 0
  for i = 0, ITEM_COUNT - 1 do
    local itemType = rd32(item(G.table, i, ITEM_TYPE))
    if itemType == TYPE_BLOCK then
      if block == 0 then G.firstBlock = i else G.blockEnd[block] = G.blockEnd[block] or i end
      block = rd32(item(G.table, i, ITEM_PARAM))
    elseif itemType == TYPE_GROUP_START then
      groupRender = rd32(item(G.table, i, ITEM_RENDER))
    elseif (itemType & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
      local param = rd32(item(G.table, i, ITEM_PARAM))
      if G.buttons[param] == nil then
        local render = rd32(item(G.table, i, ITEM_RENDER))
        if render == 0 then render = groupRender end
        G.buttons[param] = { index = i, render = render, block = block }
      end
    end
  end
  if block ~= 0 then G.blockEnd[block] = G.blockEnd[block] or ITEM_COUNT end
  if G.firstBlock == nil or G.blockEnd[ANIMALS] == nil or G.blockEnd[VEGETATION] == nil then
    error(MODULE_NAME .. ": the landscape editor's menu has not got the tabs this module knows")
  end
  for _, param in ipairs({ DEER, LION, RABBIT, CAMEL, VEGETATION, ANIMALS, ROCKS }) do
    if G.buttons[param] == nil then
      error(string.format("%s: button %d is missing from the landscape editor's menu", MODULE_NAME, param))
    end
  end
  G.plants = {}
  for param, button in pairs(G.buttons) do
    if button.block == VEGETATION then G.plants[#G.plants + 1] = param end
  end
  if #G.plants == 0 then
    error(MODULE_NAME .. ": the Vegetation menu has no plant buttons")
  end

  G.buttonRender = G.buttons[DEER].render
  for _, param in ipairs({ LION, RABBIT, CAMEL, table.unpack(G.plants) }) do
    if G.buttons[param].render ~= G.buttonRender then
      error(MODULE_NAME .. ": the landscape editor's buttons are drawn by an unknown function")
    end
  end
  G.itemY = readOperand(G.buttonRender, BUTTON_RENDER.y, "the editor button renderer")
  G.itemX = readOperand(G.buttonRender, BUTTON_RENDER.x, "the editor button renderer")
  G.drawMode = readOperand(G.buttonRender, BUTTON_RENDER.drawMode, "the editor button renderer")

  G.hoverRender = rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_RENDER))
  expectBytes(G.hoverRender, HOVER_RENDER_BYTES, "the description line renderer")
  local describe = readCallTarget(G.hoverRender, HOVER_RENDER_CALL, "the description line renderer")
  G.cameraX = readOperand(describe, CAMERA_X, "the description line renderer")
  G.cameraY = readOperand(describe, CAMERA_Y, "the description line renderer")
  G.imageButton = scan(AOB_IMAGE_BUTTON, "the image button renderer")
end

local function resolveDrawing(G)
  local ammo = scan(AOB_AMMO_COUNT, "the ammunition count")
  if readOperand(ammo, AMMO_WIDTH, "the ammunition count") ~= G.itemX + BUTTON_WIDTH then
    error(MODULE_NAME .. ": the item position globals are not laid out as the module expects")
  end
  G.textManager = readOperand(ammo, AMMO_TEXT_MANAGER, "the ammunition count")
  G.renderNumber = readCallTarget(ammo, AMMO_RENDER_NUMBER, "the number drawing")

  local nameBox = scan(AOB_NAME_BOX, "the Save dialog's name box")
  G.pencil = readOperand(nameBox, NAME_BOX.pencil, "the name box")
  G.roundedBox = readCallTarget(nameBox, NAME_BOX.roundedBox, "the name box background")
  local untilCursor = readCallTarget(nameBox, NAME_BOX.widthUntilCursor, "the name box cursor")
  G.textWidth = readCallTarget(untilCursor, WIDTH_UNTIL_CURSOR_CALL, "the text width")
  if readOperand(nameBox, NAME_BOX.textManager, "the name box") ~= G.textManager then
    error(MODULE_NAME .. ": the text manager is not the one this module knows")
  end
  G.shadowedText = readCallTarget(nameBox, NAME_BOX.shadowedText, "the text drawing")

  local menuItem = scan(AOB_MENU_ITEM, "the menu's mouse test")
  G.mouse = readOperand(menuItem, MENU_ITEM_MOUSE, "the menu's mouse test")
  G.isMouseInside = readCallTarget(menuItem, MENU_ITEM_IS_INSIDE, "the menu's mouse test")
end

local function resolveCounters(G)
  local unitTest = scan(AOB_UNITS, "the unit count")
  G.units = rd32(unitTest + UNITS_OPERAND)
  G.unitLimit = rd32(unitTest + UNITS_LIMIT)
  G.animals = {
    [DEER] = rd32(scan(AOB_DEER, "the deer count") + DEER_OPERAND),
    [LION] = rd32(scan(AOB_LIONS, "the lion count") + LIONS_OPERAND),
    [RABBIT] = rd32(scan(AOB_RABBITS, "the rabbit count") + RABBITS_OPERAND),
    [CAMEL] = rd32(scan(AOB_CAMELS, "the camel count") + CAMELS_OPERAND),
  }

  local landscape = rd32(scan(AOB_TREES, "the landscape") + TREES_OPERAND) - LANDSCAPE_ORGANISMS
  local newTree = scan(AOB_NEW_TREE, "the tree slot search")
  G.firstTree = landscape + rd32(newTree + NEW_TREE.first)
  G.treeSlots = rd32(newTree + NEW_TREE.last)
  G.treeSize = readOperand(newTree, NEW_TREE.size, "the tree slot search")
  local newRock = scan(AOB_NEW_ROCK, "the rock slot search")
  G.firstRock = landscape + rd32(newRock + NEW_ROCK.first)
  G.rockSlots = rd32(newRock + NEW_ROCK.last)
  expectBytes(newRock + NEW_ROCK.size[1], NEW_ROCK.size[2], "the rock slot search")
  G.rockSize = rd8(newRock + NEW_ROCK.size[1] + 2) & 0xFF

  local newGroup = scan(AOB_NEW_GROUP, "the group slot search")
  local groupsCall = scan(AOB_GROUPS, "the group array")
  if readCallTarget(groupsCall, GROUPS_CALL, "the group array") ~= newGroup then
    error(MODULE_NAME .. ": the group array is not the one this module knows")
  end
  G.groupSize = rd32(newGroup + NEW_GROUP.size)
  G.firstGroup = rd32(groupsCall + GROUPS_OBJECT) + G.groupSize + (rd8(newGroup + NEW_GROUP.inUse) & 0xFF)
  G.groupSlots = rd32(newGroup + NEW_GROUP.limit) - 1

  -- Which tree type each plant button places, asked of the game itself.
  local treeType = core.exposeCode(scan(AOB_TREE_TYPE, "the plant types"), 2, 1)
  G.plantTypes = {}
  for _, param in ipairs(G.plants) do
    G.plantTypes[param] = treeType(landscape, param) & (TREE_TYPES - 1)
  end
end

---------------------------------------------------------------------------------------
-- Map counts: the tooltip
---------------------------------------------------------------------------------------

local function makeTooltip(G, newTable, moved, data)
  local isMouseInside = core.exposeCode(G.isMouseInside, 5, 1)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local lineBuffers = { core.allocate(96, true), core.allocate(96, true) }

  local function lines(param)
    if param == ANIMALS then
      return {
        { "Animals and units", rd32(G.units), G.unitLimit },
        { "Herds and troops", rd32(data.totals + 8), G.groupSlots },
      }
    elseif param == VEGETATION then
      return { { "Trees and shrubs", rd32(data.totals), G.treeSlots } }
    end
    return { { "Rocks", rd32(data.totals + 4), G.rockSlots } }
  end

  -- The tooltip sits to the left of the button. Its text is right-aligned, so a longer text
  -- makes the box grow to the left, away from the button.
  return function()
    for _, param in ipairs({ ANIMALS, VEGETATION, ROCKS }) do
      local button = item(newTable, moved(G.buttons[param].index))
      local x = rd32(G.menu + MENU_X) + rd32(button + ITEM_X)
      local y = rd32(G.menu + MENU_Y) + rd32(button + ITEM_Y)
      if rd16(button + ITEM_HOVERED) ~= 0
          and isMouseInside(G.mouse, x, y, rd32(button + ITEM_WIDTH), rd32(button + ITEM_HEIGHT)) ~= 0 then
        local shown, widest = lines(param), 0
        for i, line in ipairs(shown) do
          local text = string.format("%s: %d/%d", line[1], line[2], line[3])
          writeCString(lineBuffers[i], text)
          widest = math.max(widest, textWidth(G.textManager, lineBuffers[i], #text, TOOLTIP_FONT))
        end
        local right = x - TOOLTIP_GAP
        local left = math.max(right - widest - 2 * TOOLTIP_PADDING, 0)
        local bottom = y + #shown * TOOLTIP_LINE + TOOLTIP_PADDING
        local target = rd32(G.pencil + PENCIL_TARGET)
        wr32(G.pencil + PENCIL_TARGET, 0)
        roundedBox(G.pencil, left, y, right, bottom, BOX_BLEND)
        wr32(G.pencil + PENCIL_TARGET, target)
        for i = 1, #shown do
          shadowedText(G.textManager, lineBuffers[i], right - TOOLTIP_PADDING,
            y + TOOLTIP_PADDING // 2 + (i - 1) * TOOLTIP_LINE, ALIGN_RIGHT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT,
            0, 0)
        end
        return
      end
    end
  end
end

---------------------------------------------------------------------------------------
-- Map counts: the new item table
---------------------------------------------------------------------------------------

-- Copies the item table with the new items inserted: the "i" button in front of item
-- INFO_BEFORE_ITEM, the tooltip at the end of the always shown part, and at the end of the
-- Animals and Vegetation tabs an item that draws the numbers of the tab's buttons.
local function buildTable(G, shown)
  local inserts = {
    [INFO_BEFORE_ITEM] = { "info" },
    [G.firstBlock] = { "tooltip" },
  }
  for _, tab in ipairs({ ANIMALS, VEGETATION }) do
    local before = G.blockEnd[tab]
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], tab)
  end
  local count = ITEM_COUNT + 1
  for _, list in pairs(inserts) do count = count + #list end

  local newTable = core.allocate(count * MENU_ITEM_SIZE, true)
  local movedTo, added, slot = {}, {}, 0
  for i = 0, ITEM_COUNT do
    for _, kind in ipairs(inserts[i] or {}) do
      added[kind] = slot
      slot = slot + 1
    end
    core.writeBytes(item(newTable, slot), core.readBytes(item(G.table, i), MENU_ITEM_SIZE))
    movedTo[i] = slot
    slot = slot + 1
  end
  local function moved(index) return movedTo[index] end

  local data = {}
  data.shown = core.allocate(4, true)
  wr32(data.shown, shown and 1 or 0)
  data.totals = core.allocate(12, true)
  data.typeCounts = core.allocate(TREE_TYPES * 4, true)

  local countSlots = core.allocateAssembly(COUNT_SLOTS, {
    TYPE_COUNTS = data.typeCounts, TREE_TYPES = TREE_TYPES, TOTALS = data.totals,
    FIRST_TREE = G.firstTree, TREE_SLOTS = G.treeSlots, TREE_SIZE = G.treeSize,
    TREE_TYPE_FROM_IN_USE = TREE_TYPE_FROM_IN_USE,
    FIRST_ROCK = G.firstRock, ROCK_SLOTS = G.rockSlots, ROCK_SIZE = G.rockSize,
    FIRST_GROUP = G.firstGroup, GROUP_SLOTS = G.groupSlots, GROUP_SIZE = G.groupSize,
  })
  wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_RENDER), core.allocateAssembly(DESCRIPTION_LINE, {
    SHOWN = data.shown, COUNT_SLOTS = countSlots, HOVER_RENDER = G.hoverRender,
  }))
  wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_X), HOVER_TEXT_MOVED_X)

  -- The numbers of the Animals and Vegetation tabs: per tab a list of (button, counter).
  local counted = { [ANIMALS] = {}, [VEGETATION] = {} }
  for param, address in pairs(G.animals) do table.insert(counted[ANIMALS], { param, address }) end
  for _, param in ipairs(G.plants) do
    table.insert(counted[VEGETATION], { param, data.typeCounts + G.plantTypes[param] * 4 })
  end
  local tabNumbers = core.allocateAssembly(TAB_NUMBERS, {
    SHOWN = data.shown, ITEM_MENU = ITEM_MENU, MENU_X = MENU_X, MENU_Y = MENU_Y,
    MENU_SCROLL = MENU_SCROLL, ITEM_X = ITEM_X, ITEM_Y = ITEM_Y, ITEM_WIDTH = ITEM_WIDTH,
    ITEM_HEIGHT = ITEM_HEIGHT, NUMBER_FROM_BOTTOM = NUMBER_FROM_BOTTOM, NUMBER_FONT = NUMBER_FONT,
    NUMBER_COLOUR = NUMBER_COLOUR, TEXT_MANAGER = G.textManager, RENDER_NUMBER = G.renderNumber,
  })
  for tab, list in pairs(counted) do
    local buttons = core.allocate((#list + 1) * 8, true)
    for i, entry in ipairs(list) do
      wr32(buttons + (i - 1) * 8, item(newTable, moved(G.buttons[entry[1]].index)))
      wr32(buttons + (i - 1) * 8 + 4, entry[2])
    end
    local numbers = item(newTable, added[tab])
    wr32(numbers + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
    wr32(numbers + ITEM_PARAM, buttons)
    wr32(numbers + ITEM_RENDER, tabNumbers)
    wr32(numbers + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  end

  -- The "i" button.
  local info = item(newTable, added.info)
  wr32(info + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(info + ITEM_X, INFO_BUTTON[1])
  wr32(info + ITEM_Y, INFO_BUTTON[2])
  wr32(info + ITEM_ACTION, core.allocateAssembly(TOGGLE, { SHOWN = data.shown }))
  wr32(info + ITEM_RENDER, core.allocateAssembly(INFO_BUTTON_RENDER, {
    CAMERA_X = G.cameraX, CAMERA_Y = G.cameraY, ITEM_X = G.itemX, ITEM_Y = G.itemY,
    DRAW_MODE = G.drawMode, IMAGE_BUTTON = G.imageButton,
  }))
  wr32(info + ITEM_IMAGE, INFO_IMAGE)
  wr32(info + ITEM_RENDER_TYPE, RENDER_IMAGE)
  wr32(info + ITEM_TEXT, 0)              -- no description, the usual hover sound

  -- The tooltip: drawn after everything else that is always shown, never hit by the mouse.
  local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  local drawTooltip = makeTooltip(G, newTable, moved, data)
  local broken = false
  core.detourCode(function(registers)
    if not broken then
      local ok, problem = pcall(drawTooltip)
      if not ok then
        broken = true
        log(WARNING, MODULE_NAME .. ": the tooltip stopped after an error: " .. tostring(problem))
      end
    end
    return registers
  end, pad, 5)
  local tooltip = item(newTable, added.tooltip)
  wr32(tooltip + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(tooltip + ITEM_RENDER, core.allocateAssembly(TOOLTIP, {
    SHOWN = data.shown, PAD = pad,
    ANIMALS_HOVER = item(newTable, moved(G.buttons[ANIMALS].index), ITEM_HOVERED),
    VEGETATION_HOVER = item(newTable, moved(G.buttons[VEGETATION].index), ITEM_HOVERED),
    ROCKS_HOVER = item(newTable, moved(G.buttons[ROCKS].index), ITEM_HOVERED),
  }))
  wr32(tooltip + ITEM_RENDER_TYPE, RENDER_SIMPLE)

  return newTable, data.shown
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

local function enableCounts(self, shown)
  local G = {}
  resolveMenu(G)
  resolveDrawing(G)
  resolveCounters(G)
  local newTable, shownFlag = buildTable(G, shown)
  installTable(G, newTable)
  self.shownFlag = shownFlag
  log(INFO, string.format("%s: map counts on (menu 0x%X, items 0x%X -> 0x%X; %d tree, %d rock, %d group slots)",
    MODULE_NAME, G.menu, G.table, newTable, G.treeSlots, G.rockSlots, G.groupSlots))
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

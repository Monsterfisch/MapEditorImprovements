--[[
  Map Editor Improvements

  Changes to the map editor, each a setting of its own:

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
  3. Trees:
     - Growth stage from the brush size. placeTree hands createTree a fixed stage, 3; it gets
       brush size - 1 (0 .. 6) instead. createTree still decides for shrubs (always 4).
     - An apple tree button. No tool command makes an apple tree (type 15), so the module
       takes command 136, which the click handler already sends through placeTree like the
       shrubs (it would make type 11, an invisible shrub no button uses), and has the
       command-to-type function answer 15 for it.
     - A shrub panel above the Vegetation menu while one of shrub types 5 .. 9 is chosen:
       commands 130 .. 134, which the game already understands (only 130 has a button).
       Those five shrubs are one picture (tree_shrub1) in the colours createTree gives them.
     - A felled tree panel above the Vegetation menu while a tree (types 1 .. 4) is chosen:
       one button per number of logs a felled tree of that type and growth stage can have
       (TreeRelated1[type][stage]: 1, 2, 4, 9, 9 for stages 0 .. 4). A tree placed with one
       of them chosen is laid down the way the woodcutter's log taking leaves a tree
       (advanceTreeDecayState: lying = 2, that many logs, no chops left). Its picture is the
       game's own choice (UpdateTree1: stage base - logs).
  4. Ground textures: the Textures menu's two rows get a fifth button each, Gravel (command
     13, which the click handler already understands; pictures from images/) and Iron (a copy
     of the Heights menu's iron button), and the rows are spread evenly over the panel.

  None of the menu changes patch code. The landscape editor's menu items are a static table
  handed to the Menu constructor by a CRT initializer (push table / mov ecx, menu / call
  Menu::Menu). A copy of that table is built with the module's items added and the push
  pointed at the copy; if the menu has been built already, it is built again.

  Buttons above the panel (the "i", the shrub and felled tree panels) lie over the map. The
  game draws there on the map surface, at the item position plus the camera offset (see its
  description line renderer), and so does the module. Clicks there would also reach the
  map: an item put in front of the game's map click handler tells it the mouse is not on the
  map while it is on one of these buttons.

  Every address is found by pattern scan or read out of the instruction that uses it, so the
  module runs on Stronghold Crusader.exe and Stronghold_Crusader_Extreme.exe alike.
]]

local templates = require("templates")
local png = require("png")

local MODULE_NAME = "map-editor-improvements"
local MODULE_FOLDERS = { "ucp/modules/map-editor-improvements/" }   -- UCP maps this to the active version

local DEFAULTS = {
  counts = { enabled = true, shown = true },
  menu = { always_update = true },
  trees = { growth_from_brush = true, apple = true, shrubs = true, felled = true },
  textures = { gravel_and_iron = true },
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
local MAP_CLICK_ITEM = 1                 -- every frame: the game's map click handler

-- MenuItem (0x50 bytes)
local MENU_ITEM_SIZE = 0x50
local ITEM_TYPE, ITEM_X, ITEM_Y, ITEM_WIDTH, ITEM_HEIGHT = 0x00, 0x04, 0x08, 0x0C, 0x10
local ITEM_ACTION, ITEM_PARAM, ITEM_RENDER = 0x14, 0x18, 0x1C
local ITEM_IMAGE, ITEM_RENDER_TYPE, ITEM_TEXT = 0x20, 0x24, 0x2C
local ITEM_CONTROL = 0x30                -- word: user control placing the item, -1 none
local ITEM_HOVERED, ITEM_HIDDEN, ITEM_MENU = 0x32, 0x36, 0x4C
local TYPE_EVERY_FRAME, TYPE_CLICKABLE = 0, 3
local TYPE_GROUP_START, TYPE_BLOCK, TYPE_END = 0x01000000, 0x64, 0x66
local TYPE_GROUP_MEMBER_MASK, TYPE_GROUP_MEMBER = 0xFF000000, 0x02000000
local RENDER_NONE, RENDER_SIMPLE, RENDER_IMAGE = 0, 1, 3
local PLACED_BY_CONTROL = 0x80000000     -- x of an item the user control table places
local IMAGE_INDEX_MASK = 0x7FFFFF
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

-- Button commands (item param). A category button's command is its tab's id.
local DEER, LION, RABBIT, CAMEL = 220, 221, 222, 223
local TEXTURES, VEGETATION, ANIMALS, ROCKS = 232, 234, 235, 237
local FIRST_TREE_COMMAND, LAST_TREE_COMMAND = 40, 43        -- tree types 1 .. 4
local SHRUB_COMMANDS = { 130, 131, 132, 133, 134 }          -- shrub types 5 .. 9
local APPLE_COMMAND, APPLE_TYPE = 136, 15
local GRAVEL_COMMAND, IRON_COMMAND = 13, 16

-- The rows the module spreads out, by command, left to right (the order of the buttons'
-- user control positions), and the span of the panel they are spread over.
local TEXTURE_ROWS = { { 18, 340, 10, 12, GRAVEL_COMMAND }, { 5, 7, 19, 341, IRON_COMMAND } }
local VEGETATION_ROW = { 41, 42, 40, 43, APPLE_COMMAND, 135 }
local ROW_LEFT, ROW_RIGHT = 250, 636

-- MenuItemRenderFunction_MapEditorLandscaping_GeneralButtons: the item position globals
-- (width follows the position), the hover flag, the open tab, the brush size, the chosen
-- tool, the image table, the texture renderer and the store that switches it to the screen
-- (0) before drawing; 1 draws on the map surface.
local BUTTON_RENDER = {
  hover = { 0x01, { 0x8B, 0x35 } },
  tab = { 0x21, { 0x39, 0x05 } },
  brush = { 0x4D, { 0xA1 } },
  subtype = { 0x91, { 0x39, 0x05 } },
  drawMode = { 0xC8, { 0xC7, 0x05 } },
  images = { 0xD2, { 0x8D, 0x88 } },
  y = { 0xEF, { 0x8B, 0x15 } },
  x = { 0xF8, { 0xA1 } },
  textures = { 0x101, { 0xB9 } },
}
local BUTTON_WIDTH = 0x08                -- from the x global
local IMAGE_SIZE = 0x1C                  -- image table entry: +0 gm, +4 picture

-- MenuItemActionHandler_MapEditorLandscaping_QueueCommandCallback: whether the mouse is on
-- the map (ViewportRenderState +0).
local MAP_CLICK = { onMap = { 0xF1, { 0x39, 0x1D } } }

-- The description line's renderer: mov eax,[esp+4] / push eax / mov ecx, state / call / ret,
-- and in the function it calls, the camera offset it adds for the map layer.
local HOVER_RENDER_BYTES = { 0x8B, 0x44, 0x24, 0x04, 0x50, 0xB9 }
local HOVER_RENDER_CALL = 0x0A
local CAMERA_X = { 0x5C, { 0x03, 0x0D } }   -- add ecx, [camera x]
local CAMERA_Y = { 0x62, { 0x03, 0x3D } }   -- add edi, [camera y]
local TEXT_LAYER = { 0x68, { 0xC7, 0x05 } }  -- mov dword [textManager.layer], 1

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
-- text width, the shadowed text, and the colour box (whose code gives the pencil's surface
-- and clipping functions).
local AOB_NAME_BOX = "A1 ? ? ? ? 8B 0D ? ? ? ? 8B 15 ? ? ? ? 56 57 6A 05 03 C8 51 8B 0D ? ? ? ? 03 "
  .. "D1 52 50 51 B9 ? ? ? ?"
local NAME_BOX = {
  pencil = { 0x23, { 0xB9 } },
  roundedBox = 0x28,
  widthUntilCursor = 0x32,
  colourBox = 0x69,
  textManager = { 0x9C, { 0xB9 } },
  shadowedText = 0xA1,
}
local WIDTH_UNTIL_CURSOR_CALL = 0x22     -- inside it: the text width up to a length
local COLOUR_BOX_SURFACE, COLOUR_BOX_CLIP = 0x03, 0x23
local PENCIL_TARGET = 0x0C               -- 0 screen, 1 map surface
local BOX_BLEND = 5

-- The screen's pixel format (0x565 or 0x555).
local AOB_PIXEL_FORMAT = "81 3D ? ? ? 00 65 05 00 00 75 40"
local PIXEL_FORMAT_OPERAND = 2

-- handleMenuItems, where it asks whether the mouse is over an item: the mouse and its
-- "is the mouse in this box" test. (The ui module patches the function's start.)
local AOB_MENU_ITEM = "8B 56 10 8B 46 4C 8B 4E 0C 52 8B 50 08 03 56 08 8B 40 04 03 46 04 51 52 50 B9"
local MENU_ITEM_MOUSE = { 0x19, { 0xB9 } }
local MENU_ITEM_IS_INSIDE = 0x1E

-- The tooltip: above the panel, over the map, just above the description line and starting
-- at the button's left edge.
local TOOLTIP_FONT, TOOLTIP_COLOUR = 0x12, 0xB8EEFB  -- the description line's own style
local TOOLTIP_LINE, TOOLTIP_PADDING = 16, 6
local TOOLTIP_BOTTOM = HOVER_TEXT_POSITION[2] - 3
local ALIGN_LEFT = 0
local MAP_LAYER = 1                      -- text manager layer / pencil target: the map surface

-- renderGM(gm, picture, x, y) on the texture renderer: picture tables (first picture of a
-- gm, data offsets, sizes) and the animation sprite renderer it hands trees to, which reads
-- the sprite (for its palettes) and the palette to use from two globals.
local AOB_RENDER_GM = "8B 54 24 08 56 8B 74 24 08 8B 04 B5 ? ? ? ? 69 F6 58 14 00 00"
local RENDER_GM = {
  firstPictures = 0x0C,
  offsets = { 0x21, { 0x8B, 0x14, 0x85 } },
  dataBase = { 0x28, { 0x03, 0x51, 0x78 } },
  heights = { 0x39, { 0x0F, 0xBF, 0x90 } },   -- +2 of the picture sizes (+0 width)
  animation = 0x7F,
}
local ANIMATION = { palette = { 0x25, { 0x83, 0x3D } }, sprite = { 0x56, { 0x8B, 0x0D } } }
local PICTURE_SIZE = 16
local TEXTURES_MODE, TEXTURES_DIRECT_PALETTE, TEXTURES_DATA = 0x04, 0x10, 0x78

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
-- LandscapeState::mapUITreeTypeToLogicalTreeType(command): which tree type a tool places.
local AOB_TREE_TYPE = "8B 44 24 04 83 C0 D8 83 F8 74 0F 87"
local TREE_TYPE_START = { 0x8B, 0x44, 0x24, 0x04, 0x83, 0xC0, 0xD8 }

-- placeTree(x, y, command), at `push 3 / push 0 / movzx eax,ax / ...` (the growth stage and
-- other arguments of createTree), the createTree call, and right after it
-- `mov esi,eax / imul esi,esi,<tree size>`. The command is at [esp+0x28] there.
local AOB_PLACE_TREE = "6A 03 6A 00 0F B7 C0 6A 00 52 0F BF C0 50 56 51 B9 ? ? ? ? E8 ? ? ? ? 8B F0 69 F6 ? ? ? ?"
local PLACE_TREE = { stageSize = 7, landscape = 0x11, create = 0x15, created = 0x1A, createdSize = 8,
  command = 0x28 }
-- In createTree: the logs table (TreeRelated1, int [type][7]), the gm of each tree type and
-- the update function of each tree type.
local CREATE_TREE = {
  logs = { 0x10C, { 0x0F, 0xB7, 0x94, 0x00 } },
  gm = { 0xEE, { 0x0F, 0xB7, 0x14, 0xB5 } },
  update = { 0x2E4, { 0x8B, 0x14, 0x8D } },
}
local STAGES, MAX_STAGE, PLACED_STAGE = 7, 6, 3
-- Tree fields (from a slot's start; slot 0 starts at LandscapeState + 0x1C).
local TREES_IN_LANDSCAPE = 0x1C
local TREE = { TYPE = 0x46, CHOPS = 0x72, LYING = 0x76, LOGS = 0x78, STAGE = 0x80 }
local LYING_FELLED = 2
local LAST_TREE_TYPE = 4
-- UpdateTree1's pictures of a felled tree: stage base - logs; stage 0 has only the dead
-- tree picture.
local FELLED_PICTURE_BASE = { [1] = 0x8C, [2] = 0x82, [3] = 0x76, [4] = 0x76 }
local FELLED_STAGE_0_PICTURE = 0x92
-- createTree's colours (palettes) of shrub types 5 .. 9 (all tree_shrub1, picture 1 is the
-- first wind animation frame).
local SHRUB_PALETTES = { [5] = 0, [6] = 3, [7] = 4, [8] = 7, [9] = 8 }
local SHRUB_PICTURE = 1
local FELLED_PALETTE = 0

-- The panels above the Vegetation menu: centred on the screen, squeezed together when wider.
local PANEL_BOTTOM = 444
local PANEL_PADDING, PANEL_GAP, PANEL_MARGIN = 4, 2, 4
-- The present function, where it reads the screen size: mov edx,[width] / mov edi,[height].
local AOB_SCREEN_SIZE = "8B 15 ? ? ? ? 8B 3D ? ? ? ? 89 44 24 20 03 C2 89 44 24 28"
local SCREEN_WIDTH_OPERAND = 2
local MOST_LOGS = 9                      -- buttons in the felled tree panel

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
-- Helpers
---------------------------------------------------------------------------------------

local rd32, rd16, rd8 = core.readInteger, core.readSmallInteger, core.readByte
local wr32, wr16 = core.writeInteger, core.writeSmallInteger

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

---------------------------------------------------------------------------------------
-- Pictures from images/
---------------------------------------------------------------------------------------

local function readFile(name)
  for _, folder in ipairs(MODULE_FOLDERS) do
    local file = io.open(folder .. name, "rb")
    if file ~= nil then
      local data = file:read("a")
      file:close()
      return data
    end
  end
  return nil
end

local function loadPicture(name)
  local data = readFile("images/" .. name .. ".png")
  if data == nil then
    error(string.format("%s: images/%s.png not found", MODULE_NAME, name))
  end
  local ok, width, height, pixels = pcall(png.decode, data)
  if not ok then
    error(string.format("%s: images/%s.png: %s", MODULE_NAME, name, (tostring(width):gsub("^.-:%d+: ", ""))))
  end
  return { width = width, height = height, pixels = pixels }
end

-- Writes a picture, centred on a width x height canvas, in the layout the blit routine
-- reads and returns its address.
local function storePicture(picture, width, height)
  local count = width * height
  local base = core.allocate(0x14 + count * 5, true)
  local rgb565, rgb555, mask = {}, {}, {}
  local left, top = (width - picture.width) // 2, (height - picture.height) // 2
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local sx, sy = x - left, y - top
      local p = { 0, 0, 0, 0 }
      if sx >= 0 and sy >= 0 and sx < picture.width and sy < picture.height then
        p = picture.pixels[sy * picture.width + sx + 1]
      end
      local r, g, b = p[1], p[2], p[3]
      local value565 = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
      local value555 = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
      rgb565[index * 2 - 1], rgb565[index * 2] = value565 & 0xFF, value565 >> 8
      rgb555[index * 2 - 1], rgb555[index * 2] = value555 & 0xFF, value555 >> 8
      mask[index] = p[4]
    end
  end
  wr32(base, width)
  wr32(base + 4, height)
  wr32(base + 8, base + 0x14)
  wr32(base + 0xC, base + 0x14 + count * 2)
  wr32(base + 0x10, base + 0x14 + count * 4)
  core.writeBytes(base + 0x14, rgb565)
  core.writeBytes(base + 0x14 + count * 2, rgb555)
  core.writeBytes(base + 0x14 + count * 4, mask)
  return base
end

-- A button's three pictures: <name>.png, <name>_hover.png, <name>_selected.png, all on the
-- canvas of the largest.
local function buttonPictures(name)
  local normal, hover, chosen = loadPicture(name), loadPicture(name .. "_hover"), loadPicture(name .. "_selected")
  local width = math.max(normal.width, hover.width, chosen.width)
  local height = math.max(normal.height, hover.height, chosen.height)
  return {
    width = width, height = height,
    normal = storePicture(normal, width, height),
    hover = storePicture(hover, width, height),
    chosen = storePicture(chosen, width, height),
  }
end

---------------------------------------------------------------------------------------
-- Finding things
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
      or rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_Y)) ~= HOVER_TEXT_POSITION[2]
      or rd32(item(G.table, MAP_CLICK_ITEM, ITEM_TYPE)) ~= TYPE_EVERY_FRAME then
    error(MODULE_NAME .. ": the landscape editor's menu is not laid out as the module expects")
  end

  G.site = scan("68 " .. bytesOf(G.table) .. " B9 ? ? ? ? E8", "the landscape editor menu's constructor")
  G.menu = rd32(G.site + 6)
  G.constructor = readCallTarget(G.site, 10, "the Menu constructor")

  -- The buttons by command, the render function their groups give them, the block each one
  -- is in (the tab id of the 0x64 marker before it, 0 for the part that is always shown), and
  -- where the always shown part and each tab end.
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
  if G.firstBlock == nil or G.blockEnd[ANIMALS] == nil or G.blockEnd[VEGETATION] == nil
      or G.blockEnd[TEXTURES] == nil then
    error(MODULE_NAME .. ": the landscape editor's menu has not got the tabs this module knows")
  end
  local needed = { DEER, LION, RABBIT, CAMEL, VEGETATION, ANIMALS, ROCKS, IRON_COMMAND,
    SHRUB_COMMANDS[1], table.unpack(VEGETATION_ROW, 1, 4) }
  for _, row in ipairs(TEXTURE_ROWS) do
    for i = 1, 4 do needed[#needed + 1] = row[i] end
  end
  needed[#needed + 1] = VEGETATION_ROW[6]
  for _, param in ipairs(needed) do
    if G.buttons[param] == nil then
      error(string.format("%s: button %d is missing from the landscape editor's menu", MODULE_NAME, param))
    end
  end
  G.plants = {}
  for param, button in pairs(G.buttons) do
    if button.block == VEGETATION then G.plants[#G.plants + 1] = param end
  end

  G.buttonRender = G.buttons[DEER].render
  for _, param in ipairs({ LION, RABBIT, CAMEL, table.unpack(G.plants) }) do
    if G.buttons[param].render ~= G.buttonRender then
      error(MODULE_NAME .. ": the landscape editor's buttons are drawn by an unknown function")
    end
  end
  local b = BUTTON_RENDER
  G.hover = readOperand(G.buttonRender, b.hover, "the editor button renderer")
  G.activeTab = readOperand(G.buttonRender, b.tab, "the editor button renderer")
  G.brush = readOperand(G.buttonRender, b.brush, "the editor button renderer")
  G.subtype = readOperand(G.buttonRender, b.subtype, "the editor button renderer")
  G.drawMode = readOperand(G.buttonRender, b.drawMode, "the editor button renderer")
  G.buttonImages = readOperand(G.buttonRender, b.images, "the editor button renderer")
  G.itemY = readOperand(G.buttonRender, b.y, "the editor button renderer")
  G.itemX = readOperand(G.buttonRender, b.x, "the editor button renderer")
  G.textures = readOperand(G.buttonRender, b.textures, "the editor button renderer")
  if G.drawMode ~= G.textures + TEXTURES_MODE then
    error(MODULE_NAME .. ": the texture renderer is not laid out as the module expects")
  end

  G.onMap = readOperand(rd32(item(G.table, MAP_CLICK_ITEM, ITEM_ACTION)), MAP_CLICK.onMap, "the map click handler")

  G.hoverRender = rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_RENDER))
  expectBytes(G.hoverRender, HOVER_RENDER_BYTES, "the description line renderer")
  local describe = readCallTarget(G.hoverRender, HOVER_RENDER_CALL, "the description line renderer")
  G.cameraX = readOperand(describe, CAMERA_X, "the description line renderer")
  G.cameraY = readOperand(describe, CAMERA_Y, "the description line renderer")
  G.textLayer = readOperand(describe, TEXT_LAYER, "the description line renderer")
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
  G.colourBox = readCallTarget(nameBox, NAME_BOX.colourBox, "the colour box")
  G.setupSurface = readCallTarget(G.colourBox, COLOUR_BOX_SURFACE, "the drawing surface")
  G.setupPencil = readCallTarget(G.colourBox, COLOUR_BOX_CLIP, "the drawing clip")
  G.pixelFormat = rd32(scan(AOB_PIXEL_FORMAT, "the pixel format") + PIXEL_FORMAT_OPERAND)
  G.screenWidth = rd32(scan(AOB_SCREEN_SIZE, "the screen size") + SCREEN_WIDTH_OPERAND)

  local menuItem = scan(AOB_MENU_ITEM, "the menu's mouse test")
  G.mouse = readOperand(menuItem, MENU_ITEM_MOUSE, "the menu's mouse test")
  G.isMouseInside = readCallTarget(menuItem, MENU_ITEM_IS_INSIDE, "the menu's mouse test")

  local renderGM = scan(AOB_RENDER_GM, "the picture renderer")
  G.renderGM = renderGM
  G.firstPictures = rd32(renderGM + RENDER_GM.firstPictures)
  G.pictureOffsets = readOperand(renderGM, RENDER_GM.offsets, "the picture renderer")
  expectBytes(renderGM + RENDER_GM.dataBase[1], RENDER_GM.dataBase[2], "the picture renderer")
  G.pictureHeights = readOperand(renderGM, RENDER_GM.heights, "the picture renderer")
  local animation = readCallTarget(renderGM, RENDER_GM.animation, "the sprite renderer")
  G.spritePalette = readOperand(animation, ANIMATION.palette, "the sprite renderer")
  G.sprite = readOperand(animation, ANIMATION.sprite, "the sprite renderer")
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

  local placeTree = scan(AOB_PLACE_TREE, "the tree placement")
  G.placeTree = placeTree
  G.landscape = rd32(placeTree + PLACE_TREE.landscape)
  G.createTree = readCallTarget(placeTree, PLACE_TREE.create, "createTree")
  G.treeSize = rd32(placeTree + PLACE_TREE.created + 4)
  G.logs = readOperand(G.createTree, CREATE_TREE.logs, "createTree")
  G.typeGm = readOperand(G.createTree, CREATE_TREE.gm, "createTree")
  G.updateTree = readOperand(G.createTree, CREATE_TREE.update, "createTree")

  local newTree = scan(AOB_NEW_TREE, "the tree slot search")
  if newTree ~= G.createTree then
    error(MODULE_NAME .. ": createTree is not where the module expects it")
  end
  G.firstTree = G.landscape + rd32(newTree + NEW_TREE.first)
  G.treeSlots = rd32(newTree + NEW_TREE.last)
  if readOperand(newTree, NEW_TREE.size, "the tree slot search") ~= G.treeSize then
    error(MODULE_NAME .. ": the tree size is not the one this module knows")
  end
  local newRock = scan(AOB_NEW_ROCK, "the rock slot search")
  G.firstRock = G.landscape + rd32(newRock + NEW_ROCK.first)
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

  -- Which tree type each tool places, asked of the game itself (before the apple tree hook).
  G.treeTypeOf = scan(AOB_TREE_TYPE, "the plant types")
  expectBytes(G.treeTypeOf, TREE_TYPE_START, "the plant types")
  local treeType = core.exposeCode(G.treeTypeOf, 2, 1)
  G.plantTypes = {}
  for _, param in ipairs(G.plants) do
    G.plantTypes[param] = treeType(G.landscape, param) & (TREE_TYPES - 1)
  end
  for _, param in ipairs(SHRUB_COMMANDS) do
    G.plantTypes[param] = treeType(G.landscape, param) & (TREE_TYPES - 1)
  end
  G.plantTypes[APPLE_COMMAND] = APPLE_TYPE
end

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

  -- Like the description line, the tooltip is drawn on the map surface (at the screen
  -- position plus the camera offset), which is drawn afresh every frame: nothing of it stays
  -- behind once the mouse leaves the button. Lines are added upwards, away from the panel.
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
        local left = x + rd32(G.cameraX)
        local right = left + widest + 2 * TOOLTIP_PADDING
        local bottom = rd32(G.menu + MENU_Y) + TOOLTIP_BOTTOM + rd32(G.cameraY)
        local top = bottom - #shown * TOOLTIP_LINE - TOOLTIP_PADDING
        local target = rd32(G.pencil + PENCIL_TARGET)
        wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
        roundedBox(G.pencil, left, top, right, bottom, BOX_BLEND)
        wr32(G.pencil + PENCIL_TARGET, target)
        local layer = rd32(G.textLayer)
        wr32(G.textLayer, MAP_LAYER)
        for i = 1, #shown do
          shadowedText(G.textManager, lineBuffers[i], left + TOOLTIP_PADDING,
            top + TOOLTIP_PADDING // 2 + (i - 1) * TOOLTIP_LINE, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT,
            0, 0)
        end
        wr32(G.textLayer, layer)
        return
      end
    end
  end
end

---------------------------------------------------------------------------------------
-- Trees: the shrub and felled tree panels
---------------------------------------------------------------------------------------

local function makePanel(G, O, data, panel)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local renderNumber = core.exposeCode(G.renderNumber, 10, 1)
  local spriteBox = makeSpriteBoxes(G)

  local function stage()
    if not O.growth then return PLACED_STAGE end
    return math.max(0, math.min(MAX_STAGE, rd32(G.brush) - 1))
  end

  local function hideAll()
    for _, address in ipairs(panel.items) do wr16(address + ITEM_HIDDEN, 1) end
  end

  -- What the panel shows for the chosen tool: a list of buttons, each with its item, sprite
  -- and whether it is the chosen one.
  local function entries(command)
    local list = {}
    if O.felled and command >= FIRST_TREE_COMMAND and command <= LAST_TREE_COMMAND then
      local treeType, treeStage = G.plantTypes[command], stage()
      local most = math.min(rd32(G.logs + (treeType * STAGES + treeStage) * 4), MOST_LOGS)
      local gm = rd16(G.typeGm + treeType * 4)
      for i = 1, most do
        local logs = most - i + 1
        local picture = FELLED_STAGE_0_PICTURE
        if treeStage > 0 then picture = FELLED_PICTURE_BASE[math.min(treeStage, 4)] - logs end
        list[i] = { item = panel.felled[i], gm = gm, picture = picture, palette = FELLED_PALETTE,
          param = logs, chosen = rd32(data.felledLogs) == logs and rd32(data.felledCommand) == command }
      end
    elseif O.shrubs then
      for i, shrub in ipairs(SHRUB_COMMANDS) do
        local shrubType = G.plantTypes[shrub]
        list[i] = { item = panel.shrubs[i], gm = rd16(G.typeGm + shrubType * 4), picture = SHRUB_PICTURE,
          palette = SHRUB_PALETTES[shrubType] or 0, chosen = command == shrub,
          count = data.typeCounts and (data.typeCounts + shrubType * 4) }
      end
    end
    return list
  end

  local function drawSprite(entry, x, y)
    local t = G.textures
    local mode, direct = rd32(t + TEXTURES_MODE), rd32(t + TEXTURES_DIRECT_PALETTE)
    local sprite, palette = rd32(G.sprite), rd32(G.spritePalette)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    wr32(t + TEXTURES_DIRECT_PALETTE, 1)
    wr32(G.sprite, entry.gm)
    wr32(G.spritePalette, entry.palette)
    renderGM(t, entry.gm, entry.picture, x, y)
    wr32(G.sprite, sprite)
    wr32(G.spritePalette, palette)
    wr32(t + TEXTURES_DIRECT_PALETTE, direct)
    wr32(t + TEXTURES_MODE, mode)
  end

  return function()
    local list = entries(rd32(G.subtype))
    hideAll()
    if #list == 0 then return end
    local tallest = 0
    for _, entry in ipairs(list) do
      entry.box = spriteBox(entry.gm, entry.picture)
      if entry.box == nil then return end          -- the trees' pictures are not loaded yet
      tallest = math.max(tallest, entry.box.height)
    end

    -- Lay the buttons out left to right, standing on the panel, centred on the screen; when
    -- wider than the screen, the gaps shrink (below zero, the buttons overlap).
    local height = tallest + 2 * PANEL_PADDING
    local sum = 0
    for _, entry in ipairs(list) do
      entry.width = entry.box.width + 2 * PANEL_PADDING
      sum = sum + entry.width
    end
    local screen = rd32(G.screenWidth)
    local gap = PANEL_GAP
    if #list > 1 and sum + gap * (#list - 1) > screen - 2 * PANEL_MARGIN then
      gap = (screen - 2 * PANEL_MARGIN - sum) / (#list - 1)
    end
    local total = sum + gap * (#list - 1)
    local menuX = rd32(G.menu + MENU_X)
    local top = PANEL_BOTTOM - height
    local x = (screen - total) / 2 - menuX
    local left = math.floor(x + 0.5)
    for _, entry in ipairs(list) do
      entry.x = math.floor(x + 0.5)
      wr32(entry.item + ITEM_X, entry.x)
      wr32(entry.item + ITEM_Y, top)
      wr32(entry.item + ITEM_WIDTH, entry.width)
      wr32(entry.item + ITEM_HEIGHT, height)
      if entry.param ~= nil then wr32(entry.item + ITEM_PARAM, entry.param) end
      wr16(entry.item + ITEM_HIDDEN, 0)
      x = x + entry.width + gap
    end
    local right = math.floor(x - gap + 0.5)

    -- Draw them on the map surface, like the description line.
    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left - PANEL_GAP, offsetY + top - PANEL_GAP,
      offsetX + right + PANEL_GAP, offsetY + PANEL_BOTTOM + PANEL_GAP, BOX_BLEND)
    for _, entry in ipairs(list) do
      local left, right = offsetX + entry.x, offsetX + entry.x + entry.width - 1
      local upper, lower = offsetY + top, offsetY + PANEL_BOTTOM - 1
      if rd16(entry.item + ITEM_HOVERED) ~= 0 then
        roundedBox(G.pencil, left, upper, right, lower, BOX_BLEND)
      end
      if entry.chosen then
        colourBox(G.pencil, left, upper, right, upper + 1, white)
        colourBox(G.pencil, left, lower - 1, right, lower, white)
        colourBox(G.pencil, left, upper, left + 1, lower, white)
        colourBox(G.pencil, right - 1, upper, right, lower, white)
      end
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    for _, entry in ipairs(list) do
      drawSprite(entry, offsetX + entry.x + PANEL_PADDING - entry.box.x,
        offsetY + PANEL_BOTTOM - PANEL_PADDING - entry.box.height - entry.box.y)
    end
    if O.counts and rd8(data.shown) ~= 0 then
      local layer = rd32(G.textLayer)
      wr32(G.textLayer, MAP_LAYER)
      for _, entry in ipairs(list) do
        if entry.count ~= nil then
          renderNumber(G.textManager, rd32(entry.count), offsetX + entry.x + entry.width // 2,
            offsetY + PANEL_BOTTOM - NUMBER_FROM_BOTTOM, 1, NUMBER_COLOUR, 0, NUMBER_FONT, 0, 0)
        end
      end
      wr32(G.textLayer, layer)
    end

    -- The "i" was drawn before the panel (it belongs to the part of the menu that is always
    -- shown); draw it again on top, the way its own renderer does (picture + 1 under the mouse).
    if panel.info ~= nil then
      local entry = G.buttonImages + INFO_IMAGE * IMAGE_SIZE
      local picture = rd32(entry + 4)
      if rd16(panel.info + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
      local mode = rd32(G.textures + TEXTURES_MODE)
      wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
      renderGM(G.textures, rd32(entry), picture, offsetX + rd32(panel.info + ITEM_X),
        offsetY + rd32(panel.info + ITEM_Y))
      wr32(G.textures + TEXTURES_MODE, mode)
    end
  end
end

---------------------------------------------------------------------------------------
-- Spreading rows of buttons over the panel
---------------------------------------------------------------------------------------

-- Once the buttons' pictures are loaded and the menu has placed them, spread the Textures
-- rows (with Gravel and Iron) and the Vegetation menu's top row (with the apple tree) evenly
-- between ROW_LEFT and ROW_RIGHT. Buttons keep their height; new ones (in `added`) take their
-- left neighbour's. Picture buttons have their width in `widthOf`, the others are measured by
-- their gm picture. Moved buttons are taken off the user control table, which would put
-- them back the next time the menu loads.
local function makeLayout(G, rows, added, widthOf)
  return function()
    for _, row in ipairs(rows) do
      local widths, sum = {}, 0
      for i, address in ipairs(row) do
        local width = widthOf[address]
        if width == nil then
          local index = rd32(address + ITEM_IMAGE) & IMAGE_INDEX_MASK
          local gm = rd32(G.buttonImages + index * IMAGE_SIZE)
          local first = rd32(G.firstPictures + gm * 4)
          if first <= 0 then return false end
          width = rd16(G.pictureHeights - 2 + (first + rd32(G.buttonImages + index * IMAGE_SIZE + 4) - 1) * PICTURE_SIZE)
          if width <= 0 then return false end
        end
        if not added[address] and (rd32(address + ITEM_X) & 0xFFFFFFFF) == PLACED_BY_CONTROL then
          return false                         -- the menu has not been loaded yet
        end
        widths[i], sum = width, sum + width
      end
      row.widths, row.sum = widths, sum
    end
    for _, row in ipairs(rows) do
      local gap = (ROW_RIGHT - ROW_LEFT - row.sum) / (#row - 1)
      local x, y = ROW_LEFT, nil
      for i, address in ipairs(row) do
        if added[address] then
          wr32(address + ITEM_Y, y)
        else
          y = rd32(address + ITEM_Y)
        end
        wr32(address + ITEM_X, math.floor(x + 0.5))
        wr16(address + ITEM_CONTROL, -1)
        wr16(address + ITEM_HIDDEN, 0)
        x = x + row.widths[i] + gap
      end
    end
    return true
  end
end

---------------------------------------------------------------------------------------
-- The new item table
---------------------------------------------------------------------------------------

-- Copies the item table with the module's items inserted (in front of the original item
-- whose index they are listed under) and fills them in.
local function buildTable(G, O)
  local data = {}
  local pictures = {}
  if O.apple then pictures.apple = buttonPictures("apple") end
  if O.textures then pictures.gravel = buttonPictures("gravel") end

  local inserts = {}
  local function insert(before, kind)
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], kind)
  end
  insert(MAP_CLICK_ITEM, "guard")
  if O.counts then
    insert(INFO_BEFORE_ITEM, "info")
    insert(G.firstBlock, "tooltip")
    insert(G.blockEnd[ANIMALS], "numbers" .. ANIMALS)
  end
  local vegetationEnd = G.blockEnd[VEGETATION]
  if O.apple then insert(vegetationEnd, "apple") end
  if O.shrubs then
    for i = 1, #SHRUB_COMMANDS do insert(vegetationEnd, "shrub" .. i) end
  end
  if O.felled then
    for i = 1, MOST_LOGS do insert(vegetationEnd, "felled" .. i) end
  end
  if O.shrubs or O.felled then insert(vegetationEnd, "panel") end
  if O.counts then insert(vegetationEnd, "numbers" .. VEGETATION) end
  if O.textures then
    insert(G.blockEnd[TEXTURES], "gravel")
    insert(G.blockEnd[TEXTURES], "iron")
  end

  local count = ITEM_COUNT + 1
  for _, list in pairs(inserts) do count = count + #list end
  local newTable = core.allocate(count * MENU_ITEM_SIZE, true)
  local movedTo, added, slot = {}, {}, 0
  for i = 0, ITEM_COUNT do
    for _, kind in ipairs(inserts[i] or {}) do
      added[kind] = item(newTable, slot)
      slot = slot + 1
    end
    core.writeBytes(item(newTable, slot), core.readBytes(item(G.table, i), MENU_ITEM_SIZE))
    movedTo[i] = slot
    slot = slot + 1
  end
  local function moved(index) return movedTo[index] end
  local function button(param) return item(newTable, moved(G.buttons[param].index)) end
  local function copyOf(param, into)
    core.writeBytes(into, core.readBytes(item(G.table, G.buttons[param].index), MENU_ITEM_SIZE))
  end

  data.shown = core.allocate(4, true)
  wr32(data.shown, O.shown and 1 or 0)
  data.felledLogs = core.allocate(4, true)
  data.felledCommand = core.allocate(4, true)

  -- Map counts.
  if O.counts then
    data.totals = core.allocate(12, true)
    data.typeCounts = core.allocate(TREE_TYPES * 4, true)
    local countSlots = core.allocateAssembly(templates.countSlots, {
      TYPE_COUNTS = data.typeCounts, TREE_TYPES = TREE_TYPES, TOTALS = data.totals,
      FIRST_TREE = G.firstTree, TREE_SLOTS = G.treeSlots, TREE_SIZE = G.treeSize,
      TREE_TYPE_FROM_IN_USE = TREE_TYPE_FROM_IN_USE,
      FIRST_ROCK = G.firstRock, ROCK_SLOTS = G.rockSlots, ROCK_SIZE = G.rockSize,
      FIRST_GROUP = G.firstGroup, GROUP_SLOTS = G.groupSlots, GROUP_SIZE = G.groupSize,
    })
    wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_RENDER), core.allocateAssembly(templates.descriptionLine, {
      SHOWN = data.shown, COUNT_SLOTS = countSlots, HOVER_RENDER = G.hoverRender,
    }))
    wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_X), HOVER_TEXT_MOVED_X)

    -- The numbers of the Animals and Vegetation tabs: per tab a list of (button, counter).
    local counted = { [ANIMALS] = {}, [VEGETATION] = {} }
    for param, address in pairs(G.animals) do
      table.insert(counted[ANIMALS], button(param))
      table.insert(counted[ANIMALS], address)
    end
    for _, param in ipairs(G.plants) do
      table.insert(counted[VEGETATION], button(param))
      table.insert(counted[VEGETATION], data.typeCounts + G.plantTypes[param] * 4)
    end
    if O.apple then
      table.insert(counted[VEGETATION], added.apple)
      table.insert(counted[VEGETATION], data.typeCounts + APPLE_TYPE * 4)
    end
    local tabNumbers = core.allocateAssembly(templates.tabNumbers, {
      SHOWN = data.shown, ITEM_MENU = ITEM_MENU, ITEM_HIDDEN = ITEM_HIDDEN, MENU_X = MENU_X, MENU_Y = MENU_Y,
      MENU_SCROLL = MENU_SCROLL, ITEM_X = ITEM_X, ITEM_Y = ITEM_Y, ITEM_WIDTH = ITEM_WIDTH,
      ITEM_HEIGHT = ITEM_HEIGHT, NUMBER_FROM_BOTTOM = NUMBER_FROM_BOTTOM, NUMBER_FONT = NUMBER_FONT,
      NUMBER_COLOUR = NUMBER_COLOUR, TEXT_MANAGER = G.textManager, RENDER_NUMBER = G.renderNumber,
    })
    for tab, list in pairs(counted) do
      local numbers = added["numbers" .. tab]
      wr32(numbers + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
      wr32(numbers + ITEM_PARAM, dwordList(list))
      wr32(numbers + ITEM_RENDER, tabNumbers)
      wr32(numbers + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    end

    -- The "i" button.
    local info = added.info
    wr32(info + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(info + ITEM_X, INFO_BUTTON[1])
    wr32(info + ITEM_Y, INFO_BUTTON[2])
    wr32(info + ITEM_ACTION, core.allocateAssembly(templates.toggle, { SHOWN = data.shown }))
    wr32(info + ITEM_RENDER, core.allocateAssembly(templates.infoButton, {
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
    local tooltip = added.tooltip
    wr32(tooltip + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(tooltip + ITEM_RENDER, core.allocateAssembly(templates.tooltip, {
      SHOWN = data.shown, PAD = pad,
      ANIMALS_HOVER = button(ANIMALS) + ITEM_HOVERED,
      VEGETATION_HOVER = button(VEGETATION) + ITEM_HOVERED,
      ROCKS_HOVER = button(ROCKS) + ITEM_HOVERED,
    }))
    wr32(tooltip + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  end

  -- Buttons drawn from PNG pictures: a copy of a button of their tab, their own command and
  -- pictures, hidden until laid out.
  local blit = nil
  local function pictureButton(into, model, command, set)
    if blit == nil then
      blit = core.allocateAssembly(templates.blit, {
        PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
        SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
      })
    end
    copyOf(model, into)
    wr32(into + ITEM_X, 0)
    wr32(into + ITEM_Y, 0)
    wr32(into + ITEM_WIDTH, set.width)
    wr32(into + ITEM_HEIGHT, set.height)
    wr32(into + ITEM_PARAM, command)
    wr32(into + ITEM_IMAGE, 0)
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_TEXT, 0)
    wr16(into + ITEM_HIDDEN, 1)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.pictureButton, {
      NORMAL = set.normal, HOVERED = set.hover, CHOSEN = set.chosen, COMMAND = command,
      SUBTYPE = G.subtype, HOVER = G.hover, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET,
      ITEM_X = G.itemX, ITEM_Y = G.itemY, BLIT = blit,
    }))
  end

  local rows, newButtons, rowPictures = {}, {}, {}
  if O.apple then
    pictureButton(added.apple, VEGETATION_ROW[1], APPLE_COMMAND, pictures.apple)
    rowPictures[added.apple] = pictures.apple.width
    newButtons[added.apple] = true
    local row = {}
    for _, param in ipairs(VEGETATION_ROW) do
      row[#row + 1] = param == APPLE_COMMAND and added.apple or button(param)
    end
    rows[#rows + 1] = row
  end
  if O.textures then
    pictureButton(added.gravel, TEXTURE_ROWS[1][1], GRAVEL_COMMAND, pictures.gravel)
    rowPictures[added.gravel] = pictures.gravel.width
    newButtons[added.gravel] = true
    -- Iron: a copy of the Heights menu's iron button, picture and description included.
    copyOf(IRON_COMMAND, added.iron)
    wr32(added.iron + ITEM_X, 0)
    wr32(added.iron + ITEM_Y, 0)
    wr16(added.iron + ITEM_HIDDEN, 1)
    newButtons[added.iron] = true
    for _, rowCommands in ipairs(TEXTURE_ROWS) do
      local row = {}
      for _, param in ipairs(rowCommands) do
        if param == GRAVEL_COMMAND then
          row[#row + 1] = added.gravel
        elseif param == IRON_COMMAND then
          row[#row + 1] = added.iron
        else
          row[#row + 1] = button(param)
        end
      end
      rows[#rows + 1] = row
    end
  end
  local layout = makeLayout(G, rows, newButtons, rowPictures)

  -- The shrub and felled tree panels.
  local guarded = {}
  if O.counts then
    guarded[#guarded + 1] = added.info
    guarded[#guarded + 1] = 0
  end
  if O.shrubs or O.felled then
    local panel = { items = {}, shrubs = {}, felled = {}, info = added.info }
    if O.shrubs then
      for i, command in ipairs(SHRUB_COMMANDS) do
        local into = added["shrub" .. i]
        copyOf(SHRUB_COMMANDS[1], into)        -- the shrub button: its group's action and description
        wr32(into + ITEM_X, 0)
        wr32(into + ITEM_Y, 0)
        wr32(into + ITEM_PARAM, command)
        wr32(into + ITEM_IMAGE, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
        panel.shrubs[i] = into
        panel.items[#panel.items + 1] = into
      end
    end
    if O.felled then
      local click = core.allocateAssembly(templates.felledClick, {
        SUBTYPE = G.subtype, FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      })
      for i = 1, MOST_LOGS do
        local into = added["felled" .. i]
        wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
        wr32(into + ITEM_ACTION, click)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
        panel.felled[i] = into
        panel.items[#panel.items + 1] = into
      end
    end
    for _, address in ipairs(panel.items) do
      guarded[#guarded + 1] = address
      guarded[#guarded + 1] = VEGETATION
    end

    local paint = makePanel(G, O, data, panel)
    local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
    local broken = false
    core.detourCode(function(registers)
      if not broken then
        local ok, problem = pcall(paint)
        if not ok then
          broken = true
          log(WARNING, MODULE_NAME .. ": the tree panels stopped after an error: " .. tostring(problem))
        end
      end
      return registers
    end, pad, 5)
    local first, last = 1, 0                   -- an empty range when the felled panel is off
    if O.felled then first, last = FIRST_TREE_COMMAND, LAST_TREE_COMMAND end
    local firstShrub, lastShrub = 1, 0
    if O.shrubs then firstShrub, lastShrub = SHRUB_COMMANDS[1], SHRUB_COMMANDS[#SHRUB_COMMANDS] end
    local painter = added.panel
    wr32(painter + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(painter + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(painter + ITEM_RENDER, core.allocateAssembly(templates.panel, {
      SUBTYPE = G.subtype, FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      FIRST_TREE = first, LAST_TREE = last, FIRST_SHRUB = firstShrub, LAST_SHRUB = lastShrub,
      PANEL_ITEMS = dwordList(panel.items), ITEM_HIDDEN = ITEM_HIDDEN, PAD = pad,
    }))
  end

  -- The guard, in front of the game's map click handler; it also runs the layout until it
  -- has worked.
  data.laidOut = core.allocate(4, true)
  wr32(data.laidOut, #rows == 0 and 1 or 0)
  local layoutPad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  core.detourCode(function(registers)
    local ok, done = pcall(layout)
    if not ok then
      log(WARNING, MODULE_NAME .. ": the new buttons could not be laid out: " .. tostring(done))
      done = true
    end
    if done then wr32(data.laidOut, 1) end
    return registers
  end, layoutPad, 5)
  local guard = added.guard
  wr32(guard + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(guard + ITEM_ACTION, core.allocateAssembly(templates.guard, {
    LAID_OUT = data.laidOut, LAYOUT = layoutPad, GUARDED = dwordList(guarded),
    ACTIVE_TAB = G.activeTab, ITEM_HIDDEN = ITEM_HIDDEN, ITEM_HEIGHT = ITEM_HEIGHT,
    ITEM_WIDTH = ITEM_WIDTH, ITEM_MENU = ITEM_MENU, MENU_X = MENU_X, MENU_Y = MENU_Y, ITEM_X = ITEM_X,
    ITEM_Y = ITEM_Y, MOUSE = G.mouse, IS_MOUSE_INSIDE = G.isMouseInside, ON_MAP = G.onMap,
  }))

  return newTable, data
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

---------------------------------------------------------------------------------------
-- Trees: code patches
---------------------------------------------------------------------------------------

local function patchTrees(self, G, O, data)
  self.saved = self.saved or {}
  local function patch(site, size, stub)
    table.insert(self.saved, { address = site, bytes = core.readBytes(site, size) })
    core.writeCode(site, jumpTo(site, stub, size))
  end
  if O.apple then
    patch(G.treeTypeOf, #TREE_TYPE_START, core.allocateAssembly(templates.appleType, {
      APPLE_COMMAND = APPLE_COMMAND, APPLE_TYPE = APPLE_TYPE, CONVERTER_BACK = G.treeTypeOf + #TREE_TYPE_START,
    }))
  end
  if O.growth then
    patch(G.placeTree, PLACE_TREE.stageSize, core.allocateAssembly(templates.stageFromBrush, {
      BRUSH = G.brush, MAX_STAGE = MAX_STAGE, STAGE = core.allocate(4, true),
      BACK = G.placeTree + PLACE_TREE.stageSize,
    }))
  end
  if O.felled then
    local site = G.placeTree + PLACE_TREE.created
    patch(site, PLACE_TREE.createdSize, core.allocateAssembly(templates.felledTree, {
      FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      COMMAND_ON_STACK = PLACE_TREE.command, TREE_SIZE = G.treeSize,
      TREES = G.landscape + TREES_IN_LANDSCAPE, TREE_TYPE = TREE.TYPE, LAST_TREE_TYPE = LAST_TREE_TYPE,
      STAGES = STAGES, TREE_STAGE = TREE.STAGE, LOGS = G.logs, TREE_LYING = TREE.LYING,
      LYING_FELLED = LYING_FELLED, TREE_LOGS = TREE.LOGS, TREE_CHOPS = TREE.CHOPS,
      LANDSCAPE = G.landscape, UPDATE_TREE = G.updateTree, BACK = site + PLACE_TREE.createdSize,
    }))
  end
end

local function enableMenu(self, O)
  local G = {}
  resolveMenu(G)
  resolveDrawing(G)
  resolveCounters(G)
  local newTable, data = buildTable(G, O)
  installTable(G, newTable)
  patchTrees(self, G, O, data)
  self.shownFlag = data.shown
  log(INFO, string.format("%s: editor menu changed (menu 0x%X, items 0x%X -> 0x%X; %d tree, %d rock, "
    .. "%d group slots)", MODULE_NAME, G.menu, G.table, newTable, G.treeSlots, G.rockSlots, G.groupSlots))
end

---------------------------------------------------------------------------------------
-- Always keep the menu up to date
---------------------------------------------------------------------------------------

local function enableRedraw(self)
  local site = scan(AOB_MENU_REDRAW, "the main loop's menu redraw") + MENU_REDRAW_SITE
  expectBytes(site, { 0x39, 0x1D }, "the menu redraw test")
  expectBytes(site + 6, { 0x0F, 0x85 }, "the menu redraw test")
  local stub = core.allocateAssembly(templates.menuRedraw, {
    COUNTDOWN = rd32(site + 2),
    GAME_MODE = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND),
    FULL = site + MENU_REDRAW_SIZE + rd32(site + 8),
    PARTIAL = site + MENU_REDRAW_SIZE,
  })
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, MENU_REDRAW_SIZE) })
  core.writeCode(site, jumpTo(site, stub, MENU_REDRAW_SIZE))
  log(INFO, string.format("%s: menu always kept up to date (0x%X)", MODULE_NAME, site))
end

---------------------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------------------

local function enable(self, config)
  config = config or {}
  local O = {
    counts = setting(config, "counts", "enabled") == true,
    shown = setting(config, "counts", "shown") == true,
    growth = setting(config, "trees", "growth_from_brush") == true,
    apple = setting(config, "trees", "apple") == true,
    shrubs = setting(config, "trees", "shrubs") == true,
    felled = setting(config, "trees", "felled") == true,
    textures = setting(config, "textures", "gravel_and_iron") == true,
  }
  if O.counts or O.growth or O.apple or O.shrubs or O.felled or O.textures then
    local ok, problem = pcall(enableMenu, self, O)
    if not ok then log(WARNING, tostring(problem) .. "; the editor menu is left as it is") end
  end
  if setting(config, "menu", "always_update") == true then
    local ok, problem = pcall(enableRedraw, self)
    if not ok then log(WARNING, tostring(problem) .. "; the menu is redrawn as usual") end
  end
end

local function disable(self, config)
  if self.saved ~= nil then
    for i = #self.saved, 1, -1 do
      core.writeCode(self.saved[i].address, self.saved[i].bytes)
    end
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

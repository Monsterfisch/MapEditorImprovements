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
  5. Rocks: skirmish maps open the scenario Rocks menu (tab 237, with the signpost) instead of
     tab 239: the category button's `jl` past `mov eax, 239` becomes a `jmp`.
  6. Random rock rotation: the random button sets rotation mode 0 instead of 5. Mode 5 turns
     the rotation every frame and the preview ignores it; mode 0 turns it once a second and
     the preview follows.
  7. Rock variants: a row above the Rocks menu shows the four variants of the chosen rock size
     and rotation (drawn from the game's own tile pictures through its own tile layout,
     getBuildingSizeIndexMappingData, and the map's turn). Choosing one fixes the variant the
     editor places and previews instead of cycling; the Rocks menu's own buttons go back to
     cycling.
  8. The extra rock: rock number 16 and up makes a 1x1 rock of type 0 (see docs/size-4-rocks.md);
     the variant row offers it at size 1x1.
  9. Herds: a panel above the Animals menu shows the chosen animal's herd size (base + random
     mask) and troop type, read from the herd code, with a check box that makes herds
     2 x brush - 1 animals.
  10. Trees next to obstacles: a check box in the Vegetation menu skips placeTree's check of
     the tiles around a new tree. The Vegetation menu's rows are tidied: the top row's shrub
     moves to the bottom row, which is sorted by command.
  11. Random mixes: the felled tree row gets a random standing tree (placeTree's stage, 0 up to
     the brush's) and a random felled tree (logs 1 up to the most), the shrub row a random
     shrub (the command-to-type function picks one of the five shrub commands).

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
  trees = { growth_from_brush = true, apple = true, shrubs = true, felled = true, random_mix = true,
    obstacles = true, sorted_rows = true },
  textures = { gravel_and_iron = true },
  rocks = { signpost = true, random_preview = true, variants = true, extra_rock = true, invisible = true,
    erase_invisible = true },
  castle = { building_counts = true, tower_ruins = true, tunnel_and_tents = true, statues_and_shrines = true,
    barrier = true, several_keeps = true, several_storage_and_recruitment = true, tower_engines_anywhere = true,
    keep_parts = true, damaged_walls = true },
  herds = { panel = true },
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
local VEGETATION_TREES = { 41, 42, 40, 43 }            -- the top row's trees
local TOP_ROW_SHRUB = 135
local SORTED_SHRUBS = { 130, 135, 153, 154, 155, 156 }  -- the bottom row, sorted by command
local ROW_LEFT, ROW_RIGHT = 250, 636
local OBSTACLES_BUTTON = "obstacles"                   -- the check box's key in a row

-- Constants of the later features, in a table: a Lua chunk may have at most 200 locals.
local K = {}
-- Functions of the later features, in a table for the same reason.
local C = {}

-- Rocks: the tabs (scenario with signpost, skirmish without) and the tools.
K.ROCKS_SKIRMISH = 239
K.SIGNPOST = 59
K.FIRST_ROCK_COMMAND = 205
K.LAST_ROCK_COMMAND = 209
-- The category button's action: `cmp eax, 237 / jne / cmp [map type], 1 / jl +5 / mov eax, 239`.
K.AOB_SIGNPOST = "3D ED 00 00 00 75 0E 83 3D ? ? ? ? 01 7C 05 B8 EF 00 00 00"
K.SIGNPOST_JUMP = 0x0E
K.JL_SHORT = 0x7C
K.JMP_SHORT = 0xEB
-- The random rock button: `... / mov ecx, 5 / mov [rotation mode], ecx / mov [rotation], 0`.
K.AOB_RANDOM_ROCK = "A3 ? ? ? ? A1 ? ? ? ? 83 F8 02 B9 05 00 00 00 89 0D ? ? ? ? C7 05"
K.RANDOM_ROCK_MODE = 0x12
K.RANDOM_ROCK_MODE_SIZE = 6
-- The click handler's rock placement: `lea ecx,[variant + size*4] / mov [command param 3],ecx /
-- push 0x1A / ... / call queueCommand / mov eax,[variant]` (the variant cycling).
K.AOB_ROCK_PLACE = "8D 0C ? 89 0D ? ? ? ? 6A 1A B9 ? ? ? ? C7 05 ? ? ? ? 14 00 00 00 E8 ? ? ? ? A1"
K.ROCK_PLACE = { size = 9, param = 5, variant = 0x20 }
-- ... and its preview: `mov reg,[a] / mov reg,[b]` (variant and size, either order),
-- `lea ecx,[...] / mov edx,[mouse tile y] / ... / mov ecx, TileMapState / call preview`.
K.AOB_ROCK_PREVIEW = "8D 0C ? 8B 15 ? ? ? ? A1 ? ? ? ? 51 52 50 B9 ? ? ? ? E8"
K.ROCK_PREVIEW = { size = 9, mouseY = 5, tileMap = 0x12, first = { -0x0B, { 0x8B, 0x15 } },
  second = { -0x05, { 0xA1 } } }
-- TileMapState fields: the rock tool's rotation and rotation mode, the map's turn (0, 6, 4,
-- 2), and what getBuildingSizeIndexMappingData(tile, size) leaves for a footprint tile.
K.TILE_MAP = { rotation = 0x554890, mode = 0x554894, orientation = 0x55489C,
  tileX = 0x55498C, tileY = 0x554990, tilePicture = 0x554994 }
-- The rock stamping in the map renderer: `mov eax,[esi+tileY] / add eax,[esp+10]` right after
-- the footprint call, and getRandomRockImageOffset (mov eax,[esp+4] / mov eax,[eax*4+table]).
K.AOB_ROCK_STAMP = "8B 86 90 49 55 00 03 44 24 10"
K.ROCK_STAMP = { mapping = -0x05, randomOffset = 0xAA }
K.ROCK_PICTURES = { 0x04, { 0x8B, 0x04, 0x85 } }   -- in getRandomRockImageOffset
K.ROCK_GM = { 0xA5, { 0x66, 0x8B, 0x14, 0x95 } }    -- in createRock: the gm per rock type
K.ROCK_VARIANTS = 4
K.EXTRA_VARIANT = 4
K.EXTRA_ID = 16
K.TILE_DIAMOND = { 2, 6, 10, 14, 18, 22, 26, 30, 30, 26, 22, 18, 14, 10, 6, 2 }
K.TILE_DIAMOND_BYTES = 512
-- The screen offset of a footprint tile (dx, dy) for each map turn: d = dx - dy, s = dx + dy;
-- x = xd*d + xs*s, y = yd*d + ys*s (renderMap's transform without its constants).
K.TURN = {
  [0] = { xd = 16, xs = 0, yd = 0, ys = 8 }, [6] = { xd = 0, xs = -16, yd = 8, ys = 0 },
  [4] = { xd = -16, xs = 0, yd = 0, ys = -8 }, [2] = { xd = 0, xs = 16, yd = -8, ys = 0 },
}

-- Herds: `movzx eax, byte [random] / and eax, MASK / mov edi, UNIT / add eax, BASE`, after
-- `mov word [herd + 0x42], TROOP TYPE`; deer, lions, rabbits, camels in that order.
K.AOB_HERD = "0F B6 05 ? ? ? ? 83 E0 ? BF ? 00 00 00 83 C0 ?"
K.HERD = { site = 7, size = 11, mask = 9, unit = 11, base = 17, group = { -7, { 0x66, 0xC7, 0x44, 0x28, 0x42 } } }
K.HERD_ANIMALS = { { DEER, "Deer" }, { LION, "Lion" }, { RABBIT, "Rabbit" }, { CAMEL, "Camel" } }
K.HERD_SEARCH_END = 0x01000000       -- the end of the game's code for searches with several hits

-- placeTree: `xor ebx,ebx / test eax,eax / mov [esp+0x10],esi / jle <past the check>`.
K.AOB_OBSTACLES = "33 DB 85 C0 89 74 24 10 7E 50 56 55 8D 44 24 18"
K.OBSTACLES_SIZE = 10
K.OBSTACLES_JUMP = 0x09
K.OBSTACLES_NEAR = 0x400               -- how far from placeTree's start the check lies at most

-- The game's check boxes (interface_icons3 pictures 206 tick / 208 cross, + 1 under the
-- mouse), by image table index.
K.CHECKED_IMAGE = 569
K.UNCHECKED_IMAGE = 570
K.CHECK_BOX_SIZE = 29

-- Random mixes in the tree panels: the felled tree buttons' choices for a random standing
-- tree (growth stage 0 up to the brush's, offered for stages 1 .. 4) and a random number of
-- logs, and the random numbers (a linear congruential generator, high 16 bits used).
K.RANDOM_STANDING = 0x40
K.RANDOM_FELLED = 0x41
K.MOST_RANDOM_STAGE = 4
K.RANDOM_MULTIPLIER = 1103515245
K.RANDOM_INCREMENT = 12345
K.RANDOM_LABEL = "?"

-- Invisible rocks: placeRock's `push edx / mov ecx, LandscapeState / call createRock / xor
-- edi,edi / add eax, 2000 / mov [esp+0x20],eax` (the rock number the tiles get: 2000 + slot,
-- 2000 when the list is full). createRock takes 5 arguments.
K.AOB_CREATE_ROCK_CALL = "52 B9 ? ? ? ? E8 ? ? ? ? 33 FF 05 D0 07 00 00 89 44 24 20"
K.CREATE_ROCK_CALL = 6
K.CREATE_ROCK_ARGUMENTS = 0x14
K.CHECK_BOX_GAP = 8
-- Tooltips of the check boxes sit higher than the category tooltips (clear of the menu's top).
K.CHECK_BOX_TOOLTIP_RAISE = 20
-- Names the game has no text for, shown on the description line in the game's language
-- (German when the game's text for iron, cr.tex group 8 text 337, is "Eisen").
K.NAMES = { apple = { en = "Apple tree", de = "Apfelbaum" }, gravel = { en = "Gravel", de = "Kies" } }
K.TEXT_FILE, K.TEXT_GROUP, K.TEXT_INDEX, K.GERMAN_TEXT = "cr.tex", 8, 337, "Eisen"
K.TEXT_GROUPS, K.TEXT_START = 250, 1000
-- A felled tree placed at the smallest growth stage is placed at the next one, with 1 log (the
-- smallest stage has no felled picture).
K.SMALLEST_FELLED_STAGE, K.SMALLEST_FELLED_LOGS = 1, 1
-- Erasing invisible rocks: the eraser brush (and the brush the other tools erase with) takes a
-- tile's rock off by its number: `cmp eax, 2000 / mov ecx, LandscapeState / jl <tree> / add
-- eax, -2000 / push eax / call removeRock`. An invisible rock's tiles have number 2000, an
-- empty slot. The tile is in [esp+0x20], the map tables are named a little before.
K.AOB_ERASE_ROCK = "3D D0 07 00 00 B9 ? ? ? ? 7C 15 05 30 F8 FF FF 50 E8"
K.ERASE_ROCK = { base = 1, site = 12, size = 11, call = 6 }
K.AOB_ERASE_TABLES = "F6 84 86 ? ? ? ? 30 75 ? 0F BF 84 46 ? ? ? ? 85 C0 74"
K.ERASE_TABLES = { flags = 3, numbers = 14 }
K.ROCK_TILE_FLAG = 0x80
K.ERASE_SITES = 2

-- Castle mode: the build menu (found by its minimap item, item 17), its tabs (the menu
-- category values) and the commands (placement ids) the module adds.
K.AOB_BUILD_MINIMAP = "02 00 80 00 3B 02 00 00 D1 01 00 00 7E 00 00 00 7E 00 00 00 ? ? ? ? 39 30 00 00"
K.BUILD_MINIMAP_ITEM = 17
K.BUILD_MOST_ITEMS = 1000
K.MAP_EDITOR = 1                         -- GameMode2
K.TAB_TOWERS, K.TAB_KEEPS, K.TAB_ARMY, K.TAB_GOOD, K.TAB_RUINS = 11, 13, 14, 15, 27
K.TAB_UNIT_COMMANDS = 61                 -- the engineer's siege tent buttons are here
K.FIRST_TOWER = 110                      -- towers 110 .. 114, their ruins 115 .. 119
K.TOWER_RUINS = { 115, 116, 117, 118, 119 }
K.RUIN_LABEL = "Ruin"
K.ENGINEERS_GUILD, K.TUNNELERS_GUILD = 88, 89
K.TUNNEL_COMMAND, K.TUNNEL_LABEL = 57, "Tunnel"
K.TUNNEL_WHEN = { [89] = true, [57] = true }
K.TENTS = { 190, 191, 192, 193, 194, 358 }
K.TENTS_WHEN = { [88] = true, [190] = true, [191] = true, [192] = true, [193] = true, [194] = true, [358] = true }
K.STATUES = { { 320, 313, "2x2" }, { 321, 318, "2x2" }, { 322, 318, "1x1" } }   -- command, picture of, label
K.FIRST_RUIN = 248
K.BARRIER_COMMAND, K.BARRIER_LABEL = 58, "Barrier"
-- The barrier's picture: the "no workers" sign the game floats over buildings, face on (gm
-- floats_new, picture 80; pictures 65 .. 80 turn it round). The gm number is checked against
-- the gm list (records of 1000 bytes, by name) and the check boxes' gm, interface_icons3.
K.NO_WORKERS_GM, K.NO_WORKERS_PICTURE = 172, 80
K.AOB_GM_NO_WORKERS = "66 6C 6F 61 74 73 5F 6E 65 77 00"           -- "floats_new"
K.AOB_GM_CHECK_BOXES = "69 6E 74 65 72 66 61 63 65 5F 69 63 6F 6E 73 33 00"   -- "interface_icons3"
K.GM_RECORD_SIZE = 1000
K.SCREEN_LAYER = 0
K.BUILD_NEEDED = {
  { 11, 110 }, { 11, 111 }, { 11, 112 }, { 11, 113 }, { 11, 114 }, { 14, 88 }, { 14, 89 }, { 15, 313 }, { 15, 318 },
  { 27, 248 }, { 61, 190 }, { 61, 191 }, { 61, 192 }, { 61, 193 }, { 61, 194 }, { 61, 358 },
  { 13, 60 }, { 13, 61 }, { 13, 62 }, { 10, 25 }, { 10, 26 }, { 10, 27 }, { 10, 46 },
}
-- The building list: placeBuilding's `push ebx / mov ecx, BuildingsState / mov [esi+..],edx /
-- call convertCommandBuildingTypeToBuildingType`; BuildingsState + 8 is the list's size.
K.AOB_BUILDINGS_STATE = "53 B9 ? ? ? ? 89 96 ? ? ? ? E8 ? ? ? ? 83 3D ? ? ? ? 04"
K.MAX_BUILDINGS = 8
-- The list's capacity: a walk over every slot, `mov esi, <first state> / ... / add esi,
-- <building size> / inc edi / cmp esi, <past the last>`.
K.AOB_BUILDING_SLOTS = "BE ? ? ? ? 8D 64 24 00 66 83 3E 00 74 0B 57 B9 ? ? ? ? E8 ? ? ? ? 81 C6 2C 03 00 00 83 C7 01 81 FE"
K.BUILDING_SLOTS = { first = 1, past = 0x25 }
K.BUILDING_REMOVED = 3                   -- logical state; 0 is a free slot
-- The toolbar action's `mov eax, [current player] / mov ecx,eax / imul ecx,ecx,<player size>`.
K.AOB_CURRENT_PLAYER = "A1 ? ? ? ? 8B C8 69 C9 ? ? 00 00 39 99 ? ? ? ? 74 18"
-- A walk over the building list: `lea edx,[ecx + first state] / push ebx / movzx eax, word
-- [edx] / test ax,ax / je / movsx ebx, word [edx + owner]`, ... `add edx, <building size>`.
K.AOB_PLAYER_LOOP = "8D 91 ? ? ? ? 53 0F B7 02 66 85 C0 74 ? 0F BF 5A ?"
K.PLAYER_LOOP_OWNER = 18
K.PLAYER_LOOP_STRIDE = { 0x79, { 0x81, 0xC2 } }
-- ... and in it the building types it counts: `movsx eax, word [edx + type] / add eax,-first /
-- cmp eax, last - first / ja <counted> / movzx eax, byte [eax + table] / jmp [eax*4 + jumps]`.
K.AOB_PLAYER_BUILDINGS = "0F BF 42 02 83 C0 F6 83 F8 5E 77 0E 0F B6 80 ? ? ? ? FF 24 85 ? ? ? ?"
-- getBuildingSizeForCommandBuildingType: `mov eax,[esp+4] / add eax,-0x2C / cmp eax,0x146 / ja`.
K.AOB_BUILDING_SIZE = "8B 44 24 04 83 C0 D4 3D 46 01 00 00 77 75"
K.BUILDING_SIZE_START = 7
-- The preview's building pictures: `call convertCommandBuildingTypeToBuildingType / mov eax,
-- [eax*4 + gm per building type] / mov [esi+..],eax / movsx eax,bx / push eax / mov ecx,
-- BuildingsState / call getSpriteID` (the building's first picture).
K.AOB_BUILDING_SPRITES = "E8 ? ? ? ? 8B 04 85 ? ? ? ? 89 86 ? ? ? ? 0F BF C3 50 B9 ? ? ? ? E8"
K.BUILDING_SPRITES = { gms = 8, sprite = 0x1B }
K.TUNNEL_SIZE = 3
-- Panels moved left of the screen's middle.
K.PANEL_SHIFT = { [11] = -50, [13] = -50, [15] = -50 }
K.TENTS_SHIFT = -200
-- Keep parts in the placement check (checkBuildingCanBePlacedHere: after the door tiles `mov
-- eax,[esp+0x48] / shl eax,5`, before the stockpile `mov eax,[esp+0x4C] / mov ebx,[eax+..]`)
-- and in the preview colours (setConstructionGFXLayerBasedOnPlacementChecks: after the doors
-- `shl edx,5 / add ebp,[edx+..]`, before the stockpile `mov eax,[esp+0x38] / mov ebp,[eax+..]`).
K.AOB_KEEP_CHECK = "8B 44 24 48 C1 E0 05 03 B8 ? ? ? ? 03 A8"
K.KEEP_CHECK = { size = 7, stockpile = 0xBF, stockpileSize = 10, table = 6, done = 0xB1,
  doneBytes = { 0x5F, 0x5E, 0x5D, 0x5B, 0x83, 0xC4, 0x2C, 0xC2, 0x14, 0x00 } }
K.AOB_KEEP_PREVIEW = "C1 E2 05 03 AA ? ? ? ? 03 BA ? ? ? ? 89 54 24 38"
K.AOB_KEEP_PREVIEW_STOCKPILE = "8B 44 24 38 8B A8 ? ? ? ? 8B 80 ? ? ? ? 03 44 24 18"
K.KEEP_PREVIEW = { size = 9, table = 5, stockpileSize = 10, stockpileTable = 6, done = 0x83,
  doneBytes = { 0x66, 0x8B, 0x44, 0x24, 0x34 } }
-- computeBuildingCategoryEntryPointAndDestroyEarlierBuilding(building, player, category): its
-- `push eax / mov ecx, BuildingsState / call destroyBuilding / mov edx,[esp+0x1C]`, three
-- times: the player's earlier keep (twice), then the earlier one of the unique buildings.
K.AOB_EARLIER_BUILDING = "8B 54 24 0C 53 55 56 57 33 FF 33 F6 85 D2 8B E9 C7 05"
K.EARLIER_DESTROY = "50 B9 ? ? ? ? E8 ? ? ? ? 8B 54 24 1C"
K.EARLIER_DESTROY_CALL, K.EARLIER_SEARCH = 6, 0x2D0
K.EARLIER_KEEP_CALLS = { 1, 2 }
K.EARLIER_UNIQUE_CALLS = { 3 }
K.DESTROY_ARGUMENTS = 4
-- checkBuildingCanBePlacedHere: a second stockpile, granary or armoury must touch the first
-- (`push type / ... / call hasBuildingAsNeighbour / test eax,eax / jne <allowed>`).
K.AOB_STORAGE_NEIGHBOURS = {
  "8B 44 24 50 6A 0A 50 55 57 53 B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 85",
  "8B 54 24 50 6A 13 52 55 57 53 B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 85",
  "8B 4C 24 50 6A 0B 51 55 57 53 B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 85",
}
K.STORAGE_NEIGHBOUR_CALL = 15
K.NEIGHBOUR_ARGUMENTS = 0x14
-- The place-building click for the tower mangonel and the tower ballista (in that order): with
-- the mouse button let go, `cmp esi, ebx / je <refuse>` (esi: the building on the tile), then
-- the tower tests and the spawn command (42: spawnUnit at a micro position and height).
K.AOB_TOWER_ENGINE_CLICK = "3B F3 0F 84 ? ? ? ? 8B 15 ? ? ? ? 69 F6 2C 03 00 00 0F BF 8E"
K.TOWER_ENGINE = {
  size = 8, refuse = { 0x02, { 0x3B, 0xF3, 0x0F, 0x84 } }, player = { 0x08, { 0x8B, 0x15 } },
  buildingSize = { 0x0E, { 0x69, 0xF6 } }, owners = { 0x14, { 0x0F, 0xBF, 0x8E } },
  types = { 0x23, { 0x0F, 0xB7, 0x8E } }, units = { 0x4B, { 0x66, 0x39, 0x1C, 0x45 } },
  param0 = { 0xC0, { 0x89, 0x15 } }, param1 = { 0xD5, { 0x89, 0x15 } },
  heights = { 0xE8, { 0x0F, 0xB6, 0x84, 0x0A } }, command = { 0xF0, { 0x6A } }, sync = { 0xF2, { 0xB9 } },
  param2 = { 0xF7, { 0xA3 } }, param3 = { 0xFC, { 0xC7, 0x05 } }, queue = 0x106, epilogue = 0x10B,
}
K.TOWER_4, K.TOWER_5 = 77, 78            -- the building types a tower engine can stand on
-- Keep parts: placeKeep places the keep and its doors, then (`mov eax,[esp+0x3C] / mov ecx,
-- [esp+0x48] / add ebx,[eax*8+..]`) the campfire area, then (`mov eax,[esp+0x3C] / mov edi,
-- [eax*8+..]`) the stockpile; both lead on to the same epilogue.
K.AOB_KEEP_CAMPFIRE = "8B 44 24 3C 8B 4C 24 48 03 1C C5 ? ? ? ? 03 3C C5"
K.AOB_KEEP_STOCKPILE = "8B 44 24 3C 8B 3C C5 ? ? ? ? 8B 1C C5 ? ? ? ? 03 7C 24 24"
K.KEEP_CAMPFIRE_SIZE, K.KEEP_STOCKPILE_SIZE = 8, 11
K.KEEP_EPILOGUE = { 0x78, { 0x5F, 0x5E, 0x5D, 0x5B, 0x83, 0xC4, 0x1C, 0xC2, 0x1C, 0x00 } }
K.KEEPS = { 60, 61, 62 }
K.KEEP_ONLY, K.KEEP_NO_STOCKPILE = 1, 3   -- the keep panel's choices
K.KEEP_LABELS = { [1] = "Keep only", [3] = "No stockpile" }
-- Damaged walls: placeWalls, after a tile is built or repaired (`mov ecx,[esp+0x44] / push esi /
-- push ecx / mov ecx, PathFindingState / call ...`; esi the tile, edi TileMapState), and its
-- repair test `cmp byte [esi+edi+damage], 0 / jne / test ebp,ebp / je`.
K.AOB_WALL_TILE_DONE = "56 8B CF E8 ? ? ? ? 8B 54 24 44 8B 44 24 20 52 50 6A 07"
K.WALL_TILE_DONE_SIZE, K.WALL_CLEAR_MOAT_CALL = 8, 3
-- ... and the damage byte the wall drawing reads (updateGfxLayer: `movsx edx, byte [ecx+eax+
-- damage] / test edx,edx / je`). The repair test inside placeWalls is patched by smarter-walls,
-- and so is the instruction before the site above, which it also checks.
K.AOB_WALL_DAMAGE = "0F BE 94 01 ? ? ? ? 85 D2 74"
K.WALL_DAMAGE_OPERAND = 4
K.WALLS = { 27, 46, 25, 26 }             -- stairs, low wall, high wall, crenellated wall
K.TAB_CASTLE = 10
K.DAMAGED_LABEL = "Damaged"

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
K.AOB_UNITS = "81 3D ? ? ? ? ? ? 00 00 7C 03 ? EB 01 ? 6A 1D E8"
K.UNITS_OPERAND = 2
K.UNITS_LIMIT = 6

-- The animal counters, from the animals' update functions.
K.AOB_DEER = "0F BF BE ? ? ? ? BA 01 00 00 00 01 15 ? ? ? ? 66 89 9E"
K.DEER_OPERAND = 0x0E
K.AOB_LIONS = "0F BF BE ? ? ? ? B9 01 00 00 00 01 0D ? ? ? ? 66 89 9E"
K.LIONS_OPERAND = 0x0E
K.AOB_RABBITS = "51 8B 15 ? ? ? ? 83 05 ? ? ? ? 01 53 56 8B F2"
K.RABBITS_OPERAND = 0x09
K.AOB_CAMELS = "83 05 ? ? ? ? 01 53 55 56 57 8B 3D"
K.CAMELS_OPERAND = 0x02

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
  -- Rock tool buttons are listed per tab too (they are in both Rocks tabs), with the action
  -- their group gives them.
  G.buttons, G.blockEnd, G.rockButtons = {}, {}, {}
  local groupRender, groupAction, groupIndex, block = nil, nil, nil, 0
  for i = 0, ITEM_COUNT - 1 do
    local itemType = rd32(item(G.table, i, ITEM_TYPE))
    if itemType == TYPE_BLOCK then
      if block == 0 then G.firstBlock = i else G.blockEnd[block] = G.blockEnd[block] or i end
      block = rd32(item(G.table, i, ITEM_PARAM))
    elseif itemType == TYPE_GROUP_START then
      groupRender = rd32(item(G.table, i, ITEM_RENDER))
      groupAction = rd32(item(G.table, i, ITEM_ACTION))
      groupIndex = i
    elseif (itemType & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
      local param = rd32(item(G.table, i, ITEM_PARAM))
      if G.buttons[param] == nil then
        local render = rd32(item(G.table, i, ITEM_RENDER))
        if render == 0 then render = groupRender end
        local action = rd32(item(G.table, i, ITEM_ACTION))
        if action == 0 then action = groupAction end
        G.buttons[param] = { index = i, render = render, block = block, action = action }
      end
      if param >= K.FIRST_ROCK_COMMAND and param <= K.LAST_ROCK_COMMAND then
        local action = rd32(item(G.table, i, ITEM_ACTION))
        if action == 0 then action = groupAction end
        table.insert(G.rockButtons, { index = i, action = action, block = block, group = groupIndex })
      end
    end
  end
  if block ~= 0 then G.blockEnd[block] = G.blockEnd[block] or ITEM_COUNT end
  if G.firstBlock == nil or G.blockEnd[ANIMALS] == nil or G.blockEnd[VEGETATION] == nil
      or G.blockEnd[TEXTURES] == nil or G.blockEnd[ROCKS] == nil then
    error(MODULE_NAME .. ": the landscape editor's menu has not got the tabs this module knows")
  end
  local needed = { DEER, LION, RABBIT, CAMEL, VEGETATION, ANIMALS, ROCKS, IRON_COMMAND, TOP_ROW_SHRUB,
    table.unpack(SORTED_SHRUBS) }
  for _, row in ipairs(TEXTURE_ROWS) do
    for i = 1, 4 do needed[#needed + 1] = row[i] end
  end
  for _, param in ipairs(VEGETATION_TREES) do needed[#needed + 1] = param end
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
  local unitTest = scan(K.AOB_UNITS, "the unit count")
  G.units = rd32(unitTest + K.UNITS_OPERAND)
  G.unitLimit = rd32(unitTest + K.UNITS_LIMIT)
  G.animals = {
    [DEER] = rd32(scan(K.AOB_DEER, "the deer count") + K.DEER_OPERAND),
    [LION] = rd32(scan(K.AOB_LIONS, "the lion count") + K.LIONS_OPERAND),
    [RABBIT] = rd32(scan(K.AOB_RABBITS, "the rabbit count") + K.RABBITS_OPERAND),
    [CAMEL] = rd32(scan(K.AOB_CAMELS, "the camel count") + K.CAMELS_OPERAND),
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

-- Rocks: the rock tool's state, the placement and preview sites, and what the module needs to
-- draw rocks the way the map renderer does.
local function resolveRocks(G)
  G.rockPlace = scan(K.AOB_ROCK_PLACE, "the rock placement")
  G.rockParam = rd32(G.rockPlace + K.ROCK_PLACE.param)
  G.rockVariant = rd32(G.rockPlace + K.ROCK_PLACE.variant)
  G.chosenRockSize = G.rockVariant + 4
  G.rockPreview = scan(K.AOB_ROCK_PREVIEW, "the rock preview")
  G.mouseTileY = rd32(G.rockPreview + K.ROCK_PREVIEW.mouseY)
  G.tileMap = rd32(G.rockPreview + K.ROCK_PREVIEW.tileMap)
  local a = readOperand(G.rockPreview, K.ROCK_PREVIEW.first, "the rock preview")
  local b = readOperand(G.rockPreview, K.ROCK_PREVIEW.second, "the rock preview")
  if not ((a == G.rockVariant and b == G.chosenRockSize) or (b == G.rockVariant and a == G.chosenRockSize)) then
    error(MODULE_NAME .. ": the rock variant and size are not where the module expects them")
  end
  if G.tileMap + 0x5548F4 ~= G.rockVariant then
    error(MODULE_NAME .. ": the map tile state is not laid out as the module expects")
  end
  local stamp = scan(K.AOB_ROCK_STAMP, "the rock drawing")
  G.footprint = readCallTarget(stamp, K.ROCK_STAMP.mapping, "the footprint layout")
  local randomOffset = readCallTarget(stamp, K.ROCK_STAMP.randomOffset, "the rock pictures")
  G.rockBases = readOperand(randomOffset, K.ROCK_PICTURES, "the rock pictures")
  local newRock = scan(AOB_NEW_ROCK, "the rock slot search")
  G.rockGm = rd16(readOperand(newRock, K.ROCK_GM, "createRock") + 4)
end

-- Herds: per animal the herd code site and what it does.
local function resolveHerds(G)
  local sites, start = {}, 0x400000
  while #sites < #K.HERD_ANIMALS + 1 do
    local ok, found = pcall(core.scanForAOB, K.AOB_HERD, start, K.HERD_SEARCH_END)
    if not ok or found == nil or found == 0 then break end
    sites[#sites + 1] = found
    start = found + 1
  end
  if #sites ~= #K.HERD_ANIMALS then
    error(MODULE_NAME .. ": the herd code is not the one this module knows")
  end
  G.herds = {}
  for i, site in ipairs(sites) do
    local herd = { command = K.HERD_ANIMALS[i][1], name = K.HERD_ANIMALS[i][2], site = site + K.HERD.site }
    herd.mask = rd8(site + K.HERD.mask) & 0xFF
    herd.unit = rd32(site + K.HERD.unit)
    herd.base = rd8(site + K.HERD.base) & 0xFF
    expectBytes(site + K.HERD.group[1], K.HERD.group[2], "the herd code")
    herd.group = rd16(site + K.HERD.group[1] + #K.HERD.group[2])
    G.herds[herd.command] = herd
  end
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
    local picture = { address = storeRawPicture(width, height, pixels), width = width, height = height }
    cache[key] = picture
    return picture
  end
end

---------------------------------------------------------------------------------------
-- Map counts: the tooltip
---------------------------------------------------------------------------------------

-- candidates: { item = button, lines = function returning text lines or nil }.
local function makeTooltip(G, candidates)
  local isMouseInside = core.exposeCode(G.isMouseInside, 5, 1)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local lineBuffers = { core.allocate(96, true), core.allocate(96, true) }

  -- Like the description line, the tooltip is drawn on the map surface (at the screen
  -- position plus the camera offset), which is drawn afresh every frame: nothing of it stays
  -- behind once the mouse leaves the button. Lines are added upwards, away from the panel.
  return function()
    for _, candidate in ipairs(candidates) do
      local button = candidate.item
      local x = rd32(G.menu + MENU_X) + rd32(button + ITEM_X)
      local y = rd32(G.menu + MENU_Y) + rd32(button + ITEM_Y)
      local shown = rd16(button + ITEM_HOVERED) ~= 0
        and isMouseInside(G.mouse, x, y, rd32(button + ITEM_WIDTH), rd32(button + ITEM_HEIGHT)) ~= 0
        and (candidate.name or candidate.lines())
      if shown and candidate.name ~= nil then   -- a name on the description line, like the game's
        writeCString(lineBuffers[1], shown)
        local layer = rd32(G.textLayer)
        wr32(G.textLayer, MAP_LAYER)
        shadowedText(G.textManager, lineBuffers[1], rd32(G.menu + MENU_X) + G.describeAt[1] + rd32(G.cameraX),
          rd32(G.menu + MENU_Y) + G.describeAt[2] + rd32(G.cameraY), ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
        wr32(G.textLayer, layer)
        return
      end
      if shown then
        local widest = 0
        for i, text in ipairs(shown) do
          writeCString(lineBuffers[i], text)
          widest = math.max(widest, textWidth(G.textManager, lineBuffers[i], #text, TOOLTIP_FONT))
        end
        local left = x + rd32(G.cameraX)
        local right = left + widest + 2 * TOOLTIP_PADDING
        local bottom = rd32(G.menu + MENU_Y) + TOOLTIP_BOTTOM + rd32(G.cameraY) - (candidate.raise or 0)
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
-- Rows of buttons above the panel: trees, shrubs, rocks
---------------------------------------------------------------------------------------

-- What the tree panel shows for the chosen tool: the felled trees of the chosen tree, or the
-- five shrubs, and with random mixes on a random standing tree (the tree's own button picture),
-- a random felled tree and a random shrub. Each entry: its item, a game sprite (gm, picture,
-- palette) or button image, the param its click gets, whether it is the chosen one, a label and
-- the counter to show on it.
local function makeTreeEntries(G, O, data, panel)
  local function stage()
    if not O.growth then return PLACED_STAGE end
    return math.max(0, math.min(MAX_STAGE, rd32(G.brush) - 1))
  end
  return function(command)
    local list = {}
    if O.felled and command >= FIRST_TREE_COMMAND and command <= LAST_TREE_COMMAND then
      local treeType, treeStage = G.plantTypes[command], stage()
      local most = math.min(rd32(G.logs + (treeType * STAGES + treeStage) * 4), MOST_LOGS)
      if treeStage == 0 then most = K.SMALLEST_FELLED_LOGS end
      local gm = rd16(G.typeGm + treeType * 4)
      local felledLogs, felledCommand = rd32(data.felledLogs), rd32(data.felledCommand)
      local function add(entry)
        entry.item = panel.felled[#list + 1]
        entry.chosen = felledLogs == entry.param and felledCommand == command
        list[#list + 1] = entry
      end
      local function felledPicture(logs)
        local shown = math.max(treeStage, K.SMALLEST_FELLED_STAGE)   -- see stageFromBrush
        return FELLED_PICTURE_BASE[math.min(shown, 4)] - logs
      end
      add({ image = panel.images[command], param = 0 })   -- the standing tree
      list[1].chosen = felledLogs == 0 or felledCommand ~= command
      if O.randomMix and treeStage >= 1 and treeStage <= K.MOST_RANDOM_STAGE then
        add({ image = panel.images[command], param = K.RANDOM_STANDING, label = K.RANDOM_LABEL })
      end
      for logs = most, 1, -1 do
        add({ gm = gm, picture = felledPicture(logs), palette = FELLED_PALETTE, param = logs })
      end
      if O.randomMix and most >= 2 then
        add({ gm = gm, picture = felledPicture(most), palette = FELLED_PALETTE, param = K.RANDOM_FELLED,
          label = K.RANDOM_LABEL })
      end
    elseif O.shrubs then
      local random = O.randomMix and rd8(data.randomShrub) ~= 0
      for i, shrub in ipairs(SHRUB_COMMANDS) do
        local shrubType = G.plantTypes[shrub]
        list[i] = { item = panel.shrubs[i], gm = rd16(G.typeGm + shrubType * 4), picture = SHRUB_PICTURE,
          palette = SHRUB_PALETTES[shrubType] or 0, chosen = command == shrub and not random,
          count = data.typeCounts and (data.typeCounts + shrubType * 4) }
      end
      if O.randomMix then
        local shrubType = G.plantTypes[SHRUB_COMMANDS[1]]
        list[#list + 1] = { item = panel.randomShrub, gm = rd16(G.typeGm + shrubType * 4), picture = SHRUB_PICTURE,
          palette = SHRUB_PALETTES[shrubType] or 0, chosen = random, label = K.RANDOM_LABEL }
      end
    end
    return list
  end
end

-- What the rock panel shows: the four variants of the chosen size, as the map would draw them
-- now (rotation and turn), and at size 1x1 the extra rock (number 16: type 0, base 0).
local function makeRockEntries(G, O, data, panel, rockPicture)
  return function(command)
    local size = rd32(G.chosenRockSize)
    if size < 0 or size > 3 then return {} end
    local lock = rd32(data.rockLock)
    if lock == K.EXTRA_VARIANT + 1 and size ~= 0 then
      wr32(data.rockLock, 0)                   -- the extra rock exists at 1x1 only
      lock = 0
    end
    local rotation = rd32(G.tileMap + K.TILE_MAP.rotation)
    local list = {}
    for v = 0, K.ROCK_VARIANTS - 1 do
      local base = rd32(G.rockBases + (size * K.ROCK_VARIANTS + v) * 4)
      local picture = rockPicture(size + 1, base, rotation)
      if picture == nil then return {} end
      list[#list + 1] = { item = panel.rocks[v + 1], picture = picture, param = v + 1, chosen = lock == v + 1 }
    end
    if O.extraRock and size == 0 then
      local picture = rockPicture(1, 0, rotation)
      if picture == nil then return {} end
      list[#list + 1] = { item = panel.rocks[K.EXTRA_VARIANT + 1], picture = picture,
        param = K.EXTRA_VARIANT + 1, chosen = lock == K.EXTRA_VARIANT + 1 }
    end
    return list
  end
end

-- The tooltip, drawn before the panels, again on top of them (see buildTable).
local function drawTooltipOnTop(data)
  if data.tooltip ~= nil then
    data.tooltipLate = true
    data.tooltip()
  end
end

-- Draws a row of buttons above the panel, centred on the screen (squeezed together when wider
-- than it), on the map surface like the description line, and lays out the row's items to
-- match. Every frame while the panel is shown; the panel item hides the items otherwise.
local function makePanel(G, O, data, panel, entries)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local renderNumber = core.exposeCode(G.renderNumber, 10, 1)
  local blit = core.exposeCode(G.blit, 3, 0)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local labelBuffer = core.allocate(16, true)
  local spriteBox = makeSpriteBoxes(G)

  -- A button image's gm, picture and size; nil while it is not loaded.
  local function image(index)
    local entry = G.buttonImages + index * IMAGE_SIZE
    local gm, picture = rd32(entry), rd32(entry + 4)
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local header = G.pictureHeights - 2 + (first + picture - 1) * PICTURE_SIZE
    local width, height = rd16(header), rd16(header + 2)
    if width <= 0 or height <= 0 then return nil end
    return { gm = gm, picture = picture, width = width, height = height }
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
    for _, address in ipairs(panel.items) do wr16(address + ITEM_HIDDEN, 1) end
    if #list == 0 then return end
    local tallest = 0
    for _, entry in ipairs(list) do
      if entry.gm ~= nil then
        entry.box = spriteBox(entry.gm, entry.picture)
        if entry.box == nil then return end    -- the pictures are not loaded yet
      elseif entry.image ~= nil then
        entry.button = image(entry.image)
        if entry.button == nil then return end
        entry.box = { x = 0, y = 0, width = entry.button.width, height = entry.button.height }
      else
        entry.box = { x = 0, y = 0, width = entry.picture.width, height = entry.picture.height }
      end
      tallest = math.max(tallest, entry.box.height)
    end

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
    local x = (screen - total) / 2 - menuX + (list.shift or 0)
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

    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left - PANEL_GAP, offsetY + top - PANEL_GAP,
      offsetX + right + PANEL_GAP, offsetY + PANEL_BOTTOM + PANEL_GAP, BOX_BLEND)
    for _, entry in ipairs(list) do
      local l, r = offsetX + entry.x, offsetX + entry.x + entry.width - 1
      local upper, lower = offsetY + top, offsetY + PANEL_BOTTOM - 1
      if rd16(entry.item + ITEM_HOVERED) ~= 0 then
        roundedBox(G.pencil, l, upper, r, lower, BOX_BLEND)
      end
      if entry.chosen then
        colourBox(G.pencil, l, upper, r, upper + 1, white)
        colourBox(G.pencil, l, lower - 1, r, lower, white)
        colourBox(G.pencil, l, upper, l + 1, lower, white)
        colourBox(G.pencil, r - 1, upper, r, lower, white)
      end
    end
    for _, entry in ipairs(list) do
      local sx = offsetX + entry.x + PANEL_PADDING - entry.box.x
      local sy = offsetY + PANEL_BOTTOM - PANEL_PADDING - entry.box.height - entry.box.y
      if entry.gm == nil and entry.button == nil then blit(entry.picture.address, sx, sy) end
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    for _, entry in ipairs(list) do
      local sx = offsetX + entry.x + PANEL_PADDING - entry.box.x
      local sy = offsetY + PANEL_BOTTOM - PANEL_PADDING - entry.box.height - entry.box.y
      if entry.gm ~= nil then
        drawSprite(entry, sx, sy)
      elseif entry.button ~= nil then
        local mode = rd32(G.textures + TEXTURES_MODE)
        wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
        renderGM(G.textures, entry.button.gm, entry.button.picture, sx, sy)
        wr32(G.textures + TEXTURES_MODE, mode)
      end
    end
    -- Labels (the random mixes' "?"), at the top of their button.
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    for _, entry in ipairs(list) do
      if entry.label ~= nil then
        writeCString(labelBuffer, entry.label)
        local width = textWidth(G.textManager, labelBuffer, #entry.label, TOOLTIP_FONT)
        shadowedText(G.textManager, labelBuffer, offsetX + entry.x + (entry.width - width) // 2,
          offsetY + top + PANEL_PADDING, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
      end
    end
    wr32(G.textLayer, layer)
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
      local image = G.buttonImages + INFO_IMAGE * IMAGE_SIZE
      local picture = rd32(image + 4)
      if rd16(panel.info + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
      local mode = rd32(G.textures + TEXTURES_MODE)
      wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
      renderGM(G.textures, rd32(image), picture, offsetX + rd32(panel.info + ITEM_X),
        offsetY + rd32(panel.info + ITEM_Y))
      wr32(G.textures + TEXTURES_MODE, mode)
    end
    drawTooltipOnTop(data)
  end
end

---------------------------------------------------------------------------------------
-- The herd panel above the Animals menu
---------------------------------------------------------------------------------------

-- Two lines of text in a box centred on the screen: the chosen animal's herd (base + random
-- part, or 2 x brush - 1 with the check box on) and troop type, and the check box with its
-- label. The check box item is placed under its picture.
local function makeHerdPanel(G, O, data, herd)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local buffers = { core.allocate(128, true), core.allocate(128, true) }

  return function()
    wr16(herd.checkBox + ITEM_HIDDEN, 1)
    local animal = G.herds[rd32(G.subtype)]
    if animal == nil then return end
    local brush = rd32(G.brush)
    local size
    if rd8(data.herdSync) ~= 0 then
      size = string.format("2 x brush %d - 1 = %d animals", brush, 2 * brush - 1)
    else
      size = string.format("%d + 0 to %d animals", animal.base, animal.mask)
    end
    local texts = {
      string.format("%s herd: %s, group behaviour type %d", animal.name, size, animal.group),
      "Herd size from the brush size: 2 x brush - 1",
    }
    local widths = {}
    for i, text in ipairs(texts) do
      writeCString(buffers[i], text)
      widths[i] = textWidth(G.textManager, buffers[i], #text, TOOLTIP_FONT)
    end
    local line = math.max(TOOLTIP_LINE, K.CHECK_BOX_SIZE + 2)
    local width = math.max(widths[1], K.CHECK_BOX_SIZE + TOOLTIP_PADDING + widths[2]) + 2 * TOOLTIP_PADDING
    local height = TOOLTIP_LINE + line + 2 * TOOLTIP_PADDING
    local menuX = rd32(G.menu + MENU_X)
    local left = (rd32(G.screenWidth) - width) // 2 - menuX
    local top = PANEL_BOTTOM - height
    local boxX, boxY = left + TOOLTIP_PADDING, top + TOOLTIP_PADDING + TOOLTIP_LINE
    wr32(herd.checkBox + ITEM_X, boxX)
    wr32(herd.checkBox + ITEM_Y, boxY)
    wr32(herd.checkBox + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(herd.checkBox + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr16(herd.checkBox + ITEM_HIDDEN, 0)

    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left, offsetY + top, offsetX + left + width, offsetY + PANEL_BOTTOM, BOX_BLEND)
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    shadowedText(G.textManager, buffers[1], offsetX + left + TOOLTIP_PADDING, offsetY + top + TOOLTIP_PADDING // 2,
      ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    shadowedText(G.textManager, buffers[2], offsetX + boxX + K.CHECK_BOX_SIZE + TOOLTIP_PADDING,
      offsetY + boxY + (K.CHECK_BOX_SIZE - TOOLTIP_LINE) // 2 + 2, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)

    local image = G.buttonImages + (rd8(data.herdSync) ~= 0 and K.CHECKED_IMAGE or K.UNCHECKED_IMAGE) * IMAGE_SIZE
    local picture = rd32(image + 4)
    if rd16(herd.checkBox + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
    local mode = rd32(G.textures + TEXTURES_MODE)
    wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
    renderGM(G.textures, rd32(image), picture, offsetX + boxX, offsetY + boxY)
    wr32(G.textures + TEXTURES_MODE, mode)
    drawTooltipOnTop(data)
  end
end

---------------------------------------------------------------------------------------
-- Spreading rows of buttons over the panel
---------------------------------------------------------------------------------------

-- Once the buttons' pictures are loaded and the menu has placed them, spread rows of buttons
-- evenly between ROW_LEFT and ROW_RIGHT. Buttons keep their height; new ones (in `added`) are
-- centred on their left neighbour. A row with `bottom` set stands its buttons on a common
-- line instead (the lowest bottom edge among them). Buttons with their own pictures have their
-- size in `sizeOf`, the others are measured by their gm picture. Moved buttons are taken off
-- the user control table, which would put them back the next time the menu loads. Each of
-- `places` puts one more item somewhere once it can (it answers whether it has).
local function makeLayout(G, rows, added, sizeOf, places)
  local function measure(address)
    local size = sizeOf[address]
    if size ~= nil then return size[1], size[2] end
    local index = rd32(address + ITEM_IMAGE) & IMAGE_INDEX_MASK
    local gm = rd32(G.buttonImages + index * IMAGE_SIZE)
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local header = G.pictureHeights - 2 + (first + rd32(G.buttonImages + index * IMAGE_SIZE + 4) - 1) * PICTURE_SIZE
    local width, height = rd16(header), rd16(header + 2)
    if width <= 0 then return nil end
    return width, height
  end

  return function()
    for _, place in ipairs(places or {}) do
      if not place(measure) then return false end
    end
    for _, row in ipairs(rows) do
      local widths, heights, sum = {}, {}, 0
      for i, address in ipairs(row) do
        local width, height = measure(address)
        if width == nil then return false end
        if not added[address] and (rd32(address + ITEM_X) & 0xFFFFFFFF) == PLACED_BY_CONTROL then
          return false                         -- the menu has not been loaded yet
        end
        widths[i], heights[i], sum = width, height, sum + width
      end
      row.widths, row.heights, row.sum = widths, heights, sum
    end
    for _, row in ipairs(rows) do
      local line = nil
      if row.bottom then
        for i, address in ipairs(row) do
          if not added[address] then line = math.max(line or 0, rd32(address + ITEM_Y) + row.heights[i]) end
        end
      end
      local gap = (ROW_RIGHT - ROW_LEFT - row.sum) / (#row - 1)
      local x, y, h = ROW_LEFT, nil, nil
      for i, address in ipairs(row) do
        if line ~= nil then
          wr32(address + ITEM_Y, line - row.heights[i])
        elseif added[address] then
          wr32(address + ITEM_Y, y + (h - row.heights[i]) // 2)
        else
          y, h = rd32(address + ITEM_Y), row.heights[i]
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
  local rockTabs, boxTabs = {}, {}
  for _, tab in ipairs({ ROCKS, K.ROCKS_SKIRMISH }) do
    if G.blockEnd[tab] ~= nil then
      if O.variants then rockTabs[#rockTabs + 1] = tab end
      if O.invisibleRocks then boxTabs[#boxTabs + 1] = tab end
    end
  end

  local inserts = {}
  local function insert(before, kind)
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], kind)
  end
  insert(MAP_CLICK_ITEM, "guard")
  if O.counts then insert(INFO_BEFORE_ITEM, "info") end
  if O.counts or O.obstacles or O.invisibleRocks or O.apple or O.textures then insert(G.firstBlock, "tooltip") end
  local animalsEnd = G.blockEnd[ANIMALS]
  if O.herds then
    insert(animalsEnd, "herdCheck")
    insert(animalsEnd, "herdPanel")
  end
  if O.counts then insert(animalsEnd, "numbers" .. ANIMALS) end
  local vegetationEnd = G.blockEnd[VEGETATION]
  if O.apple then insert(vegetationEnd, "apple") end
  if O.shrubs then
    for i = 1, #SHRUB_COMMANDS do insert(vegetationEnd, "shrub" .. i) end
    if O.randomMix then insert(vegetationEnd, "randomShrub") end
  end
  local felledButtons = 1 + MOST_LOGS + (O.randomMix and 2 or 0)
  if O.obstacles then insert(vegetationEnd, OBSTACLES_BUTTON) end
  if O.felled then
    for i = 1, felledButtons do insert(vegetationEnd, "felled" .. i) end
  end
  if O.shrubs or O.felled then insert(vegetationEnd, "panel") end
  if O.counts then insert(vegetationEnd, "numbers" .. VEGETATION) end
  if O.textures then
    insert(G.blockEnd[TEXTURES], "gravel")
    insert(G.blockEnd[TEXTURES], "iron")
  end
  for _, tab in ipairs(rockTabs) do
    for v = 1, K.ROCK_VARIANTS + 1 do insert(G.blockEnd[tab], "rock" .. tab .. "/" .. v) end
    insert(G.blockEnd[tab], "rockPanel" .. tab)
  end
  for _, tab in ipairs(boxTabs) do insert(G.blockEnd[tab], "invisible" .. tab) end

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
  -- A lua function called from injected code: a pad that runs it, switched off after an error.
  local function luaPad(fn, what)
    local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
    local broken = false
    core.detourCode(function(registers)
      if not broken then
        local ok, problem = pcall(fn)
        if not ok then
          broken = true
          log(WARNING, string.format("%s: %s stopped after an error: %s", MODULE_NAME, what, tostring(problem)))
        end
      end
      return registers
    end, pad, 5)
    return pad
  end
  -- A button with no picture of its own, never drawn by the menu.
  local function plainButton(into, action)
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_ACTION, action)
    wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
    wr16(into + ITEM_HIDDEN, 1)
  end

  data.shown = core.allocate(4, true)
  wr32(data.shown, O.shown and 1 or 0)
  data.felledLogs = core.allocate(4, true)
  data.felledCommand = core.allocate(4, true)
  data.rockLock = core.allocate(4, true)
  data.herdSync = core.allocate(4, true)
  data.nearObstacles = core.allocate(4, true)
  data.randomShrub = core.allocate(4, true)
  data.invisibleRocks = core.allocate(4, true)
  data.seed = core.allocate(4, true)
  wr32(data.seed, os.time())
  local unused = core.allocate(8, true)        -- the panel template's felled tree state, for panels without it
  if next(pictures) ~= nil or #rockTabs > 0 then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local guarded = {}
  local tooltips = {}

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
    guarded[#guarded + 1] = info
    guarded[#guarded + 1] = 0

    -- The category tooltips.
    local function counts(...)
      local lines = { ... }
      return function()
        if rd8(data.shown) == 0 then return nil end
        local texts = {}
        for i, line in ipairs(lines) do texts[i] = string.format("%s: %d/%d", line[1], line[2](), line[3]) end
        return texts
      end
    end
    tooltips[#tooltips + 1] = { item = button(ANIMALS), lines = counts(
      { "Animals and units", function() return rd32(G.units) end, G.unitLimit },
      { "Herds and troops", function() return rd32(data.totals + 8) end, G.groupSlots }) }
    tooltips[#tooltips + 1] = { item = button(VEGETATION), lines = counts(
      { "Trees and shrubs", function() return rd32(data.totals) end, G.treeSlots }) }
    tooltips[#tooltips + 1] = { item = button(ROCKS), lines = counts(
      { "Rocks", function() return rd32(data.totals + 4) end, G.rockSlots }) }
  end

  -- Buttons drawn from PNG pictures: a copy of a button of their tab, their own command and
  -- pictures, hidden until laid out.
  local function pictureButton(into, model, command, set)
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
      ITEM_X = G.itemX, ITEM_Y = G.itemY, BLIT = G.blit,
    }))
  end

  local rows, newButtons, sizeOf = {}, {}, {}
  local language = C.language()
  local hoverText = item(newTable, moved(HOVER_TEXT_ITEM))
  G.describeAt = { rd32(hoverText + ITEM_X), rd32(hoverText + ITEM_Y) }
  if O.apple then
    tooltips[#tooltips + 1] = { item = added.apple, name = K.NAMES.apple[language] }
    pictureButton(added.apple, VEGETATION_TREES[1], APPLE_COMMAND, pictures.apple)
    sizeOf[added.apple] = { pictures.apple.width, pictures.apple.height }
    newButtons[added.apple] = true
  end

  -- The obstacles check box: in the Vegetation menu, drawn like the menu's buttons.
  if O.obstacles then
    local box = added[OBSTACLES_BUTTON]
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = data.nearObstacles }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.checkBox, {
      FLAG = data.nearObstacles, ON_IMAGE = G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE,
      OFF_IMAGE = G.buttonImages + K.UNCHECKED_IMAGE * IMAGE_SIZE,
      HOVER = G.hover, DRAW_MODE = G.drawMode, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      TEXTURES = G.textures, RENDER_GM = G.renderGM,
    }))
    wr16(box + ITEM_HIDDEN, 1)
    sizeOf[box] = { K.CHECK_BOX_SIZE, K.CHECK_BOX_SIZE }
    newButtons[box] = true
    tooltips[#tooltips + 1] = { item = box, lines = function()
      return { "Trees next to obstacles: " .. (rd8(data.nearObstacles) ~= 0 and "allowed" or "not allowed") }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
  end

  -- The Vegetation menu's rows: the trees, the apple tree and the check box on top (the
  -- shrub moves down, unless the rows are left as they are), the shrubs sorted below.
  if O.apple or O.obstacles or O.sortedRows then
    local top = {}
    for _, param in ipairs(VEGETATION_TREES) do top[#top + 1] = button(param) end
    if O.apple then top[#top + 1] = added.apple end
    if not O.sortedRows then top[#top + 1] = button(TOP_ROW_SHRUB) end
    if O.obstacles then top[#top + 1] = added[OBSTACLES_BUTTON] end
    rows[#rows + 1] = top
  end
  if O.sortedRows then
    local bottom = { bottom = true }
    for _, param in ipairs(SORTED_SHRUBS) do bottom[#bottom + 1] = button(param) end
    rows[#rows + 1] = bottom
  end

  if O.textures then
    tooltips[#tooltips + 1] = { item = added.gravel, name = K.NAMES.gravel[language] }
    pictureButton(added.gravel, TEXTURE_ROWS[1][1], GRAVEL_COMMAND, pictures.gravel)
    sizeOf[added.gravel] = { pictures.gravel.width, pictures.gravel.height }
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
  -- The invisible rocks check box: right of the Rocks menu's last button.
  local places = {}
  for _, tab in ipairs(boxTabs) do
    local box = added["invisible" .. tab]
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = data.invisibleRocks }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.checkBox, {
      FLAG = data.invisibleRocks, ON_IMAGE = G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE,
      OFF_IMAGE = G.buttonImages + K.UNCHECKED_IMAGE * IMAGE_SIZE,
      HOVER = G.hover, DRAW_MODE = G.drawMode, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      TEXTURES = G.textures, RENDER_GM = G.renderGM,
    }))
    wr16(box + ITEM_HIDDEN, 1)
    tooltips[#tooltips + 1] = { item = box, lines = function()
      return { "Invisible rocks: " .. (rd8(data.invisibleRocks) ~= 0 and "on" or "off") }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
    local buttons = {}
    for _, rock in ipairs(G.rockButtons) do
      if rock.block == tab then buttons[#buttons + 1] = item(newTable, moved(rock.index)) end
    end
    if tab == ROCKS and G.buttons[K.SIGNPOST] ~= nil then buttons[#buttons + 1] = button(K.SIGNPOST) end
    places[#places + 1] = function(measure)
      local right, y, height = nil, 0, 0
      for _, address in ipairs(buttons) do
        local x = rd32(address + ITEM_X)
        if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
        local width, h = measure(address)
        if width == nil then return false end
        if right == nil or x + width > right then right, y, height = x + width, rd32(address + ITEM_Y), h end
      end
      wr32(box + ITEM_X, right + K.CHECK_BOX_GAP)
      wr32(box + ITEM_Y, y + (height - K.CHECK_BOX_SIZE) // 2)
      wr16(box + ITEM_HIDDEN, 0)
      return true
    end
  end
  local layout = makeLayout(G, rows, newButtons, sizeOf, places)

  -- A panel item at the end of a tab: shows its panel (lua) while one of its tools is chosen.
  local function panelItem(into, items, first, last, firstShrub, lastShrub, pad, felledLogs, felledCommand)
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.panel, {
      SUBTYPE = G.subtype, FELLED_LOGS = felledLogs or unused, FELLED_COMMAND = felledCommand or unused + 4,
      FIRST_TREE = first, LAST_TREE = last, FIRST_SHRUB = firstShrub, LAST_SHRUB = lastShrub,
      PANEL_ITEMS = dwordList(items), ITEM_HIDDEN = ITEM_HIDDEN, PAD = pad,
    }))
  end

  -- The shrub and felled tree panels.
  if O.shrubs or O.felled then
    local panel = { items = {}, shrubs = {}, felled = {}, images = {}, info = added.info }
    if O.shrubs then
      -- With random mixes, choosing a shrub (here or in the menu) ends the random shrub.
      local shrubAction = nil
      if O.randomMix then
        shrubAction = core.allocateAssembly(templates.rockButton, {
          ROCK_LOCK = data.randomShrub, ACTION = G.buttons[SHRUB_COMMANDS[1]].action,
        })
        wr32(button(SHRUB_COMMANDS[1]) + ITEM_ACTION, shrubAction)
      end
      for i, command in ipairs(SHRUB_COMMANDS) do
        local into = added["shrub" .. i]
        copyOf(SHRUB_COMMANDS[1], into)        -- the shrub button: its group's action and description
        wr32(into + ITEM_X, 0)
        wr32(into + ITEM_Y, 0)
        wr32(into + ITEM_PARAM, command)
        wr32(into + ITEM_IMAGE, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
        if shrubAction ~= nil then wr32(into + ITEM_ACTION, shrubAction) end
        panel.shrubs[i] = into
        panel.items[#panel.items + 1] = into
      end
      if O.randomMix then
        panel.randomShrub = added.randomShrub
        plainButton(panel.randomShrub, core.allocateAssembly(templates.flip, { FLAG = data.randomShrub }))
        panel.items[#panel.items + 1] = panel.randomShrub
      end
    end
    if O.felled then
      local click = core.allocateAssembly(templates.felledClick, {
        SUBTYPE = G.subtype, FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      })
      for command = FIRST_TREE_COMMAND, LAST_TREE_COMMAND do
        panel.images[command] = rd32(item(G.table, G.buttons[command].index, ITEM_IMAGE)) & IMAGE_INDEX_MASK
        -- The menu's tree buttons place standing trees again.
        wr32(button(command) + ITEM_ACTION, core.allocateAssembly(templates.rockButton, {
          ROCK_LOCK = data.felledLogs, ACTION = G.buttons[command].action,
        }))
      end
      for i = 1, felledButtons do
        plainButton(added["felled" .. i], click)
        panel.felled[i] = added["felled" .. i]
        panel.items[#panel.items + 1] = added["felled" .. i]
      end
    end
    for _, address in ipairs(panel.items) do
      guarded[#guarded + 1] = address
      guarded[#guarded + 1] = VEGETATION
    end
    local pad = luaPad(makePanel(G, O, data, panel, makeTreeEntries(G, O, data, panel)), "the tree panels")
    local first, last = 1, 0                   -- an empty range when the felled panel is off
    if O.felled then first, last = FIRST_TREE_COMMAND, LAST_TREE_COMMAND end
    local firstShrub, lastShrub = 1, 0
    if O.shrubs then firstShrub, lastShrub = SHRUB_COMMANDS[1], SHRUB_COMMANDS[#SHRUB_COMMANDS] end
    panelItem(added.panel, panel.items, first, last, firstShrub, lastShrub, pad, data.felledLogs, data.felledCommand)
  end

  -- The rock variant panels (one per Rocks tab), and the Rocks menu's own buttons going back
  -- to cycling variants.
  if #rockTabs > 0 then
    local click = core.allocateAssembly(templates.rockClick, { ROCK_LOCK = data.rockLock })
    local rockPicture = makeRockPictures(G)
    for _, tab in ipairs(rockTabs) do
      local panel = { items = {}, rocks = {}, info = added.info }
      for v = 1, K.ROCK_VARIANTS + 1 do
        local into = added["rock" .. tab .. "/" .. v]
        plainButton(into, click)
        panel.rocks[v] = into
        panel.items[#panel.items + 1] = into
        guarded[#guarded + 1] = into
        guarded[#guarded + 1] = tab
      end
      local pad = luaPad(makePanel(G, O, data, panel, makeRockEntries(G, O, data, panel, rockPicture)),
        "the rock panel")
      panelItem(added["rockPanel" .. tab], panel.items, K.FIRST_ROCK_COMMAND, K.LAST_ROCK_COMMAND, 1, 0, pad)
    end
    -- The buttons and their groups' headers, whose action the Menu constructor may copy into
    -- them.
    local wrapped = {}
    local function wrap(index, action)
      if wrapped[index] or action == 0 then return end
      wrapped[index] = true
      wr32(item(newTable, moved(index), ITEM_ACTION), core.allocateAssembly(templates.rockButton, {
        ROCK_LOCK = data.rockLock, ACTION = action,
      }))
    end
    for _, rock in ipairs(G.rockButtons) do
      wrap(rock.index, rock.action)
      if rock.group ~= nil then wrap(rock.group, rd32(item(G.table, rock.group, ITEM_ACTION))) end
    end
  end

  -- The herd panel.
  if O.herds then
    local herd = { checkBox = added.herdCheck }
    plainButton(herd.checkBox, core.allocateAssembly(templates.flip, { FLAG = data.herdSync }))
    guarded[#guarded + 1] = herd.checkBox
    guarded[#guarded + 1] = ANIMALS
    local pad = luaPad(makeHerdPanel(G, O, data, herd), "the herd panel")
    panelItem(added.herdPanel, { herd.checkBox }, K.HERD_ANIMALS[1][1], K.HERD_ANIMALS[#K.HERD_ANIMALS][1], 1, 0, pad)
  end

  -- The tooltip: drawn after everything else that is always shown, never hit by the mouse.
  if added.tooltip ~= nil then
    local hoverWords = {}
    for _, candidate in ipairs(tooltips) do hoverWords[#hoverWords + 1] = candidate.item + ITEM_HOVERED end
    -- A panel drawn later would cover it: the panels draw it again on top of themselves, and
    -- then it is left out here the next frame.
    data.tooltip = makeTooltip(G, tooltips)
    local function early()
      if data.tooltipLate then data.tooltipLate = false else data.tooltip() end
    end
    local tooltip = added.tooltip
    wr32(tooltip + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(tooltip + ITEM_RENDER, core.allocateAssembly(templates.tooltip, {
      HOVER_WORDS = dwordList(hoverWords), PAD = luaPad(early, "the tooltip"),
    }))
    wr32(tooltip + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  end

  -- The guard, in front of the game's map click handler; it also runs the layout until it
  -- has worked.
  data.laidOut = core.allocate(4, true)
  wr32(data.laidOut, (#rows == 0 and #places == 0) and 1 or 0)
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

  data.rockTabs = #rockTabs
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
-- Code patches
---------------------------------------------------------------------------------------

-- Replaces size bytes at site with a jump to stub, remembering them for disable.
local function patchJump(self, site, size, stub)
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, size) })
  core.writeCode(site, jumpTo(site, stub, size))
end

local function patchTrees(self, G, O, data)
  local randomShrubs = O.shrubs and O.randomMix
  local randomTrees = O.felled and O.randomMix
  if O.apple or randomShrubs then
    patchJump(self, G.treeTypeOf, #TREE_TYPE_START, core.allocateAssembly(templates.plantType, {
      APPLE_COMMAND = O.apple and APPLE_COMMAND or 0xFFFFFFFF, APPLE_TYPE = APPLE_TYPE,
      RANDOM_SHRUB = data.randomShrub, FIRST_SHRUB = SHRUB_COMMANDS[1],
      LAST_SHRUB = SHRUB_COMMANDS[#SHRUB_COMMANDS], SEED = data.seed, RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER,
      RANDOM_INCREMENT = K.RANDOM_INCREMENT, CONVERTER_BACK = G.treeTypeOf + #TREE_TYPE_START,
    }))
  end
  if O.growth or randomTrees then
    local brush = G.brush
    if not O.growth then                       -- the game's own stage, as a brush size
      brush = core.allocate(4, true)
      wr32(brush, PLACED_STAGE + 1)
    end
    patchJump(self, G.placeTree, PLACE_TREE.stageSize, core.allocateAssembly(templates.stageFromBrush, {
      BRUSH = brush, MAX_STAGE = MAX_STAGE, STAGE = core.allocate(4, true),
      FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand, RANDOM_STANDING = K.RANDOM_STANDING,
      COMMAND_ON_STACK = PLACE_TREE.command, MOST_RANDOM_STAGE = K.MOST_RANDOM_STAGE, SEED = data.seed,
      SMALLEST_FELLED_STAGE = K.SMALLEST_FELLED_STAGE,
      RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER, RANDOM_INCREMENT = K.RANDOM_INCREMENT,
      BACK = G.placeTree + PLACE_TREE.stageSize,
    }))
  end
  if O.felled then
    local site = G.placeTree + PLACE_TREE.created
    patchJump(self, site, PLACE_TREE.createdSize, core.allocateAssembly(templates.felledTree, {
      FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      COMMAND_ON_STACK = PLACE_TREE.command, TREE_SIZE = G.treeSize,
      TREES = G.landscape + TREES_IN_LANDSCAPE, TREE_TYPE = TREE.TYPE, LAST_TREE_TYPE = LAST_TREE_TYPE,
      STAGES = STAGES, TREE_STAGE = TREE.STAGE, LOGS = G.logs, TREE_LYING = TREE.LYING,
      LYING_FELLED = LYING_FELLED, TREE_LOGS = TREE.LOGS, TREE_CHOPS = TREE.CHOPS,
      LANDSCAPE = G.landscape, UPDATE_TREE = G.updateTree, RANDOM_STANDING = K.RANDOM_STANDING,
      RANDOM_FELLED = K.RANDOM_FELLED, SEED = data.seed, RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER,
      RANDOM_INCREMENT = K.RANDOM_INCREMENT, BACK = site + PLACE_TREE.createdSize,
    }))
  end
  if O.obstacles then
    local site = scan(K.AOB_OBSTACLES, "the tree placement's obstacle check")
    if site < G.placeTree - K.OBSTACLES_NEAR or site > G.placeTree + K.OBSTACLES_NEAR then
      error(MODULE_NAME .. ": the obstacle check is not in the tree placement")
    end
    local past = site + K.OBSTACLES_SIZE + (rd8(site + K.OBSTACLES_JUMP) & 0xFF)
    patchJump(self, site, K.OBSTACLES_SIZE, core.allocateAssembly(templates.nearObstacles, {
      FLAG = data.nearObstacles, CHECK = site + K.OBSTACLES_SIZE, PAST_CHECK = past,
    }))
  end
end

-- The rock number the editor places and previews follows the variant row.
local function patchRocks(self, G, data)
  local function rockId(site, size, tail)
    return core.allocateAssembly(templates.rockId .. tail .. "\njmp BACK\n", {
      ROCK_LOCK = data.rockLock, SIZE = G.chosenRockSize, VARIANT = G.rockVariant,
      EXTRA_VARIANT = K.EXTRA_VARIANT, EXTRA_ID = K.EXTRA_ID, PARAM3 = G.rockParam, MOUSE_Y = G.mouseTileY,
      BACK = site + size,
    })
  end
  patchJump(self, G.rockPlace, K.ROCK_PLACE.size, rockId(G.rockPlace, K.ROCK_PLACE.size, "mov [PARAM3],ecx"))
  patchJump(self, G.rockPreview, K.ROCK_PREVIEW.size, rockId(G.rockPreview, K.ROCK_PREVIEW.size, "mov edx,[MOUSE_Y]"))
end

-- With the invisible rocks check box on, placeRock gets rock 0 instead of a new rock.
function C.patchInvisibleRocks(self, data)
  local site = scan(K.AOB_CREATE_ROCK_CALL, "the rock placement's createRock call") + K.CREATE_ROCK_CALL
  local stub = core.allocateAssembly(templates.invisibleRocks, {
    FLAG = data.invisibleRocks, CREATE_ROCK = readCallTarget(site, 0, "createRock"),
    ROCK_ARGUMENTS = K.CREATE_ROCK_ARGUMENTS,
  })
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, 5) })
  core.writeCode(site, { 0xE8, core.itob(core.getRelativeAddress(site, stub, -5)) })
end

-- The eraser frees an invisible rock's tile the way removing a rock frees the rock's tiles: the
-- rock flag and the tile's rock number go.
function C.patchEraser(self)
  local tables = scan(K.AOB_ERASE_TABLES, "the eraser's map tables")
  local sites, from = {}, 0x400000
  while #sites <= K.ERASE_SITES do
    local ok, found = pcall(core.scanForAOB, K.AOB_ERASE_ROCK, from, K.HERD_SEARCH_END)
    if not ok or found == nil or found == 0 then break end
    sites[#sites + 1] = found
    from = found + 1
  end
  if #sites ~= K.ERASE_SITES then error(MODULE_NAME .. ": the eraser is not the one this module knows") end
  for _, found in ipairs(sites) do
    local site = found + K.ERASE_ROCK.site
    patchJump(self, site, K.ERASE_ROCK.size, core.allocateAssembly(templates.eraseInvisible, {
      ROCK_BASE = rd32(found + K.ERASE_ROCK.base), FLAGS = rd32(tables + K.ERASE_TABLES.flags),
      NUMBERS = rd32(tables + K.ERASE_TABLES.numbers), KEEP_FLAGS = (~K.ROCK_TILE_FLAG) & 0xFFFFFFFF,
      REMOVE_ROCK = readCallTarget(site, K.ERASE_ROCK.call, "removeRock"), BACK = site + K.ERASE_ROCK.size,
    }))
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

local function enableMenu(self, O)
  local G = {}
  resolveMenu(G)
  resolveDrawing(G)
  resolveCounters(G)
  if O.variants then
    local ok, problem = pcall(resolveRocks, G)
    if not ok then
      log(WARNING, tostring(problem) .. "; no rock variant row")
      O.variants = false
    end
  end
  if O.herds then
    local ok, problem = pcall(resolveHerds, G)
    if not ok then
      log(WARNING, tostring(problem) .. "; no herd panel")
      O.herds = false
    end
  end
  local newTable, data = buildTable(G, O)
  installTable(G, newTable)
  patchTrees(self, G, O, data)
  if data.rockTabs > 0 then patchRocks(self, G, data) end
  if O.herds then patchHerds(self, G, data) end
  if O.invisibleRocks then C.patchInvisibleRocks(self, data) end
  self.shownFlag = data.shown
  self.landscape = G
  log(INFO, string.format("%s: editor menu changed (menu 0x%X, items 0x%X -> 0x%X; %d tree, %d rock, "
    .. "%d group slots)", MODULE_NAME, G.menu, G.table, newTable, G.treeSlots, G.rockSlots, G.groupSlots))
end

-- Skirmish maps get the Rocks tab with the signpost: the jl past `mov eax, 239` always jumps.
local function enableSignpost(self)
  local site = scan(K.AOB_SIGNPOST, "the Rocks button") + K.SIGNPOST_JUMP
  expectBytes(site, { K.JL_SHORT }, "the Rocks button")
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = { K.JL_SHORT } })
  core.writeCode(site, { K.JMP_SHORT })
end

-- The random rotation button sets mode 0, which the preview follows, instead of 5.
local function enableRandomPreview(self)
  local site = scan(K.AOB_RANDOM_ROCK, "the random rock button") + K.RANDOM_ROCK_MODE
  expectBytes(site, { 0x89, 0x0D }, "the random rock button")
  patchJump(self, site, K.RANDOM_ROCK_MODE_SIZE, core.allocateAssembly(templates.randomRockMode, {
    MODE = rd32(site + 2), BACK = site + K.RANDOM_ROCK_MODE_SIZE,
  }))
end

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
-- surface (the minimap's right edge, just above the panel).
function C.makeCounts(G, B, counts)
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
    local right = rd32(B.menu + MENU_X) + B.minimapX + B.minimapWidth + rd32(G.cameraX)
    local left = right - widest - 2 * TOOLTIP_PADDING
    local bottom = rd32(B.menu + MENU_Y) + PANEL_BOTTOM - PANEL_GAP + rd32(G.cameraY)
    local top = bottom - #texts * TOOLTIP_LINE - TOOLTIP_PADDING
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
          if entry.flag ~= nil then chosen = chosen and rd32(entry.flag) == entry.value end
          list[i] = { item = panel.items[i], image = image, label = entry.label, param = param, chosen = chosen }
          if entry.compose ~= nil then
            list[i].image, list[i].picture = nil, entry.compose()
            if list[i].picture == nil then return {} end     -- its pictures are not loaded yet
          end
        end
        list.shift = row.shift or panel.shift
        return list
      end
    end
    return {}
  end
end

-- Copies the build menu's item table with the module's items added, like buildTable.
function C.build(G, B, O)
  local data = { shown = core.allocate(4, true) }
  local inserts = {}
  local function insert(before, kind)
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], kind)
  end
  insert(0, "guard")
  if O.buildingCounts then insert(B.firstBlock, "counts") end
  local panels = {}
  local function lookup(tab, command) return B.buttons[tab][command].image end
  if O.towerRuins then
    local row = {}
    for i, ruin in ipairs(K.TOWER_RUINS) do
      row[i] = { command = ruin, image = lookup(K.TAB_TOWERS, K.FIRST_TOWER + i - 1), label = K.RUIN_LABEL }
    end
    panels[#panels + 1] = { tab = K.TAB_TOWERS, rows = { row }, shift = K.PANEL_SHIFT[K.TAB_TOWERS] }
  end
  if O.armyExtras then
    -- The tunnel entrance as the map shows it, composed from its tiles like a rock.
    local sprites = scan(K.AOB_BUILDING_SPRITES, "the building pictures")
    local convert = core.exposeCode(readCallTarget(sprites, 0, "the building types"), 2, 1)
    local firstPicture = core.exposeCode(readCallTarget(sprites, K.BUILDING_SPRITES.sprite, "the building pictures"), 2, 1)
    local tunnelGm = rd32(rd32(sprites + K.BUILDING_SPRITES.gms) + (convert(B.buildings, K.TUNNEL_COMMAND) & 0xFFFF) * 4)
    local tunnelBase = firstPicture(B.buildings, K.TUNNEL_COMMAND)
    if G.footprint == nil then resolveRocks(G) end
    local tilePicture = makeRockPictures(G)
    local tunnel = { when = K.TUNNEL_WHEN, { command = K.TUNNEL_COMMAND, label = K.TUNNEL_LABEL,
      compose = function() return tilePicture(K.TUNNEL_SIZE, tunnelBase, 0, tunnelGm, true) end } }
    local tents = { when = K.TENTS_WHEN, shift = K.TENTS_SHIFT }
    for i, tent in ipairs(K.TENTS) do
      tents[i] = { command = tent, image = lookup(K.TAB_UNIT_COMMANDS, tent) }
    end
    panels[#panels + 1] = { tab = K.TAB_ARMY, rows = { tunnel, tents } }
  end
  if O.statues then
    local row = {}
    for i, statue in ipairs(K.STATUES) do
      row[i] = { command = statue[1], image = lookup(K.TAB_GOOD, statue[2]), label = statue[3] }
    end
    panels[#panels + 1] = { tab = K.TAB_GOOD, rows = { row }, shift = K.PANEL_SHIFT[K.TAB_GOOD] }
  end
  data.keepMode = core.allocate(4, true)
  data.damagedWalls = core.allocate(4, true)
  local resets = {}                        -- menu buttons that end a panel choice: { tab, command, flag }
  local function choices(tab, commands, flag, labels)
    local images, when, row = {}, {}, {}
    for _, command in ipairs(commands) do
      images[command], when[command] = lookup(tab, command), true
      resets[#resets + 1] = { tab, command, flag }
    end
    row.when = when
    for _, choice in ipairs(labels) do
      row[#row + 1] = { images = images, label = choice[2], flag = flag, value = choice[1] }
    end
    panels[#panels + 1] = { tab = tab, rows = { row }, shift = K.PANEL_SHIFT[tab] }
  end
  if O.keepParts then
    choices(K.TAB_KEEPS, K.KEEPS, data.keepMode, { { K.KEEP_ONLY, K.KEEP_LABELS[K.KEEP_ONLY] },
      { K.KEEP_NO_STOCKPILE, K.KEEP_LABELS[K.KEEP_NO_STOCKPILE] } })
  end
  if O.damagedWalls then choices(K.TAB_CASTLE, K.WALLS, data.damagedWalls, { { 1, K.DAMAGED_LABEL } }) end
  for p, panel in ipairs(panels) do
    local most = 0
    for _, row in ipairs(panel.rows) do most = math.max(most, #row) end
    panel.size = most
    for i = 1, most do insert(B.blockEnd[panel.tab], "panel" .. p .. "/" .. i) end
    insert(B.blockEnd[panel.tab], "painter" .. p)
  end
  if O.barrier then insert(B.blockEnd[K.TAB_RUINS], "barrier") end

  local total = B.count + 1
  for _, list in pairs(inserts) do total = total + #list end
  local newTable = core.allocate(total * MENU_ITEM_SIZE, true)
  local movedTo, added, slot = {}, {}, 0
  for i = 0, B.count do
    for _, kind in ipairs(inserts[i] or {}) do
      added[kind] = item(newTable, slot)
      slot = slot + 1
    end
    core.writeBytes(item(newTable, slot), core.readBytes(item(B.table, i), MENU_ITEM_SIZE))
    movedTo[i] = slot
    slot = slot + 1
  end

  local guarded, places = {}, {}
  if G.blit == nil then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local GB = setmetatable({ menu = B.menu }, { __index = G })   -- G with the build menu
  -- The toolbar action takes the siege tents for an order to selected engineers: those are
  -- chosen straight away, like the game's hotkeys do.
  local direct = core.allocateAssembly(templates.directTool, {
    DIRECT = dwordList(K.TENTS), SUBTYPE = G.subtype, TOOLBAR = B.toolbar,
  })
  for p, panel in ipairs(panels) do
    panel.items = {}
    for i = 1, panel.size do
      local into = added["panel" .. p .. "/" .. i]
      local entry = panel.rows[1][i]
      local action = direct
      if #panel.rows == 1 and entry ~= nil and entry.flag ~= nil then
        action = core.allocateAssembly(templates.setChoice, { FLAG = entry.flag, VALUE = entry.value, ACTION = B.toolbar })
      end
      wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
      wr32(into + ITEM_ACTION, action)
      wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
      wr16(into + ITEM_HIDDEN, 1)
      panel.items[i] = into
      guarded[#guarded + 1] = into
      guarded[#guarded + 1] = panel.tab
    end
    local paint = makePanel(GB, { counts = false }, data, panel, C.makeEntries(GB, panel, panel.rows))
    local painter = added["painter" .. p]
    wr32(painter + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(painter + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(painter + ITEM_RENDER, core.allocateAssembly(templates.editorPanel, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, PANEL_ITEMS = dwordList(panel.items),
      ITEM_HIDDEN = ITEM_HIDDEN, PAD = C.luaPad(paint, "a castle panel"),
    }))
  end

  if O.buildingCounts then
    local counts = core.allocate(12, true)
    local count = core.allocateAssembly(templates.buildingCounts, {
      BUILDINGS = B.buildings, MAX_BUILDINGS = K.MAX_BUILDINGS, FIRST_STATE = B.firstState,
      BUILDING_SIZE = B.buildingSize, TYPE_FROM_STATE = B.typeFromState, OWNER_FROM_STATE = B.ownerFromState,
      REMOVED = K.BUILDING_REMOVED, PLAYER_TYPES = B.playerTypes, CURRENT_PLAYER = B.currentPlayer, COUNTS = counts,
    })
    local into = added.counts
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.editorOnly, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FIRST = count,
      PAD = C.luaPad(C.makeCounts(G, B, counts), "the building counts"),
    }))
  end

  -- The barrier: a copy of the first ruin button with the barrier's command, placed in the
  -- free spot at the end of the ruins' grid once the menu has placed them.
  if O.barrier then
    local barrier = added.barrier
    local model = B.buttons[K.TAB_RUINS][K.FIRST_RUIN]
    core.writeBytes(barrier, core.readBytes(item(B.table, model.index), MENU_ITEM_SIZE))
    wr32(barrier + ITEM_X, 0)
    wr32(barrier + ITEM_Y, 0)
    wr32(barrier + ITEM_PARAM, K.BARRIER_COMMAND)
    wr32(barrier + ITEM_ACTION, B.toolbar)
    wr32(barrier + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr16(barrier + ITEM_CONTROL, -1)
    wr16(barrier + ITEM_HIDDEN, 1)
    local draw = C.makeBarrier(G)
    wr32(barrier + ITEM_RENDER, C.luaPad(function() draw(barrier) end, "the barrier button"))
    local ruins = {}
    for _, button in pairs(B.buttons[K.TAB_RUINS]) do ruins[#ruins + 1] = item(newTable, movedTo[button.index]) end
    places[#places + 1] = function(measure)
      local width, height = measure(ruins[1])
      if width == nil then return false end
      local xs, ys, taken = {}, {}, {}
      for _, ruin in ipairs(ruins) do
        local x, y = rd32(ruin + ITEM_X), rd32(ruin + ITEM_Y)
        if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
        xs[x], ys[y], taken[x .. "/" .. y] = true, true, true
      end
      local columns, rows = {}, {}
      for x in pairs(xs) do columns[#columns + 1] = x end
      for y in pairs(ys) do rows[#rows + 1] = y end
      table.sort(columns)
      table.sort(rows)
      local y = rows[#rows]
      local x = nil
      for _, column in ipairs(columns) do
        if not taken[column .. "/" .. y] then x = column end
      end
      if x == nil then                         -- no free spot: one column further right
        x = columns[#columns] + (#columns > 1 and columns[#columns] - columns[#columns - 1] or width)
      end
      wr32(barrier + ITEM_X, x)
      wr32(barrier + ITEM_Y, y)
      wr32(barrier + ITEM_WIDTH, width)
      wr32(barrier + ITEM_HEIGHT, height)
      wr16(barrier + ITEM_HIDDEN, 0)
      return true
    end
  end

  for _, reset in ipairs(resets) do
    local button = B.buttons[reset[1]][reset[2]]
    wr32(item(newTable, movedTo[button.index], ITEM_ACTION), core.allocateAssembly(templates.rockButton, {
      ROCK_LOCK = reset[3], ACTION = button.action,
    }))
  end

  -- The guard in front of the click handlers, which also places the barrier.
  local laidOut = core.allocate(4, true)
  wr32(laidOut, #places == 0 and 1 or 0)
  local layout = makeLayout(G, {}, {}, {}, places)
  local layoutPad = C.luaPad(function()
    if layout() then wr32(laidOut, 1) end
  end, "the castle layout")
  local guard = added.guard
  wr32(guard + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(guard + ITEM_ACTION, core.allocateAssembly(templates.guard, {
    LAID_OUT = laidOut, LAYOUT = layoutPad, GUARDED = dwordList(guarded),
    ACTIVE_TAB = G.activeTab, ITEM_HIDDEN = ITEM_HIDDEN, ITEM_HEIGHT = ITEM_HEIGHT,
    ITEM_WIDTH = ITEM_WIDTH, ITEM_MENU = ITEM_MENU, MENU_X = MENU_X, MENU_Y = MENU_Y, ITEM_X = ITEM_X,
    ITEM_Y = ITEM_Y, MOUSE = G.mouse, IS_MOUSE_INSIDE = G.isMouseInside, ON_MAP = G.onMap,
  }))
  return newTable, data
end

function C.signedByte(address)
  local value = rd8(address) & 0xFF
  if value >= 0x80 then value = value - 0x100 end
  return value
end

-- A lua function called from injected code: a pad that runs it, switched off after an error.
function C.luaPad(fn, what)
  local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  local broken = false
  core.detourCode(function(registers)
    if not broken then
      local ok, problem = pcall(fn)
      if not ok then
        broken = true
        log(WARNING, string.format("%s: %s stopped after an error: %s", MODULE_NAME, what, tostring(problem)))
      end
    end
    return registers
  end, pad, 5)
  return pad
end

-- Replaces the call at site with a call to stub, remembering it for disable.
function C.patchCall(self, site, stub)
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, 5) })
  core.writeCode(site, { 0xE8, core.itob(core.getRelativeAddress(site, stub, -5)) })
end

-- In the map editor, a player's new keep (and unique buildings: barracks, guilds, ...) no longer
-- destroys the earlier one, and further storage buildings need not touch the first.
function C.patchSeveralBuildings(self, G, O)
  local start = scan(K.AOB_EARLIER_BUILDING, "the earlier building removal")
  local calls, from = {}, start
  while #calls < 3 do
    local ok, found = pcall(core.scanForAOB, K.EARLIER_DESTROY, from, start + K.EARLIER_SEARCH)
    if not ok or found == nil or found == 0 then break end
    calls[#calls + 1] = found + K.EARLIER_DESTROY_CALL
    from = found + 1
  end
  if #calls ~= 3 then error(MODULE_NAME .. ": the earlier building removal is not the one this module knows") end
  local stub = core.allocateAssembly(templates.keepEarlier, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, DESTROY = readCallTarget(calls[1], 0, "destroyBuilding"),
    DESTROY_ARGUMENTS = K.DESTROY_ARGUMENTS,
  })
  local which = {}
  if O.severalKeeps then for _, i in ipairs(K.EARLIER_KEEP_CALLS) do which[#which + 1] = i end end
  if O.looseBuildings then for _, i in ipairs(K.EARLIER_UNIQUE_CALLS) do which[#which + 1] = i end end
  for _, i in ipairs(which) do C.patchCall(self, calls[i], stub) end
  if O.looseBuildings then
    local sites = {}
    for i, pattern in ipairs(K.AOB_STORAGE_NEIGHBOURS) do
      sites[i] = scan(pattern, "the storage placement test") + K.STORAGE_NEIGHBOUR_CALL
    end
    local neighbour = core.allocateAssembly(templates.anyNeighbour, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HAS_NEIGHBOUR = readCallTarget(sites[1], 0, "the neighbour test"),
      NEIGHBOUR_ARGUMENTS = K.NEIGHBOUR_ARGUMENTS,
    })
    for _, site in ipairs(sites) do C.patchCall(self, site, neighbour) end
  end
end

-- In the map editor the tower mangonel and ballista can also be put on any tile without a unit
-- (ground, walls, gates, other towers, the keep): the click sends the game's own spawn command
-- for the clicked tile instead of refusing. The player's own big towers work as before.
function C.patchTowerEngines(self, G)
  local T = K.TOWER_ENGINE
  local from, sites = 0x400000, {}
  while #sites < 3 do
    local ok, found = pcall(core.scanForAOB, K.AOB_TOWER_ENGINE_CLICK, from, K.HERD_SEARCH_END)
    if not ok or found == nil or found == 0 then break end
    sites[#sites + 1] = found
    from = found + 1
  end
  if #sites ~= 2 then error(MODULE_NAME .. ": the tower engine placement is not the one this module knows") end
  for _, site in ipairs(sites) do
    local function operand(field) return readOperand(site, T[field], "the tower engine placement") end
    expectBytes(site + T.refuse[1] - 2, T.refuse[2], "the tower engine placement")
    expectBytes(site + T.command[1], T.command[2], "the tower engine placement")
    local stub = core.allocateAssembly(templates.towerEngineGround, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, BUILDING_SIZE = operand("buildingSize"),
      OWNERS = operand("owners"), TYPES = operand("types"), CURRENT_PLAYER = operand("player"),
      TOWER_4 = K.TOWER_4, TOWER_5 = K.TOWER_5, UNIT_TILES = operand("units"), HEIGHTS = operand("heights"),
      PARAM0 = operand("param0"), PARAM1 = operand("param1"), PARAM2 = operand("param2"),
      PARAM3 = operand("param3"), UNIT_TYPE = rd32(site + T.param3[1] + 6),
      COMMAND = rd8(site + T.command[1] + 1) & 0xFF, SYNC = operand("sync"),
      QUEUE = readCallTarget(site, T.queue, "the command queue"), EPILOGUE = site + T.epilogue,
      TOWER_PATH = site + T.size, REFUSE = site + T.size + rd32(site + 4),
    })
    patchJump(self, site, T.size, stub)
  end
end

-- The keep panel's choices: in the map editor placeKeep stops after the keep and its doors
-- (keep only) or before the stockpile.
function C.patchKeepParts(self, G, data)
  local campfire = scan(K.AOB_KEEP_CAMPFIRE, "the keep's campfire area")
  local stockpile = scan(K.AOB_KEEP_STOCKPILE, "the keep's stockpile")
  local epilogue = stockpile + K.KEEP_EPILOGUE[1]
  expectBytes(epilogue, K.KEEP_EPILOGUE[2], "the end of placeKeep")
  local function stop(site, size, modes, replay)
    patchJump(self, site, size, core.allocateAssembly(templates.keepPart .. replay .. "\njmp BACK\n", {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, KEEP_MODE = data.keepMode, FIRST_MODE = modes[1],
      SECOND_MODE = modes[2] or modes[1], EPILOGUE = epilogue, BACK = site + size, TABLE = rd32(site + 7),
    }))
  end
  stop(campfire, K.KEEP_CAMPFIRE_SIZE, { K.KEEP_ONLY }, "mov eax,[esp+0x3C]\nmov ecx,[esp+0x48]")
  stop(stockpile, K.KEEP_STOCKPILE_SIZE, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x3C]\nmov edi,[eax*8+TABLE]")

  -- The placement check and the preview leave out the same parts.
  local function leaveOut(site, size, modes, replay, done, table)
    patchJump(self, site, size, core.allocateAssembly(templates.keepPart .. replay .. "\njmp BACK\n", {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, KEEP_MODE = data.keepMode, FIRST_MODE = modes[1],
      SECOND_MODE = modes[2] or modes[1], EPILOGUE = done, BACK = site + size, TABLE = table,
    }))
  end
  local KC, KP = K.KEEP_CHECK, K.KEEP_PREVIEW
  local check = scan(K.AOB_KEEP_CHECK, "the keep placement check")
  local checkStockpile = check + KC.stockpile
  expectBytes(checkStockpile, { 0x8B, 0x44, 0x24, 0x4C, 0x8B, 0x98 }, "the keep placement check")
  expectBytes(checkStockpile + KC.done, KC.doneBytes, "the end of the placement check")
  local preview = scan(K.AOB_KEEP_PREVIEW, "the keep preview")
  local previewStockpile = scan(K.AOB_KEEP_PREVIEW_STOCKPILE, "the keep preview")
  expectBytes(previewStockpile + KP.done, KP.doneBytes, "the keep preview")
  leaveOut(check, KC.size, { K.KEEP_ONLY }, "mov eax,[esp+0x48]\nshl eax,5", checkStockpile + KC.done, 0)
  leaveOut(checkStockpile, KC.stockpileSize, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x4C]\nmov ebx,[eax+TABLE]",
    checkStockpile + KC.done, rd32(checkStockpile + KC.table))
  leaveOut(preview, KP.size, { K.KEEP_ONLY }, "shl edx,5\nadd ebp,[edx+TABLE]", previewStockpile + KP.done,
    rd32(preview + KP.table))
  leaveOut(previewStockpile, KP.stockpileSize, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x38]\nmov ebp,[eax+TABLE]",
    previewStockpile + KP.done, rd32(previewStockpile + KP.stockpileTable))
end

-- The game's language for the names it has no text for: German or English.
function C.language()
  local file = io.open(K.TEXT_FILE, "rb")
  if file == nil then return "en" end
  local data = file:read("a")
  file:close()
  if #data < K.TEXT_START + 4 * K.TEXT_GROUPS then return "en" end
  local at = K.TEXT_START + 1 + 2 * string.unpack("<I4", data, 1 + 4 * K.TEXT_GROUP)
  local index = 0
  while index < K.TEXT_INDEX and at < #data do
    if data:byte(at) == 0 and data:byte(at + 1) == 0 then index = index + 1 end
    at = at + 2
  end
  local chars = {}
  while at < #data and not (data:byte(at) == 0 and data:byte(at + 1) == 0) and #chars < 32 do
    chars[#chars + 1] = data:sub(at, at)
    at = at + 2
  end
  return table.concat(chars) == K.GERMAN_TEXT and "de" or "en"
end

-- Damaged walls: in the map editor, with the choice on, every wall tile placeWalls builds or
-- repairs gets the damaged look (its damage byte; the height stays).
function C.patchDamagedWalls(self, G, data)
  local site = scan(K.AOB_WALL_TILE_DONE, "the wall placement")
  local damage = rd32(scan(K.AOB_WALL_DAMAGE, "the wall drawing") + K.WALL_DAMAGE_OPERAND)
  patchJump(self, site, K.WALL_TILE_DONE_SIZE, core.allocateAssembly(templates.damagedWall, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FLAG = data.damagedWalls, DAMAGE = damage,
    CLEAR_MOAT = readCallTarget(site, K.WALL_CLEAR_MOAT_CALL, "the wall placement"),
    BACK = site + K.WALL_TILE_DONE_SIZE,
  }))
end

-- Tower ruins get the size of their tower (the game has none for them) in the map editor.
function C.patchRuinSizes(self, G)
  local size = scan(K.AOB_BUILDING_SIZE, "the building sizes")
  patchJump(self, size, K.BUILDING_SIZE_START, core.allocateAssembly(templates.ruinSize, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FIRST_RUIN = K.TOWER_RUINS[1],
    LAST_RUIN = K.TOWER_RUINS[#K.TOWER_RUINS], TOWER_FROM_RUIN = K.TOWER_RUINS[1] - K.FIRST_TOWER,
    SIZE_BASE = C.signedByte(size + 6) & 0xFFFFFFFF, BACK = size + K.BUILDING_SIZE_START,
  }))
end

function C.enable(self, O)
  -- What the landscape menu found, if it ran: its constructor no longer pushes the table the
  -- search looks for once the module's copy is in.
  local G = self.landscape
  if G == nil then
    G = {}
    resolveMenu(G)
    resolveDrawing(G)
  end
  local B = C.resolve(G)
  local data = nil
  if O.buildingCounts or O.towerRuins or O.armyExtras or O.statues or O.barrier or O.keepParts or O.damagedWalls then
    local newTable
    newTable, data = C.build(G, B, O)
    core.writeCodeInteger(B.site + 1, newTable)
    local construct = core.exposeCode(B.constructor, 2, 1)
    local function ensure()
      if rd32(B.menu) == B.table then construct(B.menu, newTable) end
    end
    ensure()
    hooks.registerHookCallback("afterInit", ensure)
  end
  -- Each patch on its own, so that one the game does not match leaves the others working.
  local function try(wanted, patch, what, ...)
    if not wanted then return end
    local ok, problem = pcall(patch, self, ...)
    if not ok then log(WARNING, tostring(problem) .. "; " .. what .. " left out") end
  end
  try(O.towerRuins, C.patchRuinSizes, "tower ruins", G)
  try(O.severalKeeps or O.looseBuildings, C.patchSeveralBuildings, "several keeps and storage buildings", G, O)
  try(O.towerEngines, C.patchTowerEngines, "tower engines anywhere", G)
  try(O.keepParts, C.patchKeepParts, "the keep choices", G, data)
  try(O.damagedWalls, C.patchDamagedWalls, "damaged walls", G, data)
  log(INFO, string.format("%s: build menu changed (menu 0x%X, items 0x%X)", MODULE_NAME, B.menu, B.table))
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
  patchJump(self, site, MENU_REDRAW_SIZE, stub)
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
    obstacles = setting(config, "trees", "obstacles") == true,
    sortedRows = setting(config, "trees", "sorted_rows") == true,
    randomMix = setting(config, "trees", "random_mix") == true,
    textures = setting(config, "textures", "gravel_and_iron") == true,
    variants = setting(config, "rocks", "variants") == true,
    extraRock = setting(config, "rocks", "extra_rock") == true,
    herds = setting(config, "herds", "panel") == true,
    invisibleRocks = setting(config, "rocks", "invisible") == true,
  }
  local castle = {
    buildingCounts = setting(config, "castle", "building_counts") == true,
    towerRuins = setting(config, "castle", "tower_ruins") == true,
    armyExtras = setting(config, "castle", "tunnel_and_tents") == true,
    statues = setting(config, "castle", "statues_and_shrines") == true,
    barrier = setting(config, "castle", "barrier") == true,
    severalKeeps = setting(config, "castle", "several_keeps") == true,
    looseBuildings = setting(config, "castle", "several_storage_and_recruitment") == true,
    towerEngines = setting(config, "castle", "tower_engines_anywhere") == true,
    keepParts = setting(config, "castle", "keep_parts") == true,
    damagedWalls = setting(config, "castle", "damaged_walls") == true,
  }
  if O.counts or O.growth or O.apple or O.shrubs or O.felled or O.obstacles or O.sortedRows or O.textures
      or O.variants or O.herds or O.invisibleRocks then
    local ok, problem = pcall(enableMenu, self, O)
    if not ok then log(WARNING, tostring(problem) .. "; the editor menu is left as it is") end
  end
  if castle.buildingCounts or castle.towerRuins or castle.armyExtras or castle.statues or castle.barrier
      or castle.severalKeeps or castle.looseBuildings or castle.towerEngines or castle.keepParts
      or castle.damagedWalls then
    local ok, problem = pcall(C.enable, self, castle)
    if not ok then log(WARNING, tostring(problem) .. "; the build menu is left as it is") end
  end
  if setting(config, "rocks", "signpost") == true then
    local ok, problem = pcall(enableSignpost, self)
    if not ok then log(WARNING, tostring(problem) .. "; skirmish maps keep their own Rocks menu") end
  end
  if setting(config, "rocks", "erase_invisible") == true then
    local ok, problem = pcall(C.patchEraser, self)
    if not ok then log(WARNING, tostring(problem) .. "; the eraser leaves invisible rocks") end
  end
  if setting(config, "rocks", "random_preview") == true then
    local ok, problem = pcall(enableRandomPreview, self)
    if not ok then log(WARNING, tostring(problem) .. "; the random rotation is left as it is") end
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

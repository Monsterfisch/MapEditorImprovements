local templates = require("templates")
local png = require("png")

local MODULE_NAME = "map-editor-improvements"
local MODULE_FOLDERS = { "ucp/modules/map-editor-improvements/" }   -- UCP maps this to the active version

local DEFAULTS = {
  counts = { enabled = false, shown = false },
  menu = { always_update = false, dust_clouds = false, compass = false, compass_turn = false },
  trees = { growth_from_brush = false, apple = false, shrubs = false, felled = false, random_mix = false, preview = false,
    obstacles = false, no_shrub_stacking = false, spread_order = false, spread_outlines = false,
    rocks_and_water = false },
  textures = { gravel_and_iron = false, no_heights_iron = false, mask = false, mask_by_type = false },
  water = { decorations = false, foam_on_sea = false },
  brushes = { full_shape = false },
  undo = { enabled = false },
  pipette = { enabled = false, select_key_on = false, select_key = "letter_p", read_key_on = false, read_key = "ctrl",
    any_tile_key_on = false, any_tile_key = "alt" },
  rocks = { signpost = false, random_preview = false, variants = false, invisible = false,
    erase_invisible = false, remove_lost = false },
  castle = { building_counts = false, tower_ruins = false, tunnel_and_tents = false, statues_and_shrines = false,
    barrier = false, several_keeps = false, several_storage_and_recruitment = false, tower_engines_anywhere = false,
    keep_parts = false, damaged_walls = false, moat_kinds = false, moat_on_marsh = false,
    moat_removal_keeps_ground = false, variant_panels = false, ruined_cathedral = false, all_players = false,
    all_keeps = false, player_zero = false, keep_crests = false, keep_ground = false, rotation = false, unit_colour = false,
    wall_tools = false },
  herds = { panel = false, bird_bins = false, animal_bin = false, group_warning = false },
  eraser = { choice = false, seagulls = false },
  map_settings = { show_locked = false, menu = false, size_refresh = false, camera_edge = false },
  heights = { max_height = false, tool_options = false, invert_key_on = false, invert_key = "ctrl" },
  grid = { enabled = false, key = "letter_g", outside_editor = false, flattened_only = false, hide_in_v_view = false,
    grid_colour = "white", rotation_lines = false, rotation_colour = "cyan", mine_boxes = false, mine_colour = "red",
    mine_size = 4 },
}

---------------------------------------------------------------------------------------
-- What the game's code and data look like where this module touches them
---------------------------------------------------------------------------------------

-- The landscape editor's item table, found by its key button (item 11: a group member placed
-- by user control 146, command 152). The bytes in between are its action, 0 until the Menu
-- constructor has copied the group's action in.
local LANDSCAPE_KEY_RECORD = "03 00 00 02 00 00 00 80 92 00 00 00 00 00 00 00 00 00 00 00 ? ? ? ? 98 00 00 00"
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
K.ROCK_TURN_MODE = 6
K.AOB_ROCK_TURN = "8B 86 ? ? ? ? 50 55 57 51 D1 FB 03 5C 24 30 52 B9"
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

-- placeTree: `xor ebx,ebx / test eax,eax / mov [esp+0x10],esi / jle <past the check>`.
K.AOB_OBSTACLES = "33 DB 85 C0 89 74 24 10 7E 50 56 55 8D 44 24 18"
K.OBSTACLES_SIZE = 10
K.OBSTACLES_JUMP = 0x09
K.OBSTACLES_NEAR = 0x400               -- how far from placeTree's start the check lies at most
K.OBSTACLES_NUDGE = { -10, -20 }        -- the obstacles box, from its place at the end of the top row
K.ROCKS_AND_WATER_GAP = 4
-- placeTree's tile test `test dword [edi+ebp*4+LogicLayer], 0x703E25B5`; with Vegetation on rocks
-- and water these bits stay out of it: rocky, boulders, pebbles, river, ford, marsh.
K.AOB_TREE_GROUND = "F7 84 AF ? ? ? ? B5 25 3E 70"
K.TREE_GROUND = { size = 11, logic = 3, mask = 7, loose = 0x80 | 0x20000 | 0x40000 | 0x100000 | 0x200000 | 0x20000000 }

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
K.CREATE_ROCK_CALL, K.CREATE_ROCK_LANDSCAPE = 6, 2
K.CREATE_ROCK_ARGUMENTS = 0x14
K.CHECK_BOX_GAP = 8
-- Tooltips of the check boxes sit higher than the category tooltips (clear of the menu's top).
K.CHECK_BOX_TOOLTIP_RAISE = 20
-- Names the game has no text for, shown on the description line: German in a German game,
-- English otherwise.
K.NAMES = { apple = { en = "Apple tree", de = "Apfelbaum" }, gravel = { en = "Gravel", de = "Kies" } }
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
-- ... and its tree branch, `push eax / call removeTree` (the tile's tree; shrubs stacked on the
-- tile stay in the tree list). A tree's tile is 0x24 after its "in use" word.
K.ERASE_TREE = { site = 0x21, size = 6, call = 1, bytes = { 0x50, 0xE8 } }
K.TREE_TILE_FROM_IN_USE = 0x24
-- Shrub stacking: placeTree's obstacle check site follows `jne <refuse>` (a blocked tile).
K.OBSTACLES_REFUSE = { -6, { 0x0F, 0x85 } }
-- The water menu's two decorations (Stronghold's foam and small waves): commands the click
-- handler still sends to setTerrain as river with decoration 0x10 / 0x20, and the menu
-- pictures that are still in the image table (mapedit_buttons.gm1).
K.WATER = 236
K.RIVER = 14
K.WATER_DECORATIONS = { { command = 150, image = 286, name = "foam" }, { command = 151, image = 287, name = "waves" } }
K.NAMES.foam = { en = "Foam", de = "Gischt" }
K.NAMES.waves = { en = "Small waves", de = "Kleine Wellen" }
K.ROW_TOLERANCE = 20                     -- buttons whose middles are this close are one row
-- setTerrain in the map editor first turns the brush area to land for the land types (`cmp
-- [ebp+0x18], 0x40000000 / je <skip> / cmp [ebp+0x1C], 2 ...`), and 0x10 / 0x20 are among them:
-- river terrain (0x100000) with a decoration skips that, or the decoration finds no river.
K.AOB_TERRAIN_LAND = "83 3D ? ? ? ? 01 75 ? 81 7D 18 00 00 00 40 74 ? 83 7D 1C 02 74"
K.TERRAIN_LAND = { site = 9, size = 9 }
K.RIVER_TERRAIN = 0x100000
-- ... and in its tile loop, a decoration only goes on a river tile: `cmp [ebp+0x1C],0 / je /
-- mov edx,[ebp+0xC] / mov eax,[ebp-0x20] / mov ecx,[eax+edx*4+flags] / and ecx,0x100000 / jne
-- <river> / jmp <skip>`. Foam may also take an ocean tile (flag 1, the sea terrain's own flag,
-- which the river path clears).
K.AOB_DECORATION_TILE = "83 7D 1C 00 74 1A 8B 55 0C 8B 45 E0 8B 8C 90 ? ? ? ? 81 E1 00 00 10 00 75 05 E9"
K.DECORATION_TILE = { site = 0x0C, size = 15, flags = 3 }
K.FOAM, K.SEA_TILE = 0x10, 0x1
-- The brushes: getTileInSquareBrush(index, x, y) walks outwards from the cursor tile (four
-- directions, a visited mark per tile) and answers the index-th tile it reaches. It never marks
-- the cursor tile, so it comes back to it from the first ring and counts it twice: the last
-- tile of every brush (its top left corner on screen) is left out. At its start, `cmp [esp+
-- 0x1F60], ebp (index) / mov [esp+0x1C], eax / mov [esp+0xFBC], ecx (the tile) / jg <walk>`;
-- the visited marks: `movsx ebp, word [eax*2 + marks] / cmp ebp, [edi+4] (this walk's mark)`.
K.AOB_BRUSH_START = "39 AC 24 60 1F 00 00 89 44 24 1C 89 8C 24 BC 0F 00 00 7F"
K.BRUSH_START_SIZE = 18
K.AOB_BRUSH_MARKS = "0F BF 2C 45 ? ? ? ? 3B 6F 04 74"
K.BRUSH_MARKS = 4

-- Undo and redo. The map sections: `push SECTION TABLE / mov ecx, ... / mov [esp+0x50],edx /
-- mov [esp+0xBC],eax / call` (the map file's writer); entries { address, 0, size, number << 16 |
-- flag }, ending at address 0.
K.AOB_SECTION_TABLE = "68 ? ? ? ? B9 ? ? ? ? 89 54 24 50 89 84 24 BC 00 00 00 E8"
K.SECTION_TABLE = 1
K.SECTION = { address = 0, size = 8, stride = 16 }
K.MOST_SECTIONS = 1000
-- queueCommand, which every command of the player goes through before it is carried out:
-- `mov eax, [esi+0x6A4] / imul edx, edx, 0x4F8 / mov ebx, [esp+0x10] / mov [edx+esi+...], eax`
-- (+0x4B). The protocol module finds queueCommand by its first 0x45 bytes and hooks the six
-- calls through the command table, so neither is touched here.
K.AOB_QUEUE_COMMAND = "8B 86 ? ? ? ? 69 D2 F8 04 00 00 8B 5C 24 10 89 84 32"
K.QUEUE_COMMAND_SIZE = 6
-- The two buttons in the screen's top left corner (screen pixels; their items are moved there
-- every frame, whatever the menu's position), and a hidden item's place.
K.UNDO_BUTTONS = { left = 10, top = 10, gap = 8, padding = 4 }
K.FAR_AWAY = -100000
-- `push VK_DOWN / call [GetAsyncKeyState] / test ax,ax`: the mouse buttons' state.
K.AOB_ASYNC_KEY = "6A 28 FF 15 ? ? ? ? 66 85 C0"
K.ASYNC_KEY_IMPORT = 4
K.VK_LBUTTON, K.VK_RBUTTON = 0x01, 0x02
-- The commands that change the map (the command table's ids): erase, set land, raise land,
-- set terrain, equalize heights, height min/max, plateau, walls, rocks and trees, raise land 2,
-- buildings, destroy building, destroy, siege tents, animals, gates, repair tower, spawn
-- entity, remove tower engine, destroy wall or pitch. Others, like a click that only selects
-- (0x10), make no step.
K.MAP_EDITS = { 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x29, 0x2A, 0x2C,
  0x2D, 0x44, 0x45, 0x4B, 0x4C }
-- prepareMap's calls after loading a map, from `call / mov ecx, PATHFINDING / call linkTiles /
-- push edi / ...`; its `mov ecx, PATHFINDING` (forget) is where a new map clears the history.
-- (interface-visual-fixes patches prepareMap's first bytes.)
K.AOB_PREPARE_BLOCK = "E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 57 B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8"
K.PREPARE = { forget = 0x05, forgetSize = 5, pathFinding = 0x06, linkTiles = 0x0A, areas = 0x15, buildings = 0x1B, linkBuildings = 0x1F,
  climb = 0x29, cliffs = 0x4E, hovered = 0xD3, unhover = 0xDD, changedAll = -0xFB }
-- `push edi / mov ecx, MINIMAP / call triggerMinimapRedraw / mov eax, 2000 / mov ecx`.
K.AOB_MINIMAP_REDRAW = "57 B9 ? ? ? ? E8 ? ? ? ? B8 D0 07 00 00 B9"
K.MINIMAP_REDRAW = { object = 2, call = 6 }
K.UNDO_STEPS = 20
K.UNDO_GAP_BYTES = 16                     -- unchanged bytes that end a changed run
K.UNDO_SCRATCH = 16 * 1024 * 1024         -- the largest single step
K.UNDO_MOST_BYTES = 64 * 1024 * 1024      -- all steps together
-- Castle mode's building hover text ("Player 1's Keep"): RenderPlayerInfoOnHoverDisplayElement's
-- map editor branch, `mov eax,[esp+0x10] (x) / mov ecx,[hovered player]` before renderText.
K.AOB_HOVER_TEXT = "8B 44 24 10 8B 0D ? ? ? ? 53 6A 10 53 68 ? ? ? ? 6A 01 83 C5 EC 55 50"
K.HOVER_TEXT_SIZE, K.HOVER_TEXT_PLAYER, K.HOVER_TEXT_SHIFT = 10, 6, 100

-- Castle mode: the build menu (found by its minimap item, item 17), its tabs (the menu
-- category values) and the commands (placement ids) the module adds.
K.BUILD_MINIMAP_RECORD = "02 00 80 00 3B 02 00 00 D1 01 00 00 7E 00 00 00 7E 00 00 00 ? ? ? ? 39 30 00 00"
K.BUILD_MINIMAP_ITEM = 17
K.BUILD_MOST_ITEMS = 1000
K.MAP_EDITOR = 1                         -- GameMode2
-- The menu shown, GameCore.currentMenuViewType: the field right before the active tab
-- (GameCore.activeMenuTab, which G.activeTab reads; 0x1FE7D1C / 0x2A7B21C, as the game's own Alt+D
-- branch reads it). 12 is the landscape menu (MVT_MAP_EDITOR_LANDSCAPING), 14 the build menu.
K.MENU_VIEW_BEFORE_TAB, K.LANDSCAPE_VIEW = 4, 12
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
K.GM_NO_WORKERS_NAME = "66 6C 6F 61 74 73 5F 6E 65 77 00"           -- "floats_new"
K.GM_CHECK_BOXES_NAME = "69 6E 74 65 72 66 61 63 65 5F 69 63 6F 6E 73 33 00"   -- "interface_icons3"
K.GM_RECORD_SIZE = 1000
K.GM_CHECK_BOXES_ID = 156
K.AOB_GM_LIST = "6A 08 B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 53 6A 03"
K.GM_LIST = { address = 23 }
K.SCREEN_LAYER = 0
K.BUILD_NEEDED = {
  { 11, 110 }, { 11, 111 }, { 11, 112 }, { 11, 113 }, { 11, 114 }, { 14, 88 }, { 14, 89 }, { 15, 313 }, { 15, 318 },
  { 27, 248 }, { 61, 190 }, { 61, 191 }, { 61, 192 }, { 61, 193 }, { 61, 194 }, { 61, 358 },
  { 13, 60 }, { 13, 61 }, { 13, 62 }, { 10, 25 }, { 10, 26 }, { 10, 27 }, { 10, 46 },
}
-- The building list and convertCommandBuildingTypeToBuildingType, from the building table setup:
-- `mov [esi+..],ecx / push ebx / mov ecx, BuildingsState / call convert.. / mov edx,[eax*4+..]`.
-- BuildingsState + 8 is the list's size.
K.AOB_BUILDING_TABLE = "89 8E ? ? ? ? 53 B9 ? ? ? ? E8 ? ? ? ? 8B 14 85"
K.BUILDING_TABLE = { state = 8, convert = 12 }
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
-- The row kept free above the game's description line (editor/lane.lua): a check box row with its
-- padding, where controls that belong to the description go.
K.DESCRIPTION_ROW = K.CHECK_BOX_SIZE + 12
-- Buildings with variants. Placement gives setupBuildingData the variant (placement id - the
-- group's first), which keeps a value from its group's table at building +0x29C (BuildingsState
-- + id * stride + 0x2B0): `mov ecx,[esp+0x30] / mov edx,[ecx*4+GARDENS] / mov [edi+esi+0x2B0],
-- edx / ...`, then the same for ruins, cesspits, statues, shrines and ponds (by building type).
K.TAB_BAD, K.TAB_TOWN = 33, 30
K.VARIANT_GROUPS = {
  [0x42] = { first = 160, count = 12, table = 1, name = "garden" },
  [0x27] = { first = 248, count = 13, table = 2, name = "ruin" },
  [0x5B] = { first = 301, count = 4, table = 3, name = "cesspit" },
  [0x64] = { first = 313, count = 5, table = 4, name = "statue" },
  [0x65] = { first = 318, count = 5, table = 5, name = "shrine" },
  [0x68] = { first = 325, count = 4, table = 6, name = "pond" },
}
K.AOB_VARIATIONS = "8B 4C 24 30 8B 14 8D ? ? ? ? 89 94 37 ? ? ? ? 8D 45 CD E9 ? ? ? ? 5B 33 C0 5E C2 20 00 "
  .. "83 FD 27 75 17 8B 44 24 30 8B 0C 85"
K.VARIATIONS = { field = 14, tables = { 7, 0x2D, 0x49, 0x65, 0x81, 0x9D } }
-- The variant panels above the menu: one row per building with variants (its menu button's
-- first id and how many), the module's extra statues and shrines at the end of theirs.
K.VARIANT_ROWS = {
  [K.TAB_GOOD] = { { 160, 6 }, { 166, 3 }, { 169, 3 }, { 313, 5, { 320 } }, { 318, 2, { 321, 322 } } },
  [K.TAB_BAD] = { { 301, 4 } },
}
K.CAMPFIRE_TYPE = 0x33                   -- the module's barrier is a campfire (placement 58)
-- rotateFearFactorBuildingVariations, every second: `mov eax,[chosen tool] / add eax,-0xA0 /
-- cmp eax,0xA8 / ja <end>` before the table that moves the tool to the next variant.
K.AOB_VARIANT_TURN = "A1 ? ? ? ? 05 60 FF FF FF 3D A8 00 00 00 77"
K.VARIANT_TURN = { size = 10, add = 6, endRel = 0x10 }
-- Hovels: placeWorkshopOrHovel gives a new hovel its player's next variant, `mov cx,[ebx+COUNTER]
-- / ... / mov [eax+HOVEL],cx / jne / mov eax,[ebx+COUNTER] / add eax,1 / cdq / mov ecx,7 / idiv
-- ecx / mov [ebx+COUNTER],edx` (ebx: player * the player data size).
K.HOVEL_TOOL, K.HOVEL_TYPE, K.HOVEL_VARIANTS = 54, 1, 7
K.AOB_HOVEL_VARIANT = "66 8B 8B ? ? ? ? 8B E8 69 C0 2C 03 00 00 66 83 7C 24 20 01 89 44 24 28 66 89 88 ? ? ? ? "
  .. "75 ? 8B 83 ? ? ? ? 83 C0 01 99 B9 07 00 00 00 F7 F9 89 93"
K.HOVEL_VARIANT = { size = 7, counter = 3, field = 0x1C, skipRel = 0x21, advance = 0x22, advanceSize = 6 }
-- ...and the placement preview's `imul ecx,ecx,player size / mov edx,[ecx+COUNTER] / mov eax,
-- [edx*4+HOVEL PICTURES] / mov [esp+0x2C],eax`.
K.AOB_HOVEL_PREVIEW = "69 C9 F4 39 00 00 8B 91 ? ? ? ? 8B 04 95 ? ? ? ? 89 44 24 2C"
K.HOVEL_PREVIEW = { site = 6, size = 6 }
K.HOVEL_PICTURES = 15                    -- in K.AOB_HOVEL_PREVIEW: the variants' first pictures
K.MOAT_ENTRY_WIDTH = 76                  -- room for "Permanent" under its picture
-- Panels the module draws mark where they are (menu coordinates) each frame they are drawn; the
-- guard keeps clicks there off the map. A rect: active, x, y, width, height; -1 ends the list.
K.GUARD_RECTS, K.RECT_SIZE = 64, 20
-- checkBuildingCanBePlacedHere's limits on empty storage buildings (stockpile 32, granary and
-- armoury 8): `push type / push ebx / mov ecx, BuildingsState / call getEmptyBuildingCount /
-- cmp eax, LIMIT / jge <refused> / mov reg,[esp+0x50] / push type`; three sites.
K.AOB_EMPTY_STORAGE = "53 B9 ? ? ? ? E8 ? ? ? ? 83 F8 ? 0F 8D ? ? ? ? 8B ? 24 50 6A"
K.EMPTY_STORAGE = { site = 11, size = 9, limit = 13, failRel = 16, sites = 3 }
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
-- The preview of the same tools with the mouse button up: `cmp esi,ebx / je <see-through> /
-- imul esi,esi,0x32C`; the solid preview's `push 5` follows at +0x4B, the see-through one's
-- `push 0x100005` at +0x66.
K.AOB_TOWER_ENGINE_PREVIEW = "3B F3 74 62 69 F6 2C 03 00 00 0F BF"
K.TOWER_PREVIEW = { size = 10, solid = { 0x4B, { 0x6A, 0x05, 0x50, 0x53, 0x53 } },
  clear = { 0x66, { 0x68, 0x05, 0x00, 0x10, 0x00 } }, flags = { 0x3A, { 0xF7, 0x04, 0x85 } } }
-- The map editor's unit tool: `mov [esp+0x14], <tile flags that refuse a unit>` (sea, rocky,
-- building, tree, river, moat, ...); a tower engine goes only where a unit could.
K.AOB_UNIT_MASK = "89 54 24 18 89 7C 24 20 C7 44 24 14 ? ? ? ? 0F 87"
K.UNIT_MASK = 12
K.TOWER_ENGINE_UNITS = { [41] = true, [61] = true }   -- mangonel, ballista
-- ClickPlaceSiegeTent's building test: `movsx eax,word [edx*2+buildings on tiles] / test eax,eax /
-- pop ebp / je / imul eax,eax,0x32C / cmp byte [eax+has engine],0 / jne <refuse>`.
K.AOB_ENGINE_BUSY = "0F BF 04 55 ? ? ? ? 85 C0 5D 74 13 69 C0 2C 03 00 00 80 B8 ? ? ? ? 00 0F 85"
K.ENGINE_BUSY = { site = 0x13, size = 13, field = 2, jump = 9 }
-- The eraser's walk over a tile's units: `imul eax,eax,<unit size> / mov word [eax+state],3 /
-- movsx eax,word [eax+next on tile] / test eax,eax / jne`; the next unit lies 0x216 after the
-- state word (both exes).
K.AOB_UNIT_WALK = "69 C0 ? ? ? ? ? ? ? ? ? ? ? ? ? 0F BF 80 ? ? ? ? 85 C0 75 E6 83 C7 01 3B 7C 24 28 7C B3 5F 5E 5D 5B"
K.UNIT_WALK = { stride = 2, next = 18, nextAfterState = 0x216 }
-- How many tower engines a building takes (its own big towers go by the game's own rule, one):
-- the keeps 4 and the stronghold keeps 8, the large gatehouse 4, any other building one.
K.TOWER_ENGINE_MOST = { [40] = 4, [41] = 4, [42] = 4, [43] = 8, [44] = 8, [45] = 4 }
-- Keep parts: placeKeep places the keep and its doors, then (`mov eax,[esp+0x3C] / mov ecx,
-- [esp+0x48] / add ebx,[eax*8+..]`) the campfire area, then (`mov eax,[esp+0x3C] / mov edi,
-- [eax*8+..]`) the stockpile; both lead on to the same epilogue.
K.AOB_KEEP_CAMPFIRE = "8B 44 24 3C 8B 4C 24 48 03 1C C5 ? ? ? ? 03 3C C5"
K.AOB_KEEP_STOCKPILE = "8B 44 24 3C 8B 3C C5 ? ? ? ? 8B 1C C5 ? ? ? ? 03 7C 24 24"
K.KEEP_CAMPFIRE_SIZE, K.KEEP_STOCKPILE_SIZE = 8, 11
-- placeKeep's ground painter calls (keep tiles, campfire area): `push 2 / push 0 / push 6 / add
-- reg,ebx / push reg / push eax / push ebp / mov ecx,esi / call paint` (thiscall, 6 arguments).
-- Building rotation (44.2). The game's building orientation (TriggerPlaceBuilding: `cmp ecx,0x92 /
-- mov eax,0x51 / je / mov eax,[orientation]`), which the placement command, the placement
-- preview and the AI's AIV placement read; values 0, 2, 4, 6 (0xF: default). The keep's turn at
-- the start of a match (setKeepOffsetAndOrientation): the direction from the keep to (200, 200)
-- (`push 200 / ... / mov ecx,direction / ... / call / mov eax,[direction result] / and eax,0xFFFE`),
-- 2 and 6 swapped.
K.AOB_ORIENTATION = "81 F9 92 00 00 00 B8 51 00 00 00 74 05 A1 ? ? ? ?"
K.ORIENTATION = 14
K.AOB_KEEP_TURN = "68 C8 00 00 00 8D 50 D5 68 C8 00 00 00 51 89 56 28 8D 51 D5 89 4E 34 50 B9 ? ? ? ? 89 46 30 89 56 2C E8 ? ? ? ? A1 ? ? ? ? 25 FE FF 00 00"
K.KEEP_TURN = { this = 25, call = 35, result = 41 }
K.MAP_CENTRE = 200
-- placeBuilding: `cmp eax,0xF / jne / mov [esi+rotation],edx / jmp / cdq / sub eax,edx / sar eax,1 /
-- mov [esi+rotation],eax`: TileMapState's placement rotation (orientation / 2).
-- The keep layout tables (3 keep types x 4 orientations): doors etc. 24 bytes a row (the preview's
-- `movsx edx,ax / add edx,-0x3C / lea ecx,[edx+edx*2] / shl ecx,5 / add ecx,TABLE`), the campfire
-- area and the stockpile 8 bytes a row (placeKeep's `add ebx,[eax*8+..]` / `mov edi,[eax*8+..]`);
-- the preview's call `mov ecx,[..] / mov edx,[..] / push ecx / push esi / push eax / push edx /
-- mov ecx,TileMapState / call setConstructionGFXLayerBasedOnPlacementChecks`.
K.AOB_KEEP_TABLE_A = "0F BF D0 83 C2 C4 8D 0C 52 C1 E1 05 81 C1 ? ? ? ?"
K.AOB_KEEP_PREVIEW_CALL = "8B 0D ? ? ? ? 8B 15 ? ? ? ? 51 56 50 52 B9 ? ? ? ? E8"
K.KEEP_TABLES = { a = 14, b = 18, c = 7, call = 21, rows = 3, campfireSize = 7, stockpileSize = 5 }
-- Only buildings placed as several parts turn (placeBuilding's own placers, by building type):
-- barracks 8/9, engineers' guild 24, tunnellers' guild 25, oil smelter 28, keeps 40-44. The chosen
-- tool: TriggerPlaceBuilding `mov ecx,[tool] / cmp ecx,0x65 / mov edx,..`.
K.ROTATING_TYPES = { [8] = true, [9] = true, [24] = true, [25] = true, [28] = true, [40] = true, [41] = true,
  [42] = true, [43] = true, [44] = true }
K.AOB_CHOSEN_TOOL = "8B 0D ? ? ? ? 83 F9 65 8B 15"
K.AOB_PLACE_ROTATION = "83 F8 0F 75 08 89 96 ? ? ? ? EB 0B 99 2B C2 D1 F8 89 86 ? ? ? ?"
K.PLACE_ROTATION = 7
K.AOB_PREVIEW_ROTATION_RESET = "83 3D ? ? ? ? 0C 89 1D ? ? ? ? 89 0D ? ? ? ? 89 15 ? ? ? ?"
K.PREVIEW_ROTATION_RESET = 7
K.AOB_BUILDING_VALIDATOR = "83 EC 2C 53 55 8B 6C 24 40 56 33 C0 39 44 24 4C 57 8B 7C 24 44 8B F1"
-- The placement validator reads three (x,y) pairs per barracks turn and one per oil smelter turn.
-- Both guilds use the barracks row's second pair.
K.AOB_BARRACKS_ROWS = "5F 5E 5D 5B 83 C4 2C C2 14 00 8B 86 B4 49 55 00 8D 04 40 03 C0 03 C0 03 BC 00 ? ? ? ? 03 C0 03 A8"
K.AOB_OIL_ROWS = "8B 86 B4 49 55 00 03 C0 03 C0 03 BC 00 ? ? ? ? 03 C0 03 A8 ? ? ? ? C7 44 24 44 00 00 00 00"
K.PREVIEW_PART_ROWS = { barracks = 26, oil = 13 }
-- Footprint iterator calls for each extra part. Offsets are relative to the signature and the
-- call, respectively. X and Y locate the part's unrotated origin after the call.
K.PREVIEW_PART_CALLS = {
  { "8B 5C 24 30 83 C5 05 89 6C 24 34 33 ED 6A 05 55 8B CE E8 ? ? ? ? 8B 86 90 49 55 00", 18, 73, "[esp+0x48]", "edi", 0 },
  { "8D 6F 05 33 FF 6A 05 57 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 66 8B 8E 94 49 55 00 66 03 0D ? ? ? ? 03 C5", 10, 73, "[esp+0x24]", "ebp", 1 },
  { "83 C7 01 3B BE 84 49 55 00 7C A7 33 FF 6A 05 57 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 66 8B 8E 94 49 55 00", 18, 73, "[esp+0x48]", "ebp", 2 },
  { "66 3D 58 00 75 6A 83 C7 05 33 DB 6A 05 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 66 8B 96", 16, 75, "ebp", "edi", 1 },
  { "66 3D 59 00 75 6A 83 C7 05 33 DB 6A 05 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 66 8B 8E", 16, 75, "ebp", "edi", 1 },
  { "66 3D B4 00 75 6A 83 C7 04 33 DB 6A 04 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 66 8B 8E", 16, 75, "ebp", "edi" },
  { "8B 44 24 10 8B 6C 24 18 83 C0 05 89 44 24 30 33 DB 6A 05 53 8B CE E8 ? ? ? ?", 22, 86, "[esp+0x44]", "ebp", 0 },
  { "83 C5 05 33 DB 8D 49 00 6A 05 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 03 C5", 13, 86, "[esp+0x24]", "ebp", 1 },
  { "83 C3 01 3B 9E 84 49 55 00 7C 9A 33 DB 6A 05 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00 03 C5", 18, 86, "[esp+0x44]", "ebp", 2 },
  { "8B 6C 24 18 83 C5 05 33 DB 8D A4 24 00 00 00 00 6A 05 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00", 21, 87, "[esp+0x24]", "ebp", 1 },
  { "8B 6C 24 18 83 C5 04 33 DB 8D 64 24 00 6A 04 53 8B CE E8 ? ? ? ? 8B 86 90 49 55 00", 18, 86, "[esp+0x24]", "ebp" },
}
K.ROTATIONS = { { "Default" }, { "90\xB0", 2 }, { "180\xB0", 4 }, { "270\xB0", 6 }, { "Location based", "location" } }
K.ROTATION_BOX = { x = 12, y = 420, width = 150, height = 22, option = 20 }
-- The right-click ring's compass (45): `cmp eax,3 / jne / mov edx,[next] / push edx / mov ecx,
-- TileMapState / call setMapRotation` (in a match) and the same with eax (map editor); it draws
-- its picture with `add ecx,[..] / add edi,0x26 / push ecx / push edi / push 0x10 / mov ecx,
-- textures / call renderGM`, picture 0x26 + 0, 3, 2, 1 for the orientations 0, 2, 4, 6.
K.AOB_COMPASS_TURN = { { "83 F8 03 75 23 8B 15 ? ? ? ? 52 B9 ? ? ? ? E8", "compassTurnEdx", 6 },
  { "83 F8 03 75 12 A1 ? ? ? ? 50 B9 ? ? ? ? E8", "compassTurnEax", 5 } }
K.COMPASS_TURN_SITE = 5
K.AOB_COMPASS_DRAW = "03 0D ? ? ? ? 83 C7 26 51 57 6A 10 B9 ? ? ? ? E8"
K.COMPASS_DRAW = { first = 8, gm = 12 }
K.COMPASS_PICTURE = { [0] = 0, [2] = 3, [4] = 2, [6] = 1 }
-- Unit display player (46.1): PlaceUnit's single unit `push ecx / push eax / push eax / mov ecx,
-- UnitsState / call spawnUnit / pop edi ...`; the panel shows in the castle tabs 26 and 29.
K.AOB_UNIT_COLOUR = "51 50 50 B9 ? ? ? ? E8 ? ? ? ? 5F 5E 5D 5B 83 C4 1C C3"
K.UNIT_COLOUR = { site = 1, size = 7, units = 3 }
K.UNIT_TABS = { [26] = true, [29] = true }
K.UNIT_COLOUR_PANEL = { x = 330, gap = 4, label = "Unit display player:", selectedLabel = "Selected units:", above = 58 }
-- The group spawner (TribesState, VAN 0x523030) the castle's unit tools use: `push ebx / push ebp /
-- push edi / push edi / mov ecx,UnitsState / call spawnUnit / mov esi,eax / test esi,esi / je`.
K.AOB_GROUP_COLOUR = "53 55 57 57 B9 ? ? ? ? E8 ? ? ? ? 8B F0 85 F6 74 1E"
K.GROUP_COLOUR = { site = 2, size = 7, units = 3, sites = 2 }
-- Selected units (46.2): UnitsState + 0x24 + player * 4 counts each player's selection; a unit
-- (0x490 bytes, the walk's state word at +0x8C) is alive with state 2, selected by the player in
-- its word +0xB2 (0: by nobody, so player 0 cannot select), drawn in the colours of +0x80.
K.SELECTION = { counts = 0x24, state = 0x8C, alive = 2, selectedBy = 0xB2, colour = 0x80 }
-- Map size changes (47): the size action's tail `mov ecx,TileMapState / call / mov ecx,X /
-- mov [..],1 / call / push 1 / mov ecx,X / call`, patched at its second `mov ecx`; the map load's
-- viewport calls `mov ecx,viewport / mov [..],ebp / mov [..],edx / call bounds / mov ecx,viewport /
-- call build / mov ecx,viewport / call tweak`; the camera clamp in setViewportBasedOnMapSize.
K.AOB_SIZE_TAIL = "B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? C7 05 ? ? ? ? 01 00 00 00 E8 ? ? ? ? 6A 01 B9 ? ? ? ? E8"
K.SIZE_TAIL = { site = 10, size = 5 }
K.AOB_VIEWPORT_LOAD = "B9 ? ? ? ? 89 2D ? ? ? ? 89 15 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8"
K.VIEWPORT_LOAD = { viewport = 1, bounds = 17, build = 27, tweak = 37 }
K.AOB_CAMERA_CLAMP = "39 51 78 7D 03 89 51 78 39 79 78 7E 03 89 79 78 39 71 7C"
K.CAMERA_CLAMP = { size = 8 }
K.CAMERA_EDGE = { x = 32, y = 16 }
-- ... and the load's `push ebx / mov ecx,esi / call toggleFlatView / mov [..],ebx / mov [..],ebx /
-- call setChangedLayerToThreeAndMapping0x40x40` (every tile drawn afresh).
K.AOB_ALL_CHANGED = "53 8B CE E8 ? ? ? ? 89 1D ? ? ? ? 89 1D ? ? ? ? E8"
K.ALL_CHANGED = 20
-- ... and before those viewport calls the load clears the tiles' drawn pictures (`push pictures /
-- push ebx / push 0x27420 / mov ecx,memory / mov [..],edi / call fillMemory_ByteValue`, thiscall,
-- 3 arguments): tiles the new size leaves out keep none (black), the rest are drawn afresh.
-- The map size word: the size action's `push eax / mov ecx,TileMapState / mov [size],eax`.
K.AOB_SIZE_WORD = "50 B9 ? ? ? ? A3 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? C7 05"
K.SIZE_WORD = 7                          -- then `call resetHeightAndMapBorders` at +11       -- one tile, in the viewport's camera units
K.AOB_KEEP_GROUND = { "6A 02 6A 00 6A 06 03 D3 52 50 55 8B CE E8", "6A 02 6A 00 6A 06 03 CB 51 50 55 8B CE E8" }
K.KEEP_GROUND_CALL = 13
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

-- The ruined cathedral (see docs/ruined-cathedral.md): UpdateCathedral gives a cathedral its
-- ruined picture only in historical mission 7, by setting its picture field and a flag and
-- redrawing it - `cmp word [ecx+FLAG],bx / mov eax,RUINED / je / cmp [ecx+PICTURE],eax / je /
-- mov word [ecx+FLAG],1 / mov [ecx+PICTURE],eax / push esi / mov ecx, TileMapState / call
-- updateBuildingGraphicsLayer` (ecx: the building's id * its size). The module does the same to
-- a cathedral placed while "Ruined" is chosen (C.ruinWatch).
K.CATHEDRAL_TOOL, K.CATHEDRAL_TYPE, K.RUINED_LABEL = 97, 0x26, "Ruined"
K.AOB_RUINED_CATHEDRAL = "66 39 99 ? ? ? ? B8 ? ? ? ? 74 08 39 81 ? ? ? ? 74 ? 66 C7 81 ? ? ? ? 01 00 89 81 ? ? ? ? "
  .. "56 B9 ? ? ? ? E8"
K.RUINED_CATHEDRAL = { flag = 3, picture = 8, pictureField = 0x10, tileMap = 0x27, update = 0x2B }
K.LAST_PLACED = 0x554888
K.TYPE_AFTER_PICTURE = 0xD2              -- a building's type word, from its picture field
K.GM_AFTER_PICTURE = 0x04                -- and its gm (spriteSheetID)
K.RUIN_PARTS = 169                       -- the ruin's pictures, one per tile of the 13 x 13 cathedral

-- Moat. The gatehouses tab's moat buttons (106, 107) choose 0x2D (dig) and 0x2C (remove) in the
-- map editor; the click sends ClickSetTerrain with terrain 0x40000000 and a mode: 0 planned
-- moat, 1 plan removed (the game's), 2 dug moat, 3 moat removed (the editor's). The module adds
-- mode 4: dug moat without an entry in the moat list, which nothing can fill in or delete.
K.TAB_GATEHOUSES = 12
K.MOAT_BUTTON, K.MOAT_TOOL = 106, 0x2D
K.MOAT_DUG, K.MOAT_PLANNED, K.MOAT_PERMANENT = 0, 1, 2     -- the panel's choices
K.MOAT_LABELS = { [0] = "Dug", [1] = "Planned", [2] = "Permanent" }
K.MOAT_PERMANENT_MODE = 4
K.MOAT_FLAGS, K.MOAT_DUG_FLAG = 0x40004000, 0x40000000      -- planned or dug, dug
K.GROUND_HEIGHT = 8                                         -- what removeMoat gives a filled tile
K.PLAIN2_FLAG = 0x8                                         -- dug moat clears it too
-- TriggerPlaceBuildingCommand, the editor's moat click: `xor ecx,ecx / cmp eax,0x2D / setne cl /
-- push 0x15 / add ecx,2 / mov [command param 4],ecx` (2 dig, 3 remove).
K.AOB_MOAT_CLICK = "33 C9 83 F8 2D 0F 95 C1 6A 15 83 C1 02 89 0D"
K.MOAT_CLICK_SIZE = 8
-- setTerrain's moat branch, after its tests (`... movzx eax, byte [edx+HEIGHT] / cmp eax,12 / jle
-- / jmp <skip>`): `cmp dword [ebp+0x1C],0 / jne NEXT` picks the mode (ebp-0x20 TileMapState,
-- ebp+0xC the tile, ebp-0xC x, ebp+0x10 y). NEXT (mode 1) calls clearMoatDataAtTile at +0x46;
-- the mode 0 code ends with a jmp to the branch's end; the mode 2/3 code writes the decoration
-- byte at NEXT+0x80.
K.AOB_MOAT_MODE = "8B 55 E0 03 55 0C 0F B6 82 ? ? ? ? 83 F8 0C 7E 05 E9 ? ? ? ? 83 7D 1C 00 75 52"
K.MOAT_MODE = { site = 23, size = 6, height = 9, logic = 9, clear = 0x46, done = 0x4D, decoration = 0x80 }
-- The same branch's marsh test: `mov eax,[edx+ecx*4+LOGIC] / and eax,0x20000000 / je +5 / jmp <skip>`.
K.AOB_MOAT_MARSH = "8B 84 8A ? ? ? ? 25 00 00 00 20 74 05 E9"
K.MOAT_MARSH = { site = 7, size = 5 }

-- The pipette. Its tool id is above the landscape click handler's last case (0x155: anything
-- higher does nothing) and outside getBuildingSizeForCommandBuildingType's range (0x2C-0x172),
-- and no wall tool; renderPreviewMapperWithBrush shows it as the plain brush.
K.PIPETTE_TOOL = 0x1F4
K.NO_TOOL = 0xFFFFFFFF
K.PIPETTE_HEIGHTS, K.PIPETTE_TEXTURES, K.PIPETTE_OBJECTS, K.PIPETTE_ALL = 1, 2, 3, 4
K.PIPETTE_MODES = {
  { label = "Heights", what = "heights", image = 240 },        -- the Heights category's picture
  { label = "Textures", what = "textures", image = 241 },      -- the Textures category's picture
  { label = "Objects", what = "building, wall, tree or rock", image = 242 }, -- the Objects category's picture
  { label = "All", what = "textures, heights and 1x1 tree or rock" },          -- the pipette's own picture
}
-- The objects pipette takes a building or wall and then simply chooses that tool: the game's own
-- building and wall handlers (also in the landscape menu's item table) show and place it; the
-- landscape click handler only acts on its own tools (36-49, shrubs, foam, rocks, animals).
-- Buildings: building layer -> building (stride and type field from updateLogicalTileMapRelated-
-- Sections: `movsx eax, word [esi+edi*2+LAYER] / test eax,eax / je / imul eax,eax,STRIDE / cmp
-- word [eax+TYPE],0x31`) -> convertBuildingTypeToCommandBuildingType (`mov eax,[esp+4] / add
-- eax,-1 / cmp eax,0x6A / ja`, 0 for none).
K.AOB_BUILDING_TYPE = "0F BF 84 7E ? ? ? ? 85 C0 74 ? 69 C0 ? ? ? ? 66 83 B8 ? ? ? ? 31"
K.BUILDING_TYPE = { stride = 14, type = 21 }
K.AOB_COMMAND_OF_TYPE = "8B 44 24 04 83 C0 FF 83 F8 6A 0F 87"
K.BUILDINGS_STATE = 0x17                 -- in K.AOB_BUILDING_SPRITES: `mov ecx, BuildingsState`
-- Walls by their tile flags: stairs, crenellation, wall (high wall 90 above the ground, low 60).
K.STAIRS_FLAG, K.CRENEL_FLAG, K.WALL_FLAG, K.STOCKPILE_FLAG = 0x800, 0x200, 0x100, 0x2
K.STAIRS_TOOL, K.CRENEL_TOOL, K.HIGH_WALL_TOOL, K.LOW_WALL_TOOL = 27, 26, 25, 46
K.HIGH_WALL_ABOVE = 75
-- Whose a building or wall is: a building's owner word follows its type (+0xD2, +0xD6); a wall
-- tile's owner is the low 3 bits of the wall owner layer, player - 1. The editor places for the
-- player chosen with the shields beside the minimap (InGameMenu_MainButtons, map editor only):
-- `mov eax,-9 / sub eax,esi / pop edi / mov [eax*4+FLAGS],ebx / pop esi / mov [CURRENT],eax`,
-- after clearing all nine shield flags.
K.OWNER_AFTER_TYPE = 4
K.WALL_OWNER_BITS = 7
K.AOB_PLAYER_CHOICE = "B8 F7 FF FF FF 2B C6 5F 89 1C 85 ? ? ? ? 5E A3"
-- Player 0's shield (castle menu): between the 4 x 2 shields (menu x 719/757, y 462..561), its
-- clickable item before their group (the menu stops at the first item under the mouse) and its
-- picture drawn after it, on top. The first shield is the group member with parameter -10.
K.SHIELD_ZERO = { x = 738, y = 511, firstParam = -10, players = 9 }
-- The keep crests (castle mode): each keep shows its owner's shield above it, chosen look for the
-- player's active keep; a click makes it the active keep, or leaves the player without one.
-- A player's keep is GameState's BuildingEntryInfo {id, entry x, entry y, tile, area, ...} at
-- +0x30DD4 + player * player size (category 0; its campfire is category 8, 8 entries further),
-- set by computeBuildingCategoryEntryPointAndDestroyEarlierBuilding(building, player, category),
-- which placeKeep calls as `push eax / mov ecx, GameState / mov [esp+0x40],eax / call`.
K.AOB_KEEP_ENTRY_CALL = "50 B9 ? ? ? ? 89 44 24 40 E8"
K.KEEP_ENTRY = { state = 2, call = 10, first = 0x30DD4, entry = 0x28, dwords = 10, campfire = 8, stockpile = 1,
  strideAt = { 0x24, { 0x69, 0xC0 } } }
K.KEEP_TYPES = { [40] = true, [41] = true, [42] = true, [43] = true, [44] = true }
K.CAMPGROUND_TYPE = 55                   -- the keep's campfire area (not the barrier's campfire)
K.STOCKPILE_TYPE = 10
-- Building fields from the start of a building (BuildingsState + 0x14 is building 0).
K.BUILDING = { first = 0x14, type = 0xD2, owner = 0xD6, x = 0xEE, y = 0xF0, size = 0xF8, uid = 0x2A8 }
K.CREST = { lift = 120, rects = 40, selected = 8 }
-- The crest tooltip's lines ({player}: "player N"); gap: between crest and box.
K.CREST_TOOLTIP = {
  gap = 4,
  active = { "Active keep of {player}", "The lord, the starting units and new peasants appear here.",
    "Click: leave {player} without an active keep." },
  other = { "Keep of {player}", "Click: make this the active keep, where the lord,",
    "the starting units and new peasants appear." },
}
-- Wall tools (35): placeWalls' `cmp dx,0x19 / jne / add byte [esi+edi+LIVE],0x5A / jmp / cmp dx,0x2E /
-- jne / add byte [..],0x3C` (high and low wall heights); its high crenellation add followed by
-- the join point of every crenellation height, `mov eax,[esp+0x20] / and eax,1`; the stairs'
-- first step `mov eax,[esp+0x24] / sub eax,edx / sub eax,0x10`; the per-step drop `mov eax,0x10 /
-- cmp [esp+..],eax / jle / sub [esp+..],eax` in renderWallDragPreview, validateWallBuildPath and
-- placeWalls; validateWallBuildPath's two isTileEnclosedByWalls answers for crenellations
-- (`test eax,eax / mov edx,ecx / jne` and `call / test eax,eax / jne / pop ebx`, refusing with
-- reason 0x13 otherwise).
K.WALL_SITES = {
  heights = { aob = "66 83 FA 19 75 0D 80 84 3E ? ? ? ? 5A E9 ? ? ? ? 66 83 FA 2E 75 0D 80 84 3E ? ? ? ? 3C",
    high = 13, low = 32 },
  crenel = { aob = "80 84 3E ? ? ? ? 62 8B 44 24 20 83 E0 01", join = 8, live = 3 },
  first = { aob = "8B 44 24 24 2B C2 83 E8 10 85 C0 7E", at = 8 },
  steps = {
    { aob = "83 6C 24 18 01 B8 10 00 00 00 39 44 24 20 7E 0B", at = 6 },
    { aob = "83 6C 24 20 01 B8 10 00 00 00 39 44 24 24 7E 04 29 44 24 24", at = 6 },
    { aob = "29 44 24 28 B8 10 00 00 00 39 44 24 24 7C 04 29 44 24 24", at = 5 },
  },
  free1 = { aob = "85 C0 8B D1 75 B1 5B 5F 5E C7 82 ? ? ? ? 13 00 00 00" },
  free2 = { aob = "E8 ? ? ? ? 85 C0 75 3A 5B 5F 5E C7 81 ? ? ? ? 13 00 00 00", at = 5 },
}
K.HIGH_WALL, K.LOW_WALL, K.CRENEL_WALL, K.STAIRS = 25, 46, 26, 27
K.WALL_DEFAULT = { [25] = 0x5A, [46] = 0x3C, [27] = 16 }
K.STAIR_STEP = 16
K.CRENEL_LOW_HEIGHT, K.CRENEL_HIGH_HEIGHT = 0x44, 0x62
K.CRENEL_DAMAGED, K.CRENEL_LOW, K.CRENEL_HIGH, K.CRENEL_LOW_DAMAGED, K.CRENEL_HIGH_DAMAGED = 1, 2, 3, 4, 5
K.CRENEL_LABELS = { { 2, "Low" }, { 3, "High" }, { 4, "Low damaged" }, { 5, "High damaged" } }
K.WALL_SLIDER = { track = 150, height = 24, trackHeight = 10, panelRoom = 70, textRaise = 7, reset = "Reset" }
K.PLAYER_CHOICE = { flags = 11, current = 17 }
-- ...but in the landscape editor (screen 0xC) ClickPlaceBuilding places for its own player
-- variable instead (the castle screen for the command's sender): `cmp [screen],0xC / ... / mov
-- edx,[editor player] / ... / je / mov edx,[sender]`.
K.AOB_EDITOR_PLAYER = "83 3D ? ? ? ? 0C 8B 15 ? ? ? ? A1 ? ? ? ? 8B 0D ? ? ? ? 50 A1 ? ? ? ? 89 15 ? ? ? ? "
  .. "0F B7 15 ? ? ? ? 51 8B 0D ? ? ? ? 52 8B 15"
K.EDITOR_PLAYER = 53
K.PLAYERS = 8
-- Trees and rocks: the organism layer holds a tree's slot (tile flag 0x1000) or a rock's slot +
-- 2000. The pipette places one the way the landscape editor's command 0x1A ends: placeRock(x,
-- y, rock number) or placeTree(x, y, tree tool) on the tile map, called straight away (a queued
-- command runs later, after the stage, logs and turn set for it would be back): `movzx eax, word
-- [param 3] / mov ecx,[param 1] / mov edx,[param 0] / push eax / push ecx / push edx / mov ecx,
-- TileMapState / call placeRock / ret / ... / call placeTree`. placeRock makes rock number n into rock type n + 1
-- (sizes 1 to 4 for numbers 0-3, 4-7, 8-11, 12-15); a rock slot keeps its type at +0x10 and
-- its turn at +0x18, which placeRock takes from the tile map's rotation.
K.TREE_FLAG = 0x1000
-- Where renderMap draws a tile on the map surface (see the skill's notes on the screen transform):
-- per map turn the constants of drawX = cx + xd*(x-y) + xs*(x+y) - 32*C and drawY = bias + cy +
-- yd*(x-y) + ys*(x+y) - 16*R, C and R from the viewport position; the tile's height lifts it by
-- heightBasedScreenYOffset[height] (TileMapState + 0x3840). Viewport fields: x, y, zoomed out,
-- row bias.
K.SCREEN_TURN = {
  [0] = { cx = 3334, xd = 16, xs = 0, cy = 8 - 1592, yd = 0, ys = 8 },
  [6] = { cx = 9718, xd = 0, xs = -16, cy = 8 + 1600, yd = 8, ys = 0 },
  [4] = { cx = 3334, xd = -16, xs = 0, cy = 8 + 4792, yd = 0, ys = -8 },
  [2] = { cx = -3050, xd = 0, xs = 16, cy = 8 + 1600, yd = -8, ys = 0 },
}
K.VIEWPORT = { x = 0x78, y = 0x7C, zoomedOut = 0x90, bias = 0x94 }
K.HEIGHT_OFFSETS = 0x3840
K.FLAT_HEIGHT_OFFSET = 8                 -- renderMap's flattened view: every tile at this offset
K.TILE_WIDTH, K.TILE_HEIGHT = 32, 16
K.TREE_PICTURE = 0x00                    -- a tree slot's current picture (UpdateTree keeps it)
K.TREE_GM = 0x04                         -- and its gm
-- renderMap draws a tree at its tile + (14, 6) - its gm's origin; createTree reads the origin
-- from the gm's header: `movsx edx, word [ecx+0x20] / imul edx,edx,STRIDE / mov bx,[edx+X] / mov
-- [ecx+0x28],bx / movzx edx, word [edx+Y] / mov [ecx+0x2A],dx`.
K.AOB_TREE_ORIGIN = "0F BF 51 20 69 D2 ? ? ? ? 66 8B 9A ? ? ? ? 66 89 59 28 0F B7 92 ? ? ? ? 66 89 51 2A"
K.TREE_ORIGIN = { stride = 6, x = 0x0D, y = 0x18 }
K.TREE_DRAW_X, K.TREE_DRAW_Y = 14, 6
-- The rock tool's variant and size (0-3) in the tile map (rock number = size * 4 + variant), and
-- a rotation mode that leaves the rock rotation alone (5 turns it every frame, 0 every second).
K.ROCK_VARIANT_AT, K.ROCK_SIZE_AT, K.FIXED_TURN = 0x5548F4, 0x5548F8, 1
K.AOB_PLACE_PLANT = "0F B7 05 ? ? ? ? 8B 0D ? ? ? ? 8B 15 ? ? ? ? 50 51 52 B9 ? ? ? ? E8 ? ? ? ? C3 "
  .. "8B 0D ? ? ? ? 50 A1 ? ? ? ? 50 51 B9 ? ? ? ? E8"
K.PLACE_PLANT = { placeRock = 0x1B, placeTree = 0x34 }
K.ROCK_SLOT = { type = 0x10, turn = 0x18, inUse = 0x0C }
K.ROCK_TYPES = 16
K.PLANT_NAMES = { [40] = "chestnut", [41] = "oak", [42] = "pine", [43] = "birch" }
-- Names for the line above the pipette panel, by tool.
K.OBJECT_NAMES = {
  [25] = "high wall", [26] = "crenellated wall", [27] = "stairs", [46] = "low wall", [50] = "fletcher",
  [51] = "woodsman", [52] = "stockpile", [53] = "outpost bedouin", [54] = "hovel", [55] = "ox tether",
  [56] = "quarry", [57] = "tunnel", [58] = "campfire", [59] = "signpost", [60] = "keep", [61] = "keep",
  [62] = "keep", [63] = "keep", [64] = "keep", [65] = "stables", [66] = "tunnel construction",
  [70] = "wheatfarm", [71] = "hopsfarm", [72] = "applefarm", [73] = "cattlefarm", [74] = "mill",
  [75] = "baker", [76] = "brewer", [77] = "tradepost", [78] = "hunter", [79] = "bedouin stockade",
  [80] = "granary", [81] = "armoury", [82] = "poleturner", [83] = "blacksmith", [84] = "armourer",
  [85] = "tanner", [86] = "barracks", [87] = "mercenary post", [88] = "engineers guild",
  [89] = "tunnelers guild", [90] = "iron mine", [91] = "pitch rig", [92] = "inn", [93] = "healer",
  [94] = "siege tower base", [95] = "chapel", [96] = "church", [97] = "cathedral",
  [98] = "killing pit", [99] = "pitch ditch", [100] = "gatehouse", [101] = "large gatehouse",
  [102] = "small gatehouse", [103] = "wooden gatehouse", [104] = "postern gate", [105] = "drawbridge",
  [106] = "moat", [107] = "antimoat", [108] = "generic", [109] = "quarrypile", [110] = "lookout tower",
  [111] = "perimeter turret", [112] = "defence turret", [113] = "square tower", [114] = "round tower",
  [115] = "tower1 ruin", [116] = "tower2 ruin", [117] = "tower3 ruin", [118] = "tower4 ruin",
  [119] = "tower5 ruin", [120] = "flag type0", [121] = "flag type1", [122] = "flag type2",
  [123] = "flag type3", [124] = "flag type4", [125] = "flag type5", [126] = "flag type6",
  [127] = "flag type7", [128] = "flag type8", [129] = "heads", [190] = "catapult", [191] = "trebuchet",
  [192] = "siege tower", [193] = "battering ram", [194] = "portable shield"
}
-- The landscape menu's left column (UC_MAP_BRUSH 82,464 / UC_MAP_SNAP 82,507 / UC_MAP_DELETE
-- 82,552): the pipette on top, then brush size (and its second item, 331), ruler and eraser.
K.PIPETTE_COLUMN = { x = 82, tops = { 456, 490, 524, 562 }, moved = { { 1, 331 }, { 204 }, { 39 } } }
K.PIPETTE_TEXT_ABOVE = 22
K.PIPETTE_LABEL_ROOM = 15                -- a row above the panel's pictures for their labels
K.PIPETTE_ENTRY_WIDTH = 64               -- wide enough for "Textures" above its picture
K.MAP_SIZE, K.MAP_TILES = 400, 80400
-- TileMapState layers (the same offsets in both exes): decoration byte, building. The word layer
-- at +0x13DD40 (OpenSHC's RandomLayer, a saved map section) is each tile's own random number: the
-- renderers take its low bits (& 1, 3, 7, 15) to pick a picture, river foam and waves their
-- direction. Never copied: a tile whose ground changes gets a new random number.
K.TMS = { decoration = 0x1B3FE0, random = 0x13DD40, building = 0x2029B0, wallOwner = 0x2C6E50 }
K.RANDOM_LIMIT = 0x7FFF
K.MAP_BORDER = 0x30
-- The tile flags that are ground: sea, plain 1/2, earth, boulders, pebbles, iron, river, ford,
-- marsh, oil.
K.TEXTURE_FLAGS = 0xA03E800D
K.MASK_WATER = 0x00300001                -- sea, river, ford: their variants count as one
-- What the mask compares: the ground flags and the rocky flag (the Rocky texture is earth with
-- it). With water variants as one, a water tile's earth flag is dropped: a river running down a
-- slope (the waterfall edge) is river with earth.
K.MASK_FLAGS = 0xA03E808D
K.EARTH = 0x8000
-- Dust clouds (entity 0x15) step their x and y by `count % speed`; a cloud whose speeds are 0
-- divides by zero and takes the game down. In updateEntities, each step: `movsx ebp,dx / cdq /
-- jge GE` (x, after `cmp dx,bp`) and `movsx ebp,dx / test dx,dx / cdq / jge GE` (y), twice each.
K.AOB_DUST_X = "66 3B D5 0F BF EA 99 7D 0C F7 FD 85 D2 75 10 66 01 79 4C EB 0A F7 FD 85 D2 75 04 66 01 59 4C"
K.AOB_DUST_Y = "0F BF EA 66 85 D2 99 7D 0C F7 FD 85 D2 75 10 66 01 79 4E EB 0A F7 FD 85 D2 75 04 66 01 59 4E"
K.DUST_STEP = { x = 3, xSize = 6, ySize = 9, skip = 0x0A, sites = 2 }   -- skip: idiv, test, jne, add after GE
-- Heights stay off sea, walls, crenels, stairs, buildings, keeps, marsh and moat (and beach, a
-- decoration); textures off walls, crenels, stairs, buildings and keeps. Both stay off rocks,
-- but not off cliff rocks: in the map editor updateGfxLayer marks cliff edges rocky (0x80)
-- without a rock, and does so again wherever a cliff remains, so the pipette clears that flag.
K.HEIGHT_REFUSED = 0x70004F01
K.TEXTURE_REFUSED = 0x10000F00
K.ROCKY = 0x80
K.FIRST_ROCK_NUMBER = 2000               -- the organism layer: rock slot + 2000
-- useTerrainHeightBrush taking a rock off a tile it changes: `test byte [edi+ebp*4+LOGIC],0x80 /
-- je / movsx eax, word [edi+ebp*2+ORGANISM] / cmp eax,2000 / jl / add eax,-2000 / push eax /
-- mov ecx, LandscapeState / call removeRock`.
K.AOB_HEIGHT_ROCK = "F6 84 AF ? ? ? ? 80 74 1F 0F BF 84 6F ? ? ? ? 3D D0 07 00 00 7C 10 05 30 F8 FF FF 50 B9 ? ? ? ? E8"
K.HEIGHT_ROCK = { organism = 14, landscape = 32, remove = 36 }
K.BEACH_DECORATION = 0x20
K.RIVER_DEPTH = 8                        -- a river tile lies this far below its base height
K.WALK_RADIUS = 9                        -- what the height tools hand updateWalkAndPathLayer
K.TEXTURE_NAMES = { { 0x1, "sea" }, { 0x100000, "river" }, { 0x200000, "ford" }, { 0x20000000, "marsh" },
  { 0x20000, "boulders" }, { 0x40000, "pebbles" }, { 0x80000, "iron" }, { 0x80000000, "oil" },
  { 0x4, "plain 1" }, { 0x8, "plain 2" }, { 0x8000, "earth" } }
K.DECORATION_NAMES = { { 0x1, "scrub" }, { 0x2, "earth and stones" }, { 0x4, "plateau" }, { 0x8, "high plateau" },
  { 0x10, "oasis grass" }, { 0x20, "beach" }, { 0x40, "stones" }, { 0x80, "thick scrub" } }
K.RIVER_DECORATION_NAMES = { { 0x10, "foam" }, { 0x20, "small waves" } }
-- The landscape click handler: `cmp [click start],ebx / mov eax,[..] / jne / cmp [..],eax / je /
-- push ebp / mov ecx, viewport / mov [..],eax / call / cmp [click start],ebx / mov ebp,[..] /
-- mov ebx,[..] / mov esi,[mouse tile y] / mov edi,[mouse tile x]`; and its `cmp [click held],
-- ebx / jne` before the preview.
K.AOB_MOUSE_CLICK = "39 1D ? ? ? ? A1 ? ? ? ? 75 0C 39 05 ? ? ? ? 0F 84 ? ? ? ? 55 B9 ? ? ? ? A3 ? ? ? ? "
  .. "E8 ? ? ? ? 39 1D ? ? ? ? 8B 2D ? ? ? ? 8B 1D ? ? ? ? 8B 35 ? ? ? ? 8B 3D"
K.MOUSE_CLICK = { start = 2, y = 0x3D, x = 0x43 }
K.AOB_CLICK_HELD = "39 1D ? ? ? ? 0F 85 91 00 00 00 B9 ? ? ? ? E8 ? ? ? ? 8B 15"
K.CLICK_HELD = 2
-- The tile under the mouse, as the click handlers work it out before using it (from the tile
-- the renderer found under the cursor, so on raised ground too): `cmp [flat view],0 / mov ecx,
-- viewport / je / call setupMouseTileXY2 / jmp / call setupMouseTileXY`.
K.AOB_MOUSE_TILE = "83 3D ? ? ? ? 00 B9 ? ? ? ? 74 07 E8 ? ? ? ? EB 05 E8"
K.MOUSE_TILE = { flat = 2, viewport = 8, flatSetup = 14, setup = 21 }
-- renderPreviewMapperWithBrush: `mov edx,[esi+BRUSH] / mov eax,[edx*4+SIZES] / mov [esp+0x14],eax /
-- lea eax,[ebx+ebx*2] / mov eax,[eax*4+ROWS]`; its brush loop `push edx / push edi / push 1 /
-- mov ecx,esi / call getTileForBrush / ...`.
K.AOB_PIPETTE_PREVIEW = "8B 96 ? ? ? ? 8B 04 95 ? ? ? ? 89 44 24 14 8D 04 5B"
K.PIPETTE_PREVIEW = { size = 6, brush = 2, sizes = 9, rows = { 0x14, { 0x8B, 0x04, 0x85 } } }
K.AOB_BRUSH_TILE = "52 57 6A 01 8B CE E8 ? ? ? ? 8B 44 24 18 83 C7 01 3B 7C 24 1C 66 89 AC 46"
K.BRUSH_TILE_CALL = 6
-- useTerrainHeightBrush: per tile `push ebp / push ebx / mov ecx, PathFindingState / call
-- updatePathLinkagesInAllEightDirections`, after the loop `mov dword [edi+FLAG],1`; and its
-- height writes `mov al,[edi+ebp+HEIGHT] / mov [edi+ebp+DEFAULT],al / test [edi+ebp*4+LOGIC],river`.
K.AOB_HEIGHT_TAIL = "55 53 B9 ? ? ? ? E8 ? ? ? ? 8B 5C 24 1C 8B 74 24 2C 83 C6 01 3B 74 24 14 89 74 24 2C "
  .. "0F 8C ? ? ? ? C7 87 ? ? ? ? 01 00 00 00"
K.HEIGHT_TAIL = { pathFinding = 3, links = 7, flag = 0x27 }
K.AOB_HEIGHTS = "8A 84 2F ? ? ? ? 88 84 2F ? ? ? ? F7 84 AF ? ? ? ? 00 00 10 00"
K.HEIGHTS = { height = 3, default = 10, logic = 17 }
-- A height command ends with `push 9 / mov ecx, PathFindingState / call
-- updateWalkAndPathLayer / push 2 / mov ecx, minimap / mov [macro layer flag],1 / call
-- triggerMinimapRedraw`.
K.AOB_HEIGHT_TOOL = "6A 09 B9 ? ? ? ? E8 ? ? ? ? 6A 02 B9 ? ? ? ? C7 05 ? ? ? ? 01 00 00 00 E8 ? ? ? ? "
  .. "C3 CC CC 51 A1 ? ? ? ? 83 F8 01 C7 05 ? ? ? ? 06 00 00 00 75 55"
K.HEIGHT_TOOL = { walk = 7, minimap = 0x0F, macro = 0x15, redraw = 0x1D }
-- The tiles that are on the map, a byte per x, y (400 a row): the height commands' test `mov esi,
-- eax / imul esi,esi,400 / cmp byte [esi+ecx+VALID],0 / pop esi / je`.
-- The brush preview rejects a tile before reading its brush size.
K.AOB_TILE_VALID = "8B C3 69 C0 90 01 00 00 80 BC 08 ? ? ? ? 00 0F 84 ? ? ? ?"
K.TILE_VALID = 11

-- The heights menu (features 28 and 29). Its tools: raise 2 and lower 3 (raiseLand, which hill
-- 37 and mountain 36 also call, with amount 1, once per tile of a spreading search), min 21 and
-- max 22 height (useTerrainHeightBrush: 8 or 156), equalize 23 (useLevelBrush), mid 47 and high
-- 48 plateau (createPlateau). The game still handles 22; only its button was taken out (the
-- iron button took its user control, 153, and its pictures follow min height's).
K.HEIGHTS_TAB = 231
K.RAISE_TOOL, K.LOWER_TOOL, K.EQUALIZE_TOOL = 2, 3, 23
K.MIN_HEIGHT_TOOL, K.MAX_HEIGHT_TOOL, K.MAX_HEIGHT_CONTROL = 21, 22, 153
K.HEIGHT_TOOLS = { 2, 3, 21, 22, 23, 36, 37, 47, 48 }
K.HEIGHTS_TOP_ROW = { 37, 36, 21 }       -- hill, mountain, min height (then max, then iron)
K.MAX_HEIGHT_NAME = "Max Height"
-- What a height tool does to a rock it touches: "Tile only" moves just the tiles under the brush,
-- "Whole rock" moves every tile of the rock by the same amount, "Erase rock" takes it away.
K.ROCK_TILE_ONLY, K.ROCK_WHOLE, K.ROCK_ERASE = 0, 1, 2
K.ROCK_MODES = { { K.ROCK_TILE_ONLY, "Tile only" }, { K.ROCK_WHOLE, "Whole rock" }, { K.ROCK_ERASE, "Erase rock" } }
K.ROCK_RECORDS = 1024                    -- rock tiles a whole-rock move remembers between frames
K.ROCK_REACH = 4                         -- a rock's tiles lie this far around its position at most
K.ROCK_POSITION = { x = 0x12, y = 0x14 } -- in a rock slot
-- Strength 1-16: raise and lower land by that much; equalize moves a tile by (difference to
-- the middle) / (17 - strength) + 1, so 7 is the game's own rate (/ 10).
K.STRENGTH_MOST, K.STRENGTH_SUM = 16, 17
K.STRENGTH_DEFAULTS = { [2] = 1, [3] = 1, [23] = 7 }
-- raiseLand, per tile: `and dword [esi+eax*4+LOGIC], ~0x80 / test [...],river / je / add [height],8`
-- (the rocky flag goes: a rock's tile turns invisible and walkable) and, further on, `mov bl,
-- [esp+0x24] / add [eax+esi+HEIGHT],bl / mov byte [eax+esi+DECORATION],0` (the amount, which wraps
-- below 0, and the ground's look going back to plain).
K.AOB_RAISE_AND = "81 A4 86 ? ? ? ? 7F FF FF FF F7 84 86 ? ? ? ? 00 00 10 00 74 08 80 84 30"
K.RAISE_AND = { size = 11, logic = 3 }
K.AOB_RAISE_ADD = "8A 5C 24 24 00 9C 30 ? ? ? ? C6 84 30 ? ? ? ? 00 0F B6 9C 30"
K.RAISE_ADD = { size = 19, height = 7, decoration = 14 }
-- useLevelBrush: the same `and`, and the step towards the middle height `mov ecx,esi / sub ecx,eax
-- / ... (/ 10) ... / add cl,bl / add cl,1 / jmp store` up and `movzx edx,cl / sub edx,esi / ...
-- / sub cl,al / sub cl,1` down, then `mov [height],cl / mov byte [DECORATION],0`.
K.AOB_LEVEL_AND = "81 A4 AF ? ? ? ? 7F FF FF FF 0F B6 84 2F ? ? ? ? 3B C6 7D 26"
K.LEVEL_AND = { size = 11, logic = 3 }
K.AOB_LEVEL_RISE = "8B CE 2B C8 B8 67 66 66 66 F7 E9 C1 FA 02 8B CA C1 E9 1F 03 CA 02 CB 80 C1 01 EB 24"
K.LEVEL_RISE = { size = 28, store = 0x40 }
K.AOB_LEVEL_FALL = "0F B6 D1 2B D6 B8 67 66 66 66 F7 EA C1 FA 02 8B C2 C1 E8 1F 03 C2 2A C8 80 E9 01 88 8C 2F"
K.LEVEL_FALL = { size = 27 }
K.AOB_LEVEL_DECORATION = "C6 84 2F ? ? ? ? 00 80 BC 2F ? ? ? ? 08 73 08 C6 84 2F ? ? ? ? 08 80 BC 2F ? ? ? ? 9C"
K.LEVEL_DECORATION = { size = 8, decoration = 3 }
-- createPlateau: the same `and` (`... / cmp eax,4 / jne`), and `mov [edi+ebp+DECORATION],al`
-- (the plateau look, 4 or 8).
K.AOB_PLATEAU_AND = "81 A4 AF ? ? ? ? 7F FF FF FF 83 F8 04 75 0A"
K.PLATEAU_AND = { size = 11, logic = 3 }
K.AOB_PLATEAU_DECORATION = "88 84 2F ? ? ? ? 89 AF ? ? ? ? 89 9F"
K.PLATEAU_DECORATION = { size = 7, decoration = 3 }
-- useTerrainHeightBrush (min and max height): `and byte [DECORATION],0xF3` (min only: the
-- plateau looks go), then for both `test byte [LOGIC],0x80 / je and` and the rock's removal
-- (K.AOB_HEIGHT_ROCK), the `and` at +0x29, the code after it at +0x34.
K.AOB_MIN_DECORATION = "80 A4 2F ? ? ? ? F3 F6 84 AF ? ? ? ? 80 74 1F"
K.MIN_DECORATION = { size = 8, decoration = 3 }
K.MIN_ROCK = { size = 10, logic = 3, andSite = 0x29, afterAnd = 0x34 }
-- The landscape editor's click: raise `mov dword [command param],1 / call queueCommand / ...`
-- and lower `mov dword [command param],-1 / push 0x14 / jmp`: the amounts the commands carry.
K.AOB_RAISE_AMOUNT = "C7 05 ? ? ? ? 01 00 00 00 E8 ? ? ? ? 5F 5E 5B C3 C7 05 ? ? ? ? 05 00 00 00 6A 1B"
K.AOB_LOWER_AMOUNT = "C7 05 ? ? ? ? FF FF FF FF 6A 14 E9"
K.AMOUNT_VALUE = 6
-- The heights panel above the menu, and the button that removes lost rocks.
-- The texture mask. setTerrain's tile loop starts `mov ecx,[ebp+0xC] / mov edx,[ebp-0x20] / mov
-- eax,[edx+ecx*4+LOGIC] / and eax,0x10 / je / jmp <next tile>` (the clicked tile is [ebp-0x1C]);
-- setLand's `mov esi,[esp+0x18] / mov eax,[edi+esi*4+LOGIC] / test al,0x30 / jne <next tile>`
-- (the clicked tile is ebx); setTerrain calls setLand first for the ground looks: `push edx /
-- mov eax,[ebp+0xC] / push eax / mov ecx,[ebp-0x20] / call setLand / cmp [ebp+0x18],0x40000000`.
K.AOB_MASK_TERRAIN = "8B 4D 0C 8B 55 E0 8B 84 8A ? ? ? ? 83 E0 10 74 02 EB 90"
K.MASK_TERRAIN = { size = 13, logic = 9, next = 0x13 }
K.AOB_MASK_LAND = "8B 74 24 18 8B 84 B7 ? ? ? ? A8 30 0F 85"
K.MASK_LAND = { size = 11, logic = 7, next = 0x0F }
K.AOB_MASK_CALL = "52 8B 45 0C 50 8B 4D E0 E8 ? ? ? ? 81 7D 18 00 00 00 40"
K.MASK_CALL = 8
-- ...and in the other nature tools, at the start of each tile: raiseLand (raise, lower, hill,
-- mountain) `mov eax,[esp+0x18] / mov ecx,[esi+eax*4+LOGIC] / test cl,0x30 / jne <next>`;
-- useLevelBrush, useTerrainHeightBrush and createPlateau `mov ebp,[esp+TILE] / mov eax,[edi+ebp*4+
-- LOGIC] / test al,0x30 / jne <next>` (told apart by what follows); placeTree `test [edi+ebp*4+
-- LOGIC],0x703E25B5 / mov / mov / mov / jne <leave>`; placeRock's start `push ecx / mov eax,[esp+8]`.
K.AOB_MASK_RAISE = "8B 44 24 18 8B 8C 86 ? ? ? ? F6 C1 30 0F 85"
K.MASK_RAISE = { size = 11, logic = 7, next = 0x10 }
K.AOB_MASK_LEVEL = "8B 6C 24 24 8B 84 AF ? ? ? ? A8 30 0F 85 ? ? ? ? 8B C8 81 E1 01 00 00 20"
K.AOB_MASK_MIN = "8B 6C 24 24 8B 84 AF ? ? ? ? A8 30 0F 85 ? ? ? ? A9 01 05 00 70"
K.AOB_MASK_PLATEAU = "8B 6C 24 20 8B 84 AF ? ? ? ? A8 30 0F 85 ? ? ? ? A9 01 04 00 70"
K.MASK_BRUSH = { size = 11, tile = 3, logic = 7, next = 0x0F }
K.MASK_LEVEL_CLICKED = 0x18                 -- useLevelBrush keeps the clicked tile there
K.AOB_MASK_TREE = "F7 84 AF ? ? ? ? B5 25 3E 70 89 44 24 18 8B 04 85 ? ? ? ? 89 44 24 14 89 6C 24 24 0F 85"
K.MASK_TREE = { size = 11, logic = 3, test = 7, leave = 0x20 }
K.AOB_MASK_ROCK = "51 8B 44 24 08 53 55 56 57 33 DB 33 FF 3D 8F 01 00 00"
K.MASK_ROCK = { size = 5 }
-- The mask button: at the top left of the menu's panel, right of the category buttons (menu
-- coordinates; the category buttons sit at user controls 137..182, 460).
K.MASK_BUTTON = { x = 240, y = 455 }
K.HEIGHT_PANEL = { gap = 14, slider = 112, rangeSlider = 256, sliderHeight = 10, dropdown = 6, optionHeight = 20,
  rowGap = 4 }
-- The height range of raise, lower and equalize (the game's: 8 .. 128 for raise and lower, 8 ..
-- 156 for equalize), Snap to range, Invert and the ignore boxes.
K.HEIGHT_RANGE_DEFAULT = { 8, 156 }
K.LEFT_BUTTON = 1                        -- VK_LBUTTON, for following a slider
K.WATER_FLAGS = 0x60304001               -- sea, river, ford, marsh, planned or dug moat
K.FARMLAND_LOOKS = 0x91                  -- scrub, oasis grass, thick scrub
-- raiseLand's limits for ordinary ground: `je / xor ecx,ecx / lea edx,[ecx+0x14] / jmp / mov ecx,8
-- / lea edx,[ecx+0x78]`.
K.AOB_RAISE_RANGE = "74 07 33 C9 8D 51 14 EB 08 B9 08 00 00 00 8D 51 78"
K.RAISE_RANGE = { site = 9, size = 8, lowest = 1, highestAdd = 7 }
-- useLevelBrush: its limits (8 and 0x9C), the first loop's height read (`mov eax,[esp+0x24] / test
-- [edi+eax*4+LOGIC],0x30 / jne next / movzx eax,byte [eax+edi+HEIGHT] / cmp eax,ebx`) and the
-- step's `jle <no step> / mov cl,[height]` for a tile at or above the middle.
K.AOB_LEVEL_RANGE = "C6 84 2F ? ? ? ? 00 80 BC 2F ? ? ? ? 08 73 08 C6 84 2F ? ? ? ? 08 80 BC 2F ? ? ? ? 9C 76 08 C6 84 2F ? ? ? ? 9C"
K.LEVEL_RANGE = { site = 8, size = 36, height = 3 }   -- after `mov byte [DECORATION],0`
K.AOB_LEVEL_AVERAGE = "8B 44 24 24 F6 84 87 ? ? ? ? 30 75 18 0F B6 84 38 ? ? ? ? 3B C3"
K.LEVEL_AVERAGE = { site = 0x0E, size = 8, height = 0x12, next = 0x26 }
K.AOB_LEVEL_EQUAL = "7E 31 8A 8C 2F ? ? ? ? 0F B6 D1 2B D6"
K.LEVEL_EQUAL = { size = 9, height = 5, noStep = 0x33 }
-- The map drawing's patch site (renderMap's call and the floater pass) is editor/frame.lua's.
K.PLANT_TOOLS = 512                      -- the tree preview's table of tools, a byte each
-- placeTree turns a tile down with these flags (and with a plant on it).
K.TREE_REFUSED, K.TREE_FOOT_REFUSED = 0x703E25B5, 0x10100500
-- placeTree's room check (its tree-type argument `movsx eax,word [esp+0x24] / push ebp / push 3 /
-- push eax / mov ecx,organisms / call / push eax / mov ecx,organisms / call / lea ecx,[esi+esi*2] /
-- ... / mov eax,[eax*4+room]`): neighbours with these flags (border) end the look.
K.AOB_TREE_ROOM = "0F BF 44 24 24 55 6A 03 50 B9 ? ? ? ? E8 ? ? ? ? 50 B9 ? ? ? ? E8"
K.TREE_ROOM = { this = 10, first = 14, second = 25, room = { 0x3A, { 0x8B, 0x04, 0x85 } }, kinds = 64, most = 64 }
K.TREE_ROOM_EDGE = 0x10
-- The variant panels' pictures: the building composed from its tiles, made smaller to fit.
K.VARIANT_THUMB = { width = 72, height = 84 }
K.LOST_ROCKS_LABEL = "Remove lost rocks"
K.LOST_ROCKS_BUTTON = { padding = 5, height = 22, below = 6 }
-- The in-game key handlers' guard (five share it): `... cmp [menu guard],-1`, -1 while nothing
-- takes the keyboard (no text box).
K.AOB_KEY_GUARD = "F7 C1 00 00 00 40 0F 85 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 84 ? ? ? ? 83 3D ? ? ? ? FF 75 77 A1 ? ? ? ? 8B 0C 85"
K.KEY_GUARD = 32

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

-- The panels above the menus: placed by editor/lane.lua, squeezed together when wider than the screen.
local PANEL_BOTTOM = 444
local PANEL_PADDING, PANEL_GAP, PANEL_MARGIN = 4, 2, 4
-- The present function, where it reads the screen size: mov edx,[width] / mov edi,[height].
local AOB_SCREEN_SIZE = "8B 15 ? ? ? ? 8B 3D ? ? ? ? 89 44 24 20 03 C2 89 44 24 28"
local SCREEN_WIDTH_OPERAND, SCREEN_HEIGHT_OPERAND = 2, 8
local MOST_LOGS = 9                      -- buttons in the felled tree panel

-- The unit count, and the limit the editor tests it against before placing more.
K.AOB_UNITS = "81 3D ? ? ? ? ? ? 00 00 7C 03 57 EB 01 55 6A 1D E8 ? ? ? ? 83 C4 08 A1"
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

return {
  templates = templates,
  png = png,
  MODULE_NAME = MODULE_NAME,
  MODULE_FOLDERS = MODULE_FOLDERS,
  DEFAULTS = DEFAULTS,
  LANDSCAPE_KEY_RECORD = LANDSCAPE_KEY_RECORD,
  KEY_BUTTON_ITEM = KEY_BUTTON_ITEM,
  ITEM_COUNT = ITEM_COUNT,
  MAP_CLICK_ITEM = MAP_CLICK_ITEM,
  MENU_ITEM_SIZE = MENU_ITEM_SIZE,
  ITEM_TYPE = ITEM_TYPE,
  ITEM_X = ITEM_X,
  ITEM_Y = ITEM_Y,
  ITEM_WIDTH = ITEM_WIDTH,
  ITEM_HEIGHT = ITEM_HEIGHT,
  ITEM_ACTION = ITEM_ACTION,
  ITEM_PARAM = ITEM_PARAM,
  ITEM_RENDER = ITEM_RENDER,
  ITEM_IMAGE = ITEM_IMAGE,
  ITEM_RENDER_TYPE = ITEM_RENDER_TYPE,
  ITEM_TEXT = ITEM_TEXT,
  ITEM_CONTROL = ITEM_CONTROL,
  ITEM_HOVERED = ITEM_HOVERED,
  ITEM_HIDDEN = ITEM_HIDDEN,
  ITEM_MENU = ITEM_MENU,
  TYPE_EVERY_FRAME = TYPE_EVERY_FRAME,
  TYPE_CLICKABLE = TYPE_CLICKABLE,
  TYPE_GROUP_START = TYPE_GROUP_START,
  TYPE_BLOCK = TYPE_BLOCK,
  TYPE_END = TYPE_END,
  TYPE_GROUP_MEMBER_MASK = TYPE_GROUP_MEMBER_MASK,
  TYPE_GROUP_MEMBER = TYPE_GROUP_MEMBER,
  RENDER_NONE = RENDER_NONE,
  RENDER_SIMPLE = RENDER_SIMPLE,
  RENDER_IMAGE = RENDER_IMAGE,
  PLACED_BY_CONTROL = PLACED_BY_CONTROL,
  IMAGE_INDEX_MASK = IMAGE_INDEX_MASK,
  MENU_X = MENU_X,
  MENU_Y = MENU_Y,
  MENU_SCROLL = MENU_SCROLL,
  HOVER_TEXT_ITEM = HOVER_TEXT_ITEM,
  HOVER_TEXT_POSITION = HOVER_TEXT_POSITION,
  INFO_IMAGE = INFO_IMAGE,
  INFO_BUTTON = INFO_BUTTON,
  INFO_BEFORE_ITEM = INFO_BEFORE_ITEM,
  HOVER_TEXT_MOVED_X = HOVER_TEXT_MOVED_X,
  DEER = DEER,
  LION = LION,
  RABBIT = RABBIT,
  CAMEL = CAMEL,
  TEXTURES = TEXTURES,
  VEGETATION = VEGETATION,
  ANIMALS = ANIMALS,
  ROCKS = ROCKS,
  FIRST_TREE_COMMAND = FIRST_TREE_COMMAND,
  LAST_TREE_COMMAND = LAST_TREE_COMMAND,
  SHRUB_COMMANDS = SHRUB_COMMANDS,
  APPLE_COMMAND = APPLE_COMMAND,
  APPLE_TYPE = APPLE_TYPE,
  GRAVEL_COMMAND = GRAVEL_COMMAND,
  IRON_COMMAND = IRON_COMMAND,
  TEXTURE_ROWS = TEXTURE_ROWS,
  VEGETATION_TREES = VEGETATION_TREES,
  TOP_ROW_SHRUB = TOP_ROW_SHRUB,
  SORTED_SHRUBS = SORTED_SHRUBS,
  ROW_LEFT = ROW_LEFT,
  ROW_RIGHT = ROW_RIGHT,
  OBSTACLES_BUTTON = OBSTACLES_BUTTON,
  K = K,
  C = C,
  BUTTON_RENDER = BUTTON_RENDER,
  BUTTON_WIDTH = BUTTON_WIDTH,
  IMAGE_SIZE = IMAGE_SIZE,
  MAP_CLICK = MAP_CLICK,
  HOVER_RENDER_BYTES = HOVER_RENDER_BYTES,
  HOVER_RENDER_CALL = HOVER_RENDER_CALL,
  CAMERA_X = CAMERA_X,
  CAMERA_Y = CAMERA_Y,
  TEXT_LAYER = TEXT_LAYER,
  AOB_AMMO_COUNT = AOB_AMMO_COUNT,
  AMMO_WIDTH = AMMO_WIDTH,
  AMMO_TEXT_MANAGER = AMMO_TEXT_MANAGER,
  AMMO_RENDER_NUMBER = AMMO_RENDER_NUMBER,
  NUMBER_FONT = NUMBER_FONT,
  NUMBER_COLOUR = NUMBER_COLOUR,
  NUMBER_FROM_BOTTOM = NUMBER_FROM_BOTTOM,
  AOB_NAME_BOX = AOB_NAME_BOX,
  NAME_BOX = NAME_BOX,
  WIDTH_UNTIL_CURSOR_CALL = WIDTH_UNTIL_CURSOR_CALL,
  COLOUR_BOX_SURFACE = COLOUR_BOX_SURFACE,
  COLOUR_BOX_CLIP = COLOUR_BOX_CLIP,
  PENCIL_TARGET = PENCIL_TARGET,
  BOX_BLEND = BOX_BLEND,
  AOB_PIXEL_FORMAT = AOB_PIXEL_FORMAT,
  PIXEL_FORMAT_OPERAND = PIXEL_FORMAT_OPERAND,
  AOB_MENU_ITEM = AOB_MENU_ITEM,
  MENU_ITEM_MOUSE = MENU_ITEM_MOUSE,
  MENU_ITEM_IS_INSIDE = MENU_ITEM_IS_INSIDE,
  TOOLTIP_FONT = TOOLTIP_FONT,
  TOOLTIP_COLOUR = TOOLTIP_COLOUR,
  TOOLTIP_LINE = TOOLTIP_LINE,
  TOOLTIP_PADDING = TOOLTIP_PADDING,
  TOOLTIP_BOTTOM = TOOLTIP_BOTTOM,
  ALIGN_LEFT = ALIGN_LEFT,
  MAP_LAYER = MAP_LAYER,
  AOB_RENDER_GM = AOB_RENDER_GM,
  RENDER_GM = RENDER_GM,
  ANIMATION = ANIMATION,
  PICTURE_SIZE = PICTURE_SIZE,
  TEXTURES_MODE = TEXTURES_MODE,
  TEXTURES_DIRECT_PALETTE = TEXTURES_DIRECT_PALETTE,
  TEXTURES_DATA = TEXTURES_DATA,
  AOB_NEW_TREE = AOB_NEW_TREE,
  NEW_TREE = NEW_TREE,
  TREE_TYPE_FROM_IN_USE = TREE_TYPE_FROM_IN_USE,
  TREE_TYPES = TREE_TYPES,
  AOB_NEW_ROCK = AOB_NEW_ROCK,
  NEW_ROCK = NEW_ROCK,
  AOB_NEW_GROUP = AOB_NEW_GROUP,
  NEW_GROUP = NEW_GROUP,
  AOB_GROUPS = AOB_GROUPS,
  GROUPS_OBJECT = GROUPS_OBJECT,
  GROUPS_CALL = GROUPS_CALL,
  AOB_TREE_TYPE = AOB_TREE_TYPE,
  TREE_TYPE_START = TREE_TYPE_START,
  AOB_PLACE_TREE = AOB_PLACE_TREE,
  PLACE_TREE = PLACE_TREE,
  CREATE_TREE = CREATE_TREE,
  STAGES = STAGES,
  MAX_STAGE = MAX_STAGE,
  PLACED_STAGE = PLACED_STAGE,
  TREES_IN_LANDSCAPE = TREES_IN_LANDSCAPE,
  TREE = TREE,
  LYING_FELLED = LYING_FELLED,
  LAST_TREE_TYPE = LAST_TREE_TYPE,
  FELLED_PICTURE_BASE = FELLED_PICTURE_BASE,
  SHRUB_PALETTES = SHRUB_PALETTES,
  SHRUB_PICTURE = SHRUB_PICTURE,
  FELLED_PALETTE = FELLED_PALETTE,
  PANEL_BOTTOM = PANEL_BOTTOM,
  PANEL_PADDING = PANEL_PADDING,
  PANEL_GAP = PANEL_GAP,
  PANEL_MARGIN = PANEL_MARGIN,
  AOB_SCREEN_SIZE = AOB_SCREEN_SIZE,
  SCREEN_WIDTH_OPERAND = SCREEN_WIDTH_OPERAND,
  SCREEN_HEIGHT_OPERAND = SCREEN_HEIGHT_OPERAND,
  MOST_LOGS = MOST_LOGS,
  AOB_MENU_REDRAW = AOB_MENU_REDRAW,
  MENU_REDRAW_SITE = MENU_REDRAW_SITE,
  MENU_REDRAW_SIZE = MENU_REDRAW_SIZE,
  AOB_GAME_MODE = AOB_GAME_MODE,
  GAME_MODE_OPERAND = GAME_MODE_OPERAND,
  AOB_IMAGE_BUTTON = AOB_IMAGE_BUTTON,
}

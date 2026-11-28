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
local ITEM_IMAGE = layout.ITEM_IMAGE
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local IMAGE_INDEX_MASK = layout.IMAGE_INDEX_MASK
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local DEER = layout.DEER
local ANIMALS = layout.ANIMALS
local K = layout.K
local C = layout.C
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_LINE = layout.TOOLTIP_LINE
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readCallTarget = memory.readCallTarget
local item = memory.item
local writeCString = memory.writeCString
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local buttonPictures = require("editor.images").buttonPictures
local makePanel = require("editor.ui").makePanel
local patchJump = require("editor.menu_install").patchJump

---------------------------------------------------------------------------------------
-- Constants of 36-39
---------------------------------------------------------------------------------------

-- The unit limit the editor really has (the "N more units" line computes 2499 / 9999 - count;
-- K.AOB_UNITS' test, 2300 / 9800, is only where that line starts).
K.AOB_UNIT_MAX = "8D 44 38 06 B9 ? ? ? ? 2B 0D"
K.UNIT_MAX = 5
K.GROUP_MARGIN = 200                     -- the herds and groups line from fewer than this left
K.GROUP_WARNING_Y, K.GROUP_WARNING_BELOW = 10, 30
-- Crows: markNearbyTreesAsCrowTargets (esi = a tree's stage word, its in-use word at -0x3C) sets
-- `mov word [esi+0x14], 1`: the crow word, 0x50 after the in-use word; the word after it says
-- the crows flew off.
K.AOB_CROW_MARK = "66 83 7E C4 02 75 ? 83 3E 04 7D"
K.CROW_MARK_IN_USE = 0x3C
K.TREE_CROW = 0x50
K.CROW_TOOL, K.GULL_TOOL = 224, 225
-- deleteAllSeagulls (VAN 0x404A70): `cmp word [eax + state], 2 / cmp word [eax + kind], 0x1D /
-- push ecx / mov ecx, entityState / call deleteEntity`, entity count at +0x42.
K.AOB_DELETE_GULLS = "B9 01 00 00 00 56 89 0D ? ? ? ? BE 02 00 00 00 8B C1 69 C0 E8 00 00 00 66 39 B0 ? ? ? ? "
  .. "75 1B 66 83 B8 ? ? ? ? 1D 75 11 51 B9 ? ? ? ? E8"
K.DELETE_GULLS = { state = 28, kind = 37, entities = 46, delete = 50, limit = 0x40 }
-- createSeagull: `mov ebx, 1 / lea esi, [edi + slot 1]`, `cmp ebx, 0x64` ends the slots.
K.AOB_NEW_GULL = "BB 01 00 00 00 8D B7 ? ? ? ? 66 83 7E 08 00 74"
K.NEW_GULL = { first = 7, limit = 0x42 }
K.ENTITY = { size = 0xE8, state = 0x28, kind = 0x2A, uid = 0x30, tile = 0x4C }
K.GULL = { size = 0x64, uid = 4, state = 8 }
K.ENTITY_ALIVE, K.CROW_ENTITY = 2, 0x1C
-- Alt + E in the map editor: `mov ecx, units / call deleteAllAnimals`.
K.AOB_DELETE_ANIMALS = "83 F8 11 74 1A 83 F8 0C 74 15 83 F8 0E 0F 85 ? ? ? ? 39 2D ? ? ? ? 0F 85 ? ? ? ? B9 ? ? ? ? E8"
K.DELETE_ANIMALS = { units = 0x20, call = 0x24 }
K.BIN_GAP = 4
K.ANIMAL_BIN_X = 612

-- The eraser (button and tool 39) and what it may take.
K.ERASER_TOOL = 39
K.ERASE_ALL, K.ERASE_ANIMALS, K.ERASE_UNITS, K.ERASE_BUILDINGS, K.ERASE_PLANTS, K.ERASE_ROCKS = 0, 1, 2, 3, 4, 5
K.ERASER_MODES = {                       -- in the order of the numbers above
  { label = "All" }, { label = "Animals", tab = 235 }, { label = "Units", build = 26 },
  { label = "Buildings", build = 30 }, { label = "Vegetation", tab = 234 }, { label = "Rocks", tab = 237 },
}
K.ERASER_ENTRY_WIDTH = 72
K.PANEL_PICTURE_GAP = 2
K.ROCK_ORGANISM_FIRST = 2000
K.ERASE_ORGANISM_BEFORE = 12             -- movsx eax, word [esi + reg*2 + organisms] / test / je
-- The second loop: `mov dword [esi + wall found], 0 / call findBuildingOrWallAt / cmp [blocked], 0
-- / jne / cmp [wall found], 0 / jne / mov eax, [building found] / cmp eax, -1`.
K.AOB_ERASE_BUILDING = "C7 86 ? ? ? ? 00 00 00 00 E8 ? ? ? ? 83 BE ? ? ? ? 00 0F 85 ? ? ? ? 83 BE ? ? ? ? 00 "
  .. "0F 85 ? ? ? ? 8B 86 ? ? ? ? 83 F8 FF"
K.ERASE_BUILDING = { call = 10, blocked = 17, wall = 30, building = 43 }
-- The third loop: `mov word [eax + state], 3 / movsx eax, word [eax + next on tile]`; the tile's
-- first unit is read 0x12 (brush) or 0x18 (area) bytes before.
K.AOB_ERASE_UNIT = "66 C7 80 ? ? ? ? 03 00 0F BF 80 ? ? ? ? 85 C0 75 E6"
K.ERASE_UNIT = { state = 3, size = 9, mapBack = { 0x12, 0x18 } }
K.UNIT_TYPE_AFTER_STATE = 2
K.ANIMAL_TYPES = 128
-- Deer, lion, rabbit, camel, crow, seagull, cow, chicken and the burning animals.
K.ANIMAL_UNIT_TYPES = { 44, 45, 46, 47, 48, 49, 51, 62, 68, 69 }

-- The Vegetation menu's trees by what they spread on: the first three on fertile ground, the
-- fourth on infertile ground (39).
K.SPREAD_TREES = { 41, 42, 43, 40 }
K.SPREAD_FERTILE = { [41] = true, [42] = true, [43] = true }
K.SPREAD_COLOURS = { fertile = { 72, 184, 56 }, infertile = { 226, 204, 152 } }

-- Map settings: the Alt + , menu (modal 0x1F, 400 x 300; group: Single 0xA, Multi 0xB, sizes
-- 0x14-0x17; its action also still knows the lock states 0-2 and the map types 3-6, its renderer
-- their labels and King of the Hill 0xC).
K.AOB_SETTINGS_MODAL = "68 ? ? ? ? 68 ? ? ? ? 50 68 00 02 00 00 68 ? ? ? ? 68 ? ? ? ? 6A FF 6A FF 6A 1F B9"
K.SETTINGS_MODAL = { menu = 1, height = 17, width = 22, record = 33 }
K.SETTINGS_MODAL_ID = 0x1F
K.MODAL_WIDTH, K.MODAL_HEIGHT = 0x0C, 0x10
K.SETTINGS_SINGLE_RECORD = "03 00 00 02 19 00 00 00 14 00 00 00 96 00 00 00 1B 00 00 00 00 00 00 00 0A 00 00 00"
K.SETTINGS_ITEMS = 7
K.SETTINGS_HOVER = 3                    -- mov ebx, [hover]
K.RECT_BEFORE_HOVER = 0x10
K.AOB_SETTINGS_RENDER = "53 8B 1D ? ? ? ? 56 8B 74 24 0C 83 FE 03 57 C7 05 ? ? ? ? 00 00 00 00 BF 01 00 00 00 7D 11"
K.SETTINGS_DRAW = { background = 0xD8, text = 0x19B }
K.AOB_BUTTON_BACKGROUND = "6A FF 6A 00 B9 ? ? ? ? E8"
K.BUTTON_BACKGROUND = { this = 5, call = 9 }
K.AOB_BUTTON_TEXT = "B9 ? ? ? ? E8 ? ? ? ? 5F 5E 5B C3"
K.AOB_SETTINGS_LABELS = "B9 ? ? ? ? EB 2F B9 ? ? ? ? EB 28 B9 ? ? ? ? EB 21 B9"
K.SETTINGS_LABELS = { single = 8, multi = 15 }
K.AOB_SETTINGS_KOTH = "83 FE 0C 75 18 83 3D ? ? ? ? 00 0F 84 ? ? ? ? 83 3D ? ? ? ? 00 74"
K.SETTINGS_KOTH = { multi = 7, koth = 20 }
K.AOB_BALANCED = "39 0D ? ? ? ? 89 0D ? ? ? ? 75 05 83 FE FD"
K.BALANCED = 2
K.AOB_SETTINGS_ACTION = "83 FE 17 77 14 0F B6 86 ? ? ? ? FF 24 85 ? ? ? ? 89 35 ? ? ? ? 5E C3"
K.SETTINGS_LOCK = 21
K.MAP_LOCKED = 2                         -- "Mission": locked, still in the skirmish map list
K.AOB_SETTINGS_SIZE = "B8 90 01 00 00 74 04 8B 44 24 08 50 B9 ? ? ? ? A3 ? ? ? ?"
K.SETTINGS_SIZE_VAR = 18
K.AOB_SETTINGS_SIZE_ENTRY = "B9 ? ? ? ? E8 ? ? ? ? 83 FE 14 75 07 B8 A0 00 00 00"
K.AOB_ALT_COMMA = "83 3D ? ? ? ? 11 0F 85 ? ? ? ? A1 ? ? ? ? 83 F8 1F 75 13 6A 00 6A FF B9 ? ? ? ? E8"
K.ALT_COMMA = { modal = 14, manager = 28, open = 32 }
K.MAP_TYPE_PARAMS = { 3, 4, 5, 6 }       -- Siege, Invasion, Economic, Just Build
K.MAP_SIZE_PARAMS = { 0x14, 0x15, 0x16, 0x17 }
K.MAP_SIZES = { 160, 200, 300, 400 }
K.MAP_SIZE_RANGE = { 10, 400 }
K.SETTINGS_SIZE = { width = 560, height = 410 }
K.SETTINGS_LAYOUT = {
  title = { y = 12 },
  single = { x = 30, y = 44, width = 240 }, multi = { x = 290, y = 44, width = 240 },
  types = { { x = 50, y = 88, width = 200 }, { x = 50, y = 118, width = 200 }, { x = 50, y = 148, width = 200 },
    { x = 50, y = 178, width = 200 } },
  sizes = { { x = 310, y = 88, width = 200 }, { x = 310, y = 118, width = 200 }, { x = 310, y = 148, width = 200 },
    { x = 310, y = 178, width = 200 } },
  custom = { x = 310, y = 208, width = 200 },
  slider = { x = 310, y = 250, width = 200 },
  balanced = { x = 50, y = 222, width = 200 }, koth = { x = 50, y = 252, width = 200 },
  lock = { x = 180, y = 300, width = 200 },
  back = { x = 180, y = 362, width = 200 },
}
K.SLIDER_INSET = 6
K.TITLE_FONT, K.BUTTON_FONT = 0x13, 0x11
K.TEXT_NORMAL, K.TEXT_HOVERED = 0xC2F0EB, 0xCCFAFF
K.BUTTON_TEXT_DOWN = 4
K.CHECK_INSET, K.CHECK_SIZE = 7, 13
-- The map menu (MapEditorProperties) table, found by its Balanced button (item 10); the Map
-- Settings button goes right of Balanced / Unbalanced and Invasion / Economy.
K.PROPERTIES_RECORD = "03 00 00 02 F0 00 00 00 EA 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 FD FF FF FF "
  .. "00 00 00 00 06 02 00 40 03 00 00 00"
K.PROPERTIES_ITEM = 10
K.SETTINGS_BUTTON = { x = 520, y = 474, width = 160, height = 27 }
K.MOST_DIALOG_ITEMS = 200
-- Locked maps: mapNames_filterMapsIfMapLock's `cmp dword [lock], 0 / jne DROP`.
K.AOB_LOCK_FILTER = "83 3D ? ? ? ? 00 75 0E 53 56 8B CF E8"
K.LOCK_FILTER = { size = 9, jump = 7 }
K.AOB_LOAD_MODAL = "68 ? ? ? ? 68 ? ? ? ? 50 68 00 02 00 00 68 8D 01 00 00 68 BC 02 00 00 6A FF 6A FF 6A 09 B9"
K.AOB_LOAD_ACTION = "6A 09 B9 ? ? ? ? 89 1D ? ? ? ? E8 ? ? ? ? 5B 5E 5D C3 39 2D ? ? ? ? 74"
K.LOAD_ACTION = { modal = 1, listState = 3, open = 13 }
K.MAP_LIST_KIND = 2
K.LOCKED_TOGGLE = { x = 55, y = 408, width = 200, height = 27 }

---------------------------------------------------------------------------------------
-- Birds, the animal buttons, the eraser's choice, the tree outlines (36, 37, 39)
---------------------------------------------------------------------------------------

-- Birds. Crows are no list of their own: the crow tool marks the grown trees near the click
-- (markNearbyTreesAsCrowTargets sets a word of the tree, K.TREE_CROW from its in-use word; the
-- word after it says the crows flew off). Seagulls are entities of type 0x1D with a slot each in
-- the entity state's seagull list (99 slots, 1..99; slot +0 entity, +4 its uid, +8 in use).
-- deleteAllSeagulls (the game's own, unused in the editor) deletes them all.
function C.resolveBirds(G)
  if C.birds ~= nil then return C.birds end
  local D = {}
  local mark = scan(K.AOB_CROW_MARK, "the crow tool")
  local found = false
  for at = mark, mark + 0x40 do
    if rd8(at) & 0xFF == 0x66 and rd8(at + 1) & 0xFF == 0xC7 and rd8(at + 2) & 0xFF == 0x46 then
      found = (rd8(at + 3) & 0xFF) + K.CROW_MARK_IN_USE == K.TREE_CROW
      break
    end
  end
  if not found then error(MODULE_NAME .. ": the crow tool is not the one this module knows") end
  local del = scan(K.AOB_DELETE_GULLS, "the seagull removal")
  local d = K.DELETE_GULLS
  D.deleteAllGulls = del
  D.entities = rd32(del + d.entities)
  D.entityZero = rd32(del + d.state) - K.ENTITY.state
  if rd32(del + d.kind) ~= D.entityZero + K.ENTITY.kind then
    error(MODULE_NAME .. ": the entity list is not laid out as the module expects")
  end
  D.deleteEntity = readCallTarget(del, d.delete, "deleteEntity")
  expectBytes(del + d.limit, { 0x81, 0xF9 }, "the seagull removal")
  D.entitySlots = rd32(del + d.limit + 2)
  local new = scan(K.AOB_NEW_GULL, "the seagull placement")
  D.firstGull = D.entities + rd32(new + K.NEW_GULL.first)
  expectBytes(new + K.NEW_GULL.limit, { 0x83, 0xFB }, "the seagull placement")
  D.gullSlots = rd8(new + K.NEW_GULL.limit + 2) & 0xFF        -- slots 1 .. gullSlots - 1
  C.birds = D
  return D
end

local eraseAnimals
local function resolveAnimalErase()
  if eraseAnimals == nil then
    local alt = scan(K.AOB_DELETE_ANIMALS, "Alt + E")
    local call = K.DELETE_ANIMALS
    local units = rd32(alt + call.units)
    local deleteAnimals = core.exposeCode(readCallTarget(alt, call.call, "the animal removal"), 1, 1)
    eraseAnimals = function()
      deleteAnimals(units)
      return true
    end
  end
  return eraseAnimals
end

function C.birdCounts(G, D)
  local crows, gulls = 0, 0
  for i = 0, G.treeSlots - 1 do
    local tree = G.firstTree + i * G.treeSize
    if rd16(tree) ~= 0 and rd16(tree + K.TREE_CROW) ~= 0 then crows = crows + 1 end
  end
  for i = 1, D.gullSlots - 1 do
    if rd16(D.firstGull + (i - 1) * K.GULL.size + K.GULL.state) ~= 0 then gulls = gulls + 1 end
  end
  return crows, gulls
end

local function resolveBirdBins(G)
  assert(G.buttons[K.CROW_TOOL] and G.buttons[K.GULL_TOOL], "the crow and seagull buttons are missing")
  local D = C.resolveBirds(G)
  local deleteEntity = core.exposeCode(D.deleteEntity, 2, 1)
  local deleteAllGulls = core.exposeCode(D.deleteAllGulls, 0, 0)
  local function eraseCrows()
    for i = 0, G.treeSlots - 1 do
      local tree = G.firstTree + i * G.treeSize
      if rd16(tree) ~= 0 then
        wr16(tree + K.TREE_CROW, 0)
        wr16(tree + K.TREE_CROW + 2, 0)
      end
    end
    for id = 1, D.entitySlots - 1 do                 -- crows already in the air
      local entity = D.entityZero + id * K.ENTITY.size
      if rd16(entity + K.ENTITY.state) == K.ENTITY_ALIVE and rd16(entity + K.ENTITY.kind) == K.CROW_ENTITY then
        deleteEntity(D.entities, id)
      end
    end
  end
  return {
    { kind = "crowBin", beside = K.CROW_TOOL, fn = eraseCrows, text = "Erase all crows" },
    { kind = "gullBin", beside = K.GULL_TOOL, fn = function() deleteAllGulls() end, text = "Erase all seagulls" },
  }
end

function C.resolveAnimalBins(G, O)
  local bins = {}
  if O.birdButtons then
    local ok, result = pcall(resolveBirdBins, G)
    if ok then
      bins = result
    else
      log(ERROR, "The bird removal buttons are off: " .. tostring(result))
    end
  end
  if O.animalBin then
    local ok, erase = pcall(resolveAnimalErase)
    if ok and G.buttons[DEER] ~= nil then
      bins[#bins + 1] = { kind = "animalBin", fn = erase, text = "Erase all land animals" }
    else
      log(ERROR, "The All Animals button is off: " .. (ok and "the deer button is missing" or tostring(erase)))
    end
  end
  return bins
end

-- The bird bins sit next to their tools, and All Animals sits to the right.
function C.animalsMenu(M, bins)
  local G = M.G
  local pictures = buttonPictures("bin")
  local never = core.allocate(4, true)
  if G.blit == nil then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local render = core.allocateAssembly(templates.flagPictureButton, {
    NORMAL = pictures.normal, HOVERED = pictures.hover, CHOSEN = pictures.chosen, FLAG = never,
    HOVER = G.hover, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET, ITEM_X = G.itemX, ITEM_Y = G.itemY,
    BLIT = G.blit,
  })
  for _, bin in ipairs(bins) do
    local into = M.added[bin.kind]
    bin.item, bin.model = into, M.button(bin.beside or DEER)
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_X, 0)
    wr32(into + ITEM_Y, 0)
    wr32(into + ITEM_WIDTH, pictures.width)
    wr32(into + ITEM_HEIGHT, pictures.height)
    wr32(into + ITEM_ACTION, C.luaPad(bin.fn, bin.text))
    wr32(into + ITEM_RENDER, render)
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_TEXT, 0)
    wr16(into + ITEM_CONTROL, -1)
    wr16(into + ITEM_HIDDEN, 1)
    M.guarded[#M.guarded + 1] = into
    M.guarded[#M.guarded + 1] = ANIMALS
    M.tooltips[#M.tooltips + 1] = { item = into, lines = function() return { bin.text } end,
      raise = K.CHECK_BOX_TOOLTIP_RAISE }
  end
  -- Placed once the menu has placed the buttons: a bird's bin right of its button, the animals'
  -- bin at the menu's right, level with the deer.
  M.places[#M.places + 1] = function()
    local rightmost = 0
    for _, bin in ipairs(bins) do
      if (rd32(bin.model + ITEM_X) & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
    end
    for _, bin in ipairs(bins) do
      local model = bin.model
      local x = K.ANIMAL_BIN_X
      if bin.beside ~= nil then
        x = rd32(model + ITEM_X) + rd32(model + ITEM_WIDTH) + K.BIN_GAP
        rightmost = math.max(rightmost, x + pictures.width)
      else
        x = math.max(x, rightmost + 3 * K.BIN_GAP)
      end
      wr32(bin.item + ITEM_X, x)
      wr32(bin.item + ITEM_Y, rd32(model + ITEM_Y) + (rd32(model + ITEM_HEIGHT) - pictures.height) // 2)
      wr16(bin.item + ITEM_HIDDEN, 0)
    end
    return true
  end
end

-- The eraser's choice (37.2): one word, K.ERASE_ALL .. K.ERASE_ROCKS.
function C.eraserWords()
  if C.eraser ~= nil then return C.eraser end
  C.eraser = { mode = core.allocate(4, true) }
  return C.eraser
end

-- The panel above the menu while the eraser is chosen: All, Animals, Units, Buildings,
-- Vegetation, Rocks, each the eraser's picture with the menu picture of what it takes.
function C.eraserMenu(M)
  local G, data, added = M.G, M.data, M.added
  local E = C.eraserWords()
  local eraser = G.buttons[K.ERASER_TOOL]
  if eraser == nil then error(MODULE_NAME .. ": the eraser button is missing") end
  local eraserImage = rd32(item(G.table, eraser.index, ITEM_IMAGE)) & IMAGE_INDEX_MASK
  local B = nil
  local ok = pcall(function() B = C.resolve(G) end)
  if not ok then B = nil end
  local function imageOf(mode)
    if mode.tab ~= nil and G.buttons[mode.tab] ~= nil then
      return rd32(item(G.table, G.buttons[mode.tab].index, ITEM_IMAGE)) & IMAGE_INDEX_MASK
    end
    if mode.build ~= nil and B ~= nil and B.buttons[0] ~= nil and B.buttons[0][mode.build] ~= nil then
      return B.buttons[0][mode.build].image
    end
    return nil
  end
  local panel = { items = {}, info = added.info }
  local entries = {}
  for i, mode in ipairs(K.ERASER_MODES) do
    local into = added["eraserMode" .. i]
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_ACTION, C.luaPad(function() wr32(E.mode, i - 1) end, "the eraser panel"))
    wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
    wr16(into + ITEM_HIDDEN, 1)
    panel.items[i] = into
    M.guarded[#M.guarded + 1] = into
    M.guarded[#M.guarded + 1] = 0
    entries[i] = { item = into, label = mode.label, image = eraserImage, image2 = imageOf(mode) }
  end
  local paint = makePanel(G, { counts = false }, data, panel, function(subtype)
    if subtype ~= K.ERASER_TOOL then return {} end
    local list = {}
    for i, entry in ipairs(entries) do
      list[i] = { item = entry.item, image = entry.image, image2 = entry.image2, label = entry.label,
        chosen = rd32(E.mode) == i - 1, minWidth = K.ERASER_ENTRY_WIDTH }
    end
    list.labelRoom = K.PIPETTE_LABEL_ROOM
    return list
  end)
  local into = added.eraserPanel
  wr32(into + ITEM_TYPE, TYPE_CLICKABLE)       -- no size, so never under the mouse
  wr32(into + ITEM_RENDER, C.luaPad(paint, "the eraser panel"))
  wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
end

-- The eraser follows the choice: all three of its loops, in both of its functions (the brush
-- and the area version), and with All or Animals it takes seagulls too.
function C.patchEraserChoice(self, G, choice, gulls)
  pcall(C.eraseTables)                     -- before this patch hides them from the search
  local E = C.eraserWords()
  local D = gulls and C.resolveBirds(G)
  local sites = C.eraseSites()
  local buildings = memory.scanAll(K.AOB_ERASE_BUILDING, K.ERASE_SITES + 1)
  local units = memory.scanAll(K.AOB_ERASE_UNIT, K.ERASE_SITES + 1)
  if #buildings ~= K.ERASE_SITES or #units ~= K.ERASE_SITES then
    error(MODULE_NAME .. ": the eraser is not the one this module knows")
  end
  local animals = {}
  for i = 1, K.ANIMAL_TYPES do animals[i] = 0 end
  for _, kind in ipairs(K.ANIMAL_UNIT_TYPES) do animals[kind + 1] = 1 end
  local animalTable = core.allocate(K.ANIMAL_TYPES, true)
  core.writeBytes(animalTable, animals)
  local modes = { MODE = E.mode, MODE_ALL = K.ERASE_ALL, MODE_ANIMALS = K.ERASE_ANIMALS, MODE_UNITS = K.ERASE_UNITS,
    MODE_BUILDINGS = K.ERASE_BUILDINGS, MODE_PLANTS = K.ERASE_PLANTS, MODE_ROCKS = K.ERASE_ROCKS }
  local function with(values)
    for k, v in pairs(modes) do values[k] = v end
    return values
  end
  -- Assembled first, patched after: all or nothing.
  local patches = {}
  for _, found in ipairs(sites) do
    local site = found - K.ERASE_ORGANISM_BEFORE
    expectBytes(site, { 0x0F, 0xBF, 0x84 }, "the eraser's first loop")
    if choice then
      patches[#patches + 1] = { site = site, size = 8, stub = C.assemble("eraseOrganism", with({
        ORIG_LO = rd32(site), ORIG_HI = rd32(site + 4), ROCK_FIRST = K.ROCK_ORGANISM_FIRST,
        TREE_SIZE = G.treeSize, CROW_BASE = G.firstTree - G.treeSize + K.TREE_CROW, BACK = site + 8,
      })) }
    end
  end
  for _, found in ipairs(buildings) do
    local b = K.ERASE_BUILDING
    local site = found + b.call
    if choice then
      patches[#patches + 1] = { call = true, site = site, stub = C.assemble("eraseBuilding", with({
        WALL_FOUND = rd32(found + b.wall), BLOCKED = rd32(found + b.blocked), BUILDING_FOUND = rd32(found + b.building),
        FIND = readCallTarget(site, 0, "the eraser's building search"),
      })) }
    end
  end
  for _, found in ipairs(units) do
    local u = K.ERASE_UNIT
    if choice then
      patches[#patches + 1] = { site = found, size = u.size, stub = C.assemble("eraseUnit", with({
        STATE = rd32(found + u.state), UNIT_TYPE = rd32(found + u.state) + K.UNIT_TYPE_AFTER_STATE,
        ANIMAL_TYPES = K.ANIMAL_TYPES, ANIMALS = animalTable, BACK = found + u.size,
      })) }
    end
    if gulls then
      local site = nil
      for _, back in ipairs(u.mapBack) do
        if rd8(found - back) & 0xFF == 0x0F and rd8(found - back + 1) & 0xFF == 0xBF
            and rd8(found - back + 2) & 0xFF == 0x04 then
          site = found - back
        end
      end
      if site == nil then error(MODULE_NAME .. ": the eraser's unit loop is not the one this module knows") end
      patches[#patches + 1] = { site = site, size = 8, stub = C.assemble("eraseGulls", with({
        ORIG_LO = rd32(site), ORIG_HI = rd32(site + 4), FIRST_GULL = D.firstGull, GULL_STATE = K.GULL.state,
        GULL_UID = K.GULL.uid, GULL_SIZE = K.GULL.size, GULL_SLOTS = D.gullSlots, ENTITY_SLOTS = D.entitySlots,
        ENTITY_SIZE = K.ENTITY.size, ENTITY_ZERO = D.entityZero, ENTITY_UID = K.ENTITY.uid,
        ENTITY_TILE = K.ENTITY.tile, ENTITY_STATE = D.entities, DELETE_ENTITY = D.deleteEntity, BACK = site + 8,
      })) }
    end
  end
  for _, patch in ipairs(patches) do
    if patch.call then C.patchCall(self, patch.site, patch.stub) else patchJump(self, patch.site, patch.size, patch.stub) end
  end
end

-- Thin outlines around the Vegetation menu's trees (39.2): green round the ones that spread on
-- fertile ground (grass, scrub), beige round the one that spreads on infertile ground.
function C.spreadOutlines(M)
  local G, added = M.G, M.added
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local outlined = {}
  for _, param in ipairs(K.SPREAD_TREES) do
    outlined[#outlined + 1] = { item = M.button(param), fertile = K.SPREAD_FERTILE[param] == true }
  end
  local function pack(rgb)
    if rd32(G.pixelFormat) == 0x565 then
      return ((rgb[1] >> 3) << 11) | ((rgb[2] >> 2) << 5) | (rgb[3] >> 3)
    end
    return ((rgb[1] >> 3) << 10) | ((rgb[2] >> 3) << 5) | (rgb[3] >> 3)
  end
  local into = added.spreadOutline
  wr32(into + ITEM_TYPE, TYPE_CLICKABLE)       -- no size, so never under the mouse
  wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(into + ITEM_RENDER, C.luaPad(function()
    local menuX = rd32(G.menu + MENU_X) - rd32(G.menu + MENU_SCROLL)
    local menuY = rd32(G.menu + MENU_Y)
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, 0)
    for _, entry in ipairs(outlined) do
      local button = entry.item
      if rd16(button + ITEM_HIDDEN) == 0 and (rd32(button + ITEM_X) & 0xFFFFFFFF) ~= PLACED_BY_CONTROL then
        local colour = pack(entry.fertile and K.SPREAD_COLOURS.fertile or K.SPREAD_COLOURS.infertile)
        local l, t = menuX + rd32(button + ITEM_X) - 1, menuY + rd32(button + ITEM_Y) - 1
        local r, b = l + rd32(button + ITEM_WIDTH) + 2, t + rd32(button + ITEM_HEIGHT) + 2
        colourBox(G.pencil, l, t, r, t + 1, colour)
        colourBox(G.pencil, l, b - 1, r, b, colour)
        colourBox(G.pencil, l, t, l + 1, b, colour)
        colourBox(G.pencil, r - 1, t, r, b, colour)
      end
    end
    wr32(G.pencil + PENCIL_TARGET, target)
  end, "the tree outlines"))
end

-- The line at the top of the screen once fewer than K.GROUP_MARGIN herds and groups can still be
-- made (36.3), drawn from the frame hook (also with the menu hidden). It sits below the game's
-- own unit line when that one shows.
function C.groupWarning(G, data)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local buffer = core.allocate(96, true)
  data.groupCount = core.allocate(4, true)
  return function()
    local left = G.groupSlots - rd32(data.groupCount)
    local text = string.format("You can only make %d more herds and groups", math.max(left, 0))
    writeCString(buffer, text)
    local width = textWidth(G.textManager, buffer, #text, TOOLTIP_FONT)
    local x = (rd32(G.screenWidth) - width) // 2 + rd32(G.cameraX)
    local y = K.GROUP_WARNING_Y + (rd32(G.units) >= G.unitLimit and K.GROUP_WARNING_BELOW or 0) + rd32(G.cameraY)
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, x - TOOLTIP_PADDING, y, x + width + TOOLTIP_PADDING, y + TOOLTIP_LINE + TOOLTIP_PADDING,
      BOX_BLEND)
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    shadowedText(G.textManager, buffer, x, y + TOOLTIP_PADDING // 2, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)
  end
end

return true

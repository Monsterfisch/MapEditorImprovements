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
  12. Resource grid (editor/grid.lua, formerly the Resource Grid Overlay module): the AI's 5 x 5
     resource grid, the keep rotation boundaries and the iron mine footprint drawn over the map,
     toggled with Alt + G or through Custom Hotkeys.

  The map drawing's patch site after renderMap is shared: editor/frame.lua puts it in once, at
  the end of enable, and calls the grid's routine and then the editor's own frame work from it.

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

-- Load the editor features in their original definition order.
local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local C = layout.C
local AOB_MENU_REDRAW = layout.AOB_MENU_REDRAW
local DEFAULTS = layout.DEFAULTS
local MENU_REDRAW_SITE = layout.MENU_REDRAW_SITE
local MENU_REDRAW_SIZE = layout.MENU_REDRAW_SIZE
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local setting = memory.setting
local rd32 = memory.rd32
local wr32 = memory.wr32
require("editor.images")
local native = require("editor.native")
local resolveMenu = native.resolveMenu
local resolveDrawing = native.resolveDrawing
require("editor.sprites")
require("editor.ui")
require("editor.landscape_menu")
local patchJump = require("editor.menu_install").patchJump
require("editor.vegetation")
require("editor.terrain_patches")
require("editor.history")
require("editor.moat")
require("editor.pipette_native")
require("editor.vegetation_preview")
require("editor.pipette")
require("editor.landscape_controls")
require("editor.terrain")
require("editor.texture_mask")
require("editor.animals")
require("editor.settings")
local landscape = require("editor.landscape")
local enableMenu = landscape.enableMenu
local enableSignpost = landscape.enableSignpost
local enableRandomPreview = landscape.enableRandomPreview
require("editor.castle_controls")
require("editor.walls")
require("editor.castle_menu")
require("editor.castle")
local frame = require("editor.frame")
local grid = require("editor.grid")

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

local function checkedSettings(config)
  local checked = {}
  if config == nil then return checked end
  if type(config) ~= "table" then
    log(ERROR, MODULE_NAME .. ": expected a table of settings.")
    return checked
  end
  for group, defaults in pairs(DEFAULTS) do
    local section = config[group]
    if type(section) == "table" then
      local values = {}
      for name, value in pairs(section) do
        if type(defaults[name]) == "boolean" and type(value) ~= "boolean" then
          log(ERROR, string.format("%s.%s.%s: expected a boolean, using %s.",
            MODULE_NAME, group, name, tostring(defaults[name])))
        else
          values[name] = value
        end
      end
      checked[group] = values
    elseif section ~= nil then
      log(ERROR, string.format("%s.%s: expected a table of settings.", MODULE_NAME, group))
    end
  end
  return checked
end

local function pairedSettings(config, group, primary, companion)
  local enabled = setting(config, group, primary) == true
  local override = setting(config, group, companion)
  if override == nil then return enabled, enabled end
  if type(override) ~= "boolean" then
    log(ERROR, string.format("%s.%s.%s: expected a boolean, using %s.",
      MODULE_NAME, group, companion, tostring(enabled)))
    return enabled, enabled
  end
  return enabled, override
end

local function configuredKey(config, group, enabled, key)
  if not setting(config, group, enabled) then return nil end
  local value = setting(config, group, key)
  return memory.choice(value, C.keyCode(value) ~= nil, DEFAULTS[group][key], group .. "." .. key)
end

local function shortcut(config, group, choice, enabled, key, kind)
  local value = setting(config, group, choice)
  local valid = value == "off" or value == "configured" or C.keyCode(value, kind) ~= nil
  value = memory.choice(value, valid, "configured", group .. "." .. choice)
  if value == "off" then return nil end
  if value ~= "configured" then return value end
  return configuredKey(config, group, enabled, key)
end

local function enable(self, config)
  config = checkedSettings(config)
  local spreadOrder, sortedRows = pairedSettings(config, "trees", "spread_order", "sorted_rows")
  local variants, extraRock = pairedSettings(config, "rocks", "variants", "extra_rock")
  local buildingCounts, hoverTextLeft =
    pairedSettings(config, "castle", "building_counts", "hover_text_left")
  local keepCrests, crestTooltip =
    pairedSettings(config, "castle", "keep_crests", "keep_crest_tooltip")
  local settingsMenu, settingsButton = pairedSettings(config, "map_settings", "menu", "button")
  local invertKey = shortcut(config, "heights", "invert_shortcut", "invert_key_on", "invert_key", "hold")
  local selectKey = shortcut(config, "pipette", "select_shortcut", "select_key_on", "select_key", "select")
  local readKey = shortcut(config, "pipette", "read_shortcut", "read_key_on", "read_key", "hold")
  local anyKey = configuredKey(config, "pipette", "any_tile_key_on", "any_tile_key")
  local gridConfig = {}
  for name, value in pairs(DEFAULTS.grid) do gridConfig[name] = value end
  for name, value in pairs(config.grid or {}) do gridConfig[name] = value end
  grid.validateChoices(gridConfig)

  -- Undo first: its buttons go into the menus below.
  if setting(config, "undo", "enabled") == true then
    local ok, problem = pcall(C.enableUndo, self)
    if not ok then
      self.undo = nil
      log(ERROR, "Map editor undo is off.")
      log(WARNING, tostring(problem) .. "; the editor has no undo")
    end
  end
  local rockPlaced
  if setting(config, "rocks", "random_preview") == true then
    local ok, result = pcall(enableRandomPreview, self)
    if ok then rockPlaced = result
    else
      log(ERROR, "Random rock rotation previews are off.")
      log(WARNING, tostring(result))
    end
  end
  local O = {
    counts = setting(config, "counts", "enabled") == true,
    shown = setting(config, "counts", "shown") == true,
    growth = setting(config, "trees", "growth_from_brush") == true,
    apple = setting(config, "trees", "apple") == true,
    shrubs = setting(config, "trees", "shrubs") == true,
    felled = setting(config, "trees", "felled") == true,
    obstacles = setting(config, "trees", "obstacles") == true,
    rocksAndWater = setting(config, "trees", "rocks_and_water") == true,
    sortedRows = sortedRows,
    randomMix = setting(config, "trees", "random_mix") == true,
    textures = setting(config, "textures", "gravel_and_iron") == true,
    variants = variants,
    extraRock = extraRock,
    rockPlaced = rockPlaced,
    herds = setting(config, "herds", "panel") == true,
    invisibleRocks = setting(config, "rocks", "invisible") == true,
    noStacking = setting(config, "trees", "no_shrub_stacking") == true,
    treePreview = setting(config, "trees", "preview") == true,
    noHeightsIron = setting(config, "textures", "no_heights_iron") == true,
    waterDecorations = setting(config, "water", "decorations") == true,
    foamOnSea = setting(config, "water", "foam_on_sea") == true,
    maxHeight = setting(config, "heights", "max_height") == true,
    heightTools = setting(config, "heights", "tool_options") == true,
    lostRocks = setting(config, "rocks", "remove_lost") == true,
    invertKey = invertKey,
    textureMask = setting(config, "textures", "mask") == true,
    maskByType = setting(config, "textures", "mask_by_type") == true,
    birdButtons = setting(config, "herds", "bird_bins") == true,
    animalBin = setting(config, "herds", "animal_bin") == true,
    groupWarning = setting(config, "herds", "group_warning") == true,
    eraserChoice = setting(config, "eraser", "choice") == true,
    eraseGulls = setting(config, "eraser", "seagulls") == true,
    spreadOrder = spreadOrder,
    spreadOutlines = setting(config, "trees", "spread_outlines") == true,
    compass = setting(config, "menu", "compass") == true,
    undo = self.undo,
  }
  if setting(config, "pipette", "enabled") == true then
    O.pipette = {
      selectKeyOn = selectKey ~= nil, selectKey = selectKey,
      readKeyOn = readKey ~= nil, readKey = readKey,
      anyKeyOn = anyKey ~= nil, anyKey = anyKey,
    }
  end
  local castle = {
    buildingCounts = buildingCounts,
    towerRuins = setting(config, "castle", "tower_ruins") == true,
    armyExtras = setting(config, "castle", "tunnel_and_tents") == true,
    statues = setting(config, "castle", "statues_and_shrines") == true,
    variantPanels = setting(config, "castle", "variant_panels") == true,
    ruinedCathedral = setting(config, "castle", "ruined_cathedral") == true,
    barrier = setting(config, "castle", "barrier") == true,
    severalKeeps = setting(config, "castle", "several_keeps") == true,
    looseBuildings = setting(config, "castle", "several_storage_and_recruitment") == true,
    towerEngines = setting(config, "castle", "tower_engines_anywhere") == true,
    keepParts = setting(config, "castle", "keep_parts") == true,
    keepGround = setting(config, "castle", "keep_ground") == true,
    rotation = setting(config, "castle", "rotation") == true,
    unitColour = setting(config, "castle", "unit_colour") == true,
    compass = setting(config, "menu", "compass") == true,
    damagedWalls = setting(config, "castle", "damaged_walls") == true,
    allPlayers = setting(config, "castle", "all_players") == true,
    allKeeps = setting(config, "castle", "all_keeps") == true,
    playerZero = setting(config, "castle", "player_zero") == true,
    keepCrests = keepCrests,
    crestTooltip = crestTooltip,
    wallTools = setting(config, "castle", "wall_tools") == true,
    hoverTextLeft = hoverTextLeft,
    moatKinds = setting(config, "castle", "moat_kinds") == true,
    moatOnMarsh = setting(config, "castle", "moat_on_marsh") == true,
    moatRemoval = setting(config, "castle", "moat_removal_keeps_ground") == true,
    undo = self.undo,
  }
  local landscapeOK, result = pcall(enableMenu, self, O)
  local frameData
  if landscapeOK then
    frameData = result
  else
    log(ERROR, "Landscape menu changes are off.")
    log(WARNING, tostring(result))
  end
  local settings = {
    lockedMaps = setting(config, "map_settings", "show_locked") == true,
    settingsButton = settingsButton,
    settingsMenu = settingsMenu,
  }
  if settings.lockedMaps or settings.settingsButton or settings.settingsMenu then
    C.enableMapSettings(self, settings)
  end
  if castle.severalKeeps or castle.looseBuildings then C.enableExtraBuildings(self, castle) end
  if castle.buildingCounts or castle.towerRuins or castle.armyExtras or castle.statues or castle.barrier
      or castle.towerEngines or castle.keepParts
      or castle.damagedWalls or castle.hoverTextLeft or castle.undo or castle.moatKinds or castle.moatOnMarsh
      or castle.moatRemoval or castle.ruinedCathedral or castle.allPlayers or castle.allKeeps or castle.playerZero or castle.keepCrests or castle.wallTools
      or castle.keepGround or castle.rotation or castle.compass or castle.unitColour then
    local ok, problem = pcall(C.enable, self, castle)
    if not ok then
      log(ERROR, "Castle editor menu changes are off.")
      log(WARNING, tostring(problem))
    end
  end
  if setting(config, "rocks", "signpost") == true then
    local ok, problem = pcall(enableSignpost, self)
    if not ok then
      log(ERROR, "The skirmish map signpost menu is off.")
      log(WARNING, tostring(problem))
    end
  end
  if setting(config, "brushes", "full_shape") == true then
    local ok, problem = pcall(C.patchBrushShape, self)
    if not ok then
      log(ERROR, "Full brush shapes are off.")
      log(WARNING, tostring(problem))
    end
  end
  if setting(config, "rocks", "erase_invisible") == true then
    local ok, problem = pcall(C.patchEraser, self)
    if not ok then
      log(ERROR, "Erasing invisible rocks is off.")
      log(WARNING, tostring(problem))
    end
  end
  for _, entry in ipairs({ { "size_refresh", C.patchSizeRefresh, "Immediate updates for smaller maps are off." },
      { "camera_edge", C.patchCameraEdge, "Full map-edge scrolling is off." } }) do
    if setting(config, "map_settings", entry[1]) == true then
      local ok, problem = pcall(function()
        local G = self.landscape
        if G == nil then
          G = {}
          resolveMenu(G)
          resolveDrawing(G)
        end
        entry[2](self, G)
      end)
      if not ok then
        log(ERROR, entry[3])
        log(WARNING, tostring(problem))
      end
    end
  end
  if setting(config, "menu", "compass_turn") == true then
    local ok, problem = pcall(function()
      local G = self.landscape
      if G == nil then
        G = {}
        resolveMenu(G)
        resolveDrawing(G)
      end
      C.patchCompassTurn(self, G)
    end)
    if not ok then
      log(ERROR, "Turning the map both ways with the compass is off.")
      log(WARNING, tostring(problem))
    end
  end
  if setting(config, "menu", "dust_clouds") == true then
    local ok, problem = pcall(C.patchDustClouds, self)
    if not ok then
      log(ERROR, "Dust cloud changes are off.")
      log(WARNING, tostring(problem))
    end
  end
  if setting(config, "menu", "always_update") == true then
    local ok, problem = pcall(enableRedraw, self)
    if not ok then
      log(ERROR, "Always updating the map editor menu is off.")
      log(WARNING, tostring(problem))
    end
  end
  local gridOn = false
  if gridConfig.enabled == true then
    local ok, problem = pcall(grid.enable, self, gridConfig)
    gridOn = ok and problem == true
    if not ok then
      log(ERROR, "The map editor resource grid is off.")
      log(WARNING, tostring(problem))
    end
  end
  if not gridOn then frame.remove("grid") end
  -- Last: the map drawing's patch site with every routine the features above added.
  frame.commit(self, function()
    if frameData ~= nil and frameData.treePreviewItem ~= nil then
      wr32(frameData.treePreviewItem + layout.ITEM_RENDER_TYPE, layout.RENDER_NONE)
    end
  end, function(problem, installed)
    if installed then
      log(ERROR, "The vegetation preview renderer could not be updated.")
      log(WARNING, tostring(problem))
      return
    end
    if frameData ~= nil then
      landscape.reportFrameFailure(frameData, problem)
    else
      log(WARNING, tostring(problem))
    end
  end)
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

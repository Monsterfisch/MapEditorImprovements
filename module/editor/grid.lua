-- Resource grid overlay (moved here from Resource Grid Overlay 1.1.x, by Monsterfish).
--
-- Draws the grid the AI uses to pick resource-gathering spots, the keep rotation boundaries and
-- the iron mine footprint over the terrain, toggled with Alt + G. It belongs in the map editor,
-- but the "also outside the map editor" option lets it run in a normal game as well, which is how
-- the lines get checked against real terrain. What it draws is worked out in grid_view.lua and
-- drawn by grid_draw.lua's assembly.
--
-- Where it changes the game, every place found by pattern scan, valid for the plain and the
-- Extreme executable:
--
--   * The map drawing's patch site (editor/frame.lua), shared with the editor's own frame work:
--     the grid's routine runs first, then the tree preview. That call site is only reached when
--     `isInGameScreen` says the player is on the map, so the routine never runs in a menu.
--
--   * The toggle. With a Custom Hotkeys that offers `registerAction`, the grid registers an
--     editor action (Alt + the chosen key suggested) and, when it may show during games, a game
--     action that starts unbound; the player rebinds both there. Without it, the WM_SYSKEYDOWN
--     branch of the window procedure is redirected to the module's handler as before: Alt +
--     letter never reaches the ordinary WM_KEYDOWN key table, it arrives as WM_SYSKEYDOWN and goes
--     through a second, much smaller jump table. G sits on the do-nothing case there in both
--     executables, so Alt + G is free and nothing has to be suppressed.
--
--   * `requestScreenChange`, after the pending screen has been stored and while EBP still holds
--     it. Leaving the map puts the overlay away. The site lies past every byte Resolution Based
--     Zoom's own pattern on the same function reads, so the two modules can be enabled in either
--     order.

local memory = require("editor.memory")
local frame = require("editor.frame")
local B = require("editor.grid_draw")
local V = require("editor.grid_view")

local M = {}

---------------------------------------------------------------------------------------
-- Patterns
---------------------------------------------------------------------------------------

-- Head of `focusOnTile`, which picks its block of `screenPointToTileNumber` from the map
-- orientation the same way `renderMap` does:
--   mov eax,[mapOrientation] / test eax,eax / push ebx,ebp,esi,edi / mov ebp,ecx /
--   mov edi,8 / je / cmp eax,6 / jne / mov edi,0x13A18 / ...
local MAP_ORIENTATION_AOB = "A1 ? ? ? ? 85 C0 53 55 56 57 8B E9 BF 08 00 00 00 74 22 "
    .. "83 F8 06 75 07 BF 18 3A 01 00 EB 16 83 F8 04 75 07 BF 28 74 02 00"
local OFFSET_MAP_ORIENTATION = 1

-- `PencilRenderCore::setupPencilSurface`: picks the map surface when surfaceTarget is set, and
-- with it the 0x1FB0 byte pitch. Its first operand is the map surface pointer, which sits at
-- +0xD8 in the window/graphics struct.
local PENCIL_SURFACE_AOB = "8B 41 0C 85 C0 8B 15 ? ? ? ? 75 06 8B 15 ? ? ? ? 85 C0 "
    .. "89 51 04 74 08 C7 41 08 B0 1F 00 00"
local OFFSET_MAP_SURFACE_POINTER = 7

-- `GameMode2 == 1` guard in the "is the player looking at the map" helper:
--   cmp [gameMode2],1 / jne / push 4 / mov ecx,... / call / ret
local GAME_MODE_AOB = "83 3D ? ? ? ? 01 75 0D 6A 04 B9 ? ? ? ? E8 ? ? ? ? C3"
local OFFSET_GAME_MODE = 2
local GAME_MODE_EDITOR = 1

-- `renderMap`'s prologue, where the two flags that together mean "the map is being shown
-- flattened" are tested:
--   cmp [flattenA],edi / je / cmp [flattenB],edi / je / mov dword [esp+0x24],1
local FLATTENED_AOB = "39 3D ? ? ? ? 74 10 39 3D ? ? ? ? 74 08 C7 44 24 24 01 00 00 00"
local OFFSET_FLATTEN_A = 2
local OFFSET_FLATTEN_B = 10

-- The flattened branch of the tile loop, which forces every tile's height offset to the single
-- ground level the whole map is levelled to:
--   cmp [viewport+0xBC],esi / mov dword [tileHeightOffset],8 / je / mov .. / mov ..
local GROUND_HEIGHT_AOB = "39 B3 BC 00 00 00 C7 05 ? ? ? ? 08 00 00 00 74 11 "
    .. "89 35 ? ? ? ? 89 35 ? ? ? ?"
local OFFSET_GROUND_HEIGHT = 12

-- The map editor's other view, the one the V key turns on. The key handler only queues the mode
-- on the command object; the flag the renderer actually reads is a field of that object at
-- +0x5548C4, which `renderMap` consults eleven times. Take the object from the handler:
--   push 3 / mov ecx, commandObject / call / mov [DAT], ebp / jmp tail
--
-- **It reads the other way round to what the name suggests.** Every one of those eleven tests is
-- `cmp [flag], 0 / je skip` guarding the work that draws the things standing on the map, so
-- **non-zero is the ordinary view and zero is the stripped-down one**. Read it the wrong way and
-- the overlay disappears everywhere, because the flag is non-zero almost all the time.
local VIEW_MODE_AOB = "6A 03 B9 ? ? ? ? E8 ? ? ? ? 89 2D ? ? ? ? E9"
local OFFSET_COMMAND_OBJECT = 3
local VIEW_FLAG_IN_COMMAND_OBJECT = 0x5548C4

-- The WM_SYSKEYDOWN arm of the window procedure. ESI is the virtual-key code and ECX is still
-- the lParam the procedure loaded on entry:
--   mov esi,[esp+0x64] / lea eax,[esi-0xD] / cmp eax,0xD1 / mov ebp,1 / mov [DAT],ebp /
--   ja tail / movzx eax, byte [eax+caseTable] / jmp dword [eax*4+addressTable]
local SYS_KEY_DISPATCH_AOB = "8B 74 24 64 8D 46 F3 3D D1 00 00 00 BD 01 00 00 00 "
    .. "89 2D ? ? ? ? 0F 87 ? ? ? ? 0F B6 80 ? ? ? ? FF 24 85 ? ? ? ?"
local OFFSET_SYS_KEY_JUMP = 36
local SIZE_SYS_KEY_JUMP = 7

-- `isInGameScreen`: the three immediates are the screen ids that mean "on the map".
local IN_GAME_SCREEN_AOB = "8B 41 0C 83 F8 0C 74 0D 83 F8 0E 74 08 83 F8 10 74 03 "
    .. "33 C0 C3"
local OFFSETS_IN_GAME_SCREEN_IDS = { 5, 10, 15 }

-- Screen ids that still count as "on the map" for keeping the overlay on: the three
-- `isInGameScreen` accepts, plus the map editor's own properties screen, which the editor steps
-- through without leaving the map behind.
local MAP_EDITOR_PROPERTIES_SCREEN = 0x11

-- `requestScreenChange` after the request has been normalized and stored:
--   jne / mov ebp,0x29 / mov eax,[esp+0x10] / push ebx / push edi / mov [esi+0x18],ebp /
--   mov [esi+4],eax / call [time] / mov [esi+8],eax / mov eax,ebp / sub eax,0xC
-- The handler takes `mov [esi+8],eax / mov eax,ebp` (5 bytes), where EBP still holds the screen
-- the game is about to move to. Resolution Based Zoom changes the six bytes before this pattern
-- and its own pattern ends with `mov [esi+0x18],ebp`; Custom Hotkeys reads the function's first
-- 21 bytes. Neither reaches the five bytes taken here.
local SCREEN_CHANGE_AOB = "75 05 BD 29 00 00 00 8B 44 24 10 53 57 89 6E 18 89 46 04 FF 15 ? ? ? ? 89 46 08 8B C5 83 E8 0C"
local OFFSET_SCREEN_STORED = 25
local SIZE_SCREEN_STORED = 5

---------------------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------------------

-- Virtual-key code per choice name for the Alt + key toggle without Custom Hotkeys. Only keys
-- that land on the do-nothing case of the WM_SYSKEYDOWN table in both executables are offered,
-- so Alt plus any of them has no meaning of its own to take away.
local VIRTUAL_KEY_CODES = {
  letter_a = 0x41, letter_b = 0x42, letter_f = 0x46, letter_g = 0x47,
  letter_i = 0x49, letter_j = 0x4A, letter_l = 0x4C, letter_m = 0x4D,
  letter_n = 0x4E, letter_o = 0x4F, letter_p = 0x50, letter_s = 0x53,
  letter_w = 0x57, letter_y = 0x59, letter_z = 0x5A,
  f1 = 0x70, f2 = 0x71, f3 = 0x72, f4 = 0x73, f5 = 0x74, f6 = 0x75,
  f7 = 0x76, f8 = 0x77, f9 = 0x78,
  numpad_multiply = 0x6A, numpad_add = 0x6B, numpad_subtract = 0x6D,
  numpad_decimal = 0x6E, numpad_divide = 0x6F,
  insert = 0x2D, delete_key = 0x2E, home = 0x24, end_key = 0x23,
  page_up = 0x21, page_down = 0x22, caps_lock = 0x14,
}
local DEFAULT_KEY = "letter_g"

-- The same choices as Custom Hotkeys' physical keys (set-1 scan code, E0 prefix), for the
-- suggested binding of the editor action. Letters are where they sit on a US keyboard, which is
-- where Custom Hotkeys shows them; the player can rebind there. Alt + F4 belongs to Windows, so
-- that choice suggests no binding.
local SCAN_CODES = {
  letter_a = { 0x1E }, letter_b = { 0x30 }, letter_f = { 0x21 }, letter_g = { 0x22 },
  letter_i = { 0x17 }, letter_j = { 0x24 }, letter_l = { 0x26 }, letter_m = { 0x32 },
  letter_n = { 0x31 }, letter_o = { 0x18 }, letter_p = { 0x19 }, letter_s = { 0x1F },
  letter_w = { 0x11 }, letter_y = { 0x15 }, letter_z = { 0x2C },
  f1 = { 0x3B }, f2 = { 0x3C }, f3 = { 0x3D }, f5 = { 0x3F }, f6 = { 0x40 },
  f7 = { 0x41 }, f8 = { 0x42 }, f9 = { 0x43 },
  numpad_multiply = { 0x37 }, numpad_add = { 0x4E }, numpad_subtract = { 0x4A },
  numpad_decimal = { 0x53 }, numpad_divide = { 0x35, true },
  insert = { 0x52, true }, delete_key = { 0x53, true }, home = { 0x47, true },
  end_key = { 0x4F, true }, page_up = { 0x49, true }, page_down = { 0x51, true },
  caps_lock = { 0x3A },
}
local ALT = 4

local DEFAULT_GRID_COLOUR = "white"
-- The mine footprint takes red, so the keep rotation boundaries move to cyan; two reds on the
-- same picture would be unreadable. Both are still free to change.
local DEFAULT_ROTATION_COLOUR = "cyan"
local DEFAULT_MINE_COLOUR = "red"

local ACTION_EDITOR = "ext.map-editor-improvements.grid-toggle"
local ACTION_GAME = "ext.map-editor-improvements.grid-toggle-game"

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local readInteger = core.readInteger
local writeInteger = core.writeInteger
local floor = math.floor
local max = math.max

local function readAddress(address)
  return readInteger(address) & 0xFFFFFFFF
end

---Scan for an AOB the grid can manage without: one match, or nil. Other modules change game
---code before this one runs, so a pattern that has been overwritten must disable the part that
---needs it rather than take the game down at launch.
---@param pattern string
---@param purpose string what the address is for, for the log line
---@return number|nil address
local function scanOptional(pattern, purpose)
  local found, address = pcall(memory.scanUnique, pattern, purpose)
  if not found then
    log(WARNING, tostring(address) .. "; resource grid: that part is disabled. Another module has "
      .. "probably changed it.")
    return nil
  end
  return address
end

---Bit 30 of lParam is set when a key-down message is a hold-down auto-repeat.
local function isAutoRepeat(lParam)
  if lParam < 0 then
    lParam = lParam + 0x100000000
  end
  return floor(lParam / 0x40000000) % 2 == 1
end

---Resolve a configured choice name against a table, falling back to a default.
local function resolveChoice(name, table_, defaultName, what)
  local value = table_[name]
  if value == nil then
    if name ~= nil then
      log(WARNING, string.format("resource grid: unknown %s '%s', using '%s'.",
        what, tostring(name), defaultName))
    end
    value = table_[defaultName]
  end
  return value
end

---The Custom Hotkeys proxy when it offers module actions, else nil.
local function actionProvider()
  local hotkeys = modules ~= nil and modules["custom-hotkeys"] or nil
  if hotkeys ~= nil and type(hotkeys.registerAction) == "function" then return hotkeys end
  return nil
end

---------------------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------------------

---Set the grid up from its option group. Adds its routine to the map drawing's patch site;
---init.lua puts the site in afterwards.
---@param self table the module
---@param config table the grid's option group (map-editor-improvements.grid)
---@return boolean enabled
function M.enable(self, config)
  config = config or {}
  if config.enabled == false then return false end

  if modules ~= nil and modules["resource-grid-overlay"] ~= nil then
    log(WARNING, "resource grid: Resource Grid Overlay is active and draws it; "
      .. "this module leaves the grid to it. Turn that module off to use the grid here.")
    return false
  end
  local S = frame.resolve()
  if not S.firstLoadFree then
    log(WARNING, "resource grid: another module has changed the map drawing's "
      .. "first load; the grid is disabled.")
    return false
  end

  local hotkey = resolveChoice(config.key, VIRTUAL_KEY_CODES, DEFAULT_KEY, "hotkey")
  local gridChannels = resolveChoice(config.grid_colour, V.COLOURS, DEFAULT_GRID_COLOUR, "grid colour")
  local rotationChannels = resolveChoice(config.rotation_colour, V.COLOURS, DEFAULT_ROTATION_COLOUR,
    "rotation colour")
  local mineChannels = resolveChoice(config.mine_colour, V.COLOURS, DEFAULT_MINE_COLOUR, "mine colour")
  local withRotation = config.rotation_lines ~= false
  -- Default on, so the overlay is usable for checking alignment against a real map even when the
  -- config file has not been written yet.
  local editorOnly = config.outside_editor == false
  -- Default on: the lines lie on one height, so they only tell the whole truth in the flattened
  -- view. Turn it off to see them over real terrain as well.
  local flattenedOnly = config.flattened_only ~= false
  -- Kept as its own switch, and separate from the flattened gate, so that if this one ever reads
  -- the wrong thing it can be turned off without losing the other.
  local hideInVView = config.hide_in_v_view ~= false

  -- Only the mine width has a setting in the GUI: every other position is either worked out from
  -- the game's own numbers or, for the keep rotation origin, measured once and fixed. The reads
  -- stay so that a hand-edited ucp-config.yml can still override them.
  local function number(value, fallback)
    return type(value) == "number" and floor(value) or fallback
  end
  local tune = {
    withRotation = withRotation,
    mineBoxes = config.mine_boxes ~= false,
    mineSize = number(config.mine_size, V.MINE_FOOTPRINT),
    originX = number(config.origin_x, V.DEFAULT_ROTATION_ORIGIN),
    originY = number(config.origin_y, V.DEFAULT_ROTATION_ORIGIN),
    boundaryX = number(config.boundary_x, 0),
    boundaryY = number(config.boundary_y, 0),
  }

  local surfaceSite = scanOptional(PENCIL_SURFACE_AOB, "the map surface pointer")
  local gameModeSite = scanOptional(GAME_MODE_AOB, "the game mode flag")
  local orientationSite = scanOptional(MAP_ORIENTATION_AOB, "the map orientation")
  local flattenSite = scanOptional(FLATTENED_AOB, "the flattened view flags")
  local groundSite = scanOptional(GROUND_HEIGHT_AOB, "the ground height")
  local viewModeSite = scanOptional(VIEW_MODE_AOB, "the V view flag")
  local hotkeys = actionProvider()
  -- Also with Custom Hotkeys: the way back should its registration refuse the actions.
  local dispatchSite = scanOptional(SYS_KEY_DISPATCH_AOB, "the Alt key dispatcher")

  if surfaceSite == nil or gameModeSite == nil or orientationSite == nil
      or (hotkeys == nil and dispatchSite == nil) then
    log(WARNING, "resource grid: disabled, the game code it needs was not found.")
    return false
  end

  local viewport = S.viewport
  local surfacePointer = readAddress(surfaceSite + OFFSET_MAP_SURFACE_POINTER)
  local windowStruct = surfacePointer - V.MAP_SURFACE_POINTER_IN_STRUCT
  local gameMode = readAddress(gameModeSite + OFFSET_GAME_MODE)

  local state = {
    -- The height the game levels the whole map to in its flattened view, read from the
    -- instruction that sets it. Lines sit on that height, so they follow ordinary flat ground and
    -- match the flattened view exactly.
    groundHeight = groundSite ~= nil and readInteger(groundSite + OFFSET_GROUND_HEIGHT)
      or V.DEFAULT_GROUND_HEIGHT,
    tune = tune,
    -- One list per rotation per zoom level, indexed by orientation and then by the divisor the
    -- rebuild works out. Eight small lists, built once.
    lines = {},
    -- Only the keep rotation boundaries take a nudge.
    nudgeX = { 0, tune.boundaryX, 0 },
    nudgeY = { 0, tune.boundaryY, 0 },
    -- Colours per pixel layout, worked out once for each so the rebuild only picks.
    palette = {
      [false] = { V.packColour(gridChannels, false), V.packColour(rotationChannels, false),
        V.packColour(mineChannels, false) },
      [true] = { V.packColour(gridChannels, true), V.packColour(rotationChannels, true),
        V.packColour(mineChannels, true) },
    },
  }

  local longest = 0
  for orientation, transform in pairs(V.ORIENTATIONS) do
    state.lines[orientation] = {
      V.buildLines(tune, transform, 1),
      V.buildLines(tune, transform, V.ZOOMED_OUT_DIVISOR),
    }
    longest = max(longest, #state.lines[orientation][1],
      #state.lines[orientation][V.ZOOMED_OUT_DIVISOR])
  end
  -- The block is sized once the longest line list is known; no view can clip in more lines than
  -- a list holds.
  local control = core.allocate(B.SEGMENT_LIST + 8 * longest, true)
  state.control = control

  -- Both nil when the scan failed; the gate then stays off.
  local flattenA = flattenSite ~= nil and readAddress(flattenSite + OFFSET_FLATTEN_A) or nil
  local flattenB = flattenSite ~= nil and readAddress(flattenSite + OFFSET_FLATTEN_B) or nil
  local viewFlag = viewModeSite ~= nil
    and readAddress(viewModeSite + OFFSET_COMMAND_OBJECT) + VIEW_FLAG_IN_COMMAND_OBJECT or nil
  if flattenedOnly and flattenA == nil then
    log(WARNING, "resource grid: the flattened view flags were not found, "
      .. "so the overlay shows in every view.")
  end

  writeInteger(control + B.EDITOR_ONLY, editorOnly and 1 or 0)
  writeInteger(control + B.FLATTENED_ONLY, (flattenedOnly and flattenA ~= nil) and 1 or 0)
  writeInteger(control + B.HIDE_IN_V_VIEW, (hideInVView and viewFlag ~= nil) and 1 or 0)

  -- The frame routine reads the view values through this table, in VIEW_KEY order.
  local zero = control + B.ALWAYS_ZERO
  local sources = {
    readAddress(orientationSite + OFFSET_MAP_ORIENTATION),
    viewport + V.VIEWPORT_ZOOMED_OUT,
    viewport + V.VIEWPORT_ROW_BIAS_ACTIVE,
    viewport + V.VIEWPORT_X,
    viewport + V.VIEWPORT_Y,
    viewport + V.VIEWPORT_TILES_PER_ROW,
    viewport + V.VIEWPORT_ROW_COUNT,
    windowStruct + V.COLOR_BIT_MODE_IN_STRUCT,
  }
  local sourceTable = core.allocate(4 * #sources, true)
  for index, address in ipairs(sources) do
    writeInteger(sourceTable + 4 * (index - 1), address)
  end

  -- The rebuild is reached from the assembly through a redirect on a pad of its own.
  local rebuildFailed = false
  local rebuildPad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  core.detourCode(function(registers)
    local ok, err = pcall(V.rebuild, state)
    if not ok then
      writeInteger(control + B.SEGMENT_COUNT, 0)
      writeInteger(control + B.MARKER_BLOCK, 0)
      writeInteger(control + B.MARKER_BLOCK + 4, 0)
      if not rebuildFailed then
        rebuildFailed = true
        log(WARNING, "resource grid: could not work out the overlay: " .. tostring(err))
      end
    end
    -- Marked valid either way: a failure is not retried until the view changes.
    writeInteger(control + B.CACHE_VALID, 1)
    return registers
  end, rebuildPad, 5)

  local routine = B.build({
    OVERLAY_SHOWN = control + B.SHOWN,
    OVERLAY_EDITOR_ONLY = control + B.EDITOR_ONLY,
    OVERLAY_FLATTENED_ONLY = control + B.FLATTENED_ONLY,
    OVERLAY_HIDE_IN_V_VIEW = control + B.HIDE_IN_V_VIEW,
    CACHE_VALID_ADDRESS = control + B.CACHE_VALID,
    VIEW_KEY_ADDRESS = control + B.VIEW_KEY,
    SEGMENT_COUNT_ADDRESS = control + B.SEGMENT_COUNT,
    SEGMENT_LIST_ADDRESS = control + B.SEGMENT_LIST,
    STYLE_COLOURS_ADDRESS = control + B.STYLE_COLOURS,
    MARKER_PARAMETERS = control + B.MARKER_BLOCK,
    SOURCE_TABLE = sourceTable,
    GAME_MODE_ADDRESS = gameMode,
    GAME_MODE_EDITOR_VALUE = GAME_MODE_EDITOR,
    FLATTEN_A_ADDRESS = flattenA or zero,
    FLATTEN_B_ADDRESS = flattenB or zero,
    VIEW_FLAG_ADDRESS = viewFlag or zero,
    SURFACE_POINTER_ADDRESS = surfacePointer,
    SURFACE_PITCH_VALUE = V.SURFACE_PITCH,
    REBUILD_ADDRESS = rebuildPad,
  })

  ---Whether the overlay is allowed where the game currently is. Normally that means the map
  ---editor; with the "outside the map editor" option on it means anywhere the map is drawn,
  ---which is what you want when checking the lines against real terrain. The frame routine
  ---makes the same test on its own.
  local function allowedHere()
    return not editorOnly or readInteger(gameMode) == GAME_MODE_EDITOR
  end
  -- Also false while the map drawing's site is not in (it failed, or waits for afterInit).
  local function toggle()
    if not allowedHere() or not frame.running("grid") then return false end
    writeInteger(control + B.SHOWN, readInteger(control + B.SHOWN) == 0 and 1 or 0)
    return true
  end

  local input = nil
  if hotkeys ~= nil then
    local labels = require("editor.grid_labels")
    local key = config.key ~= nil and VIRTUAL_KEY_CODES[config.key] ~= nil and config.key or DEFAULT_KEY
    local scan = SCAN_CODES[key]
    local ok, problem = pcall(function()
      hotkeys:registerAction({
        id = ACTION_EDITOR, label = labels.editor, category = labels.category,
        context = { kind = "editor" },
        default = scan ~= nil and { scan = scan[1], extended = scan[2] == true, mods = ALT } or false,
        callback = function() return toggle() end,
      })
    end)
    if ok then
      input = "Custom Hotkeys actions"
      if not editorOnly then
        local gameOk, gameProblem = pcall(function()
          hotkeys:registerAction({
            id = ACTION_GAME, label = labels.game, category = labels.category,
            context = { kind = "world" }, default = false,
            callback = function() return toggle() end,
          })
        end)
        if not gameOk then
          log(WARNING, "resource grid: Custom Hotkeys refused the game action ("
            .. tostring(gameProblem) .. "); the grid toggles in the map editor only")
        end
      end
    else
      log(WARNING, "resource grid: Custom Hotkeys refused the toggle ("
        .. tostring(problem) .. "); Alt + key instead")
    end
  end
  if input == nil and dispatchSite ~= nil then
    -- Alt plus the hotkey. WM_SYSKEYDOWN is the only message Alt combinations arrive on, so no
    -- separate modifier test is needed, and the key is on the do-nothing case of that table so
    -- nothing has to be suppressed either.
    core.detourCode(function(registers)
      if registers.ESI == hotkey and not isAutoRepeat(registers.ECX) then
        toggle()
      end
      return registers
    end, dispatchSite + OFFSET_SYS_KEY_JUMP, SIZE_SYS_KEY_JUMP)
    input = string.format("Alt + key 0x%02X", hotkey)
  elseif input == nil then
    log(WARNING, "resource grid: no way to toggle it; it stays hidden")
    input = "no toggle"
  end

  -- Leaving the map puts the overlay away, so coming back into the editor always starts with it
  -- off. Moving between the editor's own screens keeps it.
  local mapScreens = { [MAP_EDITOR_PROPERTIES_SCREEN] = true }
  local inGameScreenSite = scanOptional(IN_GAME_SCREEN_AOB, "the on-the-map screen ids")
  local screenChangeSite = inGameScreenSite ~= nil
    and scanOptional(SCREEN_CHANGE_AOB, "the screen change function") or nil
  if screenChangeSite ~= nil then
    for _, offset in ipairs(OFFSETS_IN_GAME_SCREEN_IDS) do
      mapScreens[core.readByte(inGameScreenSite + offset)] = true
    end
    core.detourCode(function(registers)
      if not mapScreens[registers.EBP] then
        writeInteger(control + B.SHOWN, 0)
      end
      return registers
    end, screenChangeSite + OFFSET_SCREEN_STORED, SIZE_SCREEN_STORED)
  else
    log(WARNING, "resource grid: no screen change site, so it stays on when you leave the map")
  end

  -- Last, once every other part is in: a failure above leaves no grid routine behind.
  frame.add("grid", routine)
  log(INFO, string.format("resource grid: %s, %d lines, rotation boundaries %s, %s.",
    input, #state.lines[V.DEFAULT_ORIENTATION][1], withRotation and "on" or "off",
    editorOnly and "map editor only" or "on every map"))
  return true
end

return M

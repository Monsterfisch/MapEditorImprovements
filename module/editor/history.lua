local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local K = layout.K
local C = layout.C
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readCallTarget = memory.readCallTarget
local rd32 = memory.rd32
local wr32 = memory.wr32
local patchJump = require("editor.menu_install").patchJump
local actions = require("editor.actions")

-- What a map is: the sections the game saves a map with (its section table). Before the first
-- map edit of a click the module copies them (the snapshot); when the step ends - at the next
-- click's first edit, or at a click on undo or redo - it compares them and keeps only the bytes
-- that changed, old and new. A brush held down is one click. Undo writes the old bytes back, redo the new ones, and then the things
-- the game works out from the map are worked out again, as after loading a map.

-- The section list for the diff: { live address, snapshot address, size } per section, 0 at the end.
function C.undoSections()
  local sections, total = {}, 0
  local at = rd32(scan(K.AOB_SECTION_TABLE, "the map sections") + K.SECTION_TABLE)
  while rd32(at + K.SECTION.address) ~= 0 do
    local size = rd32(at + K.SECTION.size)
    sections[#sections + 1] = { address = rd32(at + K.SECTION.address), size = size }
    total = total + size
    at = at + K.SECTION.stride
    if #sections > K.MOST_SECTIONS then error(MODULE_NAME .. ": the map section table has no end") end
  end
  return sections, total
end

function C.enableUndo(self)
  local U = { open = false, last = 0, steps = {}, redo = {}, bytes = 0 }
  local sections, total = C.undoSections()
  U.shadow = core.allocate(total, true)
  U.list = core.allocate((#sections + 1) * 12, true)
  local offset = 0
  for i, section in ipairs(sections) do
    section.shadow = U.shadow + offset
    wr32(U.list + (i - 1) * 12, section.address)
    wr32(U.list + (i - 1) * 12 + 4, section.shadow)
    wr32(U.list + (i - 1) * 12 + 8, section.size)
    offset = offset + section.size
  end
  U.scratch = core.allocate(K.UNDO_SCRATCH, false)
  local state = core.allocate(16, true)
  local diff = core.exposeCode(core.allocateAssembly(templates.undoDiff, {
    SECTIONS = U.list, OUT_BEGIN = U.scratch, OUT_LIMIT = U.scratch + K.UNDO_SCRATCH, GAP = K.UNDO_GAP_BYTES,
    WRITE_AT = state, ENTRY_AT = state + 4, RUN_FROM = state + 8, RUN_LENGTH = state + 12,
  }), 0, 0)

  -- The mouse buttons, through a thunk to GetAsyncKeyState.
  local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, {
    IMPORT = rd32(scan(K.AOB_ASYNC_KEY, "the key state") + K.ASYNC_KEY_IMPORT),
  }), 1, 0)
  local function down(key) return (asyncKey(key) % 0x10000) >= 0x8000 end
  local edits = {}
  for _, command in ipairs(K.MAP_EDITS) do edits[command] = true end
  U.released = true      -- the mouse buttons were up since the last map edit

  -- What the game works out from the map after loading it (prepareMap's own calls).
  local block = scan(K.AOB_PREPARE_BLOCK, "the map preparation")
  local P = K.PREPARE
  local tileMap = rd32(scan(K.AOB_ROCK_PREVIEW, "the tile map") + K.ROCK_PREVIEW.tileMap)
  local pathFinding, buildingsState = rd32(block + P.pathFinding), rd32(block + P.buildings)
  local hovered = rd32(block + P.hovered)
  local function call(offset, args) return core.exposeCode(readCallTarget(block, offset, "the map preparation"), args, 1) end
  local changedAll = call(P.changedAll, 1)
  local linkTiles, areas, linkBuildings = call(P.linkTiles, 1), call(P.areas, 2), call(P.linkBuildings, 1)
  local climb, cliffs, unhover = call(P.climb, 1), call(P.cliffs, 1), call(P.unhover, 1)
  local minimapSite = scan(K.AOB_MINIMAP_REDRAW, "the minimap redraw")
  local minimap = rd32(minimapSite + K.MINIMAP_REDRAW.object)
  local redrawMinimap = core.exposeCode(readCallTarget(minimapSite, K.MINIMAP_REDRAW.call, "the minimap redraw"), 2, 1)
  local function refresh()
    changedAll(tileMap)
    linkTiles(pathFinding)
    areas(pathFinding, 1)
    linkBuildings(buildingsState)
    climb(pathFinding)
    cliffs(tileMap)
    unhover(hovered)
    redrawMinimap(minimap, 1)
  end

  local function forget(list)
    for i = #list, 1, -1 do
      U.bytes = U.bytes - list[i].size
      core.deallocate(list[i].address)
      list[i] = nil
    end
  end
  local function snapshot()
    for _, section in ipairs(sections) do core.copyMemory(section.shadow, section.address, section.size) end
  end
  local function closeStep()
    U.open = false
    local size = diff() & 0xFFFFFFFF
    if size == 0 then return end
    if size == 0xFFFFFFFF then
      log(WARNING, MODULE_NAME .. ": an editor change too big to undo; the undo history starts afresh")
      forget(U.steps)
      forget(U.redo)
      return
    end
    local record = { address = core.allocate(size, false), size = size }
    core.copyMemory(record.address, U.scratch, size)
    forget(U.redo)
    U.steps[#U.steps + 1] = record
    U.bytes = U.bytes + size
    while #U.steps > K.UNDO_STEPS or (U.bytes > K.UNDO_MOST_BYTES and #U.steps > 1) do
      local oldest = table.remove(U.steps, 1)
      U.bytes = U.bytes - oldest.size
      core.deallocate(oldest.address)
    end
  end
  -- Writes a step's old (undo) or new (redo) bytes back: records of address, length, old, new.
  local function apply(record, new)
    local at, finish = record.address, record.address + record.size
    while at < finish do
      local address, length = rd32(at), rd32(at + 4)
      core.copyMemory(address, at + 8 + (new and length or 0), length)
      at = at + 8 + 2 * length
    end
    refresh()
  end

  -- Every command the editor queues (before it is carried out): a map edit after the mouse
  -- buttons were let go starts a new step.
  local command = core.allocate(4, true)
  local function beginEdit()
    if U.open and U.released then closeStep() end
    if not U.open then
      snapshot()
      U.open = true
    end
    U.released = false
  end
  local function onCommand()
    if edits[rd32(command) & 0xFF] then beginEdit() end
  end
  local gameMode = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND)
  local queue = scan(K.AOB_QUEUE_COMMAND, "the command queue")
  local original = {}
  for i, byte in ipairs(core.readBytes(queue, K.QUEUE_COMMAND_SIZE)) do original[i] = string.format("0x%02X", byte & 0xFF) end
  patchJump(self, queue, K.QUEUE_COMMAND_SIZE, core.allocateAssembly(
    templates.undoCommand:gsub("ORIGINAL", "db " .. table.concat(original, ",")), {
      GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, PAD = C.luaPad(onCommand, "the undo history"),
      COMMAND = command, BACK = queue + K.QUEUE_COMMAND_SIZE,
    }))

  -- What the two buttons do (see C.undoButtons), in the map editor only.
  local function editor() return rd32(gameMode) == K.MAP_EDITOR end
  self.undo = {
    editor = editor,
    beginEdit = beginEdit,       -- for the module's own map edits (the pipette)
    undo = function()
      if not editor() then return end
      if U.open then closeStep() end
      local record = table.remove(U.steps)
      if record == nil then return end
      apply(record, false)
      U.redo[#U.redo + 1] = record
    end,
    redo = function()
      if not editor() then return end
      if U.open then closeStep() end   -- something new done since the undo: nothing to redo
      local record = table.remove(U.redo)
      if record == nil then return end
      apply(record, true)
      U.steps[#U.steps + 1] = record
    end,
    -- Every frame (from the buttons): notes the mouse buttons being let go.
    tick = function()
      if not (down(K.VK_LBUTTON) or down(K.VK_RBUTTON)) then U.released = true end
    end,
    available = {
      undo = function() return U.open or #U.steps > 0 end,
      redo = function() return not U.open and #U.redo > 0 end,
    },
  }

  -- Another map: the history is about the old one.
  expectBytes(block + P.forget, { 0xB9 }, "the map preparation")
  patchJump(self, block + P.forget, P.forgetSize, core.allocateAssembly(templates.undoForget, {
    PAD = C.luaPad(function()
      U.open = false
      forget(U.steps)
      forget(U.redo)
    end, "the undo history"),
    PATHFINDING = pathFinding, BACK = block + P.forget + P.forgetSize,
  }))

  -- Undo and redo as Custom Hotkeys actions (editor/actions.lua), once the history is in. A press
  -- does what a click on the button does, so not while a mouse button is held.
  local hotkeys = actions.provider()
  if hotkeys ~= nil then
    actions.history(hotkeys, function(kind)
      local undo = self.undo
      if undo == nil or not editor() or down(K.VK_LBUTTON) or down(K.VK_RBUTTON) or not undo.available[kind]() then
        return false
      end
      undo[kind]()
      return true
    end)
  end
  log(INFO, string.format("%s: undo and redo ready (%d map sections, %.1f MB)", MODULE_NAME, #sections, total / 1e6))
end

return true

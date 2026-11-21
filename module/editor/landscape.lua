local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local K = layout.K
local C = layout.C
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local rd32 = memory.rd32
local native = require("editor.native")
local resolveMenu = native.resolveMenu
local resolveDrawing = native.resolveDrawing
local resolveCounters = native.resolveCounters
local resolveRocks = native.resolveRocks
local resolveHerds = native.resolveHerds
local buildTable = require("editor.landscape_menu").buildTable
local menu_install = require("editor.menu_install")
local installTable = menu_install.installTable
local patchJump = menu_install.patchJump
local patchTrees = require("editor.vegetation").patchTrees
local patchRocks = require("editor.terrain_patches").patchRocks
local patchHerds = require("editor.landscape_controls").patchHerds

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
  if data.mask ~= nil then
    local ok, problem = pcall(C.patchTextureMask, self, G, data)
    if not ok then log(WARNING, tostring(problem) .. "; the texture mask does nothing") end
  end
  if data.heights ~= nil then
    local ok, problem = pcall(C.patchHeightTools, self, G, data)
    if not ok then log(WARNING, tostring(problem) .. "; the height tools keep breaking rocks") end
  end
  if data.heights ~= nil or data.mask ~= nil then
    local ok, problem = pcall(C.patchHeightFilters, self, G, data)
    if not ok then log(WARNING, tostring(problem) .. "; the height tools change every tile under the brush") end
  end
  if data.heights ~= nil or data.treePreviewDraw ~= nil or data.groupWarning ~= nil then
    local ok, problem = pcall(C.patchFrame, self, G, data)
    if not ok then log(WARNING, tostring(problem) .. "; the tree preview only shows with the menu") end
  end
  if data.pipette ~= nil then
    local ok, problem = pcall(C.patchPipettePreview, self, data.pipette, data.pipetteRead)
    if not ok then log(WARNING, tostring(problem) .. "; the pipette shows the whole brush while taking a tile") end
  end
  if O.eraserChoice or O.eraseGulls then
    local ok, problem = pcall(C.patchEraserChoice, self, G, O.eraserChoice, O.eraseGulls)
    if not ok then log(WARNING, tostring(problem) .. "; the eraser takes everything as before") end
  end
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

return {
  enableMenu = enableMenu,
  enableSignpost = enableSignpost,
  enableRandomPreview = enableRandomPreview,
}

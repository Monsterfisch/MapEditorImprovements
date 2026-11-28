local C = require("editor.layout").C
local memory = require("editor.memory")
local jumpTo = memory.jumpTo
local rd32 = memory.rd32

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
C.patchJump = patchJump                  -- for C functions written above this one

return {
  installTable = installTable,
  patchJump = patchJump,
}

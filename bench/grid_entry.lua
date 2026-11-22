-- The bench's way into the module: the resource grid alone, enabled the way init.lua enables
-- it, then the map drawing's shared patch site committed the same way. `editorRoutine`, when
-- given, stands in for the editor's own frame work (the tree preview and the rest), which needs
-- the whole editor menu.
return function(moduleDir)
  package.path = moduleDir .. "/?.lua;" .. package.path
  local grid = require("editor.grid")
  local frame = require("editor.frame")
  local module = {}
  function module.enable(self, config, editorRoutine)
    self.gridOn = grid.enable(self, config)
    if editorRoutine ~= nil then frame.add("editor", editorRoutine) end
    self.problem = nil
    self.committed = frame.commit(self, function(problem) self.problem = tostring(problem) end)
  end
  return module
end

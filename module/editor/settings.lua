local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local TYPE_GROUP_START = layout.TYPE_GROUP_START
local TYPE_END = layout.TYPE_END
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local K = layout.K
local C = layout.C
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readCallTarget = memory.readCallTarget
local bytesOf = memory.bytesOf
local writeCString = memory.writeCString
local rd32 = memory.rd32
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local patchJump = require("editor.menu_install").patchJump
local native = require("editor.native")

---------------------------------------------------------------------------------------
-- Map settings (38): locked maps in the Load dialog, the map menu's Map Settings button and the
-- Alt + , menu itself
---------------------------------------------------------------------------------------

-- A copy of a menu's item table with items of the module's own before its end marker; the
-- constructor's push can be pointed at the copy after its new items are ready.
-- `site` is the `push table / mov ecx, menu / call Menu::Menu` in the constructor. Returns the new
-- items. Whatever the push names now is copied, so a module that extended the table first keeps
-- its items.
function C.appendItems(self, site, count, purpose)
  local old = rd32(site + 1)
  local menu = rd32(site + 6)
  local constructor = readCallTarget(site, 10, "the Menu constructor")
  local n = 0
  while rd32(old + n * MENU_ITEM_SIZE) ~= TYPE_END do
    n = n + 1
    if n > K.MOST_DIALOG_ITEMS then error(MODULE_NAME .. ": " .. purpose .. " is not the one this module knows") end
  end
  local new = core.allocate((n + count + 1) * MENU_ITEM_SIZE, true)
  core.writeBytes(new, core.readBytes(old, n * MENU_ITEM_SIZE))
  core.writeBytes(new + (n + count) * MENU_ITEM_SIZE, core.readBytes(old + n * MENU_ITEM_SIZE, MENU_ITEM_SIZE))
  local items = {}
  for i = 1, count do items[i] = new + (n + i - 1) * MENU_ITEM_SIZE end
  local original = core.readBytes(site + 1, 4)
  local construct = core.exposeCode(constructor, 2, 1)
  local function install()
    self.saved = self.saved or {}
    table.insert(self.saved, { address = site + 1, bytes = original })
    core.writeCodeInteger(site + 1, new)
  end
  local function ensure()
    if rd32(menu) == old then construct(menu, new) end
  end
  return items, install, ensure
end

-- An item that is clicked and drawn by lua functions.
function C.luaItem(into, x, y, width, height, action, render, what)
  wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(into + ITEM_X, x)
  wr32(into + ITEM_Y, y)
  wr32(into + ITEM_WIDTH, width)
  wr32(into + ITEM_HEIGHT, height)
  wr32(into + ITEM_ACTION, action and C.luaPad(action, what) or C.assemble("alwaysYes", {}))
  wr32(into + ITEM_PARAM, 0)
  wr32(into + ITEM_RENDER, render and C.luaPad(render, what) or 0)
  wr32(into + ITEM_RENDER_TYPE, render and RENDER_SIMPLE or RENDER_NONE)
  wr32(into + ITEM_TEXT, 0)
  wr16(into + ITEM_CONTROL, 0)
end

-- The stock button renderer supplies the shared button background, text and rectangle.
local function resolveSettingsDrawing()
  local S = { render = scan(K.AOB_SETTINGS_RENDER, "the Map Settings button renderer") }
  -- The render: `mov ebx,[hover]` first; the item rect is the four words before the hover flag.
  S.hover = rd32(S.render + K.SETTINGS_HOVER)
  S.rect = S.hover - K.RECT_BEFORE_HOVER
  local background, text = S.render + K.SETTINGS_DRAW.background, S.render + K.SETTINGS_DRAW.text
  if not core.matchesAOB(K.AOB_BUTTON_BACKGROUND, background) or not core.matchesAOB(K.AOB_BUTTON_TEXT, text) then
    error(MODULE_NAME .. ": the Map settings buttons are not drawn as the module expects")
  end
  S.buttons = rd32(background + K.BUTTON_BACKGROUND.this)
  S.buttonBackground = readCallTarget(background, K.BUTTON_BACKGROUND.call, "the button background")
  S.textManager = rd32(text + 1)
  S.renderText = readCallTarget(text, 5, "the text drawing")
  return S
end

local function resolveSettings(render)
  local S = {}
  local modal = scan(K.AOB_SETTINGS_MODAL, "the Map settings menu")
  S.modalSite = modal
  S.menu = rd32(modal + K.SETTINGS_MODAL.menu)
  S.record = rd32(modal + K.SETTINGS_MODAL.record)
  S.site = scan("68 ? ? ? ? B9 " .. bytesOf(S.menu) .. " E8 ? ? ? ? C3", "the Map settings menu's constructor")
  local itemTable, _, constructor = memory.menuTable(S.site, 1, K.SETTINGS_SINGLE_RECORD, "the Map Settings menu")
  S.table, S.constructor = itemTable, constructor
  S.action = rd32(S.table + ITEM_ACTION)
  S.render = rd32(S.table + ITEM_RENDER)
  if rd32(S.table + ITEM_TYPE) ~= TYPE_GROUP_START or S.render ~= render then
    error(MODULE_NAME .. ": the Map settings menu is not the one this module knows")
  end
  local labels = scan(K.AOB_SETTINGS_LABELS, "the Map settings labels")
  S.singleLabel = labels + K.SETTINGS_LABELS.single
  S.multiLabel = labels + K.SETTINGS_LABELS.multi
  local koth = scan(K.AOB_SETTINGS_KOTH, "the King of the Hill flag")
  S.multi = rd32(koth + K.SETTINGS_KOTH.multi)
  S.koth = rd32(koth + K.SETTINGS_KOTH.koth)
  S.balanced = rd32(scan(K.AOB_BALANCED, "the balanced flag") + K.BALANCED)
  S.lock = rd32(scan(K.AOB_SETTINGS_ACTION, "the map lock") + K.SETTINGS_LOCK)
  S.size = rd32(scan(K.AOB_SETTINGS_SIZE, "the map size") + K.SETTINGS_SIZE_VAR)
  S.sizeEntry = scan(K.AOB_SETTINGS_SIZE_ENTRY, "the map size change")
  return S
end

local settingsControls
local function resolveSettingsControls()
  if settingsControls == nil then
    local alt = scan(K.AOB_ALT_COMMA, "Alt + ,")
    local modal = rd32(alt + K.ALT_COMMA.modal)
    local manager = rd32(alt + K.ALT_COMMA.manager)
    local entry = readCallTarget(alt, K.ALT_COMMA.open, "the modal opener")
    local open = core.exposeCode(entry, 3, 1)
    local function openSettings()
      if rd32(modal) ~= -1 then return false end
      open(manager, K.SETTINGS_MODAL_ID, 0)
      return true
    end
    settingsControls = {
      openSettings = openSettings,
      closeSettings = function() open(manager, -1, 0) end,
    }
  end
  return settingsControls
end

-- Draws a button the way the Map settings menu draws its own: background (highlighted while
-- chosen or under the mouse), then the text centred in the game's button font.
function C.buttonDrawer(S, G)
  local background = core.exposeCode(S.buttonBackground, 3, 1)
  local renderText = core.exposeCode(S.renderText, 9, 1)
  local buffers = {}
  local function buffer(text)
    if buffers[text] == nil then
      buffers[text] = core.allocate(#text + 1, true)
      writeCString(buffers[text], text)
    end
    return buffers[text]
  end
  local function rect()
    return rd32(S.rect), rd32(S.rect + 4), rd32(S.rect + 8), rd32(S.rect + 12)
  end
  local D = {}
  function D.button(text, chosen, box)
    local hovered = rd32(S.hover)
    wr32(S.hover, (chosen or hovered ~= 0) and 1 or 0)
    background(S.buttons, 0, -1)
    wr32(S.hover, hovered)
    local x, y, w = rect()
    local textX = x + w // 2
    if box ~= nil then                         -- a check box at the left, ticked while on
      local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
      local l, t = x + K.CHECK_INSET, y + K.CHECK_INSET
      local s = K.CHECK_SIZE
      G.colourBoxFn(G.pencil, l, t, l + s, t + 1, white)
      G.colourBoxFn(G.pencil, l, t + s - 1, l + s, t + s, white)
      G.colourBoxFn(G.pencil, l, t, l + 1, t + s, white)
      G.colourBoxFn(G.pencil, l + s - 1, t, l + s, t + s, white)
      if box then G.colourBoxFn(G.pencil, l + 3, t + 3, l + s - 3, t + s - 3, white) end
      textX = textX + (K.CHECK_INSET + s) // 2
    end
    renderText(S.textManager, buffer(text), textX, y + K.BUTTON_TEXT_DOWN, 1,
      hovered ~= 0 and K.TEXT_HOVERED or K.TEXT_NORMAL, K.BUTTON_FONT, 0, 0)
  end
  function D.text(text, font, down)
    local x, y, w = rect()
    renderText(S.textManager, buffer(text), x + w // 2, y + (down or 0), 1, K.TEXT_NORMAL, font, 0, 0)
  end
  D.rect = rect
  return D
end

function C.enableMapSettings(self, O)
  local G = self.landscape or {}
  local drawingOK, drawing, draw = pcall(function()
    local S = resolveSettingsDrawing()
    return S, C.buttonDrawer(S, G)
  end)
  local controlsOK, controls
  if O.settingsButton or O.settingsMenu then controlsOK, controls = pcall(resolveSettingsControls) end
  local boxesOK, boxesProblem
  if O.lockedMaps or O.settingsMenu then
    boxesOK, boxesProblem = pcall(function()
      native.resolveButtonDrawing(G)
      G.colourBoxFn = core.exposeCode(G.colourBox, 6, 1)
    end)
  end
  local function install(wanted, name, fn)
    if not wanted then return end
    local ok, problem = pcall(function()
      if not drawingOK then error(drawing, 0) end
      fn()
    end)
    if not ok then log(ERROR, name .. " is off. " .. tostring(problem)) end
  end

  -- 38.1: Show locked maps, in the Load dialog while it lists maps.
  install(O.lockedMaps, "Show locked maps", function()
    if not boxesOK then error(boxesProblem, 0) end
    local anchor = scan(K.AOB_LOAD_MODAL, "the Load dialog")
    local menu = rd32(anchor + 1)
    local init = scan("68 ? ? ? ? B9 " .. bytesOf(menu) .. " E8", "the Load dialog constructor")
    local show = core.allocate(4, true)
    local site = scan(K.AOB_LOCK_FILTER, "the locked map filter")
    expectBytes(site + K.LOCK_FILTER.jump, { 0x75 }, "the locked map filter")
    local drop = site + K.LOCK_FILTER.size + (rd8(site + K.LOCK_FILTER.jump + 1) & 0xFF)
    local stub = C.assemble("lockedMaps", { SHOW = show, LOCK_STATE = rd32(site + 2), KEEP = site + K.LOCK_FILTER.size,
      DROP = drop })
    local action = scan(K.AOB_LOAD_ACTION, "the Load maps action")
    local listState = rd32(action + K.LOAD_ACTION.listState)
    local modal = rd8(action + K.LOAD_ACTION.modal)
    local opener = core.exposeCode(readCallTarget(action, K.LOAD_ACTION.open, "the map list"), 2, 1)
    local items, publish, ensure = C.appendItems(self, init, 1, "the Load dialog")
    local toggle = items[1]
    local function listingMaps() return rd32(listState) == K.MAP_LIST_KIND end
    C.luaItem(toggle, K.LOCKED_TOGGLE.x, K.LOCKED_TOGGLE.y, K.LOCKED_TOGGLE.width, K.LOCKED_TOGGLE.height,
      function()
        if not toggle or not listingMaps() then return end
        wr32(show, rd32(show) ~= 0 and 0 or 1)
        opener(listState, modal)
      end,
      function()
        if not toggle then return end
        local on = listingMaps()
        wr32(toggle + ITEM_WIDTH, on and K.LOCKED_TOGGLE.width or 0)
        wr32(toggle + ITEM_HEIGHT, on and K.LOCKED_TOGGLE.height or 0)
        if on then draw.button("Show locked maps", false, rd32(show) ~= 0) end
      end, "the Show locked maps box")
    publish()
    patchJump(self, site, K.LOCK_FILTER.size, stub)
    ensure()
    local render = rd32(toggle + ITEM_RENDER)
    hooks.registerHookCallback("afterInit", function()
      ensure()
      -- Another extension may have copied the item into its replacement table.
      local item = rd32(init + 1)
      local match
      toggle = nil
      -- The checkbox and Autosave's three buttons may extend the table.
      for _ = 0, K.MOST_DIALOG_ITEMS + 4 do
        if rd32(item + ITEM_TYPE) == TYPE_END then
          toggle = match
          break
        end
        if not match and rd32(item + ITEM_RENDER) == render then match = item end
        item = item + MENU_ITEM_SIZE
      end
      if not toggle then
        log(ERROR, "Show locked maps is off. The Load control could not be restored.")
      end
    end)
  end)

  -- 38.2: the Map Settings button on the map's menu screen.
  install(O.settingsButton, "The Map Settings button", function()
    if not controlsOK then error(controls, 0) end
    local init = memory.menuInitializer(0x1E0)
    memory.menuTable(init, K.PROPERTIES_ITEM, K.PROPERTIES_RECORD, "the map menu")
    local items, publish, ensure = C.appendItems(self, init, 1, "the map menu")
    local b = K.SETTINGS_BUTTON
    C.luaItem(items[1], b.x, b.y, b.width, b.height, controls.openSettings,
      function() draw.button("Map Settings", false) end, "the Map Settings button")
    publish()
    ensure()
    hooks.registerHookCallback("afterInit", ensure)
  end)

  -- 38.3-38.9: the menu itself.
  install(O.settingsMenu, "Expanded Map Settings", function()
    if not controlsOK then error(controls, 0) end
    if not boxesOK then error(boxesProblem, 0) end
    local S = resolveSettings(drawing.render)
    native.resolveMouse(G)
    C.settingsMenu(self, G, S, draw, controls.closeSettings)
  end)
end

function C.settingsMenu(self, G, S, draw, closeSettings)
  local L = K.SETTINGS_LAYOUT
  local keyState = C.resolved and C.resolved.keyState or rd32(scan(K.AOB_ASYNC_KEY, "the key state") + K.ASYNC_KEY_IMPORT)
  local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = keyState }), 1, 0)
  local function leftHeld() return (asyncKey(K.LEFT_BUTTON) % 0x10000) >= 0x8000 end
  local mapSize = core.exposeCode(C.assemble("mapSize", { SIZE_CODE = S.sizeEntry }), 1, 0)

  -- The table: the group (Single, Multi, the four map types, the four sizes), then the module's
  -- own items, then the end marker.
  local group = { { L.single, 0xA }, { L.multi, 0xB } }
  for i, param in ipairs(K.MAP_TYPE_PARAMS) do group[#group + 1] = { L.types[i], param } end
  for i, param in ipairs(K.MAP_SIZE_PARAMS) do group[#group + 1] = { L.sizes[i], param } end
  local own = { "title", "custom", "slider", "sliderTick", "balanced", "koth", "lock", "back" }
  local count = 1 + #group + #own + 1
  local new = core.allocate(count * MENU_ITEM_SIZE, true)
  core.writeBytes(new, core.readBytes(S.table, MENU_ITEM_SIZE))
  local model = S.table + MENU_ITEM_SIZE                   -- the Single button
  for i, entry in ipairs(group) do
    local into = new + i * MENU_ITEM_SIZE
    core.writeBytes(into, core.readBytes(model, MENU_ITEM_SIZE))
    wr32(into + ITEM_X, entry[1].x)
    wr32(into + ITEM_Y, entry[1].y)
    wr32(into + ITEM_WIDTH, entry[1].width)
    wr32(into + ITEM_HEIGHT, K.SETTINGS_BUTTON.height)
    wr32(into + ITEM_PARAM, entry[2])
    wr32(into + ITEM_ACTION, S.action)
    wr32(into + ITEM_RENDER, S.render)
  end
  local at = {}
  for i, kind in ipairs(own) do at[kind] = new + (#group + i) * MENU_ITEM_SIZE end
  core.writeBytes(new + (count - 1) * MENU_ITEM_SIZE, core.readBytes(S.table + K.SETTINGS_ITEMS * MENU_ITEM_SIZE,
    MENU_ITEM_SIZE))
  if rd32(new + (count - 1) * MENU_ITEM_SIZE) ~= TYPE_END then
    error(MODULE_NAME .. ": the Map settings menu is not the one this module knows")
  end

  local h = K.SETTINGS_BUTTON.height
  local function flip(address) wr32(address, rd32(address) ~= 0 and 0 or 1) end
  C.luaItem(at.title, 0, L.title.y, K.SETTINGS_SIZE.width, 0, nil,
    function() draw.text("Map Settings", K.TITLE_FONT) end, "the Map settings title")
  local function standard()
    local size = rd32(S.size)
    for _, value in ipairs(K.MAP_SIZES) do if value == size then return true end end
    return false
  end
  C.luaItem(at.custom, L.custom.x, L.custom.y, L.custom.width, h, nil,
    function() draw.button("Custom", not standard()) end, "the Custom size")
  -- The slider: a click picks the size under the mouse and follows it while held; the map gets
  -- the size when the button is let go.
  local slider = { dragging = false, value = nil }
  local function valueAt()
    local x, _, w = draw.rect()
    local mouse = C.mouseX(G)
    if mouse == nil then return nil end
    local low, high = K.MAP_SIZE_RANGE[1], K.MAP_SIZE_RANGE[2]
    local t = math.min(math.max((mouse - x - K.SLIDER_INSET) / math.max(w - 2 * K.SLIDER_INSET, 1), 0), 1)
    return math.floor(low + t * (high - low) + 0.5)
  end
  local sliderRect = {}
  C.luaItem(at.slider, L.slider.x, L.slider.y, L.slider.width, h,
    function()
      slider.dragging = true
      slider.value = valueAt() or rd32(S.size)
    end,
    function()
      sliderRect.x, sliderRect.y, sliderRect.w = draw.rect()
      if slider.dragging then
        local value = valueAt()
        if value ~= nil then slider.value = value end
      end
      local value = slider.dragging and slider.value or rd32(S.size)
      draw.button(string.format("Map size: %d", value), false)
      local low, high = K.MAP_SIZE_RANGE[1], K.MAP_SIZE_RANGE[2]
      local t = (math.min(math.max(value, low), high) - low) / (high - low)
      local x = sliderRect.x + K.SLIDER_INSET + math.floor(t * (sliderRect.w - 2 * K.SLIDER_INSET) + 0.5)
      local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
      G.colourBoxFn(G.pencil, x - 2, sliderRect.y + 2, x + 2, sliderRect.y + h - 2, white)
    end, "the map size slider")
  wr32(at.sliderTick + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(at.sliderTick + ITEM_ACTION, C.luaPad(function()
    if not slider.dragging or leftHeld() then return end
    slider.dragging = false
    local value = slider.value
    if value ~= nil and value ~= rd32(S.size) then mapSize(value) end
  end, "the map size slider"))
  wr32(at.sliderTick + ITEM_RENDER_TYPE, RENDER_NONE)
  C.luaItem(at.balanced, L.balanced.x, L.balanced.y, L.balanced.width, h, function() flip(S.balanced) end,
    function() draw.button("Balanced", false, rd32(S.balanced) == 0) end, "the Balanced box")   -- 0: balanced
  C.luaItem(at.koth, L.koth.x, L.koth.y, L.koth.width, h, function() flip(S.koth) end,
    function() draw.button("King of the Hill", false, rd32(S.koth) ~= 0) end, "the King of the Hill box")
  C.luaItem(at.lock, L.lock.x, L.lock.y, L.lock.width, h,
    function() wr32(S.lock, rd32(S.lock) ~= 0 and 0 or K.MAP_LOCKED) end,
    function() draw.button("Lock map", false, rd32(S.lock) ~= 0) end, "the Lock map box")
  C.luaItem(at.back, L.back.x, L.back.y, L.back.width, h,
    closeSettings, function() draw.button("Back", false) end, "the Back button")

  -- Texts: Singleplayer and Multiplayer.
  local labels = { { site = S.singleLabel, text = "Singleplayer" }, { site = S.multiLabel, text = "Multiplayer" } }
  for _, label in ipairs(labels) do
    label.address = core.allocate(#label.text + 1, true)
    writeCString(label.address, label.text)
  end
  local construct = core.exposeCode(S.constructor, 2, 1)
  self.saved = self.saved or {}
  for _, label in ipairs(labels) do
    table.insert(self.saved, { address = label.site, bytes = core.readBytes(label.site, 4) })
    core.writeCodeInteger(label.site, label.address)
  end
  -- Size: the constructor's pushes, and the record if it was built already.
  local m = K.SETTINGS_MODAL
  table.insert(self.saved, { address = S.modalSite + m.height, bytes = core.readBytes(S.modalSite + m.height, 4) })
  table.insert(self.saved, { address = S.modalSite + m.width, bytes = core.readBytes(S.modalSite + m.width, 4) })
  core.writeCodeInteger(S.modalSite + m.height, K.SETTINGS_SIZE.height)
  core.writeCodeInteger(S.modalSite + m.width, K.SETTINGS_SIZE.width)
  local function resize()
    if rd32(S.record) == K.SETTINGS_MODAL_ID then
      wr32(S.record + K.MODAL_WIDTH, K.SETTINGS_SIZE.width)
      wr32(S.record + K.MODAL_HEIGHT, K.SETTINGS_SIZE.height)
    end
  end
  resize()
  hooks.registerHookCallback("afterInit", resize)
  -- The table.
  table.insert(self.saved, { address = S.site + 1, bytes = core.readBytes(S.site + 1, 4) })
  core.writeCodeInteger(S.site + 1, new)
  local function ensure()
    if rd32(S.menu) == S.table then construct(S.menu, new) end
  end
  ensure()
  hooks.registerHookCallback("afterInit", ensure)
end

return true

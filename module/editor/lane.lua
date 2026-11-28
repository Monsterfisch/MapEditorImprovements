-- The band above an editor menu where the module's floating panels go: the picture rows (tree,
-- rock, castle variants, ruins, ...), the herd and height panels and the wall height slider.
-- One placement for all of them, so none covers anything else drawn there:
--
--   * the menu's own items above its top edge (in both menus two buttons sit at y 410), measured
--     the way the module measures buttons (their size, else their picture's);
--   * the game's description line (the native item drawn by the description renderer, 400 wide)
--     and the row above it, where controls belonging to the description go;
--   * the module's own fixed boxes there (the building counts above the minimap).
--
-- A box goes in at its preferred bottom, at the free spot nearest its preferred centre. When no
-- spot along that line is wide enough, it moves up above whatever it would cover and tries again.
-- Positions are menu coordinates, as the menu items' own.

local layout = require("editor.layout")
local K = layout.K
local ITEM_X, ITEM_Y = layout.ITEM_X, layout.ITEM_Y
local ITEM_WIDTH, ITEM_HEIGHT = layout.ITEM_WIDTH, layout.ITEM_HEIGHT
local ITEM_TYPE, ITEM_PARAM, ITEM_IMAGE = layout.ITEM_TYPE, layout.ITEM_PARAM, layout.ITEM_IMAGE
local ITEM_RENDER, ITEM_RENDER_TYPE, ITEM_HIDDEN = layout.ITEM_RENDER, layout.ITEM_RENDER_TYPE, layout.ITEM_HIDDEN
local TYPE_BLOCK, TYPE_END = layout.TYPE_BLOCK, layout.TYPE_END
local RENDER_IMAGE = layout.RENDER_IMAGE
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local IMAGE_INDEX_MASK, IMAGE_SIZE, PICTURE_SIZE = layout.IMAGE_INDEX_MASK, layout.IMAGE_SIZE, layout.PICTURE_SIZE
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE
local MENU_X, MENU_SCROLL = layout.MENU_X, layout.MENU_SCROLL
local PANEL_BOTTOM, PANEL_GAP, PANEL_MARGIN = layout.PANEL_BOTTOM, layout.PANEL_GAP, layout.PANEL_MARGIN
local TOOLTIP_LINE = layout.TOOLTIP_LINE

local M = {}

-- How far above the menu's top items still count: anything lower is the menu itself.
M.BAND_BELOW = 64

---------------------------------------------------------------------------------------
-- Placement (pure: numbers in, numbers out)
---------------------------------------------------------------------------------------

---The spot for a box of width x height.
---@param width number
---@param height number
---@param opts table left, right: the span it may use; inner: { left, right }, the part it stays in
---  when it fits there (the menu's own width, so a panel stays over the menu and moves up rather
---  than sideways off it); bottom: its preferred bottom; centre: its preferred centre; keepOut:
---  list of { x, y, w, h } it may not cover; gap: room kept around them
---@return number left, number top
function M.place(width, height, opts)
  local gap = opts.gap or 0
  local bottom = opts.bottom
  local left, right, centre = opts.left, opts.right, opts.centre
  local inner = opts.inner
  if inner ~= nil then
    local innerLeft, innerRight = math.max(left, inner.left), math.min(right, inner.right)
    if innerRight - innerLeft >= width then left, right = innerLeft, innerRight end
  end
  -- Each step up clears at least one keep-out for good, so this ends within #keepOut steps.
  for _ = 1, #opts.keepOut + 2 do
    local top = bottom - height
    local blocked, highest = {}, nil
    for _, r in ipairs(opts.keepOut) do
      if r.y < bottom + gap and r.y + r.h > top - gap and r.x - gap < right and r.x + r.w + gap > left then
        blocked[#blocked + 1] = { r.x - gap, r.x + r.w + gap }
        highest = highest == nil and r.y or math.max(highest, r.y)
      end
    end
    table.sort(blocked, function(a, b) return a[1] < b[1] end)
    -- The free stretches of the span along this line, and the one nearest the centre that fits.
    local best, bestDistance = nil, nil
    local from = left
    local function consider(a, b)
      if b - a < width then return end
      local x = math.max(a, math.min(b - width, centre - width / 2))
      local distance = math.abs(x + width / 2 - centre)
      if best == nil or distance < bestDistance then best, bestDistance = x, distance end
    end
    for _, b in ipairs(blocked) do
      if b[1] > from then consider(from, b[1]) end
      from = math.max(from, b[2])
    end
    consider(from, right)
    if best ~= nil then return math.floor(best + 0.5), top end
    if highest == nil then                             -- the span itself is too narrow
      return math.floor(math.max(left, centre - width / 2) + 0.5), top
    end
    -- Up just past the lowest-lying of what it would cover; the others may still leave room.
    bottom = highest - gap
  end
  return math.floor(math.max(left, centre - width / 2) + 0.5), bottom - height
end

---Whether two { x, y, w, h } rects share any point.
function M.overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

---------------------------------------------------------------------------------------
-- What is already in the band (reads the live menu)
---------------------------------------------------------------------------------------

---The items of a menu table by block (0: those shown with every tab, else the tab's id), in the
---order the menu has them, and for each item its block and its place in the table. Called once
---the module's copy of the table is complete.
---@return table<number, number[]> addresses by block, table<number, number> block by address,
---  table<number, number> place by address
function M.blocks(itemTable)
  local rd32 = core.readInteger
  local blocks, blockOf, order, block, i = { [0] = {} }, {}, {}, 0, 0
  while true do
    local address = itemTable + i * MENU_ITEM_SIZE
    local itemType = rd32(address + ITEM_TYPE)
    if itemType == TYPE_END then break end
    if itemType == TYPE_BLOCK then
      block = rd32(address + ITEM_PARAM)
      blocks[block] = blocks[block] or {}
    else
      table.insert(blocks[block], address)
      blockOf[address], order[address] = block, i
    end
    i = i + 1
  end
  return blocks, blockOf, order
end

---A button's picture size (its image table entry's gm picture), nil while the gm is not loaded.
function M.measurePicture(G, address)
  local rd32, rd16 = core.readInteger, core.readSmallInteger
  local index = rd32(address + ITEM_IMAGE) & IMAGE_INDEX_MASK
  local gm = rd32(G.buttonImages + index * IMAGE_SIZE)
  local first = rd32(G.firstPictures + gm * 4)
  if first <= 0 then return nil end
  local header = G.pictureHeights - 2 + (first + rd32(G.buttonImages + index * IMAGE_SIZE + 4) - 1) * PICTURE_SIZE
  local width, height = rd16(header), rd16(header + 2)
  if width <= 0 then return nil end
  return width, height
end

---A menu item's size: its own, else its picture's for an item the menu draws as a picture; nil
---if it has neither.
function M.measure(G, address)
  local rd32 = core.readInteger
  local width, height = rd32(address + ITEM_WIDTH), rd32(address + ITEM_HEIGHT)
  if width > 0 and height > 0 then return width, height end
  if rd32(address + ITEM_RENDER_TYPE) ~= RENDER_IMAGE then return nil end
  width, height = M.measurePicture(G, address)
  if width == nil or height == nil or height <= 0 then return nil end
  return width, height
end

---Whether an item that could not be measured may still get a size: a picture item with a picture
---(not image 0, which has none: the build menu has one such item) whose gm is not loaded yet.
local function pending(address)
  local rd32 = core.readInteger
  return rd32(address + ITEM_RENDER_TYPE) == RENDER_IMAGE and (rd32(address + ITEM_IMAGE) & IMAGE_INDEX_MASK) ~= 0
end

---What a floating panel of this menu must keep clear of while `tab` is shown, apart from the
---module's fixed boxes (M.extras): the menu's items above its top (not the module's floating ones)
---and the description line with the row above it. Also whether every item could be measured (its
---picture may not be loaded yet, nor the menu laid out).
---@param measure fun(address: number): number?, number?
---@return table[] rects, boolean complete
function M.keepOuts(data, tab, measure)
  local rd32, rd16 = core.readInteger, core.readSmallInteger
  local list, complete = {}, true
  local function add(address)
    if data.floating[address] or rd16(address + ITEM_HIDDEN) ~= 0 then return end
    local x = rd32(address + ITEM_X)
    if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then
      complete = false
      return
    end
    local y = rd32(address + ITEM_Y)
    if y >= PANEL_BOTTOM + M.BAND_BELOW then return end
    local width, height = measure(address)
    if width ~= nil then
      list[#list + 1] = { x = x, y = y, w = width, h = height }
    elseif pending(address) then
      complete = false
    end
  end
  for _, address in ipairs(data.laneBlocks[0] or {}) do add(address) end
  if tab ~= 0 then
    for _, address in ipairs(data.laneBlocks[tab] or {}) do add(address) end
  end
  local description = data.description
  if description ~= nil then
    local shift = data.descriptionShift or 0
    local y = rd32(description + ITEM_Y)
    list[#list + 1] = { x = rd32(description + ITEM_X) - shift, y = y - K.DESCRIPTION_ROW,
      w = rd32(description + ITEM_WIDTH) + shift, h = K.DESCRIPTION_ROW + TOOLTIP_LINE }
  end
  return list, complete
end

---The module's fixed boxes in the band (the building counts), as they were last drawn.
function M.extras(data)
  local list = {}
  for _, rect in pairs(data.laneExtra) do list[#list + 1] = rect end
  return list
end

-- How many placements reuse a tab's keep-outs before they are read again from the menu.
M.REUSE = 60

---The menu's own width: from its leftmost to its rightmost item on the menu bar (from the row
---above its top down) shown with every tab, the description line included; nil while none can be
---measured. Items elsewhere on the screen (the undo and redo buttons at its top left) don't count.
---Also whether every such item could be measured.
---@return table|nil span, boolean complete
function M.menuSpan(data, measure)
  local rd32, rd16 = core.readInteger, core.readSmallInteger
  local low, high, complete = nil, nil, true
  local function take(x, width)
    low = low == nil and x or math.min(low, x)
    high = high == nil and x + width or math.max(high, x + width)
  end
  for _, address in ipairs(data.laneBlocks[0] or {}) do
    local x = rd32(address + ITEM_X)
    if not data.floating[address] and rd16(address + ITEM_HIDDEN) == 0 then
      if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then
        complete = false
      elseif rd32(address + ITEM_Y) >= PANEL_BOTTOM - K.DESCRIPTION_ROW then
        local width = measure(address)
        if width ~= nil then
          take(x, width)
        elseif pending(address) then
          complete = false
        end
      end
    end
  end
  if data.description ~= nil then
    take(rd32(data.description + ITEM_X), rd32(data.description + ITEM_WIDTH))
  end
  if low == nil then return nil, complete end
  return { left = low, right = high }, complete
end

---Whether any of these items is shown.
local function anyShown(items)
  local rd16 = core.readSmallInteger
  for _, address in ipairs(items) do
    if rd16(address + ITEM_HIDDEN) == 0 then return true end
  end
  return false
end

---The spot for a floating box of this menu: centred over the menu, as low as it can sit at its
---preferred bottom (PANEL_BOTTOM unless given) without covering anything in the band, within the
---menu's width when it fits there. `owner` is what places it (a panel): its `items` are the
---floating ones it moves. Its box also stays clear of the boxes of the owners the menu draws
---before it in the same frame (the pipette panel, in the block every tab shows, before a
---Vegetation panel; a wall panel before its slider): those shown, of the block every tab shows or
---of the tab shown. An owner the menu draws later keeps clear of this one instead, so neither
---depends on the other's last frame, and a panel left up on another tab does not count.
---@param extra table[]|nil more rects to keep clear of (the panel a slider stands on)
---@return number left, number top
function M.spot(G, data, owner, width, height, bottom, extra)
  local rd32 = core.readInteger
  if not owner.laneRegistered then
    -- Where the menu draws it: the block and the place of its first item in the table.
    owner.laneOrder = math.huge
    for _, address in ipairs(owner.items) do
      data.floating[address] = true
      local place = data.laneOrder ~= nil and data.laneOrder[address] or nil
      if place ~= nil and place < owner.laneOrder then
        owner.laneOrder, owner.laneBlock = place, data.laneBlockOf[address]
      end
    end
    owner.laneRegistered = true
  end
  -- Menu coordinates to the screen: the menu's x less its scroll, as the menu draws its items.
  local menuX = rd32(G.menu + MENU_X) - rd32(G.menu + MENU_SCROLL)
  local screen = rd32(G.screenWidth)
  local function measure(address) return M.measure(G, address) end
  -- The menu's items stay put once it is laid out: read them once per tab, then reuse them a while.
  local tab = rd32(G.activeTab)
  local cache = data.laneCache
  if cache == nil or cache.tab ~= tab or cache.uses >= M.REUSE then
    local list, complete = M.keepOuts(data, tab, measure)
    local span, spanComplete = M.menuSpan(data, measure)
    cache = { tab = tab, list = list, span = span, uses = (complete and spanComplete) and 0 or M.REUSE }
    data.laneCache = cache
  end
  cache.uses = cache.uses + 1
  local keepOut = {}
  for _, rect in ipairs(cache.list) do keepOut[#keepOut + 1] = rect end
  for _, rect in ipairs(M.extras(data)) do keepOut[#keepOut + 1] = rect end
  for _, rect in ipairs(extra or {}) do keepOut[#keepOut + 1] = rect end
  data.lanePlaced = data.lanePlaced or {}
  for other, placed in pairs(data.lanePlaced) do
    if other.laneOrder < owner.laneOrder and (other.laneBlock == 0 or other.laneBlock == tab)
        and anyShown(other.items) then
      keepOut[#keepOut + 1] = placed
    end
  end
  local left, top = M.place(width, height, {
    left = PANEL_MARGIN - menuX, right = screen - PANEL_MARGIN - menuX, centre = screen / 2 - menuX,
    inner = cache.span, bottom = bottom or PANEL_BOTTOM, keepOut = keepOut, gap = PANEL_GAP,
  })
  data.lanePlaced[owner] = { x = left, y = top, w = width, h = height }
  return left, top
end

---Set up a menu's lane once its item table is complete: its items by block and its description
---line, given, or else the item the game's description renderer draws.
function M.prepare(data, itemTable, description, descriptionRender, descriptionShift)
  data.laneBlocks, data.laneBlockOf, data.laneOrder = M.blocks(itemTable)
  data.descriptionShift = descriptionShift or 0
  data.description = description
  if description == nil then
    for _, address in ipairs(data.laneBlocks[0]) do
      if core.readInteger(address + ITEM_RENDER) == descriptionRender then data.description = address end
    end
  end
  if data.description == nil then
    log(WARNING, "the description line of a menu was not found; panels may cover it")
  end
end

return M

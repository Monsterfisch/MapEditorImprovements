-- Resource grid: what the picture looks like for a view (moved here from Resource Grid Overlay
-- 1.1.x, by Monsterfish). Pure geometry plus the writes into the block the assembly draws from.
--
-- What is on screen
--
--   * The resource grid itself. `AIVState` carries `HeatMap heatMaps[80][80]`, one record per
--     5 x 5 block of tiles - `incrementStructureHeatMapTile` divides both tile coordinates by 5
--     before indexing it - and every "where does a quarry / iron mine / woodcutter's hut go"
--     decision (`findAppropriateGridLocationForResourceTypeBuilding`,
--     `findAppropriateWoodCutterGridLocation`, `recomputeAIAvailableGridTiles`) counts boulders,
--     iron, oil and trees per block. So the block edges, every fifth tile boundary in both map
--     axes, are what a mapper needs to see.
--
--   * The keep rotation boundaries. `setKeepOffsetAndOrientation` takes the direction from the
--     keep to the map centre (200, 200), rounds it down to an even one of the eight compass
--     directions and swaps east with west, which leaves four regions. A keep placed in each of
--     them has its whole AIV built at a different rotation. The four boundaries meet at the
--     centre tile and run out to the map edge at a 1:2 slope; the real boundary is a staircase
--     that wanders up to about one tile either side of the straight line drawn here.
--
--   The lines lie on one height, because a flat grid has to. The one they lie on is the height
--   `renderMap` levels every tile to in its flattened view - the one the editor's spacebar turns
--   on - which is the map's normal ground, so the grid sits on ordinary flat terrain and matches
--   the flattened view exactly. That height is read out of the instruction that sets it rather
--   than hardcoded.
--
--   Nothing reaches the surface unclipped: the lines are clipped in lua to the part of the
--   surface this frame redrew, and a mine marker whose corners leave that box is dropped.
--   Nothing is clamped, so nothing gets bent.

local B = require("editor.grid_draw")

local M = {}

---------------------------------------------------------------------------------------
-- Map and surface geometry
---------------------------------------------------------------------------------------

-- The AI's resource grid: one cell per 5 x 5 tiles, 80 x 80 cells on a 400 x 400 map.
local GRID_STEP = 5
local MAP_TILES = 400

-- Where an iron mine lands inside a block. `aiPlaceIronMine` asks
-- `findAppropriateGridLocationForResourceTypeBuilding` for a block and then places the mine at
-- tile (5*gridX, 5*gridY) flat - no candidate offsets, unlike the quarry, which walks a ring of
-- nine - so the footprint always sits flush in the low corner of the block and leaves the last
-- row and column of the block empty.
--
-- Only the two far edges are drawn, meeting at the footprint's far corner: the other two are the
-- grid lines themselves, so together they close the box.
--
-- These have to be real per-block segments rather than lines running the width of the map - a
-- continuous lattice is a different picture, it joins every block to the next. That is
-- thousands of short segments a frame at a wide resolution zoomed out, far too many to push
-- through lua one at a time, so the loop that emits them is assembly: it walks the visible
-- blocks, works each corner out by adding a constant step, and draws the two edges. A block
-- whose marker is not wholly inside the clip box is skipped rather than clipped, which costs a
-- marker at the very edge of the screen and saves clipping arithmetic on every one of them.
M.MINE_FOOTPRINT = 4

-- A "400 x 400" map holds 80400 tiles, laid out as a diamond inside the 400 x 400 coordinate
-- square: row y runs from x = 199-y to x = 200+y and back again. In terms of d = x - y and
-- s = x + y that diamond is exactly the rectangle d in [-200, 200], s in [199, 599]
-- (401 * 200 + 400 * 201 = 80400 tiles), and the corners of those tiles reach one step further
-- out.
local CORNER_D_MIN, CORNER_D_MAX = -201, 201
local CORNER_S_MIN, CORNER_S_MAX = 199, 601

-- Where `renderMap` puts a tile on the map surface. It starts every row at x = 0x46 (+0x10 on
-- every other row), steps 0x20 per tile along the row and 8 down per row, and starts from the
-- grid cell (viewportX/32, viewportY/16).
--
-- **Which way the map is turned matters.** That loop is identical whichever way it is; what
-- changes is which of the four blocks of `screenPointToTileNumber` it walks, and each block lays
-- the diamond along a different pair of axes - the rows of block 0 are lines of constant s, of
-- block 1 lines of constant d, and so on round the four quarter turns. Writing d = x-y and
-- s = x+y, and unrolling the loop for each block, the point the four tiles around corner
-- (cx, cy) share comes out as
--   P.x = (constX - 32*cameraCell)              + xd*d + xs*s
--   P.y = (rowBias + 8 + constY - 16*cameraRow) + yd*d + ys*s
-- with the coefficients in ORIENTATIONS below. Every one of them is linear in d and s, so a
-- straight line in tile space stays a straight line on screen at any rotation and only its two
-- endpoints have to be transformed.
--
-- Getting this wrong is not always obvious: the grid is its own mirror image, so it still looks
-- plausible at 180 degrees while the keep rotation boundaries, which are not symmetric, come out
-- visibly wrong.
--
-- **Zoomed out** (`[vp+0x90] != 0`) the tile loop is unchanged - same 0x20 per tile, same 8 per
-- row - and the halving happens in the blitter instead: it lands the tile at
-- `surface + (drawX & ~1) + (drawY >> 1)*0x1FB0`, i.e. at pixel `(drawX/2, drawY/2)`, and the
-- viewport asks for twice as many tiles and rows to fill the screen. Every number above is even,
-- so the whole transform survives being divided by two exactly; that is the only difference,
-- and getting it wrong makes the grid keep its zoomed-in size and scroll at twice the speed of
-- the map. Verified against a re-simulation of the table builder and both render loops: the four
-- blocks each come out a permutation of all 80400 tiles, and the transform matches every tile
-- the game places, at every rotation and both zoom levels.
M.ORIENTATIONS = {
  [0] = { constX = 3350, xd = 16, xs = 0, constY = -1592, yd = 0, ys = 8 },
  [6] = { constX = 9750, xd = 0, xs = -16, constY = 1608, yd = 8, ys = 0 },
  [4] = { constX = 3350, xd = -16, xs = 0, constY = 4808, yd = 0, ys = -8 },
  [2] = { constX = -3050, xd = 0, xs = 16, constY = 1608, yd = -8, ys = 0 },
}
M.DEFAULT_ORIENTATION = 0
local ORIENTATIONS, DEFAULT_ORIENTATION = M.ORIENTATIONS, M.DEFAULT_ORIENTATION

local ROW_PITCH = 8
local TILE_PITCH = 32
local FIRST_TILE_SURFACE_X = 0x46
M.ZOOMED_OUT_DIVISOR = 2
local ZOOMED_OUT_DIVISOR = M.ZOOMED_OUT_DIVISOR

-- Terrain height. The blitter puts each tile at `rowY - heightOffset[tileHeight]`, so a flat
-- overlay has to choose a height to lie at. `renderMap`'s flattened branch - the one the
-- editor's spacebar turns on - forces that offset to a single constant for every tile, and that
-- constant is the normal ground the whole map is levelled to, so it is exactly the height the
-- lines want. It is read out of the instruction that sets it rather than hardcoded, and only
-- used as a fallback here.
M.DEFAULT_GROUND_HEIGHT = 8

-- The map surface is 0x1FB0 bytes (4056 pixels) per line, and the game's pencil only ever draws
-- inside that; the clip box below keeps to the same range. Two pixels are left spare at the
-- bottom for the second row of the line.
local SURFACE_WIDTH = 4056
local SURFACE_HEIGHT = 4056
M.SURFACE_PITCH = 0x1FB0
local LINE_THICKNESS_SPARE = 2

-- `renderMap` renders `[viewport+0x8C] + 0x2A` rows minus the first-row bias, and
-- `[viewport+0x88]` (+1 on the longer rows) tiles per row. Anything outside that is surface the
-- frame did not touch.
local EXTRA_RENDERED_ROWS = 0x2A

-- Viewport (ViewportRenderState) field offsets.
M.VIEWPORT_X = 0x78
M.VIEWPORT_Y = 0x7C
M.VIEWPORT_TILES_PER_ROW = 0x88
M.VIEWPORT_ROW_COUNT = 0x8C
M.VIEWPORT_ZOOMED_OUT = 0x90
M.VIEWPORT_ROW_BIAS_ACTIVE = 0x94

-- Window/graphics struct: the 16 bit pixel layout DirectDraw handed the game, and the map surface
-- pointer, which the pencil reads from +0xD8.
M.COLOR_BIT_MODE_IN_STRUCT = 0x54
local COLOR_MODE_565 = 0x565
M.MAP_SURFACE_POINTER_IN_STRUCT = 0xD8

-- The four keep rotation boundaries, in tile-corner coordinates. They start at the four corners
-- of the centre tile (200, 200) and end where the staircase they approximate runs off the map.
-- Moving the origin translates all four.
local ROTATION_ORIGIN = 200

-- Where they are actually drawn. `setKeepOffsetAndOrientation` compares the keep against tile
-- (200, 200), and that is genuinely the centre of the playable area at every map size, but on
-- the map the boundaries line up three tiles further out, so that is what gets drawn. This
-- offset is measured against the game rather than derived: the likely reason is that the
-- coordinate the game compares is the keep's own anchor tile while what a mapper lines a keep up
-- by is its middle, which for a keep's footprint is about three tiles along both axes.
M.DEFAULT_ROTATION_ORIGIN = 203
local ROTATION_BOUNDARIES = {
  { 201, 201, 267, 333 },  -- north / east
  { 200, 201, 67, 267 },   -- north / west
  { 201, 200, 334, 134 },  -- east / south
  { 200, 200, 134, 66 },   -- south / west
}

-- Line styles, which index the colour table the assembly reads.
M.STYLE_GRID = 1
M.STYLE_ROTATION = 2
M.STYLE_MINE = 3
local STYLE_GRID, STYLE_ROTATION, STYLE_MINE = M.STYLE_GRID, M.STYLE_ROTATION, M.STYLE_MINE

-- Colours as 8 bit per channel, resolved to the surface's own 16 bit layout at draw time because
-- the graphics replacer can be configured either way.
M.COLOURS = {
  white = { 255, 255, 255 },
  red = { 255, 32, 32 },
  yellow = { 255, 224, 0 },
  cyan = { 0, 255, 255 },
  green = { 0, 255, 64 },
  magenta = { 255, 0, 255 },
  orange = { 255, 144, 0 },
  black = { 0, 0, 0 },
}

local COORDINATE_RANGE, STYLE_SHIFT = B.COORDINATE_RANGE, B.STYLE_SHIFT

-- Looked up once; the rebuild calls them a few hundred times.
local readInteger = core.readInteger
local writeInteger = core.writeInteger
local floor = math.floor
local min = math.min
local max = math.max

---Integer division that rounds towards zero, which is what the game's `cdq / and / sar`
---sequences do and what the viewport-to-grid-cell arithmetic has to match.
local function truncatedDivide(value, divisor)
  if value < 0 then
    return -floor(-value / divisor)
  end
  return floor(value / divisor)
end

---Pack an 8 bit per channel colour into the surface's 16 bit layout.
---@param channels number[] red, green, blue in 0..255
---@param is565 boolean true for RGB 5-6-5, false for (A)RGB 1-5-5-5
---@return number
function M.packColour(channels, is565)
  local red, green, blue = channels[1], channels[2], channels[3]
  if is565 then
    return floor(red / 8) * 0x800 + floor(green / 4) * 0x20
      + floor(blue / 8)
  end
  return floor(red / 8) * 0x400 + floor(green / 8) * 0x20
    + floor(blue / 8)
end

---------------------------------------------------------------------------------------
-- The line list
---------------------------------------------------------------------------------------

---Screen offset, relative to the corner lattice origin, of the tile corner (cx, cy), for one
---map rotation. Every coefficient is even, so the zoomed-out halving is exact.
local function cornerOffset(cornerX, cornerY, transform, divisor)
  local d, s = cornerX - cornerY, cornerX + cornerY
  return (transform.xd * d + transform.xs * s) // divisor,
    (transform.yd * d + transform.ys * s) // divisor
end

---Every line the overlay can draw, as screen offsets from the corner lattice origin plus a style
---index. Built once per rotation and zoom level; only the origin moves as the camera scrolls.
---@param tune table the fine tuning settings
---@param transform table one entry of ORIENTATIONS
---@param divisor number 1 zoomed in, 2 zoomed out
---@return table[] lines each { offsetX1, offsetY1, offsetX2, offsetY2, style }
function M.buildLines(tune, transform, divisor)
  local lines = {}

  local function add(x1, y1, x2, y2, style)
    local offsetX1, offsetY1 = cornerOffset(x1, y1, transform, divisor)
    local offsetX2, offsetY2 = cornerOffset(x2, y2, transform, divisor)
    lines[#lines + 1] = { offsetX1, offsetY1, offsetX2, offsetY2, style }
  end

  -- A grid line at a constant tile x runs along constant cx in the corner lattice, so
  -- d = cx - cy falls and s = cx + cy rises as cy grows. Clipping cy against the map's d and s
  -- bounds gives the part of the line that is over the map at all; lines whose range comes out
  -- empty sit entirely off the diamond and are left out.
  for cx = 0, MAP_TILES, GRID_STEP do
    local low = max(cx - CORNER_D_MAX, CORNER_S_MIN - cx)
    local high = min(cx - CORNER_D_MIN, CORNER_S_MAX - cx)
    if low < high then
      add(cx, low, cx, high, STYLE_GRID)
    end
  end

  for cy = 0, MAP_TILES, GRID_STEP do
    local low = max(cy + CORNER_D_MIN, CORNER_S_MIN - cy)
    local high = min(cy + CORNER_D_MAX, CORNER_S_MAX - cy)
    if low < high then
      add(low, cy, high, cy, STYLE_GRID)
    end
  end

  -- The four boundaries are a rigid cross, so moving the origin just translates them.
  if tune.withRotation then
    local shiftX = tune.originX - ROTATION_ORIGIN
    local shiftY = tune.originY - ROTATION_ORIGIN
    for _, boundary in ipairs(ROTATION_BOUNDARIES) do
      add(boundary[1] + shiftX, boundary[2] + shiftY,
        boundary[3] + shiftX, boundary[4] + shiftY, STYLE_ROTATION)
    end
  end

  return lines
end

---------------------------------------------------------------------------------------
-- Working the picture out for a view
---------------------------------------------------------------------------------------

---@class GridState
---@field control number address of the block shared with the assembly
---@field groundHeight number pixels the flattened map's ground sits above the row line
---@field tune table the fine tuning settings
---@field lines table<number, table[][]> line lists by orientation, then by zoom divisor
---@field nudgeX number[] screen nudge per style index
---@field nudgeY number[]
---@field palette table<boolean, number[]> packed colours per style, by "is 565"

---Clip every line to the box and write the survivors into the list the assembly draws.
---@return number how many were written
local function writeSegments(state, lines, originX, originY,
    clipLeft, clipRight, clipTop, clipBottom)
  local list = state.control + B.SEGMENT_LIST
  local nudgeX, nudgeY = state.nudgeX, state.nudgeY
  local count = 0

  for index = 1, #lines do
    local line = lines[index]
    local style = line[5]
    local baseX = originX + nudgeX[style]
    local baseY = originY + nudgeY[style]
    local x1 = baseX + line[1]
    local y1 = baseY + line[2]
    local x2 = baseX + line[3]
    local y2 = baseY + line[4]
    local deltaX = x2 - x1
    local deltaY = y2 - y1

    -- Liang-Barsky, unrolled over the four edges. `enter` and `leave` are the fraction of the
    -- line that survives; `alive` goes false as soon as the two cross.
    local enter, leave, alive = 0.0, 1.0, true

    for edge = 1, 4 do
      local p, q
      if edge == 1 then
        p, q = -deltaX, x1 - clipLeft
      elseif edge == 2 then
        p, q = deltaX, clipRight - x1
      elseif edge == 3 then
        p, q = -deltaY, y1 - clipTop
      else
        p, q = deltaY, clipBottom - y1
      end

      if p == 0 then
        if q < 0 then
          alive = false
          break
        end
      else
        local ratio = q / p
        if p < 0 then
          if ratio > leave then
            alive = false
            break
          end
          if ratio > enter then
            enter = ratio
          end
        else
          if ratio < enter then
            alive = false
            break
          end
          if ratio < leave then
            leave = ratio
          end
        end
      end
    end

    if alive then
      local startX = floor(x1 + enter * deltaX + 0.5)
      local startY = floor(y1 + enter * deltaY + 0.5)
      local endX = floor(x1 + leave * deltaX + 0.5)
      local endY = floor(y1 + leave * deltaY + 0.5)
      -- The clip box already keeps every end inside the surface; this only guards the packing,
      -- which has twelve bits per coordinate.
      if startX >= 0 and startX < COORDINATE_RANGE and startY >= 0
          and startY < COORDINATE_RANGE and endX >= 0 and endX < COORDINATE_RANGE
          and endY >= 0 and endY < COORDINATE_RANGE then
        local slot = list + count * 8
        writeInteger(slot, startX + startY * COORDINATE_RANGE + style * STYLE_SHIFT)
        writeInteger(slot + 4, endX + endY * COORDINATE_RANGE)
        count = count + 1
      end
    end
  end

  return count
end

---Screen position of the tile corner (cx, cy) for one rotation and zoom level.
local function cornerScreen(transform, divisor, originX, originY, cornerX, cornerY)
  local d, s = cornerX - cornerY, cornerX + cornerY
  return originX + (transform.xd * d + transform.xs * s) // divisor,
    originY + (transform.yd * d + transform.ys * s) // divisor
end

---Tile corner a screen point sits on, the inverse of the above. Exactly one of the two
---coefficients on each screen axis is non-zero, so each axis yields one of d and s.
local function screenCorner(transform, divisor, originX, originY, x, y)
  local d, s
  if transform.xd ~= 0 then
    d = (x - originX) * divisor / transform.xd
  else
    s = (x - originX) * divisor / transform.xs
  end
  if transform.yd ~= 0 then
    d = (y - originY) * divisor / transform.yd
  else
    s = (y - originY) * divisor / transform.ys
  end
  return (s + d) / 2, (s - d) / 2
end

-- The map's four extreme corners and the clip box's four corners, walked by index so the rebuild
-- allocates nothing.
local MAP_CORNER_D = { CORNER_D_MIN, CORNER_D_MAX, CORNER_D_MIN, CORNER_D_MAX }
local MAP_CORNER_S = { CORNER_S_MIN, CORNER_S_MIN, CORNER_S_MAX, CORNER_S_MAX }

---Fill in the marker parameter block for this view, or leave it empty.
local function writeMarkers(state, transform, divisor, originX, originY,
    clipLeft, clipRight, clipTop, clipBottom, colour)
  local size = state.tune.mineSize

  -- One block step and the two footprint edges, in screen pixels. Every coefficient is even, so
  -- these divide exactly at both zoom levels.
  local stepXx = GRID_STEP * (transform.xd + transform.xs) // divisor
  local stepXy = GRID_STEP * (transform.yd + transform.ys) // divisor
  local stepYx = GRID_STEP * (transform.xs - transform.xd) // divisor
  local stepYy = GRID_STEP * (transform.ys - transform.yd) // divisor
  local farX = size * (transform.xd + transform.xs) // divisor
  local farY = size * (transform.yd + transform.ys) // divisor
  local sideX = size * (transform.xs - transform.xd) // divisor
  local sideY = size * (transform.ys - transform.yd) // divisor

  -- Only blocks over the map are worth walking. The map is a rectangle on screen, so
  -- intersecting the clip box with its four extreme corners is the whole test.
  local mapLeft, mapRight, mapTop, mapBottom
  for corner = 1, 4 do
    local d, s = MAP_CORNER_D[corner], MAP_CORNER_S[corner]
    local x = originX + (transform.xd * d + transform.xs * s) // divisor
    local y = originY + (transform.yd * d + transform.ys * s) // divisor
    mapLeft = mapLeft and min(mapLeft, x) or x
    mapRight = mapRight and max(mapRight, x) or x
    mapTop = mapTop and min(mapTop, y) or y
    mapBottom = mapBottom and max(mapBottom, y) or y
  end

  local left = max(clipLeft, mapLeft)
  local right = min(clipRight, mapRight)
  local top = max(clipTop, mapTop)
  local bottom = min(clipBottom, mapBottom)
  if right <= left or bottom <= top then
    return
  end

  -- Block range covering that box. The corners of a screen rectangle map to a turned rectangle
  -- in block space, so this over-covers; the loop's own test drops the rest.
  local lowX, highX, lowY, highY
  for corner = 1, 4 do
    local pointX = (corner == 1 or corner == 3) and left or right
    local pointY = corner <= 2 and top or bottom
    local cornerX, cornerY = screenCorner(
      transform, divisor, originX, originY, pointX, pointY)
    local blockX = floor(cornerX / GRID_STEP)
    local blockY = floor(cornerY / GRID_STEP)
    lowX = lowX and min(lowX, blockX) or blockX
    highX = highX and max(highX, blockX) or blockX
    lowY = lowY and min(lowY, blockY) or blockY
    highY = highY and max(highY, blockY) or blockY
  end

  local blocks = MAP_TILES // GRID_STEP
  lowX = max(lowX - 1, -1)
  lowY = max(lowY - 1, -1)
  highX = min(highX + 1, blocks)
  highY = min(highY + 1, blocks)
  if highX < lowX or highY < lowY then
    return
  end

  local anchorX, anchorY = cornerScreen(transform, divisor, originX, originY,
    GRID_STEP * lowX, GRID_STEP * lowY)

  -- The counts go last, so the block never holds a count with stale steps behind it.
  local parameters = state.control + B.MARKER_BLOCK
  writeInteger(parameters + 8, anchorX)
  writeInteger(parameters + 12, anchorY)
  writeInteger(parameters + 16, stepXx)
  writeInteger(parameters + 20, stepXy)
  writeInteger(parameters + 24, stepYx)
  writeInteger(parameters + 28, stepYy)
  writeInteger(parameters + 32, farX)
  writeInteger(parameters + 36, farY)
  writeInteger(parameters + 40, sideX)
  writeInteger(parameters + 44, sideY)
  writeInteger(parameters + 48, clipLeft)
  writeInteger(parameters + 52, clipRight)
  writeInteger(parameters + 56, clipTop)
  writeInteger(parameters + 60, clipBottom - LINE_THICKNESS_SPARE)
  writeInteger(parameters + 64, colour)
  writeInteger(parameters + 4, highY - lowY + 1)
  writeInteger(parameters, highX - lowX + 1)
end

---Work out what the overlay looks like for the view the frame routine just recorded, and leave
---it where the assembly draws it from. Called only when that view has changed.
---@param state GridState
function M.rebuild(state)
  local control = state.control

  -- Empty first, so that anything going wrong part way leaves nothing half drawn.
  writeInteger(control + B.SEGMENT_COUNT, 0)
  writeInteger(control + B.MARKER_BLOCK, 0)
  writeInteger(control + B.MARKER_BLOCK + 4, 0)

  local zoomedOut = readInteger(control + B.VIEW_KEY_ZOOMED_OUT) ~= 0
  local divisor = zoomedOut and ZOOMED_OUT_DIVISOR or 1

  local orientation = readInteger(control + B.VIEW_KEY_ORIENTATION)
  local transform = ORIENTATIONS[orientation]
  if transform == nil then
    orientation = DEFAULT_ORIENTATION
    transform = ORIENTATIONS[orientation]
  end

  local colours = state.palette[
    readInteger(control + B.VIEW_KEY_COLOUR_MODE) == COLOR_MODE_565]
  writeInteger(control + B.STYLE_COLOURS + 4 * STYLE_GRID, colours[STYLE_GRID])
  writeInteger(control + B.STYLE_COLOURS + 4 * STYLE_ROTATION, colours[STYLE_ROTATION])
  writeInteger(control + B.STYLE_COLOURS + 4 * STYLE_MINE, colours[STYLE_MINE])

  -- Reproduce the row bias `renderMap` picks, because the whole vertical placement and the
  -- number of rows it renders hang off it.
  local rowBias = 0
  local firstRow = 0
  if readInteger(control + B.VIEW_KEY_ROW_BIAS) ~= 0 then
    if zoomedOut then
      rowBias, firstRow = 0x80, 0x10
    else
      rowBias, firstRow = 0x40, 8
    end
  end

  local cameraCell = truncatedDivide(
    readInteger(control + B.VIEW_KEY_VIEWPORT_X), TILE_PITCH)
  local cameraRow = truncatedDivide(
    readInteger(control + B.VIEW_KEY_VIEWPORT_Y) + rowBias, 2 * ROW_PITCH)

  -- Every term is even, so the zoomed-out halving is exact rather than a rounding. The ground
  -- height is part of the same pixel scale, so it halves with the rest; the boundary nudges are
  -- in finished screen pixels and are added afterwards.
  local originX = (transform.constX - TILE_PITCH * cameraCell) // divisor
  local originY = (rowBias + ROW_PITCH + transform.constY
    - 2 * ROW_PITCH * cameraRow - state.groundHeight) // divisor

  -- The clip box is the part of the map surface this frame actually redrew: rows `rowBias` to
  -- `rowBias + 8*rendered`, columns from the first tile of a row to the last. Anything wider is
  -- surface the frame never touched.
  local tilesPerRow = readInteger(control + B.VIEW_KEY_TILES_PER_ROW)
  local renderedRows = readInteger(control + B.VIEW_KEY_ROW_COUNT)
    + EXTRA_RENDERED_ROWS - firstRow

  local clipLeft = FIRST_TILE_SURFACE_X // divisor
  local clipRight = min(
    (FIRST_TILE_SURFACE_X + TILE_PITCH * (tilesPerRow + 2)) // divisor,
    SURFACE_WIDTH - 1)
  local clipTop = max(rowBias // divisor, 0)
  local clipBottom = min(
    (rowBias + ROW_PITCH + ROW_PITCH * renderedRows) // divisor, SURFACE_HEIGHT - 1)

  if clipRight <= clipLeft or clipBottom - LINE_THICKNESS_SPARE <= clipTop then
    return
  end

  writeInteger(control + B.SEGMENT_COUNT, writeSegments(state,
    state.lines[orientation][divisor], originX, originY,
    clipLeft, clipRight, clipTop, clipBottom - LINE_THICKNESS_SPARE))

  if state.tune.mineBoxes then
    writeMarkers(state, transform, divisor, originX, originY,
      clipLeft, clipRight, clipTop, clipBottom, colours[STYLE_MINE])
  end
end

return M

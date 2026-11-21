local layout = require("editor.layout")
local png = layout.png
local MODULE_NAME = layout.MODULE_NAME
local MODULE_FOLDERS = layout.MODULE_FOLDERS
local wr32 = require("editor.memory").wr32

---------------------------------------------------------------------------------------
-- Pictures from images/
---------------------------------------------------------------------------------------

local function readFile(name)
  for _, folder in ipairs(MODULE_FOLDERS) do
    local file = io.open(folder .. name, "rb")
    if file ~= nil then
      local data = file:read("a")
      file:close()
      return data
    end
  end
  return nil
end

local function loadPicture(name)
  local data = readFile("images/" .. name .. ".png")
  if data == nil then
    error(string.format("%s: images/%s.png not found", MODULE_NAME, name))
  end
  local ok, width, height, pixels = pcall(png.decode, data)
  if not ok then
    error(string.format("%s: images/%s.png: %s", MODULE_NAME, name, (tostring(width):gsub("^.-:%d+: ", ""))))
  end
  return { width = width, height = height, pixels = pixels }
end

-- Writes a picture, centred on a width x height canvas, in the layout the blit routine
-- reads and returns its address.
local function storePicture(picture, width, height)
  local count = width * height
  local base = core.allocate(0x14 + count * 5, true)
  local rgb565, rgb555, mask = {}, {}, {}
  local left, top = (width - picture.width) // 2, (height - picture.height) // 2
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local sx, sy = x - left, y - top
      local p = { 0, 0, 0, 0 }
      if sx >= 0 and sy >= 0 and sx < picture.width and sy < picture.height then
        p = picture.pixels[sy * picture.width + sx + 1]
      end
      local r, g, b = p[1], p[2], p[3]
      local value565 = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
      local value555 = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
      rgb565[index * 2 - 1], rgb565[index * 2] = value565 & 0xFF, value565 >> 8
      rgb555[index * 2 - 1], rgb555[index * 2] = value555 & 0xFF, value555 >> 8
      mask[index] = p[4]
    end
  end
  wr32(base, width)
  wr32(base + 4, height)
  wr32(base + 8, base + 0x14)
  wr32(base + 0xC, base + 0x14 + count * 2)
  wr32(base + 0x10, base + 0x14 + count * 4)
  core.writeBytes(base + 0x14, rgb565)
  core.writeBytes(base + 0x14 + count * 2, rgb555)
  core.writeBytes(base + 0x14 + count * 4, mask)
  return base
end

-- A button's three pictures: <name>.png, <name>_hover.png, <name>_selected.png, all on the
-- canvas of the largest.
local function buttonPictures(name)
  local normal, hover, chosen = loadPicture(name), loadPicture(name .. "_hover"), loadPicture(name .. "_selected")
  local width = math.max(normal.width, hover.width, chosen.width)
  local height = math.max(normal.height, hover.height, chosen.height)
  return {
    width = width, height = height,
    normal = storePicture(normal, width, height),
    hover = storePicture(hover, width, height),
    chosen = storePicture(chosen, width, height),
  }
end

return {
  loadPicture = loadPicture,
  storePicture = storePicture,
  buttonPictures = buttonPictures,
}

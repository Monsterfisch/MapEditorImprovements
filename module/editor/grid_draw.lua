-- Resource grid: the shared block and the assembly that draws the grid (moved here from
-- Resource Grid Overlay 1.1.x, by Monsterfish).
--
-- The frame routine is called from the map drawing's patch site (editor/frame.lua) and only
-- calls into lua when there is something new to work out. Switched off, it costs one compare a
-- frame. Switched on, it checks the map editor, flattened view and V view itself, and then
-- compares the few values the picture depends on (map rotation, zoom level,
-- camera, rendered area, pixel format) with the ones it last drew for. Only when one of them has
-- changed does it call lua, which clips every line to the new view and writes what is left into
-- a short list. Every other frame the assembly replays that list.
--
-- The pixels are put down by the module's own line loop, straight into the map surface. It is
-- Bresenham with the same start point, error term and tie-break as `PencilRenderCore::drawLine`,
-- so it sets exactly the pixels the game's drawer would, and it does both rows of the two-pixel
-- line in the same pass.

local M = {}

---------------------------------------------------------------------------------------
-- Shared state between lua and the assembly
---------------------------------------------------------------------------------------

-- One block of memory holds everything both sides read. The lua writes the switches once,
-- flips `shown` from the toggle and the screen change, and fills in the colours, the line list
-- and the marker parameters whenever the frame routine asks it to; the assembly keeps the view
-- values it last drew for, so it can tell when to ask.
M.SHOWN = 0
M.CACHE_VALID = 4            -- 0 makes the next frame work everything out again
M.EDITOR_ONLY = 8
M.FLATTENED_ONLY = 12
M.HIDE_IN_V_VIEW = 16
M.VIEW_KEY = 20              -- the eight values below, in this order
M.VIEW_KEY_ORIENTATION = 20
M.VIEW_KEY_ZOOMED_OUT = 24
M.VIEW_KEY_ROW_BIAS = 28
M.VIEW_KEY_VIEWPORT_X = 32
M.VIEW_KEY_VIEWPORT_Y = 36
M.VIEW_KEY_TILES_PER_ROW = 40
M.VIEW_KEY_ROW_COUNT = 44
M.VIEW_KEY_COLOUR_MODE = 48
M.SEGMENT_COUNT = 52
M.STYLE_COLOURS = 56         -- one int per style index, 0 unused
M.MARKER_BLOCK = 72          -- the marker parameters, see MARKER_SCRIPT
M.MARKER_PARAMETER_COUNT = 17
-- Read in place of a flag whose scan failed.
M.ALWAYS_ZERO = M.MARKER_BLOCK + 4 * M.MARKER_PARAMETER_COUNT
-- Two ints per line, see grid_view.writeSegments; the block ends with it.
M.SEGMENT_LIST = M.ALWAYS_ZERO + 4

-- A clipped line is packed into two ints for the assembly, x in the low 12 bits and y in the
-- next 12 - the clip box keeps both inside 0..4055 - and the style in the top byte of the first.
M.COORDINATE_RANGE = 0x1000
M.STYLE_SHIFT = 0x1000000

---------------------------------------------------------------------------------------
-- Assembly
---------------------------------------------------------------------------------------

---Assemble one script into an allocation of its own. UCP hands fasm a fixed 64 KB for the
---source, the symbols and the output together, and a script dense with labels uses a lot of it,
---so the drawing code is split into small scripts that reach each other by address, and each
---goes in without indentation, comments or constants it never uses.
---@param script string
---@param values table every constant any of the scripts uses
---@return number address of the script's first instruction
local function assemble(script, values)
  local lines = {}
  for rawLine in script:gmatch("[^\n]+") do
    local line = (rawLine:gsub(";.*", "")):match("^%s*(.-)%s*$")
    if line ~= "" then
      lines[#lines + 1] = line
    end
  end
  local body = table.concat(lines, "\n") .. "\n"
  local used = {}
  for name, value in pairs(values) do
    if body:find("%f[%w_]" .. name .. "%f[^%w_]") then
      used[name] = value
    end
  end
  return core.allocateAssembly(body, used)
end

-- `drawSegment(x1, y1, x2, y2, colour)`, cdecl, keeps ebx, esi, edi and ebp.
--
-- `PencilRenderCore::drawLine` unrolled for the map surface: the same Bresenham, stepping from
-- (x1, y1), taking the diagonal step only when the error term is above zero, with y as the major
-- axis exactly when dy > dx, as the game's own test has it. The game's separate horizontal and
-- vertical loops put down the same pixels as this one does with a zero minor step, just in the
-- other order, which one colour cannot show. Each step writes the pixel and the one below it,
-- so one pass draws both rows of the two-pixel line.
local SEGMENT_SCRIPT = [[
  drawSegment:
    push ebp
    push ebx
    push esi
    push edi

    mov eax, dword [esp + 24]
    imul edi, eax, SURFACE_PITCH_VALUE
    add edi, dword [SURFACE_POINTER_ADDRESS]
    mov eax, dword [esp + 20]
    add edi, eax
    add edi, eax

    mov eax, dword [esp + 28]
    sub eax, dword [esp + 20]
    mov ebx, 2
    jge segmentRightward
    neg eax
    mov ebx, -2
  segmentRightward:
    mov ecx, dword [esp + 32]
    sub ecx, dword [esp + 24]
    mov edx, SURFACE_PITCH_VALUE
    jge segmentDownward
    neg ecx
    mov edx, -SURFACE_PITCH_VALUE
  segmentDownward:
    cmp ecx, eax
    jg segmentSteep

    lea esi, [ecx + ecx]
    mov ebp, esi
    sub ebp, eax
    push esi
    sub dword [esp], eax
    sub dword [esp], eax
    mov ecx, eax
    add edx, ebx
    jmp segmentStart

  segmentSteep:
    lea esi, [eax + eax]
    mov ebp, esi
    sub ebp, ecx
    push esi
    sub dword [esp], ecx
    sub dword [esp], ecx
    xchg ebx, edx
    add edx, ebx

  segmentStart:
    mov eax, esi
    movzx esi, word [esp + 40]
  segmentPixel:
    mov word [edi], si
    mov word [edi + SURFACE_PITCH_VALUE], si
    test ebp, ebp
    jle segmentStraight
    add edi, edx
    add ebp, dword [esp]
    sub ecx, 1
    jge segmentPixel
    jmp segmentEnd
  segmentStraight:
    add edi, ebx
    add ebp, eax
    sub ecx, 1
    jge segmentPixel
  segmentEnd:

    add esp, 4
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
]]

-- `drawSegmentList()`: every line lua left in the list, unpacked and drawn in order.
local SEGMENT_LIST_SCRIPT = [[
  drawSegmentList:
    push ebx
    push esi
    push edi
    mov esi, SEGMENT_LIST_ADDRESS
    mov edi, dword [SEGMENT_COUNT_ADDRESS]
  segmentsNext:
    test edi, edi
    jle segmentsDone
    mov eax, dword [esi]
    mov edx, dword [esi + 4]
    mov ecx, eax
    shr ecx, 24
    push dword [STYLE_COLOURS_ADDRESS + ecx*4]
    mov ecx, edx
    shr ecx, 12
    and ecx, 0xFFF
    push ecx
    and edx, 0xFFF
    push edx
    mov ecx, eax
    shr ecx, 12
    and ecx, 0xFFF
    push ecx
    and eax, 0xFFF
    push eax
    call DRAW_SEGMENT
    add esp, 20
    add esi, 8
    sub edi, 1
    jmp segmentsNext
  segmentsDone:
    pop edi
    pop esi
    pop ebx
    ret
]]

-- `drawMarkers()`: one "V" per block, the two far edges of the iron mine footprint.
-- Parameter block, by byte offset from MARKER_PARAMETERS:
--   0 countX      4 countY       8 originX     12 originY
--  16 stepX x    20 stepX y     24 stepY x     28 stepY y
--  32 far-cx x   36 far-cx y    40 far-cy x    44 far-cy y
--  48 clip left  52 clip right  56 clip top    60 clip bottom
--  64 colour
local MARKER_SCRIPT = [[
  drawMarkers:
    push ebp
    mov ebp, esp
    sub esp, 48
    push ebx
    push esi
    push edi

    mov ebx, MARKER_PARAMETERS
    mov eax, dword [ebx + 8]
    mov dword [ebp - 4], eax
    mov eax, dword [ebx + 12]
    mov dword [ebp - 8], eax
    mov eax, dword [ebx + 4]
    mov dword [ebp - 12], eax

  markerRow:
    cmp dword [ebp - 12], 0
    jle markersDone
    mov eax, dword [ebp - 4]
    mov dword [ebp - 16], eax
    mov eax, dword [ebp - 8]
    mov dword [ebp - 20], eax
    mov eax, dword [ebx]
    mov dword [ebp - 24], eax

  markerColumn:
    cmp dword [ebp - 24], 0
    jle markerRowNext
    mov esi, dword [ebp - 16]
    mov edi, dword [ebp - 20]

    mov eax, esi
    add eax, dword [ebx + 32]
    mov dword [ebp - 28], eax
    mov eax, edi
    add eax, dword [ebx + 36]
    mov dword [ebp - 32], eax

    mov eax, esi
    add eax, dword [ebx + 40]
    mov dword [ebp - 36], eax
    mov eax, edi
    add eax, dword [ebx + 44]
    mov dword [ebp - 40], eax

    mov eax, dword [ebp - 28]
    add eax, dword [ebx + 40]
    mov dword [ebp - 44], eax
    mov eax, dword [ebp - 32]
    add eax, dword [ebx + 44]
    mov dword [ebp - 48], eax

    mov eax, dword [ebx + 48]
    cmp dword [ebp - 28], eax
    jl markerSkip
    cmp dword [ebp - 36], eax
    jl markerSkip
    cmp dword [ebp - 44], eax
    jl markerSkip
    mov eax, dword [ebx + 52]
    cmp dword [ebp - 28], eax
    jg markerSkip
    cmp dword [ebp - 36], eax
    jg markerSkip
    cmp dword [ebp - 44], eax
    jg markerSkip
    mov eax, dword [ebx + 56]
    cmp dword [ebp - 32], eax
    jl markerSkip
    cmp dword [ebp - 40], eax
    jl markerSkip
    cmp dword [ebp - 48], eax
    jl markerSkip
    mov eax, dword [ebx + 60]
    cmp dword [ebp - 32], eax
    jg markerSkip
    cmp dword [ebp - 40], eax
    jg markerSkip
    cmp dword [ebp - 48], eax
    jg markerSkip

    push dword [ebx + 64]
    push dword [ebp - 48]
    push dword [ebp - 44]
    push dword [ebp - 32]
    push dword [ebp - 28]
    call DRAW_SEGMENT
    add esp, 20

    push dword [ebx + 64]
    push dword [ebp - 48]
    push dword [ebp - 44]
    push dword [ebp - 40]
    push dword [ebp - 36]
    call DRAW_SEGMENT
    add esp, 20

  markerSkip:
    mov eax, dword [ebp - 16]
    add eax, dword [ebx + 16]
    mov dword [ebp - 16], eax
    mov eax, dword [ebp - 20]
    add eax, dword [ebx + 20]
    mov dword [ebp - 20], eax
    sub dword [ebp - 24], 1
    jmp markerColumn

  markerRowNext:
    mov eax, dword [ebp - 4]
    add eax, dword [ebx + 24]
    mov dword [ebp - 4], eax
    mov eax, dword [ebp - 8]
    add eax, dword [ebx + 28]
    mov dword [ebp - 8], eax
    sub dword [ebp - 12], 1
    jmp markerRow

  markersDone:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
]]

-- The frame routine, called from the map drawing's patch site. All registers are preserved;
-- flags are not, and nothing after the site reads them.
local FRAME_SCRIPT = [[
  gridFrame:
    cmp dword [OVERLAY_SHOWN], 0
    jne frameActive
    ret

  frameActive:
    pushad

    cmp dword [OVERLAY_EDITOR_ONLY], 0
    je frameInPlace
    cmp dword [GAME_MODE_ADDRESS], GAME_MODE_EDITOR_VALUE
    je frameInPlace
    mov dword [OVERLAY_SHOWN], 0
    jmp frameDone

  frameInPlace:
    cmp dword [OVERLAY_FLATTENED_ONLY], 0
    je frameFlatOk
    cmp dword [FLATTEN_A_ADDRESS], 0
    je frameDone
    cmp dword [FLATTEN_B_ADDRESS], 0
    je frameDone
  frameFlatOk:
    cmp dword [OVERLAY_HIDE_IN_V_VIEW], 0
    je frameViewOk
    cmp dword [VIEW_FLAG_ADDRESS], 0
    je frameDone
  frameViewOk:

    ; The picture only depends on these eight values. Keep each one and note whether it
    ; moved; any change, or a cache that was never filled, means asking lua again.
    mov ebx, dword [CACHE_VALID_ADDRESS]
    mov esi, SOURCE_TABLE
    mov edi, VIEW_KEY_ADDRESS
    mov ecx, 8
  frameKeyNext:
    mov edx, dword [esi]
    mov eax, dword [edx]
    cmp eax, dword [edi]
    je frameKeySame
    mov dword [edi], eax
    xor ebx, ebx
  frameKeySame:
    add esi, 4
    add edi, 4
    sub ecx, 1
    jne frameKeyNext

    test ebx, ebx
    jne frameDraw
    call REBUILD_ADDRESS

  frameDraw:
    cmp dword [SURFACE_POINTER_ADDRESS], 0
    je frameDone
    call DRAW_SEGMENT_LIST
    call DRAW_MARKERS

  frameDone:
    popad
    ret
]]

---Build the frame routine and the routines it draws with, callees first so each script can be
---handed the address of the ones it calls.
---@param values table the addresses and constants the scripts refer to
---@return number address of the frame routine
function M.build(values)
  values.DRAW_SEGMENT = assemble(SEGMENT_SCRIPT, values)
  values.DRAW_SEGMENT_LIST = assemble(SEGMENT_LIST_SCRIPT, values)
  values.DRAW_MARKERS = assemble(MARKER_SCRIPT, values)
  return assemble(FRAME_SCRIPT, values)
end

return M

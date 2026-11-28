--[[
  The assembly the module injects. Every upper-case name is a constant init.lua passes in.
]]

local templates = {}

---------------------------------------------------------------------------------------
-- Map counts
---------------------------------------------------------------------------------------

-- Counts the used tree slots (also by tree type), rock slots and group slots.
templates.countSlots = [[
push esi
push edi
mov edi,TYPE_COUNTS
mov ecx,TREE_TYPES
xor eax,eax
rep stosd
xor edx,edx
mov esi,FIRST_TREE
mov ecx,TREE_SLOTS
tree_loop:
cmp word [esi],0
je tree_next
inc edx
movzx eax,word [esi+TREE_TYPE_FROM_IN_USE]
and eax,TREE_TYPES-1
inc dword [TYPE_COUNTS+eax*4]
tree_next:
add esi,TREE_SIZE
dec ecx
jnz tree_loop
mov [TOTALS],edx
xor edx,edx
mov esi,FIRST_ROCK
mov ecx,ROCK_SLOTS
rock_loop:
cmp word [esi],0
je rock_next
inc edx
rock_next:
add esi,ROCK_SIZE
dec ecx
jnz rock_loop
mov [TOTALS+4],edx
xor edx,edx
mov esi,FIRST_GROUP
mov ecx,GROUP_SLOTS
group_loop:
cmp word [esi],0
je group_next
inc edx
group_next:
add esi,GROUP_SIZE
dec ecx
jnz group_loop
mov [TOTALS+8],edx
pop edi
pop esi
ret
]]

-- Render function for the description line, the first item drawn every frame: count, then
-- draw the line as before.
templates.descriptionLine = [[
cmp byte [SHOWN],0
je skip
call COUNT_SLOTS
skip:
jmp HOVER_RENDER
]]

-- Render function for the last item of a tab: the numbers of the tab's counted buttons, drawn
-- after every button of the tab so no neighbouring picture covers them. The item's param is
-- a list of (button item, counter) pairs ending in 0. A button's place on screen is worked
-- out the way the menu's render pass does it (menu position - scroll + item position); its
-- size is what the render pass took from the picture. Hidden buttons get no number.
templates.tabNumbers = [[
cmp byte [SHOWN],0
je done
push esi
mov esi,[esp+8]
next_button:
mov eax,[esi]
test eax,eax
je finished
cmp word [eax+ITEM_HIDDEN],0
jne skip_button
mov ecx,[eax+ITEM_MENU]
mov edx,[ecx+MENU_X]
sub edx,[ecx+MENU_SCROLL]
add edx,[eax+ITEM_X]
mov ecx,[ecx+MENU_Y]
add ecx,[eax+ITEM_Y]
add ecx,[eax+ITEM_HEIGHT]
sub ecx,NUMBER_FROM_BOTTOM
mov eax,[eax+ITEM_WIDTH]
sar eax,1
add edx,eax
mov eax,[esi+4]
push 0
push 0
push NUMBER_FONT
push 0
push NUMBER_COLOUR
push 1
push ecx
push edx
push dword [eax]
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
skip_button:
add esi,8
jmp next_button
finished:
pop esi
done:
ret
]]

-- Render function for the "i": like the description line, on the map surface at the item
-- position plus the camera offset.
templates.infoButton = [[
mov eax,[CAMERA_X]
add [ITEM_X],eax
mov eax,[CAMERA_Y]
add [ITEM_Y],eax
mov dword [DRAW_MODE],1
jmp IMAGE_BUTTON
]]

-- Render function for the tooltip item: hand over to lua while the mouse is on one of the
-- buttons with a tooltip (a list of their hover words, ending in 0).
templates.tooltip = [[
mov ecx,HOVER_WORDS
next_word:
mov eax,[ecx]
test eax,eax
je quiet
cmp word [eax],0
jne show
add ecx,4
jmp next_word
show:
jmp PAD
quiet:
ret
]]

-- Action of the "i" button.
templates.toggle = [[
xor byte [SHOWN],1
ret
]]

---------------------------------------------------------------------------------------
-- Buttons above the panel
---------------------------------------------------------------------------------------

-- Action of the first item, run every frame before the game's map click handler: while the
-- mouse is on one of the module's buttons above the panel (over the map), the click is not a
-- click on the map. The list holds (item, tab) pairs ending in 0; tab 0 means every tab.
-- Until the moved buttons have been laid out (their pictures must be loaded first) it also
-- asks lua to try.
templates.guard = [[
cmp byte [LAID_OUT],0
jne guard
call LAYOUT
guard:
push esi
mov esi,GUARDED
next_guarded:
mov eax,[esi]
test eax,eax
je guard_rects
mov ecx,[esi+4]
test ecx,ecx
je any_tab
cmp ecx,[ACTIVE_TAB]
jne skip_guarded
any_tab:
cmp word [eax+ITEM_HIDDEN],0
jne skip_guarded
push dword [eax+ITEM_HEIGHT]
push dword [eax+ITEM_WIDTH]
mov ecx,[eax+ITEM_MENU]
mov edx,[ecx+MENU_Y]
add edx,[eax+ITEM_Y]
push edx
mov edx,[ecx+MENU_X]
add edx,[eax+ITEM_X]
push edx
mov ecx,MOUSE
call IS_MOUSE_INSIDE
test eax,eax
je skip_guarded
mov dword [ON_MAP],0
jmp guard_rects
skip_guarded:
add esi,8
jmp next_guarded
guard_rects:
mov esi,RECTS
next_rect:
cmp dword [esi],-1
je guard_done
cmp dword [esi],0
je skip_rect
mov dword [esi],0
push dword [esi+16]
push dword [esi+12]
mov edx,[THE_MENU+MENU_Y]
add edx,[esi+8]
push edx
mov edx,[THE_MENU+MENU_X]
add edx,[esi+4]
push edx
mov ecx,MOUSE
call IS_MOUSE_INSIDE
test eax,eax
je skip_rect
mov dword [ON_MAP],0
skip_rect:
add esi,20
jmp next_rect
guard_done:
pop esi
ret
]]

-- Render function of the panel item at the end of a tab: lua draws the panel while one of two
-- ranges of tools is chosen (an empty range is FIRST 1, LAST 0), else every panel button is
-- hidden. A felled tree choice ends when another tool is chosen.
templates.panel = [[
mov eax,[SUBTYPE]
cmp eax,[FELLED_COMMAND]
je keep_felled
mov dword [FELLED_LOGS],0
keep_felled:
cmp eax,FIRST_TREE
jb not_tree
cmp eax,LAST_TREE
jbe show
not_tree:
cmp eax,FIRST_SHRUB
jb hide
cmp eax,LAST_SHRUB
jbe show
hide:
mov ecx,PANEL_ITEMS
hide_next:
mov eax,[ecx]
test eax,eax
je hidden
mov word [eax+ITEM_HIDDEN],1
add ecx,4
jmp hide_next
hidden:
ret
show:
jmp PAD
]]

-- Action of a felled tree button (param: logs): choose that many logs for the tree tool, or,
-- clicked again, go back to standing trees.
templates.felledClick = [[
mov eax,[esp+4]
mov edx,[SUBTYPE]
cmp eax,[FELLED_LOGS]
jne choose
cmp edx,[FELLED_COMMAND]
jne choose
xor eax,eax
choose:
mov [FELLED_LOGS],eax
mov [FELLED_COMMAND],edx
ret
]]

-- Action of a check box or other on/off button: flip the flag.
templates.flip = [[
xor byte [FLAG],1
ret
]]

-- Render function of a check box in the panel (on the screen, like the other buttons): the
-- picture of image table entry ON_IMAGE or OFF_IMAGE (+0 gm, +4 picture), + 1 under the mouse.
templates.checkBox = [[
mov ecx,OFF_IMAGE
cmp byte [FLAG],0
je chosen
mov ecx,ON_IMAGE
chosen:
mov edx,[ecx]
mov eax,[ecx+4]
cmp dword [HOVER],0
je draw
inc eax
draw:
mov dword [DRAW_MODE],0
push dword [ITEM_Y]
push dword [ITEM_X]
push eax
push edx
mov ecx,TEXTURES
call RENDER_GM
mov dword [DRAW_MODE],1
ret
]]

---------------------------------------------------------------------------------------
-- Rocks
---------------------------------------------------------------------------------------

-- Action of a rock variant button (param: variant + 1): choose that variant, or, clicked
-- again, go back to the game's cycling variants.
templates.rockClick = [[
mov eax,[esp+4]
cmp eax,[ROCK_LOCK]
jne set_lock
xor eax,eax
set_lock:
mov [ROCK_LOCK],eax
ret
]]

-- Action of the Rocks menu's own rock buttons: they go back to the cycling variants.
templates.rockButton = [[
mov dword [ROCK_LOCK],0
jmp ACTION
]]

-- The rock number the editor places and previews: variant + size * 4, or with a variant
-- chosen in the panel that variant (+ size * 4), or for the extra rock EXTRA_ID. Replaces
-- `lea ecx,[variant + size*4]` and the 6-byte instruction after it, which ends the template.
templates.rockId = [[
push eax
mov eax,[ROCK_LOCK]
test eax,eax
jne locked
mov ecx,[SIZE]
shl ecx,2
add ecx,[VARIANT]
jmp rock_done
locked:
dec eax
cmp eax,EXTRA_VARIANT
jb chosen_variant
mov ecx,EXTRA_ID
jmp rock_done
chosen_variant:
mov ecx,[SIZE]
shl ecx,2
add ecx,eax
rock_done:
pop eax
]]

-- The random rock button's `mov [mode], ecx` (ecx = 5): the module's own mode instead, which
-- neither of the game's timers turns (5 every frame, 0 once a second); the preview follows the
-- rotation, and templates.rockTurn moves it on after every placed rock.
templates.randomRockMode = [[
mov dword [MODE],TURN_MODE
jmp BACK
]]

-- placeRock's `mov eax,[esi+ROTATION]` (the rotation this rock gets): in the module's mode the
-- next rock gets another rotation (0, 2, 4 or 6, never the same twice in a row).
templates.rockTurn = [[
mov eax,[esi+ROTATION]
cmp dword [GAME_MODE],MAP_EDITOR
jne rock_turn_done
cmp dword [esi+MODE],TURN_MODE
jne rock_turn_done
push eax
push ecx
push edx
mov ecx,eax
rdtsc
and eax,6
cmp eax,ecx
jne rock_turn_new
add eax,2
and eax,6
rock_turn_new:
mov [esi+ROTATION],eax
inc dword [PLACED]
pop edx
pop ecx
pop eax
rock_turn_done:
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Herds
---------------------------------------------------------------------------------------

-- An animal's herd size, `and eax,MASK / mov edi,UNIT / add eax,BASE` (eax: a random byte):
-- with the check box on, 2 * brush - 1 instead.
templates.herdSize = [[
and eax,MASK
mov edi,UNIT
add eax,BASE
cmp byte [HERD_SYNC],0
je herd_done
mov eax,[BRUSH]
add eax,eax
dec eax
herd_done:
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Trees next to obstacles
---------------------------------------------------------------------------------------

-- placeTree, `xor ebx,ebx / test eax,eax / mov [esp+0x10],esi / jle <past the check>`
-- (ebp: the tile, edi: TileMapState): with NO_STACKING set, a tile that already has a tree or
-- shrub is refused (the shrubs that need no room would stack there); with the flag set, the
-- check of the tiles around a new tree is skipped, as for a tree type that needs no room.
templates.nearObstacles = [[
xor ebx,ebx
mov [esp+0x10],esi
cmp byte [NO_STACKING],0
je no_stack_test
movzx ecx,word [edi+ebp*2+NUMBERS]
test ecx,ecx
je no_stack_test
cmp ecx,ROCK_BASE
jb refuse_tile
no_stack_test:
cmp byte [FLAG],0
jne skip_check
test eax,eax
jle skip_check
jmp CHECK
skip_check:
jmp PAST_CHECK
refuse_tile:
jmp REFUSE
]]

---------------------------------------------------------------------------------------
-- Pictures
---------------------------------------------------------------------------------------

-- blit(picture, x, y): copies a picture's opaque pixels to the pencil's surface, clipped by
-- the pencil. A picture is { width, height, 565 pixels, 555 pixels, alpha bytes }.
templates.blit = [[
push ebp
push ebx
push esi
push edi
mov ecx,PENCIL
call SETUP_SURFACE
mov esi,[esp+0x14]
mov eax,[esp+0x18]
mov edx,[esp+0x1C]
mov ecx,[esi+4]
lea ecx,[edx+ecx-1]
mov ebx,[esi]
lea ebx,[eax+ebx-1]
push 0
push ecx
push ebx
push edx
push eax
mov ecx,PENCIL
call SETUP_PENCIL
test eax,eax
je finished
mov eax,[PENCIL+0x30]
mov edx,[PENCIL+0x38]
cmp eax,edx
jle x_sorted
xchg eax,edx
x_sorted:
mov [SCRATCH],eax
mov [SCRATCH+4],edx
mov eax,[PENCIL+0x34]
mov edx,[PENCIL+0x3C]
cmp eax,edx
jle y_sorted
xchg eax,edx
y_sorted:
mov [SCRATCH+8],eax
mov [SCRATCH+12],edx
mov ebp,[esi+8]
cmp dword [PIXEL_FORMAT],0x565
je format_known
mov ebp,[esi+0xC]
format_known:
mov ebx,[SCRATCH+8]
next_row:
cmp ebx,[SCRATCH+12]
jg finished
mov edi,ebx
imul edi,[PENCIL+8]
add edi,[PENCIL+4]
mov eax,ebx
sub eax,[esp+0x1C]
imul eax,[esi]
sub eax,[esp+0x18]
mov [SCRATCH+16],eax
mov ecx,[SCRATCH]
next_pixel:
cmp ecx,[SCRATCH+4]
jg row_done
mov eax,[SCRATCH+16]
add eax,ecx
mov edx,[esi+0x10]
cmp byte [edx+eax],0x80
jb skip_pixel
movzx edx,word [ebp+eax*2]
mov [edi+ecx*2],dx
skip_pixel:
inc ecx
jmp next_pixel
row_done:
inc ebx
jmp next_row
finished:
pop edi
pop esi
pop ebx
pop ebp
ret
]]

-- Render function of a button drawn from PNG pictures (apple tree, gravel): the chosen,
-- hovered or normal picture at the item position, on the screen like the other buttons.
templates.pictureButton = [[
mov eax,NORMAL
cmp dword [SUBTYPE],COMMAND
jne not_chosen
mov eax,CHOSEN
jmp draw
not_chosen:
cmp dword [HOVER],0
je draw
mov eax,HOVERED
draw:
push dword [PENCIL+PENCIL_TARGET]
mov dword [PENCIL+PENCIL_TARGET],0
push dword [ITEM_Y]
push dword [ITEM_X]
push eax
call BLIT
add esp,12
pop dword [PENCIL+PENCIL_TARGET]
ret
]]

---------------------------------------------------------------------------------------
-- Placing trees
---------------------------------------------------------------------------------------

-- mapUITreeTypeToLogicalTreeType(command), replacing `mov eax,[esp+4] / add eax,-0x28`: the
-- apple tree command gives the apple tree, and while the random shrub is on, a shrub command
-- one of the five shrubs at random.
templates.plantType = [[
mov eax,[esp+4]
cmp eax,APPLE_COMMAND
jne not_apple
mov eax,APPLE_TYPE
ret 4
not_apple:
cmp byte [RANDOM_SHRUB],0
je plain
cmp eax,FIRST_SHRUB
jb plain
cmp eax,LAST_SHRUB
ja plain
push ecx
push edx
mov eax,[SEED]
imul eax,eax,RANDOM_MULTIPLIER
add eax,RANDOM_INCREMENT
mov [SEED],eax
shr eax,16
xor edx,edx
mov ecx,LAST_SHRUB-FIRST_SHRUB+1
div ecx
lea eax,[edx+FIRST_SHRUB]
pop edx
pop ecx
plain:
add eax,-0x28
jmp CONVERTER_BACK
]]

-- placeTree, `push 3 / push 0 / movzx eax,ax`: the growth stage handed to createTree is the
-- brush size minus one (0 .. 6; BRUSH may be a constant instead) instead of 3, and with the
-- random tree chosen for this tree tool (FELLED_LOGS = RANDOM_STANDING) a stage from 0 up to
-- that one. A felled tree of the smallest stage (which has no felled picture) gets the next. The command is on the stack as at the felled tree site (createTree cleans up its
-- arguments).
templates.stageFromBrush = [[
push eax
push ecx
push edx
mov eax,[BRUSH]
dec eax
jns stage_low_ok
xor eax,eax
stage_low_ok:
cmp eax,MAX_STAGE
jle stage_high_ok
mov eax,MAX_STAGE
stage_high_ok:
test eax,eax
jne stage_grown
mov ecx,[FELLED_LOGS]
test ecx,ecx
je stage_grown
cmp ecx,RANDOM_STANDING
je stage_grown
movsx ecx,word [esp+COMMAND_ON_STACK+12]
cmp ecx,[FELLED_COMMAND]
jne stage_grown
mov eax,SMALLEST_FELLED_STAGE
stage_grown:
cmp dword [FELLED_LOGS],RANDOM_STANDING
jne stage_done
movsx ecx,word [esp+COMMAND_ON_STACK+12]
cmp ecx,[FELLED_COMMAND]
jne stage_done
cmp eax,MOST_RANDOM_STAGE
ja stage_done
lea ecx,[eax+1]
mov eax,[SEED]
imul eax,eax,RANDOM_MULTIPLIER
add eax,RANDOM_INCREMENT
mov [SEED],eax
shr eax,16
xor edx,edx
div ecx
mov eax,edx
stage_done:
mov [STAGE],eax
pop edx
pop ecx
pop eax
push dword [STAGE]
push 0
movzx eax,ax
jmp BACK
]]

-- placeTree, right after createTree (`mov esi,eax / imul esi,esi,0x9C`; eax, the new tree,
-- is used again further down): with a felled tree chosen for this tree tool, the new tree is
-- laid down the way the woodcutter's log taking leaves it (lying, no chops left, that many
-- logs, at most what a tree of its type and stage gives; RANDOM_FELLED: 1 up to that at
-- random), and its picture worked out again by its update function, called as createTree
-- calls it. The random standing tree (RANDOM_STANDING) stays standing.
templates.felledTree = [[
mov esi,eax
test eax,eax
je plain
cmp dword [FELLED_LOGS],0
je plain
cmp dword [FELLED_LOGS],RANDOM_STANDING
je plain
push eax
movsx edx,word [esp+COMMAND_ON_STACK+4]
cmp edx,[FELLED_COMMAND]
jne felled_done
imul edx,esi,TREE_SIZE
add edx,TREES
movsx eax,word [edx+TREE_TYPE]
lea ecx,[eax-1]
cmp ecx,LAST_TREE_TYPE-1
ja felled_done
imul ecx,eax,STAGES
add ecx,[edx+TREE_STAGE]
mov ecx,[LOGS+ecx*4]
mov eax,[FELLED_LOGS]
cmp eax,RANDOM_FELLED
jne fixed_logs
test ecx,ecx
jle felled_done
push edx
mov eax,[SEED]
imul eax,eax,RANDOM_MULTIPLIER
add eax,RANDOM_INCREMENT
mov [SEED],eax
shr eax,16
xor edx,edx
div ecx
lea eax,[edx+1]
pop edx
fixed_logs:
cmp eax,ecx
jle logs_fit
mov eax,ecx
logs_fit:
test eax,eax
jle felled_done
mov word [edx+TREE_LYING],LYING_FELLED
mov [edx+TREE_LOGS],ax
mov word [edx+TREE_CHOPS],0
push dword [LANDSCAPE]
mov dword [LANDSCAPE],0
movsx eax,word [edx+TREE_TYPE]
call dword [UPDATE_TREE+eax*4]
pop dword [LANDSCAPE]
felled_done:
pop eax
plain:
imul esi,esi,TREE_SIZE
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Always keep the menu up to date
---------------------------------------------------------------------------------------

-- Replaces cmp [countdown], ebx / jne FULL in the main loop.
templates.menuRedraw = [[
cmp dword [COUNTDOWN],0
jne full
cmp dword [GAME_MODE],1
jne partial
full:
jmp FULL
partial:
jmp PARTIAL
]]

---------------------------------------------------------------------------------------
-- Invisible rocks
---------------------------------------------------------------------------------------

-- Called instead of createRock from placeRock: with the check box on, act as if the rock list
-- were full (rock 0), which leaves the tiles taken but no rock drawn - what happens anyway
-- once 4000 rocks are on the map.
templates.invisibleRocks = [[
cmp byte [FLAG],0
jne no_rock
jmp CREATE_ROCK
no_rock:
xor eax,eax
ret ROCK_ARGUMENTS
]]

---------------------------------------------------------------------------------------
-- Castle mode
---------------------------------------------------------------------------------------

-- Render function of a panel item in the build menu: lua draws the panel in the map editor,
-- anywhere else the panel's buttons are hidden.
templates.editorPanel = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne hide
jmp PAD
hide:
mov ecx,PANEL_ITEMS
hide_next:
mov eax,[ecx]
test eax,eax
je hidden
mov word [eax+ITEM_HIDDEN],1
add ecx,4
jmp hide_next
hidden:
ret
]]

-- Render function of something drawn in the map editor only: FIRST, then lua.
templates.editorOnly = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne quiet
call FIRST
jmp PAD
quiet:
ret
]]

-- Counts the buildings: every one in use and not being removed, the players' own
-- buildings (an owner and a type from PLAYER_TYPES) and those of the current player.
templates.buildingCounts = [[
push ebx
push esi
push edi
push ebp
xor eax,eax
xor ebx,ebx
xor edi,edi
mov esi,FIRST_STATE
mov ecx,[BUILDINGS+MAX_BUILDINGS]
dec ecx
jle counted
next_building:
movzx edx,word [esi]
test edx,edx
je skip_building
cmp edx,REMOVED
je skip_building
inc eax
movzx edx,word [esi+TYPE_FROM_STATE]
cmp edx,255
ja skip_building
cmp byte [PLAYER_TYPES+edx],0
je skip_building
movsx ebp,word [esi+OWNER_FROM_STATE]
test ebp,ebp
je skip_building
inc ebx
cmp ebp,[CURRENT_PLAYER]
jne skip_building
inc edi
skip_building:
add esi,BUILDING_SIZE
dec ecx
jne next_building
counted:
mov [COUNTS],eax
mov [COUNTS+4],ebx
mov [COUNTS+8],edi
pop ebp
pop edi
pop esi
pop ebx
ret
]]

-- getBuildingSizeForCommandBuildingType, replacing `mov eax,[esp+4] / add eax,SIZE_BASE`: in
-- the map editor a tower ruin's command counts as its tower's.
templates.ruinSize = [[
mov eax,[esp+4]
cmp dword [GAME_MODE],MAP_EDITOR
jne ruin_plain
cmp eax,FIRST_RUIN
jb ruin_plain
cmp eax,LAST_RUIN
ja ruin_plain
sub eax,TOWER_FROM_RUIN
ruin_plain:
add eax,SIZE_BASE
jmp BACK
]]

-- Called instead of destroyBuilding where a new keep or unique building removes the player's
-- earlier one: in the map editor the earlier one stays.
templates.keepEarlier = [[
cmp dword [GAME_MODE],MAP_EDITOR
je keep_it
jmp DESTROY
keep_it:
ret DESTROY_ARGUMENTS
]]

-- Called instead of hasBuildingAsNeighbour for a further storage building: in the map editor
-- it may stand anywhere.
templates.anyNeighbour = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne ask_game
mov eax,1
ret NEIGHBOUR_ARGUMENTS
ask_game:
jmp HAS_NEIGHBOUR
]]

-- The tower engine click with the mouse button let go, replacing `cmp esi,ebx / je REFUSE`
-- (esi: the building on the tile, eax: the tile, ebp/edi: its x/y): in the map editor lua
-- decides (RULE with the tile in TILE): 0 refuses, 2 leaves the player's own big towers to the
-- game's own tests (TOWER_PATH), 1 gives the spawn command for the clicked tile itself (spawnUnit
-- adds half a tile to the position, so the tile's corner, x * 8, is its middle).
templates.towerEngineGround = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne in_game
mov [TILE],eax
call RULE
cmp dword [ANSWER],2
je on_tower
cmp dword [ANSWER],0
je refuse
lea edx,[ebp*8]
mov [PARAM0],edx
lea edx,[edi*8]
mov [PARAM1],edx
movzx edx,byte [HEIGHTS+eax]
mov [PARAM2],edx
mov dword [PARAM3],UNIT_TYPE
push COMMAND
mov ecx,SYNC
call QUEUE
jmp EPILOGUE
in_game:
test esi,esi
je refuse
on_tower:
jmp TOWER_PATH
refuse:
jmp REFUSE
]]

-- ClickPlaceSiegeTent (the spawn command), replacing `cmp byte [eax+HAS_ENGINE],0 / jne BUSY`
-- (eax: the building on the target tile): the game refuses a building that already has a tower
-- engine; in the map editor the placement rule has already decided, so several may go on one.
templates.towerEngineBusy = [[
cmp dword [GAME_MODE],MAP_EDITOR
je free_building
cmp byte [eax+HAS_ENGINE],0
jne BUSY
free_building:
jmp BACK
]]

-- The tower engine preview with the mouse button up, replacing `cmp esi,ebx / je TRANSPARENT /
-- imul esi,esi,BUILDING_SIZE`: in the map editor the same lua rule as the click picks the
-- solid preview (OPAQUE), the see-through one, or the game's own tower tests.
templates.towerEnginePreview = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne in_game
mov [TILE],eax
call RULE
cmp dword [ANSWER],2
je game_test
cmp dword [ANSWER],0
je transparent
jmp OPAQUE
in_game:
cmp esi,ebx
je transparent
game_test:
imul esi,esi,BUILDING_SIZE
jmp BACK
transparent:
jmp TRANSPARENT
]]

-- placeTree's tile test, replacing `test dword [edi+ebp*4+LOGIC],MASK`: in the map editor with
-- the Vegetation on rocks and water box ticked, marsh, river, ford, rocky, boulder and pebble
-- tiles are left out of the test.
templates.treeGround = [[
cmp byte [FLAG],0
je strict
cmp dword [GAME_MODE],MAP_EDITOR
jne strict
test dword [edi+ebp*4+LOGIC],LOOSE_MASK
jmp BACK
strict:
test dword [edi+ebp*4+LOGIC],MASK
jmp BACK
]]

-- Action of a panel entry that is a way of placing a tool: remember the choice, then choose the
-- tool (ACTION with the entry's command).
templates.setChoice = [[
mov dword [FLAG],VALUE
jmp ACTION
]]


-- The right-click ring's compass, replacing `mov REG,[NEXT]` before setMapRotation(NEXT): with
-- Ctrl held the map turns the other way (2 * CURRENT - NEXT, orientations 0, 2, 4, 6).
templates.compassTurnEdx = [[
push eax
push ecx
push 0x11
call dword [IMPORT]
mov edx,[NEXT]
test ax,0x8000
je compass_kept
mov eax,[CURRENT]
add eax,eax
sub eax,edx
and eax,7
mov edx,eax
compass_kept:
pop ecx
pop eax
jmp BACK
]]

templates.compassTurnEax = [[
push ecx
push edx
push 0x11
call dword [IMPORT]
mov ecx,eax
mov eax,[NEXT]
test cx,0x8000
je compass_kept
mov edx,[CURRENT]
add edx,edx
sub edx,eax
and edx,7
mov eax,edx
compass_kept:
pop edx
pop ecx
jmp BACK
]]

-- PlaceUnit's spawnUnit(player, display player, ...) for a single unit, replacing `push eax /
-- push eax / mov ecx,UNITS` (eax: the current player): in the map editor the unit is drawn in the
-- colours of the chosen display player.
templates.unitColourEdi = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne colour_same
push dword [COLOUR]
jmp colour_owner
colour_same:
push edi
colour_owner:
push edi
mov ecx,UNITS
jmp BACK
]]

templates.unitColour = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne colour_same
push dword [COLOUR]
jmp colour_owner
colour_same:
push eax
colour_owner:
push eax
mov ecx,UNITS
jmp BACK
]]

-- After the map editor changes the map size (replacing `mov ecx,AFTER_THIS` after the size is
-- set and the cut-off area cleared): the viewport's tile map, its border tiles and the camera
-- bounds are worked out again, as loading a map does, so the cut-off tiles are off at once.
templates.sizeRefresh = [[
pushad
cmp dword [GAME_MODE],MAP_EDITOR
jne size_refresh_done
push dword [SIZE_WORD]
mov ecx,TILEMAP
call BORDERS
mov ecx,VIEWPORT
call BUILD
mov ecx,VIEWPORT
call TWEAK
mov ecx,VIEWPORT
call BOUNDS
call PAD
mov ecx,TILEMAP
call CHANGED
size_refresh_done:
popad
mov ecx,AFTER_THIS
jmp BACK
]]

-- setViewportBasedOnMapSize, replacing `cmp [ecx+0x78],edx / jge / mov [ecx+0x78],edx` (edx/edi:
-- the lowest and highest camera x, esi/ebx: y): in the map editor one tile more on every side.
templates.cameraEdge = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne edge_kept
sub edx,TILE_X
add edi,TILE_X
sub esi,TILE_Y
add ebx,TILE_Y
edge_kept:
cmp [ecx+0x78],edx
jge edge_low_ok
mov [ecx+0x78],edx
edge_low_ok:
jmp BACK
]]

-- TriggerPlaceBuilding's orientation read. An override belongs to the tool that supplied it.
templates.rotationRead = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne rotation_plain
cmp dword [WANTED],0xFFFFFFFF
je rotation_plain
mov eax,[TOOL]
cmp eax,[WANTED_TOOL]
jne rotation_plain
mov eax,[WANTED]
jmp BACK
rotation_plain:
mov eax,[ORIENTATION]
jmp BACK
]]

-- The cursor's orientation reset, between the comparison and the branch using its flags.
templates.previewRotationReset = [[
pushfd
push eax
mov eax,ebx
cmp dword [GAME_MODE],MAP_EDITOR
jne preview_rotation_store
mov eax,[TOOL]
cmp eax,[WANTED_TOOL]
jne preview_rotation_plain
mov eax,[WANTED]
cmp eax,6
ja preview_rotation_plain
shr eax,1
jmp preview_rotation_store
preview_rotation_plain:
mov eax,ebx
preview_rotation_store:
mov [ROTATION],eax
pop eax
popfd
jmp BACK
]]

-- The validator and cursor renderer both read keep parts from row zero.
templates.keepPreviewTurn = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne preview_plain
cmp dword [ROTATION],0
je preview_plain
cmp dword [ROTATION],3
ja preview_plain
cmp word [esp+ARG_BYTES-4],0x3C
jb preview_plain
cmp word [esp+ARG_BYTES-4],0x3E
ja preview_plain
; The rejected preview can read raw row indices even for tiles outside the map.
if ARG_BYTES = 16
  cmp dword [ecx+0x554934],0
  je preview_turn
  push eax
  push edx
  movzx eax,word [esp+20]
  sub eax,0x3C
  shl eax,2
  add eax,[ROTATION]
  shl eax,4
  add eax,KEEP_BOUNDS
  mov edx,[esp+12]
  cmp edx,[eax]
  jl preview_outside
  cmp edx,[eax+4]
  jg preview_outside
  mov edx,[esp+16]
  cmp edx,[eax+8]
  jl preview_outside
  cmp edx,[eax+12]
  jg preview_outside
  pop edx
  pop eax
end if
preview_turn:
call preview_swap
repeat ARG_BYTES/4
  push dword [esp+ARG_BYTES]
end repeat
call PREVIEW
call preview_swap
ret ARG_BYTES
if ARG_BYTES = 16
preview_outside:
  pop edx
  pop eax
end if
preview_plain:
jmp PREVIEW
preview_swap:
pushad
mov ebx,[ROTATION]
xor ebp,ebp
preview_type:
; table A: 24 bytes a row
mov eax,ebp
shl eax,2
lea esi,[eax+eax*2]
shl esi,3
add esi,TABLE_A
lea edi,[ebx+ebx*2]
shl edi,3
add edi,esi
mov ecx,6
preview_a:
mov eax,[esi]
mov edx,[edi]
mov [esi],edx
mov [edi],eax
add esi,4
add edi,4
dec ecx
jnz preview_a
; tables B and C: 8 bytes a row
mov eax,ebp
shl eax,5
lea esi,[eax+TABLE_B]
lea edi,[esi+ebx*8]
mov ecx,2
preview_b:
mov eax,[esi]
mov edx,[edi]
mov [esi],edx
mov [edi],eax
add esi,4
add edi,4
dec ecx
jnz preview_b
mov eax,ebp
shl eax,5
lea esi,[eax+TABLE_C]
lea edi,[esi+ebx*8]
mov ecx,2
preview_c:
mov eax,[esi]
mov edx,[edi]
mov [esi],edx
mov [edi],eax
add esi,4
add edi,4
dec ecx
jnz preview_c
inc ebp
cmp ebp,KEEP_ROWS
jb preview_type
popad
ret
]]

-- Translate the native footprint iterator's offsets by the change in the part's origin.
templates.rotatedPreviewPart = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne part_plain
cmp dword [ROTATION],0
je part_plain
cmp dword [ROTATION],3
ja part_plain
push dword [esp+8]
push dword [esp+8]
call WALK
push eax
push edx
imul ecx,[ROTATION],ROW_SIZE
mov eax,[ecx+PART]
sub eax,[PART]
add eax,[esi+TILE_X]
mov edx,[ecx+PART+4]
sub edx,[PART+4]
add edx,[esi+TILE_Y]
mov ecx,Y_ORIGIN
add ecx,edx
cmp ecx,MAP_SIZE
jae part_skip
imul ecx,MAP_SIZE
add ecx,X_ORIGIN
add ecx,eax
mov [esi+TILE_X],eax
mov [esi+TILE_Y],edx
add eax,X_ORIGIN
cmp eax,MAP_SIZE
jae part_skip
cmp byte [VALID+ecx],0
jne part_done
part_skip:
mov dword [esp+8],SKIP
part_done:
pop edx
pop eax
ret 8
part_plain:
jmp WALK
]]

-- placeKeep's ground painter (thiscall, 6 arguments): in the map editor the ground stays as it is.
templates.keepGround = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne paint
ret 0x18
paint:
jmp PAINT
]]

-- editor, with one of the keep choices that leave that part out, go straight to the end.
templates.keepPart = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne keep_part
cmp dword [KEEP_MODE],FIRST_MODE
je keep_done
cmp dword [KEEP_MODE],SECOND_MODE
jne keep_part
keep_done:
jmp EPILOGUE
keep_part:
]]

-- placeWalls, after a tile is built or repaired (esi the tile, edi TileMapState), replacing
-- `push esi / mov ecx,edi / call clearMoat`: with the damaged choice on, the tile looks damaged.
templates.damagedWall = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne wall_done
cmp byte [FLAG],0
je wall_height
mov byte [esi+edi+DAMAGE],1
wall_height:
; a crenellation with a chosen height gets it again here: the game places a one-tile wall
; twice, and on the second pass Smarter Walls puts a "damaged" crenellation back at the
; height it remembers, after the crenellation height hook ran
cmp dword [CRENEL_HEIGHT],0
je wall_done
test dword [edi+esi*4+LOGIC],0x200
jz wall_done
push eax
push edx
mov eax,[CRENEL_HEIGHT]
mov dl,[esi+edi+BASE]
add dl,al
jnc wall_set
mov dl,0xFF
wall_set:
mov [esi+edi+LIVE],dl
pop edx
pop eax
wall_done:
push esi
mov ecx,edi
call CLEAR_MOAT
jmp BACK
]]

-- Action of a castle panel entry: a command in DIRECT is chosen straight away, any other goes
-- through the toolbar action as a menu button's would.
templates.directTool = [[
mov eax,[esp+4]
mov ecx,DIRECT
next_direct:
mov edx,[ecx]
test edx,edx
je through_toolbar
cmp edx,eax
je choose_direct
add ecx,4
jmp next_direct
choose_direct:
mov [SUBTYPE],eax
ret
through_toolbar:
jmp TOOLBAR
]]

-- An eraser brush taking a rock off a tile, replacing `add eax, -ROCK_BASE / push eax / call
-- removeRock` (eax: the tile's rock number, esi: TileMapState, [esp+0x20]: the tile): rock 0,
-- an invisible rock, only frees this tile.
templates.eraseInvisible = [[
sub eax,ROCK_BASE
jne real_rock
mov edx,[esp+0x20]
and dword [esi+edx*4+FLAGS],KEEP_FLAGS
mov word [esi+edx*2+NUMBERS],0
jmp BACK
real_rock:
push eax
call REMOVE_ROCK
jmp BACK
]]

-- An eraser brush taking a tree off a tile, replacing `push eax / call removeTree` (eax: the
-- tree the tile names, [esp+0x20]: the tile): every other tree in use on that tile goes too.
templates.eraseStack = [[
push eax
call REMOVE_TREE
push ebx
push esi
push edi
mov ebx,[esp+0x2C]
mov esi,FIRST_TREE
mov edi,1
next_tree:
cmp word [esi],0
je other_tile
cmp [esi+TILE_FROM_IN_USE],ebx
jne other_tile
push edi
mov ecx,LANDSCAPE
call REMOVE_TREE
other_tile:
add esi,TREE_SIZE
inc edi
cmp edi,TREE_SLOTS
jbe next_tree
pop edi
pop esi
pop ebx
jmp BACK
]]

-- RenderPlayerInfoOnHoverDisplayElement, map editor branch: `mov eax,[esp+0x10] / mov ecx,
-- [PLAYER]`, the text's x and player, with the x SHIFT further left.
templates.hoverTextLeft = [[
mov eax,[esp+0x10]
sub eax,SHIFT
mov ecx,[PLAYER]
jmp BACK
]]

-- setTerrain, map editor, replacing `cmp dword [ebp+0x18], 0x40000000 / je SKIP_LAND` (the land
-- types are first laid as land): river terrain skips that too, so foam and small waves (river
-- with decoration 0x10 / 0x20, which are also land type values) find their river.
templates.riverDecorations = [[
cmp dword [ebp+0x18],0x40000000
je SKIP_LAND
cmp dword [ebp+0x18],RIVER
je SKIP_LAND
jmp BACK
]]

-- setTerrain's tile test for a decoration, replacing `mov ecx,[eax+edx*4+FLAGS] / and ecx,
-- RIVER / jne TILE_OK` (eax: TileMapState, edx: the tile): a river tile as before, and for foam
-- laid as river also an ocean tile.
templates.foamOnSea = [[
mov ecx,[eax+edx*4+FLAGS]
test ecx,RIVER
jne tile_ok
cmp dword [ebp+0x18],RIVER
jne tile_refused
cmp dword [ebp+0x1C],FOAM
jne tile_refused
test ecx,SEA
jne tile_ok
tile_refused:
jmp BACK
tile_ok:
jmp TILE_OK
]]

-- getTileInSquareBrush's start (edi: PathFindingState, eax: y, ecx: the cursor tile), replacing
-- `cmp [esp+0x1F60],ebp / mov [esp+0x1C],eax / mov [esp+0xFBC],ecx` before its `jg`: the cursor
-- tile is marked as visited by this walk too, so the walk does not count it a second time (in
-- the map editor).
templates.brushStart = [[
mov [esp+0x1C],eax
mov [esp+0xFBC],ecx
cmp dword [GAME_MODE],MAP_EDITOR
jne brush_unmarked
mov edx,[edi+4]
mov [ecx*2+MARKS],dx
brush_unmarked:
cmp [esp+0x1F60],ebp
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Moat
---------------------------------------------------------------------------------------

-- The editor's moat click, replacing `xor ecx,ecx / cmp eax,0x2D / setne cl` (eax: the chosen
-- tool; the game adds 2 to ecx for the mode): remove stays 3, the moat tool gets 2 (dug), 0
-- (planned) or 4 (permanent) from the panel's choice in MOAT_MODE (0 dug, 1 planned, 2 permanent).
templates.moatClick = [[
mov ecx,1
cmp eax,MOAT_TOOL
jne moat_click_done
mov ecx,[MOAT_MODE]
cmp ecx,PLANNED
jne moat_click_done
mov ecx,-2
moat_click_done:
jmp BACK
]]

-- setTerrain's moat modes, replacing `cmp dword [ebp+0x1C],0 / jne NEXT` (ebp-0x20 TileMapState,
-- ebp+0xC the tile, ebp-0xC x, ebp+0x10 y). Mode PERMANENT: dug moat without a moat list entry.
-- Mode 3 with KEEP_GROUND: only a planned or dug tile changes - flags and moat entry go, a dug
-- tile gets ground height back; the decoration and the other flags stay.
templates.moatModes = [[
mov eax,[ebp+0x1C]
cmp eax,PERMANENT
je moat_permanent
cmp eax,3
jne moat_game
mov ecx,KEEP_GROUND
test ecx,ecx
je moat_game
mov ecx,[ebp-0x20]
mov edx,[ebp+0x0C]
mov eax,[ecx+edx*4+LOGIC]
test eax,MOAT_FLAGS
je DONE
test eax,DUG
je moat_unplan
mov byte [ecx+edx+HEIGHT],GROUND
moat_unplan:
and dword [ecx+edx*4+LOGIC],UNMOAT
jmp moat_entry
moat_permanent:
mov ecx,[ebp-0x20]
mov edx,[ebp+0x0C]
mov eax,[ecx+edx*4+LOGIC]
and eax,UNMOAT_PLAIN
or eax,DUG
mov [ecx+edx*4+LOGIC],eax
mov byte [ecx+edx+HEIGHT],0
mov byte [ecx+edx+DECORATION],0
moat_entry:
push dword [ebp+0x10]
push dword [ebp-0x0C]
mov ecx,[ebp-0x20]
call CLEAR_DATA
jmp DONE
moat_game:
test eax,eax
jne NEXT
jmp PLAN
]]

-- The moat branch's marsh test, replacing `and eax,0x20000000` (before `je <go on>`): in the map
-- editor marsh does not stop moat.
templates.moatMarsh = [[
and eax,0x20000000
je moat_marsh_done
cmp dword [GAME_MODE],MAP_EDITOR
jne moat_marsh_done
xor eax,eax
moat_marsh_done:
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Pipette
---------------------------------------------------------------------------------------

-- checkBuildingCanBePlacedHere, replacing `cmp eax,LIMIT / jge FAIL` (eax: the player's empty
-- storage buildings of the type): no limit in the map editor.
templates.storageLimit = [[
cmp dword [GAME_MODE],MAP_EDITOR
je limit_pass
cmp eax,LIMIT
jge FAIL
limit_pass:
jmp BACK
]]

-- rotateFearFactorBuildingVariations, replacing `mov eax,[SUBTYPE] / add eax,TURN_ADD`: a variant
-- chosen in its panel (or by the pipette) stays chosen.
templates.variantLock = [[
mov eax,[SUBTYPE]
cmp eax,[VARIANT_LOCK]
je TURN_END
add eax,TURN_ADD
jmp BACK
]]

-- Action of a variant panel button (param: its placement id): that variant, locked.
templates.variantChoice = [[
mov eax,[esp+4]
mov [VARIANT_LOCK],eax
jmp ACTION
]]

-- placeWorkshopOrHovel, replacing `mov cx,[ebx+COUNTER]` (the player's next hovel variant): in
-- the map editor the variant chosen in the panel (HOVEL_LOCK = variant + 1) instead.
templates.hovelVariant = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne hovel_own
mov ecx,[HOVEL_LOCK]
test ecx,ecx
je hovel_own
dec ecx
jmp BACK
hovel_own:
mov cx,[ebx+COUNTER]
jmp BACK
]]

-- The placement preview, replacing `mov edx,[ecx+COUNTER]`: the chosen variant too.
templates.hovelPreview = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne hovel_seen
mov edx,[HOVEL_LOCK]
test edx,edx
je hovel_seen
dec edx
jmp BACK
hovel_seen:
mov edx,[ecx+COUNTER]
jmp BACK
]]

-- ...and `mov eax,[ebx+COUNTER]` before it moves on to the next: not with a chosen variant.
templates.hovelAdvance = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne hovel_next
cmp dword [HOVEL_LOCK],0
jne SKIP
hovel_next:
mov eax,[ebx+COUNTER]
jmp BACK
]]

-- A button with its own pictures (like pictureButton), chosen while FLAG is set.
templates.flagPictureButton = [[
mov eax,NORMAL
cmp dword [FLAG],0
je flag_not_chosen
mov eax,CHOSEN
jmp flag_draw
flag_not_chosen:
cmp dword [HOVER],0
je flag_draw
mov eax,HOVERED
flag_draw:
push dword [PENCIL+PENCIL_TARGET]
mov dword [PENCIL+PENCIL_TARGET],0
push dword [ITEM_Y]
push dword [ITEM_X]
push eax
call BLIT
add esp,12
pop dword [PENCIL+PENCIL_TARGET]
ret
]]

-- Crenellations may stand free in the map editor: validateWallBuildPath's two answers of
-- isTileEnclosedByWalls count as yes there. The first replaces `test eax,eax / mov edx,ecx / jne`,
-- the second `test eax,eax / jne / pop ebx`.
templates.crenelFree1 = [[
test eax,eax
mov edx,ecx
jne free_yes
cmp dword [GAME_MODE],MAP_EDITOR
je free_yes
jmp REFUSE
free_yes:
jmp YES
]]

templates.crenelFree2 = [[
test eax,eax
jne free_yes
cmp dword [GAME_MODE],MAP_EDITOR
je free_yes
pop ebx
jmp REFUSE
free_yes:
jmp YES
]]

-- Where every crenellation height of placeWalls meets (esi the tile, edi the tile map): in the
-- map editor with a height chosen (HEIGHT, 0 = the game's own), the crenellation stands that
-- high above the ground, low (LOW) or high in the game's sense ([esp+0x34], the 0x10000 flag).
templates.crenelHeight = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne crenel_parity
mov eax,[HEIGHT]
test eax,eax
jz crenel_parity
mov dl,[esi+edi+BASE]
add dl,al
jnc crenel_set
mov dl,0xFF
crenel_set:
mov [esi+edi+LIVE],dl
mov eax,[LOW]
mov [esp+0x34],eax
crenel_parity:
mov eax,[esp+0x20]
and eax,1
jmp BACK
]]

-- Player 0's shield picture: only in the map editor (its click item is hidden elsewhere), in its
-- chosen look while player 0 is the current player.
templates.shieldZero = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne shield_off
mov word [CLICK+ITEM_HIDDEN],0
xor eax,eax
cmp dword [CURRENT],0
sete al
mov [CHOSEN],eax
jmp BUTTON
shield_off:
mov word [CLICK+ITEM_HIDDEN],1
ret
]]

-- Render function of a panel item: lua draws the panel while FLAG is set, else every panel
-- button is hidden.
templates.flagPanel = [[
cmp dword [FLAG],0
je flag_hide
jmp PAD
flag_hide:
mov ecx,PANEL_ITEMS
flag_hide_next:
mov eax,[ecx]
test eax,eax
je flag_hidden
mov word [eax+ITEM_HIDDEN],1
add ecx,4
jmp flag_hide_next
flag_hidden:
ret
]]

-- renderPreviewMapperWithBrush, replacing `mov edx,[esi+BRUSH]` (the brush size, after three
-- pushes: the tool is at [esp+0x18]): the tool in ONE_TILE (the pipette taking a tile, or placing
-- objects one at a time) shows one tile.
templates.pipettePreview = [[
mov edx,[esp+0x18]
cmp edx,[ONE_TILE]
jne preview_brush
mov edx,1
jmp BACK
preview_brush:
mov edx,[esi+BRUSH]
jmp BACK
]]

---------------------------------------------------------------------------------------
-- Undo and redo
---------------------------------------------------------------------------------------

-- GetAsyncKeyState (cdecl, the key).
templates.undoKeyState = [[
push dword [esp+4]
call dword [IMPORT]
ret
]]


-- Compares the map sections with their snapshot: SECTIONS lists { live, snapshot, size }, 0 at
-- the end. Every changed run (ended by GAP unchanged bytes) goes to OUT_BEGIN as { address,
-- length, old bytes, new bytes }. Returns the bytes written, or 0xFFFFFFFF if OUT_LIMIT is passed.
templates.undoDiff = [[
push ebx
push esi
push edi
push ebp
cld
mov dword [WRITE_AT],OUT_BEGIN
mov dword [ENTRY_AT],SECTIONS
next_section:
mov eax,[ENTRY_AT]
mov ebx,[eax]
test ebx,ebx
je diff_done
mov edx,[eax+4]
mov ebp,[eax+8]
add eax,12
mov [ENTRY_AT],eax
xor ecx,ecx
skip_dwords:
lea eax,[ecx+4]
cmp eax,ebp
ja skip_bytes
mov eax,[ebx+ecx]
cmp eax,[edx+ecx]
jne skip_bytes
add ecx,4
jmp skip_dwords
skip_bytes:
cmp ecx,ebp
jae next_section
mov al,[ebx+ecx]
cmp al,[edx+ecx]
jne run_found
inc ecx
jmp skip_bytes
run_found:
mov esi,ecx
mov edi,ecx
run_next:
inc ecx
cmp ecx,ebp
jae run_end
mov al,[ebx+ecx]
cmp al,[edx+ecx]
je run_same
mov edi,ecx
jmp run_next
run_same:
mov eax,ecx
sub eax,edi
cmp eax,GAP
jb run_next
run_end:
inc edi
sub edi,esi
mov eax,[WRITE_AT]
lea ecx,[eax+edi*2+8]
cmp ecx,OUT_LIMIT
ja diff_full
mov [RUN_FROM],esi
mov [RUN_LENGTH],edi
lea ecx,[ebx+esi]
mov [eax],ecx
mov [eax+4],edi
mov ecx,edi
add esi,edx
lea edi,[eax+8]
rep movsb
mov ecx,[RUN_LENGTH]
mov esi,[RUN_FROM]
add esi,ebx
rep movsb
mov [WRITE_AT],edi
mov ecx,[RUN_FROM]
add ecx,[RUN_LENGTH]
jmp skip_dwords
diff_done:
mov eax,[WRITE_AT]
sub eax,OUT_BEGIN
jmp diff_exit
diff_full:
mov eax,0xFFFFFFFF
diff_exit:
pop ebp
pop edi
pop esi
pop ebx
ret
]]

-- An instruction of queueCommand (ORIGINAL), after its three pushes: in the map editor lua
-- first, with the command (queueCommand's argument) in COMMAND.
templates.undoCommand = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne command_run
push eax
mov eax,[esp+0x14]
mov [COMMAND],eax
pop eax
pushad
pushfd
call PAD
popfd
popad
command_run:
ORIGINAL
jmp BACK
]]


-- prepareMap after loading a map, replacing `mov ecx, PATHFINDING`: lua forgets the history.
templates.undoForget = [[
pushad
pushfd
call PAD
popfd
popad
mov ecx,PATHFINDING
jmp BACK
]]

---------------------------------------------------------------------------------------
-- The height tools (features 28, 29)
---------------------------------------------------------------------------------------

-- Called with eax = a tile a height tool changes, edx = 1 when the tool is one that breaks rock
-- tiles unless Break rock tiles is off (raise, lower, hill, mountain, equalize), 0 for one that
-- never does (min and max height, the plateaus). Erase rock: takes the tile's rock away (the
-- game's removeRock). Whole rock: remembers the tile, its rock and its height before (the base
-- height, which the tools write last) for the lua that moves the rest of the rock. Answers eax =
-- 1 to keep the tile's rocky flag (the caller skips its `and`), 0 to clear it.
templates.rockCheck = [[
push ebx
push ecx
push edx
movsx ecx,word [ORGANISM+eax*2]
sub ecx,FIRST_ROCK_NUMBER
jl rock_none
mov ebx,[ROCK_MODE]
cmp ebx,MODE_ERASE
je rock_erase
cmp ebx,MODE_WHOLE
jne rock_kept
test ecx,ecx
je rock_kept
mov ebx,[RECORD_COUNT]
cmp ebx,RECORD_MOST
jae rock_kept
lea ebx,[RECORDS+ebx*8]
mov [ebx],eax
mov [ebx+4],cx
movzx ecx,byte [BASE_HEIGHT+eax]
mov [ebx+6],cl
inc dword [RECORD_COUNT]
rock_kept:
mov edx,[esp]
test edx,edx
je rock_keep
cmp dword [BREAK_ROCKS],0
jne rock_none
rock_keep:
mov eax,1
jmp rock_done
rock_erase:
test ecx,ecx
jne rock_remove
mov word [ORGANISM+eax*2],0
jmp rock_none
rock_remove:
pushad
push ecx
mov ecx,LANDSCAPE
call REMOVE_ROCK
popad
rock_none:
xor eax,eax
rock_done:
pop edx
pop ecx
pop ebx
ret
]]

-- raiseLand's `and dword [esi+eax*4+LOGIC],~0x80` (tile eax, TileMapState esi): only when
-- rockCheck says so.
templates.raiseRock = [[
push eax
push edx
mov edx,1
call ROCK_CHECK
pop edx
test eax,eax
pop eax
jne raise_rock_kept
and dword [esi+eax*4+LOGIC],0xFFFFFF7F
raise_rock_kept:
jmp BACK
]]

-- The same `and` in useLevelBrush and createPlateau (tile ebp, TileMapState edi).
templates.brushRock = [[
push eax
push edx
mov eax,ebp
mov edx,MAY_BREAK
call ROCK_CHECK
pop edx
test eax,eax
pop eax
jne brush_rock_kept
and dword [edi+ebp*4+LOGIC],0xFFFFFF7F
brush_rock_kept:
jmp BACK
]]

-- raiseLand's `mov bl,[esp+0x24] / add [eax+esi+HEIGHT],bl / mov byte [eax+esi+DECORATION],0`:
-- the amount added without wrapping past 0 or 255 (the game's limits follow), and the ground's
-- look reset only with Reset ground textures on.
templates.raiseAmount = [[
movzx ebx,byte [eax+esi+HEIGHT]
add ebx,[esp+0x24]
jns raise_above_zero
xor ebx,ebx
raise_above_zero:
cmp ebx,0xFF
jbe raise_in_byte
mov ebx,0xFF
raise_in_byte:
mov [eax+esi+HEIGHT],bl
cmp dword [RESET],0
je raise_ground_kept
mov byte [eax+esi+DECORATION],0
raise_ground_kept:
jmp BACK
]]

-- useLevelBrush's step up (eax = the height, bl the same byte, esi the middle height): the
-- difference / DIVISOR + 1, at most the difference; the result in cl, as the game has it.
templates.levelRise = [[
mov ecx,esi
sub ecx,eax
mov eax,ecx
cdq
idiv dword [DIVISOR]
inc eax
cmp dword [INVERT],0
jne level_rise_invert
cmp eax,ecx
jbe level_rise_short
mov eax,ecx
level_rise_short:
mov cl,bl
add cl,al
jmp HEIGHT_STORE
level_rise_invert:
movzx ecx,bl
sub ecx,eax
jns level_rise_inverted
xor ecx,ecx
level_rise_inverted:
jmp HEIGHT_STORE
]]

-- ...and down (cl = the height, esi the middle height).
templates.levelFall = [[
movzx edx,cl
sub edx,esi
mov eax,edx
push edx
cdq
idiv dword [DIVISOR]
pop edx
inc eax
cmp dword [INVERT],0
jne level_fall_invert
cmp eax,edx
jbe level_fall_short
mov eax,edx
level_fall_short:
sub cl,al
jmp HEIGHT_STORE
level_fall_invert:
movzx ecx,cl
add ecx,eax
cmp ecx,0xFF
jbe level_fall_inverted
mov ecx,0xFF
level_fall_inverted:
jmp HEIGHT_STORE
]]

-- useLevelBrush's `mov byte [edi+ebp+DECORATION],0`: only with Reset ground textures on.
templates.levelGround = [[
cmp dword [RESET],0
je level_ground_kept
mov byte [edi+ebp+DECORATION],0
level_ground_kept:
jmp BACK
]]

-- createPlateau's `mov [edi+ebp+DECORATION],al` (the plateau look): only with Reset ground
-- textures on.
templates.plateauGround = [[
cmp dword [RESET],0
je plateau_ground_kept
mov [edi+ebp+DECORATION],al
plateau_ground_kept:
jmp BACK
]]

-- useTerrainHeightBrush's `test byte [edi+ebp*4+LOGIC],0x80 / je` before the rock's removal:
-- the ground's look reset with Reset ground textures on, then rockCheck (which also erases the
-- rock in Erase rock), and the `and` only when it says so.
templates.minMaxRock = [[
cmp dword [RESET],0
je min_ground_kept
mov byte [edi+ebp+DECORATION],0
min_ground_kept:
push edx
mov eax,ebp
xor edx,edx
call ROCK_CHECK
pop edx
test eax,eax
jne AFTER_AND
jmp AND_SITE
]]

-- Render function of a panel shown while the chosen tool is one of COMMANDS (a list ending in
-- -1): calls PAD, or hides the panel's items.
templates.toolPanel = [[
mov eax,[SUBTYPE]
mov ecx,COMMANDS
tool_panel_next:
mov edx,[ecx]
cmp edx,-1
je tool_panel_hide
cmp eax,edx
je tool_panel_show
add ecx,4
jmp tool_panel_next
tool_panel_show:
jmp PAD
tool_panel_hide:
mov ecx,PANEL_ITEMS
tool_panel_hide_next:
mov eax,[ecx]
test eax,eax
je tool_panel_hidden
mov word [eax+ITEM_HIDDEN],1
add ecx,4
jmp tool_panel_hide_next
tool_panel_hidden:
ret
]]

-- Every-frame item: calls PAD while COUNT is not 0.
templates.whenCounted = [[
cmp dword [COUNT],0
je counted_none
jmp PAD
counted_none:
ret
]]

---------------------------------------------------------------------------------------
-- The texture mask
---------------------------------------------------------------------------------------

-- Called with eax = a tile a texture tool is about to paint, ecx = the tile the command was
-- clicked on, edx = 1 from setTerrain's tile loop, 0 from setLand's. BY_TYPE: water's variants
-- count as one (its look is not compared). With the mask on and a
-- Textures menu tool chosen (TOOLS, ending in -1), the first command of a stroke takes the
-- clicked tile's texture (ground flags and look) as the reference; after that only tiles with
-- that texture are painted. setLand runs first for the ground looks when called from setTerrain
-- (NESTED): the tiles it lets through are marked in STAMPS, as setTerrain then finds them changed.
-- Answers eax = 1 to paint the tile, 0 to leave it. Keeps every register but eax and edx.
templates.maskCheck = [[
push ebx
push esi
mov ebx,edx
cmp byte [MASK_ON],0
je mask_paint
mov edx,[SUBTYPE]
mov esi,TOOLS
mask_tool:
cmp dword [esi],-1
je mask_paint
cmp [esi],edx
je mask_tool_found
add esi,4
jmp mask_tool
mask_tool_found:
cmp dword [REF_VALID],0
jne mask_compare
mov edx,[LOGIC+ecx*4]
call mask_kind
mov [REF_FLAGS],edx
movzx edx,byte [DECORATION+ecx]
mov [REF_DECORATION],edx
mov dword [REF_VALID],1
mask_compare:
test ebx,ebx
je mask_look
cmp byte [STAMPS+eax],0
je mask_look
mov byte [STAMPS+eax],0
jmp mask_paint
mask_look:
mov edx,[LOGIC+eax*4]
call mask_kind
cmp edx,[REF_FLAGS]
jne mask_skip
cmp dword [BY_TYPE],0
je mask_exact
test dword [REF_FLAGS],WATER_FLAGS
jnz mask_same
mask_exact:
movzx edx,byte [DECORATION+eax]
cmp edx,[REF_DECORATION]
jne mask_skip
mask_same:
test ebx,ebx
jne mask_paint
cmp dword [NESTED],0
je mask_paint
mov byte [STAMPS+eax],1
mask_paint:
mov eax,1
jmp mask_done
mask_skip:
xor eax,eax
mask_done:
pop esi
pop ebx
ret
; edx = a tile's flags -> its ground flags, which the mask compares together with the look (each
; texture is its own). With BY_TYPE a water tile's look is not compared, so every variant of sea,
; river or ford (edges, deeper water, foam, waves) counts as that water.
mask_kind:
and edx,TEXTURE_FLAGS
cmp dword [BY_TYPE],0
je mask_kind_done
test edx,WATER_FLAGS
jz mask_kind_done
and edx,NOT_EARTH
mask_kind_done:
ret
]]

-- A dust cloud's step (updateEntities), replacing `movsx ebp,dx / [test dx,dx] / cdq / jge GE`:
-- with a speed of 0 the step is skipped (SKIP) instead of dividing by it.
templates.dustStep = [[
movsx ebp,dx
cdq
test ebp,ebp
jz STEP_SKIP
jg STEP_POSITIVE
jmp STEP_NEGATIVE
]]

-- setTerrain's tile loop, replacing `mov ecx,[ebp+0xC] / mov edx,[ebp-0x20] / mov eax,[edx+ecx*4+
-- LOGIC]` (the tile, TileMapState, its flags): the next tile when the mask says no.
templates.maskTerrain = [[
mov eax,[ebp+0xC]
mov ecx,[ebp-0x1C]
mov edx,1
call MASK_CHECK
test eax,eax
je NEXT_TILE
mov ecx,[ebp+0xC]
mov edx,[ebp-0x20]
mov eax,[edx+ecx*4+LOGIC]
jmp BACK
]]

-- setLand's tile loop, replacing `mov esi,[esp+0x18] / mov eax,[edi+esi*4+LOGIC]` (the tile and
-- its flags; ebx is the clicked tile).
templates.maskLand = [[
mov esi,[esp+0x18]
push ecx
push edx
mov eax,esi
mov ecx,ebx
xor edx,edx
call MASK_CHECK
pop edx
pop ecx
test eax,eax
je NEXT_TILE
mov eax,[edi+esi*4+LOGIC]
jmp BACK
]]

-- In place of setTerrain's `call setLand`: the same call, with NESTED set meanwhile.
templates.maskNested = [[
mov dword [NESTED],1
pop dword [RETURN]
call SET_LAND
mov dword [NESTED],0
push dword [RETURN]
ret
]]

-- Every frame: a stroke ends when the mouse button is up; the next click takes a new reference.
templates.maskRelease = [[
cmp dword [CLICK_HELD],0
jne mask_held
mov dword [REF_VALID],0
mask_held:
ret
]]

-- Inverted equalize up and down (above): away from the middle height, without wrapping.

-- useLevelBrush, replacing `jle <no step> / mov cl,[edi+ebp+HEIGHT]` (a tile not below the middle
-- height: at it, or above it). At it, inverted: a chance of 2 x strength % to go up and as much
-- to go down, by strength / 2 (at least 1); the strength is STRENGTH_SUM - [DIVISOR].
templates.levelEqual = [[
jle level_equal
mov cl,[edi+ebp+HEIGHT]
jmp FALL
level_equal:
cmp dword [INVERT],0
je NO_STEP
mov eax,[SEED]
imul eax,eax,RANDOM_MULTIPLIER
add eax,RANDOM_INCREMENT
mov [SEED],eax
shr eax,16
and eax,0x7FFF
xor edx,edx
mov ecx,100
div ecx
mov ebx,STRENGTH_SUM
sub ebx,[DIVISOR]
lea eax,[ebx+ebx]
cmp edx,eax
jb level_equal_up
add eax,eax
cmp edx,eax
jae NO_STEP
shr ebx,1
jnz level_equal_down_by
mov ebx,1
level_equal_down_by:
movzx eax,byte [edi+ebp+HEIGHT]
sub eax,ebx
jns level_equal_down
xor eax,eax
level_equal_down:
mov cl,al
jmp HEIGHT_STORE
level_equal_up:
shr ebx,1
jnz level_equal_up_by
mov ebx,1
level_equal_up_by:
movzx eax,byte [edi+ebp+HEIGHT]
add eax,ebx
cmp eax,0xFF
jbe level_equal_raised
mov eax,0xFF
level_equal_raised:
mov cl,al
jmp HEIGHT_STORE
]]

-- useLevelBrush's limits `cmp [height],8 / jae / mov [height],8 / cmp [height],0x9C / jbe / mov
-- [height],0x9C`: the height range instead.
templates.levelRange = [[
movzx eax,byte [edi+ebp+HEIGHT]
cmp eax,[RANGE_MIN]
jae level_range_low
mov eax,[RANGE_MIN]
level_range_low:
cmp eax,[RANGE_MAX]
jbe level_range_high
mov eax,[RANGE_MAX]
level_range_high:
mov [edi+ebp+HEIGHT],al
jmp BACK
]]

-- useLevelBrush's first loop (the lowest and highest height under the brush), replacing `movzx
-- eax,byte [eax+edi+HEIGHT]` (eax the tile, ebp the clicked tile): tiles the height filter leaves
-- alone do not count.
templates.levelAverage = [[
push ecx
push edx
push eax
mov ecx,ebp
call HEIGHT_FILTER
test eax,eax
pop eax
pop edx
pop ecx
je AVERAGE_NEXT
movzx eax,byte [eax+edi+HEIGHT]
jmp BACK
]]

-- raiseLand's limits for ordinary ground, `mov ecx,8 / lea edx,[ecx+0x78]` (lowest, highest): the
-- height range for the raise and lower tools (hill and mountain keep the game's).
templates.raiseRange = [[
mov ecx,GAME_LOWEST
mov edx,GAME_HIGHEST
push eax
mov eax,[SUBTYPE]
cmp eax,RAISE_TOOL
je raise_range
cmp eax,LOWER_TOOL
jne raise_range_done
raise_range:
mov ecx,[RANGE_MIN]
mov edx,[RANGE_MAX]
raise_range_done:
pop eax
jmp BACK
]]

-- The height tools' filter, before the mask: eax = the tile, ecx = the clicked tile. Ignore water
-- (WATER_FLAGS), ignore farmland (FARMLAND looks, not on river), and for raise, lower and
-- equalize the height range when the tool does not snap to it (equalize inverted never does).
-- Then maskCheck. Answers eax = 1 to change the tile, 0 to leave it.
templates.heightFilter = [[
push ebx
push edx
mov ebx,[LOGIC+eax*4]
cmp dword [IGNORE_WATER],0
je filter_land
test ebx,WATER_FLAGS
jne filter_skip
filter_land:
cmp dword [IGNORE_FARMLAND],0
je filter_range
test ebx,RIVER
jne filter_range
test byte [DECORATION+eax],FARMLAND
jne filter_skip
filter_range:
mov edx,[SUBTYPE]
cmp edx,RAISE_TOOL
je filter_ranged
cmp edx,LOWER_TOOL
je filter_ranged
cmp edx,EQUALIZE_TOOL
jne filter_mask
cmp dword [INVERT],0
jne filter_check_range
filter_ranged:
cmp dword [SNAP],0
jne filter_mask
filter_check_range:
movzx edx,byte [BASE_HEIGHT+eax]
cmp edx,[RANGE_MIN]
jb filter_skip
cmp edx,[RANGE_MAX]
ja filter_skip
filter_mask:
pop edx
pop ebx
mov edx,1
jmp MASK_CHECK
filter_skip:
pop edx
pop ebx
xor eax,eax
ret
]]

-- For a filter without the mask.
templates.alwaysYes = [[
mov eax,1
ret
]]

-- After the map is drawn (called from the map drawing's patch site, editor/frame.lua), every
-- frame on the game screen: in the map editor the tree preview while a plant tool is chosen
-- (PLANTS: a byte per tool); outside it the height tool settings go back to their defaults.
templates.frameHook = [[
pushad
cmp dword [GAME_MODE],MAP_EDITOR
je frame_editor
mov dword [RANGE_MIN],DEFAULT_MIN
mov dword [RANGE_MAX],DEFAULT_MAX
mov dword [SNAP],1
mov dword [INVERT],0
mov dword [IGNORE_WATER],0
mov dword [IGNORE_FARMLAND],0
jmp frame_done
frame_editor:
cmp dword [GROUP_ON],0
je frame_plants
xor edx,edx
mov esi,FIRST_GROUP
mov ecx,GROUP_SLOTS
frame_group:
cmp word [esi],0
je frame_group_next
inc edx
frame_group_next:
add esi,GROUP_SIZE
dec ecx
jnz frame_group
mov [GROUP_COUNT],edx
mov eax,GROUP_SLOTS
sub eax,edx
cmp eax,GROUP_MARGIN
jge frame_plants
call GROUP_PAD
frame_plants:
mov eax,[SUBTYPE]
cmp eax,PLANT_TOOLS
jae frame_done
cmp byte [PLANTS+eax],0
je frame_done
cmp dword [MENU_RENDER],RENDER_NONE
jne frame_done
call PAD
frame_done:
popad
ret
]]

-- Every-frame item of the heights menu: PAD while COUNT is not 0 (a whole rock to move) or the
-- equalize tool is chosen (its invert key).
templates.heightTick = [[
cmp dword [COUNT],0
jne height_tick_go
cmp dword [SUBTYPE],EQUALIZE_TOOL
je height_tick_go
ret
height_tick_go:
jmp PAD
]]

-- The mask in the other nature tools: each replaces the instructions that load a tile and its
-- flags at the start of a per-tile step, asks maskCheck (eax = the tile, ecx = the tile the
-- command was clicked on) and goes to the tool's next tile when it says no.
-- raiseLand (raise, lower, hill, mountain): `mov eax,[esp+0x18] / mov ecx,[esi+eax*4+LOGIC]`,
-- the clicked tile in ebp.
templates.raiseMask = [[
mov eax,[esp+0x18]
push ecx
mov ecx,ebp
mov edx,1
call MASK_CHECK
pop ecx
test eax,eax
je NEXT_TILE
mov eax,[esp+0x18]
mov ecx,[esi+eax*4+LOGIC]
jmp BACK
]]

-- useLevelBrush (equalize): `mov ebp,[esp+TILE_AT] / mov eax,[edi+ebp*4+LOGIC]`, the clicked
-- tile at [esp+CLICKED_AT].
templates.levelMask = [[
mov eax,[esp+TILE_AT]
mov ecx,[esp+CLICKED_AT]
mov edx,1
call MASK_CHECK
test eax,eax
je NEXT_TILE
mov ebp,[esp+TILE_AT]
mov eax,[edi+ebp*4+LOGIC]
jmp BACK
]]

-- useTerrainHeightBrush (min, max) and createPlateau: the same, the clicked tile in ebx.
templates.brushMask = [[
mov eax,[esp+TILE_AT]
mov ecx,ebx
mov edx,1
call MASK_CHECK
test eax,eax
je NEXT_TILE
mov ebp,[esp+TILE_AT]
mov eax,[edi+ebp*4+LOGIC]
jmp BACK
]]

-- placeTree, replacing `test dword [edi+ebp*4+LOGIC],TEST_MASK` (the tree's tile ebp; the jne
-- after it, past two movs, leaves): leaves when the mask says no.
templates.treeMask = [[
push eax
push ecx
push edx
mov eax,ebp
mov ecx,ebp
mov edx,1
call MASK_CHECK
test eax,eax
pop edx
pop ecx
pop eax
je TREE_LEAVE
cmp byte [FLAG],0
je strict_test
cmp dword [GAME_MODE],MAP_EDITOR
jne strict_test
test dword [edi+ebp*4+LOGIC],LOOSE_MASK
jmp BACK
strict_test:
test dword [edi+ebp*4+LOGIC],TEST_MASK
jmp BACK
]]

-- placeRock's start `push ecx / mov eax,[esp+8]` (x, y on the stack): returns at once when the
-- mask says no for the rock's tile.
templates.rockMask = [[
mov eax,[esp+4]
mov edx,[esp+8]
cmp eax,MAP_SIZE
jae rock_mask_go
cmp edx,MAP_SIZE
jae rock_mask_go
push ecx
imul edx,edx,MAP_SIZE
cmp byte [VALID+edx+eax],0
je rock_mask_go_pop
mov edx,[esp+12]
lea edx,[edx+edx*2]
add eax,[ROWS+edx*4]
mov ecx,eax
mov edx,1
call MASK_CHECK
pop ecx
test eax,eax
jne rock_mask_go
ret 0xC
rock_mask_go_pop:
pop ecx
rock_mask_go:
push ecx
mov eax,[esp+8]
jmp BACK
]]

-- The eraser's choice of what it takes (37.2). Its first loop, replacing `movsx eax, word
-- [esi + reg*2 + organisms]` (ORIG_LO/HI, put back as it was): a tile's tree or rock is left
-- (eax 0, so the game's `test eax,eax / je` skips it) unless the choice takes it; with Animals a
-- tree loses its crows and stays.
templates.eraseOrganism = [[
dd ORIG_LO
dd ORIG_HI
test eax,eax
je organism_back
cmp dword [MODE],MODE_ALL
je organism_back
cmp eax,ROCK_FIRST
jl organism_tree
cmp dword [MODE],MODE_ROCKS
je organism_back
xor eax,eax
jmp organism_back
organism_tree:
cmp dword [MODE],MODE_PLANTS
je organism_back
cmp dword [MODE],MODE_ANIMALS
jne organism_none
push edx
mov edx,eax
imul edx,edx,TREE_SIZE
mov word [edx+CROW_BASE],0
mov word [edx+CROW_BASE+2],0
pop edx
organism_none:
xor eax,eax
organism_back:
jmp BACK
]]

-- Its second loop, in place of `call findBuildingOrWallAt` (thiscall, 3 arguments): unless the
-- choice takes buildings, the answer is "nothing there" (the fields the call fills).
templates.eraseBuilding = [[
cmp dword [MODE],MODE_ALL
je building_find
cmp dword [MODE],MODE_BUILDINGS
je building_find
mov dword [ecx+WALL_FOUND],0
mov dword [ecx+BLOCKED],0
mov dword [ecx+BUILDING_FOUND],-1
ret 0xC
building_find:
jmp FIND
]]

-- Its third loop, replacing `mov word [eax + state], 3` (eax: the unit's offset): animals (the
-- types ANIMALS marks) go with Animals, every other unit with Units.
templates.eraseUnit = [[
cmp dword [MODE],MODE_ALL
je unit_kill
push edx
movzx edx,word [eax+UNIT_TYPE]
cmp edx,ANIMAL_TYPES
jae unit_person
movzx edx,byte [ANIMALS+edx]
jmp unit_kind
unit_person:
xor edx,edx
unit_kind:
cmp dword [MODE],MODE_ANIMALS
jne unit_not_animal
test edx,edx
pop edx
jne unit_kill
jmp BACK
unit_not_animal:
cmp dword [MODE],MODE_UNITS
jne unit_leave
test edx,edx
pop edx
je unit_kill
jmp BACK
unit_leave:
pop edx
jmp BACK
unit_kill:
mov word [eax+STATE],3
jmp BACK
]]

-- Seagulls under the eraser (37.1), once per tile of its third loop, before `movsx eax, word
-- [reg*2 + units on tile]` (ORIG_LO/HI): every seagull whose entity stands on the tile ([esp+0x20]
-- there) is deleted and its slot cleared. Only with All and Animals.
templates.eraseGulls = [[
pushad
cmp dword [MODE],MODE_ALL
je gull_go
cmp dword [MODE],MODE_ANIMALS
jne gull_done
gull_go:
mov ebx,[esp+0x40]
mov esi,FIRST_GULL
mov edi,1
gull_next:
cmp word [esi+GULL_STATE],0
je gull_skip
movsx eax,word [esi]
test eax,eax
jle gull_skip
cmp eax,ENTITY_SLOTS
jge gull_skip
imul eax,eax,ENTITY_SIZE
add eax,ENTITY_ZERO
mov ecx,[esi+GULL_UID]
cmp ecx,[eax+ENTITY_UID]
jne gull_skip
cmp [eax+ENTITY_TILE],ebx
jne gull_skip
movsx eax,word [esi]
push eax
mov ecx,ENTITY_STATE
call DELETE_ENTITY
push edi
mov edi,esi
mov ecx,GULL_SIZE/4
xor eax,eax
cld
rep stosd
pop edi
gull_skip:
add esi,GULL_SIZE
inc edi
cmp edi,GULL_SLOTS
jl gull_next
gull_done:
popad
dd ORIG_LO
dd ORIG_HI
jmp BACK
]]

-- The map list filter (mapNames_filterMapsIfMapLock), replacing `cmp dword [lock], 0 / jne
-- DROP`: with Show locked maps ticked every map stays in the list.
templates.lockedMaps = [[
cmp dword [SHOW],0
jne locked_keep
cmp dword [LOCK_STATE],0
jne locked_drop
locked_keep:
jmp KEEP
locked_drop:
jmp DROP
]]

-- A cdecl map size change: the Map settings menu's own size code (its size buttons' case) run
-- with a size of the caller's choice, as if no size button but a custom value were clicked.
templates.mapSize = [[
push esi
xor esi,esi
jmp SIZE_CODE
]]

return templates

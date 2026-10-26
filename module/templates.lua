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
je guard_done
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
jmp guard_done
skip_guarded:
add esi,8
jmp next_guarded
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

-- The random rock button's `mov [mode], ecx` (ecx = 5): mode 0 instead, the slowly turning
-- mode the preview follows.
templates.randomRockMode = [[
mov dword [MODE],0
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

-- placeTree, `xor ebx,ebx / test eax,eax / mov [esp+0x10],esi / jle <past the check>`:
-- with the flag set, the check of the tiles around a new tree is skipped, as for a tree
-- type that needs no room.
templates.nearObstacles = [[
xor ebx,ebx
mov [esp+0x10],esi
cmp byte [FLAG],0
jne skip_check
test eax,eax
jle skip_check
jmp CHECK
skip_check:
jmp PAST_CHECK
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
-- that one. The command is on the stack as at the felled tree site (createTree cleans up its
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
-- (esi: the building on the tile, eax: the tile, ebp/edi: its x/y): in the map editor any tile
-- but the player's own big towers gets the spawn command straight away, if no unit stands
-- there; the towers go on to the game's own tests (TOWER_PATH).
templates.towerEngineGround = [[
cmp dword [GAME_MODE],MAP_EDITOR
jne in_game
test esi,esi
je on_ground
imul ecx,esi,BUILDING_SIZE
movsx edx,word [ecx+OWNERS]
cmp edx,[CURRENT_PLAYER]
jne on_ground
movzx edx,word [ecx+TYPES]
cmp edx,TOWER_4
je on_tower
cmp edx,TOWER_5
je on_tower
on_ground:
cmp word [UNIT_TILES+eax*2],0
jne refuse
lea edx,[ebp*8+4]
mov [PARAM0],edx
lea edx,[edi*8+4]
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

return templates

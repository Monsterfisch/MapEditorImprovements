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

-- Render function for the tooltip item: hand over to lua while the mouse is on a category
-- button.
templates.tooltip = [[
cmp byte [SHOWN],0
je quiet
cmp word [ANIMALS_HOVER],0
jne show
cmp word [VEGETATION_HOVER],0
jne show
cmp word [ROCKS_HOVER],0
je quiet
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

-- Render function of the panel item at the end of the Vegetation tab: the shrub panel while
-- one of its shrubs is chosen, the felled tree panel while a tree is chosen (lua draws them),
-- else every panel button hidden. A felled tree choice ends when another tool is chosen.
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

-- LandscapeState::mapUITreeTypeToLogicalTreeType, start: the apple tree command gives the
-- apple tree type, every other command goes on as before (the replayed first two
-- instructions: mov eax,[esp+4] / add eax,-0x28).
templates.appleType = [[
mov eax,[esp+4]
cmp eax,APPLE_COMMAND
jne not_apple
mov eax,APPLE_TYPE
ret 4
not_apple:
add eax,-0x28
jmp CONVERTER_BACK
]]

-- placeTree, `push 3 / push 0 / movzx eax,ax`: the growth stage handed to createTree is the
-- brush size minus one (0 .. 6) instead of 3.
templates.stageFromBrush = [[
push eax
mov eax,[BRUSH]
dec eax
jns stage_low_ok
xor eax,eax
stage_low_ok:
cmp eax,MAX_STAGE
jle stage_high_ok
mov eax,MAX_STAGE
stage_high_ok:
mov [STAGE],eax
pop eax
push dword [STAGE]
push 0
movzx eax,ax
jmp BACK
]]

-- placeTree, right after createTree (`mov esi,eax / imul esi,esi,0x9C`; eax, the new tree,
-- is used again further down): with a felled tree chosen for this tree tool, the new tree is
-- laid down the way the woodcutter's log taking leaves it (lying, no chops left, that many
-- logs, at most what a tree of its type and stage gives), and its picture worked out again
-- by its update function, called as createTree calls it.
templates.felledTree = [[
mov esi,eax
test eax,eax
je plain
cmp dword [FELLED_LOGS],0
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

return templates

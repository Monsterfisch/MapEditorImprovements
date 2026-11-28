# Map Editor Improvements

A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme. It makes the map editor
show more about the map you are working on: how many animals, units, trees and rocks it has,
right on the landscape editor's buttons, with a red "i" button to hide or show the numbers. It
also keeps the editor's menu up to date while the mouse is on the map, and adds tools: tree
growth stages, apple trees, more shrubs, felled trees, random mixes, gravel and iron, rock
variants, herd sizes. And it draws the grid the AI reads when it looks for places for its
resource buildings - 5 x 5 blocks of tiles - over the terrain, with the four lines where a keep's
rotation changes and the tiles an iron mine would cover in each block; **Alt + G** switches it on
and off. That resource grid was the separate Resource Grid Overlay module until 1.0.65; its
settings are not taken over, and while Resource Grid Overlay is turned on this module leaves the
grid to it.

What the module does, in plain English, is in `module/locale/description-en.md`.

## What is in here

| Folder | |
|---|---|
| `module/` | the module itself - this is the source of truth, edited in place |
| `docs/` | notes on how parts of the game work: the size 4 rock (`size-4-rocks.md`), the river decorations (`river-decorations.md`) and the ruined cathedral (`ruined-cathedral.md`) |
| `tools/publish.py` | copies `module/` into a game's `ucp/modules` folder as `map-editor-improvements-<version>`. Options: `--bump` (raise the version first), `--keep` (remove no older copies), `--game "<game folder>"` (where to publish). The comment at the top of the script explains each, and how the game folder is remembered in `tools/publish-config.json` (created by the script, not committed) |
| `tools/make_icons.py` | made `module/images/apple*.png` and `gravel*.png` once, from the game's own pictures. Only used while building the module, not needed to use or work on it |
| `tools/make_pipette_icons.py` | made the pipette button, `module/images/pipette*.png`, from the eraser button's parchment (reads the game's `gm/mapedit_buttons.gm1`). Only used while building the module |
| `tools/make_undo_icons.py` | made the undo and redo arrows, `module/images/undo*.png` and `redo*.png`. Only used while building the module |

## Development workflow

1. Edit under `module/`.
2. `python tools/publish.py --bump` - raises the last version slot (in `definition.yml`) and copies the module to `ucp/modules/map-editor-improvements-<version>` in the
   game folder. The first time, add `--game "<game folder>"` (the folder with `ucp-config.yml`);
   the script stores it in `tools/publish-config.json` and uses it from then on. Older copies
   are removed, except the newest one and any version the UCP config still uses (`--keep`
   removes none). Do this with the game closed.
3. In the UCP GUI press F5, then apply.
4. Commit and tag: `git commit -am "<version> - <what changed>" && git tag v<version>`.

## How to use

1. Put the module into the game: either run `python tools/publish.py --game "<game folder>"`,
   which copies the `module/` folder to `ucp/modules/map-editor-improvements-<version>`, or do
   it by hand: zip the *contents* of `module/` (so `definition.yml` is at the top of the zip)
   and name the zip `map-editor-improvements-<version>.zip`, with the version from
   `definition.yml`, then install it from the UCP3 GUI or drop it into `ucp/modules`.
2. In the UCP3 GUI's Content tab, add Map Editor Improvements to the active extensions and
   apply. Its entries under "Customisations" switch each feature on or off; by default
   everything is off (see Vanilla and Recommended below).
3. Start the game and open the map editor: the features are in the landscape editor's menus and
   the castle mode's building menu. [docs/features.md](docs/features.md) describes every feature.

## How it works

* **No code patches for the counts.** The landscape editor's menu items are a static table
  handed to `Menu::Menu` by a CRT initializer. A copy replaces it with two items added: the
  "i" button (the game's own red "i", image table index 197) and, at the end of the always
  shown part (before the first 0x64 tab marker), an invisible tooltip item. The push is
  pointed at the copy and the menu built again if it already was.
* **Numbers on buttons.** The deer, lion, rabbit, camel and plant buttons get a render
  function that runs the game's button renderer and then the game's own number drawing, in
  the style of the siege engines' ammunition count (font 0x11, white, centred at the bottom).
* **Counting.** Once a frame, before the buttons are drawn (from the description line's
  render), assembly walks the tree, rock and group slots the way the game's own free-slot
  searches do, whose code also gives the slot counts and sizes; trees are also counted by
  type. Which type each plant button places comes from the game's own command-to-type
  function. Animals use the per-tick counters their update functions add to; units use
  UnitsState's count and the limit the editor tests it against.
* **Tooltips.** The tooltip item's render checks the three category buttons' hover flags in
  assembly and only then calls lua, which checks the mouse with the game's own box test and
  draws the Save dialog name box's translucent rounded box and shadowed text above the panel,
  over the button, on the map surface like the description line (camera offset added). The
  map surface is drawn afresh every frame, so the tooltip leaves nothing behind.
* **The "i".** Above the panel the game draws on the map surface at the item position plus
  the camera offset (its description line does this); the "i" is drawn the same way, through
  the game's image button renderer. The description line moves right to make room.
* **Always up to date.** In the main loop, `cmp [GameCore.countdown], 0 / jne <full redraw>`
  is pointed at a stub that also takes the full redraw when GameMode2 is 1 (map editor). The
  countdown is not touched, so nothing else that reads it changes.
* **Growth stage.** placeTree's `push 3` (the stage it hands createTree) becomes brush - 1.
* **Apple tree.** Command 136 (routed through placeTree like the shrubs, normally an unused
  invisible shrub) is answered with type 15 by a hook on the command-to-type function.
* **Shrubs 5-9.** Commands 130-134 already exist; the panel buttons are copies of the shrub
  button with those commands. The five are one sprite in createTree's palettes 0, 3, 4, 7, 8.
* **Felled trees.** Right after placeTree's createTree call, a chosen log count lays the new
  tree down as the woodcutter leaves it (lying = 2, logs, no chops) and its update function
  picks the picture. The panel shows the game's own sprites (renderGM on the map surface
  with the tree palette), placed by bounding boxes read from the loaded picture data.
* **Above the panel.** A new first item tells the game's map click handler the mouse is not
  on the map while it is on one of the module's buttons there.
* **Textures.** Gravel (command 13) and a copy of the Heights menu's Iron button join the
  rows; the rows are spread evenly once the pictures are loaded, and taken off the user
  control table so the menu loader does not put them back.
* **Rocks.** The Rocks button's `jl` past `mov eax, 239` becomes a `jmp` (signpost tab on
  skirmish maps); the random rotation button stores mode 0 instead of 5. The variant row draws
  the game's rock tile pictures through its own footprint function and the map's turn; the
  rock number at the click handler's placement and preview (`lea ecx,[variant + size*4]`)
  comes from a stub that uses the chosen variant, or 16 for the extra 1x1 rock (see
  `docs/size-4-rocks.md`).
* **Herds.** The four herd sites (`and eax, mask / mov edi, unit / add eax, base`) are read for
  the panel and replaced by stubs that give 2 x brush - 1 while its check box is on.
* **Trees next to obstacles.** placeTree's `jle` past the check of the tiles around a new tree
  is taken while the check box is on.
* **Random mixes.** The felled tree choice also holds 0x40 (random standing tree: the stage
  stub picks 0 .. the brush's) and 0x41 (random logs, in the felled tree stub); the random
  shrub makes the command-to-type hook pick one of commands 130-134. A small linear
  congruential generator gives the numbers.
* **Invisible rocks.** placeRock's call to createRock answers slot 0 while the check box is on,
  which is what the game does once its 4000 rocks are used up: the tiles get rock number 2000.
  The eraser takes a rock off by number - 2000, so for such a tile it would clear empty slot 0;
  both erase brushes now free the tile itself instead (rock flag 0x80 and the tile's number).
* **Moat.** In the editor the moat buttons (106/107) choose 0x2D/0x2C and the click sends
  ClickSetTerrain with terrain 0x40000000 and a mode (0 planned, 1 plan removed, 2 dug, 3
  removed). The panel's choice picks mode 0, 2 or the module's 4 (dug moat without a moat list
  entry, which units fill and the destroy tool delete through - so it stays). setTerrain's
  mode 3 normally sets every tile under the brush to height 8 and clears its decoration byte;
  the module's mode 3 only clears moat flags and the moat entry (height 8 for dug tiles).
  The branch's marsh test is skipped in the editor.
* **Pipette.** Its own tool id (0x1F4), which no click handler acts on and which the brush
  preview shows as the plain brush (a patch on the preview's brush read shows one tile while
  it takes a tile). An every-frame item in front of the map click handler watches the mouse.
  Heights are written like useTerrainHeightBrush does (base height, live height 8 lower on
  river), textures as the ground flags of the tile word plus the decoration byte (the tile's
  random word at +0x13DD40 is never copied - it picks the picture - but renewed when the ground
  changes); then, as the game's tools do, path links per tile, the logic and macro layer flags,
  updateWalkAndPathLayer and a minimap redraw. Cliff rocks are the rocky flag (0x80) that
  updateGfxLayer sets on steep edges in the editor without a rock: the pipette clears it (real
  rocks, organism layer >= 2000, only go with the any-tile key, through removeRock). The objects
  pipette reads the building (layer -> type -> convertBuildingTypeToCommandBuildingType) or the
  wall kind (flags, height above the ground) and then just chooses that tool between clicks.
  Trees and rocks come from the organism layer (tree slot, or rock slot + 2000) and are placed
  by calling placeTree / placeRock directly (a queued command would run after the module put
  the brush, felled logs and rock turn back); the tree's stage goes through the growth-from-brush
  hook (brush = stage + 1 for that one call), felled trees through the felled tree hook. Keys are polled with GetAsyncKeyState (the key
  dispatcher is resolution-based-zoom's), and not while a text box has the keyboard.
* **Undo and redo.** The map is the sections the game saves a map file with (its section
  table, 122 sections: 13.8 MB in Crusader, 25.2 MB in Extreme). The first map edit command
  (ids 0x12-0x1D and a few more, hooked in queueCommand past the bytes the protocol module
  searches for) after the mouse buttons were let go copies them all; the step ends at the next
  such command, or at a click on undo or redo, when an asm diff
  keeps only the changed runs, old and new bytes. Undo and redo write them back and then run
  prepareMap's own updates (path links, areas, climbing, waterfall foam, hovered state, the
  minimap). The two buttons are items of the landscape and the build menu that move themselves
  to the screen's top left every frame (an item's place is relative to its menu) and are drawn
  on the map surface; prepareMap's refresh after loading clears the history.
* **Max height.** The game still handles placement id 22 (the menu action sets the min/max word
  to 1, useTerrainHeightBrush sets 156); only the button is missing. A copy of the min height
  button gets command 22, the next image table entry (gm 108 picture 172, right after min
  height's) and user control 153 (UC_MAP_MAX), which the iron button took over.
* **Height tools.** Raise/lower (and hill/mountain, which call raiseLand once per tile of a
  spreading search, amount 1), equalize, min/max and the plateaus each clear the rocky flag
  (`and [logic],~0x80`) of every tile they change; updateGfxLayer only draws a tile as rock with
  that flag, so a rock's touched tiles vanish and become walkable while the rock stays. Each of
  those `and`s now asks one routine (rockCheck) first: keep the flag on a rock tile (unless
  Break rock tiles is on, for the tools that broke rocks), erase the rock (Erase rock, removeRock),
  or remember the tile and its height before (Whole rock: the base height, which the tools write
  last). An every-frame item then moves the rest of each remembered rock by the average change
  and runs the tools' own updates (path links, walk layer, minimap). The ground's look (the
  decoration byte) is only reset with Reset ground textures on; min height's `and 0xF3` goes.
  raiseLand's `add [height],amount` no longer wraps; the raise and lower amounts are the
  immediates of the click handler's `mov [command param],1/-1`, rewritten from the slider, and
  equalize's step `difference / 10 + 1` divides by 17 - strength instead.
* **Texture mask.** setTerrain's and setLand's tile loops ask maskCheck before each tile: with
  the button on (images/mask*.png from tools/make_mask_icons.py, at K.MASK_BUTTON) and a Textures menu tool chosen, the stroke's first command takes the clicked
  tile's ground flags (K.TEXTURE_FLAGS) and decoration byte, and only tiles with both the same
  are painted. setTerrain calls setLand first for the ground looks (a wrapper around that call
  sets a flag), and the tiles setLand lets through are marked in a byte per tile, since
  setTerrain then finds them changed. An every-frame item clears the reference while the map
  click is not held.
  The same check sits at the start of each tile in raiseLand (raise, lower, hill, mountain),
  useLevelBrush, useTerrainHeightBrush, createPlateau and placeTree, and at placeRock's start;
  the pipette checks every brush tile in lua (C.maskAllows) before it changes any. One button,
  in the always shown part of the landscape menu.
* **Height range, snap, invert, ignore boxes.** raiseLand's ordinary-ground limits (`mov ecx,8 /
  lea edx,[ecx+0x78]`) become the range for raise and lower; useLevelBrush's 8 / 0x9C limits become
  the range; its first loop (the lowest and highest height, whose middle the tiles move to) skips
  tiles the height filter leaves alone. The height filter (templates.heightFilter) runs at the
  start of every tile of the height tools: Ignore water (sea, river, ford, marsh, moat flags),
  Ignore farmland (scrub, thick scrub, oasis grass looks), and the range when not snapping, then
  the mask. Invert flips equalize's steps; at the middle height a random step (2 x strength %
  each way) replaces the game's `jle <no step>`. The settings reset outside the map editor from
  a detour after renderMap (the `mov ecx,[..]` after resource-grid-overlay's own detour), which
  also draws the tree preview, so it shows with the menu hidden too.
* **Variant pictures.** The castle panels' variant entries compose the building from its tiles
  (like the tunnel entrance) with its first picture (getSpriteID, or the hovel preview's table of
  variant pictures, or the ruin's 0x11F) and shrink it by whole steps (block averages).
* **Lost rocks.** A rock slot is in use when its word at +0x0C is not 0; the button collects the
  rock numbers (slot + 2000) of all 80400 tiles' organism words and zeroes every slot in use that
  no tile names (removeRock would also clear its footprint, which other plants now hold).
* **Birds.** Crows are no list: the crow tool (markNearbyTreesAsCrowTargets) sets a word of each
  grown tree near the click (in-use word + 0x50; + 0x52 says they flew off). Seagulls are entities
  (type 0x1D) with a slot in the entity state's seagull list (slots 1..99: +0 entity, +4 uid, +8 in
  use). Erase all seagulls calls the game's own unused deleteAllSeagulls; erase all crows clears the
  tree words and deletes crow entities (type 0x1C); erase all animals is Alt + E's call. The real
  unit limit is the "N more units" line's `mov ecx, 2499 / sub ecx, [units]` (9999 in Extreme).
  The herds and groups line is drawn from the map drawing's patch site (below), which counts the
  group slots.
* **Eraser choice.** useEraserBrush and eraseAreaWithBrush have the same three loops. The first's
  `movsx eax, [organisms]` answers 0 for a tree or rock the choice leaves (with Animals the tree's
  crow words are cleared); the second's building search answers "nothing" (it fills the found
  fields itself); the third's `mov word [unit + state], 3` only runs for animals (unit types 44-49,
  51, 62, 68, 69) or the others. Seagulls whose entity tile (+0x4C) is the tile go before the
  third loop's unit lookup.
* **Map settings.** Alt + , opens modal 0x1F (MenuItems_EditorMapTypeQuickChange). Its action
  still handles params 0-2 (lock state Editable / Playable / Mission), 3-6 (map types Siege,
  Invasion, Economic, Just Build) and the sizes 0x14-0x17; its renderer also still has King of
  the Hill (0xC, the flag the skirmish code reads). The module builds a new table with those, its
  own items (title, Custom, slider, Balanced, King of the Hill, Lock map, Back), widens the modal
  record and the constructor's pushes, and runs the size case with esi 0 for any size. The map
  menu (MapEditorProperties) and the Load dialog get one item each by copying whatever table the
  constructor pushes now (autosave extends the Load dialog first); locked maps stay in the list
  when mapNames_filterMapsIfMapLock's `cmp [lock], 0 / jne` is answered "keep".
* **Panels above the menu never overlap.** Every floating panel (the picture rows of both menus, the herd and height panels, the wall height slider) is placed by `module/editor/lane.lua`: at the lowest free spot over the menu, clear of the menu's own items above its top (measured like the module measures buttons), of the game's description line and the row above it, of the building counts, and of the panels the menu draws before it in the same frame (the pipette panel before a Vegetation panel, a wall panel before its slider). When nothing along that line is wide enough, the panel moves up. `cd bench && python test_layout.py` checks every panel kind on both executables' menus at screen widths from 800 to 2560, and walks through the tabs frame by frame: panels left up on another tab don't count, panels up at once never overlap and nothing moves between frames.
* **The map drawing's patch site.** After `renderMap`'s one call and the floater pass come two
  loads (`mov eax,[..]`, `mov ecx,[..]`). `module/editor/frame.lua` puts one jump in their place
  that calls the resource grid's routine and then the editor's own frame work (tree preview,
  herds and groups line, height tool reset outside the editor), does both loads and goes on.
  With the grid off only the second load is taken, so Resource Grid Overlay 1.1 can still take
  the first when it is installed on its own; with that module active, this one leaves the grid
  to it.
* **The resource grid.** `AIVState` holds one `HeatMap` record per 5 x 5 block, 80 x 80 of them,
  and every resource-building decision is a search over those blocks - so the block edges are
  what a mapper needs to see. `setKeepOffsetAndOrientation` builds the whole AIV turned by the
  quarter the keep sits in, which gives the four rotation boundaries; the AI puts an iron mine
  flat in the low corner of its block, which gives the footprint. One linear transform per map
  rotation, halved exactly when zoomed out, places the lines; they lie at the height the game
  levels the map to in its flattened view. The frame routine is assembly: with the grid off, a
  compare; with it on, it compares the values the picture depends on (rotation, zoom, camera,
  rendered area, pixel format) with the ones it last drew for and only calls into lua when one
  has changed. The pixels go into the map surface through the module's own Bresenham loop,
  which follows `PencilRenderCore::drawLine` rule for rule.
* **The module's keys in Custom Hotkeys.** With a Custom Hotkeys that offers `registerAction`
  (`module/editor/actions.lua`), these keys are actions there, in the category "Map Editor
  Improvements", which the player can rebind, clear or reset. Each suggests the key chosen in
  this module's options, at its US-layout position (on other layouts a letter may sit elsewhere);
  Custom Hotkeys leaves an action unbound when that key is already taken.

  | Action | Context | Suggested | Does |
  |---|---|---|---|
  | `ext.map-editor-improvements.grid-toggle` | map editor | Alt + the grid key (G) | shows or hides the grid |
  | `ext.map-editor-improvements.grid-toggle-game` | games, while the grid may show there | Alt + the grid key (G) | the same in games |
  | `ext.map-editor-improvements.pipette` | map editor (does nothing in the build menu) | the pipette key (P), if on | chooses the pipette, then its next kind |
  | `ext.map-editor-improvements.undo` / `.redo` | map editor | none (the buttons have no key) | a click on the undo or redo button |

  Without that API, or when it refuses the grid's editor action or the pipette action, the
  module's own key handling stays: the grid through the WM_SYSKEYDOWN arm of the window
  procedure (Alt + G sits on that table's do-nothing case in both executables), in the editor
  and in games; the pipette key through its key poll. The API registers the grid's two actions
  one at a time; should it take the editor one and refuse the game one, the grid toggles in the
  editor only, and the log says so.
  Custom Hotkeys also offers unassigned hold actions for sampling another tile, painting any
  tile and reversing Equalize. The module's configured keys still work. The game handles Alt + E
  for land animals and Alt + comma for opening and closing Map Settings.
  Leaving the map puts the grid away: `requestScreenChange` is redirected after
  the pending screen is stored, past every byte Resolution Based Zoom's pattern on that function
  reads.
* Every address is found by pattern scan or read out of the instruction that uses it, and
  checked against the bytes the module expects. Verified offline against both exes.

## Vanilla and Recommended

Every option of the module is off by default, so the module alone leaves the editor as the game
has it. Two plugins in this repository form the Map Editor Improvements family in the launcher:
`map-editor-improvements-recommended` (offered first) switches on the recommended settings,
`map-editor-improvements-vanilla` keeps everything off. Plugins that build on the module set the
options they need themselves.

## Credits

Map Editor Improvements is by Monsterfish (GitHub: Monsterfisch) and Heroesflorian. The resource
grid is Monsterfish's Resource Grid Overlay. Krarilotus proposed merging it into this module, and
Heroesflorian, co-author of this module, agreed. See `module/CREDITS.md`.

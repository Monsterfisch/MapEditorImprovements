# Map Editor Improvements

A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme. It makes the map editor
show more about the map you are working on: how many animals, units, trees and rocks it has,
right on the landscape editor's buttons, with a red "i" button to hide or show the numbers. It
also keeps the editor's menu up to date while the mouse is on the map, and adds tools: tree
growth stages, apple trees, more shrubs, felled trees, random mixes, gravel and iron, rock
variants, herd sizes.

What the module does, in plain English, is in `module/locale/description-en.md`.

## What is in here

| Folder | |
|---|---|
| `module/` | the module itself - this is the source of truth, edited in place |
| `docs/` | notes on how parts of the game work (`size-4-rocks.md`) |
| `tools/publish.py` | copies `module/` into a game's `ucp/modules` folder as `map-editor-improvements-<version>`. Options: `--bump` (raise the version first), `--keep` (remove no older copies), `--game "<game folder>"` (where to publish). The comment at the top of the script explains each, and how the game folder is remembered in `tools/publish-config.json` (created by the script, not committed) |
| `tools/make_icons.py` | made `module/images/apple*.png` and `gravel*.png` once, from the game's own pictures. Only used while building the module, not needed to use or work on it |

## Development workflow

1. Edit under `module/`.
2. `python tools/publish.py --bump` - raises the last version slot (in `definition.yml` and the
   description) and copies the module to `ucp/modules/map-editor-improvements-<version>` in the
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
   everything is on.
3. Start the game and open the map editor: the features are in the landscape editor's menus and
   the castle mode's building menu.

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
* Every address is found by pattern scan or read out of the instruction that uses it, and
  checked against the bytes the module expects. Verified offline against both exes.

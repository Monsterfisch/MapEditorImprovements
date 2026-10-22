# Map Editor Improvements

A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme. It makes the map editor
show more about the map you are working on: how many animals, units, trees and rocks it has,
right on the landscape editor's buttons, with a red "i" button to hide or show the numbers. It
also keeps the editor's menu up to date while the mouse is on the map.

What the module does, in plain English, is in `module/locale/description-en.md`.

## What is in here

| Folder | |
|---|---|
| `module/` | the module itself - this is the source of truth, edited in place |
| `tools/publish.py` | copies `module/` into the game's module folder under a new version |

## Working on it

1. Edit under `module/`.
2. `python tools/publish.py --bump` - raises the last version slot and copies the module to
   `ucp/modules/map-editor-improvements-<version>`. Do this with the game closed.
3. In the UCP GUI press F5, then apply.
4. Commit and tag: `git commit -am "<version> - <what changed>" && git tag v<version>`.

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
* Every address is found by pattern scan or read out of the instruction that uses it, and
  checked against the bytes the module expects. Verified offline against both exes.

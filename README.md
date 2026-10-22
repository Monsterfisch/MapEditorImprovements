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
  handed to `Menu::Menu` by a CRT initializer. A copy with the "i" button added (an image item,
  the game's own red "i", image table index 197) replaces it; the push is pointed at the copy
  and the menu built again if it already was.
* **Numbers.** The Animals, Rocks, deer, lion, rabbit and camel buttons get a render function
  that runs the game's button renderer and then the game's own number drawing, in the style of
  the siege engines' ammunition count (font 0x11, white, centred at the bottom). The counters
  are UnitsState's unit count, the rock id counter, and the per-tick counters the animals'
  update functions add to.
* **Vegetation.** The description line (item 9) gets a render function that adds
  `: <organism count>` behind the text while the menu's hovered item is the Vegetation button.
  It draws on the map layer like the line itself. The line moves right to make room for the "i".
* **Always up to date.** In the main loop, `cmp [GameCore.countdown], 0 / jne <full redraw>`
  is pointed at a stub that also takes the full redraw when GameMode2 is 1 (map editor). The
  countdown is not touched, so nothing else that reads it changes.
* Every address is found by pattern scan or read out of the instruction that uses it, and
  checked against the bytes the module expects. Verified offline against both exes.

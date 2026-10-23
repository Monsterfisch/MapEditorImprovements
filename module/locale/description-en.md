# Map Editor Improvements

**Author**: Monsterfish
**Version**: 1.0.7

Makes the map editor show more about the map you are working on and adds tools the editor
lacks: tree growth stages, apple trees, more shrubs, felled trees, gravel and iron. Every
part can be switched off in the settings.

## Map counts

In the landscape editor:

- **Tooltips on the category buttons.** Point at a button and a tooltip shows how many the
  map has against the game's limit:
  - **Animals:** animals and units (the editor stops placing more at the limit), and herds and
    troops - every herd you place and every group of troops takes one of these, and they have
    a limit of their own.
  - **Vegetation:** trees and shrubs. All plants share one limit of 1999.
  - **Rocks:** rocks.
- **Animals menu:** the deer, camel, rabbit and lion buttons each show how many of that
  animal are on the map.
- **Vegetation menu:** every tree and shrub button shows how many of that plant are on the
  map.

A red **"i"** button sits above the key button. Click it to hide all of this, click it again
to bring it back. The settings decide whether it starts shown or hidden. The button's
description line (the text that appears when you point at a button) moves a little to the
right to make room for it.

## Trees and shrubs

- **Growth stage from the brush size.** With a tree chosen, the brush size button sets how
  big the placed trees are:

  | Brush | Tree |
  |---|---|
  | 1 to 3 | young trees, smallest first |
  | 4 | fully grown (what the editor always placed) |
  | 5 | fully grown; woodcutters leave it alone until it turns back into a normal tree |
  | 6 | dead tree |
  | 7 | dead tree that disappears sooner |

  Shrubs always come out the same.
- **Apple tree button** in the Vegetation menu.
- **More shrubs.** While the shrub that comes in five colours is chosen, a row above the
  Vegetation menu offers all five colours.
- **Felled trees.** While a tree is chosen, a row above the Vegetation menu shows that tree
  felled, once for every number of logs it can still hold: 9 down to 1 for a fully grown
  tree, fewer for smaller ones, none for dead ones. Click one, and the trees you place lie
  felled with that many logs. Click it again to place standing trees again.

The row above the Vegetation menu sits over the map; clicking it does not place anything on
the map.

## Ground textures

The Textures menu gets **Gravel** at the end of the top row and **Iron** at the end of the
bottom row (the same iron as in the Heights menu, which keeps its button too). Both rows are
spread evenly over the panel to make room.

## Pictures

The apple tree and gravel buttons use the pictures in the module's `images` folder:
`apple.png`, `apple_hover.png`, `apple_selected.png` and `gravel.png`, `gravel_hover.png`,
`gravel_selected.png` (normal, mouse over it, chosen). Replace them with your own to change
the buttons.

## Always keep the menu up to date

The game only redraws the editor's menu while the mouse is over it. If something changes
while the mouse is on the map, for example a hotkey picks another tool or the counts change
as you place animals, the menu keeps showing the old state until you move the mouse back
onto it. With this setting the menu is redrawn all the time in the map editor. It does not
change anything outside the map editor.

## Good to know

- Works with Stronghold Crusader and Stronghold Crusader Extreme. The limits are read from
  the game, so Extreme shows its own (higher) unit limit.
- Trees, shrubs and rocks are counted by the places they take up in the game's lists, which
  is what the limits apply to. A stack of shrubs on one spot counts every shrub in it.
- Nothing is saved into the map.

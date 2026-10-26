# Map Editor Improvements

**Author**: Monsterfish
**Version**: 1.0.9

Makes the map editor show more about the map you are working on and adds tools the editor
lacks: tree growth stages, apple trees, more shrubs, felled trees, gravel and iron, rock
variants, herd sizes. Every part can be switched off in the settings.

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

- **Random mixes.** The rows above the Vegetation menu get buttons marked "?":
  - **Random tree**, first in the felled tree row: every tree you place gets a random growth
    stage from the smallest up to the brush's. Brush 1 (the smallest trees) and the dead
    trees have none.
  - **Random felled tree**, last in the felled tree row: felled trees with a random number of
    logs, from 1 up to what that tree can hold.
  - **Random shrub**, last in the shrub row: the five shrub colours mixed at random.

  Click it again, or choose another button, to stop mixing.
- **Trees next to obstacles.** A check box at the end of the top row. While it is ticked,
  trees and shrubs can be placed right next to buildings, rocks, walls and other trees.
  Point at it to see whether it is on.
- **Tidier rows.** The top row holds the trees (and the apple tree and the check box); the
  shrub that sat there moves to the bottom row, whose shrubs are sorted.

The row above the Vegetation menu sits over the map; clicking it does not place anything on
the map.

## Ground textures

The Textures menu gets **Gravel** at the end of the top row and **Iron** at the end of the
bottom row (the same iron as in the Heights menu, which keeps its button too). Both rows are
spread evenly over the panel to make room.

## Rocks

- **Signpost on skirmish maps.** Skirmish maps get the same Rocks menu as scenario maps, with
  the signpost button.
- **Random rotation in the preview.** With the random rotation button chosen, the rock turns
  once a second instead of every frame, so the preview under the mouse shows the rock you
  are about to place.
- **Variant row.** A row above the Rocks menu shows the four variants of the chosen rock
  size, turned the way they would be placed (it follows the random rotation too). Click one
  and every rock you place is that variant. Click it again, or any button of the Rocks menu,
  and the editor goes back to changing the variant after every rock.
- **Invisible rocks.** A check box to the right of the Rocks menu's buttons. While it is
  ticked, every rock you place is an invisible rock straight away (the "2k stones trick")
  instead of only after 4000 rocks: the tiles are taken, so nothing can be built there and
  nobody walks there, but no rock is drawn, so the tiles keep showing what was there before.
  Untick it to place normal rocks again. The invisible rocks are saved in the map like the
  ones the game makes after 4000 rocks.
- **Extra small rock.** For the smallest rocks the row offers a fifth variant: a small rock
  the game has but the editor never places. It is saved in the map like any other rock.

## Castle mode

In the building menu of the map editor's castle mode:

- **Building counts** above the minimap:
  - every building on the map against the game's limit. This includes keeps, landscape
    buildings and the parts some buildings are made of, which take up places in the list too;
  - the player buildings of all players together;
  - the player buildings of the current player.

  Player buildings are the ones an enemy can be sent to destroy.
- **Tower ruins.** While the Towers menu is open, a row above it offers the ruins of all five
  towers.
- **Tunnel entrance and siege tents.** In the army buildings menu, with the tunnelers' guild
  chosen, a row above the menu offers a tunnel entrance; with the engineers' guild chosen,
  the six siege tents.
- **Statue and shrines.** While the menu of good things is open, a row above it offers the
  unused 2x2 statue, 2x2 shrine and 1x1 shrine.
- **Barrier.** The Ruins menu gets a Barrier button in its free spot at the bottom right: a
  1x1 barrier that can be deleted again.

## Herds

While the deer, lion, rabbit or camel is chosen, a panel above the Animals menu shows how
big that animal's herds are (a fixed number plus a random number) and which troop type the
herd uses. Tick its check box and herds come out as big as the brush: 2 x brush size - 1
animals, so brush 1 places single animals and brush 7 herds of 13.

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

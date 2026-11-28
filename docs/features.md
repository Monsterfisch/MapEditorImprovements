# Map Editor Improvements: features

## Map counts

In the landscape editor:

- **Tooltips on the category buttons.** Point at a button and a tooltip shows how many the
  map has against the game's limit:
  - **Animals:** animals and units against the real limit (2499, 9999 in Extreme), herds and
    groups - every herd you place and every group of troops takes one of these, and they have
    a limit of their own (1249) - and birds: the crows (marks on trees, no limit of their own) and
    the seagulls (at most 99).
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

The Vegetation menu's trees are sorted by what they spread on: first the three that spread on
fertile ground (oasis grass, thick and thin scrub) with a thin green outline, then the one
that spreads on infertile ground (dirt, stony dirt, dunes) with a thin beige outline.

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
- **Apple tree button** in the Vegetation menu (named on the description line like the other
  plants: "Apple tree", in German "Apfelbaum").
- **More shrubs.** While the shrub that comes in five colours is chosen, a row above the
  Vegetation menu offers all five colours.
- **Felled trees.** While a tree is chosen, a row above the Vegetation menu shows that tree
  standing, then felled, once for every number of logs it can still hold: 9 down to 1 for a
  fully grown tree, fewer for smaller ones, none for dead ones (the smallest trees are felled
  with 1 log, as a tree of the next stage). Click one, and the trees you place lie felled with
  that many logs. Click it again, the standing tree or the tree in the menu to place standing
  trees again.

- **Random mixes.** The rows above the Vegetation menu get buttons marked "?":
  - **Random tree**, first in the felled tree row: every tree you place gets a random growth
    stage from the smallest up to the brush's. Brush 1 (the smallest trees) and the dead
    trees have none.
  - **Random felled tree**, last in the felled tree row: felled trees with a random number of
    logs, from 1 up to what that tree can hold.
  - **Random shrub**, last in the shrub row: the five shrub colours mixed at random.

  Click it again, or choose another button, to stop mixing.
- **Trees next to obstacles.** A check box at the end of the top row. While it is ticked,
  trees can be placed right next to buildings, rocks, walls and other trees (shrubs can stand
  there anyway).
  Point at it to see whether it is on.
- **Tidier rows.** The top row holds the trees (and the apple tree and the check box); the
  shrub that sat there moves to the bottom row, whose shrubs are sorted.

- **Tree preview.** While a tree or shrub is chosen, the tree it would plant is shown on the tile
  under the mouse, at the stage the brush gives it or felled with the chosen logs - also for the
  pipette, which shows the very tree it took. Not while zoomed out, and not where the tree
  cannot be planted; it also shows with the menu hidden (Tab).
- **No shrub stacks.** A tree or shrub can no longer be placed on a tile that already has
  one. Some shrubs used to pile up on one tile, invisible but each taking a place of the tree
  limit for good; the eraser now also clears every shrub piled up on a tile, so old stacks can
  be removed.

The row above the Vegetation menu sits over the map; clicking it does not place anything on
the map.

## Ground textures

The Textures menu gets **Gravel** at the end of the top row and **Iron** at the end of the
bottom row (the same iron as in the Heights menu, which keeps its button too). Both rows are
spread evenly over the panel to make room.

With the Textures menu's iron in place, the Heights menu's iron button goes (a setting).

**Mask.** A button (a square, half filled) at the top left of the landscape editor's menu. While it is
on, the nature tools (heights, textures, water, trees and shrubs, rocks and the pipette) only change tiles with the same texture as the tile you first click on, so you can paint
over one kind of ground without touching its neighbours. Let go of the mouse and the next click
picks a new texture to paint over.

## Water

The water menu gets back two river decorations from the first Stronghold's editor, which
Crusader still supports but has no buttons for:

- **Foam**: white water and rising spray, as below a waterfall, on every river tile under the
  brush. It can also go on ocean tiles, which then become river with foam (a setting).
- **Small waves**: on the one river tile under the mouse.

Both only go on river tiles and are saved in the map (see `docs/river-decorations.md` in the
module's repository).

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
- **Erasing invisible rocks.** The landscape eraser removes invisible rocks too: each tile it
  touches is freed and shows the ground again, the same as for a normal rock. No need to place
  and erase a shrub on every tile any more.
- **Extra small rock.** For the smallest rocks the row offers a fifth variant: a small rock
  the game has but the editor never places. It is saved in the map like any other rock.
- **Remove lost rocks.** A button at the bottom right of the Rocks menu. Rocks the raise or
  lower tool broke and whose tiles were then all covered by shrubs stay in the map's list of
  rocks without any tile: nothing can see, erase or reach them, and each uses up one of the
  4000 rock slots. The button takes every such rock off the list; its tooltip says how many.

## Heights

- **Max Height.** The first Stronghold's Max Height tool is back, right of Min Height: it sets
  the ground under the brush to height 156.
- **Height tool options.** While a height tool is chosen, a panel above the Heights menu has, in
  rows from the bottom:
  - **Reset ground textures** (off at first): whether the height tools also turn the ground
    back to its plain look (and the plateaus to dirt). Off, they only change the height.
  - **Break rock tiles** (off at first): whether raise, lower, equalize, hill and mountain break
    rocks the way the game does: the touched tiles turn invisible and walkable while the rock
    stays. Off, rocks stay whole.
  - **Ignore water** and **Ignore farmland** (off at first): the height tools leave sea, river,
    ford, marsh and moat tiles, or scrub, thick scrub and oasis grass tiles, untouched.
  - For raise, lower and equalize: **Snap to range** (on at first; off, tiles outside the range
    are left alone instead of brought into it), **Invert** (equalize only: it roughens the ground,
    and flat ground gets random bumps; hold Ctrl for the same, a setting), the **height range**
    (a slider with two ends, 8 to 156 at first, any of 0 to 255) and the **strength** (raise and
    lower by that much per step; equalize faster, 7 is the game's rate). Drag the sliders.
  - **Rock height changes** (a list; Whole rock at first): what the height tools do to a rock they
    touch. *Tile only* moves just the tiles under the brush, *Whole rock* moves all of the rock's
    tiles by the same amount, *Erase rock* removes the rock (what min height always did).
  The range, Snap to range, Invert and the ignore boxes go back to their defaults when you leave
  the map editor.
  Raise and lower no longer wrap round at the lowest and highest heights.

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
- **Statue and shrines.** The unused 2x2 statue, 2x2 shrine and 1x1 shrine: at the end of the
  statue's and the shrine's variants, or (with building variants off) in a row above the menu of
  good things.
- **Building variants.** While a garden (2x2, 3x3 or 4x4), statue, shrine or cesspit is chosen,
  a row above the menu offers each of its variants, each shown as it looks on the map. One chosen
  there stays chosen, instead of the
  game turning it into the next variant every second. The hovel gets the same row (and the ruined
  cathedral its own picture): a variant
  chosen there is placed every time instead of each player's next one. Choosing the building in
  the menu itself goes back to the game's cycling.
- **Several keeps.** Placing a keep no longer removes the player's earlier keep (or its
  campfire). The newest keep is the player's active one; the others stay on the map as
  buildings.
- **Several storage and recruitment buildings.** Barracks, mercenary posts, guilds and the
  other buildings a player normally has only one of are no longer removed when another one is
  placed, and further stockpiles, granaries and armouries can stand anywhere instead of having
  to touch the first one. Any number of them may also stand empty (the game allows only 8
  empty granaries or armouries and 32 empty stockpiles per player).
- **Tower mangonels and ballistae anywhere.** The tower mangonel and tower ballista of the army
  buildings menu can be put on any tile where no unit stands: the ground, walls, gates, any
  tower or the keep. On the player's own square and round towers they work as before.
- **Keep without campfire or stockpile.** While a keep is chosen, a row above the keeps menu
  offers it in two more ways: **Keep only** (the keep and its entrance) and **No stockpile**
  (keep, entrance and campfire area). The preview and the check for room cover only those
  parts. Choosing the keep in the menu places the whole keep again.
- **Damaged walls.** While the stairs, low wall, high wall or crenellated wall is chosen, a row
  above the castle buildings menu offers it **Damaged**: the walls you place get the top of a
  damaged wall and keep their height. Choosing the wall in the menu places normal walls again.
- **Ruined cathedral.** While the cathedral is chosen, a row above the town menu offers it
  **Ruined**: the cathedral you place gets the ruined picture that the game otherwise shows only
  in the mission "Kerak" when its cathedral is badly damaged. In a game it is still a whole,
  working cathedral that just looks ruined. Choosing the cathedral in the menu places normal ones
  again, and the pipette takes a ruined cathedral as ruined. This needs the game's own
  `gm/tile_churches.gm1`: older or replaced copies have no ruined cathedral in them, and then
  cathedrals are placed whole (the game's log says so).
- **Dug, planned and permanent moat.** While the moat is chosen in the gatehouses menu, a row
  above the menu offers it three ways: **Dug** (the editor's usual moat), **Planned** (moat
  marked out to be dug, as in a game) and **Permanent** (dug moat that nobody can fill in or
  delete in a game). Choosing the moat in the menu goes back to dug moat.
- **Moat on marsh.** Moat can be placed on marsh again; the marsh stays under it and comes
  back when the moat is filled in.
- **Removing moat keeps the ground.** "Remove moat" only changes tiles with dug or planned
  moat: the moat goes (dug moat gets the normal ground height back) and the ground's texture
  stays. Before, every tile under the brush became plain dirt.
- **Building names further left.** The name of the building under the mouse ("Player 1's
  Keep") moves 100 pixels to the left, clear of the building counts.
- **Barrier.** The Ruins menu gets a Barrier button in its free spot at the bottom right: a
  1x1 barrier that can be deleted again.

## Herds

While the deer, lion, rabbit or camel is chosen, a panel above the Animals menu shows how
big that animal's herds are (a fixed number plus a random number) and which group behaviour type the
herd uses. Tick its check box and herds come out as big as the brush: 2 x brush size - 1
animals, so brush 1 places single animals and brush 7 herds of 13.

Red wastebin buttons in the Animals menu: right of the crow button **Erase all crows** (the trees
stay), right of the seagull button **Erase all seagulls**, and on the right **Erase all
animals** (the same as Alt + E; birds stay).

When fewer than 200 herds and groups can still be made, a line at the top of the screen says how
many are left, like the game's own line for units.

## Eraser

The eraser also takes the seagulls over the tiles it erases. While it is chosen, a panel above the
menu picks what it takes:

- **All** - everything, as before.
- **Animals** - animals, crows (the trees stay) and seagulls.
- **Units** - every other unit.
- **Buildings** - buildings, keeps, ruins and walls.
- **Vegetation** - trees and shrubs.
- **Rocks** - rocks, invisible rocks too.

## Map settings

- **Show locked maps:** a box in the editor's Load dialog. Ticked, the list also shows locked
  maps (the game hides them).
- **Map Settings button** on the map's menu screen (where Save and Exit are), right of the
  Balanced / Unbalanced or Invasion / Economy buttons. It opens the menu Alt + , opens.
- **The Map Settings menu** is bigger: a title; Singleplayer and Multiplayer; under
  Singleplayer the map types Siege, Invasion, Economic and Just Build (castle builder); under
  Multiplayer the sizes 160, 200, 300, 400 and Custom, and a Map size slider from 10 to 400
  (the map takes the size when you let go of the mouse); Balanced and King of the Hill; Lock map;
  and Back (Esc and Alt + , still close it too). These were all still in the game: its menu code
  knew the map types, the lock states (Editable, Playable, Mission) and King of the Hill, only
  the buttons were gone. Lock map sets the "Mission" lock, which keeps the map in the skirmish
  list; a locked map no longer shows in the editor's Load dialog unless Show locked maps is
  ticked.

## Pictures

The apple tree and gravel buttons use the pictures in the module's `images` folder:
`apple.png`, `apple_hover.png`, `apple_selected.png` and `gravel.png`, `gravel_hover.png`,
`gravel_selected.png` (normal, mouse over it, chosen). Replace them with your own to change
the buttons.

## Brushes

The game's brushes count the tile under the mouse twice and leave out one tile, the top left
corner of the shape on screen - in the preview and when placing. With this setting every brush
has its whole shape.

## Undo and redo

Two arrow buttons in the top left corner of the map editor (in the landscape and the castle
menus): the left one takes back the last thing done on the map - placing or removing
buildings, trees, rocks and animals, painting textures and water, changing heights - and the
right one puts it back. A button is greyed out while there is nothing to take back or put
back. Up to the last 20 steps are kept. Every click is one step, and a brush stroke held down is
undone at once. Clicks that change nothing on the map, like a click with no tool chosen, make
no step, so they do not get in the way of a redo. Doing something new after an undo drops the steps that could have been redone, and loading another map starts the
history afresh.

## Pipette

A pipette button sits in the landscape editor's left column, above the brush size (brush size,
ruler and eraser move down a little for it). Choosing it shows a row above the menu - **Heights**,
**Textures**, **Objects**, **All** - and above that a line with what the pipette holds.

- **Taking:** click a tile. The pipette shows a single tile while it takes one.
- **Giving:** then click or drag: the tiles under the brush get the heights, the textures or
  both. Heights leave the ground's texture alone and textures leave the heights alone.
- **Objects:** click a building, wall, tree or rock to take it. Buildings and walls are then
  placed the way their own menu button does (with the same preview and checks), for the player
  they belonged to - the pipette chooses that player's shield; trees (same
  kind and growth stage, or felled with the same number of logs) and rocks (same kind and turn)
  the way the tree and rock tools place them - click, or drag for several - with the rock
  preview and the game's own placement checks. The brush, rock rotation and felled tree choice
  go back to what they were once the pipette lets go. A tree's stage follows the "growth stage
  from the brush size" setting; with it off, trees are placed at the game's usual stage.
- **All** also takes a tree or 1x1 rock on the tile and puts one on every tile under the brush
  where there is room.
- Heights are not given to sea, beach, marsh, moat, rocks, walls or buildings; textures not to
  rocks, walls or buildings. The cliff rocks the editor puts on steep edges are cleared (they
  come back wherever an edge stays steep). Holding **Alt** gives heights and textures to every
  tile anyway; rocks stay where they are (experimental).
- Choosing the pipette or one of its kinds again empties it. **P** chooses the pipette, and
  pressed again goes on to the next kind. Holding **Ctrl** takes a new tile while the pipette
  holds something; letting go gives again. All three keys can be changed or switched off.
- Undo takes pipette strokes back like any other change.

## Always keep the menu up to date

The game only redraws the editor's menu while the mouse is over it. If something changes
while the mouse is on the map, for example a hotkey picks another tool or the counts change
as you place animals, the menu keeps showing the old state until you move the mouse back
onto it. With this setting the menu is redrawn all the time in the map editor. It does not
change anything outside the map editor.

## Resource grid

Draws over the map the grid the AI uses when it looks for places for its quarries, iron mines,
pitch rigs and woodcutters: blocks of 5 x 5 tiles. A patch of stone inside one block is worth
more to the AI than the same patch spread over four. It also draws the four lines where the AI's
castle layout turns with the keep's position, and in every block the tiles an AI iron mine would
cover.

- **Alt + G** shows or hides it in the map editor. Another Alt + key can be chosen in the
  settings.
- With the recommended settings it only shows in the flattened view (space bar), where the
  lines lie exactly on the ground, and it is hidden in the V view.
- **Allow the overlay during games** lets you check the lines in a test game.
- The colours of the grid, the boundaries and the mine footprint can be changed.
- Nothing is saved into the map.

## Good to know

- Works with Stronghold Crusader and Stronghold Crusader Extreme. The limits are read from
  the game, so Extreme shows its own (higher) unit limit.
- Trees, shrubs and rocks are counted by the places they take up in the game's lists, which
  is what the limits apply to. A stack of shrubs on one spot counts every shrub in it.
- Nothing is saved into the map.

## Author settings

Set these URLs under `map-editor-improvements` in a preset or profile.

| Setting | Effect |
| --- | --- |
| `counts.shown` | Start with map counts visible when counts are enabled. |
| `textures.no_heights_iron` | Hide Iron in Heights when Gravel and Iron are available in Textures. |
| `pipette.any_tile_key_on`, `pipette.any_tile_key` | Enable and assign the held modifier for pasting heights and textures on protected tiles. The modifier defaults to Alt and starts disabled. |
| `grid.rotation_colour`, `grid.mine_colour`, `grid.mine_size` | Set the keep rotation line color, the iron mine outline color, and the mine footprint width in tiles. |

The author setting follows its launcher switch when it is unset. An explicit
author setting controls that part independently.

| Launcher switch | Author setting |
| --- | --- |
| `trees.spread_order` | `trees.sorted_rows` |
| `rocks.variants` | `rocks.extra_rock` |
| `castle.building_counts` | `castle.hover_text_left` |
| `castle.keep_crests` | `castle.keep_crest_tooltip` |
| `map_settings.menu` | `map_settings.button` |

Use configured key reads the profile’s separate enable and key settings for
`heights.invert_shortcut`, `pipette.select_shortcut` and `pipette.read_shortcut`.
Choose Off to disable the module’s shortcut or choose a key directly. With Custom
Hotkeys, the Pipette action has its own binding in the in-game editor.

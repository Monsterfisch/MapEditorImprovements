# The "size 4" rock: what it is, whether it is safe, and how far it goes

Checked by reading the code of both executables (Stronghold Crusader.exe and
Stronghold_Crusader_Extreme.exe, same logic in both). Not yet confirmed in game.

## What happens when the rock size is 4 or more

When you place a rock, the editor sends one number to the rock placement: `variant + size × 4`
(variant 0–3 is the value that cycles after every rock, size 0–3 comes from the brush).

`placeRock` turns that number into a rock **type** and a **footprint**:

| number | type | footprint |
|---|---|---|
| 0–3 | 1–4 | 1×1 |
| 4–7 | 5–8 | 2×2 |
| 8–11 | 9–12 | 3×3 |
| 12–15 | 13–16 | 4×4 |
| 16 and up | **0** | **1×1** (the start values, because no case matches) |

So size 4 (numbers 16–19) and anything higher all give the **same** thing: a 1×1 rock of type
0. The variant makes no difference for it.

## Why type 0 looks different

Every rock type has a little function that runs when the rock is created. For types 1–16 it
stores the rock's first picture (a "base"): 529/533/537/541 for the 1×1 rocks, 465–513 for 2×2,
321–429 for 3×3, 65–257 for 4×4 (all in `tile_rocks8.gm1`). Type 0's function does nothing, so
the base stays at what the empty slot held, and that is always **0**: removing a rock wipes its
slot to zeros, and unused slots start as zeros.

When the map is drawn, each rock tile shows picture
`base + tile number + rotation step × tiles + 1`, where the rotation step (0–3) comes from the
rock's own rotation plus the way the map is turned. With base 0 and one tile, a type-0 rock
shows **picture 1, 2, 3 or 4** of `tile_rocks8.gm1`, depending on rotation. No rock type uses
pictures 1–64 of that file; they are single-tile pieces of rocky ground. That is the "new"
rock.

## Can it cause problems?

Nothing found that would break a game or a map:

- **Saving and loading.** Maps save the rock list as it is in memory (the whole 4000 × 32 byte
  array, file section 0x3F6), and loading does not run the type functions again. A type-0 rock
  is saved and loaded like any other and draws the same afterwards.
- **Playing the map without this module.** The rock is drawn straight from the saved values, so
  a game without the module shows it the same way.
- **Other code that looks at rock types.** Only two functions read a rock's type: they give
  rock tiles a height for line of sight and similar checks (types 13+ tallest, 9+ next, the rest
  lowest). Type 0 counts as a small rock, which is what it looks like.
- **Removing it.** The delete tool, and anything that clears rocks, works through the tile's
  rock number and wipes the slot like any other rock.
- **Turning the map.** Because the rotation step picks among pictures 1–4, turning the map shows
  a *different* rocky piece rather than the same piece from another side. Ordinary 1×1 rocks
  turn properly because their four pictures are one rock seen from four sides. This is the one
  visible quirk.
- **The placement preview** shows nothing for it: the preview's own table has no entry past 15,
  so it previews a rock of size 0. Placing still works.

## More variants the same way, without new map format or graphics

Yes, many more are possible.

- The picture a rock shows comes only from the **saved base**. A type-0 rock keeps whatever
  base it has, because nothing ever recalculates it. So a module could place a type-0 rock and
  then set its base to any value. That needs no new map format (the base is already saved) and
  no new graphics.
- **Bases 0, 4, 8, … 60** pick the 64 single-tile rocky pieces at the start of
  `tile_rocks8.gm1`, four at a time: up to 16 different 1×1 "rocks". Each one would also show
  the turning quirk above, unless those 64 pictures happen to be laid out as 16 pieces seen
  from four sides, which can only be checked by looking at them in game.
- **Higher bases** would pick single tiles out of the existing 2×2, 3×3 and 4×4 rocks. As 1×1
  rocks these look like cut-out pieces, and they don't turn properly either.
- **Bigger type-0 rocks** are not reachable through the size value (anything from 16 up is
  1×1). Making one would need a change in `placeRock` itself. It would be saved fine, but its
  pictures would only make sense if a matching block of pictures existed in the file.
- Types 17–19 also exist in the game's tables, but nothing can create them, and like type 0
  they have no picture function.

## In short

Size 4 is not a fifth size but a leftover: an un-typed 1×1 rock that shows the first rocky-ground
picture. It is safe to use and survives saving and playing. The same trick, with a chosen base,
could give up to 16 more 1×1 rock looks without any new files. Their one flaw is that turning the
map swaps them for a different-looking piece.

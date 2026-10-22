# Map Editor Improvements

**Author**: Monsterfish
**Version**: 1.0.5

Makes the map editor show more about the map you are working on. Every part can be switched
off in the settings.

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

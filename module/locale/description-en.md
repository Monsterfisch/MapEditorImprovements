# Map Editor Improvements

**Author**: Monsterfish
**Version**: 1.0.0

Makes the map editor show more about the map you are working on. Every part can be switched
off in the settings.

## Map counts

In the landscape editor:

- **Animals button:** how many animals and units are on the map.
- **Rocks button:** how many rocks are on the map. The game does not always keep this number
  up to date, so it can lag behind.
- **Vegetation button:** point at it, and the number of trees and shrubs appears next to the
  button's description. The game allows 1999 at most.
- **Animals menu:** the deer, camel, rabbit and lion buttons each show how many of that
  animal are on the map.

A red **"i"** button sits above the key button. Click it to hide the numbers, click it again
to bring them back. The settings decide whether the numbers start shown or hidden. The
button's description line (the text that appears when you point at a button) moves a little
to the right to make room for it.

## Always keep the menu up to date

The game only redraws the editor's menu while the mouse is over it. If something changes
while the mouse is on the map, for example a hotkey picks another tool or the counts change
as you place animals, the menu keeps showing the old state until you move the mouse back
onto it. With this setting the menu is redrawn all the time in the map editor. It does not
change anything outside the map editor.

## Good to know

- Works with Stronghold Crusader and Stronghold Crusader Extreme.
- Nothing is saved into the map.

"""The editor's floating panels (editor/lane.lua) never cover each other, the menus' own items in
the band above the menu, the game's description line or the row above it, and stay on the screen.

Runs the module's lane.lua under Lua 5.4, its memory reads served from each executable's static
data: the landscape and build menus' item tables, their description items (the item the game's
description renderer draws) and the native buttons above the menu. The menu's origin, the screen
width and the active tab are written into a scratch area, as the game would have them, and every
placement goes through lane.spot, as the module's panels do. The module's own items at the
screen's top left (the undo and redo buttons) are added to each menu. What only exists at runtime
gets a bound that errs on the safe side: picture buttons without a size of their own take the room
up to their right-hand neighbour (at most 64 x 64), the building counts box the width of its
longest line at 8 pixels a character.

Every panel kind of both menus is placed, with entry counts and sizes at least as large as the
module's (castle: ruins, variant rows, hovels, keep parts, walls and crenels with the wall height
slider on top, moat kinds, tunnel and tents; landscape: trees, shrubs, felled trees (up to 12),
rock variants, eraser, pipette with its text line, the herd panel, the height panel), at screen
widths from 1024 to 2560. Each must lie on the screen, over the menu where it fits, and clear of
every keep-out; the slider also clear of its panel; the pipette panel and a Vegetation panel shown
at once clear of each other. Plus a property check of the placement itself on random keep-outs,
and the ruins row placed as 1.0.63 did, which these checks catch.
"""
import os, random, struct, sys
import lupa.lua54 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from shc import Exe, G as GAME

MODULE = os.environ.get('MAP_EDITOR_IMPROVEMENTS_MODULE', os.path.join(os.path.dirname(HERE), 'module'))
SIZE = 0x50
LANDSCAPE_AOB = "03 00 00 02 00 00 00 80 92 00 00 00 00 00 00 00 00 00 00 00 ? ? ? ? 98 00 00 00"
LANDSCAPE_KEY_ITEM, LANDSCAPE_DESCRIPTION_ITEM = 11, 9
BUILD_AOB = "02 00 80 00 3B 02 00 00 D1 01 00 00 7E 00 00 00 7E 00 00 00 ? ? ? ? 39 30 00 00"
BUILD_MINIMAP_ITEM = 17
SCREENS = (1024, 1280, 1366, 1600, 1920, 2560)
MENU_WIDTH = 1024
SCRATCH = 0x7F000000              # the menu object, screen width and active tab
FAKE_ITEMS = 0x7F001000           # the module's own items at the screen's top left
PANEL_PADDING, PANEL_GAP, PANEL_MARGIN = 4, 2, 4

failures = 0


def expect(label, ok, detail=''):
    global failures
    failures += not ok
    if not ok:
        print('  FAIL %s %s' % (label, detail))
    return ok


class Static:
    """core's reads over an executable's file image, with writes on top."""

    def __init__(self, exe):
        self.E = exe
        self.writes = {}

    def read(self, va, n):
        out = bytearray()
        for i in range(n):
            a = va + i
            if a in self.writes:
                out.append(self.writes[a])
            else:
                o = self.E.va2off(a)
                out.append(self.E.data[o] if o is not None else 0)
        return bytes(out)

    def put32(self, va, value):
        for i, b in enumerate(struct.pack('<i', value)):
            self.writes[va + i] = b

    def put16(self, va, value):
        for i, b in enumerate(struct.pack('<h', value)):
            self.writes[va + i] = b


def runtime(mem):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.INFO, g.WARNING = 'INFO', 'WARNING'
    g.log = lambda level, text: None
    c = lua.table()
    c.readInteger = lambda a: struct.unpack('<i', mem.read(int(a), 4))[0]
    c.readSmallInteger = lambda a: struct.unpack('<h', mem.read(int(a), 2))[0]
    c.readByte = lambda a: mem.read(int(a), 1)[0]
    g.core = c
    lua.execute('package.path = %r .. "/?.lua;" .. package.path' % MODULE.replace('\\', '/'))
    return lua


def items(mem, table):
    """(address, type, x, y, w, h, render-type, block) of every item, in order."""
    out, block, i = [], 0, 0
    while i < 1000:
        a = table + i * SIZE
        t, x, y, w, h = struct.unpack('<Iiiii', mem.read(a, 20))
        if t == 0x66:
            break
        if t == 0x64:
            block = struct.unpack('<i', mem.read(a + 0x18, 4))[0]
        rtype = struct.unpack('<i', mem.read(a + 0x24, 4))[0]
        out.append((a, t, x, y, w, h, rtype, block))
        i += 1
    return out


def bounded_measure(mem, all_items):
    """Size of an item: its own, else (pictures) up to its right-hand neighbour on its row."""
    by_address = {it[0]: it for it in all_items}

    def measure(address):
        address = int(address)
        if address not in by_address:          # the module's own items: their own size
            w, h = struct.unpack('<ii', mem.read(address + 0x0C, 8))
            return (w, h) if w > 0 and h > 0 else None
        a, t, x, y, w, h, rtype, block = by_address[address]
        if w > 0 and h > 0:
            return w, h
        if rtype != 3:
            return None
        right = [o[2] for o in all_items if o[0] != a and abs(o[3] - y) <= 4 and o[2] > x and o[7] == block
                 and (o[2] & 0xFFFFFFFF) != 0x80000000]
        width = min(64, (min(right) - x) if right else 64)
        return width, 64
    return measure


# Panel kinds: (name, entries, entry picture width, picture height, label room, extra above)
CASTLE_PANELS = {
    10: [('walls', 4, 64, 96, 16, 0), ('crenels', 6, 64, 96, 16, 0)],
    11: [('ruins', 5, 72, 110, 16, 0)],
    12: [('moat kinds', 3, 90, 64, 16, 0)],
    13: [('keep parts', 2, 120, 120, 16, 0)],
    14: [('tunnel', 1, 120, 90, 16, 0), ('tents', 6, 72, 90, 16, 0)],
    15: [('good things variants', 8, 72, 84, 16, 0)],
    30: [('hovels', 7, 72, 84, 16, 0), ('ruined cathedral', 1, 72, 84, 16, 0)],
    33: [('bad things variants', 4, 72, 84, 16, 0)],
}
LANDSCAPE_PANELS = [
    ('trees', 9, 64, 120, 16, 0), ('shrubs', 6, 48, 64, 16, 0), ('felled', 12, 64, 90, 16, 0),
    ('rock variants', 5, 64, 64, 16, 0), ('eraser', 6, 64, 64, 16, 0), ('pipette', 6, 64, 64, 16, 22),
    ('herd panel', 1, 520, 60, 0, 0), ('height panel', 1, 820, 110, 0, 0),
]


def panel_box(entries, width, height, label, above):
    total = entries * (width + 2 * PANEL_PADDING) + (entries - 1) * PANEL_GAP
    return total + 2 * PANEL_GAP, height + 2 * PANEL_PADDING + label + 2 * PANEL_GAP + above


def overlap(a, b):
    return a['x'] < b['x'] + b['w'] and b['x'] < a['x'] + a['w'] and a['y'] < b['y'] + b['h'] and b['y'] < a['y'] + a['h']


class Menu:
    """One menu of one executable, as lane.spot sees it."""

    def __init__(self, label, lua, mem, table, description, render, shift, counts):
        self.label, self.lua, self.mem = label, lua, mem
        self.lane = lua.eval('(require("editor.lane"))')
        self.layout = lua.eval('(require("editor.layout"))')
        self.all_items = items(mem, table)
        measure = bounded_measure(mem, self.all_items)
        self.measure = measure
        self.lane.measure = lambda G, address: measure(address)
        self.data = lua.table()
        self.data.floating, self.data.laneExtra = lua.table(), lua.table()
        self.lane.prepare(self.data, table, description, render, shift)
        if counts is not None:
            self.data.laneExtra.counts = lua.table_from(counts)
        # The module's undo and redo buttons, at the screen's top left (menu coordinates there).
        self.fake = []
        for i in range(2):
            address = FAKE_ITEMS + i * SIZE
            mem.put32(address, 3)
            mem.put32(address + 0x0C, 30)
            mem.put32(address + 0x10, 30)
            mem.put32(address + 0x24, 1)
            self.fake.append(address)
            lua.eval('table.insert')(self.data.laneBlocks[0], address)
        self.G = lua.table_from({'menu': SCRATCH, 'screenWidth': SCRATCH + 0x40, 'activeTab': SCRATCH + 0x44})

    def screen(self, width, tab):
        menu_x = (width - MENU_WIDTH) // 2
        self.mem.put32(SCRATCH + 4, menu_x)
        self.mem.put32(SCRATCH + 8, 0)
        self.mem.put32(SCRATCH + 0x40, width)
        self.mem.put32(SCRATCH + 0x44, tab)
        for i, address in enumerate(self.fake):
            self.mem.put32(address + 4, 10 + i * 40 - menu_x)
            self.mem.put32(address + 8, 10)
        self.data.laneCache = None
        self.data.lanePlaced = None
        return menu_x

    def keep_outs(self, tab):
        rects = self.lane.keepOuts(self.data, tab, self.measure)[0]
        return [dict(x=r.x, y=r.y, w=r.w, h=r.h)
                for r in list(rects.values()) + list(self.lane.extras(self.data).values())]

    def spot(self, owner, w, h, bottom=None, extra=None):
        extra_lua = self.lua.table_from([self.lua.table_from(r) for r in (extra or [])])
        left, top = self.lane.spot(self.G, self.data, owner, w, h, bottom, extra_lua)
        return dict(x=left, y=top, w=w, h=h)


def check_menu(menu, tabs, panels_for):
    placed = 0
    span = menu.lane.menuSpan(menu.data, menu.measure)[0]
    inner = dict(left=span.left, right=span.right)
    print('  %s: menu width %d..%d' % (menu.label, inner['left'], inner['right']))
    for screen in SCREENS:
        menu.screen(screen, 0)
        span = menu.lane.menuSpan(menu.data, menu.measure)[0]
        expect('%s at %d px: the undo/redo buttons do not widen the menu' % (menu.label, screen),
               span.left == inner['left'] and span.right == inner['right'], repr((span.left, span.right)))
    for tab in tabs:
        keep = menu.keep_outs(tab)
        for screen in SCREENS:
            menu_x = menu.screen(screen, tab)
            left_edge, right_edge = PANEL_MARGIN - menu_x, screen - PANEL_MARGIN - menu_x
            for name, entries, width, height, room, above in panels_for(tab):
                menu.data.lanePlaced = None
                w, h = panel_box(entries, width, height, room, above)
                box = menu.spot(menu.lua.table_from({'items': menu.lua.table()}), w, h)
                where = '%s tab %d %s at %d px: box %r' % (menu.label, tab, name, screen, box)
                expect('inside the screen', left_edge <= box['x'] and box['x'] + w <= right_edge, where)
                if w <= inner['right'] - inner['left']:
                    expect('over the menu', inner['left'] <= box['x'] and box['x'] + w <= inner['right'], where)
                expect('above the menu', box['y'] + h <= menu.layout.PANEL_BOTTOM, where)
                expect('on the screen vertically', box['y'] >= 0, where)
                for r in keep:
                    expect('clear of %r' % r, not overlap(box, r), where)
                placed += 1
                if name in ('walls', 'crenels'):
                    sw, sh = 420, menu.layout.K.WALL_SLIDER.height
                    slider = menu.spot(menu.lua.table_from({'items': menu.lua.table()}), sw, sh,
                                       box['y'] - 3 * PANEL_GAP, [box])
                    expect('slider inside the screen', left_edge <= slider['x'] and slider['x'] + sw <= right_edge, where)
                    expect('slider clear of its panel', not overlap(slider, box), where)
                    for r in keep:
                        expect('slider clear of %r' % r, not overlap(slider, r), where)
                    placed += 1
    return placed


def check_together(menu, tab):
    """The pipette panel and a Vegetation panel up at once, frame after frame."""
    shown = FAKE_ITEMS + 0x400
    menu.mem.put32(shown, 3)
    menu.mem.put16(shown + 0x36, 0)
    pipette = menu.lua.table_from({'items': menu.lua.table_from([shown])})
    trees = menu.lua.table_from({'items': menu.lua.table_from([shown + SIZE])})
    menu.mem.put16(shown + SIZE + 0x36, 0)
    count = 0
    for screen in SCREENS:
        menu.screen(screen, tab)
        pw, ph = panel_box(*LANDSCAPE_PANELS[5][1:])
        tw, th = panel_box(*LANDSCAPE_PANELS[0][1:])
        for frame in range(3):
            a = menu.spot(pipette, pw, ph)
            b = menu.spot(trees, tw, th)
            expect('%s at %d px frame %d: pipette and trees panels clear of each other' % (menu.label, screen, frame),
                   not overlap(a, b), '%r %r' % (a, b))
            count += 2
    return count


def property_check(lua):
    lane = lua.eval('(require("editor.lane"))')
    rng = random.Random(7)
    count = 0
    for _ in range(3000):
        keep = []
        for _ in range(rng.randint(0, 8)):
            keep.append(dict(x=rng.randint(-200, 1100), y=rng.randint(200, 460), w=rng.randint(1, 400), h=rng.randint(1, 80)))
        width, height = rng.randint(10, 900), rng.randint(10, 160)
        inner = dict(left=rng.randint(-300, 100), right=rng.randint(600, 1400))   # may reach past the screen
        opts = dict(left=-100, right=1124, centre=512, bottom=444, gap=2, inner=lua.table_from(inner),
                    keepOut=lua.table_from([lua.table_from(r) for r in keep]))
        left, top = lane.place(width, height, lua.table_from(opts))
        box = dict(x=left, y=top, w=width, h=height)
        ok = top + height <= 444 and left >= -100 and left + width <= 1124
        clamped = (max(-100, inner['left']), min(1124, inner['right']))
        if width <= clamped[1] - clamped[0]:
            ok = ok and clamped[0] <= left and left + width <= clamped[1]
        ok = ok and all(not overlap(box, r) for r in keep)
        count += 1
        expect('placement property', ok, 'keep %r inner %r size %dx%d -> %r' % (keep, inner, width, height, box))
    return count


def main():
    total = 0
    for exe_name in ('Stronghold Crusader.exe', 'Stronghold_Crusader_Extreme.exe'):
        E = Exe(os.path.join(GAME, exe_name))
        mem = Static(E)
        lua = runtime(mem)
        layout = lua.eval('(require("editor.layout"))')
        K = layout.K
        land = E.find(LANDSCAPE_AOB)
        build = E.find(BUILD_AOB)
        expect(exe_name + ': menus found once', len(land) == 1 and len(build) == 1)
        land_table = land[0] - LANDSCAPE_KEY_ITEM * SIZE
        build_table = build[0] - BUILD_MINIMAP_ITEM * SIZE
        description = land_table + LANDSCAPE_DESCRIPTION_ITEM * SIZE
        render = struct.unpack('<I', mem.read(description + 0x1C, 4))[0]
        # The module moves the landscape description line right of its "i" button.
        mem.put32(description + 4, layout.HOVER_TEXT_MOVED_X)
        landscape = Menu(exe_name + ' landscape', lua, mem, land_table, description, render, 0, None)
        expect(landscape.label + ': description line found', landscape.data.description is not None)
        landscape_tabs = sorted({it[7] for it in landscape.all_items} - {0})
        total += check_menu(landscape, landscape_tabs, lambda tab: LANDSCAPE_PANELS)
        total += check_together(landscape, landscape_tabs[0])
        # Building counts: right edge on the minimap's, 3 lines, the longest line's width bound.
        minimap = build_table + BUILD_MINIMAP_ITEM * SIZE
        mx, my, mw = struct.unpack('<iii', mem.read(minimap + 4, 12))
        width = 8 * len('Player buildings, all players: 9999') + 2 * layout.TOOLTIP_PADDING
        height = 3 * layout.TOOLTIP_LINE + layout.TOOLTIP_PADDING
        counts = dict(x=mx + mw - width, y=layout.PANEL_BOTTOM - PANEL_GAP - height, w=width, h=height)
        castle = Menu(exe_name + ' castle', lua, mem, build_table, None, render, K.HOVER_TEXT_SHIFT, counts)
        expect(castle.label + ': description line found (by its renderer)', castle.data.description is not None)
        total += check_menu(castle, sorted(CASTLE_PANELS), lambda tab: CASTLE_PANELS[tab])
        # The reported case: five ruins on the towers tab, before and now.
        d = castle.data.description
        dx, dy, dw = struct.unpack('<iii', mem.read(d + 4, 12))
        print('  %s: castle description line at (%d, %d), %d wide' % (exe_name, dx, dy, dw))
        keep = castle.keep_outs(11)
        w, h = panel_box(*CASTLE_PANELS[11][0][1:])
        for screen in (1024, 1920, 2560):
            menu_x = castle.screen(screen, 11)
            # As 1.0.63 placed it: centred on the screen, 50 left (K.PANEL_SHIFT[11]), bottom 444.
            old = dict(x=(screen - w) // 2 - menu_x - 50, y=layout.PANEL_BOTTOM - h, w=w, h=h)
            covered = [r for r in keep if overlap(old, r)]
            new = castle.spot(lua.table_from({'items': lua.table()}), w, h)
            print('  ruins at %d px: before %r covered %r; now %r covers %d' % (
                screen, old, covered, new, sum(overlap(new, r) for r in keep)))
            expect('the old placement is caught by this check', len(covered) > 0)
    total += property_check(lua)
    print('%d placements checked, %d failures' % (total, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

"""The editor's floating panels (editor/lane.lua) never cover each other, the menus' own items in
the band above the menu, the game's description line or the row above it, and stay on the screen.

Runs the module's lane.lua under Lua 5.4, its memory reads served from each executable's static
data. Each menu's item table is copied, as the module copies it, with the module's items added
where the module adds them: the undo and redo buttons (placed at the screen's top left), the
landscape menu's "i" button, and the items of every floating panel (one owner per panel) at the end
of its block, which is also the order the menu draws them in. The menu's origin and scroll, the
screen size and the active tab are written into a scratch area, as the game would have them, and
every placement goes through lane.spot, as the module's panels do. What only exists at runtime gets
a bound that errs on the safe side: picture buttons without a size of their own take the room up
to their right-hand neighbour (at most 64 x 64; image 0 has no picture), the building counts box
the width of its longest line at 8 pixels a character.

Checks:
  * every panel kind of both menus on its own, with entry counts and sizes at least as large as
    the module's, at screen widths from 800 to 2560 (800 with the menu scrolled), plus the wall
    height slider on its panel: on the screen, over the menu where it fits, clear of every
    keep-out, and the slider clear of its panel;
  * a walk through the tabs of each menu, frame by frame, the way the menu draws its panels: a
    panel left up on another tab doesn't count, panels up at once (the pipette and a Vegetation
    panel, a wall panel and its slider) never overlap, nothing jumps between frames, also when the
    pipette's line widens or the wall panel changes to the crenel panel, and each step's places
    equal those of the same step from a fresh start;
  * the keep-outs are complete (read again only every lane.REUSE placements) once the menu is laid
    out;
  * the placement itself on random keep-outs; and the ruins row placed as 1.0.63 did, which these
    checks catch.
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
# Screen width: (height, menu scrolls tried). The menu's coordinates start 600 above the bottom.
SCREENS = {800: (600, (0, 112, 224)), 1024: (768, (0,)), 1280: (1024, (0,)), 1366: (768, (0,)),
           1600: (900, (0,)), 1920: (1080, (0,)), 2560: (1440, (0,))}
MENU_WIDTH = 1024
SCRATCH = 0x7F000000              # the menu object, screen width and active tab
COPIES = 0x7F100000               # the module's copies of the menu tables
PANEL_PADDING, PANEL_GAP, PANEL_MARGIN = 4, 2, 4
TYPE_CLICKABLE, RENDER_NONE, RENDER_IMAGE, TYPE_BLOCK, TYPE_END = 3, 0, 3, 0x64, 0x66
PLACED = 0x80000000
TEXTURES, VEGETATION, ANIMALS, ROCKS, HEIGHTS = 232, 234, 235, 237, 231
HEIGHT_LIST = 66                  # the height panel's mode list, open above it

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

    def put(self, va, data):
        for i, b in enumerate(data):
            self.writes[va + i] = b

    def put32(self, va, value):
        self.put(va, struct.pack('<I', value & 0xFFFFFFFF))

    def put16(self, va, value):
        self.put(va, struct.pack('<h', value))


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
    """(address, type, x, y, w, h, render-type, block, image) of every item, in order."""
    out, block, i = [], 0, 0
    while i < 2000:
        a = table + i * SIZE
        t, x, y, w, h = struct.unpack('<Iiiii', mem.read(a, 20))
        if t == TYPE_END:
            break
        if t == TYPE_BLOCK:
            block = struct.unpack('<i', mem.read(a + 0x18, 4))[0]
        image = struct.unpack('<I', mem.read(a + 0x20, 4))[0] & 0xFFFF
        rtype = struct.unpack('<i', mem.read(a + 0x24, 4))[0]
        out.append((a, t, x, y, w, h, rtype, block, image))
        i += 1
    return out


def copy_table(mem, table, at, inserts):
    """The menu table copied to `at`, with each block's `inserts` (name, item fields) added at its
    end. Returns the copy, the new address of each original item and of each added one."""
    inserts = {block: list(entries) for block, entries in inserts.items()}
    originals, added, block, i, out = {}, {}, 0, 0, at

    def flush(b):
        nonlocal out
        for name, fields in inserts.pop(b, []):
            mem.put(out, bytes(SIZE))
            mem.put32(out, fields.get('type', TYPE_CLICKABLE))
            for offset, key in ((4, 'x'), (8, 'y'), (0x0C, 'w'), (0x10, 'h'), (0x20, 'image'), (0x24, 'render')):
                mem.put32(out + offset, fields.get(key, 0))
            mem.put16(out + 0x36, fields.get('hidden', 1))
            added[name] = out
            out += SIZE
    while True:
        a = table + i * SIZE
        t = struct.unpack('<I', mem.read(a, 4))[0]
        if t in (TYPE_BLOCK, TYPE_END):
            flush(block)
        if t == TYPE_BLOCK:
            block = struct.unpack('<i', mem.read(a + 0x18, 4))[0]
        mem.put(out, mem.read(a, SIZE))
        originals[i] = out
        out += SIZE
        i += 1
        if t == TYPE_END:
            break
    expect('every insert has its block', not inserts, repr(sorted(inserts)))
    return at, originals, added


def bounded_measure(mem, all_items):
    """Size of an item: its own, else (pictures) up to its right-hand neighbour on its row; image 0
    has no picture."""
    by_address = {it[0]: it for it in all_items}

    def measure(address):
        a, t, x, y, w, h, rtype, block, image = by_address[int(address)]
        w, h = struct.unpack('<ii', mem.read(a + 0x0C, 8))
        x, y = struct.unpack('<ii', mem.read(a + 4, 8))
        if w > 0 and h > 0:
            return w, h
        if rtype != RENDER_IMAGE or image == 0:
            return None
        right = [o[2] for o in all_items if o[0] != a and abs(o[3] - y) <= 4 and o[2] > x and o[7] == block
                 and (o[2] & 0xFFFFFFFF) != PLACED]
        return min(64, (min(right) - x) if right else 64), 64
    return measure


def panel_box(entries, width, height, label, above, above_width=0):
    total = entries * (width + 2 * PANEL_PADDING) + (entries - 1) * PANEL_GAP
    return max(total, above_width) + 2 * PANEL_GAP, height + 2 * PANEL_PADDING + label + 2 * PANEL_GAP + above


# Panel kinds: (entries, entry picture width, picture height, label room, extra above[, line width])
CASTLE_PANELS = {
    10: {'walls': (4, 64, 96, 16, 0), 'crenels': (6, 64, 96, 16, 0)},
    11: {'ruins': (5, 72, 110, 16, 0)},
    12: {'moat kinds': (3, 90, 64, 16, 0)},
    13: {'keep parts': (2, 120, 120, 16, 0)},
    14: {'tunnel': (1, 120, 90, 16, 0), 'tents': (6, 72, 90, 16, 0)},
    15: {'good things variants': (8, 72, 84, 16, 0)},
    30: {'hovels': (7, 72, 84, 16, 0), 'ruined cathedral': (1, 72, 84, 16, 0)},
    33: {'bad things variants': (4, 72, 84, 16, 0)},
}
SLIDER = (420, 24)
PIPETTE_SHORT = (4, 64, 64, 15, 22, 300)
PIPETTE_WIDE = (4, 64, 64, 15, 22, 600)
# Landscape owners: the block their items are in, and their panels' sizes.
LANDSCAPE_OWNERS = {
    'pipette': (0, {'pipette': PIPETTE_SHORT, 'pipette, wide line': PIPETTE_WIDE}),
    'eraser': (0, {'eraser': (6, 64, 64, 16, 0)}),
    'vegetation': (VEGETATION, {'trees': (9, 64, 120, 16, 0), 'shrubs': (6, 48, 64, 16, 0),
                                'felled': (12, 64, 90, 16, 0)}),
    'rocks': (ROCKS, {'rock variants': (5, 64, 64, 16, 0)}),
    'herd': (ANIMALS, {'herd panel': None}),
    'height': (HEIGHTS, {'height panel': None}),
}
FIXED_SIZES = {'herd panel': (532, 72), 'height panel': (832, 122)}


def size_of(kind, sizes, screen):
    spec = sizes[kind]
    if spec is None:
        return FIXED_SIZES[kind]
    w, h = panel_box(*spec)
    # makePanel narrows the gaps between the entries to fit the screen.
    return min(w, screen - 2 * PANEL_MARGIN), h


def overlap(a, b):
    return a['x'] < b['x'] + b['w'] and b['x'] < a['x'] + a['w'] and a['y'] < b['y'] + b['h'] and b['y'] < a['y'] + a['h']


class Menu:
    """One menu of one executable, as the module builds it and lane.spot sees it."""

    def __init__(self, label, lua, mem, table, at, inserts, description_index, render, shift, counts, moved_x=None):
        self.label, self.lua, self.mem = label, lua, mem
        self.lane = lua.eval('(require("editor.lane"))')
        self.layout = lua.eval('(require("editor.layout"))')
        self.table, originals, self.added = copy_table(mem, table, at, inserts)
        description = originals[description_index] if description_index is not None else None
        if description is not None and moved_x is not None:
            mem.put32(description + 4, moved_x)
        self.all_items = items(mem, self.table)
        self.measure = bounded_measure(mem, self.all_items)
        measure = self.measure
        self.lane.measure = lambda G, address: measure(address)
        self.data = lua.table()
        self.data.floating, self.data.laneExtra = lua.table(), lua.table()
        self.lane.prepare(self.data, self.table, description, render, shift)
        if counts is not None:
            self.data.laneExtra.counts = lua.table_from(counts)
        self.G = lua.table_from({'menu': SCRATCH, 'screenWidth': SCRATCH + 0x40, 'activeTab': SCRATCH + 0x44})
        self.owners = {}
        self.blocks = {it[7] for it in self.all_items}

    def owner(self, name):
        if name not in self.owners:
            self.owners[name] = self.lua.table_from({'items': self.lua.table_from([self.added[name]])})
        return self.owners[name]

    def screen(self, width, tab, scroll=0):
        height = SCREENS[width][0]
        menu_x, menu_y = (width - MENU_WIDTH) // 2 if width >= MENU_WIDTH else 0, height - 600
        self.mem.put32(SCRATCH + 4, menu_x)
        self.mem.put32(SCRATCH + 8, menu_y)
        self.mem.put32(SCRATCH + 0x14, scroll)
        self.mem.put32(SCRATCH + 0x40, width)
        self.mem.put32(SCRATCH + 0x44, tab)
        for i, kind in enumerate(('undo', 'redo')):
            if kind in self.added:
                self.mem.put32(self.added[kind] + 4, 10 + i * 38 - menu_x)
                self.mem.put32(self.added[kind] + 8, 10 - menu_y)
        self.data.laneCache = None
        origin = menu_x - scroll
        return dict(left=PANEL_MARGIN - origin, right=width - PANEL_MARGIN - origin, top=-menu_y, origin=origin)

    def tab(self, tab):
        self.mem.put32(SCRATCH + 0x44, tab)

    def fresh(self):
        self.data.laneCache = None
        self.data.lanePlaced = None
        for name in self.added:
            if name not in ('undo', 'redo', 'info'):
                self.mem.put16(self.added[name] + 0x36, 1)

    def keep_outs(self, tab):
        rects = self.lane.keepOuts(self.data, tab, self.measure)[0]
        return [dict(x=r.x, y=r.y, w=r.w, h=r.h)
                for r in list(rects.values()) + list(self.lane.extras(self.data).values())]

    def span(self, edges):
        span = self.lane.menuSpan(self.data, self.measure)[0]
        return max(edges['left'], span.left), min(edges['right'], span.right)

    def spot(self, owner, w, h, bottom=None, extra=None):
        extra_lua = self.lua.table_from([self.lua.table_from(r) for r in (extra or [])])
        left, top = self.lane.spot(self.G, self.data, owner, w, h, bottom, extra_lua)
        return dict(x=left, y=top, w=w, h=h)


def check_box(menu, where, box, edges, keep, inner, reach_up=0):
    w = box['w']
    if w <= edges['right'] - edges['left']:
        expect('inside the screen', edges['left'] <= box['x'] and box['x'] + w <= edges['right'], where)
    if w <= inner[1] - inner[0]:
        expect('over the menu', inner[0] <= box['x'] and box['x'] + w <= inner[1], where)
    expect('above the menu', box['y'] + box['h'] <= menu.layout.PANEL_BOTTOM, where)
    expect('on the screen vertically', box['y'] - reach_up >= edges['top'], where)
    for r in keep:
        expect('clear of %r' % r, not overlap(box, r), where)


def check_single(menu, tabs, kinds_for):
    """Every panel kind on its own on every tab given, the wall slider on its panel."""
    placed, wide = 0, []
    for tab in tabs:
        keep = menu.keep_outs(tab)
        for screen, (_, scrolls) in SCREENS.items():
            for scroll in scrolls:
                edges = menu.screen(screen, tab, scroll)
                inner = menu.span(edges)
                for kind, sizes in kinds_for(tab):
                    menu.fresh()
                    w, h = size_of(kind, sizes, screen)
                    box = menu.spot(menu.lua.table_from({'items': menu.lua.table()}), w, h)
                    where = '%s tab %d %s at %d px scroll %d: box %r' % (menu.label, tab, kind, screen, scroll, box)
                    if w > edges['right'] - edges['left']:
                        wide.append('%s at %d px' % (kind, screen))
                    check_box(menu, where, box, edges, keep, inner, HEIGHT_LIST if kind == 'height panel' else 0)
                    placed += 1
                    if kind in ('walls', 'crenels'):
                        slider = menu.spot(menu.lua.table_from({'items': menu.lua.table()}), SLIDER[0], SLIDER[1],
                                           box['y'] - 3 * PANEL_GAP, [box])
                        check_box(menu, where + ' slider %r' % slider, slider, edges, keep, inner)
                        expect('slider clear of its panel', not overlap(slider, box), where)
                        placed += 1
    if wide:
        print('  %s: wider than the screen (not checked against its edges): %s' % (menu.label, ', '.join(sorted(set(wide)))))
    return placed


def walk(menu, steps, owners, screen, scroll, fresh_each):
    """The steps (tab, [(owner, kind)]) frame by frame, as the menu draws: on each frame every
    owner of block 0 and of the tab, in table order, hides its items, and the active ones are
    placed and shown. The panels of other tabs keep their items shown, as the game leaves them."""
    order = sorted(owners, key=lambda name: menu.added[name])
    results, placed = [], 0
    edges = menu.screen(screen, steps[0][0], scroll)
    if not fresh_each:
        menu.fresh()
    for tab, active in steps:
        if fresh_each:
            menu.fresh()
        menu.tab(tab)
        frames = []
        for _ in range(3):
            rects = {}
            for name in order:
                block, sizes = owners[name]
                if block not in (0, tab):
                    continue
                menu.mem.put16(menu.added[name] + 0x36, 1)
                kinds = [k for o, k in active if o == name]
                if not kinds:
                    continue
                if name == 'slider':
                    panel = rects[[o for o, _ in active if o in ('walls', 'crenels')][0]]
                    box = menu.spot(menu.owner(name), SLIDER[0], SLIDER[1], panel['y'] - 3 * PANEL_GAP, [panel])
                else:
                    w, h = size_of(kinds[0], sizes, screen)
                    box = menu.spot(menu.owner(name), w, h)
                menu.mem.put16(menu.added[name] + 0x36, 0)
                rects[name] = box
                placed += 1
            frames.append(rects)
        results.append((tab, active, frames, edges))
    return results, placed


def check_walk(menu, steps, owners):
    placed = 0
    for screen, (_, scrolls) in SCREENS.items():
        for scroll in scrolls:
            reference, n1 = walk(menu, steps, owners, screen, scroll, True)
            walked, n2 = walk(menu, steps, owners, screen, scroll, False)
            placed += n1 + n2
            for step, ((tab, active, frames, edges), (_, _, ref_frames, _)) in enumerate(zip(walked, reference)):
                keep = menu.keep_outs(tab)
                inner = menu.span(edges)
                where = '%s walk step %d (tab %d, %s) at %d px scroll %d' % (
                    menu.label, step, tab, ', '.join(k for _, k in active), screen, scroll)
                for f, rects in enumerate(frames):
                    for name, box in rects.items():
                        check_box(menu, '%s frame %d %s %r' % (where, f, name, box), box, edges, keep, inner,
                                  HEIGHT_LIST if name == 'height' else 0)
                    names = sorted(rects)
                    for i, a in enumerate(names):
                        for b in names[i + 1:]:
                            expect('panels up at once clear of each other', not overlap(rects[a], rects[b]),
                                   '%s frame %d: %s %r, %s %r' % (where, f, a, rects[a], b, rects[b]))
                    expect('the same places on every frame', rects == frames[0], '%s frame %d: %r then %r' % (
                        where, f, frames[0], rects))
                expect('the same places as from a fresh start', frames[-1] == ref_frames[-1],
                       '%s: %r, fresh %r' % (where, frames[-1], ref_frames[-1]))
    return placed


def check_complete(menu, tabs):
    """Once the menu is laid out (the control-placed items given places below the band), every
    tab's keep-outs and the menu's width are complete, so they are reused for lane.REUSE frames."""
    moved = []
    for it in menu.all_items:
        if (it[2] & 0xFFFFFFFF) == PLACED:
            moved.append(it[0])
            menu.mem.put32(it[0] + 4, 0)
            menu.mem.put32(it[0] + 8, 1000)
    print('  %s: %d items placed by the menu itself, given places below the band for this check' % (
        menu.label, len(moved)))
    for tab in tabs:
        complete = menu.lane.keepOuts(menu.data, tab, menu.measure)[1]
        expect('%s tab %d: keep-outs complete once laid out' % (menu.label, tab), complete)
    expect('%s: menu width complete once laid out' % menu.label, menu.lane.menuSpan(menu.data, menu.measure)[1])
    menu.screen(1920, tabs[0])
    menu.fresh()
    owner = menu.lua.table_from({'items': menu.lua.table()})
    for _ in range(3):
        menu.spot(owner, 100, 50)
    expect('%s: keep-outs reused' % menu.label, menu.data.laneCache.uses < menu.lane.REUSE,
           'uses %r' % menu.data.laneCache.uses)
    for address in moved:
        menu.mem.put32(address + 4, PLACED)
    menu.fresh()


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
    for n, exe_name in enumerate(('Stronghold Crusader.exe', 'Stronghold_Crusader_Extreme.exe')):
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
        render = struct.unpack('<I', mem.read(land_table + LANDSCAPE_DESCRIPTION_ITEM * SIZE + 0x1C, 4))[0]
        undo = [('undo', dict(w=30, h=30, render=1, hidden=0)), ('redo', dict(w=30, h=30, render=1, hidden=0))]

        # Landscape: block 0 gets the undo/redo, "i" and pipette and eraser items; each tab its panels'.
        land_blocks = {it[7] for it in items(mem, land_table)}
        inserts = {0: undo + [('info', dict(x=layout.INFO_BUTTON[1], y=layout.INFO_BUTTON[2], w=30, h=30,
                                            render=RENDER_IMAGE, image=layout.INFO_IMAGE, hidden=0)),
                              ('pipette', {}), ('eraser', {})]}
        land_owners = {}
        for name, (block, sizes) in LANDSCAPE_OWNERS.items():
            if block == 0 or block in land_blocks:
                land_owners[name] = (block, sizes)
                if block != 0:
                    inserts.setdefault(block, []).append((name, {}))
        expect(exe_name + ': the landscape tabs the walk uses exist',
               all(t in land_blocks for t in (TEXTURES, VEGETATION, ANIMALS, ROCKS, HEIGHTS)))
        landscape = Menu(exe_name + ' landscape', lua, mem, land_table, COPIES + n * 0x40000, inserts,
                         LANDSCAPE_DESCRIPTION_ITEM, render, 0, None, layout.HOVER_TEXT_MOVED_X)
        expect(landscape.label + ': description line found', landscape.data.description is not None)
        span = landscape.lane.menuSpan(landscape.data, landscape.measure)[0]
        print('  %s: menu width %d..%d' % (landscape.label, span.left, span.right))
        expect(landscape.label + ': the "i" button is part of the menu', span.left == layout.INFO_BUTTON[1])
        landscape_tabs = sorted(landscape.blocks - {0})
        all_landscape = [(kind, sizes) for _, sizes in LANDSCAPE_OWNERS.values() for kind in sizes]
        total += check_single(landscape, landscape_tabs, lambda tab: all_landscape)
        total += check_walk(landscape, [
            (VEGETATION, [('pipette', 'pipette'), ('vegetation', 'trees')]),
            (VEGETATION, [('pipette', 'pipette, wide line'), ('vegetation', 'trees')]),
            (VEGETATION, [('vegetation', 'felled')]),
            (HEIGHTS, [('height', 'height panel')]),
            (ANIMALS, [('herd', 'herd panel')]),
            (ROCKS, [('rocks', 'rock variants')]),
            (ROCKS, [('pipette', 'pipette, wide line'), ('rocks', 'rock variants')]),
            (TEXTURES, [('pipette', 'pipette, wide line')]),
            (TEXTURES, [('eraser', 'eraser')]),
            (VEGETATION, [('pipette', 'pipette'), ('vegetation', 'shrubs')]),
            (HEIGHTS, [('height', 'height panel')]),
        ], land_owners)
        check_complete(landscape, landscape_tabs)

        # Castle: undo/redo in block 0; each tab its panels' items, the wall slider's after them.
        minimap = build_table + BUILD_MINIMAP_ITEM * SIZE
        mx, my, mw = struct.unpack('<iii', mem.read(minimap + 4, 12))
        width = 8 * len('Player buildings, all players: 9999') + 2 * layout.TOOLTIP_PADDING
        height = 3 * layout.TOOLTIP_LINE + layout.TOOLTIP_PADDING
        counts = dict(x=mx + mw - width, y=layout.PANEL_BOTTOM - PANEL_GAP - height, w=width, h=height)
        inserts = {0: list(undo)}
        castle_owners = {}
        for tab, kinds in CASTLE_PANELS.items():
            for kind in kinds:
                inserts.setdefault(tab, []).append((kind, {}))
                castle_owners[kind] = (tab, kinds)
        inserts[K.TAB_CASTLE].append(('slider', {}))
        castle_owners['slider'] = (K.TAB_CASTLE, None)
        castle = Menu(exe_name + ' castle', lua, mem, build_table, COPIES + n * 0x40000 + 0x20000, inserts,
                      None, render, K.HOVER_TEXT_SHIFT, counts)
        expect(castle.label + ': description line found (by its renderer)', castle.data.description is not None)
        span = castle.lane.menuSpan(castle.data, castle.measure)[0]
        print('  %s: menu width %d..%d' % (castle.label, span.left, span.right))
        total += check_single(castle, sorted(CASTLE_PANELS),
                              lambda tab: [(k, CASTLE_PANELS[tab]) for k in CASTLE_PANELS[tab]])
        total += check_walk(castle, [
            (11, [('ruins', 'ruins')]),
            (30, [('hovels', 'hovels')]),
            (14, [('tents', 'tents')]),
            (15, [('good things variants', 'good things variants')]),
            (10, [('walls', 'walls'), ('slider', 'slider')]),
            (10, [('crenels', 'crenels'), ('slider', 'slider')]),
            (10, [('walls', 'walls'), ('slider', 'slider')]),
            (12, [('moat kinds', 'moat kinds')]),
            (13, [('keep parts', 'keep parts')]),
            (33, [('bad things variants', 'bad things variants')]),
            (30, [('ruined cathedral', 'ruined cathedral')]),
            (14, [('tunnel', 'tunnel')]),
            (11, [('ruins', 'ruins')]),
        ], castle_owners)
        check_complete(castle, sorted(CASTLE_PANELS))

        # The reported case: five ruins on the towers tab, before and now.
        d = castle.data.description
        dx, dy, dw = struct.unpack('<iii', mem.read(d + 4, 12))
        print('  %s: castle description line at (%d, %d), %d wide' % (exe_name, dx, dy, dw))
        keep = castle.keep_outs(11)
        w, h = panel_box(*CASTLE_PANELS[11]['ruins'])
        for screen in (1024, 1920, 2560):
            edges = castle.screen(screen, 11)
            castle.fresh()
            # As 1.0.63 placed it: centred on the screen, 50 left (K.PANEL_SHIFT[11]), bottom 444.
            old = dict(x=(screen - w) // 2 - edges['origin'] - 50, y=layout.PANEL_BOTTOM - h, w=w, h=h)
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

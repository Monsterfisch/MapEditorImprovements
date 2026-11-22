"""The resource grid, frame by frame, on both executables.

`reference-1.0.0/` is Resource Grid Overlay as 1.0.0 shipped it: lua clipped every line each
frame and the game's own `PencilRenderCore::drawLine` drew them. Since then the frame routine is
assembly, the lines are only worked out again when the view changes, and the module writes the
pixels itself; the grid now lives in Map Editor Improvements and runs from the map drawing's
patch site it shares with the editor's frame work. The picture must not have changed, so every
scenario here draws a frame both ways and the map surface has to come out byte for byte the
same - which also keeps the reference as the definition of "right" for any later rewrite. On top
of that the build under test must leave every register as it found it, must not write outside
the surface, the stack and its own allocations, and must only enter lua when the view it last
drew for has actually changed."""
import sys, time
from host import *

OLD = REFERENCE
NEW = MODULE

# The overlay off: jump into the shared site, call the grid's routine, its compare, jump and
# return, both loads, jump back. One call and return more than the overlay had on its own site.
OFF_COST = 8
OPCODE_JMP, OPCODE_LOAD_EAX, OPCODE_LOAD_ECX = 0xE9, 0xA1, 0x8B

SMALL = {'view+88': 14, 'view+8c': 34}
SMALL_OUT = {'view+90': 1, 'view+88': 22, 'view+8c': 52}


def rt(base, **extra):
    d = dict(base)
    for k, v in extra.items():
        d[k.replace('_', '+', 1) if k.startswith(('view_', 'win_')) else k] = v
    return d


SCENARIOS = [
    ('zoomed in', rt(SMALL), None, None),
    ('zoomed out', rt(SMALL_OUT), None, None),
    ('zoomed out + row bias', rt(SMALL_OUT, view_94=1), None, None),
    ('zoomed in + row bias', rt(SMALL, view_94=1), None, None),
    ('zoomed out, far left', rt(SMALL_OUT, view_78=0, view_7c=0), None, None),
    ('rotation 6', rt(SMALL, orient=6), None, None),
    ('rotation 4', rt(SMALL, orient=4), None, None),
    ('rotation 2', rt(SMALL, orient=2), None, None),
    ('rotation 6 zoomed out', rt(SMALL_OUT, orient=6), None, None),
    ('rotation 2 zoomed out', rt(SMALL_OUT, orient=2), None, None),
    ('bogus rotation', rt(SMALL, orient=3), None, None),
    ('565 pixel format', rt(SMALL, win_54=0x565), None, None),
    ('camera at origin', rt(SMALL, view_78=0, view_7c=0), None, None),
    ('camera off the map', rt(SMALL, view_78=12000, view_7c=3000), None, None),
    ('negative camera', rt(SMALL, view_78=-100, view_7c=-40), None, None),
    ('bottom edge of map', rt(SMALL, view_78=3200, view_7c=6200), None, None),
    ('right edge of map', rt(SMALL, view_78=6300, view_7c=3000), None, None),
    ('odd camera values', rt(SMALL, view_78=3217, view_7c=811), None, None),
    ('normal game allowed', rt(SMALL, gm=3), {'outside_editor': True}, None),
    ('normal game editor-only', rt(SMALL, gm=3), {'outside_editor': False}, None),
    ('editor, editor-only', rt(SMALL), {'outside_editor': False}, None),
    ('no rotation lines', rt(SMALL), {'rotation_lines': False}, None),
    ('nonsense config', rt(SMALL), {'key': 'letter_q', 'grid_colour': 'puce'}, None),
    ('normal view hides', rt(SMALL, flatA=0), None, None),
    ('normal view (B) hides', rt(SMALL, flatB=0), None, None),
    ('V view hides', rt(SMALL, vflag=0), None, None),
    ('V view, gate off', rt(SMALL, vflag=0), {'hide_in_v_view': False}, None),
    ('normal view, gate off', rt(SMALL, flatA=0), {'flattened_only': False}, None),
    ('mine boxes off', rt(SMALL), {'mine_boxes': False}, None),
    ('mine footprint 3', rt(SMALL), None, {'mine_size': 3}),
    ('mine footprint 5', rt(SMALL_OUT), None, {'mine_size': 5}),
    ('colours changed', rt(SMALL), {'grid_colour': 'black', 'rotation_colour': 'red',
                                    'mine_colour': 'white'}, None),
    ('origin override 150,250', rt(SMALL), None, {'origin_x': 150, 'origin_y': 250}),
    ('boundary nudge', rt(SMALL), None, {'boundary_x': 12, 'boundary_y': -9}),
    ('boundary nudge zoomed out', rt(SMALL_OUT), None, {'boundary_x': 12, 'boundary_y': -9}),
    ('junk tune values', rt(SMALL), None, {'origin_x': 'nope', 'boundary_y': None}),
    ('tiny render area', rt(SMALL, view_88=1, view_8c=1), None, None),
    ('empty render area', rt(SMALL, view_88=-3, view_8c=-60), None, None),
]


class Pair:
    def __init__(self, exe_path, runtime=None, overlay=None, tune=None, **new_only):
        """`new_only` goes to the build under test alone: Custom Hotkeys, other modules, the
        editor's frame routine."""
        self.old = Host(OLD, exe_path, runtime, overlay, tune)
        self.new = Host(NEW, exe_path, runtime, overlay, tune, **new_only)
        self.control = None

    def put(self, key, value):
        self.old.put(key, value)
        self.new.put(key, value)

    def press(self, **kw):
        self.old.press(**kw)
        self.new.press(**kw)

    def screen(self, ebp):
        self.old.screen(ebp)
        self.new.screen(ebp)

    def frame(self):
        for h in (self.old, self.new):
            h.clear_surface()
        lua_before = self.new.lua_calls
        old_count = self.old.frame()
        log = self.new.m.write_log = []
        new_count = self.new.frame()
        self.new.m.write_log = None
        bad = [(a, n) for a, n in log if not allowed(self.new, a, n)]
        do, po = self.old.surface_digest()
        dn, pn = self.new.surface_digest()
        return {'same': do == dn, 'painted': po, 'old': old_count, 'new': new_count,
                'lua': self.new.lua_calls - lua_before, 'bad_writes': bad}


def allowed(host, address, size):
    if SURFACE <= address and address + size <= SURFACE + SURFACE_BYTES:
        return True
    if STACK_TOP - 0x10000 <= address and address + size <= STACK_TOP:
        return True
    if HEAP <= address < host.heap:          # the module's own allocations
        return True
    return False


failures = 0


def expect(label, ok):
    global failures
    failures += not ok
    print('  %-4s %s' % ('ok' if ok else 'FAIL', label))


def check(label, result, expect_painted=None, expect_lua=None):
    global failures
    ok = result['same'] and not result['bad_writes']
    if expect_painted is not None:
        ok = ok and ((result['painted'] > 0) == expect_painted)
    if expect_lua is not None:
        ok = ok and result['lua'] == expect_lua
    failures += not ok
    print('  %-4s %-34s px=%-6d old=%-8d new=%-7d lua=%d%s' % (
        'ok' if ok else 'FAIL', label, result['painted'], result['old'], result['new'],
        result['lua'], '' if not result['bad_writes'] else ' BAD WRITES %r' % result['bad_writes'][:3]))


def main():
    global failures
    started = time.time()
    for exe_path, label in ((VAN_PATH, 'plain'), (EXT_PATH, 'extreme')):
        print('==', label)

        for name, runtime, overlay, tune in SCENARIOS:
            pair = Pair(exe_path, runtime, overlay, tune)
            pair.press()
            check(name, pair.frame())

        print('  -- one session, frame by frame')
        p = Pair(exe_path, rt(SMALL))
        check('off', p.frame(), False, 0)
        p.press(esi=0x48)
        check('other key', p.frame(), False, 0)
        p.press(ecx=0x40000000)
        check('auto-repeat', p.frame(), False, 0)
        p.press()
        check('on: first frame works it out', p.frame(), True, 1)
        check('on: static camera replays', p.frame(), True, 0)
        check('on: static again', p.frame(), True, 0)
        p.put('view+78', 3232)
        check('scrolled one tile', p.frame(), True, 1)
        check('scrolled, static', p.frame(), True, 0)
        p.put('view+7c', 840)
        check('scrolled down', p.frame(), True, 1)
        p.put('view+90', 1); p.put('view+88', 22); p.put('view+8c', 52)
        check('zoomed out', p.frame(), True, 1)
        p.put('orient', 6)
        check('rotated', p.frame(), True, 1)
        p.put('win+54', 0x565)
        check('pixel format changed', p.frame(), True, 1)
        p.put('view+94', 1)
        check('row bias on', p.frame(), True, 1)
        p.put('flatA', 0)
        check('left flattened view', p.frame(), False, 0)
        p.put('view+78', 3264)
        check('scrolled while hidden', p.frame(), False, 0)
        p.put('flatA', 1)
        check('back to flattened view', p.frame(), True, 1)
        check('flattened, static', p.frame(), True, 0)
        p.put('vflag', 0)
        check('V view', p.frame(), False, 0)
        p.put('vflag', 1)
        check('out of V view', p.frame(), True, 0)
        p.screen(0x0E)
        check('editor build menu keeps it', p.frame(), True, 0)
        p.screen(0x29)
        check('main menu turns it off', p.frame(), False, 0)
        p.press()
        check('on again, same view', p.frame(), True, 0)
        p.press()
        check('off again', p.frame(), False, 0)
        p.put('view+78', 3296)
        p.press()
        check('on again, moved while off', p.frame(), True, 1)

        print('  -- editor only')
        p = Pair(exe_path, rt(SMALL, gm=3), {'outside_editor': False})
        p.press()
        check('key ignored outside the editor', p.frame(), False, 0)
        p.put('gm', 1)
        p.press()
        check('key works in the editor', p.frame(), True, 1)
        p.put('gm', 3)
        check('left the editor', p.frame(), False, 0)
        p.put('gm', 1)
        check('back in, stays off', p.frame(), False, 0)

        print('  -- register and memory transparency with the overlay off')
        h = Host(NEW, exe_path, rt(SMALL))
        h.m.write_log = []
        n = h.frame()
        # The only write: the return address of the shared site's call into the grid's routine,
        # in the four bytes below the stack pointer.
        writes = list(h.m.write_log)
        clean = writes == [(STACK_TOP - 4, 4)]
        print('  %-4s off costs %d instructions, writes %s' % (
            'ok' if n == OFF_COST and clean else 'FAIL', n,
            'only the return address' if clean else repr(writes)))
        failures += not (n == OFF_COST and clean)
        section_end = h.lua.eval('require("editor.memory").sectionEnd')(h.renderSite)
        code = [vs + max(vsz, rsz) for vs, vsz, po, rsz, name in h.E.secs if vs <= h.renderSite < vs + max(vsz, rsz)]
        expect('uniqueness re-scans end with the code section (0x%X)' % (section_end or 0),
               code and section_end == code[0])

        print('  -- Custom Hotkeys with module actions')
        p = Pair(exe_path, rt(SMALL), hotkeys=True)
        actions = p.new.hotkeys.actions
        editor = actions['ext.map-editor-improvements.grid-toggle']
        game = actions['ext.map-editor-improvements.grid-toggle-game']
        expect('no Alt key redirect with the action API', p.new.keySite not in p.new.detours)
        expect('editor action, Alt + G suggested', editor is not None and editor.context.kind == 'editor'
               and editor.default.scan == 0x22 and editor.default.extended is False
               and editor.default.mods == 4)
        expect('game action, unbound', game is not None and game.context.kind == 'world'
               and game.default is False)
        check('off', p.frame(), False, 0)
        p.press()
        check('action on', p.frame(), True, 1)
        check('action on, static', p.frame(), True, 0)
        p.screen(0x29)
        check('main menu turns it off', p.frame(), False, 0)
        p.press()
        check('action on again', p.frame(), True, 0)
        p.press()
        check('action off', p.frame(), False, 0)
        h = Host(NEW, exe_path, rt(SMALL), {'outside_editor': False}, hotkeys=True)
        expect('editor only: no game action',
               h.hotkeys.actions['ext.map-editor-improvements.grid-toggle-game'] is None)
        h = Host(NEW, exe_path, rt(SMALL), {'key': 'f4'}, hotkeys=True)
        expect('Alt + F4 is Windows\': no suggestion',
               h.hotkeys.actions['ext.map-editor-improvements.grid-toggle'].default is False)
        h = Host(NEW, exe_path, rt(SMALL), {'key': 'numpad_divide'}, hotkeys=True)
        d = h.hotkeys.actions['ext.map-editor-improvements.grid-toggle'].default
        expect('numpad / suggested as an extended key', d.scan == 0x35 and d.extended is True)
        h = Host(NEW, exe_path, rt(SMALL, gm=3), {'outside_editor': False}, hotkeys=True)
        expect('editor action refused outside the editor',
               h.action('ext.map-editor-improvements.grid-toggle') is False)

        print('  -- the shared site with the editor\'s frame work')
        p = Pair(exe_path, rt(SMALL), editor_routine=True)
        expect('one jump over both loads', p.new.site_bytes(16, 1)[0] == OPCODE_JMP
               and p.new.site_bytes(21, 6) == bytes([0x90] * 6))
        p.press()
        check('grid drawn with the editor routine', p.frame(), True, 1)
        check('static', p.frame(), True, 0)
        expect('editor routine ran once a frame', p.new.m.u32(p.new.editorCalls) == 2)

        print('  -- grid off, the editor routine alone')
        h = Host(NEW, exe_path, rt(SMALL), editor_routine=True, grid=False)
        h.frame()
        expect('first load left for others', h.site_bytes(16, 1)[0] == OPCODE_LOAD_EAX
               and h.site_bytes(21, 1)[0] == OPCODE_JMP)
        expect('editor routine runs', h.m.u32(h.editorCalls) == 1)
        expect('nothing else changed', not h.detours)

        print('  -- Resource Grid Overlay still active, enabled after this module')
        h = Host(NEW, exe_path, rt(SMALL), modules=['resource-grid-overlay'], editor_routine=True)
        expect('grid left to that module', h.mod.gridOn is False and not h.detours)
        expect('it is named in the log', any('Resource Grid Overlay' in line for line in h.logs))
        expect('whole call site untouched while modules are enabled', h.mod.committed == 'afterInit'
               and h.site_bytes(16, 1)[0] == OPCODE_LOAD_EAX and h.site_bytes(21, 1)[0] == OPCODE_LOAD_ECX)
        h.fire_after_init()
        expect('second load taken at afterInit', h.mod.problem is None
               and h.site_bytes(16, 1)[0] == OPCODE_LOAD_EAX and h.site_bytes(21, 1)[0] == OPCODE_JMP)
        h.frame()
        expect('editor routine runs', h.m.u32(h.editorCalls) == 1)

        print('  -- Resource Grid Overlay still active, enabled before this module')
        h = Host(NEW, exe_path, rt(SMALL), modules=['resource-grid-overlay'], editor_routine=True,
                 first_load_taken=True)
        h.fire_after_init()
        expect('its jump kept, the second load taken', h.mod.gridOn is False and h.mod.problem is None
               and h.site_bytes(16, 5) == bytes([0xE9, 0, 0, 0, 0]) and h.site_bytes(21, 1)[0] == OPCODE_JMP)

        print('  -- first load already taken by another module')
        h = Host(NEW, exe_path, rt(SMALL), first_load_taken=True, editor_routine=True)
        expect('grid refuses, other module\'s jump kept', h.mod.gridOn is False
               and h.site_bytes(16, 5) == bytes([0xE9, 0, 0, 0, 0]))
        expect('editor routine takes the second load', h.site_bytes(21, 1)[0] == OPCODE_JMP)

    print('\n%d failures, %.0fs' % (failures, time.time() - started))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

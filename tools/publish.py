r"""Publish module/ into the game's module folder under the version in definition.yml.

The UCP GUI notices a new version on F5 and moves the pin with its apply button, so a build
is always *copied* to a new folder and older folders are left alone until they are safe to
remove. `ucp-config.yml` is never written here - the apply button owns it - but it is read,
because the version it pins must still exist on disk. Deleting a pinned folder is what makes
the GUI refuse the whole config with MISSING_DEPENDENCIES.

    python tools/publish.py                    # copy module/ to map-editor-improvements-<version>
    python tools/publish.py --bump             # raise the last version slot first
    python tools/publish.py --keep             # publish and clear nothing
    python tools/publish.py --game "C:\path"   # publish into this game folder

The game folder (the one holding ucp-config.yml and ucp/modules) comes from --game, or else
from publish-config.json next to this script. The script creates that file the first time it
runs, and stores the --game path in it when it holds none yet, so after one run with --game
the plain commands above are enough. To use another game folder later, pass --game again (it
is used for that run only) or edit the file. The file is personal and not committed.
"""
import json, os, re, shutil, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
HERE = os.path.dirname(TOOLS)
MODULE = os.path.join(HERE, 'module')
SETTINGS = os.path.join(TOOLS, 'publish-config.json')
NAME = 'map-editor-improvements'


def game_folder():
    """The game folder: --game if given, else the one in publish-config.json. Creates the file
    when it is missing and stores --game in it when it has no game folder yet."""
    settings = {}
    if os.path.isfile(SETTINGS):
        with open(SETTINGS, encoding='utf-8') as f:
            settings = json.load(f)
    given = None
    if '--game' in sys.argv:
        at = sys.argv.index('--game')
        if at + 1 >= len(sys.argv):
            sys.exit('--game needs the game folder after it')
        given = sys.argv[at + 1]
    if given and not settings.get('game'):
        settings['game'] = given
        print('stored the game folder in', os.path.basename(SETTINGS))
    if not os.path.isfile(SETTINGS) or (given and settings['game'] == given):
        settings.setdefault('game', '')
        with open(SETTINGS, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(settings, f, indent=2)
            f.write('\n')
    game = given or settings.get('game')
    if not game:
        sys.exit('no game folder: run once with --game "<the game folder>" (it is then stored in %s)'
                 % os.path.basename(SETTINGS))
    if not os.path.isdir(os.path.join(game, 'ucp', 'modules')):
        sys.exit('%s has no ucp/modules folder - is it the game folder with UCP3 installed?' % game)
    return game


GAME = game_folder()
MODULES = os.path.join(GAME, 'ucp', 'modules')
CONFIG = os.path.join(GAME, 'ucp-config.yml')


def version(text):
    return tuple(int(part) for part in text.split('.'))


def read_version():
    path = os.path.join(MODULE, 'definition.yml')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    return re.search(r'^version:\s*(\S+)', text, re.M).group(1), path, text


def bump():
    current, path, text = read_version()
    parts = current.split('.')
    parts[-1] = str(int(parts[-1]) + 1)
    new = '.'.join(parts)
    text = re.sub(r'^version:\s*\S+', 'version: ' + new, text, count=1, flags=re.M)
    text = re.sub(r'^(\s+version:\s*)\S+', r'\g<1>' + new, text, count=1, flags=re.M)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    description = os.path.join(MODULE, 'locale', 'description-en.md')
    with open(description, encoding='utf-8') as f:
        text = f.read()
    text = re.sub(r'^\*\*Version\*\*: \S+', '**Version**: ' + new, text, count=1, flags=re.M)
    with open(description, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('%s -> %s' % (current, new))
    return new


def pinned():
    """Every version of this module the GUI's config asks for. Read only."""
    if not os.path.isfile(CONFIG):
        return set()
    with open(CONFIG, encoding='utf-8', errors='replace') as f:
        text = f.read()
    found = re.findall(r'-\s*extension:\s*%s\s*\n\s*version:\s*(\S+)' % re.escape(NAME), text)
    return {version(v) for v in found}


def installed():
    found = []
    for entry in os.listdir(MODULES):
        if entry.startswith(NAME + '-') and os.path.isdir(os.path.join(MODULES, entry)):
            tail = entry[len(NAME) + 1:]
            if re.fullmatch(r'\d+(\.\d+)*', tail):
                found.append((version(tail), entry))
    return sorted(found)


def main():
    current = bump() if '--bump' in sys.argv else read_version()[0]
    target = os.path.join(MODULES, '%s-%s' % (NAME, current))
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(MODULE, target)
    print('published', os.path.basename(target))

    held = pinned()
    if held:
        print('the config pins', ', '.join('%s' % '.'.join(map(str, v)) for v in sorted(held)))
    if '--keep' in sys.argv:
        print('installed:', ', '.join(entry for _, entry in installed()))
        return

    # What stays: this build, whatever the config still pins - deleting that is what gives
    # the GUI MISSING_DEPENDENCIES and stops it loading at all - and the newest build
    # besides this one, so there is always something to fall back to. Everything else goes,
    # because the GUI lists every folder it finds.
    keep = {version(current)} | held
    others = [v for v, _ in installed() if v != version(current)]
    if others:
        keep.add(max(others))
    for v, entry in installed():
        if v not in keep:
            shutil.rmtree(os.path.join(MODULES, entry))
            print('cleared', entry)
    print('installed:', ', '.join(entry for _, entry in installed()))


if __name__ == '__main__':
    main()

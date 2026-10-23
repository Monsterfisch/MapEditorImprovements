"""Make the button pictures in module/images from the game's graphics.

    python tools/make_icons.py [gravel source png]

apple*.png: the game's apple tree (tree_apple.gm1, picture 51, ripe apples) shrunk onto
parchment cut from the editor's own tree icon (mapedit_buttons.gm1, picture 115), with the
editor icons' cyan glow for the hover and selected states.

gravel*.png: the three states stacked top to bottom in one picture (normal, hover,
selected), cut apart at the transparent rows between them.

The pictures are only a start; replace them with your own (same names) and the module uses
those.
"""
import os, struct, sys
from PIL import Image, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(HERE, 'module', 'images')
GM = r'H:\steam\steamapps\common\Stronghold Crusader Extreme UCP3 new\gm'
ICON_SIZE = (64, 72)


def load_gm(name):
    data = open(os.path.join(GM, name), 'rb').read()
    header = struct.unpack('<22I', data[:88])
    count, kind = header[3], header[5]
    palette = struct.unpack('<256H', data[88:88 + 512])
    position = 88 + 5120
    offsets = struct.unpack('<%dI' % count, data[position:position + 4 * count])
    position += 4 * count
    sizes = struct.unpack('<%dI' % count, data[position:position + 4 * count])
    position += 4 * count
    heads = [struct.unpack('<HH', data[position + 16 * i:position + 16 * i + 4]) for i in range(count)]
    base = position + 16 * count
    return data, kind, palette, offsets, sizes, heads, base


def colour(value):
    return ((value >> 10) & 31) << 3, ((value >> 5) & 31) << 3, (value & 31) << 3, 255


def frame(gm, picture):
    data, kind, palette, offsets, sizes, heads, base = gm
    index = picture - 1
    width, height = heads[index]
    image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    pixels = image.load()
    stream = data[base + offsets[index]:base + offsets[index] + sizes[index]]
    wide = kind != 2                      # 16-bit pixels, else palette indices
    i = x = y = 0
    while i < len(stream):
        token = stream[i]
        i += 1
        n, flag = (token & 0x1F) + 1, token >> 5
        if flag == 0:
            for _ in range(n):
                if wide:
                    value = struct.unpack_from('<H', stream, i)[0]
                    i += 2
                else:
                    value = palette[stream[i]]
                    i += 1
                if x < width and y < height:
                    pixels[x, y] = colour(value)
                x += 1
        elif flag == 4:
            x, y = 0, y + 1
        elif flag == 2:
            if wide:
                value = struct.unpack_from('<H', stream, i)[0]
                i += 2
            else:
                value = palette[stream[i]]
                i += 1
            for _ in range(n):
                if x < width and y < height:
                    pixels[x, y] = colour(value)
                x += 1
        elif flag == 1:
            x += n
        else:
            break
    return image


def parchment(size):
    """Tiles a plain corner of the editor's tree icon over the whole picture."""
    icon = frame(load_gm('mapedit_buttons.gm1'), 115)
    patch = icon.crop((2, icon.height - 18, 18, icon.height - 2))
    result = Image.new('RGBA', size)
    for top in range(0, size[1], 16):
        for left in range(0, size[0], 16):
            tile = patch
            if (left // 16 + top // 16) % 2:
                tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
            result.paste(tile, (left, top))
    return result


def glow(image, sprite_mask, strength):
    """The editor icons' cyan glow around the drawing."""
    ring = sprite_mask.filter(ImageFilter.MaxFilter(3))
    ring = ImageChops.subtract(ring, sprite_mask).point(lambda v: v * strength // 255)
    cyan = Image.new('RGBA', image.size, (110, 235, 225, 255))
    result = image.copy()
    result.paste(cyan, (0, 0), ring)
    return result


def apple():
    sprite = frame(load_gm('tree_apple.gm1'), 51)
    sprite = sprite.crop(sprite.getbbox())
    scale = min((ICON_SIZE[0] - 8) / sprite.width, (ICON_SIZE[1] - 8) / sprite.height)
    sprite = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
                           Image.LANCZOS)
    alpha = sprite.split()[3].point(lambda v: 255 if v > 96 else 0)
    sprite.putalpha(alpha)
    base = parchment(ICON_SIZE)
    left = (ICON_SIZE[0] - sprite.width) // 2
    top = ICON_SIZE[1] - 4 - sprite.height
    mask = Image.new('L', ICON_SIZE, 0)
    mask.paste(alpha, (left, top))
    normal = base.copy()
    normal.paste(sprite, (left, top), alpha)
    normal.save(os.path.join(IMAGES, 'apple.png'))
    glow(normal, mask, 110).save(os.path.join(IMAGES, 'apple_hover.png'))
    glow(normal, mask, 210).save(os.path.join(IMAGES, 'apple_selected.png'))


def gravel(source):
    image = Image.open(source).convert('RGBA')
    alpha = image.split()[3]
    rows = [any(alpha.getpixel((x, y)) for x in range(image.width)) for y in range(image.height)]
    parts, start = [], None
    for y, filled in enumerate(rows + [False]):
        if filled and start is None:
            start = y
        elif not filled and start is not None:
            parts.append((start, y))
            start = None
    if len(parts) != 3:
        raise SystemExit('%s: expected three pictures stacked top to bottom, found %d' % (source, len(parts)))
    for name, (top, bottom) in zip(('gravel', 'gravel_hover', 'gravel_selected'), parts):
        part = image.crop((0, top, image.width, bottom))
        part.crop(part.getbbox()).save(os.path.join(IMAGES, name + '.png'))


if __name__ == '__main__':
    os.makedirs(IMAGES, exist_ok=True)
    apple()
    if len(sys.argv) > 1:
        gravel(sys.argv[1])
    print('written to', IMAGES)

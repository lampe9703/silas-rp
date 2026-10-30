"""比较字体里「关」和「于」的实际字形宽度，判断是不是字体本身画得窄。"""
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont, TTCollection

TARGET = {'关': 0x5173, '于': 0x4E8E, '数': 0x6570}


def measure(font, label):
    cmap = font.getBestCmap()
    upm = font['head'].unitsPerEm
    hmtx = font['hmtx']
    glyph_set = font.getGlyphSet()

    print(f'\n--- {label} (unitsPerEm={upm}) ---')
    adv = {}
    ink = {}
    for ch, cp in TARGET.items():
        gname = cmap.get(cp)
        if gname is None:
            print(f'  {ch} 缺字')
            continue
        adv[ch] = hmtx[gname][0]
        pen = BoundsPen(glyph_set)
        glyph_set[gname].draw(pen)
        if pen.bounds is None:
            ink[ch] = 0
        else:
            x_min, _, x_max, _ = pen.bounds
            ink[ch] = x_max - x_min

    for ch in TARGET:
        if ch in adv:
            print(f'  {ch}: 前进宽={adv[ch]:>5}  墨迹宽={ink[ch]:>5}  '
                  f'墨迹/前进={ink[ch] / adv[ch]:.2f}')
    if '关' in adv and '于' in adv:
        print(f'  → 关/于 墨迹比 = {ink["关"] / ink["于"]:.2f}')


def main(path):
    if path.lower().endswith('.ttc'):
        coll = TTCollection(path, lazy=True)
        for i, font in enumerate(coll.fonts):
            name = font['name']
            try:
                family = name.getDebugName(1)
                sub = name.getDebugName(2)
                full = name.getDebugName(4)
            except Exception:
                family = sub = full = '?'
            print(f'[TTC #{i}] family={family} sub={sub} full={full}')
            measure(font, f'#{i} {family}')
    else:
        font = TTFont(path, lazy=True)
        measure(font, path)


if __name__ == '__main__':
    main(sys.argv[1])

"""把霞鹜文楷 LXGW WenKai Regular 子集化，控制内置体积。

码位策略：CJK 基本区全量（U+4E00–U+9FFF，20992 字）+ 常用符号区间。

历史：v1.0.0 之前只取 GB2312（7756 字，3.4MB），生僻字与人名用字会掉到
系统字体上，界面上看起来像「字体没换全」。现在放宽到整个基本区（12.2MB），
代价是安装包变大，换来的是正文里几乎不会再出现混排字体。
"""
import os

from fontTools import subset
from fontTools.ttLib import TTFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(BASE, '..', '_tmp_font', 'LXGWWenKai-Regular.ttf')
DST = os.path.join(BASE, 'assets', 'fonts', 'SilasWenKai-Regular.ttf')

# 霞鹜文楷的 OFL 声明了保留字体名（Reserved Font Name）：'霞鹜'、'LXGW' 等。
# 子集化属于「修改版本」，按 OFL 规定不得继续使用保留名，故改名。
NEW_FAMILY = 'Silas WenKai'
NEW_FULL = 'Silas WenKai Regular'
NEW_PS = 'SilasWenKai-Regular'
NEW_VERSION = 'Version 1.530 (subset of LXGW WenKai)'


def cjk_chars():
    """CJK 基本区全部码位（含未分配位置，subsetter 会自动跳过缺失字形）。"""
    return set(range(0x4E00, 0xA000))


def main():
    chars = cjk_chars()
    print('CJK 基本区码位:', len(chars))

    ranges = [
        (0x0020, 0x007E), (0x00A0, 0x00FF), (0x2000, 0x206F),
        (0x20A0, 0x20BF), (0x2190, 0x21FF), (0x2200, 0x22FF),
        (0x2460, 0x24FF), (0x2500, 0x257F), (0x25A0, 0x25FF),
        (0x2600, 0x26FF), (0x3000, 0x303F), (0xFE30, 0xFE4F),
        (0xFF00, 0xFFEF),
    ]
    unicodes = set()
    for lo, hi in ranges:
        unicodes.update(range(lo, hi + 1))
    unicodes.update(chars)
    for c in '·—…“”‘’《》〈〉「」『』【】％℃±×÷≈≤≥√∞':
        unicodes.add(ord(c))

    print('目标码位:', len(unicodes))

    font = TTFont(SRC)

    opts = subset.Options()
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ['DSIG']

    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)

    # 3) 改名：避免使用 OFL 保留字体名
    name_table = font['name']
    replacements = {
        1: NEW_FAMILY,          # Family
        3: f'{NEW_VERSION};SilasWenKai',  # Unique ID
        4: NEW_FULL,            # Full name
        6: NEW_PS,              # PostScript name
        16: NEW_FAMILY,         # Typographic Family
        17: NEW_FULL,           # Typographic Subfamily
    }
    for record in name_table.names:
        if record.nameID in replacements:
            record.string = replacements[record.nameID].encode(record.getEncoding())
        elif record.nameID == 5:  # Version string
            record.string = NEW_VERSION.encode(record.getEncoding())
    print('已重命名字体:', NEW_FAMILY)

    font.save(DST)
    src_mb = os.path.getsize(SRC) / 1024 / 1024
    dst_mb = os.path.getsize(DST) / 1024 / 1024
    print(f'{src_mb:.1f}MB -> {dst_mb:.1f}MB')


if __name__ == '__main__':
    main()

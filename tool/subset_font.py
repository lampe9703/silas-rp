"""把 Noto Sans SC 可变字体实例化为 Regular 并子集化，控制内置体积。"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SRC = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\ai_roleplay\assets\fonts\NotoSansSC-VF.ttf"
DST = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\ai_roleplay\assets\fonts\NotoSansSC-Regular.ttf"


def gb2312_chars():
    out = set()
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                out.add(bytes([hi, lo]).decode('gb2312'))
            except UnicodeDecodeError:
                pass
    return out


def main():
    chars = gb2312_chars()
    print('GB2312 汉字/符号:', len(chars))

    # 常用符号、标点、拉丁、全角、箭头、数学符号
    ranges = [
        (0x0020, 0x007E), (0x00A0, 0x00FF), (0x2000, 0x206F),
        (0x20A0, 0x20BF), (0x2190, 0x21FF), (0x2200, 0x22FF),
        (0x2500, 0x257F), (0x25A0, 0x25FF), (0x2600, 0x26FF),
        (0x3000, 0x303F), (0xFE30, 0xFE4F), (0xFF00, 0xFFEF),
    ]
    unicodes = set()
    for lo, hi in ranges:
        unicodes.update(range(lo, hi + 1))
    unicodes.update(ord(c) for c in chars)
    # 界面里会出现的几个特殊字符
    for c in '·—…“”‘’《》〈〉「」『』【】％℃±×÷≈≤≥√∞':
        unicodes.add(ord(c))

    print('目标码位:', len(unicodes))

    font = TTFont(SRC)
    print('原始 表:', 'fvar' in font)

    # 1) 实例化成静态 Regular（去掉 wght 轴，体积立降）
    if 'fvar' in font:
        instantiateVariableFont(font, {'wght': 400}, inplace=True)
        print('已实例化为 wght=400')

    # 2) 子集化
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

    font.save(DST)
    src_mb = os.path.getsize(SRC) / 1024 / 1024
    dst_mb = os.path.getsize(DST) / 1024 / 1024
    print(f'{src_mb:.1f}MB -> {dst_mb:.1f}MB')


if __name__ == '__main__':
    main()

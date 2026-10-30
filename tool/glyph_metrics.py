"""分析截图里汉字的墨迹宽度与笔画粗细，用来区分「字形本身窄」和「渲染变细」。"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    pos = 8
    width = height = bitdepth = colortype = 0
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b'IHDR':
            width, height, bitdepth, colortype = struct.unpack('>IIBB', body[:10])
        elif tag == b'IDAT':
            idat += body
        elif tag == b'IEND':
            break
        pos += 12 + length
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


def analyze(path, y0, y1, threshold=None):
    w, h, ch, px = read_png(path)
    y1 = min(y1, h)

    # 自动判断深浅底：取四角亮度中位数当背景
    corners = []
    for cy in (0, h - 1):
        for cx in (0, w - 1):
            i = (cy * w + cx) * ch
            corners.append((px[i] + px[i + 1] + px[i + 2]) / 3)
    corners.sort()
    bg = corners[len(corners) // 2]
    dark_bg = bg < 128

    def ink(x, y):
        i = (y * w + x) * ch
        lum = (px[i] + px[i + 1] + px[i + 2]) / 3
        return (lum - bg) > 60 if dark_bg else (bg - lum) > 60

    cols = []
    for x in range(w):
        n = sum(1 for y in range(y0, y1) if ink(x, y))
        cols.append(n)

    # 按列切字
    glyphs = []
    inside = False
    start = 0
    for x, n in enumerate(cols):
        if n > 0 and not inside:
            inside, start = True, x
        elif n == 0 and inside:
            inside = False
            if x - start > 4:
                glyphs.append((start, x))
    if inside:
        glyphs.append((start, w))

    print(f'{path}  y[{y0},{y1})  切出 {len(glyphs)} 个字')
    for idx, (x0, x1) in enumerate(glyphs):
        ys = [y for y in range(y0, y1) if any(ink(x, y) for x in range(x0, x1))]
        if not ys:
            continue
        top, bot = min(ys), max(ys)
        # 笔画粗细：统计每行连续墨迹段的长度中位数
        runs = []
        for y in range(top, bot + 1):
            run = 0
            for x in range(x0, x1):
                if ink(x, y):
                    run += 1
                elif run:
                    runs.append(run); run = 0
            if run:
                runs.append(run)
        runs.sort()
        med = runs[len(runs) // 2] if runs else 0
        ink_count = sum(1 for y in range(top, bot + 1) for x in range(x0, x1) if ink(x, y))
        print(f'  #{idx} x[{x0},{x1}) 宽={x1 - x0} 高={bot - top + 1} '
              f'墨迹={ink_count} 墨迹占框比={ink_count / ((x1 - x0) * (bot - top + 1)):.2f} '
              f'笔画中位={med}')


if __name__ == '__main__':
    analyze(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))

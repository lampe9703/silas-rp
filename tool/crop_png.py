"""纯标准库的 PNG 裁剪 + 放大（没有 Pillow 时用）。"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
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
    assert bitdepth == 8, bitdepth
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
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


def write_png(path, width, height, channels, pixels):
    colortype = {1: 0, 3: 2, 4: 6}[channels]
    raw = bytearray()
    stride = width * channels
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        c = tag + body
        return struct.pack('>I', len(body)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, colortype, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))
    open(path, 'wb').write(png)


def crop_scale(src, dst, x, y, w, h, scale=4):
    width, height, ch, px = read_png(src)
    x = max(0, min(x, width - 1))
    y = max(0, min(y, height - 1))
    w = min(w, width - x)
    h = min(h, height - y)
    out_w, out_h = w * scale, h * scale
    out = bytearray(out_w * out_h * ch)
    for oy in range(out_h):
        sy = y + oy // scale
        for ox in range(out_w):
            sx = x + ox // scale
            si = (sy * width + sx) * ch
            di = (oy * out_w + ox) * ch
            out[di:di + ch] = px[si:si + ch]
    write_png(dst, out_w, out_h, ch, out)
    print(f'{dst}: {out_w}x{out_h} (src {width}x{height}, ch={ch})')


if __name__ == '__main__':
    crop_scale(sys.argv[1], sys.argv[2],
               int(sys.argv[3]), int(sys.argv[4]),
               int(sys.argv[5]), int(sys.argv[6]),
               int(sys.argv[7]) if len(sys.argv) > 7 else 4)

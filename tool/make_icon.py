"""生成 Android 启动图标（纯标准库，无第三方依赖）。

设计：圆角方形渐变底 + 白色对话气泡（含尾巴）+ 三个圆点。
用 SDF（有符号距离场）计算覆盖率做抗锯齿，按 4 倍超采样渲染再降采样。
"""
import math
import os
import struct
import zlib

TOP = (124, 108, 240)      # #7C6CF0
BOTTOM = (82, 64, 201)     # #5240C9
DOT = (95, 79, 216)        # 圆点颜色，比气泡底略深


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def sdf_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def sdf_rot_rect(px, py, cx, cy, hw, hh, r, angle):
    dx, dy = px - cx, py - cy
    ca, sa = math.cos(-angle), math.sin(-angle)
    lx, ly = dx * ca - dy * sa, dx * sa + dy * ca
    return sdf_round_rect(lx, ly, 0.0, 0.0, hw, hh, r)


def coverage(sdf, soft=1.0):
    return clamp(0.5 - sdf / soft)


def blend(dst, src, a):
    return tuple(int(round(dst[i] * (1 - a) + src[i] * a)) for i in range(3))


def render(size, scale=4):
    """在 size*scale 的画布上渲染后做盒式降采样"""
    n = size * scale
    acc = [[[0.0, 0.0, 0.0, 0.0] for _ in range(size)] for _ in range(size)]

    S = n / 1024.0  # 设计稿按 1024 坐标系

    for y in range(n):
        for x in range(n):
            px, py = (x + 0.5) / S, (y + 0.5) / S

            # 外轮廓：圆角方形
            outer = coverage(sdf_round_rect(px, py, 512, 512, 500, 500, 220), 1.4)
            if outer <= 0:
                continue

            t = clamp(py / 1024.0)
            bg = tuple(int(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t)) for i in range(3))

            # 气泡 + 尾巴（并集）
            bubble = sdf_round_rect(px, py, 512, 468, 252, 184, 92)
            tail = sdf_rot_rect(px, py, 402, 660, 92, 92, 30, math.radians(45))
            body = min(bubble, tail)
            body_cov = coverage(body, 1.4)

            color = bg
            if body_cov > 0:
                color = blend(color, (255, 255, 255), body_cov)

            # 三个圆点
            for cx in (404, 512, 620):
                d = math.hypot(px - cx, py - 462) - 34
                dc = coverage(d, 1.4)
                if dc > 0:
                    color = blend(color, DOT, dc)

            ax, ay = x // scale, y // scale
            cell = acc[ay][ax]
            cell[0] += color[0]
            cell[1] += color[1]
            cell[2] += color[2]
            cell[3] += 255.0 * outer

    k = float(scale * scale)
    out = bytearray()
    for row in acc:
        out.append(0)  # filter type 0
        for r, g, b, a in row:
            out.extend((
                int(round(r / k)),
                int(round(g / k)),
                int(round(b / k)),
                int(round(a / k)),
            ))
    return bytes(out)


def write_png(path, size, raw):
    def chunk(tag, data):
        c = tag + data
        return (struct.pack(">I", len(data)) + c
                + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    base = "android/app/src/main/res"
    targets = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in targets.items():
        d = os.path.join(base, folder)
        os.makedirs(d, exist_ok=True)
        raw = render(size)
        path = os.path.join(d, "ic_launcher.png")
        write_png(path, size, raw)
        print("wrote", path, size)

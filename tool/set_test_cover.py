"""临时给角色卡挂一张测试封面，用来验证对话页的模糊背景。"""
import math
import os
import sqlite3
import struct
import subprocess
import time
import zlib

ADB = r"C:\Users\lively lampe\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
PKG = "com.roleplay.ai_roleplay"
WORK = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\_shots\db"
DB = os.path.join(WORK, "ai_roleplay.sqlite")
IMG = os.path.join(WORK, "test_cover.png")

W, H = 360, 640


def make_png():
    rows = bytearray()
    for y in range(H):
        rows.append(0)
        for x in range(W):
            u, v = x / W, y / H
            # 三段彩色渐变 + 斜向条纹，模糊后能明显看出色彩分布
            r = int(120 + 110 * math.sin(3.1 * u + 1.2 * v) ** 2)
            g = int(90 + 80 * math.sin(2.3 * v + 0.6) ** 2)
            b = int(160 + 90 * math.sin(2.7 * (u + v)) ** 2)
            stripe = 18 if int((x + y) / 14) % 2 == 0 else 0
            rows.extend((
                min(255, r + stripe),
                min(255, g + stripe // 2),
                min(255, b + stripe),
            ))

    def chunk(tag, data):
        c = tag + data
        return (struct.pack(">I", len(data)) + c
                + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))
    with open(IMG, "wb") as f:
        f.write(png)
    print("cover generated", len(png), "bytes")


def adb(*a):
    return subprocess.run([ADB, *a], capture_output=True)


def main():
    os.makedirs(WORK, exist_ok=True)
    make_png()
    adb("shell", "am", "force-stop", PKG)
    time.sleep(1)

    for name, path in (("files/ai_roleplay.sqlite", DB),
                       ("files/ai_roleplay.sqlite-wal", DB + "-wal")):
        with open(path, "wb") as f:
            f.write(adb("exec-out", "run-as", PKG, "cat", name).stdout)

    db = sqlite3.connect(DB)
    rows = db.execute("SELECT id, name, avatar_path FROM character_cards").fetchall()
    print("cards:", rows)
    if not rows:
        print("没有角色卡，跳过")
        return
    cid = rows[0][0]
    db.execute("UPDATE character_cards SET avatar_path = ? WHERE id = ?",
               ("avatars/test_cover.png", cid))
    db.commit()
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.commit()
    db.close()
    for s in ("-wal", "-shm"):
        if os.path.exists(DB + s):
            os.remove(DB + s)

    adb("push", DB, "/data/local/tmp/ai_roleplay.sqlite")
    adb("shell", "run-as", PKG, "cp", "/data/local/tmp/ai_roleplay.sqlite",
        "files/ai_roleplay.sqlite")
    adb("shell", "run-as", PKG, "rm", "-f",
        "files/ai_roleplay.sqlite-wal", "files/ai_roleplay.sqlite-shm")

    adb("push", IMG, "/data/local/tmp/test_cover.png")
    adb("shell", "run-as", PKG, "mkdir", "-p", "files/avatars")
    adb("shell", "run-as", PKG, "cp", "/data/local/tmp/test_cover.png",
        "files/avatars/test_cover.png")

    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    print("done, card =", cid)


if __name__ == "__main__":
    main()

"""重置测试数据：给角色卡补开场白，并清空会话，让 App 下次打开时自动开场。"""
import os
import sqlite3
import subprocess
import time

ADB = r"C:\Users\lively lampe\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
PKG = "com.roleplay.ai_roleplay"
WORK = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\_shots\db"
DB = os.path.join(WORK, "ai_roleplay.sqlite")


def adb(*a, **kw):
    return subprocess.run([ADB, *a], capture_output=True, **kw)


def main():
    adb("shell", "am", "force-stop", PKG)
    time.sleep(1)

    for name, path in (
        ("files/ai_roleplay.sqlite", DB),
        ("files/ai_roleplay.sqlite-wal", DB + "-wal"),
    ):
        with open(path, "wb") as f:
            f.write(adb("exec-out", "run-as", PKG, "cat", name).stdout)

    db = sqlite3.connect(DB)
    db.execute(
        "UPDATE character_cards SET first_mes = ?, personality = ?, updated_at = ?",
        ("你好呀，我是测试角色。", "温柔、话不多", int(time.time() * 1000)),
    )
    db.execute("DELETE FROM messages")
    db.execute("DELETE FROM chat_sessions")
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
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    print("reset done")


if __name__ == "__main__":
    main()

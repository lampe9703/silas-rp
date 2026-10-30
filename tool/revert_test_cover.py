"""把测试封面从角色卡上撤掉，恢复成原来的样子。"""
import os
import sqlite3
import subprocess
import time

ADB = r"C:\Users\lively lampe\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
PKG = "com.roleplay.ai_roleplay"
WORK = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\_shots\db"
DB = os.path.join(WORK, "ai_roleplay.sqlite")


def adb(*a):
    return subprocess.run([ADB, *a], capture_output=True)


def main():
    adb("shell", "am", "force-stop", PKG)
    time.sleep(1)

    r = adb("exec-out", "run-as", PKG, "cat", "files/ai_roleplay.sqlite")
    if len(r.stdout) < 1024:
        print("无法读取数据库（可能装的是不可调试的 release 包）")
        return
    with open(DB, "wb") as f:
        f.write(r.stdout)
    with open(DB + "-wal", "wb") as f:
        f.write(adb("exec-out", "run-as", PKG, "cat",
                    "files/ai_roleplay.sqlite-wal").stdout)

    db = sqlite3.connect(DB)
    db.execute(
        "UPDATE character_cards SET avatar_path = NULL WHERE avatar_path = ?",
        ("avatars/test_cover.png",),
    )
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
    adb("shell", "run-as", PKG, "rm", "-f", "files/avatars/test_cover.png")
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    print("测试封面已撤除")


if __name__ == "__main__":
    main()

"""清理测试痕迹并把手机设置恢复原状。"""
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
    # 1. 删掉指向本地 mock 的测试配置与测试角色卡
    adb("shell", "am", "force-stop", PKG)
    time.sleep(1)
    for name, path in (("files/ai_roleplay.sqlite", DB),
                       ("files/ai_roleplay.sqlite-wal", DB + "-wal")):
        with open(path, "wb") as f:
            f.write(adb("exec-out", "run-as", PKG, "cat", name).stdout)

    db = sqlite3.connect(DB)
    db.execute("DELETE FROM api_configs")
    db.execute("DELETE FROM app_settings WHERE key = 'default_api_config_id'")
    db.execute("DELETE FROM messages")
    db.execute("DELETE FROM chat_sessions")
    db.execute("DELETE FROM character_tags")
    db.execute("DELETE FROM character_greetings")
    db.execute("DELETE FROM character_cards")
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
    adb("shell", "run-as", PKG, "rm", "-rf", "files/avatars")
    print("app data cleaned")

    # 2. 恢复输入法：三个都启用，默认回到搜狗
    adb("shell", "ime", "enable",
        "com.sohu.inputmethod.sogou/.SogouIME")
    adb("shell", "ime", "enable",
        "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME")
    adb("shell", "ime", "set", "com.sohu.inputmethod.sogou/.SogouIME")
    print("ime restored")

    # 3. 恢复息屏时间（删除自定义值，回到系统默认）
    adb("shell", "settings", "delete", "system", "screen_off_timeout")

    # 4. 移除端口映射
    adb("reverse", "--remove-all")

    # 5. 重启应用，回到干净首屏
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    print("done")


if __name__ == "__main__":
    main()

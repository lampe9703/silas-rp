"""把一条指向本地 mock 服务的 API 配置写进设备数据库，绕过输入法限制。

用法：先 force-stop 应用，再运行本脚本，最后重新启动应用。
"""
import os
import sqlite3
import subprocess
import time
import uuid

ADB = r"C:\Users\lively lampe\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
PKG = "com.roleplay.ai_roleplay"
WORK = r"C:\Users\lively lampe\WorkBuddy AI\2026-10-24-01-14-03\_shots\db"
DB_LOCAL = os.path.join(WORK, "ai_roleplay.sqlite")


def adb(*args, **kw):
    return subprocess.run([ADB, *args], capture_output=True, **kw)


def main():
    os.makedirs(WORK, exist_ok=True)
    adb("shell", "am", "force-stop", PKG)
    time.sleep(1)

    with open(DB_LOCAL, "wb") as f:
        f.write(adb("exec-out", "run-as", PKG, "cat", "files/ai_roleplay.sqlite").stdout)
    with open(DB_LOCAL + "-wal", "wb") as f:
        f.write(adb("exec-out", "run-as", PKG, "cat", "files/ai_roleplay.sqlite-wal").stdout)

    db = sqlite3.connect(DB_LOCAL)
    now = int(time.time() * 1000)
    cid = str(uuid.uuid4())
    db.execute(
        """INSERT OR REPLACE INTO api_configs
           (id,name,base_url,model,is_openai_compatible,key_ref,extra_headers,
            max_tokens,temperature,top_p,stream,is_default,created_at,updated_at)
           VALUES (?,?,?,?,1,'','{}',NULL,NULL,NULL,1,1,?,?)""",
        (cid, "LocalMock", "http://127.0.0.1:8080/v1", "mock-model", now, now),
    )
    db.commit()
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.commit()
    db.close()

    for suffix in ("-wal", "-shm"):
        if os.path.exists(DB_LOCAL + suffix):
            os.remove(DB_LOCAL + suffix)

    print("config inserted:", cid)

    adb("push", DB_LOCAL, "/data/local/tmp/ai_roleplay.sqlite")
    adb("shell", "run-as", PKG, "cp", "/data/local/tmp/ai_roleplay.sqlite",
        "files/ai_roleplay.sqlite")
    adb("shell", "run-as", PKG, "rm", "-f",
        "files/ai_roleplay.sqlite-wal", "files/ai_roleplay.sqlite-shm")
    print("db pushed")

    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    print("app started")


if __name__ == "__main__":
    main()

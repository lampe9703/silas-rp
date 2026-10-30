"""本地 Mock OpenAI 兼容服务，用于验证 App 的流式链路。

- GET  /v1/models            → 供「测试连接」使用
- POST /v1/chat/completions  → 支持 stream=true 的 SSE 分块返回

所有请求体都会追加写入 mock_requests.log，便于核对 App 实际发出的提示词。
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mock_requests.log")

REPLY = "你好呀，我是测试角色。这是一段用来验证流式输出的回复，会一段一段地出现在屏幕上。"


def chunks(text, size=4):
    for i in range(0, len(text), size):
        yield text[i:i + size]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            body = json.dumps({
                "object": "list",
                "data": [{"id": "mock-model", "object": "model"}],
            }).encode()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {"_raw": raw.decode("utf-8", "replace")}

        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "at": time.strftime("%H:%M:%S"),
                "path": self.path,
                "auth": self.headers.get("Authorization", ""),
                "body": payload,
            }, ensure_ascii=False) + "\n")

        if payload.get("stream"):
            self._stream()
        else:
            self._once()

    def _stream(self):
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def send(obj):
            self.wfile.write(f"data: {json.dumps(obj, ensure_ascii=False)}\n\n".encode())
            self.wfile.flush()

        send({"choices": [{"delta": {"role": "assistant"}, "index": 0}]})
        for piece in chunks(REPLY):
            send({"choices": [{"delta": {"content": piece}, "index": 0}]})
            time.sleep(0.06)

        send({"choices": [{"delta": {}, "finish_reason": "stop", "index": 0}]})
        # 末尾带 usage，模拟 stream_options.include_usage
        send({
            "choices": [],
            "usage": {
                "prompt_tokens": 128,
                "completion_tokens": 46,
                "total_tokens": 174,
            },
        })
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def _once(self):
        body = json.dumps({
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": "mock-model",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": REPLY},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 128, "completion_tokens": 46, "total_tokens": 174},
        }).encode()
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("mock openai server on :8080")
    server.serve_forever()

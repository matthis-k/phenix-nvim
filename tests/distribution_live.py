"""Full P1 Neovim distribution -> ACP -> HTTP Model check without API billing."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

binary, output_dir = sys.argv[1:]
out = Path(output_dir)
out.mkdir(parents=True, exist_ok=True)
calls = []

class Provider(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *_):
        pass
    def do_POST(self):
        assert self.path == "/v1/chat/completions"
        assert self.headers.get("Authorization") == "Bearer distribution-fixture"
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        calls.append(body)
        assert body["model"] == "distribution-fixture"
        assert body["messages"][-1] == {
            "role": "user", "content": "test the live Neovim provider"
        }
        assert body["stream"] is True
        payload = [
            {"choices": [{"index": 0, "delta": {
                "content": "verified-live-provider"
            }, "finish_reason": "stop"}]},
            {"choices": [], "usage": {"prompt_tokens": 12, "completion_tokens": 3}},
        ]
        answer = ("".join("data: " + json.dumps(item) + "\n\n" for item in payload)
                  + "data: [DONE]\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)
        self.wfile.flush()

server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = os.environ.copy()
    env.update(
        OPENAI_API_KEY="distribution-fixture",
        PHENIX_MODEL_HTTP_ENDPOINT=f"http://127.0.0.1:{server.server_port}/v1/chat/completions",
        PHENIX_MODEL_HTTP_MODEL="distribution-fixture",
        HOME=str(out / "home"),
        XDG_STATE_HOME=str(out / "state"),
        XDG_CONFIG_HOME=str(out / "config"),
        XDG_DATA_HOME=str(out / "data"),
        XDG_CACHE_HOME=str(out / "cache"),
    )
    # The packaged HTTP launcher owns the default state path.
    env.pop("PHENIX_BASIC_SQLITE_PATH", None)
    for var in ("HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME",
                "XDG_DATA_HOME", "XDG_CACHE_HOME"):
        Path(env[var]).mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [binary, "test", "the", "live", "Neovim", "provider"],
        capture_output=True, text=True, env=env, timeout=120
    )
    assert result.returncode == 0, (result.stdout, result.stderr)
    # The runner reserves stdout for the assistant answer and stderr for
    # diagnostics, allowing the CLI output to be safely piped.
    assert "verified-live-provider" in result.stdout, (result.stdout, result.stderr)
    assert "phenix.model.http" in result.stderr, (result.stdout, result.stderr)
    assert "verified-live-provider" not in result.stderr, result.stderr
    assert len(calls) == 1, calls
    assert (out / "state" / "phenix" / "basic-http.sqlite").is_file()
    (out / "result.json").write_text(json.dumps({
        "format": "phenix.nvim.p1-live.v1",
        "model": "phenix.model.http",
        "requests": len(calls),
        "answer": "verified-live-provider",
    }, indent=2))
finally:
    server.shutdown()

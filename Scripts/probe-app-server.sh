#!/usr/bin/env bash
# 探测本机 Codex CLI + 真实 app-server 数据（需在 Mac 上运行）
set -euo pipefail

echo "== Codex-Pulse · 真实数据探测 =="
echo

if ! command -v codex >/dev/null 2>&1; then
  echo "❌ 未找到 codex CLI"
  echo "   安装示例: npm i -g @openai/codex  或见 https://github.com/openai/codex"
  exit 1
fi

CODEX="$(command -v codex)"
echo "✓ CLI: $CODEX"
codex --version 2>/dev/null || true
echo

# Generate schemas for the installed version (optional)
SCHEMA_DIR="$(cd "$(dirname "$0")/.." && pwd)/docs/schemas"
mkdir -p "$SCHEMA_DIR"
if codex app-server generate-json-schema --out "$SCHEMA_DIR" 2>/dev/null; then
  echo "✓ Schema 已生成到 docs/schemas"
else
  echo "· generate-json-schema 不可用（可忽略）"
fi
echo

python3 - <<'PY'
import json, subprocess, sys, threading, time, queue

proc = subprocess.Popen(
    ["codex", "app-server"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def reader(q):
    assert proc.stdout is not None
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            q.put(json.loads(line))
        except json.JSONDecodeError:
            q.put({"_raw": line})

q: queue.Queue = queue.Queue()
threading.Thread(target=reader, args=(q,), daemon=True).start()

req_id = 0

def send(method, params=None, is_notification=False):
    global req_id
    msg = {"method": method}
    if not is_notification:
        req_id += 1
        msg["id"] = req_id
    msg["params"] = params if params is not None else {}
    assert proc.stdin is not None
    proc.stdin.write(json.dumps(msg, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    return None if is_notification else req_id

def wait_result(expect_id, timeout=8.0):
    deadline = time.time() + timeout
    notes = []
    while time.time() < deadline:
        try:
            msg = q.get(timeout=0.2)
        except queue.Empty:
            continue
        if msg.get("id") == expect_id:
            return msg, notes
        if "method" in msg and "id" not in msg:
            notes.append(msg.get("method"))
    raise TimeoutError(f"timeout waiting for id={expect_id}")

try:
    print("→ initialize")
    i = send("initialize", {
        "clientInfo": {"name": "codex_pulse_probe", "title": "Codex-Pulse Probe", "version": "0.1.0"},
        "capabilities": {
            "experimentalApi": False,
            "optOutNotificationMethods": [
                "item/agentMessage/delta",
                "item/reasoning/summaryTextDelta",
                "item/reasoning/textDelta",
            ],
        },
    })
    resp, _ = wait_result(i)
    if "error" in resp:
        print("initialize error:", resp["error"])
        sys.exit(2)
    result = resp.get("result", {})
    print("  server:", {k: result.get(k) for k in ("userAgent", "codexHome", "platformOs") if k in result or True})
    print("  keys:", list(result.keys())[:12])

    send("initialized", {}, is_notification=True)
    time.sleep(0.3)

    for method, params in [
        ("account/read", {"refreshToken": False}),
        ("account/rateLimits/read", {}),
        ("account/usage/read", {}),
        ("thread/list", {"limit": 5, "archived": False}),
    ]:
        print(f"→ {method}")
        try:
            i = send(method, params)
            resp, notes = wait_result(i, timeout=12)
            if "error" in resp:
                print("  error:", resp["error"])
            else:
                r = resp.get("result", {})
                # compact print
                text = json.dumps(r, ensure_ascii=False, default=str)
                if len(text) > 900:
                    text = text[:900] + "…"
                print("  result:", text)
            if notes:
                print("  notes:", notes[:6])
        except Exception as e:
            print("  failed:", e)

    print("\n✓ 探测完成。若 account/read 有 email/planType，即可在 Codex-Pulse 中显示真实数据。")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
PY

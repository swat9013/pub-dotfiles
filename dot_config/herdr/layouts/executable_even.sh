#!/bin/bash
# 既存 pane を等倍に並べる layout (herdr 版)
# split tree を保ったまま各 split の ratio を leaves_first / total_leaves に更新する。
# 他 3 layout (ide / 4col-lazygit / emacs-dev) と違い pane の新規生成はしない (整地系)。
#
# upstream で `select-layout even-*` 相当は Issue #209 で not planned と却下されている。
# CLI ラッパーも無い (`herdr api` は snapshot/schema のみ) ため、
# layout.set_split_ratio を HERDR_SOCKET_PATH に対して raw JSON-RPC で流す。
# wire format: newline-delimited JSON (`nc -U` で probe 済み、応答も同形式)。
#
# split id encoding (`split_<depth>_<digits>`) は upstream 内部実装依存で不安定なので
# 木構造は splits[].rect + panes[].rect の包含関係で復元する。
# path は false=first (左/上), true=second (右/下) の bool 列 (path=[] が root)。
#
# 起動経路: layout-menu.sh の "4 even" 項目。
#
# ┌───┬─┬──┬───┐              ┌──┬──┬──┬──┬──┐
# │ A │B│C │ D │  →           │A │B │C │D │E │
# │   │ │  │   │               │  │  │  │  │  │
# └───┴─┴──┴───┘              └──┴──┴──┴──┴──┘

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

: "${HERDR_SOCKET_PATH:?HERDR_SOCKET_PATH not set — must run inside a herdr session}"

# popup 起動 (layout-menu.sh 経由) では env から起動元 pane を継承する。
# 直接 keybind 起動時は env 未設定なので herdr pane current にフォールバック。
if [[ -n "${HERDR_ACTIVE_PANE_ID:-}" ]]; then
	pane="$HERDR_ACTIVE_PANE_ID"
else
	pane=$(herdr pane current | jq -r '.result.pane.pane_id')
fi

layout_json=$(herdr pane layout --pane "$pane")

exec python3 - "$layout_json" "$pane" "$HERDR_SOCKET_PATH" <<'PYEOF'
import json, socket, sys

layout = json.loads(sys.argv[1])["result"]["layout"]
pane_id, sock_path = sys.argv[2], sys.argv[3]

splits, panes = layout["splits"], layout["panes"]
if not splits:
	sys.exit(0)  # 1 pane しか無ければ整地する対象が無い

def contains(o, i):
	return (o["x"] <= i["x"] and o["y"] <= i["y"]
		and o["x"] + o["width"]  >= i["x"] + i["width"]
		and o["y"] + o["height"] >= i["y"] + i["height"])

def area(n):
	r = n["rect"]
	return r["width"] * r["height"]

nodes = ([{"kind": "pane",  "rect": p["rect"]} for p in panes]
       + [{"kind": "split", "rect": s["rect"], "direction": s["direction"], "id": s["id"]} for s in splits])

def children_of(split):
	inside = [n for n in nodes if n is not split and contains(split["rect"], n["rect"])]
	# split より狭い split に覆われている node は「直接の子」ではない。
	smaller = [n for n in inside if n["kind"] == "split" and area(n) < area(split)]
	def hidden(x):
		return any(s is not x and contains(s["rect"], x["rect"]) for s in smaller)
	direct = [n for n in inside if not hidden(n)]
	direct.sort(key=lambda n: n["rect"]["x" if split["direction"] == "right" else "y"])
	if len(direct) != 2:
		sys.stderr.write(f"[even] split {split['id']} has {len(direct)} direct children (expected 2)\n")
		sys.exit(1)
	return direct

root = max((n for n in nodes if n["kind"] == "split"), key=area)

requests = []
def walk(node, path):
	if node["kind"] == "pane":
		return 1
	first, second = children_of(node)
	l = walk(first,  path + [False])
	r = walk(second, path + [True])
	requests.append({
		"id": f"even:{len(requests)}",
		"method": "layout.set_split_ratio",
		"params": {"pane_id": pane_id, "path": path, "ratio": l / (l + r)},
	})
	return l + r
walk(root, [])

# herdr server は 1 connection = 1 request で応答後に close するため、request 毎に接続する。
# (empirical: 同一 connection に 2 request 連投しても 2 個目は無視されるのを検証済み)
for req in requests:
	s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	s.settimeout(3.0)
	s.connect(sock_path)
	try:
		s.sendall((json.dumps(req) + "\n").encode())
		# 応答を 1 行読んで close (server が in-flight を捨てないため)。
		buf = b""
		while b"\n" not in buf:
			chunk = s.recv(4096)
			if not chunk:
				break
			buf += chunk
		resp = json.loads(buf.decode().splitlines()[0]) if buf else {}
		if "error" in resp:
			sys.stderr.write(f"[even] {req['id']} failed: {resp['error']}\n")
			sys.exit(1)
	finally:
		s.close()
PYEOF

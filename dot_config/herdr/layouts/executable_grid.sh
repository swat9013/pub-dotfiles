#!/bin/bash
# 「最左は縦長のコマンド入力用、右は最低幅を保ったマス目」に組み替える layout (herdr 版)
# pane の新規生成・破棄はしない (整地系。even.sh と同じ位置づけ)。
#
# **最左に来るのは起動元 pane** (popup なら呼んだ時点で focus していた pane)。
# 同じ tab の残り pane が右側へ列優先で敷き詰められる。agent の pane から呼べば
# その agent が最左の縦長になるので、コマンド入力用の shell に focus してから呼ぶこと。
#
# ┌───┬─┬──┬───┐              ┌──────┬───┬───┬───┬───┐
# │ A │B│C │ D │  →           │      │ B │ D │ F │ H │
# │   │ │  │   │               │  A   ├───┼───┼───┤   │
# │   │ │  │   │               │      │ C │ E │ G │   │
# └───┴─┴──┴───┘              └──────┴───┴───┴───┴───┘
#
# even.sh は split tree の形を保ったまま ratio だけ均す。横一列に 8 pane 並べば
# 8 列のまま均等化するので 1 列 41 桁になり Claude Code が読めない。本 script は
# **木の形自体を組み替える**ことで列数を最低幅から逆算し、あふれた分を下へ折り返す。
#
# 実現手段 (herdr 0.8.0 で実測):
# - layout.apply は既存 pane を引き取らず tab ごと作り直す (走行中の agent が全滅する)
#   ため使えない。
# - 同一 tab 内の `pane move` は success を返して何もしない (no-op)。別 tab へ退避して
#   から戻すと期待どおり再配置され、pane_id もプロセスも保たれる。
# - 幅は ratio でしか指定できない (絶対列数を渡す API が無い)。したがって下の幅指定は
#   「実行した瞬間の描画幅に対する比率」として固定される。端末をリサイズすると比例
#   して伸縮するので、必要なら再実行する。
#
# 起動経路: layout-menu.sh の "5 grid" 項目。
#
# HERDR_GRID_PLAN_FROM=<path> を与えると、その JSON (herdr pane layout の応答) から
# 実行計画を組み立てて print するだけで、socket には一切触れない (test / 事前確認用)。

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

# popup 起動 (layout-menu.sh 経由) では env から起動元 pane を継承する。
# 直接 keybind 起動時は env 未設定なので herdr pane current にフォールバック。
if [[ -n "${HERDR_ACTIVE_PANE_ID:-}" ]]; then
	pane="$HERDR_ACTIVE_PANE_ID"
else
	pane=$(herdr pane current | jq -r '.result.pane.pane_id')
fi

if [[ -n "${HERDR_GRID_PLAN_FROM:-}" ]]; then
	layout_json=$(cat "$HERDR_GRID_PLAN_FROM")
	socket=""
else
	: "${HERDR_SOCKET_PATH:?HERDR_SOCKET_PATH not set — must run inside a herdr session}"
	layout_json=$(herdr pane layout --pane "$pane")
	socket="$HERDR_SOCKET_PATH"
fi

exec python3 - "$layout_json" "$pane" "$socket" <<'PYEOF'
import json, socket, subprocess, sys

# 最右まで敷き詰めたときに 1 列が下回ってはいけない幅。Claude Code の TUI が
# 折り返しだらけにならない下限として 60 桁を採った (41 桁は実用に耐えなかった)。
MIN_COLUMN_WIDTH = 60
# 最左のコマンド入力用 pane に与える幅。
LEFT_COLUMN_WIDTH = 90

layout = json.loads(sys.argv[1])["result"]["layout"]
anchor_id, sock_path = sys.argv[2], sys.argv[3]

others = [p for p in layout["panes"] if p["pane_id"] != anchor_id]
if not others:
	sys.exit(0)  # 最左 1 枚しか無ければ敷き詰める対象が無い

# 見た目の並び (左上から右下) を維持したまま組み替える。
others.sort(key=lambda p: (p["rect"]["x"], p["rect"]["y"]))
pane_ids = [p["pane_id"] for p in others]

area_width = layout["area"]["width"]
# 描画幅は sidebar を除いた実効幅なので、狭い端末では LEFT_COLUMN_WIDTH を下回る。
# そのまま使うと ratio が 1 を超え、grid 側の幅が負になる。半分を上限に切り詰める。
left_width = min(LEFT_COLUMN_WIDTH, area_width // 2)
column_count = max(1, min(len(pane_ids), (area_width - left_width) // MIN_COLUMN_WIDTH))

# 列の高さを揃える (余りを左の列から 1 枚ずつ配る)。7 枚 4 列なら 2,2,2,1。
base, remainder = divmod(len(pane_ids), column_count)
columns, cursor = [], 0
for index in range(column_count):
	size = base + (1 if index < remainder else 0)
	columns.append(pane_ids[cursor:cursor + size])
	cursor += size


def leaf(pane_id):
	return {"type": "pane", "pane_id": pane_id}


def graft(node, target_id, direction, added_id):
	"""target_id の葉を split(direction, target, added) へ置き換える。

	`pane move --target-pane` が「対象 pane を分割して隣に差し込む」挙動そのもの。
	move 列と同じ順序で適用すれば、完成後の tree をそのまま予測できる。
	"""
	if node["type"] == "pane":
		if node["pane_id"] != target_id:
			return node
		return {"type": "split", "direction": direction,
		        "first": leaf(target_id), "second": leaf(added_id)}
	return {**node,
	        "first": graft(node["first"], target_id, direction, added_id),
	        "second": graft(node["second"], target_id, direction, added_id)}


# move は「列の先頭を左から順に横並びで作る」→「各列を下へ埋める」の順でなければ
# ならない。pane move は部分木ではなく **pane** を分割するため、列を作り終える前に
# 下方向へ埋めると、後続の横 split が列の中に潜り込む。
moves = []
previous = anchor_id
for column in columns:
	moves.append((column[0], previous, "right"))
	previous = column[0]
for column in columns:
	above = column[0]
	for pane_id in column[1:]:
		moves.append((pane_id, above, "down"))
		above = pane_id

tree = leaf(anchor_id)
for moved_id, target_id, direction in moves:
	tree = graft(tree, target_id, direction, moved_id)


def span(node, direction):
	"""node が direction 方向に占める区画数。right なら列数、down なら行数。"""
	if node["type"] == "pane":
		return 1
	measure = (span(node["first"], direction), span(node["second"], direction))
	return sum(measure) if node["direction"] == direction else max(measure)


def plan_ratios(node, path, out):
	if node["type"] == "pane":
		return
	first = span(node["first"], node["direction"])
	second = span(node["second"], node["direction"])
	out.append((path, first / (first + second)))
	plan_ratios(node["first"], path + [False], out)
	plan_ratios(node["second"], path + [True], out)


ratios = []
plan_ratios(tree, [], ratios)
# root だけは均等割りではなく「最左を指定幅にする」比率へ差し替える。
ratios[0] = ([], left_width / area_width)


def show_path(path):
	return "/".join("second" if step else "first" for step in path) or "root"


if not sock_path:
	print(f"plan panes={len(pane_ids)} columns={column_count} area_width={area_width}")
	for moved_id, target_id, direction in moves:
		print(f"move {moved_id} after {target_id} {direction}")
	for path, ratio in ratios:
		print(f"ratio {show_path(path)} {ratio:.3f}")
	sys.exit(0)


def herdr(*args):
	"""herdr CLI を叩き、失敗したら即座に中断する。

	move が 1 つでも落ちると以降の target が実在しなくなり、下で組み立てた tree の
	予測と実体がずれる。部分適用で放置せず fail fast させる。
	"""
	result = subprocess.run(["herdr", *args], capture_output=True, text=True)
	response = json.loads(result.stdout) if result.stdout else {}
	if result.returncode != 0 or "error" in response:
		sys.stderr.write(f"[grid] herdr {' '.join(args)} failed: "
		                 f"{response.get('error', result.stderr.strip())}\n")
		sys.exit(1)


def request(method, params):
	# herdr server は 1 connection = 1 request で応答後に close するため接続を使い捨てる。
	sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	sock.settimeout(3.0)
	sock.connect(sock_path)
	try:
		sock.sendall((json.dumps({"id": f"grid:{method}", "method": method,
		                          "params": params}) + "\n").encode())
		buf = b""
		while b"\n" not in buf:
			chunk = sock.recv(4096)
			if not chunk:
				break
			buf += chunk
		response = json.loads(buf.decode().splitlines()[0]) if buf else {}
		if "error" in response:
			sys.stderr.write(f"[grid] {method} failed: {response['error']}\n")
			sys.exit(1)
	finally:
		sock.close()


tab_id, workspace_id = layout["tab_id"], layout["workspace_id"]
for moved_id, target_id, direction in moves:
	# 同一 tab 内の move は no-op なので、pane 単位で空の tab へ退避してから戻す。
	# 退避先を move ごとに新規 tab にすることで、退避中の pane が他を圧迫しない
	# (pane が抜けて空になった tab は herdr が自動で閉じる)。
	herdr("pane", "move", moved_id, "--new-tab", "--workspace", workspace_id, "--no-focus")
	herdr("pane", "move", moved_id, "--tab", tab_id,
	      "--target-pane", target_id, "--split", direction, "--no-focus")

for path, ratio in ratios:
	request("layout.set_split_ratio", {"tab_id": tab_id, "path": path, "ratio": ratio})
PYEOF

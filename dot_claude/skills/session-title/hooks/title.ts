// Haiku に渡す指示と、その返答から session 名を取り出す判定。

// 指示する長さの目安と、返答が長すぎたときに切る上限。
// サイドバー（幅 36 列）の 1 行に全角でおよそ 17 字が入る。目安で切ると語の途中で切れるので、上限は余裕を持たせる。
export const TARGET_CHARS = 14
export const MAX_CHARS = 24
export const PROMPT_CHARS = 2000
export const TIMEOUT_MS = 3000

// 「OK」「続けて」のような短い返答は話題が変わらないので、Haiku を呼ばずに今の名前のまま進める。
// issue / CL の番号（#123）を含む prompt は短くても新しいタスクを指しうるので、要約に回す。
export const SHORT_PROMPT_CHARS = 8
export const isShortReply = (prompt: string): boolean => {
  const text = prompt.trim()
  return Array.from(text).length <= SHORT_PROMPT_CHARS && !/#\d/.test(text)
}

// mod が session に最後に付けた名前と、その session を最後に見た時刻を、session ごとの key で $.store に持つ。
// $.store は全 session で共有なので、key を分けて並行 session の書き込みが互いを消さないようにする。
// key が MAX_SESSIONS + PRUNE_SLACK 件を超えたら、最後に見た時刻の古い順に MAX_SESSIONS 件まで消す。
const KEY_PREFIX = 'title:'
// 押し出しは全 key の値を読むので、件数を大きくすると押し出す回の prompt が遅れる。余裕の分だけ回数を減らす。
export const MAX_SESSIONS = 200
export const PRUNE_SLACK = 50
export type Owned = { title: string, seenAt: number }

export const ownedKey = (sessionId: string): string => `${KEY_PREFIX}${sessionId}`
export const isOwnedKey = (key: string): boolean => key.startsWith(KEY_PREFIX)

export const readOwned = (value: unknown): Owned | undefined =>
  typeof value === 'object' && value !== null
    && typeof (value as Owned).title === 'string' && typeof (value as Owned).seenAt === 'number'
    ? value as Owned
    : undefined

// 消す key を、最後に見た時刻の古い順に選ぶ。件数が上限と余裕の和を超えるまでは消さない。
export const keysToPrune = (entries: readonly (readonly [string, Owned | undefined])[]): string[] => {
  if (entries.length <= MAX_SESSIONS + PRUNE_SLACK) return []
  return [...entries]
    .sort(([, a], [, b]) => (a?.seenAt ?? 0) - (b?.seenAt ?? 0))
    .slice(0, entries.length - MAX_SESSIONS)
    .map(([key]) => key)
}

export const SYSTEM = `あなたは Claude Code の session に短い名前を付ける。名前は terminal のサイドバーに 1 行で表示され、並んだ複数の session のうちどれが何の作業かを見分けるのに使われる。

- いま取り組んでいるタスクを、全角${TARGET_CHARS}字前後の名詞句で書く（例: 「herdrサイドバーの設計」「#2138 gate設計の再検討」）。長くなるなら語を削り、語の途中で切らない
- 依頼に issue や PR / MR の番号（#1234 など）があれば、名前の先頭に置く
- 依頼が現在の名前のタスクの続き（承認・短い返答・同じ話題の追加指示）なら、SAME とだけ返す
- 名前だけを 1 行で返す。説明・引用符・句点は付けない`

export const buildPrompt = (current: string | undefined, prompt: string): string =>
  `現在の名前: ${current ?? '(なし)'}\n\n今回の依頼:\n${Array.from(prompt).slice(0, PROMPT_CHARS).join('')}`

// terminal title に流れるので制御文字は落とす。両端の引用符・markdown の強調と、末尾の句読点を外す。
// 【】のように名前の一部になりうる括弧は外さない（片側だけ外れると名前が崩れる）。
const CONTROL = /\p{Cc}/gu
const WRAP = /^[\s"'`*「『“‘]+|[\s"'`*」』”’。.、,]+$/gu
// 「SAME」の後に続いてよいのは、句読点と括弧の注記（「SAME（続き）」）だけ。「Same Origin の検証」は名前として読む
const SAME = /^same(?:[\s.。!！]*|\s*[（(].*[)）])$/i

// 返答から新しい名前を取り出す。付け直さないときは undefined。
export const parseTitle = (reply: string, current: string | undefined): string | undefined => {
  const line = reply.split('\n').find(l => l.trim() !== '') ?? ''
  const cleaned = line.replace(CONTROL, '').replace(WRAP, '')
  if (SAME.test(cleaned)) return undefined
  const title = Array.from(cleaned).slice(0, MAX_CHARS).join('').trim()
  if (title === '' || title === current) return undefined
  return title
}

// 今の名前を付け直してよいか。名前が無いか、この session に mod が最後に付けた名前のままのときだけ付け直す。
// それ以外は user が `/rename` や `claude -n` で付けた名前なので上書きしない。
export const isRetitlable = (current: string | undefined, owned: Owned | undefined): boolean =>
  current === undefined || current === owned?.title

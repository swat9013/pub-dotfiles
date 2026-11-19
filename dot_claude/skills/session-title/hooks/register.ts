import type { EngineInterface, ModelCompleteResult, Register } from 'claude-code'
import {
  MAX_SESSIONS, PRUNE_SLACK, SYSTEM, TIMEOUT_MS,
  buildPrompt, isOwnedKey, isRetitlable, isShortReply, keysToPrune, ownedKey, parseTitle, readOwned,
} from './title.ts'

// 上限を超えた古い session の key を消す。件数が上限を超えたときだけ値を読む。
const prune = async ($: EngineInterface) => {
  const keys = (await $.store.keys()).filter(isOwnedKey)
  if (keys.length <= MAX_SESSIONS + PRUNE_SLACK) return
  const entries = await Promise.all(keys.map(async k => [k, readOwned(await $.store.get(k))] as const))
  for (const k of keysToPrune(entries)) await $.store.delete(k)
}

// user が prompt を送るたびに、いまのタスクを Haiku に要約させて session 名を付け直す。
// session 名は terminal title にも出るので、herdr などはそれを読むだけで済む。
export const register: Register = on => {
  on('classic.UserPromptSubmit', async ($, e, next) => {
    // 機械の turn だと source が示すときは触らない。source の無い turn を user の turn とみなす判断と
    // その見直し条件は dot_claude/README.md の session-title の行にある。
    if (e.source !== undefined && e.source !== 'user') return next(e)
    if (!e.session_id) return next(e)

    const key = ownedKey(e.session_id)
    const stored = await $.store.get(key)
    const owned = readOwned(stored)
    if (stored !== undefined && owned === undefined) {
      $.ui.log(`session-title: ${key} の値が想定の形でない`, { to: 'debug' })
    }
    if (!isRetitlable(e.session_title, owned)) return next(e)
    // 短い返答では要約を呼ばない。使っている session の時刻だけ更新して押し出されないようにする
    if (isShortReply(e.prompt)) {
      if (owned !== undefined) await $.store.set(key, { title: owned.title, seenAt: Date.now() })
      return next(e)
    }

    // 要約は他の hook と並行に走らせ、prompt が待つ時間を重ねない。reject しても今の名前のまま進める
    const [result, reply] = await Promise.all([
      next(e),
      $.model.complete({
        model: 'haiku',
        system: SYSTEM,
        prompt: buildPrompt(e.session_title, e.prompt),
        maxTokens: 64,
        effort: 'low',
        timeoutMs: TIMEOUT_MS,
      }).catch((error: unknown): ModelCompleteResult | undefined => {
        $.ui.log(`session-title: 要約の呼び出しが失敗 (${String(error)})`, { to: 'debug' })
        return undefined
      }),
    ])
    // prompt を止めた・名前を付けた hook があれば、その判断を優先する
    if (result.block !== undefined || result.sessionTitle !== undefined) return result
    if (reply !== undefined && !reply.isAnswered) {
      $.ui.log(`session-title: 要約できず (${reply.reason})`, { to: 'debug' })
    }
    const title = reply?.isAnswered ? parseTitle(reply.text, e.session_title) : undefined

    // 付け直さない turn でも、使っている session の時刻を更新して押し出されないようにする
    if (title === undefined) {
      if (owned !== undefined) await $.store.set(key, { title: owned.title, seenAt: Date.now() })
      return result
    }
    // 古い key を先に消してから書き、書いた直後に返す（同じ session の dispatch が重なったときの窓を狭める）
    await prune($)
    await $.store.set(key, { title, seenAt: Date.now() })
    return { ...result, sessionTitle: title }
  })
}

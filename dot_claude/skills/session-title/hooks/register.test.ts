import { expect, mock, test, type TestBody } from 'claude-code/testing'
import type { ClassicResult, ModelCompleteResult, On } from 'claude-code'
import { MAX_SESSIONS, PRUNE_SLACK, ownedKey } from './title.ts'

const USAGE = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }

// engine 側を立てる。store は entries を初期値にしたメモリ、settings の hook は beneath を返し、
// Haiku は replies を順に返す（尽きたら失敗）。
const engine = (
  on: On,
  replies: string[],
  { entries = {}, beneath = {} }: { entries?: Record<string, unknown>, beneath?: ClassicResult } = {},
) => {
  const calls = { model: 0 }
  mock.store(on, entries)
  on('classic.UserPromptSubmit', () => beneath)
  on('model.complete', () => {
    calls.model += 1
    const text = replies.shift()
    const value: ModelCompleteResult = text === undefined
      ? { isAnswered: false, reason: 'aborted', usage: USAGE }
      : { isAnswered: true, text, usage: USAGE }
    return { value }
  })
  return calls
}

// 要約に回る長さの prompt（短い返答として飛ばされないもの）
const TASK = 'herdr の設定を見直したい'

// mod が session に付けた名前の記録（seenAt は最後に見た時刻）
const owned = (sessionId: string, title: string, seenAt = 1) => ({ [ownedKey(sessionId)]: { title, seenAt } })

// 別の session の記録を n 件、s1 より新しい時刻で作る
const others = (n: number) =>
  Object.assign({}, ...Array.from({ length: n }, (_, i) => owned(`old${i}`, `名前${i}`, 100 + i)))

// user が composer から送った prompt として raise する
const send = (
  $: Parameters<TestBody>[0],
  fields: { prompt: string, session_id?: string, session_title?: string },
) => $.classic.UserPromptSubmit({ source: 'user', ...fields })

test('話題が変わった prompt では session 名を付け直す', async ($, on) => {
  engine(on, ['herdrサイドバーの設計'])

  const result = await send($, { prompt: 'herdr のサイドバーを設計したい' })

  expect(result.sessionTitle).toBe('herdrサイドバーの設計')
})

test('mod が付けた名前のままなら次の prompt でも付け直す', async ($, on) => {
  engine(on, ['次のタスク'], { entries: owned('s1', '最初のタスク') })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: '最初のタスク' })

  expect(result.sessionTitle).toBe('次のタスク')
})

test('user が付けた名前は上書きせず、要約も呼ばない', async ($, on) => {
  const calls = engine(on, ['別の名前'])

  const result = await send($, { prompt: TASK, session_title: 'fork: 手で付けた名前' })

  expect(result.sessionTitle).toBeUndefined()
  expect(calls.model).toBe(0)
})

test('user が以前 mod の付けた名前へ戻したら、それも上書きしない', async ($, on) => {
  // mod が A → B と付けた後、user が /rename で A に戻した状態
  const calls = engine(on, ['別の名前'], { entries: owned('s1', 'B') })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: 'A' })

  expect(result.sessionTitle).toBeUndefined()
  expect(calls.model).toBe(0)
})

test('別の session に付けた名前の記録は、この session の判定に効かない', async ($, on) => {
  // session s2 に mod が付けた名前と同じ文字列を、user が s1 に付けた状態
  const calls = engine(on, ['別の名前'], { entries: owned('s2', '同じ名前') })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: '同じ名前' })

  expect(result.sessionTitle).toBeUndefined()
  expect(calls.model).toBe(0)
})

// 押し出しのテストは store を数百件ずつ読み書きするので、時間の上限を広げる
const PRUNE_TEST = { timeoutMs: 30_000 }

test('付け直さない turn でも、使っている session の記録は古い順の押し出しから外れる', PRUNE_TEST, async ($, on) => {
  // s1 が最も古い状態で SAME の turn を送り、その後に別の session の付け直しで押し出しが起きる
  engine(on, ['SAME', '新しい session', '今の作業'], {
    entries: { ...owned('s1', '前の作業', 0), ...others(MAX_SESSIONS + PRUNE_SLACK + 1) },
  })
  await send($, { prompt: TASK, session_id: 's1', session_title: '前の作業' })
  await send($, { prompt: TASK, session_id: 'new' })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: '前の作業' })

  expect(result.sessionTitle).toBe('今の作業')
})

test('記録が上限と余裕の和を超えたら、最も古い session の記録から消す', PRUNE_TEST, async ($, on) => {
  const calls = engine(on, ['名前', '別の名前'], { entries: others(MAX_SESSIONS + PRUNE_SLACK + 1) })
  await send($, { prompt: TASK, session_id: 'new' })

  // 記録の消えた最も古い session の名前は、user が付けた名前と同じ扱いになる
  const result = await send($, { prompt: TASK, session_id: 'old0', session_title: '名前0' })

  expect(result.sessionTitle).toBeUndefined()
  expect(calls.model).toBe(1)
})

test('記録が上限と余裕の和を超えるまでは消さない', PRUNE_TEST, async ($, on) => {
  engine(on, ['名前', '別の名前'], { entries: others(MAX_SESSIONS + PRUNE_SLACK) })
  await send($, { prompt: TASK, session_id: 'new' })

  const result = await send($, { prompt: TASK, session_id: 'old0', session_title: '名前0' })

  expect(result.sessionTitle).toBe('別の名前')
})

for (const reply of ['SAME', 'SAME.', 'same', '**SAME**', 'SAME（続き）']) {
  test(`続きを示す返答「${reply}」では付け直さない`, async ($, on) => {
    engine(on, [reply])

    const result = await send($, { prompt: TASK })

    expect(result.sessionTitle).toBeUndefined()
  })
}

for (const reply of ['Same Origin Policyの検証', 'same-site以外の設定', 'Sameの意味']) {
  test(`same で始まる名前「${reply}」は名前として読む`, async ($, on) => {
    engine(on, [reply])

    const result = await send($, { prompt: TASK })

    expect(result.sessionTitle).toBe(reply)
  })
}

for (const prompt of ['OK', '  はい  ', 'それで進めて']) {
  test(`短い返答「${prompt}」では要約を呼ばない`, async ($, on) => {
    const calls = engine(on, ['名前'])

    const result = await send($, { prompt })

    expect(result.sessionTitle).toBeUndefined()
    expect(calls.model).toBe(0)
  })
}

test('短くても issue / CL の番号を含む prompt は要約に回す', async ($, on) => {
  engine(on, ['#123 の対応'])

  const result = await send($, { prompt: '#123 やって' })

  expect(result.sessionTitle).toBe('#123 の対応')
})

test('短い返答の turn でも、使っている session の記録は押し出しから外れる', PRUNE_TEST, async ($, on) => {
  engine(on, ['新しい session', '今の作業'], {
    entries: { ...owned('s1', '前の作業', 0), ...others(MAX_SESSIONS + PRUNE_SLACK + 1) },
  })
  await send($, { prompt: 'OK', session_id: 's1', session_title: '前の作業' })
  await send($, { prompt: TASK, session_id: 'new' })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: '前の作業' })

  expect(result.sessionTitle).toBe('今の作業')
})

test('返答が今の名前と同じなら付け直さない', async ($, on) => {
  engine(on, ['いまの名前'], { entries: owned('s1', 'いまの名前') })

  const result = await send($, { prompt: TASK, session_id: 's1', session_title: 'いまの名前' })

  expect(result.sessionTitle).toBeUndefined()
})

test('要約が失敗・時間切れなら今の名前のまま進む', async ($, on) => {
  engine(on, [])

  const result = await send($, { prompt: TASK })

  expect(result.sessionTitle).toBeUndefined()
  expect(result.block).toBeUndefined()
})

test('要約の呼び出しが reject しても、他の hook の結果のまま進む', async ($, on) => {
  mock.store(on)
  on('classic.UserPromptSubmit', () => ({ additionalContext: ['下の hook'] }))
  on('model.complete', () => {
    throw new Error('transport')
  })

  const result = await send($, { prompt: TASK })

  expect(result).toEqual({ additionalContext: ['下の hook'] })
})

test('他の hook が prompt を止めたら名前を付けない', async ($, on) => {
  engine(on, ['名前'], { beneath: { block: '止めた理由' } })

  const result = await send($, { prompt: TASK })

  expect(result).toEqual({ block: '止めた理由' })
})

test('他の hook が付けた名前を上書きしない', async ($, on) => {
  engine(on, ['名前'], { beneath: { sessionTitle: '他の hook の名前' } })

  const result = await send($, { prompt: TASK })

  expect(result.sessionTitle).toBe('他の hook の名前')
})

test('長すぎる返答は全角 24 字で切る', async ($, on) => {
  engine(on, ['とても長いタスクの名前がここに入っていて上限を超えたので切られる'])

  const result = await send($, { prompt: TASK })

  expect(result.sessionTitle).toBe('とても長いタスクの名前がここに入っていて上限を超')
})

for (const [reply, expected] of [
  ['「名前」', '名前'], ['“名前”', '名前'], ['`名前`', '名前'], ['名前。', '名前'], ['【調査】herdr設計', '【調査】herdr設計'],
] as const) {
  test(`返答の両端の引用符と句点だけを外す: ${reply}`, async ($, on) => {
    engine(on, [reply])

    const result = await send($, { prompt: TASK })

    expect(result.sessionTitle).toBe(expected)
  })
}

test('返答の制御文字は名前に入れない', async ($, on) => {
  engine(on, ['名\u001b]0;x\u0007前'])

  const result = await send($, { prompt: TASK })

  expect(result.sessionTitle).toBe('名]0;x前')
})

for (const source of ['system', 'sdk', 'loop_wakeup'] as const) {
  test(`機械の turn（source: ${source}）では触らない`, async ($, on) => {
    const calls = engine(on, ['名前'])

    const result = await $.classic.UserPromptSubmit({ prompt: 'task notification', source })

    expect(result.sessionTitle).toBeUndefined()
    expect(calls.model).toBe(0)
  })
}

test('source の無い turn は user の turn として付け直す', async ($, on) => {
  engine(on, ['名前'])

  const result = await $.classic.UserPromptSubmit({ prompt: TASK })

  expect(result.sessionTitle).toBe('名前')
})

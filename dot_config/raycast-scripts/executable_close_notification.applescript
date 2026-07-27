-- macOS 26 Tahoe 通知を閉じるスクリプト
--
-- 【macOS 26 TahoeでのUI構造調査結果】
-- 通知センターの階層構造:
--   window "Notification Center"
--     → group 1
--       → group 1  ★Tahoeで追加された階層
--         → scroll area 1
--           → group 1  ★通知コンテナ
--             → groups (各通知グループ: group 1, group 2, ...)
--               → subrole: AXNotificationCenterAlert/AlertStack
--
-- 【過去バージョンとの違い】
-- - Big Sur〜Sequoia: group 1 → scroll area 1 (group 1が1つだけ)
-- - Tahoe 26.0:       group 1 → group 1 → scroll area 1 (group 1が2つ)
--
-- 【通知を閉じる方法】
-- scroll area 1 直下に group (通知) が配置されている
-- 各通知(group)にはactionsプロパティがあり、以下のようなactionが含まれる:
--   - "Name:Clear All" (すべて消去) - AlertStackの場合
--   - "Name:Close" (閉じる) - Alert/AlertStack両方
--   - "Name:Show Details" (詳細を表示)
--   - "Name:Show" (表示)
-- このうち "Clear All" または "Close" を含むactionをperformすれば通知が閉じる
--
-- 【UI構造の調査方法】
-- ターミナルから以下のコマンドで調査可能:
--   osascript -e 'tell application "System Events" to tell process "NotificationCenter" to tell window "Notification Center" to get properties'
--   osascript -e 'tell application "System Events" to tell process "NotificationCenter" to tell window "Notification Center" to tell group 1 to tell group 1 to tell scroll area 1 to tell UI element 1 to tell group 1 to get name of actions'

tell application "System Events"
	try
		tell application process "NotificationCenter"
			tell window "Notification Center"
				tell group 1
					tell group 1
						tell scroll area 1
							-- scroll area 直下の全UI要素をループ
							set uiElementsList to UI elements
							repeat with uiElem in uiElementsList
								try
									tell uiElem
										-- まずこの要素自体のアクションをチェック（単一通知の場合）
										set elemActions to actions
										repeat with elemAction in elemActions
											set actionName to name of elemAction
											if actionName contains "Clear All" or actionName contains "Close" then
												perform elemAction
											end if
										end repeat

										-- 次に子要素をチェック（コンテナの場合）
										try
											set childElements to UI elements
											repeat with childElem in childElements
												try
													tell childElem
														set childActions to actions
														repeat with childAction in childActions
															set childActionName to name of childAction
															if childActionName contains "Clear All" or childActionName contains "Close" then
																perform childAction
															end if
														end repeat
													end tell
												end try
											end repeat
										end try
									end tell
								on error
									-- 通知が見つからない、またはアクセスできない場合はスキップ
								end try
							end repeat
						end tell
					end tell
				end tell
			end tell
		end tell
	on error errMsg
		-- エラーが発生した場合は何もしない
		-- デバッグ時は以下のコメントを外してエラーを確認:
		-- display dialog "Error: " & errMsg buttons {"OK"} default button "OK"
	end try
end tell

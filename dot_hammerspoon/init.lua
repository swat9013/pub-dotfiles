-- ~/.hammerspoon/init.lua
-- 管理: chezmoi source = dot_hammerspoon/init.lua
-- 役割: hotkey → アクション、外部ディスプレイ接続/切断時の自動処理、ログイン時ジョブ、朝の URL。
-- 修飾キーの物理リマップ (caps→ctrl, cmd↔opt 入替, 日本語キー変換) は Karabiner が担当する。

local home = os.getenv("HOME")
local raycastScripts = home .. "/.config/raycast-scripts/"

-- アプリ起動 (launchOrFocus 系 — 未起動なら起動する)
local launchApps = {
  ["1"] = "Google Chrome",
  ["2"] = "Obsidian",
  ["3"] = "Slack",
  ["4"] = "Todoist",
  ["5"] = "Ghostty",
  ["6"] = "Claude",
  ["9"] = "Orca",
  ["0"] = "Finder",
}
for key, appName in pairs(launchApps) do
  hs.hotkey.bind({"ctrl"}, key, function()
    hs.application.launchOrFocus(appName)
  end)
end

-- アプリフォーカス (focusIfRunning 系 — 起動中のみ、未起動なら何もしない)
-- ctrl+6 は意図的に未割当 (元の karabiner にも存在しない)
local focusApps = {
  ["7"] = "com.amazon.Lassen",     -- Amazon Kindle
  ["8"] = "com.microsoft.VSCode",  -- Visual Studio Code
}
local function focusIfRunning(bundleID)
  local app = hs.application.get(bundleID)
  if app then app:activate(true) end
end
for key, bundleID in pairs(focusApps) do
  hs.hotkey.bind({"ctrl"}, key, function()
    focusIfRunning(bundleID)
  end)
end

-- スクリプト実行
hs.hotkey.bind({"cmd", "alt"}, "0", function()
  hs.osascript.applescriptFromFile(raycastScripts .. "close_notification.applescript")
end)
hs.hotkey.bind({"cmd", "alt"}, "9", function()
  hs.osascript.applescriptFromFile(raycastScripts .. "move_mouse_to_center.applescript")
end)

-- 外部ディスプレイ監視: 接続→内蔵ディスプレイ輝度MAX / 切断→内蔵スピーカー消音。
-- 輝度・音量とも「内蔵 (built-in)」を明示特定して対象にする。key code シミュレートや
-- defaultOutputDevice() だと外部ディスプレイ / 外部出力を誤って変えてしまうため。
lastScreenCount = #hs.screen.allScreens()
screenWatcher = hs.screen.watcher.new(function()
  local now = #hs.screen.allScreens()
  if now > lastScreenCount then
    -- 接続: 内蔵ディスプレイ (name に "Built-in" を含む) の輝度を MAX にする
    local builtin
    for _, scr in ipairs(hs.screen.allScreens()) do
      if (scr:name() or ""):find("Built%-in") then builtin = scr; break end
    end
    if builtin then builtin:setBrightness(1.0) else hs.alert.show("built-in display not found") end
  elseif now < lastScreenCount then
    -- 切断: 内蔵スピーカー (transportType "Built-in") を消音する
    local builtin
    for _, dev in ipairs(hs.audiodevice.allOutputDevices()) do
      if dev:transportType() == "Built-in" then builtin = dev; break end
    end
    if builtin then builtin:setVolume(0) else hs.alert.show("built-in speaker not found") end
  end
  lastScreenCount = now
end)
screenWatcher:start()

-- ログイン時ジョブ: plugin-update。
-- init.lua は hs.reload() でも再実行されるため、HS プロセスの PID を hs.settings に永続化し、
-- 前回と異なる PID のとき (= ログインに伴う HS 新規起動) のみ実行する。
-- hs.task はリロード時の Lua state 破棄で実行中の子プロセスを terminate するため使わず、
-- nohup + & で HS から切り離して起動する (成否通知はスクリプト自身の osascript が担う)。
-- plugin-update が導入されていない環境もあるため、実体の有無を確認してから起動する。
local pluginUpdateScript = home .. "/.local/libexec/plugin-update.sh"
local pluginUpdatePidKey = "pluginUpdate.lastRunPid"
if hs.fs.attributes(pluginUpdateScript)
  and hs.settings.get(pluginUpdatePidKey) ~= hs.processInfo.processID then
  hs.settings.set(pluginUpdatePidKey, hs.processInfo.processID)
  os.execute("nohup '" .. pluginUpdateScript .. "'"
    .. " >> '" .. home .. "/Library/Logs/plugin-update.log' 2>&1 &")
end

-- 朝の URL: 指定曜日の指定時間帯に、その日初めて PC を開いたとき (ログイン / スリープ復帰 / 画面ロック解除)
-- URL を既定ブラウザで開く。設定は非公開の local.lua (未配置なら機能ごと無効):
--   return { morningURL = { url = "https://...", from = "05:00", to = "09:30",
--                           weekdays = {2, 3, 4, 5, 6} } }  -- os.date の wday (1=日)
-- 同日 2 回目以降は開かない (最終実行日を hs.settings に永続化)。
local localOk, localConfig = pcall(dofile, home .. "/.hammerspoon/local.lua")
local morningURL = localOk and type(localConfig) == "table" and localConfig.morningURL or nil
local function toMinutes(hhmm)
  local h, m = hhmm:match("^(%d+):(%d+)$")
  return tonumber(h) * 60 + tonumber(m)
end
local function openMorningURL()
  local now = os.date("*t")
  local today = os.date("%Y-%m-%d")
  if hs.settings.get("morningURL.lastDate") == today then return end
  local isTargetDay = false
  for _, wday in ipairs(morningURL.weekdays or {2, 3, 4, 5, 6}) do
    if wday == now.wday then isTargetDay = true; break end
  end
  if not isTargetDay then return end
  local minutes = now.hour * 60 + now.min
  if minutes < toMinutes(morningURL.from) or minutes >= toMinutes(morningURL.to) then return end
  hs.settings.set("morningURL.lastDate", today)
  hs.urlevent.openURL(morningURL.url)
end
if morningURL then
  -- ログイン判定は plugin-update と同じく HS プロセスの PID の変化で行う (リロードでは発火しない)
  if hs.settings.get("morningURL.lastPid") ~= hs.processInfo.processID then
    hs.settings.set("morningURL.lastPid", hs.processInfo.processID)
    openMorningURL()
  end
  -- watcher は GC 回避のためグローバルに保持する
  morningURLWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake
      or event == hs.caffeinate.watcher.screensDidUnlock then
      openMorningURL()
    end
  end)
  morningURLWatcher:start()
end

-- 設定の自動リロード (開発ループ)。watcher は GC 回避のためグローバルに保持する。
configWatcher = hs.pathwatcher.new(home .. "/.hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end)
configWatcher:start()

hs.alert.show("Hammerspoon config loaded")

-- Git status colors (Tokyo Night theme)
th.git = th.git or {}
th.git.modified = ui.Style():fg("#e0af68")
th.git.added = ui.Style():fg("#9ece6a")
th.git.untracked = ui.Style():fg("#bb9af7")
th.git.ignored = ui.Style():fg("#626880")
th.git.deleted = ui.Style():fg("#f7768e")
th.git.updated = ui.Style():fg("#7aa2f7")

require("git"):setup()

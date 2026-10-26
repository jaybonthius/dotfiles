-- Make macOS Option act as Meta, like Ghostty's macos-option-as-alt = true.
-- Each Option+key types ESC followed by the key (US layout), so Emacs sees M-key.
local terminal = "com.superlogical.terminal"

local function meta(text)
  return function(ctx, ev)
    rex.block.call(terminal, "write", { block_id = ctx.block_id, data = "\27" .. text })
    return true
  end
end

local shifted = {
  ["`"] = "~", ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%",
  ["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")", ["-"] = "_",
  ["="] = "+", ["["] = "{", ["]"] = "}", ["\\"] = "|", [";"] = ":", ["'"] = "\"",
  [","] = "<", ["."] = ">", ["/"] = "?",
}

for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
  rex.bind("alt+" .. c, meta(c))
  rex.bind("alt+shift+" .. c, meta(c:upper()))
end

for c, s in pairs(shifted) do
  rex.bind("alt+" .. c, meta(c))
  rex.bind("alt+shift+" .. c, meta(s))
end

rex.bind("alt+space", meta(" "))
rex.bind("alt+backspace", meta("\127"))

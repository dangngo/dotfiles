local wezterm = require 'wezterm';

function extract_filename(uri)
  local start, match_end = uri:find("$EDITOR:");
  if start == 1 then
    -- filepath /path/to/file.txt:row:column
    local filepath = uri:sub(match_end+1)
    local start, match_end = filepath:find(":");
    -- filename /path/to/file.txt
    local filename = filepath:sub(0, match_end - 1)

    -- row_col 10:5
    local row_col = filepath:sub(match_end + 1)
    local start, match_end = row_col:find(":");
    local row = row_col:sub(0, match_end - 1)
    local col = row_col:sub(match_end + 1)

    return filename, row, col
  end
  return nil
end

function debug(str)
  local text = "o" .. str
  return wezterm.action{SendString=text}
end

wezterm.on("open-uri", function(window, pane, uri)
  local name, row, col = extract_filename(uri)
  if name then
    local script_path = os.getenv("WEZTERM_CONFIG_DIR") .. "/scripts/edit_file"
    
    -- debugging
    -- local action = debug(script_path .. "/wezterm.lua")

    -- example: ~/.zshrc:10:5
    local action = wezterm.action{SpawnCommandInNewTab={
        args={"/bin/sh", script_path, name, row}
      }};

    window:perform_action(action, pane);

    -- prevent the default action from opening in a browser
    return false
  end
end)

return {
  -- Font 
  font = wezterm.font("Iosevka Nerd Font", {weight = "Bold"}),
  font_size = 14,

  -- Colors
  color_scheme = "NightFox",

  -- Window
  hide_tab_bar_if_only_one_tab = true,
  audible_bell = "Disabled",
  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },
  hyperlink_rules = {
    -- Defaults, don't edit
    -- URL
    -- example https://wezfurlong.org/wezterm/hyperlinks.html
    {
      regex = "\\b\\w+://(?:[\\w.-]+)\\.[a-z]{2,15}\\S*\\b",
      format = "$0",
    },

    -- Email addresses
    -- exampel: ngominh.dang96@gmail.com
    {
      regex = "\\b[-_.A-Za-z0-9]+@[\\w-]+(\\.[\\w-]+)+\\b",
      format = "mailto:$0",
    },
    -- file:// URI
    -- example: file:///Users/141217/.config/wezterm/wezterm.lua
    {
      regex = "\\bfile://\\S*\\b",
      format = "$0",
    },
    
    -- Custom
    -- Open file at line for debug
    -- example: /Users/141217/work/repos/cdo-k8s-kops/k8s.dev.cdgfossil.com/s1.k8s.dev.cdgfossil.com.yaml:10:5
    {
      regex = "(?:[-.\\w@~/]+)?(?:/[.\\w\\-@]+)+:\\d+:\\d+",
      format = "$EDITOR:$0",
    },

  },
}

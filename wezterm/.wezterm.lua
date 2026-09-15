local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

-- 配色方案：設為 Solarized Dark (Gogh)，與 Herdr 保持一致
config.color_scheme = 'Solarized Dark (Gogh)'

-- 啟用 WezTerm 原生分頁列
config.enable_tab_bar = true

-- 預設字型大小：14pt
config.font_size = 14.0

-- 邊距調整為 0，讓 Herdr 的邊界與視窗無縫貼合
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

-- ----------------------------------------------------
-- 自動記憶與還原視窗大小 (Window Size Persistence)
-- ----------------------------------------------------
local size_file = wezterm.home_dir .. '/.config/wezterm/window_size.json'

local function read_saved_size()
  local f = io.open(size_file, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  if ok and type(data) == 'table' then
    return data
  end
  return nil
end

local function save_window_size(window, pane)
  if not window then return end
  local dim = window:get_dimensions()
  if dim.is_full_screen then return end

  pane = pane or window:active_pane()
  local p_dim = pane and pane:get_dimensions() or {}

  local data = {
    cols = p_dim.cols,
    rows = p_dim.viewport_rows,
    pixel_width = dim.pixel_width,
    pixel_height = dim.pixel_height,
    dpi = dim.dpi,
  }

  local f = io.open(size_file, 'w')
  if f then
    f:write(wezterm.json_encode(data))
    f:close()
  end
end

-- 當視窗大小改變時，自動記錄最新尺寸
wezterm.on('window-resized', function(window, pane)
  save_window_size(window, pane)
end)

-- 當重新載入設定檔時 (例如按 Ctrl+Shift+R)，立刻記錄當下視窗大小
wezterm.on('window-config-reloaded', function(window, pane)
  save_window_size(window, pane)
end)

-- 啟動時先以記憶的行列數初始化視窗
local saved_size = read_saved_size()
if saved_size and saved_size.cols and saved_size.rows then
  config.initial_cols = saved_size.cols
  config.initial_rows = saved_size.rows
end

-- ----------------------------------------------------
-- 快速啟動選單 (Launch Menu)
-- ----------------------------------------------------
config.launch_menu = {
  {
    label = 'Windows Herdr',
    args = { 'herdr.exe' },
  },
  {
    label = 'WSL Herdr',
    args = { 'wsl.exe', '-d', 'Ubuntu', '--cd', '~', 'herdr' },
  },
}

-- ----------------------------------------------------
-- 視窗開啟時預設啟動兩個分頁：Windows Herdr 與 WSL Herdr
-- ----------------------------------------------------
wezterm.on('gui-startup', function(cmd)
  local window
  local tab_win

  if cmd and cmd.args and #cmd.args > 0 then
    tab_win, _, window = mux.spawn_window(cmd)
  else
    -- Tab 1: Windows Herdr
    local _
    tab_win, _, window = mux.spawn_window {
      args = { 'herdr.exe' },
    }
    tab_win:set_title('Windows Herdr')

    -- Tab 2: WSL Herdr
    local tab_wsl, _ = window:spawn_tab {
      args = { 'wsl.exe', '-d', 'Ubuntu', '--cd', '~', 'herdr' },
    }
    tab_wsl:set_title('WSL Herdr')

    -- 預設選取第一個分頁
    tab_win:activate()
  end

  -- 還原精確像素大小
  local saved = read_saved_size()
  if saved and saved.pixel_width and saved.pixel_height then
    local gui_win = window:gui_window()
    if gui_win then
      gui_win:set_inner_size(saved.pixel_width, saved.pixel_height)
    end
  end
end)

return config

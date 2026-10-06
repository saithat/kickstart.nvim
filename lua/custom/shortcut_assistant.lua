local M = {}
local history_path = vim.fn.stdpath('state') .. '/shortcut-assistant/history.jsonl'

local modes = {
  { name = 'normal', keys = { 'n' } },
  { name = 'visual', keys = { 'v', 'x' } },
  { name = 'insert', keys = { 'i' } },
  { name = 'terminal', keys = { 't' } },
}

local function readable_keys(lhs)
  local notation = lhs:find('<[^>]+>') and lhs or vim.fn.keytrans(lhs)
  local chars = vim.fn.split(notation, [[\zs]])
  local keys = {}
  local i = 1

  while i <= #chars do
    local key = chars[i]
    if key == '<' then
      local parts = { key }
      repeat
        i = i + 1
        key = chars[i]
        if key then parts[#parts + 1] = key end
      until not key or key == '>'
      key = table.concat(parts)
    end

    keys[#keys + 1] = ({ ['<Space>'] = 'Space', ['<CR>'] = 'Enter', ['<Tab>'] = 'Tab', ['<Esc>'] = 'Esc' })[key] or key
    i = i + 1
  end

  return table.concat(keys, ' ')
end

local function active_mappings(buf)
  local lines = {}

  for _, mode in ipairs(modes) do
    local mappings = {}
    local mode_lines = {}
    for _, key in ipairs(mode.keys) do
      for _, map in ipairs(vim.api.nvim_get_keymap(key)) do
        if map.desc and map.desc ~= '' and not map.lhs:match('^<Plug>') then mappings[map.lhs] = map end
      end
    end
    for _, key in ipairs(mode.keys) do
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, key)) do
        if map.desc and map.desc ~= '' and not map.lhs:match('^<Plug>') then mappings[map.lhs] = map end
      end
    end

    for _, map in pairs(mappings) do
      local action = map.desc:gsub('%[([^%]]+)%]', '%1'):gsub('%s+', ' ')
      mode_lines[#mode_lines + 1] = ('%s | %s | %s'):format(mode.name, readable_keys(map.lhs), action)
    end
    table.sort(mode_lines)
    vim.list_extend(lines, mode_lines)
  end

  return table.concat(lines, '\n')
end

function M.prompt(buf)
  return ([[
You answer questions about Neovim keys and commands. The active buffer has filetype %s.
The list below contains the active custom mappings. A buffer-local mapping overrides
a global mapping with the same mode and keys.

Active mappings (mode | keys to press in order | action):
%s

Question: $input

Give the shortest correct sequence of keys or Ex commands that completes the
task. For multiple actions, put the steps in order, one short line each:
"keys or :command — brief explanation". For one action, use one line.

For custom actions, copy the complete matching keys column, including Space
and letter case. Space means press the space bar. Explain only the action from
the same row. Prefer active mappings over equivalent built-in commands. For
built-in commands, use standard Neovim syntax and include Enter if needed.
Put the colon immediately before an Ex command, as in :write<Enter>.
Mention the required mode or a prerequisite only when it matters. If asked
about command flags, explain them briefly. Do not invent mappings or commands;
say when you cannot verify a step. Do not add headings or unrelated steps.
]]):format(vim.bo[buf].filetype, active_mappings(buf))
end

local function ask()
  local buf = vim.api.nvim_get_current_buf()
  local gen = require 'gen'
  gen.prompts.Ask_Shortcut = {
    prompt = function()
      local question = vim.fn.input('Neovim question: ')
      if question:match('^%s*$') then return nil end
      local prompt = M.prompt(buf):gsub('%$input', function() return question end)
      local safe_prompt = prompt:gsub('%%', '\29'):gsub('%$', '\30')
      return safe_prompt
    end,
    replace = false,
    body = { think = 'low', keep_alive = 0, options = { temperature = 0, num_predict = 768, num_ctx = 8192 } },
    command = function()
      local script = vim.fn.stdpath('config') .. '/scripts/shortcut_history_proxy.py'
      return ('python3 %s %s $body'):format(vim.fn.shellescape(script), vim.fn.shellescape(history_path))
    end,
  }
  vim.cmd 'Gen Ask_Shortcut'
end

local function ollama_ready()
  return vim.system({ 'curl', '--silent', '--fail', '--max-time', '1', 'http://127.0.0.1:11434/api/tags' }):wait().code == 0
end

local function start_ollama()
  if ollama_ready() then return end

  local job = vim.fn.jobstart({ 'ollama', 'serve' }, { detach = true })
  if job <= 0 or not vim.wait(5000, ollama_ready, 100) then error('Could not start the local Ollama server') end
end

function M.setup()
  require('gen').setup { model = 'gpt-oss:20b', init = start_ollama }
  vim.keymap.set('n', '<leader>sa', ask, { desc = '[S]earch [A]sk about shortcuts' })
  vim.api.nvim_create_user_command('ShortcutHistory', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(history_path))
  end, { desc = 'Open saved Neovim shortcut questions and answers' })
end

return M

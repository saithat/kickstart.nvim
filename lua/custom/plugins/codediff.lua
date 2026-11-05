-- codediff.nvim: VSCode-style side-by-side diffs for reviewing changes
-- (e.g. what a coding agent just did) with a file explorer, staging, and history.
-- https://github.com/esmuellert/codediff.nvim
--
-- Note: on first use it downloads a prebuilt diff library from the plugin's
-- GitHub releases. `:CodeDiff install!` forces a reinstall.

vim.pack.add {
  { src = 'https://github.com/esmuellert/codediff.nvim', version = vim.version.range '*' },
}

require('codediff').setup {
  explorer = {
    view_mode = 'tree',
    line_stats = { enabled = true },
  },
  diff = {
    -- Fold unchanged code, keeping some context around each hunk
    compact = true,
    compact_context_lines = 8,
  },
}

vim.keymap.set('n', '<leader>dv', '<Cmd>CodeDiff<CR>', { desc = '[D]iff: toggle CodeDiff [v]iew' })
vim.keymap.set('n', '<leader>dh', '<Cmd>CodeDiff history %<CR>', { desc = '[D]iff: file [h]istory' })
vim.keymap.set('n', '<leader>dH', '<Cmd>CodeDiff history<CR>', { desc = '[D]iff: repo [H]istory' })

local ok, wk = pcall(require, 'which-key')
if ok then wk.add { { '<leader>d', group = '[D]iff' } } end

-- Workaround for neovim/neovim#40290 (fixed in Neovim master by #42301, not in
-- 0.12.6): the treesitter fold module's OptionSet autocmd crashes with
-- "Invalid buffer id" when codediff's compact mode sets 'foldminlines' after a
-- diff buffer was wiped. Drop that autocmd; it only matters when changing
-- foldminlines/foldnestmax. Remove once on a Neovim release that has the fix.
if vim.fn.has 'nvim-0.13' == 0 then
  require 'vim.treesitter._fold'
  for _, au in ipairs(vim.api.nvim_get_autocmds { event = 'OptionSet' }) do
    if au.desc == 'Refresh treesitter folds' then vim.api.nvim_del_autocmd(au.id) end
  end
end

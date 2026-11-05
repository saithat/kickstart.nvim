-- oil.nvim: edit the file system like a normal buffer
-- https://github.com/stevearc/oil.nvim
--
-- Usage: `-` opens the parent directory. Edit lines to rename/create/delete
-- files, then `:w` to apply. `<CR>` opens, `-` goes up, `g?` shows help.

vim.pack.add {
  { src = 'https://github.com/stevearc/oil.nvim', version = vim.version.range '*' },
}

require('oil').setup {
  -- Open directories (e.g. `nvim .`) in oil instead of netrw / neo-tree
  default_file_explorer = true,
  view_options = {
    show_hidden = true,
  },
}

vim.keymap.set('n', '-', '<Cmd>Oil<CR>', { desc = 'Open parent directory (oil)' })

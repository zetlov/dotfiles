-- display
--- show line number
vim.opt.number = true
vim.opt.relativenumber = true
--- show matching bracket
vim.opt.showmatch = true
vim.opt.matchtime = 1
--- show command as typed
vim.opt.showcmd = true
--- highlight current line
vim.opt.cursorline = true

-- input
--- tab
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
--- completion
vim.opt.wildmenu = true
vim.opt.wildmode = {'longest', 'list', 'full'}

--search
--- ignore case
vim.opt.ignorecase = true
vim.opt.smartcase = true
--- highlight searuch
vim.opt.hlsearch = true
vim.opt.incsearch = true
--- back to head when reach the bottom
vim.opt.wrapscan = true

--backspace
vim.opt.backspace = {'start', 'eol', 'indent'}

-- file
--- do not backup
vim.opt.backup = false
--- do not make swap files
vim.opt.swapfile = false
--- read file automatically when it changes
vim.opt.autoread = true
--- enable to open when editing
vim.opt.hidden = true
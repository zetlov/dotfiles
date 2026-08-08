vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

    -- import文をスキップしてソース定義まで飛ぶ gd
    vim.keymap.set("n", "gd", function()
      vim.lsp.buf.definition({
        on_list = function(opts)
          if not opts.items or #opts.items == 0 then return end
          if #opts.items > 1 then
            vim.fn.setqflist({}, " ", opts)
            vim.cmd("copen")
            return
          end
          local item = opts.items[1]
          local fname = item.filename
          local lnum = item.lnum or 1
          local col = (item.col or 1) - 1
          local buf = vim.fn.bufadd(fname)
          vim.fn.bufload(buf)
          local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
          vim.cmd("edit " .. vim.fn.fnameescape(fname))
          vim.api.nvim_win_set_cursor(0, { lnum, col })
          -- import行だったらもう一度定義へ
          if line:match("^%s*from%s+") or line:match("^%s*import%s+") then
            vim.lsp.buf.definition()
          end
        end,
      })
    end, { buffer = bufnr, desc = "Go to Definition (smart)" })
  end,
})

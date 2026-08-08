return {
  {
    "mfussenegger/nvim-dap",
    cond = function() return not vim.g.vscode end,
    dependencies = {
      -- UI
      {
        "rcarriga/nvim-dap-ui",
        dependencies = { "nvim-neotest/nvim-nio" }, -- dap-ui必須
      },
      -- 変数の値をvirtual text表示
      { "theHamsta/nvim-dap-virtual-text" },

      -- mason連携（デバッガのインストール＆プリセット設定）
      {
        "jay-babu/mason-nvim-dap.nvim",
        dependencies = { "williamboman/mason.nvim" },
      },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      -- 見た目（好みで変えてOK）
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticWarn", linehl = "Visual" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticHint" })

      -- dap-ui
      dapui.setup()

      -- セッション開始/終了でUIを自動開閉（定番）
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- virtual text（標準はこれで十分）
      require("nvim-dap-virtual-text").setup({
        commented = true,
      })

      -- mason-nvim-dap
      -- ここで指定するのは「dapのアダプタ名」（例: python, delve）で、masonのパッケージ名じゃない点に注意
      -- （python <-> debugpy みたいに変換してくれる）:contentReference[oaicite:3]{index=3}
      require("mason-nvim-dap").setup({
        ensure_installed = {
          "python",
        },
        handlers = {}, -- 何も書かなければプリセットで自動セットアップ :contentReference[oaicite:4]{index=4}
      })
    end,
  },
}

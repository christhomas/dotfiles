return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
        "codelldb",
      },
    },
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
   'mrcjkb/rustaceanvim',
    version = '^5', -- Recommended
    lazy = false, -- This plugin is already lazy  
    ft = "rust",
    dependencies = { "WhoIsSethDaniel/mason-tool-installer.nvim" },
    config = function ()
      local adapter_path = vim.fn.expand("$MASON/packages/codelldb/extension/adapter/codelldb")
      if vim.fn.executable(adapter_path) == 0 then
        vim.notify("codelldb not installed — run :MasonInstall codelldb", vim.log.levels.WARN)
        return
      end

      vim.g.rustaceanvim = {
        dap = {
          adapter = {
            type = "server",
            port = "${port}",
            executable = {
              command = adapter_path,
              args = { "--port", "${port}" },
            },
          },
        },
      }
    end
  },

  {
    'mfussenegger/nvim-dap',
    config = function()
			local dap, dapui = require("dap"), require("dapui")
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
		end
  },

  {
    'rcarriga/nvim-dap-ui', 
    dependencies = {"mfussenegger/nvim-dap", "nvim-neotest/nvim-nio"},
    config = function()
			require("dapui").setup()
		end,
  },
  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
}

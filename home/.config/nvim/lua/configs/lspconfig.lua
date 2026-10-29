-- load defaults i.e lua_lsp
-- (sets capabilities/on_init for all servers via vim.lsp.config("*")
-- and on_attach keymaps via an LspAttach autocmd)
require("nvchad.configs.lspconfig").defaults()

-- EXAMPLE
local servers = { "html", "cssls" }

-- lsps with default config
vim.lsp.enable(servers)

-- configuring single server, example: typescript
-- vim.lsp.config("ts_ls", {
--   settings = { ... },
-- })
-- vim.lsp.enable "ts_ls"

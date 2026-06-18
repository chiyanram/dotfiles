local M = {}

local border = {
  { "🭽", "FloatBorder" },
  { "▔", "FloatBorder" },
  { "🭾", "FloatBorder" },
  { "▕", "FloatBorder" },
  { "🭿", "FloatBorder" },
  { "▁", "FloatBorder" },
  { "🭼", "FloatBorder" },
  { "▏", "FloatBorder" },
}

---Show LSP diagnostics
function M.lsp_show_diagnostics()
  vim.diagnostic.open_float({ border = border })
end

---setup default capabilities and configuration for an lsp
---@param ... table<any, any> Overrides to apply to the configuration
function M.make_conf(...)
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true,
  }
  capabilities.textDocument.completion.completionItem.snippetSupport = true
  capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = { "documentation", "detail", "additionalTextEdits", "documentHighlight" },
  }
  capabilities.textDocument.colorProvider = { dynamicRegistration = false }
  capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)

  return vim.tbl_deep_extend("force", {
    handlers = {
      ["textDocument/hover"] = function(err, result, ctx, config)
        return vim.lsp.handlers.hover(err, result, ctx, vim.tbl_deep_extend("force", config or {}, { border = border }))
      end,
      ["textDocument/signatureHelp"] = function(err, result, ctx, config)
        return vim.lsp.handlers.signature_help(
          err,
          result,
          ctx,
          vim.tbl_deep_extend("force", config or {}, { border = border })
        )
      end,
    },
    capabilities = capabilities,
  }, ...)
end

return M

-- lips editor integration for Neovim (built-in LSP).
-- Detects .lips programs and attaches the domain-blind `lips lsp` server,
-- which serves each buffer from its neighbouring <language>.lang (resolved from
-- the program's <instance>.<language>.lips name).

-- Recognise the program extension as its own filetype.
vim.filetype.add({ extension = { lips = "lips" } })

-- Start one server per lips buffer, rooted at the file's directory (where its
-- <language>.lang lives). vim.lsp reuses a client across buffers with the same
-- root.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lips",
  callback = function(args)
    vim.lsp.start({
      name = "lips",
      cmd = { "lips", "lsp" },
      root_dir = vim.fs.dirname(args.file),
    })
  end,
})

-- Completion: the built-in omni-completion (<C-x><C-o>) works out of the box.
-- For as-you-type completion, point nvim-cmp / blink at the `lips` client, or
-- on nvim >= 0.11 enable vim.lsp.completion for the buffer.

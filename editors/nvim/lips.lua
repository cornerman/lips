-- lips editor integration for Neovim (built-in LSP).
-- Detects .loose programs and attaches the domain-blind `lips lsp` server,
-- which serves each buffer from its neighbouring <file>.lang.

-- Recognise the program extension as its own filetype.
vim.filetype.add({ extension = { loose = "loose" } })

-- Start one server per loose buffer, rooted at the file's directory (where its
-- .lang lives). vim.lsp reuses a client across buffers with the same root.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "loose",
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

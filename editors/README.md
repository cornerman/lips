# Editor Integration

One server, every language: `lips lsp` is domain-blind and serves any lips
program from the `<file>.lang` beside it (completion from the language's
patterns, diagnostics from `diagnose`). Configure it once; every program you
mint gets tooling for free. It is pure of AI and offline, like `run`.

`lips` must be on `PATH` (`nix build` then add `result/bin`, or use the
devshell). The convention is that programs end in `.loose`, with a committed
`<program>.loose.lang` next to them.

## Neovim (built-in LSP)

Drop `nvim/lips.lua` into your config (or copy its body). It registers the
`loose` filetype and starts the server on those buffers. Completion is the
built-in LSP omni-completion (`<C-x><C-o>`), or wire your completion plugin
(nvim-cmp / blink) to the `lips` client. Diagnostics show inline.

## Vim (vim-lsp or coc.nvim)

vim-lsp:

    au User lsp_setup call lsp#register_server({
      \ 'name': 'lips',
      \ 'cmd': {server_info->['lips', 'lsp']},
      \ 'allowlist': ['loose'],
      \ })
    au BufRead,BufNewFile *.loose set filetype=loose

Completion via `<C-x><C-o>` (vim-lsp sets omnifunc), or asyncomplete.

## VS Code

VS Code needs a thin extension (it will not launch an arbitrary LSP binary
otherwise). The minimal one is in `vscode/`:

    cd editors/vscode
    npm install
    # then press F5 in VS Code to launch an Extension Development Host,
    # or package it:  npx vsce package   and install the .vsix

It launches `lips lsp` for `.loose` files. Completion and diagnostics then work
like any language.

## Helix

In `languages.toml`:

    [[language]]
    name = "loose"
    scope = "source.loose"
    file-types = ["loose"]
    language-servers = ["lips"]

    [language-server.lips]
    command = "lips"
    args = ["lsp"]

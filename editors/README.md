# Editor Integration

One server, every language: `lips lsp` is domain-blind and serves any lips
program from the shared `<language>.lang` beside it (completion from the
language's patterns, diagnostics from `diagnose`). Configure it once; every
program you mint gets tooling for free. It is pure of AI and offline, like
`run`.

`lips` must be on `PATH`. On NixOS / home-manager, add the flake package
once: `home.packages = [ inputs.lips.packages.${pkgs.system}.default ];`.
Elsewhere, `nix build` then add `result/bin`, or use the devshell. Once `lips`
is on PATH the server (`lips lsp`) is available to every editor below with no
per-language configuration.

Programs are named `<instance>.<language>.lips`: the uniform `.lips`
extension is what every editor associates on, and the server reads the shared
`<language>.lang` beside the program (e.g. `ledger.backup.lips` -> `backup.lang`).

## Neovim (built-in LSP)

Drop `nvim/lips.lua` into your config (or copy its body). It registers the
`lips` filetype and starts the server on those buffers. Completion is the
built-in LSP omni-completion (`<C-x><C-o>`), or wire your completion plugin
(nvim-cmp / blink) to the `lips` client. Diagnostics show inline.

## Vim (vim-lsp or coc.nvim)

vim-lsp:

    au User lsp_setup call lsp#register_server({
      \ 'name': 'lips',
      \ 'cmd': {server_info->['lips', 'lsp']},
      \ 'allowlist': ['lips'],
      \ })
    au BufRead,BufNewFile *.lips set filetype=lips

Completion via `<C-x><C-o>` (vim-lsp sets omnifunc), or asyncomplete.

## VS Code

VS Code needs a thin extension (it will not launch an arbitrary LSP binary
otherwise). The minimal one is in `vscode/`:

    cd editors/vscode
    npm install
    # then press F5 in VS Code to launch an Extension Development Host,
    # or package it:  npx vsce package   and install the .vsix

It launches `lips lsp` for `.lips` files. Completion and diagnostics then work
like any language.

## Helix

In `languages.toml`:

    [[language]]
    name = "lips"
    scope = "source.lips"
    file-types = ["lips"]
    language-servers = ["lips"]

    [language-server.lips]
    command = "lips"
    args = ["lsp"]

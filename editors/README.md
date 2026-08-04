# Editor Integration

One server, every language: `lips lsp` is domain-blind and serves any lips
program from the shared `<language>/<language>.lang` beside it. Configure it
once; every program you mint gets tooling for free. It is pure of AI and
offline, like `run`.

Three things it does, all derived from the language beside your program:

- **Completion** from the language's patterns, each hole labelled with the type
  the engine gives it (`serve http on port <port:int>`).
- **Diagnostics** from the same `diagnose` that `lips check` prints: a line no
  pattern reads, a line two patterns read, a question left open, a value the
  option cannot take.
- **Hover** on any line: the pattern that read it, the decisions it states, and
  every option it realizes with the values filled in -- the machinery lips
  derives from your sentence, without compiling.

`lips` must be on `PATH`. On NixOS / home-manager, add the flake package
once: `home.packages = [ inputs.lips.packages.${pkgs.system}.default ];`.
Elsewhere, `nix build` then add `result/bin`, or use the devshell. Once `lips`
is on PATH the server (`lips lsp`) is available to every editor below with no
per-language configuration.

Programs are named `<instance>.<language>.lips`: the uniform `.lips`
extension is what every editor associates on, and the server reads the shared
`<language>/<language>.lang` in the language folder beside the program (e.g.
`ledger.backup.lips` -> `backup/backup.lang`).

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

VS Code needs a thin extension: it will not start a language server from
settings, and a language id no extension declares falls back to plain text
([microsoft/vscode#194759](https://github.com/microsoft/vscode/issues/194759)).
So `vscode/` holds one, and it does exactly two things -- declare the `lips`
language for `.lips`, and spawn `lips lsp` over stdio. Every capability lives in
the server, which is why this file has no reason to change as lips grows.

The flake builds it, so nothing needs `npm` at install time:

    nix build .#vscode-extension

On NixOS / home-manager, take it from the flake you already use for `lips`:

    programs.vscode = {
      enable = true;
      mutableExtensionsDir = true;   # keep installing marketplace extensions by hand
      profiles.default.extensions = [
        inputs.lips.packages.${pkgs.system}.vscode-extension
      ];
    };

`lips` must be on `PATH` for the editor process (`home.packages` is enough); the
extension spawns whatever `lips` it finds, so upgrading lips moves the server
without rebuilding the extension.

Elsewhere, or to hack on the extension itself:

    cd editors/vscode
    npm install          # package-lock.json is committed; nix builds from it
    # press F5 in VS Code for an Extension Development Host,
    # or package it:  npx vsce package   and install the .vsix

After changing `package-lock.json`, refresh the hash the flake pins:

    nix run nixpkgs#prefetch-npm-deps -- editors/vscode/package-lock.json

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

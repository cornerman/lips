// Minimal VS Code client for the lips language server. VS Code will not launch
// an arbitrary LSP binary on its own, so this thin extension does it: it starts
// `lips lsp` and routes `.lips` documents to it. All the intelligence lives in
// the server (completion from the language, diagnostics from diagnose); this
// file only wires the transport.

const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

function activate(context) {
  const serverOptions = {
    command: "lips",
    args: ["lsp"],
    transport: TransportKind.stdio,
  };
  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "lips" }],
  };
  client = new LanguageClient("lips", "lips", serverOptions, clientOptions);
  client.start();
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };

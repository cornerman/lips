// The ONLY action a lips mint may take. pi runs the mint with its built-in
// tools and every ambient extension, skill and context file disabled, so this
// file is the mint's complete world: look up an option in the pinned schema of
// the target world. It shells out to the lips binary, so what the model is told
// is exactly what lips itself would say -- there is no second, model-facing
// renderer that could drift from the human-facing one.
//
// There is deliberately no tool that JUDGES an engine. Informing is safe to
// expose; deciding is not, and the gate that decides runs once, in Haskell,
// after the model is done.
//
// pi loads this with `-e` for a single run, so the tool exists inside lips'
// mint and nowhere else: a user's own pi sessions never gain it.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawnSync } from "node:child_process";

// No defaults. A silent fallback would be a lie generator: if the target ever
// failed to reach this child, the mint would search the NixOS schema while
// generating a home-manager engine, and every answer it got would be
// confidently wrong -- exactly the guessing invariant 2 exists to prevent.
// Fail at load, not per call, so the run dies before the model reads anything.
function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `lips mint tool: ${name} is unset. ` +
        "\u2192 run the packaged lips: nix run . -- generate <program>",
    );
  }
  return value;
}

const bin = required("LIPS_BIN");
const target = required("LIPS_MINT_TARGET");

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    // The name states the action, because a name is the first thing the model
    // reads. The CLI verb behind it stays the bare noun `options`, matching
    // generate/compile/check/lsp; the two need not agree.
    name: "query_options",
    label: "Options",
    description:
      "Look up option paths and their types in the pinned schema of the target " +
      "world. QUERY is a dotted prefix (browse a namespace) or any substring of " +
      "a path (find the namespace from a domain word, e.g. 'backup'). A narrow " +
      "query answers with exact 'path : type' lines; a broad one answers with the " +
      "namespaces holding the matches, the one with the most matches first, which " +
      "you then ask about by name. Every option your rules name must appear here, " +
      "or the mint is rejected.",
    parameters: Type.Object({
      query: Type.String({
        description: "A dotted option prefix, or any substring of a path.",
      }),
    }),
    async execute(_toolCallId: string, params: { query: string }) {
      const r = spawnSync(bin, ["options", "--target", target, params.query], {
        encoding: "utf8",
      });
      // stderr carries lips' own deduce-or-fail remedies, which are as useful to
      // the model as the answer itself, so both channels go back verbatim.
      const text = [r.stdout ?? "", r.stderr ?? ""].filter(Boolean).join("\n");
      return { content: [{ type: "text", text: text || "no output" }], details: {} };
    },
  });
}

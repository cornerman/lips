// The ONLY actions a lips mint may take. pi runs the mint with its built-in
// tools and every ambient extension, skill and context file disabled, so this
// file is the mint's complete world: look up an option in the pinned schema of
// the target world, and check a draft engine before answering with it. Both
// shell out to the lips binary, so what the model is told is exactly what lips
// itself would say -- there is no second, model-facing renderer that could
// drift from the human-facing one.
//
// Two tools, and neither one decides. query_options informs about NAMES;
// check_draft REPORTS which gate rejects a draft. The gate that decides still
// runs once, in Haskell, after the model is done -- a model that skips both
// tools is refused by exactly the same gates as before. What moved is when the
// mint can learn it is wrong, not who judges it.
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
// Comma-separated: one call may mint for several worlds, and every lookup names
// the one it is about. A world outside this list is refused rather than searched
// in the wrong schema.
const worlds = required("LIPS_MINT_WORLDS").split(",").filter(Boolean);
// Newline-separated, supplied by generate: the model may not choose which
// programs its draft is judged against, or it could validate against a corpus
// that is not the one being minted.
const programs = required("LIPS_MINT_PROGRAMS").split("\n").filter(Boolean);

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    // The name states the action, because a name is the first thing the model
    // reads. The CLI verb behind it stays the bare noun `options`, matching
    // generate/compile/check/lsp; the two need not agree.
    name: "query_options",
    label: "Options",
    description:
      "Look up option paths and their types in the pinned schema of ONE world. " +
      "WORLD is the world you are asking about. QUERY is a dotted prefix (browse a namespace) or any substring of " +
      "a path (find the namespace from a domain word, e.g. 'backup'). A narrow " +
      "query answers with exact 'path : type' lines; a broad one answers with the " +
      "namespaces holding the matches, the one with the most matches first, which " +
      "you then ask about by name. Every option your rules name must appear here, " +
      "or the mint is rejected.",
    parameters: Type.Object({
      world: Type.String({
        description: "Which world's schema to search. One of: " + worlds.join(", "),
      }),
      query: Type.String({
        description: "A dotted option prefix, or any substring of a path.",
      }),
    }),
    async execute(_toolCallId: string, params: { world: string; query: string }) {
      // Deduce-or-fail: a name outside this mint's worlds is a question lips
      // cannot answer, and answering it from another world's schema is the
      // confidently-wrong lookup this tool exists to prevent.
      if (!worlds.includes(params.world)) {
        return {
          content: [{
            type: "text",
            text: `${params.world} is not a world this mint writes for. ` +
              `Ask about one of: ${worlds.join(", ")}`,
          }],
          details: {},
          isError: true,
        };
      }
      const r = spawnSync(bin, ["options", "--target", params.world, params.query], {
        encoding: "utf8",
      });
      // On success the answer alone goes back. lips writes progress to stderr
      // ("building the schema from pinned flake..."), and appending that to a
      // list of options corrupts it: asked to count the lines of a 26-option
      // answer carrying two progress lines, a model answered 27. On failure the
      // opposite holds -- stderr is where the deduce-or-fail remedy lives, and
      // the model needs it to ask a better question.
      const failed = r.status !== 0;
      const text = (failed ? [r.stdout, r.stderr] : [r.stdout])
        .filter(Boolean)
        .join("\n");
      return {
        content: [{ type: "text", text: text || "no output" }],
        details: {},
        isError: failed,
      };
    },
  });

  pi.registerTool({
    name: "check_draft",
    label: "Check draft",
    description:
      "Check a DRAFT engine before you answer with it. Pass the complete set of " +
      "lines you intend to answer with; lips runs its own gates over them and " +
      "reports the first one that rejects the draft, in the same words the " +
      "refusal would use. It does not run the claim gate or the artifact build, " +
      "and it says so. A clean answer does not guarantee acceptance; a dirty one " +
      "guarantees refusal, so fix what it names and check again. Never narrate " +
      "what this tool told you in your answer: the answer is engine lines only, " +
      "and a sentence about the check is a line lips refuses.",
    parameters: Type.Object({
      draft: Type.String({
        description: "The complete draft engine, in the answer format.",
      }),
    }),
    async execute(_toolCallId: string, params: { draft: string }) {
      // One program at a time: check takes exactly one, and the engine-level
      // gates are program-independent, so the first failure is the answer.
      for (const program of programs) {
        const r = spawnSync(bin, ["check", "--draft", program], {
          input: params.draft,
          encoding: "utf8",
        });
        if (r.status !== 0) {
          return {
            content: [
              {
                type: "text",
                text:
                  [r.stdout, r.stderr].filter(Boolean).join("\n") || "no output",
              },
            ],
            details: {},
            isError: true,
          };
        }
      }
      return {
        content: [
          {
            type: "text",
            // The reminder rides on the machine's own last words, where the
            // temptation is created: told it is clean, a model wants to say so,
            // and one narrating sentence in the reply fails the whole mint
            // (observed, sonnet-5, the first live run of this tool).
            text:
              "the draft passes every gate lips can run before you answer. " +
              "Answer with those lines ALONE -- no sentence about this check, " +
              "which lips would read as a malformed item and refuse.",
          },
        ],
        details: {},
        isError: false,
      };
    },
  });
}

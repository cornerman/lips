// The ONLY actions a lips mint may take. pi runs the mint with its built-in
// tools and every ambient extension, skill and context file disabled, so this
// file is the mint's complete world: look up an option in the pinned schema of
// the target world, and submit a draft engine as the answer. Both shell out to
// the lips binary, so what the model is told is exactly what lips itself would
// say -- there is no second, model-facing renderer that could drift from the
// human-facing one.
//
// Three tools, and none of them decides. query_options and query_language
// inform about NAMES -- the option paths of a world, and the clauses another
// language already defines; submit_draft REPORTS which gate rejects a draft,
// and stages a clean one as the answer. The gate that decides still runs once, in Haskell, after the
// model is done, over the staged bytes. What moved is when the mint can learn
// it is wrong, not who judges it.
//
// Staging is what makes the checked draft and the answer the same bytes: twice
// (2026-08-09) a mint checked draft A and answered with a different draft B,
// which lips then refused for a defect the tool had already named, wasting the
// whole one-shot call. There is no free-text answer channel any more.
//
// pi loads this with `-e` for a single run, so the tool exists inside lips'
// mint and nowhere else: a user's own pi sessions never gain it.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname } from "node:path";

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
// Where a clean draft becomes the answer generate reads. Supplied per call, so
// one mint can never stage into another's directory.
const answerPath = required("LIPS_MINT_ANSWER");

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
    // A language a program NAMES is a question, and this is where it is asked.
    // Its answer is the same list the kernel grounds the draft against, from the
    // same binary, so a call that passes this tool cannot fail the composition
    // gate for a name that was never there -- the silent misread of 2026-08-12
    // (a line saying "as defined by match" was read as a local field, and every
    // gate stayed green) has no room left.
    name: "query_language",
    label: "Language",
    description:
      "List the clauses another language defines, which your rules may CALL " +
      "instead of defining again. LANGUAGE is the language a line of the program " +
      "names, as a program names it (the .lips extension: 'player' for " +
      "player.lips or squad.player.lips). WORLD is the world you are writing " +
      "rules for, because a language is lowered per world. The answer is one " +
      "'name arity' line per clause, arity '-' where it takes no parameter list. " +
      "Call those names as they are printed; never define one of them yourself, " +
      "and never call a name this tool did not print.",
    parameters: Type.Object({
      world: Type.String({
        description: "Which world's rules to read. One of: " + worlds.join(", "),
      }),
      language: Type.String({
        description: "The language to ask about, without the .lips extension.",
      }),
    }),
    async execute(_toolCallId: string, params: { world: string; language: string }) {
      // The same refusal query_options makes, for the same reason: a language
      // lowered for another world exports other names, and answering from it
      // would ground the draft against a vocabulary this mint never links.
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
      // Beside the importer, exactly where `lips check` resolves an import from:
      // a language folder is found relative to the program that names it, so the
      // tool must ask from that directory and not from wherever pi was started.
      const r = spawnSync(bin, ["exports", "--target", params.world, params.language], {
        cwd: dirname(programs[0]) || ".",
        encoding: "utf8",
      });
      // Same split as query_options, for the same reason: a clean answer alone
      // (progress text corrupts a list a model counts), a failure with the
      // stderr that carries the remedy. An unminted language is an ERROR here,
      // never an empty list -- "exports nothing" would read as permission to
      // define the names locally, which is the failure this tool removes.
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
    name: "submit_draft",
    label: "Submit draft",
    description:
      "Submit your engine. This is the ONLY way an engine reaches lips: pass the " +
      "complete set of lines, and lips runs its own gates over them and reports " +
      "the first one that rejects them, in the same words the refusal would use. " +
      "A refused submission stages nothing, so fix what it names and submit " +
      "again. A clean submission is staged as your answer; it does not guarantee " +
      "acceptance, because the claim gate and the artifact build still run after " +
      "you are done. The last clean submission is the engine lips takes, and " +
      "nothing you write outside this tool is read as engine lines.",
    parameters: Type.Object({
      draft: Type.String({
        description: "The complete engine, in the answer format.",
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
      // Overwrite on purpose: a later clean submission supersedes an earlier
      // one, so the model may keep improving, and a submission that FAILS the
      // loop above leaves the last clean one standing.
      writeFileSync(answerPath, params.draft);
      return {
        content: [
          {
            type: "text",
            text:
              "the draft passes every gate lips can run before you are done, and " +
              "is staged as your answer. The claim gate and the artifact build " +
              "still run after, so this is not acceptance. Submit again to " +
              "replace it; whatever you write outside this tool is read by " +
              "nothing.",
          },
        ],
        details: {},
        isError: false,
      };
    },
  });
}

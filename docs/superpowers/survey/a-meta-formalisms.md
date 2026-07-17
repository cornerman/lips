# Meta-Formalisms: Specs of Language Specs

This survey covers systems whose entire purpose is to let someone write a definition of a
language and get, from that one definition, an implementation and its supporting tools.
That is exactly the shape lipsidea proposes: one uniform meta-structure from which the
checker, completion, error messages, formatter, and docs for every layered vocabulary are
derived, not hand-built per vocabulary. For each system below the survey asks five
questions: what its meta-structure actually is (grammar formalism plus semantics
formalism), whether that meta-structure is executable and deterministic enough that an
interpreter or compiler can be *derived* from it rather than separately implemented,
how far generated tooling (editor services, debuggers, REPLs) actually got in practice
and where it stalled, who uses the system today and why it stayed niche, and finally
what lipsidea should steal or reject from it. The last question ends every section with
a clearly marked recommendation; the formalism for lipsidea's own kernel is not yet
decided, and this survey is direct input to that decision, not a retrofit of a decision
already made.

Sources are linked inline. Adoption claims that rest on blog posts, retrospectives, or a
project's own README rather than a peer-reviewed paper are marked as such.

## Quick-Reference Table

| System | Syntax formalism | Semantics formalism | Interpreter/compiler derived? | IDE tooling derived? | Primary users today |
|---|---|---|---|---|---|
| K Framework | BNF with K annotations | Rewriting logic, refounded on Matching Logic | Yes: LLVM interpreter, Haskell-backend prover, both from one definition | No: hand-maintained syntax files only, no generated LSP | Runtime Verification Inc. (formal methods, smart-contract audit) |
| Racket `#lang` | Reader (arbitrary code) | Expander to core forms (arbitrary code) | Yes: a `#lang` is just a compiler pass, always executable | Partial: DrRacket tooling transfers only as far as macros expand to shared core forms | Racket/Scheme PL research and CS education; Typed Racket, Scribble in production use |
| JetBrains MPS | Structure aspect (metamodel, no grammar) | Constraints + type-system + generator aspects | Yes for lowering (generator); no built-in operational semantics | Yes, most completely of any system surveyed: editor, completion, live checks, all derived | mbeddr, YouTrack (2009), Realaxy (2010), PEoPL; narrow but real commercial base |
| Spoofax (SDF3/Statix/Stratego) | SDF3 (scannerless GLR) | Statix (scope-graph constraints) + Stratego (rewriting) | Yes: parser, type checker, transformation all derived from declarative specs | Yes via ESV: hovers, squiggles, outline all declaratively bound | TU Delft-adjacent language-engineering research |
| Rascal | Built-in concrete syntax | One general-purpose analysis/transform language | Yes, as ordinary JVM-hosted programs | Yes: generic LSP/VSCode support built once, not per language | CWI software-analysis research |
| PLT Redex | Racket-embedded BNF | Reduction rules, executable as Racket | Yes, directly (it is a Racket program) | No: tooling targets the semanticist's own workflow, not end-user IDEs for the modeled language | PL-theory research and pedagogy (Northeastern/PLT) |
| Ott | Standalone ASCII notation | Inference-rule judgments, exported to proof assistants | Indirect: correctness depends on faithfulness of the Coq/HOL/Isabelle/Lem export | No | PL-theory research (Cambridge/Inria lineage); "remains in continuous use" as of 2024 per its own README |

## K Framework

**Meta-structure.** A K definition has three parts: BNF syntax productions annotated with
K attributes (strictness, associativity, evaluation-order hints); configuration
declarations that organize program state into nested, labeled "cells"; and rewrite rules
over a computation structure, a nested list that sequences pending program fragments much
like an abstract machine's control stack. Early K rested on rewriting logic and a Maude
backend ("K Framework Distilled," Lucanu, Șerbănuță, Roșu, WRLA 2012,
https://doi.org/10.1007/978-3-642-34005-5_3). K has since been refounded on Matching
Logic, a single program logic into which K's designers argue most established logics
(first-order logic, separation logic, reachability logic) embed, giving K one unifying
foundation rather than a federation of separately-justified formalisms ("Matching
μ-Logic," Chen and Roșu, LICS 2019, https://doi.org/10.1109/lics.2019.8785675; "Matching
Logic," LMCS 2017, https://doi.org/10.23638/lmcs-13(4:28)2017; "Matching Logic
Explained," JLAMP 2021, https://doi.org/10.1016/j.jlamp.2021.100638).

**Executable and deterministic.** Yes, and this is K's strongest, best-evidenced claim.
`kompile` turns one definition into multiple derived artifacts: an LLVM-backend concrete
interpreter fast enough for real execution, and a Haskell-backend symbolic engine that
doubles as a reachability-logic prover. Both come from the same source definition, with
no separate hand-written interpreter and no separate hand-written verifier. The claim is
validated by real, large semantics built this way: KEVM, a complete formal semantics of
the Ethereum Virtual Machine used for smart-contract verification (Hildenbrandt et al.,
CSF 2018, https://doi.org/10.1109/csf.2018.00022); a complete C11 semantics that backs
RV-Match, a tool for catching undefined behavior in C programs (Daian et al., "Runtime
Verification at Work: A Tutorial," RV 2016,
https://fsl.cs.illinois.edu/publications/daian-guth-hathhorn-li-pek-saxena-serbanuta-rosu-2016-rv.html);
and formal semantics for Java and x86-64. The K tutorial's own lesson list documents the
breadth of what a single definition drives: source-level debugging of the interpreted
program with GDB or LLDB (Lesson 1.19), a REPL for debugging proofs on the Haskell
backend (Lesson 2.17), and deductive verification (Lesson 1.22)
(https://kframework.org/).

**Generated tooling reality.** Parsing, documentation, and the runtime/proof backends are
genuinely derived, not hand-built. Editor tooling is not. K's own GitHub README states
plainly: "Users should feel comfortable using the command line, as we do not provide GUI
tools at this time" (https://github.com/runtimeverification/k). K's "Editor Support" page
lists syntax-highlighting definitions, contributed and maintained by hand, for Atom,
BBEdit, Emacs, IntelliJ, Notepad++, Vim, VSCode, and Pygments, the last of which the page
itself admits is "far from being complete"
(https://kframework.org/editor_support/). There is no generated language server, no
derived code completion, and no derived in-editor error checking for a *language defined
in K*, despite K deriving that language's runtime semantics with real rigor. This gap
between semantics-completeness and IDE-completeness, ten-plus years into K's existence,
is the single most important cautionary data point in this survey for lipsidea's
tooling ambition.

**Adoption reality.** K lives almost entirely inside formal methods and, specifically,
Runtime Verification Inc., the company founded by K's chief designer, Grigore Roșu,
which sells RV-Match (C), formal x86 semantics, and EVM/smart-contract verification
services built on K. No mainstream language implementer ships a general-purpose runtime
built with K; the tool's niche is "give me a checkable, executable spec of an existing
or new language and derive an interpreter and prover from it," a narrower ambition than
"build me a language people program in day to day." Build requirements are heavy (LLVM
15+, Boost, GMP, Maven, JDK 17+, per the project's own build instructions), and the
tutorial runs to dozens of lessons across five parts, evidence of real, not marketing,
learning-curve cost.

**Lipsidea verdict.** Steal the discipline of one definition driving multiple derived
artifacts with zero hand-written glue between them, and matching logic's choice of a
single base logic that types, reachability, and meta-theory all reduce to, rather than
bolting together separately-justified formalisms per concern; this is close kin to
lipsidea's "one uniform meta-structure." Reject the assumption that IDE tooling comes
free once semantics is nailed down: K disproves that by omission. Reject the toolchain's
operational weight (multiple backends in different host languages, a heavyweight native
build) as a model for a spec-language kernel that wants a small, auditable core.

## Racket `#lang`

**Meta-structure.** Racket imposes no separate meta-language distinct from the object
language. A "language" is a Racket module that supplies a reader, which turns raw text
into syntax objects, and an expander, a compile-time macro program that rewrites those
syntax objects down to Racket's core forms. `#lang foo` at the top of a file names the
Racket module that supplies this reader/expander pair
(https://docs.racket-lang.org/guide/languages.html). Because both halves are ordinary
Racket code, defining a new vocabulary means writing a program in the substrate, not
filling in a schema in a separate meta-language. Racket imposes no fixed semantics
formalism either: each `#lang` assigns whatever meaning it likes to its own forms, while
typically reusing Racket's existing semantics for whatever it doesn't redefine. Typed
Racket, a gradually-typed dialect, is itself layered on top using exactly this mechanism
("Languages as Libraries," Tobin-Hochstadt, St-Amour, Culpepper, Flatt, Felleisen, PLDI
2011, https://www2.ccs.neu.edu/racket/pubs/pldi11-thacff.pdf; summarized further in "A
Programmable Programming Language," Felleisen et al., Communications of the ACM 2018,
https://doi.org/10.1145/3127323).

**Executable and deterministic.** Yes, by construction. Expansion is macro-expansion, a
terminating, deterministic rewriting process over syntax objects, followed by ordinary
Racket compilation to bytecode and then JIT, or, since Racket CS (version 8.0), to native
code via the Chez Scheme runtime. There is no separate "compile the spec" phase distinct
from "compile the program": the same pipeline that compiles plain Racket compiles every
`#lang`-defined program, because every `#lang` bottoms out in Racket.

**Generated tooling reality.** DrRacket, Racket's self-hosted IDE, derives a real amount
of tooling automatically, but only as far as a `#lang` reuses shared core forms: any
language that expands into Racket's own module system, contracts, and base forms
inherits DrRacket's background syntax checker, debugger, and algebraic stepper without
extra work, because those tools operate on the expanded core, not on each language's
surface syntax (https://en.wikipedia.org/wiki/Racket_(programming_language)). Beyond
that shared floor, nothing is automatic: custom error messages, custom highlighting, and
custom completion for a genuinely new `#lang` are hand-written per language. There is no
single declarative language description that a generator reads to produce a language
server, the way MPS or Langium promise; DrRacket's generality comes from shared
infrastructure at the core-forms level, not from analyzing a grammar-plus-semantics
description.

**Adoption reality.** This is the most successful language-oriented-programming
ecosystem in production terms surveyed here. Typed Racket, Scribble (Racket's own
documentation language), Slideshow, Datalog, Racklog, FrTime, Lazy Racket, Hackett, and
the pedagogical language Pyret (originally hosted as a `#lang`) are real, maintained
dialects (https://en.wikipedia.org/wiki/Racket_(programming_language)). Adoption
concentrates in the Racket/Scheme research community and computer-science education
(the ProgramByDesign and Bootstrap outreach programs); outside that community, authoring
a new `#lang` remains a specialist activity, because writing a correct, hygiene-respecting
reader/expander pair, while "just code," demands real macro expertise.

**Lipsidea verdict.** Steal the core idea directly: a spec-language and its own
meta-language need not be two different formalisms. If the substrate is expressive
enough (a real module system plus a principled, hygienic expansion layer), defining a new
vocabulary is writing ordinary code in that substrate, and tooling that understands the
substrate transfers automatically to everything that bottoms out in it. This is the
closest existing precedent to lipsidea's "one substrate, many layered vocabularies,
tooling derived rather than hand-built" ambition. Reject the assumption that this
transfer reaches everywhere: DrRacket's free tooling stops exactly where a `#lang`
introduces genuinely new structure with no shared core-form equivalent, and lipsidea
must decide that boundary explicitly rather than assume Racket's answer generalizes.

## JetBrains MPS

**Meta-structure.** MPS defines a language through several co-located aspects, each
itself expressed in an MPS language: structure (a metamodel of concepts, properties,
children, and references, comparable to Ecore/EMF, with no textual grammar at all, since
MPS stores programs directly as ASTs); editor (projectional rules describing how each
concept's cells render and how a user edits them, meaning MPS can present tables and
diagrams, not only text-like views); constraints (well-formedness rules); type-system
(typing rules, checked incrementally); and generator (deterministic model-to-model or
model-to-text lowering rules). All of these aspect-languages are themselves defined
using the same mechanism, so MPS is self-describing: the language used to define
"structure" or "editor" is itself an MPS language, bootstrapped
(https://en.wikipedia.org/wiki/JetBrains_MPS; https://www.jetbrains.com/mps/).

**Executable and deterministic.** Yes for the lowering direction. Because there is no
parsing step in the normal case (the AST is the actual stored artifact; the editor only
projects a view of it), "compiling" a program is running the generator aspect's
deterministic rules over that AST down to a target language, for instance the mbeddr
project generating C from higher-level embedded-systems concepts (Voelter et al.,
"mbeddr: instantiating a language workbench in the embedded software domain," Automated
Software Engineering 2013, https://doi.org/10.1007/s10515-013-0120-4). The type-system
aspect is a constraint-propagation formalism adequate for static checks; MPS does not
itself provide an operational-semantics formalism for the target language's runtime
behavior in the sense K does. MPS derives type checkers and code generators, not
interpreters.

**Generated tooling reality.** This is MPS's strongest result among every system
surveyed. Because structure, editor, constraints, and type-system are all declarative
aspects read by one shared IDE engine, MPS derives, automatically, a projectional editor
with syntax coloring, code completion, live constraint and type-error highlighting,
find-usages, and refactoring, described plainly on its own Wikipedia entry as providing
"many IDE services automatically: editor, code completion, find usages, etc."
(https://en.wikipedia.org/wiki/JetBrains_MPS). This is dev tooling genuinely derived
from a uniform meta-structure, the closest kinship in this survey to lipsidea's
ambition. The cost is real: projectional editing means source is not text, so plain-git
diffing, grepping, and copy-paste from outside sources interoperate poorly, a friction
widely cited as MPS's main practical drawback in the broader language-workbench
literature (Martin Fowler, "Language Workbenches: The Killer-App for Domain Specific
Languages?", 2005, https://martinfowler.com/articles/languageWorkbench.html). Composing
independently-developed languages inside one file works better than in grammar-based
systems, since there is no shared grammar to keep unambiguous, but MPS's own
documentation and the mbeddr case study still describe language composition as a skill,
not a solved problem.

**Adoption reality.** Real but narrow commercial use. JetBrains's own YouTrack bug
tracker, released in October 2009, was the first commercial product built with MPS;
mbeddr targets embedded and formal-methods DSLs; Realaxy shipped a commercial
ActionScript IDE on MPS in April 2010; PEoPL applies MPS to software product-line
engineering (https://en.wikipedia.org/wiki/JetBrains_MPS). Despite JetBrains's own IDE
distribution channel, the same company behind IntelliJ, MPS never became a mainstream
tool. The two causes most consistently cited across the language-workbench literature
are the projectional-editing tax described above and the standalone-IDE requirement:
adopting an MPS language means adopting MPS itself as the editor, not adding a plugin to
whatever editor a team already uses.

**Lipsidea verdict.** Steal the single strongest empirical result in this survey: a
uniform meta-structure genuinely can drive editor, completion, live-checking, and doc
tooling automatically when the aspects are declarative and machine-readable; MPS proves
this by fifteen-plus years of production existence, not by aspiration. Steal the
bootstrapping discipline of defining the aspect languages themselves inside the same
system. Reject projectional editing as a default: lipsidea's context, AI-authored specs
that need human legibility, plain-text diffs in git, and NixOS-module compile targets,
weighs toward text as the source of truth, and MPS demonstrates that tooling-generability
and text-friendliness pull in different directions. Reject MPS's own-IDE adoption model
in favor of a generated tool shaped like a language server that plugs into editors people
already use.

## Spoofax and Rascal (the ASF+SDF/Stratego Lineage)

Spoofax and Rascal are related but distinct descendants of the same academic lineage:
ASF+SDF (Algebraic Specification Formalism plus Syntax Definition Formalism) and its
Meta-Environment, built at CWI in the 1990s, pioneered modular, composable grammars (SDF)
and declarative, rewrite-based specification of transformations (ASF). Stratego grew out
of that lineage as a more flexible transformation language built on strategic term
rewriting (generic traversal combinators controlling where and how rules apply), later
merging with the SDF ecosystem as Stratego/XT and then Spoofax, developed at TU Delft.
Rascal, developed separately at CWI, folds parsing, analysis, and transformation into one
general-purpose language instead of federating specialized sublanguages. Neither
ASF+SDF's Meta-Environment nor the old Stratego/XT project site has a dedicated
Wikipedia page today, and strategoxt.org itself now redirects to a bibliography site
(https://strategoxt.org, retrieved via researchr.org), a small but concrete sign of how
much churn this lineage has been through; the project-history angle behind that churn
belongs to the sibling survey b-graveyard.md, and this section covers only the
formalism.

**Meta-structure, Spoofax.** SDF3 defines syntax as a context-free and lexical grammar
parsed with scannerless GLR, avoiding a separate lexer-grammar ambiguity problem. Statix
defines static semantics as logical constraints over scope graphs, a graph-based
formalization of name binding and scoping (building on NaBL2, van Antwerpen, Néron,
Tolmach, Visser, Wachsmuth, PEPM 2016; formalized as Statix in Rouvoet, van Antwerpen,
Bach Poulsen, Krebbers, Visser, "Knowing When to Ask: Sound Scheduling of Name
Resolution in Type Checkers Derived from Declarative Specifications," OOPSLA 2020,
https://doi.org/10.1145/3428248). Stratego defines transformation and compilation as
rewrite rules organized under explicit strategies. ESV (Editor SerVices) declaratively
binds all of the above to IDE behavior: what analyses run on save, what a hover shows,
how the outline view is structured. SPT provides a declarative test-suite format for
parsers, analyses, and transformations (https://spoofax.dev/).

**Meta-structure, Rascal.** One language covers all of parsing (grammars defined
inline), pattern matching over concrete and abstract syntax fragments, generic
type-safe tree traversal, and analysis and transformation, positioned by its own
homepage as "the one-stop shop for metaprogramming" built on the idea that "source code
= data" (https://www.rascal-mpl.org/). Where Spoofax composes SDF3, Statix, Stratego,
and ESV as separate sublanguages, Rascal trades that per-concern separation for a single
scripting language competent at all of these tasks at once.

**Executable and deterministic.** Yes for both, by different mechanisms. Statix
constraints, once solved, deterministically decide whether a program's names and types
resolve; the OOPSLA 2020 paper's central contribution is a formal characterization of
exactly when constraint-solving order cannot affect the answer, "stability" of name and
type queries, precisely the kind of determinism guarantee a derived static checker needs
to be trustworthy. Stratego rewriting is deterministic given a fixed strategy, since a
strategy pins down control explicitly rather than leaving rule application as implicit
search. Rascal programs are ordinary deterministic programs in a typed, JVM-hosted
language.

**Generated tooling reality.** This is the most complete generated-IDE story among the
grammar-based (non-projectional) systems surveyed. From an SDF3 grammar alone, Spoofax
derives a parser, syntax highlighting, and an outline view; Statix constraints derive
error and warning squiggles; ESV wires both into most of what an LSP-based IDE plugin
needs. The Statix paper's own framing is explicit about the ambition: to close "the
large gap between the specification of type systems and the implementation of their
type checkers" so the derived checker needs no separate hand-written implementation
(https://doi.org/10.1145/3428248). Rascal ships its own generic VSCode extension and
Language Server Protocol support, built once for any Rascal-defined language rather than
per language (https://www.rascal-mpl.org/). Shortfalls are documented in Spoofax's own
how-to guides: Statix is young enough that Spoofax's docs carry live migration guides,
"Migrate from NaBL2" and "Migrating to the Concurrent Solver"
(https://spoofax.dev/), meaning static-semantics tooling has required real migration
effort even for existing Spoofax languages; and Stratego-program debugging exists as a
separate, less mature facility than the parsing and analysis tooling.

**Adoption reality.** Both remain active, research-oriented tools rather than mainstream
production ones: Spoofax's most recent stable release is 2.5.23 (28 April 2025,
https://spoofax.dev/), and Rascal's blog and release notes are current
(https://www.rascal-mpl.org/). Neither has an MPS-style commercial success story; usage
concentrates in language-engineering research (Spoofax, TU Delft lineage) and
software-analysis research (Rascal, CWI). The lineage's specific technical
contributions, scannerless GLR parsing, modular composable grammars, and scope graphs
for name binding, have arguably had more influence through citation and piecemeal reuse
than through Spoofax or Rascal themselves becoming widely adopted end-user tools.

**Lipsidea verdict.** Steal scope graphs and Statix's framing of "derive the type
checker" as a scheduling problem over declarative constraints with a proven determinism
guarantee, directly relevant if lipsidea's kernel needs a derived static checker whose
behavior can be formally guaranteed rather than informally trusted. Steal the ESV
pattern of one declarative layer mapping checker and analysis output to editor behavior,
cleanly separated from the semantics itself, a good shape for lipsidea's own
checker/completion/errors pipeline. Steal Rascal's proof point that generic LSP support
can be a built-once facility of the meta-language rather than a per-vocabulary artifact.
Reject Spoofax's multi-sublanguage complexity, four or more distinct languages glued
together, as a starting shape; lipsidea's "one uniform meta-structure" goal argues for
something closer to Rascal's single-language unification or K's single-notation
approach.

## PLT Redex and Ott: Semantics as Spec, Not as Compiler

Redex and Ott share a narrower and more modest goal than every system above: neither
tries to derive a production interpreter, checker, or IDE for the language it
specifies. Both target the working semanticist writing and validating a model, whether
of an existing language or a new calculus, treating "is my spec correct" as the whole
problem rather than "can users get a toolchain from my spec."

**Meta-structure.** Redex is a domain-specific language embedded in Racket for
specifying operational semantics: a BNF grammar plus reduction rules, executable
directly because Redex is implemented as an ordinary Racket macro layer, so a Redex
model is a Racket program with no separate host logic
(https://redex.racket-lang.org/). Ott is a standalone tool with its own concise ASCII
notation, deliberately close to informal mathematical notation, for syntax plus
inference-rule-style judgments and semantics; Ott's primary output is high-quality
typeset LaTeX, and from the same source it also generates formalizations for Coq, HOL,
Isabelle/HOL, Lem, and OCaml, plus an experimental Menhir parser
(https://github.com/ott-lang/ott). Ott additionally auto-generates the substitution and
free-variable functions that binding requires, sparing the well-known manual tedium of
getting alpha-renaming-safe substitution right by hand, a hard problem lipsidea's own
semantics layer will also face.

**Executable and deterministic.** Redex is directly executable, since it is a Racket
program, and it supports randomized test generation to try to falsify claimed properties
of a semantics (https://redex.racket-lang.org/). Its flagship validation is empirical:
"Run Your Research: On the Effectiveness of Lightweight Mechanization" (Klein, Clements,
Dimoulas, Eastlund, Felleisen, Flatt, McCarthy, Rafkind, Tobin-Hochstadt, Findler, POPL
2012, https://doi.org/10.1145/2103656.2103691) mechanized nine ICFP 2009 papers in Redex
and found mistakes in all nine, concrete evidence that an executable, testable
specification catches real errors paper-and-pencil review misses. Ott's determinism
guarantee is one level removed: a definition's meaning is only as reliable as the
faithfulness of its translation into Coq, HOL, Isabelle, or Lem, where those systems'
own execution or proof engines take over
("Ott: Effective Tool Support for the Working Semanticist," Sewell, Zappa Nardelli,
Owens, Peskine, Ridge, Sarkar, Strniša, ICFP 2007,
https://doi.org/10.1145/1291151.1291155, and Journal of Functional Programming 2010,
https://doi.org/10.1017/s0956796809990293).

**Generated tooling reality.** Redex's tooling serves the semantics engineer: reduction
stepping and visualization, random test-case generation, and, through its Racket
embedding, ordinary DrRacket editor support for the metalanguage, not for a language
built with it. Ott generates typeset documentation directly from a spec, a legitimate
"docs derived from spec" data point relevant to lipsidea, plus skeleton formalizations
for five proof-assistant targets, but neither tool derives end-user editor tooling
(completion, hovers, checkers) for the language being specified.

**Adoption reality.** Both are standard tools of a small, specific community: PL-theory
researchers writing and mechanizing operational semantics, concentrated around
Northeastern/PLT for Redex (tied to the textbook "Semantics Engineering with PLT
Redex," Felleisen, Findler, Flatt, MIT Press) and Cambridge/Inria for Ott. Both remain
actively used in exactly that niche; Ott's own GitHub page states "As of 2024, Ott
remains in continuous use" (https://github.com/ott-lang/ott). Neither aims at, nor has
reached, adoption outside PL-theory research and pedagogy.

**Lipsidea verdict.** Steal Ott's template of one syntax-and-semantics description
producing several distinct derived outputs, typeset docs, and multiple proof-assistant
encodings, as the smallest, most focused precedent in this survey for lipsidea's own
"checker, completion, errors, formatter, docs, all derived" ambition. Steal Redex's
random-testing-against-a-model discipline as a cheap, concrete validation technique
lipsidea's kernel formalism should support from the start. Reject scope: neither tool
tries to derive end-user editor tooling for the specified language, so neither is a
template for lipsidea's IDE-tooling half; they answer whether a spec is correct, not
whether users of that spec get an IDE.

## Also Noted

These systems informed the survey but did not warrant full sections, either because
they lack a semantics formalism (tree-sitter, BNFC), stayed a research prototype
(Melange), or belong primarily to a sibling survey's angle (ASF+SDF history, OMeta).

| System | What it is | Relevance to lipsidea | Source |
|---|---|---|---|
| Melange | A meta-language for composing DSLs from reusable "chunks" of syntax, semantics, and editor bindings, aimed at the problem that each new DSL reinvents most of a previous one | Conceptually close to lipsidea's "vocabularies layered over one substrate"; stayed a research prototype with no evidence of wide adoption | Degueule, Combemale, Blouin, Barais, Jézéquel, "Melange: a meta-language for modular and reusable development of DSLs," SLE 2015, https://doi.org/10.1145/2814251.2814252 |
| Langium | TypeScript-hosted, grammar-first workbench, explicit successor to Eclipse Xtext, generates a typed AST plus a full Language Server Protocol server from one grammar | The inverse trade-off from K and Ott: no formal semantics story at all, hand-written validators and interpreters, but ships real generated LSP tooling as the central deliverable rather than an afterthought | https://langium.org/ |
| tree-sitter | Pure incremental-parsing library and grammar DSL; explicitly not a semantics system | No notion of static or dynamic semantics exists here at all; noted because so much mainstream editor tooling (GitHub, Neovim, Helix, Zed) leans on tree-sitter grammars for syntax highlighting, so a lipsidea tool wanting cheap syntax-level support in existing editors will likely need a tree-sitter grammar as a leaf artifact regardless of the semantics formalism chosen | https://tree-sitter.github.io/tree-sitter/ |
| BNFC | Labelled-BNF-to-many-backends compiler-frontend generator (Chalmers/Gothenburg): one grammar yields a lexer, parser, AST, pretty-printer, and LaTeX spec for Haskell, Agda, C, C++, Java, and OCaml | The most batteries-included, no-semantics baseline surveyed; shows how much grammar alone buys (types, parser, pretty-printer, typeset docs) and how little it says about meaning | https://bnfc.digitalgrammars.com/ |
| ASF+SDF Meta-Environment | CWI's 1990s-2000s modular grammar and rewrite-based transformation system, direct ancestor of Stratego/Spoofax and an influence on Rascal | Historical interest only today; no dedicated Wikipedia page exists even for its immediate successor Stratego/XT, and strategoxt.org itself now redirects to a bibliography site | https://strategoxt.org (redirects to researchr.org) |
| OMeta | A PEG-based formalism unifying lexer, parser, and tree transformation into one mechanism, used in Ian Piumarta's work adjacent to Alan Kay's STEPS project | Another "one formalism for grammar and transform" data point alongside Rascal's similar unification choice; the STEPS/OMeta project-history angle belongs to the sibling survey b-graveyard.md | (project-history sources in b-graveyard.md) |

## Cross-Cutting Observations

Three patterns recur across every system surveyed, and each bears directly on
lipsidea's design.

**Semantics-completeness and IDE-completeness are separate achievements, and most
systems solve only one.** K and Ott derive rigorous, checkable semantics and prove it
with real validation (K's production formal semantics for EVM, C11, and x86; Redex's
nine-out-of-nine bug find), but neither derives end-user editor tooling. Langium and
tree-sitter invert this: strong generated editor tooling, no semantics formalism at
all. Only MPS, and to a real but lesser extent Spoofax, derive both from one
meta-structure. Any claim that a rigorous semantics formalism automatically yields good
tooling, or vice versa, is unsupported by the evidence gathered here; lipsidea has to
architect for both explicitly.

**Determinism at the semantics layer is achievable and has been proven in practice, at
real scale.** K's LLVM and Haskell backends, Statix's proven scheduling-stability
guarantee, and Redex's direct executability all show that a rewriting- or
constraint-based semantics formalism can be made fully deterministic without giving up
expressiveness. This de-risks lipsidea's requirement that compile and run stay 100%
deterministic with no model in the loop; the prior art for how to get there already
exists.

**Text-as-source-of-truth and generated-tooling-completeness are in tension, and every
system picks a side.** MPS gets the most complete derived tooling by abandoning text as
the stored representation, at a real and repeatedly documented cost to plain-git
diffing and copy-paste ergonomics. Every text-based system surveyed (K, Racket, Spoofax,
Rascal, Redex, Ott) accepts a tooling ceiling in exchange for keeping specs as ordinary,
diffable, greppable text. Given lipsidea's stated need for AI-authored, human-legible,
git-diffable specs, this survey's evidence points toward the text-based side of that
tension, accepting MPS's tooling ceiling as the price, rather than toward projectional
editing.

## Recommendation

This is the surveyor's own ranked judgment, not a settled decision.

1. **Closest structural precedent: Racket's `#lang`.** Treating the meta-language and
   the object language as the same substrate, so that defining a vocabulary is writing
   code in the substrate rather than filling out a separate schema, is the mechanism
   most directly analogous to lipsidea's "one substrate, many layered vocabularies."
   Lipsidea should study `#lang`'s reader/expander split as a starting shape for how a
   vocabulary declares itself over the kernel.

2. **Closest semantics-rigor precedent: K Framework's matching logic plus multi-backend
   derivation.** The discipline of picking one base logic that everything else reduces
   to, and deriving an interpreter and a symbolic/proof engine from the same
   definition, is the best-evidenced precedent for lipsidea's "derived, not hand-built"
   claim at the semantics layer. Lipsidea should not copy K's toolchain weight, but
   should copy its one-definition-many-backends discipline.

3. **Closest tooling-completeness precedent: JetBrains MPS.** MPS is the only system
   surveyed with fifteen-plus years of production evidence that editor, completion,
   live-checking, and doc tooling can all be genuinely derived from a uniform
   meta-structure. Lipsidea should study MPS's aspect separation (structure,
   constraints, type-system, editor bindings, generator) as a checklist of what a
   uniform meta-structure needs to specify to make tooling derivable, while rejecting
   projectional editing itself.

4. **Closest derived-static-checker precedent: Spoofax's Statix.** If lipsidea's kernel
   needs a statically checkable name/type layer with a provable determinism guarantee,
   Statix's scope-graph constraint formalism and its stability theorem are the most
   directly reusable piece of prior art in this survey, more so than inventing a
   binding/scoping story from scratch.

5. **Closest "docs and multi-target derivation" precedent: Ott.** For the specific
   claim that one spec should produce documentation and more than one derived
   artifact with no separate hand-written path between them, Ott, not K or MPS, is the
   smallest and most legible existing template, precisely because its ambitions are
   modest enough to have actually been fully realized.

Ranked by relevance to the kernel-formalism decision, in order: K Framework and Statix
for the semantics and static-checking core; `#lang` for how a vocabulary declares
itself over the substrate; MPS for what a uniform meta-structure must expose to make
tooling derivable; Ott and Redex for validation technique and multi-target derivation
at small scale.

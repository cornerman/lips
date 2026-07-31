# The Graveyard: Prior Attempts at Intent-Level Programming

This document catalogs major prior attempts to let humans state intent while a machine produces
working software, and it records why each attempt failed, stalled, or survived only in a narrow
niche. It exists to keep lips from repeating a known failure under a new name. Sibling
documents cover adjacent ground: `a-meta-formalisms.md` covers language workbenches and
parsing formalisms (MPS, Spoofax, Redex, OMeta as a formalism), `c-guarantees.md` covers the
correctness-by-construction lineage (Dhall, Dafny, TLA+), and `d-aiwave-and-nix.md` covers the
current AI-codegen wave and the NixOS module system lips targets. This document stays with
systems that are dead, stalled, or permanently niche.

Method note: every factual claim below carries a source URL, fetched and read directly (Wikipedia
via its API, primary blogs, official docs, Hacker News via the Algolia search API) rather than
recalled from training data. Where a claim is my own synthesis rather than something a source
states outright, it is marked "inference."

Terminology used in the closing synthesis follows lips's own vocabulary: "kernel" is
the spec-language itself, "vocabulary" is a problem-specific language minted in the kernel,
"Solution" is an application spec written in a vocabulary, and "System" is the kernel plus its
vocabularies plus the compiler plus the Nix realization.

## Fourth-Generation Languages (PowerBuilder, FoxPro, Progress)

The 4GL wave promised that a non-procedural, English-adjacent language
could replace COBOL-era procedural code for business applications. [James
Martin coined the term in his 1981 book *Application Development Without
Programmers*](https://en.wikipedia.org/wiki/Fourth-generation_programming_language), explicitly
framing 4GLs as a way to open development to non-programmers.

The intent-level artifact was a form-and-report specification (PowerBuilder's DataWindow,
FoxPro's dBase-derived table-and-screen definitions, Progress's 4GL over its own database) bound
tightly to a single vendor's runtime and database engine. [PowerBuilder's DataWindow "frees the
programmer from considering the differences between Database Management Systems," but only within
Sybase's (later SAP's, later Appeon's) own stack](https://en.wikipedia.org/wiki/PowerBuilder). The
specification gap, the part no form-generator could express, was filled by an embedded scripting
language (PowerScript, FoxPro's own procedural dialect) that looked like an escape hatch but
was actually the load-bearing language for anything beyond CRUD.

The escape hatch was that scripting language itself, not a true exit to a general-purpose
stack. Once an application's logic grew past forms and reports, developers wrote most of the
real behavior in PowerScript or FoxPro code, and that code was not portable off the vendor's
runtime. There was no clean boundary between "generated" and "hand-written"; the two were
interleaved in the same files from day one.

4GLs did not fail outright. PowerBuilder and FoxPro-descended systems still run production workloads
in banks, insurers, and government agencies decades later, and [Progress Software still sells its
4GL-descended OpenEdge platform](https://en.wikipedia.org/wiki/Progress_Software). What failed
was the premise: that a wider, non-programmer population would author 4GL applications. [Progress
Software itself gave up on being a broad platform vendor in 2012, announcing a shift to become "a
much more narrowly focused specialist vendor"](https://en.wikipedia.org/wiki/Progress_Software)
and selling off most non-core product lines. The category survived by retreating from "everyone
can build software" to "developers build CRUD software faster," and by 2000 new development in
these languages had mostly stopped even as old installations lingered as unkillable legacy systems.

What lips should keep: the DataWindow's insight that one declarative artifact can cover
the overwhelming majority of a business application's UI and data-binding logic is correct
and worth preserving. The failure was coupling that declarative core to a single proprietary
runtime with no open compilation target, so escaping the vendor meant rewriting from scratch.

## CASE Tools and the Big CASE Wave

Computer-Aided Software Engineering tools promised to generate code directly from diagrams
capturing an analyst's model of a system. [The lineage runs from Daniel Teichroew's 1968 ISDOS
project and PSL/PSA at the University of Michigan through a market of over 100 vendors and nearly
200 products by 1990](https://en.wikipedia.org/wiki/Computer-aided_software_engineering). IBM tried
to consolidate the market around a shared repository standard, AD/Cycle, built on DB2 and OS/2.

The intent-level artifact was a data-flow diagram, entity-relationship diagram, or structure
chart stored in a shared repository ("active dictionary"). The specification gap was filled
by code generation templates tied to a specific target language and runtime, plus a promise
of "round-trip engineering" (regenerating the diagram from hand-edited code, and vice versa)
that never worked reliably in practice.

The escape hatch was hand-editing the generated code, which is precisely what broke round-trip
engineering: once a developer touched generated output directly, the model and the code diverged
permanently, and the tool could no longer regenerate without destroying the manual changes. Vendors
sold "protected regions" and merge tools to paper over this, but the fundamental problem, that
generated and hand-written code occupied the same file with no reliable boundary, was never solved.

CASE tools stalled for tightly linked reasons. Economically, tools were expensive and tied
training investment to a single vendor's notation. Architecturally, [AD/Cycle depended on the
mainframe and DB2, and "with the decline of the mainframe, AD/Cycle and the Big CASE tools
died off"](https://en.wikipedia.org/wiki/Computer-aided_software_engineering). Most of the
surviving vendors were absorbed by Computer Associates, and the market consolidated into UML
tooling by the mid-1990s. The deeper failure was that the round-trip promise was never kept:
once developers learned they could not trust the generator to preserve their edits, they stopped
trusting the model and used the diagramming tool only for documentation, if at all.

What lips should keep: the idea of a single shared, machine-readable model as the source of
truth is correct. What must differ is the direction of generation. lips's compile step must
be one-directional and total (Solution to NixOS module), with no expectation of round-tripping
hand edits back into the spec; if a capability is missing, it belongs in the vocabulary, not
patched into the output.

## UML, Model-Driven Architecture, and Executable UML

[UML unified the competing object-oriented notations of Booch, Rumbaugh, and Jacobson at OOPSLA
'95](https://en.wikipedia.org/wiki/Unified_Modeling_Language) and became an OMG and later
ISO/IEC standard. [The Object Management Group layered Model-Driven Architecture on top of UML
in 2001](https://en.wikipedia.org/wiki/Model-driven_architecture), defining Platform-Independent
Models (PIM) and Platform-Specific Models (PSM) with a formal transformation language (QVT)
between them. [Executable UML (xtUML), formalized in a 2002 book and descended from the
Shlaer-Mellor method of the late 1980s](https://en.wikipedia.org/wiki/Executable_UML), went
furthest: it added precise action semantics so a model could be compiled directly to running
code by "translation" rather than manual "elaboration."

The intent-level artifact was the PIM: class diagrams, statecharts, and an action
language, all independent of implementation technology. [Shlaer and Mellor's
original goal was analysis "so precise that it is possible to implement the
analysis model directly by translation," using a reusable "virtual machine" per target
platform](https://en.wikipedia.org/wiki/Shlaer%E2%80%93Mellor_method). The specification gap for
plain UML (not Executable UML) was filled entirely by a human: [UML diagrams have no standard
execution semantics, and "most developers do not use UML per se, but instead produce more informal
diagrams, often hand-drawn"](https://en.wikipedia.org/wiki/Unified_Modeling_Language). That
single sentence from UML's own reference page is the whole story of UML's actual fate: it became
a whiteboard sketching convention, not an executable specification.

The escape hatch for MDA was the PSM layer, hand-written or hand-tuned platform-specific code
sitting below the PIM. Because the PIM-to-PSM transformation was one directional and the PSM
was where all the messy platform detail lived, teams inevitably edited the PSM directly under
deadline pressure, and from that point on the PIM was decorative. Executable UML's xtUML variant
avoided this by compiling straight through a vendor virtual machine (Abstract Solutions, Mentor
Graphics, Pathfinder Solutions), which kept determinism but reintroduced vendor lock-in at the
virtual-machine layer.

Plain UML failed to become executable because it was designed as a notation standard, not a
semantics standard, and standardizing 14 diagram types by committee optimized for diagram-vendor
interoperability over runnable precision. MDA stalled because platform-independence was a moving
target (each new PSM technology needed new transformation rules) and because the promise of "write
once, generate for any platform" rarely survived contact with a platform's real quirks. Executable
UML achieved genuine determinism in narrow domains (embedded and safety-critical systems, where
Shlaer-Mellor tools still have users) but never crossed into mainstream application development,
in part because the tooling required a dedicated commercial virtual machine and in part because
most developers found the notation heavier than just writing code.

What lips should keep: Executable UML's core bet, that a model can have complete enough
semantics to compile deterministically rather than merely document, is exactly lips's bet
too. The lesson is to avoid MDA's layered PIM/PSM split with a hand-editable middle layer;
lips's Solution should compile directly to the NixOS module in one deterministic step,
with no intermediate artifact that invites hand-editing.

## Intentional Software (Charles Simonyi)

Charles Simonyi, who had built Microsoft's first WYSIWYG word processor
at Xerox PARC and later oversaw Word and Excel at Microsoft, founded
Intentional Software in 2002 to build on ideas he called "intentional
programming." [Simonyi rejoined Microsoft when it acquired Intentional Software in
2017](http://www.zdnet.com/article/microsoft-buys-intentional-software-simonyi-to-rejoin-microsoft/),
fifteen years after founding it, without the company ever having shipped a widely known
independent commercial product.

The intent-level artifact was a domain expert's own notation, editable through multiple
simultaneous "projections" of a single underlying semantic model. [Martin Fowler, who
tracked the company for years as a paying-attention outsider, described the Intentional
Domain Workbench as a language workbench supporting "projectional editing," where the same
state-machine model could be viewed and edited as XML, custom syntax, Ruby, or a diagram,
all reversibly](https://martinfowler.com/bliki/IntentionalSoftware.html). The specification
gap was filled by the projection mechanism itself: since every view was a live, bidirectional
projection of one model, there was in principle no separate "generated code" to fall out of sync,
a genuinely different answer to CASE's round-trip problem.

The escape hatch story is largely invisible from the outside, because Intentional Software
almost never showed its tool to the public. [Fowler's own account opens by noting years of "Real
Soon Now" and a version 1.0 release in 2009 that the company did not even announce on its own
website](https://martinfowler.com/bliki/IntentionalSoftware.html). Whatever glue story existed
was known only to the small number of enterprise customers (reportedly including an insurance
company payroll system) who used the workbench directly, and it never became public knowledge,
which is itself diagnostic: a specification technology that cannot be evaluated by the outside
world cannot build the ecosystem or trust it needs to spread.

Intentional Software did not fail so much as it never left the lab in public view. Economically,
it survived seventeen years on Simonyi's own capital and a handful of confidential enterprise
contracts rather than a product business, and it was eventually folded quietly back into
Microsoft's Office group rather than sold as a going concern with public traction. Culturally,
the project's secrecy (no public releases, no developer community, no documentation) meant
it could never accumulate the network effects that make a language workbench self-sustaining;
a projectional editor is only as valuable as the ecosystem of projections built for it, and an
ecosystem cannot form around a tool nobody outside a few clients can try.

What lips should keep: projectional editing's insight, that intent and its various renderings
can be kept in permanent sync by making the renderings views of one model rather than one-way
generation targets, is powerful and worth studying (sibling document `a-meta-formalisms.md` covers
this formalism in more depth). The organizational lesson is separate and just as important: an
intent-language system needs public, inspectable artifacts from early on, or it cannot recruit
the vocabulary authors and reviewers it needs to matter.

## VPRI STEPS (Alan Kay)

The Viewpoints Research Institute's "STEPS Toward the Reinvention of Programming" project,
funded by a National Science Foundation grant (No. 0639876) and led by Alan Kay's team, ran from
roughly 2007 to 2012 with the explicit goal of building a complete personal computing system,
from user interface down to the metal, in about 20,000 lines of code, a claimed 100 to 1,000
times reduction from the millions of lines such a system normally requires. [The 2012 final
report is on record at VPRI](https://www.vpri.org/pdf/tr2012001_steps.pdf).

The intent-level artifact was, at STEPS's most ambitious layer, a set of tiny domain-specific
languages (KScript and KSWorld for UI, Nile for graphics compilers, OMeta for parsers) each
written to be small enough that its own meaning was legible on inspection; sibling document
`a-meta-formalisms.md` covers OMeta and Nile as formalisms in depth. The specification gap in
a conventional system, the huge volume of code implementing accidental complexity rather than
the actual problem, was the thing STEPS was measuring and trying to eliminate by design.

STEPS is unusual in this survey because it never claimed to have an escape hatch
story, and that omission is the point. [The final report states plainly: "STEPS is
not aimed at producing a new practical alternative to existing PC operating systems and
applications... the STEPS project is a kind of 'science experiment' rather than an engineering
project"](https://www.vpri.org/pdf/tr2012001_steps.pdf). It further states the team's "primary
aim was not to improve existing designs either for the end-user or at the architectural level,"
only to measure how small a meaning-complete system could get. There was no glue problem to
solve because there was no commitment to production use in the first place.

STEPS did not fail on its own terms; it answered the question it asked (a runnable
personal-computing stack in the low tens of thousands of lines is achievable) and then the funding
ended in 2012 with no successor project or company built on the result (inference, based on the
absence of any later VPRI STEPS report or commercial spinoff in public records). The failure,
if it can be called that, is one of translation: a research result showing code-size reduction
is possible was never converted into a maintained, adoptable system, because the project was
structured from the start as a bounded science experiment rather than as the seed of a product
with users, a support model, and an evolution path.

What lips should keep: the discipline of treating code volume itself as a defect to be
measured and minimized, and the practice of building each layer as its own small, legible language
rather than one monolithic general-purpose stack, both anticipate lips's own "vocabulary
per problem domain over one general substrate" design. The lesson to avoid is STEPS's explicit
choice to stay a science project. lips needs a Solution to be usable by a real owner on a
real machine from an early milestone, not only publishable as a measurement of what is possible.

## Literate Programming (Donald Knuth)

[Knuth introduced literate programming in 1984 with WEB, a system for writing a
program as an explanation in natural language interspersed with code, from which
a "tangle" step produces compilable source and a "weave" step produces formatted
documentation](https://en.wikipedia.org/wiki/Literate_programming). The idea inverted the
usual relationship between code and comments: prose was primary, and code was embedded in it
in whatever order best explained the logic, not in the order a compiler demanded.

The intent-level artifact was the woven document itself, readable as an essay. The specification
gap was filled by nothing extra; Knuth's claim was that forcing the author to explain the design
in prose, at the point of writing it, surfaced bad decisions before they were built. The escape
hatch barely exists as a separate concept here, because literate programming never abstracted
away implementation detail; it only reordered and annotated it. There was nothing to "escape"
because nothing was hidden.

Literate programming as Knuth specified it (WEB, CWEB) never became a mainstream way to
write general software. It stayed mostly within Knuth's own projects (TeX, METAFONT) and a
small community of enthusiasts. It failed to spread for cultural and tooling reasons more
than technical ones: it demanded a different authoring discipline than the code-first habits
of most working programmers, its tools were per-language and clunky to integrate with editors
and debuggers of the day, and it offered no answer to how a team, not a single author, keeps
a woven narrative and a codebase consistent as both evolve under multiple hands.

What lips should keep: the core claim, that forcing precise explanation at authoring time
catches design errors before they are built, is directly relevant to lips's premise that AI
can write code faster than a human can review it, so the artifact a human reviews must be dense
intent rather than generated code. [Literate programming's real afterlife is the computational
notebook (Jupyter and similar), which Wikipedia's own account credits with an "important
resurgence... especially in data science"](https://en.wikipedia.org/wiki/Literate_programming),
suggesting the durable form of this idea is "prose and executable fragments interleaved for one
author's own reasoning," not "prose as the source of truth for a shipped system." lips's
Solution should be closer to the latter: a dense spec that is the artifact, not an essay with
code attached.

## HyperCard

[Apple shipped HyperCard free with every new Macintosh starting in
1987, built around "stacks" of "cards" with a built-in scripting language,
HyperTalk](https://en.wikipedia.org/wiki/HyperCard). Bill Atkinson, its creator, called it a
"software erector set." It let non-programmers build real, useful hypermedia applications
(databases, interactive presentations, games) years before the web existed.

The intent-level artifact was the stack itself: a live, directly manipulable arrangement
of cards, fields, buttons, and backgrounds, where "there is no difference between
moving a text field on the card and typing into it" from the runtime's point of
view. [Every object's state is saved immediately; there is no separate compile or save
step](https://en.wikipedia.org/wiki/HyperCard). The specification gap between what drag-and-drop
layout could express and what an application actually needed to do was filled by HyperTalk
scripts attached directly to the objects they controlled.

The escape hatch was HyperTalk itself, which is notable for not being a second-class add-on:
it was a full, if simple, programming language available on any object, so there was no cliff
between "no-code" and "real code." This is one of the few systems in this survey where the
escape hatch did not visibly kill the abstraction; users graduated from clicking to scripting
gradually, on the same objects, in the same tool.

HyperCard did not fail on technical or expressiveness grounds. It failed because its owner stopped
investing in it. [Apple gave HyperCard its final update in 1998 and withdrew it from sale in
March 2004, and it was never ported to Mac OS X](https://en.wikipedia.org/wiki/HyperCard). This
is a platform-death failure mode distinct from every other entry in this survey: a well-designed,
genuinely successful intent-level tool can still die because the company that owns its runtime
decides, for reasons unrelated to the tool's merit (in HyperCard's case, the web's rise and an
internal strategic pivot after Steve Jobs's return), to stop maintaining it.

What lips should keep: HyperCard's single most important property is that the "no-code"
surface and the "real code" layer were the same objects in the same tool, with no separate
export or rewrite step to go from one to the other. lips's vocabularies should aim for that
same continuity between a Solution's declarative surface and whatever escape hatch it offers,
rather than a hard wall between "spec" and "code."

## Inform 7

[Graham Nelson's Inform, first released in 1993 and rewritten as Inform 6 in 1996, became
the dominant tool for building parser-based interactive fiction, compiling to the Z-machine or
Glulx virtual machines](https://en.wikipedia.org/wiki/Inform). In 2006 Nelson released Inform 7,
briefly called "Natural Inform," a complete redesign using a natural-language-like syntax and a
"book publishing" metaphor for organizing source text into volumes, chapters, and sections.

The intent-level artifact is prose that reads like English but compiles deterministically:
sentences like "The kitchen is a room. The key is in the kitchen." define the world model
directly. The specification gap for genuinely underspecified behavior is filled by a large
standard library plus an explicit, testable system of "rules" that fire in a defined order,
not by any human in the loop at runtime.

The escape hatch is deliberately narrow and explicit: Inform 7 lets an author drop into literal
Inform 6 code for anything the natural-language layer cannot express, clearly demarcated
as embedded legacy code rather than silently interleaved (inference, based on Inform 6/7
interoperation as described in the language's own documentation and referenced in its Wikipedia
entry). Because interactive fiction's domain is narrow (rooms, objects, simple physical actions,
a limited number of verbs), the natural-language surface rarely needs the escape hatch at all.

Inform 7 has not failed; it has simply stayed inside the one domain where "natural-language-like
syntax" and "precise enough semantics to compile" turn out to coexist: static-world interactive
fiction, where the vocabulary of possible actions is small and mostly agreed upon in advance. It
never attempted, and was never asked, to generalize to arbitrary software, which is exactly why
its natural-language syntax never hit the wall that killed the 4GLs' "English for managers" promise.

What lips should keep: Inform 7 is proof that natural-language-adjacent syntax can be genuinely
deterministic and compileable when the vocabulary is narrow and well curated, which validates
lips's own bet that "vocabularies" should be freely minted per problem domain rather than one
universal natural-language grammar stretched to cover everything. The caution is scope discipline:
Inform 7's success is inseparable from its refusal to generalize past interactive fiction.

## Wolfram Language

[Wolfram Language has been the engine behind Mathematica since 1988, built around symbolic
computation, pattern-based rewriting, and functional programming, with the "Wolfram Language"
name only formally adopted in 2013](https://en.wikipedia.org/wiki/Wolfram_Language) when Wolfram
Research wanted a name for a free Raspberry Pi build.

The intent-level artifact is a symbolic expression, evaluated by repeatedly applying rewrite
rules until nothing more applies. This is a genuinely different, and genuinely powerful, model of
"intent": instead of specifying steps, an author specifies transformation rules and lets the engine
find a fixed point. The specification gap for anything outside built-in mathematical and symbolic
domains is filled by Wolfram's own enormous standard library, curated centrally by one company.

The escape hatch is limited by design: [the reference implementation
lives entirely inside Mathematica and Wolfram's cloud services, both closed
source](https://en.wikipedia.org/wiki/Wolfram_Language), and while Wolfram has released an
open-source parser (originally C++, rewritten in Rust in 2023) and there exist third-party
reimplementations, there is no way to leave the Wolfram ecosystem while keeping the language;
leaving means rewriting in something else entirely.

Wolfram Language has not failed by any reasonable definition (it remains the primary tool in
large parts of computational science and math education) but it has also never become a general
application-development substrate outside Wolfram's own commercial ecosystem, and that ceiling is
structural rather than technical: a single company controls the only complete implementation, sets
the price, and decides what enters the standard library, so no outside developer or company will
bet a product's core logic on it. It is included here as the clearest example of a technically
excellent intent-language whose adoption ceiling is entirely a vendor-control problem, not an
expressiveness problem.

What lips should keep: rule-based rewriting to a fixed point is a strong model for expressing
"what," not "how," and worth studying for how a vocabulary's compiler might resolve a Solution. The
lesson to avoid is single-vendor control of the only real implementation; lips's kernel
and compiler need to be open enough that no single company's roadmap or pricing can gate adoption.

## Dark (Darklang)

[Paul Biggar founded Dark Inc. in 2017 to build a "deployless" language: a statically
typed functional language paired with its own structured editor, cloud runtime,
and trace-driven debugger, so that writing code and deploying it were the same
act](https://blog.darklang.com/goodbye-dark-inc-welcome-darklang-inc/). Dark ran a hosted
product from 2019 (later called "Darklang-classic") through 2025.

The intent-level artifact was code written directly in Dark's own browser-based structured editor,
immediately live in the cloud with no separate build or deploy step, and inspectable through
recorded traces of real production calls rather than local test runs. The specification gap,
ordinary infrastructure concerns like deployment, hosting, and scaling, was filled entirely by
Dark's own proprietary cloud runtime; there was no other place to run Dark code.

The escape hatch essentially did not exist, and [the founders later named this directly as
a core design mistake: "our custom in-browser editor was bad, and disjointed from our users'
'normal' development flows," and "users voiced a feeling of vendor lock-in, due to our license
and our-cloud-only runtime"](https://blog.darklang.com/an-overdue-status-update/). There was
no way to write Dark code in a normal editor, run it locally, or deploy it outside Dark's own
cloud, so any team that hit a limitation had no partial retreat available, only a full rewrite
in something else.

[Biggar's own retrospective is unusually candid: "we burned cash too quickly between
2017 and 2020... the product wasn't quite good enough back then to raise a Series A,"
and by the time ChatGPT arrived, "our product was not the right one for the era of coding
agents," because a bespoke structured editor made no sense once developers were writing
code inside Cursor, Copilot, and similar LLM-integrated editors rather than Dark's own
tool](https://blog.darklang.com/goodbye-dark-inc-welcome-darklang-inc/). Dark Inc. ran out of
money in 2025 and sold its assets to a new company (Darklang Inc.) formed by former employees,
who [wound down the original hosted "Darklang-classic" product entirely, citing both its ~$2,600 a
month running cost on a tight budget and the fact that it had "not received real feature updates
in over two years"](https://blog.darklang.com/winding-down-darklang-classic/). The successor
company is rebuilding Dark as an open-source language usable in ordinary editors and runnable
anywhere, explicitly reversing the original all-in-one, cloud-only design.

What lips should keep: Dark's founders converged, after the fact, on immutability as "the
secret sauce," valuable specifically because it makes AI-generated code safer to read and
to replay, which validates lips's own premise that a deterministic, inspectable artifact
matters more once an AI is writing the first draft. The lesson to avoid is total: never require
an owner to leave their normal editor, deployment process, and hosting choice in order to use
the System. lips's Solution compiling to an ordinary NixOS module, runnable on the owner's
own machine with the owner's own tools, is the direct fix for exactly the lock-in Dark's founders
named as fatal.

## Eve (Chris Granger)

[Chris Granger, previously the creator of the Light Table IDE, founded Kodowa in 2014 to build
Eve, described as "a programming language and IDE based on years of research into building a
human-first programming platform"](https://chris-granger.com/2016/07/21/two-years-of-eve/),
combining a temporal relational database with a general-purpose declarative language and a
novel end-user interface.

The intent-level artifact shifted across Eve's lifetime. [Granger's own two-year retrospective
reports that the team "built over 30 versions of Eve" in two years, exploring prototypes from
"a graphical database explorer to a document editor with embedded and always up-to-date natural
language queries"](https://chris-granger.com/2016/07/21/two-years-of-eve/), before concluding the
platform (the relational language and database) and the end-user interface needed to be developed
as two separate problems. The specification gap, in the end, was the interface itself: Granger
writes plainly that "the language only takes us part of the way... we're under no delusion that
a textual syntax in a programming context is going to be the thing that ultimately gets us in
the hands of an accountant or a cancer researcher," and that "it's not entirely clear what that
looks like yet."

The escape hatch, once the platform and UI were separated in 2016, was a plain textual syntax and
JSON protocol aimed at developers rather than end users, an implicit admission that the original
end-user vision needed a developer beachhead first. This is a coherent strategy (Granger argues
technology diffuses from technical to non-technical users) but it also meant Eve, after two
years, still had no shipped answer to the problem it was originally founded to solve.

[On January 25, 2018, Granger announced to the Eve mailing list: "Despite some
promising leads and lots of meetings over the past several months, we weren't able
to find a good home for Eve... we have to start the process of winding the company
down"](https://groups.google.com/d/msg/eve-talk/YFguOGkNrBo/EozaCfheAQAJ). The proximate cause
was economic (no acquirer, no sustainable business model found after roughly four years total,
counting Light Table, of related research), but the deeper cause, visible in Granger's own words
a year and a half earlier, is that Eve never converged: 30 prototypes in two years is a sign of
a team still searching for the right interface, not one iterating toward a shippable product,
and the underlying relational-database semantics, however sound, were never enough on their
own to reach the "accountant or cancer researcher" the project was named for.

What lips should keep: Granger's diagnosis that "we can't just paper over the complexity"
and that the platform "has to allow for the representation" (a UI cannot be bolted onto semantics
that were not designed to support it) is a real design constraint. lips sidesteps Eve's
actual failure point by not attempting to invent a novel end-user interface at all: its audience
is software-literate owners and architects working in text, and any friendlier authoring surface
is optional future tooling on top of a already-useful kernel, not a prerequisite for the System
to work.

## Low-Code and No-Code Platforms (OutSystems, Mendix, Retool)

[The low-code category traces its roots to 4GLs and 1990s rapid-application-development
tools, with the market's origin usually dated to 2011 and the term
"low-code" itself coined by Forrester Research analysts on June 9,
2014](https://en.wikipedia.org/wiki/Low-code_development_platform). [OutSystems was
founded in 2001 in Lisbon](https://en.wikipedia.org/wiki/OutSystems) and [Mendix in 2005 in
Rotterdam](https://en.wikipedia.org/wiki/Mendix); both are commercially large today ([Mendix was
acquired by Siemens for $730 million in 2018](https://en.wikipedia.org/wiki/Mendix); [OutSystems
raised at a reported $9.5 billion valuation in 2021](https://en.wikipedia.org/wiki/OutSystems)),
which places this entry firmly in "stalled to a profitable niche" rather than "dead."

The intent-level artifact is a visual model, typically drag-and-drop screens, data models,
and process flowcharts, generated into a full application by the platform's own compiler and
runtime. [Mendix's own framing captures the specification-gap answer directly: "professional IT
people supply the technical, low-coder the logistics theme"](https://en.wikipedia.org/wiki/Mendix),
meaning the platform never intended non-programmers to work unsupervised; a professional developer
remains in the loop for anything technically deep, which quietly concedes the original "citizen
developer replaces the programmer" pitch. [Retool, founded in 2017 and focused from the start on
internal, non-customer-facing tools, put the same concession directly in its own founder's words:
CEO David Hsu described the product as drag-and-drop components "with code written on top of that,
for the last 20% or 30% of the
work"](https://techcrunch.com/2022/07/28/retool-raises-45m-at-a-3-2b-valuation-to-make-building-custom-software-as-easy-as-buying-off-the-shelf/),
an explicit, self-stated version of the escape-hatch pattern this
survey keeps finding.

The escape hatch is "drop into code," available in every major low-code platform as custom widgets,
custom actions, or embedded script blocks, and it is the single most consistent complaint pattern
across the category: [Wikipedia's own summary of criticism notes IT professionals question "whether
these platforms actually make development cheaper or easier" once escape hatches are exercised, and
cites concern that "adopting low-code development platforms internally could lead to an increase in
unsupported" custom extensions](https://en.wikipedia.org/wiki/Low-code_development_platform). Once
an application needs custom code, that code typically still runs inside the vendor's proprietary
runtime, so a team gets neither the full productivity of the visual layer nor the full freedom
of ordinary code; it gets vendor lock-in on top of an escape hatch that never truly escapes.

Low-code did not fail to exist; it failed to fulfill its most ambitious promise,
replacing professional software development at scale, and instead settled into a real
but bounded niche: internal enterprise tools, prototypes, and process automation,
exactly the domain both OutSystems and Mendix now emphasize commercially. [Security
and governance concerns compound the ceiling: Wikipedia notes "growing" concern "over
low-code development platform security and compliance," especially where apps touch consumer
data](https://en.wikipedia.org/wiki/Low-code_development_platform), which limits how far into
mission-critical systems these platforms are trusted to go. The proprietary-runtime lock-in
is the same failure mode seen in 4GLs and Dark, recurring here at enterprise rather than
individual-developer scale.

What lips should keep: low-code's visual-model-to-generated-application pipeline validates
that most CRUD-shaped application logic really can be captured declaratively and compiled without
hand-written code. The property to avoid is the proprietary escape hatch and proprietary runtime;
lips's compile target is an ordinary NixOS module, so there is no vendor-controlled runtime
to be locked into in the first place, and no separate "drop into code" mode whose output cannot
be regenerated.

## Declarative Infrastructure-as-Code (Terraform, CloudFormation, Kubernetes YAML and Helm)

This is the closest living analog to lips's own target: a declarative specification
that compiles deterministically to a running system, at production scale, used by nearly
the entire software industry today. [Terraform, launched by HashiCorp in 2014, uses its
own declarative HashiCorp Configuration Language (HCL) to describe a desired end-state,
then computes and applies the create, update, and delete operations needed to reach
it](https://en.wikipedia.org/wiki/Terraform_(software)). AWS CloudFormation and Kubernetes
manifests (plain YAML, or YAML templated through Helm charts) follow the same declarative,
desired-state model on their respective platforms. This is not a graveyard entry in the sense
of being dead; it is included because its specific failure modes are exactly the ones lips's
Nix-module compilation target must design around from the outset.

The intent-level artifact is the declarative file itself (an HCL module, a CloudFormation
template, a Kubernetes manifest) describing desired end-state rather than the steps to reach
it. The specification gap between "desired state" and "the actual API calls needed" is filled
by each system's own reconciliation engine (Terraform's provider plugins computing a diff and
executing CRUD calls; Kubernetes controllers continuously reconciling actual cluster state
toward the manifest).

The escape hatch is where this family's most instructive failure lives. Helm, the dominant
Kubernetes packaging tool, generates YAML by running Go's text templating engine over YAML files as
plain strings, with no understanding of YAML's own structure until after template expansion. [Helm's
own best-practices documentation has to warn authors to manage whitespace by hand, chomping newlines
with `{{- ... -}}` syntax, precisely because the templater does not know it is producing structured
data until the text is fully rendered](https://helm.sh/docs/chart_best_practices/templates/). This
is the "glue kills the abstraction" pattern in its purest form: a tool meant to generate
structured configuration deterministically instead generates text that merely looks like structured
configuration, and an entire body of "best practices" exists only to work around that category
error. Terraform's own escape hatch, the `local-exec` provisioner and hand-written provider
code, plays a similar role: anything the declarative model cannot express drops straight to an
imperative shell command with no static checking at all.

None of these tools have failed commercially; all three are industry-standard. Their glue problem
shows up instead as chronic, well-documented operational pain: infrastructure "drift" (the real,
running system silently diverging from the declared state after a manual fix or an out-of-band
change), YAML files that sprawl into thousands of near-duplicate lines across environments, and Helm
charts whose logic lives in a templating layer that is invisible to a YAML linter or a Kubernetes
API validator until render time (inference, based on Helm's own documented templating design cited
above and widely reported operational experience across the Kubernetes ecosystem). [HashiCorp's 2023
relicensing of Terraform under the Business Source License, restricting competitive commercial
use, triggered a community fork (OpenTF, later OpenTofu, now under the Linux Foundation) and
public criticism from Pulumi's founder that HashiCorp had refused years of upstream provider
contributions from competitors](https://en.wikipedia.org/wiki/Terraform_(software)), showing
that even a widely adopted, technically successful declarative system remains exposed to the
vendor-control failure mode seen elsewhere in this survey, this time expressed as a license
change rather than a runtime lock-in.

What lips should keep: the desired-state, reconciliation-engine model these tools popularized
(describe the end-state, let a compiler compute what to do to get there) is the right shape,
and it is close to what a NixOS module already does, since Nix builds are themselves declarative
and reproducible by construction. What lips must design out is Helm's specific mistake: text
templating over a structured format, layered on before that format is ever parsed as structured
data. A vocabulary's compiler must always emit through the kernel's own typed representation,
never assemble the Nix output as untyped text, and the licensing lesson argues for lips's
compiler and kernel staying on unambiguously open terms from the start, sibling document
`c-guarantees.md` covers the further step some of these tools' critics took, replacing string
templating with total, typed configuration languages such as Dhall.

## Synthesized Taxonomy of Failure Modes

The thirteen entries above fail, stall, or niche down for a small number of recurring
reasons. Ranked here by how many entries each mode killed or capped, and how hard the mode
is to route around after the fact, with the design property that would have prevented it in
lips's own terms.

**1. Escape-hatch decay: the glue breaks the abstraction's guarantees.** This is the most
lethal and most recurring pattern in the survey. CASE tools lost round-trip engineering the
moment hand-edited code diverged from the model. MDA's PSM layer became the place all real work
happened once it was hand-tuned. Helm renders YAML as untyped text before it is ever parsed
as YAML, and its own documentation exists partly to manage the fallout. Low-code's "drop into
code" still runs inside a proprietary runtime, so it escapes nothing. Dark's founders named
this directly as fatal: no path existed from their structured editor back to a normal one. The
preventive property: an escape hatch must be a first-class, typed, kernel-checked construct
that still goes through the compiler, never a side channel that lets a human or a template
write past the type system directly into the compiled artifact. In lips, a vocabulary that
cannot express something gets a new capability added to the vocabulary and recompiled; nobody
hand-edits the emitted NixOS module and expects it to survive the next compile.

**2. Economics: the technology needed more time to mature than its funding allowed.** VPRI
STEPS was explicitly bounded as a grant-funded science project with a fixed end date, never
structured to become a maintained product. Eve burned through its runway across 30 unconverged
prototypes before finding no acquirer. Dark burned cash between 2017 and 2020 before it could
raise a Series A, then again through 2025 before running out entirely. Intentional Software
survived seventeen years on private capital and a handful of confidential contracts, never a
real product business. The preventive property: the System must be useful to a single owner
on a single machine at small scale from an early milestone, not gated behind a future critical
mass of users, vocabularies, or funding rounds; lips's own scope (one owner, one Solution,
compiling to one NixOS module) is already structured this way.

**3. Vendor or research lock-in: the only complete implementation is closed, proprietary,
or single-owner.** Wolfram Language's reference implementation lives entirely inside one
company's commercial products. Low-code platforms lock generated applications to a proprietary
runtime. Dark's cloud-only runtime was named by its own founders as a top reason for user
distrust. Even open-source Terraform was not immune: HashiCorp's 2023 license change split its
own community. The preventive property: the compiled target must be a standard, independently
inspectable artifact with no single-company gatekeeper. lips's choice of the NixOS module as
canonical target already satisfies this, since Nix and NixOS have their own life outside lips.

**4. Loss of human legibility: the model or diagram stops being what anyone actually reads.**
UML's own reference material concedes most developers draw informal diagrams instead of using
UML as intended; the artifact became decoration rather than source of truth. CASE-generated
code, once hand-patched, becomes unreadable spaghetti no one trusts the model to explain. The
preventive property: the spec itself, not the compiled output, must be the artifact a human
reviews, and it must remain the single source of truth permanently, not merely at the moment of
first generation. lips's one-directional compile (Solution to Nix module, never the reverse)
removes the possibility of the two drifting apart in the first place.

**5. All-or-nothing adoption: no incremental path onto or off of the system.** STEPS required
rebuilding an entire OS stack to demonstrate its result. Dark required abandoning a team's
editor, deployment pipeline, and hosting entirely. Eve, in its early years, asked developers to
learn an entirely new representation with no bridge to existing tools. By contrast, Terraform
and Kubernetes manifests succeeded partly because they could be adopted one resource or one
service at a time, layered onto infrastructure that already existed. The preventive property:
a Solution should compile to one ordinary NixOS module usable alongside hand-written modules
in an existing system, so adoption happens one machine or one component at a time.

**6. Platform death by owner neglect, independent of design quality.** HyperCard is the
clearest case: a well-designed, successful tool died because Apple stopped investing in it,
unrelated to any flaw in HyperCard itself. The preventive property: build on a platform with
governance independent of the System's own maintainers, so the System's fate is not entangled
with one company's unrelated strategic pivot. Building on the existing NixOS/Nix ecosystem,
rather than a bespoke lips-only runtime, is the direct application of this lesson.

**7. The natural-language trap: syntax that looks accessible is mistaken for semantics that are
actually simple.** 4GLs marketed English-adjacent syntax as proof that non-programmers could
write real applications, and that promise fell apart the moment real business logic needed
precise conditionals and exception handling. Inform 7 shows the same surface strategy can work,
but only because its domain (interactive fiction) has a small, stable vocabulary of possible
actions agreed on in advance. The preventive property: treat vocabularies as formal and dense by
design, not as attempts to look like English, and rely on the AI-assisted authoring step, not the
kernel's own grammar, to bridge to a non-technical stakeholder's phrasing when that is even needed.

**8. Interface research immaturity blocking an otherwise sound core.** Eve's own retrospective
states the semantic core (a temporal relational language and database) was comparatively settled
while the end-user interface was never solved, and 30 UI prototypes in two years is the visible
cost of that gap. The preventive property: do not make a novel end-user interface a precondition
for the System to work. lips's audience is software-literate owners and architects working
in ordinary text, which sidesteps this failure mode entirely by not attempting the harder,
still-unsolved problem Eve was actually founded to solve.

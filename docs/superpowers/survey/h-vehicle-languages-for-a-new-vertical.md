# Vehicle Languages for the Next lips Vertical

Configuration is a solved vertical for lips: NixOS, home-manager, kubenix and terranix each supply an externally maintained, machine-queryable schema of option names, and the kernel's merge-by-strength physics matches the option module system each world already runs. This survey asks what comes next: a target whose native semantics is still declarative decisions or rules, but whose subject matter is not system configuration. It scores each candidate against the five criteria the project actually needs (external typed vocabulary, composition algebra, deterministic offline evaluator, breadth of the vertical, ecosystem growth independent of lips), and it tests a sharper, narrower hypothesis raised mid-survey: that some of these languages define a function as an unordered set of guarded clauses, exactly lips's decision base merged by subject. Where that holds, porting lips's kernel semantics is not an analogy, it is close to a literal restatement in a new vocabulary.

## The Clause-Union Hypothesis, Stated Precisely

lips's decision base is a set: same subject and incompatible strength is a conflict, different subjects union without interaction (`DESIGN.md` §2.1, restated in `docs/superpowers/survey/f-decision-calculus-theory.md`). The question this survey adds: does a candidate language define a named unit of behavior (a rule set, a policy set, a decision table, a variable's defining equations) the same way, an unordered set of `pattern -> result` clauses, where clauses on the same pattern conflict and clauses on different patterns union? If yes, the subject is the name, the clause is the decision, and the target language's own conflict/union rule is lips's `Replace`/`Append` `MergeMode`, already present, needing no new kernel physics, only a new option-vocabulary lookup and a new realization backend. If no, and instead the language relies on textual order, an explicit priority number an author must dial, or a DAG a build tool schedules, then adopting it would drag target-specific composition knowledge into a kernel that is supposed to stay domain-blind (see `AGENTS.md`, "The Kernel Knows Nothing"), which is exactly the failure mode this project exists to avoid.

## Catala

Catala is a domain-specific language, from Inria, "for deriving faithful-by-construction algorithms from legislative texts," built so that each line of a program is traceable to a clause of a specific statute (catala GitHub README, github.com/CatalaLang/catala). Its ICFP-line publication is Merigoux, Chataing and Protzenko, "Catala: A Programming Language for the Law" (arXiv:2103.03198, submitted March 2021; the abstract records a compiler with core steps "proven correct using the F* proof assistant," evaluated on section 121 of the US federal income tax code and French family benefits, in the course of which the authors "uncover a bug in the official implementation"). The formalization is public in `doc/formalization/` of the compiler repository: an F* proof of the translation from a "default calculus" to a target lambda calculus, with one admitted lemma disclosed by name (a substitution-invariance lemma, not a correctness gap in the exceptions logic itself).

**Composition algebra.** This is the entry the clause-union hypothesis was built to test, and Catala answers it directly but not for free. A Catala variable can be defined by several piecewise clauses, each guarded by a condition (`under condition ... consequence equals ...`), scattered across however many articles the underlying statute spreads it over. The book's tutorial states the merge rule as an algorithm:

> "The semantics of Catala are formally defined and based on prioritized
> default logic, which translates intuitively to the following algorithm
> describing how to compute exceptions: 1. Gather all definitions
> (conditional or not) for a given variable; 2. Among these definitions,
> check all that apply (whose conditions evaluate to true): if no definition
> applies, the program crashes... if only one definition applies, then pick
> it... if multiple definitions apply, then check their priorities: if
> there exists one definition that is an exception to all the others that
> apply, pick it... otherwise, the program crashes with an error
> ('conflicting definitions')."
> (book.catala-lang.org/en/2-2-conditionals-exceptions.html)

Read against lips: the variable is the subject, each piecewise definition is a decision, and two definitions whose conditions both hold and which stand in no exception relation are the conflict lips calls incompatible strength; the book's own error message is literally "conflict between multiple valid consequences for assigning the same variable." That is `Replace` with a conflict report, structurally identical to lips's merge-by-strength. The difference, and it is the whole difference between Catala and the CSS/Drools pattern the calculus survey (survey F) warns about, is where the priority lives: Catala's `exception` keyword names a relation between two specific clauses ("this clause is an exception to that one"), not a global integer any author can dial to make a clause win. That is closer to lips's structural strength (system default < engine default < program) than to an authored priority number, and it is a genuine design idea lips does not yet have: a strength expressed as a named edge between two decisions rather than as a scalar. Clauses on genuinely different subjects (different variables) union trivially, with no special syntax, exactly as lips's decision base does.

**External typed vocabulary.** Weak, and structurally so. Catala's names are the variables and structures the author declares in the program itself (`declaration structure Individual: data income content money`); there is no external, independently maintained schema of legal concepts to query the way nixpkgs' option tree is queried. The `Individual`/`income` vocabulary here is invented per program, not grounded. A mint into Catala would have nothing to ground names against except whatever the author already typed, which inverts lips's model: lips's value comes from confirming a name against an authority the author does not control, and Catala offers no such authority.

**Deterministic offline evaluator.** Strong. `clerk run` (the reference driver referenced in the book's own error trace, `clerk run tutorial.catala_en --scope=Test`) and the standalone compiler both run offline with no network or model dependency; the F* proof gives a formal, not just empirical, determinism argument for the compilation step it covers.

**Breadth of the vertical.** Large in principle (any statute that is "an algorithm in disguise," the paper's own phrase, covering tax law, social benefits, eligibility rules) but the corpus of actually-written Catala programs is small: `catala-examples` and the French family-benefits and US tax-code demonstrations are the visible body of work. Unverified: I searched for a citable account of Catala running in French government production (beyond the paper's own worked examples) and did not find a primary source confirming operational deployment; the honest claim is "research pilot with real legal texts," not "deployed system," pending better evidence.

**Ecosystem growth independent of lips.** Weak. The project is Inria-led, 2,353 GitHub stars, active but small (github.com/CatalaLang/catala, fetched stargazer count). It grows because a small academic-and-legaltech community maintains it, not because a large external body publishes new legal vocabulary for it to consume.

## OPA / Rego

Rego is the policy language of the Open Policy Agent, a CNCF Graduated project (openpolicyagent.org/docs/ecosystem, fetched: the ecosystem page lists OPA, Regal, Gatekeeper and Conftest under the CNCF banner). OPA's own docs describe Rego as "inspired by Datalog and extend[ing] it to support structured document models such as JSON" (openpolicyagent.org/docs/policy- language).

**Composition algebra: this is where the clause-union hypothesis is not an analogy but close to a restatement.** Rego rules come in two shapes, and the documentation names the merge rule for each explicitly.

Partial (incremental) rules union:

> "A rule may be defined multiple times with the same name. When a rule is
> defined this way, the rule definition is called incremental because each
> definition is additive. The document produced by incrementally defined
> rules is the union of the documents produced by each individual rule. An
> incrementally defined rule can be intuitively understood as `<rule-1> OR
> <rule-2> OR ... OR <rule-N>`."
> (openpolicyagent.org/docs/policy-language, "Incremental Definitions")

Complete rules conflict on disagreement:

> "Documents produced by rules with complete definitions can only have one
> value at a time. If evaluation produces multiple values for the same
> document, an error will be returned... OPA returns an error in this case
> because the rule definitions are in conflict. The value produced by
> `max_memory` cannot be 32 and 4 at the same time."
> (same page, "Complete Definitions")

Map this onto lips term for term: the rule name is the subject; each rule body plus head is a decision; a complete rule's disagreement is exactly the `Replace`-mode conflict lips reports as two decisions with both provenances; an incremental (partial, set- or object-valued) rule's union is exactly the `Append`-mode aggregation lips already has a `MergeMode` for. The isomorphism is close enough that a lips engine targeting Rego would not need to invent a translation of its merge semantics, it would need to pick, per subject, whether the emitted Rego is a complete rule (program's assertions must not disagree) or an incremental rule (program's assertions accumulate), which is exactly the choice `MergeMode` already encodes for NixOS options. Rego even extends the same discipline to comprehensions: "Object comprehensions are not allowed to have conflicting entries, similar to rules" (same page). This makes Rego, for the *logic* vertical, structurally what the NixOS module system is for the *config* vertical: a target whose native combination algebra is the lips kernel's algebra, not a foreign one the kernel would have to be taught.

**External typed vocabulary.** Partial. OPA is domain-blind by design (it evaluates policy against whatever JSON input an integration hands it), which is a virtue for OPA and a problem for lips's grounding story: there is no single external, queryable schema of "legal policy vocabulary" the way nixpkgs has one option tree. What exists instead is per-integration input schemas (Kubernetes admission review objects, Envoy ext_authz requests, Terraform plan JSON), each externally maintained by its own project, each independently queryable (a Kubernetes `AdmissionReview` schema, Terraform's plan JSON schema). A lips mint into Rego for Kubernetes admission control could ground field names against the Kubernetes OpenAPI schema exactly as it grounds Nix option names today; a mint into generic Rego with no fixed input shape could not. The fit is real but conditional on picking a concrete integration, not the bare language.

**Deterministic offline evaluator.** Strong. `opa eval <query>` is documented as a first-class CLI verb ("Evaluate a Rego query and print the result," openpolicyagent.org/docs/cli) that runs fully offline against local policy and data files; OPA also compiles to WASM for embedding. No service call is required for evaluation.

**Breadth of the vertical.** Large and growing. Beyond OPA itself (12,056 GitHub stars, github.com/open-policy-agent/opa fetched), Gatekeeper (4,251 stars) targets Kubernetes admission control specifically, and the OPA ecosystem page lists Regal (a linter) and Conftest (policy testing for config files) as sibling first-party projects; the wider integration list (API gateways, CI policy, Terraform plan review) is one of the widest of any candidate here.

**Ecosystem growth independent of lips.** Strong. CNCF graduation is itself governance evidence of external maintenance breadth beyond a single vendor.

## Cedar

Cedar is AWS's authorization policy language, open-sourced and, distinctly among this list, formally specified in Lean with differential testing against the production Rust evaluator (github.com/cedar-policy/cedar-spec, fetched: "This repository contains the formalization of Cedar and infrastructure for performing differential randomized testing (DRT) between the formalization and Rust production implementation," with `cedar-lean` holding "the Lean formalization of, and proofs about, Cedar").

**Composition algebra.** Cedar policies are individually `permit` or `forbid` statements over a fixed schema (principal, action, resource, context); the docs state the combination algorithm as three numbered rules:

> "1. If any forbid policy evaluates to true, then the final result is Deny.
> 2. Else, if any permit policy evaluates to true, then the final result is
> Allow. 3. Otherwise (i.e., no policy is satisfied), the final result is
> Deny."
> (docs.cedarpolicy.com/auth/authorization.html, "Algorithm")

and names the resulting properties directly: "default deny... forbid overrides permit... skip on error" (same page, "Discussion"). Tested against the clause-union hypothesis, this is a narrower structure than Rego's: there are exactly two subjects, the Allow verdict and the Deny verdict, each an `Append`-mode union of every policy clause that evaluates true for that verdict (rule 1 and rule 2 are each an OR over a policy set, matching Rego's incremental-rule union), and those two subjects stand in a fixed, global strength order (forbid always outranks permit) rather than lips's per-subject, provenance-derived strength. Cedar's own justification for hardcoding that order rather than letting authors set it is exactly the argument survey F makes for lips's structural strength over an authored number: "readers just have to understand what each policy says, not what it doesn't... forbid policies effectively define permission 'guardrails' that permit policies cannot cross" (same page). Cedar is a specialization of the clause-union algebra to two fixed-priority verdict buckets; it fits the hypothesis, but a lips mint into Cedar could only ever choose which bucket a clause lands in, never invent a new priority level, because the language gives it none to invent.

**External typed vocabulary.** Strong, and structurally closer to lips's nixpkgs story than any other candidate surveyed. Cedar requires a schema (entity types, actions, attribute types) and validates policies against it; the terminology page states plainly that "if you don't define a schema, then Cedar doesn't have a way to ensure that the policies adhere to your intentions" (docs.cedarpolicy.com/overview/terminology.html, "Schema"). Unlike OPA, whose input shape is integration-defined and only optionally schema-checked, Cedar bakes schema validation into the language's own tooling. The catch is that, unlike nixpkgs, no single external body publishes a shared Cedar schema across many applications: each application authors its own entity and action types, so the schema is per-application, grounded by the application team rather than inherited from an upstream package set. A lips mint into Cedar would ground names against *an* application's schema (queryable, typed, exactly the nixpkgs-options shape) but would need that schema handed to it, not discovered from a shared upstream the way nixpkgs already is.

**Deterministic offline evaluator.** Strong. The Rust `cedar-policy` crate and its CLI evaluate policies offline with no service dependency; the Lean formalization and DRT harness give a second, independent evaluator whose agreement with the production one is continuously tested rather than merely assumed.

**Breadth of the vertical.** Partial. Authorization is broad as a problem class, but Cedar's actual footprint today is AWS-centric (Verified Permissions, AWS's own services) plus a smaller open-source following (1,632 GitHub stars, github.com/cedar-policy/cedar fetched, an order of magnitude below OPA's).

**Ecosystem growth independent of lips.** Partial. Growth is real but concentrated in one primary sponsor (AWS) rather than a broad multi-vendor CNCF-style governance body.

## OMG DMN (Decision Tables)

DMN 1.4 is the OMG's standard for decision logic, and the clause-union question has a spec-mandated, textbook answer here rather than an inferred one: DMN names the conflict-resolution rule for a decision table directly as its "hit policy," a single required or defaulted indicator per table.

> "The hit policy specifies what the result of the decision table is in
> cases of overlapping rules, i.e., when more than one rule matches the
> input data... The hit policy SHALL default to Unique, in which case the
> hit indicator is optional. Decision tables with the Unique hit policy
> SHALL NOT contain overlapping rules."
> (OMG DMN 1.4 specification, section 8.2.10, PDF fetched from
> omg.org/spec/DMN/1.4/PDF, pp. 67-68)

The spec then enumerates seven policies by name: Unique (no overlap possible, lips's non-conflicting `Replace`), Any (overlap permitted only if every matching rule agrees on the output, an idempotent `Append`), Priority (multiple rules match, an explicit priority order in the output list picks one, lips's `Replace` with authored rather than structural strength), First (rule order breaks the tie, the one policy the spec itself calls bad practice: "first hit tables are not considered good practice because they do not offer a clear overview of the decision logic"), and three multi-hit policies, Output order, Rule order, and Collect (with optional `+ < > #` aggregation operators), which are `Append` by construction, aggregated exactly the way lips's list-valued `Append` mode is. This is the most explicit, most exhaustively named clause-union vocabulary of any candidate surveyed: DMN does not leave the merge rule implicit in an evaluator's behavior, it puts a one-letter code in a spec-mandated table cell and defines every code's semantics in the standard itself. Survey F already flagged this ("lips's equivalent is `MergeMode`... the stronger version of the same idea") without the direct spec quote; this survey supplies it.

**External typed vocabulary.** Weak to partial. A DMN decision table's input and output columns are typed against whatever data model the author (or FEEL expression) declares; there is no external, cross-organization registry of decision-table subjects the way nixpkgs enumerates options. Where DMN tables are generated against a specific business object model (an insurance product catalog, a claims schema) that model can serve the grounding role, but, as with Cedar, it is locally authored rather than centrally published.

**Deterministic offline evaluator.** Strong in principle, mixed in practice. The standard defines FEEL (Friendly Enough Expression Language) precisely enough that conformant engines should agree, and open-source engines (Camunda's DMN engine, jDMN) evaluate offline with no service dependency. Cross-engine determinism is a conformance-testing question this survey did not independently verify beyond the spec's own conformance-levels language.

**Breadth of the vertical.** Large. Decision tables are the lingua franca of business rules across insurance underwriting, loan eligibility, claims adjudication and regulatory compliance; DMN specifically targets the segment of "business rules" that already speaks in tables, which is most of it.

**Ecosystem growth independent of lips.** Partial. OMG stewards the standard and multiple vendors (Camunda, Drools/jBPM, IBM) implement it independently, which is real multi-vendor growth, but adoption skews toward enterprise BPM suites rather than the broad open developer ecosystem OPA or dbt enjoy.

## dbt

dbt (data build tool) is a SQL-transformation framework; its docs describe a model as, at minimum, "a SQL select statement" whose output shape is optionally locked down by a model contract ("dbt will verify that your model's transformation will produce a dataset matching up with its contract, or it will fail to build," docs.getdbt.com/docs/collaborate/govern/model-contracts).

**Composition algebra: this is where dbt fails the clause-union test outright, and it is worth stating precisely why.** Two dbt models do not combine by declaring the same subject and letting a merge rule decide; they combine by one model's SQL calling `ref()` on another, which dbt's own materials describe as building "a Directed Acyclic Graph... to visualize data pipelines and lineage" and to "understand dependencies between data models" (docs.getdbt.com/terms/dag). That is composition by explicit, author-declared reference forming an ordered execution plan, the same shape lips's `f-decision-calculus-theory.md` survey flags as the bad case in term- rewriting-with-priorities: order matters, and the order is not a byproduct of subject identity, it is the entire mechanism. Two independently written dbt models cannot be merged the way two lips decision bases can; they can only be wired together by one calling the other by name. This is the same shape as orchestration (Step Functions, Temporal, Airflow), not the shape of Rego, Cedar or DMN, even though dbt's *domain* (data transformation) looks declarative on the surface.

**External typed vocabulary.** Strong, and this is dbt's genuine strength: dbt's schema comes from the warehouse's own `information_schema` (queried at run time by dbt itself) plus model contracts that pin column names and types, and dbt's package ecosystem (dbt Hub, `dbt_utils` and hundreds of community packages) is externally maintained vocabulary in the sense that a package publishes macros and models other projects `ref()` without reinventing them. That half of the criterion, an externally grown, queryable vocabulary, is present and healthy.

**Deterministic offline evaluator.** Partial. `dbt compile` and `dbt build` are deterministic given a fixed warehouse state, but "offline" is qualified: dbt always compiles against a live warehouse connection to resolve `ref()`/`source()` and to run the SQL it generates, so there is no lips-style bit-identical, no-service compile step; the artifact `dbt` produces (compiled SQL) is deterministic, but producing and validating it is not offline in lips's sense.

**Breadth of the vertical.** Very large: dbt is close to the default transformation layer for the modern analytics-engineering stack (13,559 GitHub stars, github.com/dbt-labs/dbt-core fetched), with a correspondingly large corpus of real, publicly shared projects.

**Ecosystem growth independent of lips.** Strong; dbt Labs plus a large open package ecosystem grow the vocabulary independent of any one adopter.

**Verdict for this survey's purpose.** dbt is the clearest false positive in the candidate list: broad, well-typed, thoroughly external, and yet its composition algebra is the one lips's kernel is built specifically not to need, because that algebra is a DAG a build tool schedules, not a set a kernel merges by name. Adopting it as a lips target would force exactly the target-specific composition knowledge ("in what order do these two decisions execute") into a kernel whose invariant is that it never learns such a thing.

## The Rest, Briefly

**XACML** is a warning, not a candidate. Its combining algorithms (`deny-overrides`, `permit-overrides`, `first-applicable`, and, per the wikipedia summary of the standard's combining-algorithm section, "deny-unless-permit"/"permit-unless-deny" for whole PolicySets) are named per policy rather than fixed by the language the way Cedar's forbid-overrides-permit is: the authored-priority antipattern survey F already catalogued for CSS specificity and Drools salience ("priority is an unstructured integer any author may set at any site... the chain then encodes nothing"). That combining-algorithm identifier being a per-policy attribute, rather than a global kernel rule, is a plausible partial explanation for the standard's decline into a smaller, more XML-tooling-heavy niche than OPA later occupied for the same problem class; this is inference, not a claim found stated as such in a primary source.

**Kyverno** (7,987 GitHub stars) targets the same Kubernetes-admission niche as Gatekeeper but writes policy in Kubernetes-native YAML rather than Rego, trading Rego's general composition algebra for a narrower, admission-specific rule shape; folding it into the OPA/Gatekeeper entry rather than treating it separately is the right scope call here.

**Protobuf/gRPC, OpenAPI, GraphQL SDL, JSON Schema** are interface vocabularies, not decision vocabularies: they describe the shape of data, not a rule resolving a conflict between two assertions about one subject. A schema field either exists once or it is a schema error, closer to lips's `Replace`-only degenerate case than to a rich merge algebra, and CUE already covers this ground in survey F.

**Step Functions / Amazon States Language, Temporal, XState/SCXML, Airflow/Dagster** were not fetched in depth because dbt's DAG finding already establishes the shared negative result: an ordered execution graph is not a name-merged decision set, and grafting one onto lips's kernel would require the kernel to learn "what happens before what," the class of target-specific knowledge `AGENTS.md` forbids.

## Ranked Verdict

| Candidate | External vocabulary | Composition algebra | Deterministic offline eval | Vertical breadth | Ecosystem growth | One-line verdict |
|---|---|---|---|---|---|---|
| Rego / OPA | partial (per-integration schemas) | **strong** (incremental=Append, complete=Replace, spec-named) | strong (`opa eval`) | strong (CNCF-graduated, wide) | strong (CNCF) | The semantic mirror for logic that NixOS is for config; pick an integration schema and the algebra is already isomorphic. |
| Cedar | strong (mandatory schema) | strong but narrow (2 fixed-priority buckets, spec-named) | strong (Rust + Lean DRT) | partial (AWS-centric) | partial (single primary sponsor) | Best-grounded and best-verified, but its combination algebra has no room for a third priority level. |
| DMN | weak/partial (locally authored models) | **strong** (hit policy is a spec-mandated merge-mode literal) | strong in spec, mixed across engines | strong (business rules is huge) | partial (multi-vendor, enterprise-skewed) | The most explicit clause-union vocabulary of any candidate; weak only on the external-schema axis. |
| Catala | weak (no external schema) | strong (prioritized defaults; strength as a named edge, not a number) | strong (`clerk run`, F*-proven compiler step) | large in principle, thin in practice | weak (small academic community) | Semantically the closest cousin to lips's whole worldview, but nothing external to ground names against. |
| dbt | strong (warehouse schema + packages) | **weak/none** (DAG via `ref()`, order-sensitive) | partial (needs a live warehouse) | very large | strong | The false positive: everything external and typed, but the wrong algebra entirely. |
| XACML | partial (attribute schemas) | weak (authored per-policy combining algorithm) | strong (offline PDP) | was large, now declining | weak (largely superseded) | The cautionary tale: authored priority, not structural, and it shows in its decline. |

## The Two or Three Worth Trying First, and the Exact First Experiment

**Rego, first.** It is the strongest fit on the criterion this survey found sharpest: its own documentation names the merge rule (`Replace` for complete rules, `Append` for incremental rules) in almost lips's own vocabulary, its evaluator is a single deterministic offline binary, and its ecosystem is the largest and most independently governed of any candidate. The first mint: take a small, already-solved config domain lips knows well (say, a firewall or admission-control policy, "deny requests to namespace X unless the requester carries role Y") and mint a Rego engine targeting Kubernetes `AdmissionReview` objects, grounding option-analogue names (fields of the admission request, `object.metadata.namespace`, `object.spec.*`) against the Kubernetes OpenAPI schema exactly as a NixOS mint grounds `services.*` against nixpkgs. Falsifier: if the mint cannot express "two independently written policy lines about different namespaces must compose without one author reading the other's rule," the way two `backup.lips` instances compose today, the clause-union isomorphism was cosmetic, not structural, and Rego drops to the same tier as Catala (interesting semantics, no path to reuse lips's kernel unchanged).

**Cedar, second, specifically because its schema mandate makes the grounding story easier to bootstrap than Rego's.** The first mint: a small multi-tenant SaaS authorization scenario ("editors of a document may share it with viewers, owners may revoke access") minted against a Cedar schema the human supplies once (entity types `User`, `Document`, actions `view`/`edit`/`share`), with lips's mint-time lookup confirming action and attribute names against that schema exactly as it confirms a Nix option path today. Falsifier: if a program needs a third priority tier ("this policy overrides that permit, but only when this other forbid does not also fire"), Cedar's fixed two-bucket algorithm cannot express it without leaving the language, which would mean Cedar's "clean" composition story is clean only because it is narrow, and lips would be discovering the limit of a target rather than a limit of its own kernel.

**Catala, worth a spike, not a mint, third.** Its prioritized-default algebra is the closest philosophical relative to lips of anything surveyed, including the "strength as a named edge" idea lips does not currently have, but the missing external vocabulary is not a small gap, it is the whole reason lips grounds names in the first place. The right first experiment is smaller than a mint: take one already-written Catala example from `catala-examples` (a small eligibility rule, not a full tax code) and ask whether an *existing* legal or regulatory schema (a government open-data API naming benefit categories, say) could stand in for nixpkgs as the grounding authority. Falsifier: if no such schema exists for any real regulatory domain at nixpkgs' scale and specificity, Catala stays a fascinating sibling design, not a lips target, until someone builds that schema, which is not lips's job to build.

**What would kill all three at once.** If, across three independent mint attempts (Rego, Cedar, and a DMN spike), the engine's rules keep needing to know *which* clause should win beyond what the target's own merge-mode literal already expresses (Rego's incremental/complete choice, Cedar's permit/forbid bucket, DMN's hit-policy code), then the clause-union hypothesis is confirmed exactly where it matters and the kernel needs no new physics, only new realization backends and new schema lookups: the config vertical's whole playbook, replayed once per world. If instead every mint needs some escape hatch the target's own merge algebra cannot express (an authored priority number, a rule order, a DAG), that is the signal the vertical is a worse fit than this survey concluded, and the honest fallback is to say so and try the next candidate rather than bend the kernel to fit.


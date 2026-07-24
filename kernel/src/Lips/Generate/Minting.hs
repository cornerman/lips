{-# LANGUAGE OverloadedStrings #-}

-- | The pure parts of @generate@ (crystallization + engine-synthesis plans):
-- the model mints a whole /engine/ -- patterns (the language), rules (the
-- mechanisms), demands (completeness) -- and never the meaning of the program.
-- The kernel crystallizes the program with the minted engine and validates by
-- a full run; nothing the model says becomes meaning except through
-- deterministic template matching.
--
-- With the back half minted too, no vocabulary hint remains: the model invents
-- the intermediate subjects itself, and closure is /checked/, not trusted --
-- an unmapped decision, an unmet demand, an uncovered line, or invalid Nix
-- each fails the validation run.
--
-- This module holds the system prompt and the parser for the model's reply.
-- The model call itself is IO and lives in the CLI. The model replies with one
-- confidence-prefixed item per line; the item body distinguishes the three
-- forms (pattern, @match@ rule, @demand@).
module Lips.Generate.Minting
  ( systemPrompt
  , systemPromptFor
  , promptWithDirection
  , EngineItem (..)
  , SourceFile (..)
  , ItemCandidate (..)
  , parseEngineCandidates
  , assemble
  , expectsOf
  , sourcesOf
  , uncheckableExpects
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Kernel.Engine.Data      (DemandSpec, Emit (..), MapRule (..), parseDemandBody, parseRuleBody)
import Lips.Kernel.Engine.Value     (valueRefsDerivation)
import Lips.Generate.Harness (Confidence (..))
import Lips.Nix.Target       (Target (..))
import Lips.Kernel.Expect          (Expect (..), parseExpectBody)
import Lips.Kernel.Lang.Store        (EngineData (..), parsePatternBody)
import Lips.Kernel.Lang.Pattern     (Pattern)

-- | A generated source file for an artifact: its artifact name, the relative
-- path within the artifact's source tree, and the verbatim content. Written to
-- @<program>.artifacts/<name>/<path>@ and staged at @./artifacts/<name>@ for
-- the build (artifacts plan, option 1).
data SourceFile = SourceFile
  { sfArtifact :: Text
  , sfPath     :: Text
  , sfContent  :: Text
  }
  deriving (Eq, Show)

-- | One minted item: an engine part (pattern, rule, demand), a behavioral
-- assertion (the @.expect@ contract), or a generated source file (an artifact's
-- source, a separate committed file, not part of the engine).
data EngineItem
  = ItemPattern Pattern
  | ItemRule MapRule
  | ItemDemand DemandSpec
  | ItemExpect Expect
  | ItemSource SourceFile
  -- | A plain-language reason a low-confidence item is unsure. Carries no
  -- engine meaning (dropped by 'assemble'\/'expectsOf'\/'sourcesOf'); it only
  -- feeds the refusal message, keyed by the id it shares with its item.
  | ItemNote Text
  deriving (Eq, Show)

-- | An item the model proposes, with the confidence it attaches to it.
-- @icLine@ retains the raw minted line verbatim (@<confidence> <id> <body>@)
-- so the deduce-or-fail refusal can echo exactly what the model emitted.
data ItemCandidate = ItemCandidate
  { icItem       :: EngineItem
  , icConfidence :: Confidence
  , icLine       :: Text
  , icId         :: Text     -- ^ the line's id token, so a note pairs to its item
  }
  deriving (Eq, Show)

-- | The instruction given to the model. A versioned System artifact, stored in
-- the repository and reviewable (spec section 5, layer 3).
-- | The mint prompt for a target world: a world-steering preamble naming the
-- option namespaces to emit into, then the world-neutral body. The preamble is
-- the ONLY thing that differs per world; the body's grammar (patterns, rules,
-- typed holes, artifacts, expects) is identical.
systemPromptFor :: Target -> Text
systemPromptFor t = worldSection t <> "\n" <> commonBody

-- | Kept for back-compat and the pinned-artifact test: the NixOS prompt.
systemPrompt :: Text
systemPrompt = systemPromptFor Nixos

-- | The per-world steering preamble: which option namespaces the mint must
-- emit into. This is where the world lives; the body below is world-neutral.
worldSection :: Target -> Text
worldSection Nixos = T.unlines
  [ "TARGET WORLD: NixOS (a whole machine, root). Emit NixOS option paths:"
  , "services.*, systemd.services.* and systemd.timers.*, environment.*,"
  , "networking.*, users.*, and so on. <self> keys an attrsOf-submodule"
  , "instance name (services.restic.backups.<self>, systemd.services.<self>)." ]
worldSection HomeManager = T.unlines
  [ "TARGET WORLD: home-manager (one user's $HOME, unprivileged). Emit"
  , "home-manager option paths ONLY, never NixOS system options: programs.*,"
  , "services.* (home-manager user services), systemd.user.services.* and"
  , "systemd.user.timers.*, home.packages, home.file.*, home.sessionVariables,"
  , "xdg.*. There is no system-level config and no root. <self> keys an"
  , "attrsOf-submodule instance name (systemd.user.services.<self>)." ]

-- | The world-neutral body of the mint prompt: the grammar the model must
-- emit. Named 'commonBody' because it is shared by every target; the world is
-- chosen by 'worldSection' above.
commonBody :: Text
commonBody = T.unlines
  [ "You crystallize a loose program into a lips ENGINE: patterns (the"
  , "language), rules (the mechanisms), and demands (completeness). You never"
  , "state the program's meaning; the kernel derives it deterministically by"
  , "applying your patterns to the program text."
  , ""
  , "Your situation: you act exactly once. Afterwards the human edits the"
  , "program and the kernel re-reads it with your patterns, deterministically,"
  , "without you. So: replace EVERY program value with a hole, so edits flow"
  , "without regeneration. The engine you mint is pure data; there is no"
  , "escape to code. Never guess. Route each gap by its kind:"
  , "  - A missing PROGRAM FACT (a value a human could write in the program and"
  , "    a pattern could read) is not yours to invent: emit a high-confidence"
  , "    demand asking for it, AND a pattern that will read the answer line, so"
  , "    the human states it and re-runs. Prefer this whenever the program is"
  , "    simply silent about something its setup needs."
  , "  - A value you must still choose (a free default, or a build input you"
  , "    cannot deduce) gets LOW confidence -- refusal beats invention -- and a"
  , "    because-note naming, in one plain sentence, what the human could state"
  , "    to pin it: <confidence> <id> because \"...\" (same id as the item)."
  , "Never work around the value grammar (no packing computation into strings);"
  , "if something is inexpressible, give it low confidence so the kernel is"
  , "extended instead."
  , ""
  , "Output ONLY lines of these forms, no prose, no code fences. Every line"
  , "names its kind with a leading keyword (pattern|match|demand|expect|because),"
  , "so a"
  , "pattern template may itself begin with any word:"
  , ""
  , "  <confidence> <id> pattern <template> => <kind> <subject> <strength> \"<assertion>\" ; <kind> <subject> <strength> \"<assertion>\""
  , "  <confidence> <id> match <kind> <subject> => <option.path> \"<rhs>\" ; <option.path> \"<rhs>\""
  , "  <confidence> <id> demand <subject> \"<question>\""
  , ""
  , "confidence: a number in [0,1]; below 0.7 means unsure, and the build will"
  , "refuse the engine (that is correct behavior, not failure)."
  , ""
  , "PATTERNS (ids p1, p2, ...): one per distinct line shape; together they"
  , "must cover every input line. template = the loose line with VALUES"
  , "replaced by <holes>; fixed words match literally (case-insensitive)."
  , "Each hole binds exactly one token, captured verbatim. To capture a QUOTED"
  , "value that may contain spaces, use a quoted hole: text \"<body>\" binds the"
  , "inner text of a \"...\" value (quotes dropped). A BULLETED list item begins"
  , "with a literal - token, so include it (- <path> ...); put the item's own"
  , "value (e.g. the path) into the subject so each item is a distinct decision."
  , "One line often states SEVERAL facts (\"http server in go on port 8080\" fixes"
  , "language AND port; \"- /hi => status 200 text/plain \\\"hi\\\"\" fixes a route's"
  , "status, type and body). A line matches ONE pattern, so that pattern must"
  , "emit ONE decision per fact, separated by ' ; ', or a demand on the second"
  , "fact can never be met. Give each emit its own subject."
  , "A HEADING or label line that only groups and introduces the lines under it"
  , "(e.g. \"http routes:\") carries no value to realize: emit a single"
  , "'concept' decision for it and write NO rule -- a concept is decorative"
  , "vocabulary, exempt from realization. Use the heading to understand the"
  , "grouped lines: give those items a shared subject prefix (routes -> the"
  , "items become route.<path>...), so the group is legible in the output. When"
  , "a line under a heading is ONLY the item's value (one token, no other"
  , "structure), its pattern template is a single hole and its subject is keyed"
  , "by that hole alone (<item> => fact group.<item>), so each bare line becomes"
  , "its own distinct subject and the items never collide; one rule then emits"
  , "each to a list option, which aggregates the items from all such lines."
  , "kind: one of"
  , "concept fact oblige forbid allow invariant view assume steer glue meta."
  , "strength: stated. subject: invent a dotted vocabulary for this problem"
  , "(e.g. backup.source). Every hole used in the subject or assertion MUST"
  , "appear in the template. Patterns must be orthogonal: no input line may"
  , "match two of them."
  , ""
  , "SEVERAL PROGRAMS: you may be given more than one example program (each in a"
  , "=== program ... === block). They are examples of ONE language. Generalize"
  , "ACROSS them: the same line-shape appearing in different programs is a SINGLE"
  , "pattern, and every position where the examples differ is a hole (this is how"
  , "you learn what varies). Never mint a separate pattern per program -- that"
  , "breaks orthogonality, since the shared line then matches two patterns."
  , ""
  , "RULES (ids r1, r2, ...): map EVERY subject your patterns produce to"
  , "option assignments in the target world named above; any decision no rule"
  , "maps fails the build --"
  , "EXCEPT a 'concept' (decorative heading), which needs no rule."
  , "Every <rhs> is wrapped in ONE pair of surrounding double quotes, and"
  , "inside it is a VALUE, not a Nix expression -- the kernel rejects"
  , "computation. The value forms are the Nix value algebra minus computation:"
  , "a string \\\"...\\\", a list [ ... ], true, false, null, an integer, a float,"
  , "a path (/x or ./x), a TYPED HOLE (below), and a bare ${pkgs.<name>} or"
  , "${artifact.<name>} REFERENCE. A string rhs looks like \"\\\"<value>\\\"\" and a"
  , "list rhs looks like \"[ \\\"timers.target\\\" ]\". A list of PACKAGES (an"
  , "option like environment.systemPackages, or writeShellApplication's"
  , "runtimeInputs) holds bare references, not strings:"
  , "\"[ ${pkgs.curl} ${artifact.<name>} ]\" -- each element is a derivation."
  , "Inside Nix strings only two things beyond literal text parse: the holes"
  , "<value> (the matched decision's assertion) / <value.N> (its Nth"
  , "whitespace-separated token, 1-based; use it when a pattern's assertion"
  , "joins several holes) and ${pkgs.<name>} package references. Outside a"
  , "string, a bare ${pkgs.<name>} or ${artifact.<name>} is itself a value (a"
  , "list element). No functions, no splitString, no other ${...}. Do not quote"
  , "a package into a string when the option wants a derivation. Template holes"
  , "bind single tokens;"
  , "punctuation like a trailing period stays outside the hole."
  , ""
  , "TYPED HOLES: a NixOS option is typed. For a NON-string option (a port, a"
  , "count, a size, a toggle, a path) do NOT quote the hole; use a typed hole"
  , "naming the type: <value:int>, <value:bool>, <value:float>, <value:path>"
  , "(or <value.N:int> for the Nth token). It emits a value of that type and"
  , "fails if the program token is not of that type. Quote a hole"
  , "(\"\\\"<value>\\\"\") only for genuinely string-typed options. So a port rule"
  , "looks like services.nginx.defaultHTTPListenPort \"<value:int>\". Realize"
  , "work as services and timers or other options in the target world."
  , ""
  , "PACKAGE NAMES: some options hold package DERIVATIONS (a list of"
  , "packages -- environment.systemPackages, home.packages, a runtimeInputs),"
  , "and the program NAMES those packages. A package name is a value from the"
  , "program, so it fills a hole -- but the hole must become a pkgs.<name>"
  , "derivation, not a string. Use the pkg hole: <value:pkg> for one name, or"
  , "<value.tail:pkg> for the rest of a line (several names). Each token"
  , "becomes a bare pkgs.<name> in the realized list. Example, for a line"
  , "'install htop, ripgrep.' whose pattern's value is the tail 'htop, ripgrep':"
  , "  match install <pkg> => environment.systemPackages \"<value.tail:pkg>\""
  , "realizes to environment.systemPackages = [ pkgs.htop pkgs.ripgrep ];. Do"
  , "NOT write ${pkgs.<value>} (the path must be a literal name, not a hole; it"
  , "is rejected); do NOT quote the name into a string (\"<value>\" yields a"
  , "string, the wrong type for a package list). The name is validated as an"
  , "identifier (letters, digits, -, _, and dots), so a token that is not a"
  , "package name fails loud rather than building a bad path."
  , ""
  , "INSTANCE NAMES (<self>): some options are an attrsOf of submodules keyed by"
  , "an instance NAME you would otherwise invent -- services.restic.backups.<name>,"
  , "systemd.services.<name>. Do NOT bake a name read from the program into that"
  , "key. Use the reserved segment <self>: services.restic.backups.<self>.paths."
  , "It binds to the program's own instance name (its file basename) at realize"
  , "time, so ONE grammar serves many programs -- each its own instance -- and two"
  , "of them compose in one configuration without collision. Use <self> only where"
  , "the option schema has such a name placeholder; elsewhere it is rejected."
  , ""
  , "VALUE-KEYED OPTIONS (<capture>): when a program lists SEVERAL items of one"
  , "kind, each identified by its own value -- http routes by path, mounts by"
  , "mountpoint, virtual hosts by domain -- do NOT fold them into one fixed option"
  , "(they would collide) and do NOT invent a table item kind. Instead give the"
  , "PATTERN's emitted subject a hole for the identifier, so each item"
  , "crystallizes to its own subject: 'fact route.<path>.status \"<status>\"'"
  , "turns the line '- /hello => status 200' into subject route./hello.status."
  , "Then write ONE rule whose match subject carries the same <name> as a"
  , "CAPTURE and whose emit path repeats that <name> where the target option is"
  , "an attrsOf keyed by name:"
  , "  match fact route.<path>.status => environment.etc.<path>.text \"\\\"<value>\\\"\""
  , "The <name> may also be EMBEDDED in a segment when the key is composed,"
  , "e.g. environment.etc.http-routes-<path>.text -- every occurrence is filled."
  , "The capture binds each concrete key (/hello, /bye, ...) and fans the one"
  , "rule out to one distinct option slot per item, riding the target's native"
  , "attrsOf merge -- the per-item analogue of <self>. Like <self>, a <capture>"
  , "segment is accepted only where the option schema has a name placeholder"
  , "(an attrsOf), so key into a REAL attrsOf option (e.g. environment.etc);"
  , "elsewhere it is rejected. A capture reaches the emit PATH only; the value"
  , "still comes from <value>/<value.N>."
  , ""
  , "ARTIFACTS (only when the program needs a program BUILT FROM SOURCE, e.g. a"
  , "server you must write): a rule may emit an artifact group under the subject"
  , "root artifact.<name>: a builder and its arguments. The builder is a nixpkgs"
  , "builder path (a name, not code), e.g. rustPlatform.buildRustPackage or"
  , "buildGoModule. Example emits inside a rule:"
  , "  artifact.<name>.builder \"\\\"rustPlatform.buildRustPackage\\\"\" ;"
  , "  artifact.<name>.args.pname \"\\\"<name>\\\"\" ;"
  , "  artifact.<name>.args.version \"\\\"0.1.0\\\"\" ;"
  , "  artifact.<name>.args.src \"./artifacts/<name>\" ;"
  , "  artifact.<name>.args.cargoHash \"\\\"<sha256>\\\"\""
  , "The source tree is staged at ./artifacts/<name>, so args.src is that exact"
  , "path. Provide each source file with a source block (a heredoc); the path is"
  , "relative to the artifact's source root:"
  , "  <confidence> <id> source <name> <relpath> <<<lips"
  , "  ...verbatim file content..."
  , "  lips>>>"
  , "Reference the built artifact in an option with ${artifact.<name>}, e.g."
  , "  systemd.services.<name>.serviceConfig.ExecStart"
  , "    \"\\\"${artifact.<name>}/bin/<name>\\\"\""
  , "Prefer configuring a PREBUILT ${pkgs.<name>} package; mint an artifact only"
  , "when the program itself must be written. Keep source self-contained (no"
  , "external dependency fetch) unless the program clearly requires it."
  , ""
  , "DEMANDS (ids q1, q2, ...): what any program in this language must state,"
  , "as a subject plus the question to ask when it is missing."
  , ""
  , "EXPECTS (ids a1, a2, ...): the behavioral test. One per program value that"
  , "must reach the config. Form:"
  , "  <confidence> <id> expect <option.path> from <subject>[#<n>]"
  , "It asserts the value your patterns capture into <subject> (or its nth"
  , "whitespace token, #n, 1-based) appears at NixOS option <option.path> in"
  , "the realized module. Name the SAME option paths your rules assign. Emit"
  , "one expect for every distinct program value a rule carries into an option,"
  , "so realization and configurability are pinned. A VALUE-KEYED expect uses the"
  , "same <capture> on both sides (expect environment.etc.http-routes<path>.text"
  , "from route.<path>.status); it expands to one check per matching item, so"
  , "write ONE family expect, not one per route."
  , "NO EXPECT FOR A PACKAGE OR BUILD: an option you fill with a package or build"
  , "reference (a derivation -- environment.systemPackages, home.packages, a"
  , "runtimeInputs, an ExecStart holding ${artifact.<name>}) carries no checkable"
  , "value. The behavioral check runs with an empty pkgs, so it cannot read a"
  , "derivation; such an expect is rejected. Write NO expect for a derivation"
  , "option. The rule that emits it is the whole contract. Expects are for"
  , "options that hold a value from the program: a string, number, path, list of"
  , "strings, or record."
  , ""
  , "The kernel verifies: every line crystallizes, every decision is mapped,"
  , "every demand is met, the result parses as a NixOS module, and every"
  , "expect holds against the evaluated module."
  , ""
  , "Example input line:"
  , "  the bank drops csv files into inbox/."
  , "Example output lines:"
  , "  0.96 p1 pattern the bank drops csv files into <loc> => fact feed.source stated \"<loc>\""
  , "  0.95 r1 match fact feed.source => systemd.services.ingest.environment.INBOX \"\\\"<value>\\\"\""
  , "  0.9 q1 demand feed.source \"where do the files arrive?\""
  , "  0.95 a1 expect systemd.services.ingest.environment.INBOX from feed.source"
  ]

-- | Compose the effective mint prompt: the fixed domain-blind physics, plus
-- (when present) the owner's per-program DIRECTION. Direction is mechanism
-- taste that steers /how/ the engine is minted (which package, which shape),
-- never /what/ must hold; the appended rule tells the model to treat it as
-- preference only, so an obligation cannot enter through this channel.
-- Because direction rides inside the system prompt, it is pinned into the
-- @.generation@ record and the @genId@ hash for free, and @run@\/@check@ never
-- see it. A blank direction file is ignored (no channel, no drift).
promptWithDirection :: Maybe Text -> Target -> Text
promptWithDirection md t = case md of
  Just d | not (T.null (T.strip d)) ->
    systemPromptFor t <> T.unlines
      [ ""
      , "DIRECTION (the owner's taste for THIS program; optional, advisory)."
      , "The text below is PREFERENCE, not requirement. It says how to prefer"
      , "building the engine: mechanism choices only (which package, which"
      , "shape). It never states what must be true. Anything that MUST hold"
      , "lives in the program or its expects, so do not read an obligation out"
      , "of it, and never let it override a value the program states. When it"
      , "does not apply, ignore it."
      , "--- begin direction ---"
      , T.strip d
      , "--- end direction ---"
      ]
  _ -> systemPromptFor t

-- | Parse a model reply into item candidates, collecting per-line errors.
-- Single-item lines parse individually; a @source@ block spans multiple lines
-- (a heredoc between @<<<lips@ and a closing @lips>>>@) so generated source can
-- contain anything. Outside a block, blank\/comment\/fence lines are ignored.
parseEngineCandidates :: Text -> ([Text], [ItemCandidate])
parseEngineCandidates reply = go (T.lines reply) [] []
  where
    go [] errs cands = (reverse errs, reverse cands)
    go (l : ls) errs cands
      | Just prefix <- sourceHeader l =
          let (content, rest) = break (\x -> T.strip x == closeMarker) ls
           in case rest of
                [] -> go [] (("unterminated source block (missing " <> closeMarker <> "): " <> T.strip l) : errs) cands
                (_ : rest') -> case mkSource prefix (T.strip l) (T.intercalate "\n" content) of
                  Left e  -> go rest' (e : errs) cands
                  Right c -> go rest' errs (c : cands)
      | ignorable (T.strip l) = go ls errs cands
      | otherwise = case parseLine (T.strip l) of
          -- Echo the raw line the model wrote, so a refusal naming an item by
          -- id ("...(item p1)") also shows what p1 actually was. Without it the
          -- id is a dead reference: the reply is discarded on refusal.
          Left e  -> go ls ((e <> "\n      as written: " <> T.strip l) : errs) cands
          Right c -> go ls errs (c : cands)
    ignorable t = T.null t || "#" `T.isPrefixOf` t || "```" `T.isPrefixOf` t

closeMarker :: Text
closeMarker = "lips>>>"

-- | A source-block header ends with the open marker @<<<lips@; return the
-- prefix before it (@<confidence> <id> source <name> <relpath>@) to parse.
sourceHeader :: Text -> Maybe Text
sourceHeader l = T.stripSuffix "<<<lips" (T.stripEnd (T.strip l))

-- | Parse a source-block header prefix and pair it with its collected content.
mkSource :: Text -> Text -> Text -> Either Text ItemCandidate
mkSource prefix rawHeader content = do
  (confTok, r1) <- firstToken prefix ("empty source header: " <> rawHeader)
  (idTok, r2)   <- firstToken r1 ("no id in source header: " <> rawHeader)
  conf          <- parseConfidence confTok
  case T.words r2 of
    ["source", name, relpath] ->
      Right (ItemCandidate (ItemSource (SourceFile name relpath content)) (Confidence conf) rawHeader idTok)
    _ -> Left ("source header must be '<confidence> <id> source <name> <relpath> <<<lips': " <> rawHeader)

-- | Group parsed items into an engine (the @.lang@ artifact). Expects are not
-- part of the engine; see 'expectsOf'.
assemble :: [EngineItem] -> EngineData
assemble items =
  EngineData
    { edPatterns = [p | ItemPattern p <- items]
    , edRules    = [r | ItemRule r <- items]
    , edDemands  = [q | ItemDemand q <- items]
    }

-- | The minted behavioral contract (the @.expect@ artifact).
expectsOf :: [EngineItem] -> [Expect]
expectsOf items = [e | ItemExpect e <- items]

-- | The minted artifact source files (written beside the program).
sourcesOf :: [EngineItem] -> [SourceFile]
sourcesOf items = [s | ItemSource s <- items]

-- | The expects that name an option a rule fills with a package or artifact
-- reference (a derivation, not a program value). A containment check against
-- such an option is meaningless and cannot be evaluated under the check's
-- empty @pkgs@ stub, so naming one is a mint defect. Returned so @generate@
-- and @check@ reject it loud (deduce-or-fail) rather than crash the eval.
uncheckableExpects :: [MapRule] -> [Expect] -> [Expect]
uncheckableExpects rules = filter ((`elem` derivationPaths) . exPath)
  where
    derivationPaths =
      [ emPath em | r <- rules, em <- mrEmits r, valueRefsDerivation (emRhs em) ]

parseLine :: Text -> Either Text ItemCandidate
parseLine line = do
  (confTok, r1) <- firstToken line "empty item line"
  (idTok, body0) <- firstToken r1 ("no id after confidence: " <> line)
  conf <- parseConfidence confTok
  let body = T.strip body0
      -- Name the offending item by id, not by echoing the whole raw line
      -- (which may carry a multi-line escaped script and reads as noise).
      located = either (\e -> Left (e <> " (item " <> idTok <> ")")) Right
  -- Every item is keyword-led (pattern/match/demand/expect), so the item kind
  -- is read, never guessed. A pattern's template may then begin with any
  -- domain word ("match the invoice ...") without being mistaken for a rule;
  -- and an unrecognized body fails loud instead of silently becoming a
  -- malformed pattern.
  item <- case firstWord body of
    "pattern" -> ItemPattern <$> located (parsePatternBody idTok (afterKeyword body))
    "match"   -> ItemRule    <$> located (parseRuleBody   idTok body)
    "demand"  -> ItemDemand  <$> located (parseDemandBody idTok body)
    "expect"  -> ItemExpect  <$> located (parseExpectBody idTok body)
    "because" -> ItemNote    <$> located (parseNoteBody body)
    other     -> Left ("unknown item kind '" <> other
                        <> "' (want pattern|match|demand|expect|because) in: " <> line)
  Right (ItemCandidate item (Confidence conf) line idTok)
  where
    firstWord t = case T.words t of { (w : _) -> w; [] -> "" }
    afterKeyword = T.stripStart . T.drop (T.length ("pattern" :: Text)) . T.stripStart

-- | The reason inside a @because "<reason>"@ line: the single quoted string
-- after the keyword. Fails loud on a missing or unquoted reason.
parseNoteBody :: Text -> Either Text Text
parseNoteBody body =
  let r = T.stripStart (T.drop (T.length ("because" :: Text)) (T.stripStart body))
  in case T.stripPrefix "\"" (T.stripEnd r) >>= T.stripSuffix "\"" of
       Just inner -> Right inner
       Nothing    -> Left "because note must be a quoted reason: because \"...\""

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseConfidence :: Text -> Either Text Double
parseConfidence t = case TR.double t of
  Right (d, rest) | T.null rest, d >= 0, d <= 1 -> Right d
  _ -> Left ("bad confidence: " <> t)

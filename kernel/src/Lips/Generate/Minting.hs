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
import Lips.Kernel.Expect          (Expect (..), parseExpectBody)
import Lips.Kernel.Lang.Lang        (EngineData (..), parsePatternBody)
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
  deriving (Eq, Show)

-- | An item the model proposes, with the confidence it attaches to it.
-- @icLine@ retains the raw minted line verbatim (@<confidence> <id> <body>@)
-- so the deduce-or-fail refusal can echo exactly what the model emitted.
data ItemCandidate = ItemCandidate
  { icItem       :: EngineItem
  , icConfidence :: Confidence
  , icLine       :: Text
  }
  deriving (Eq, Show)

-- | The instruction given to the model. A versioned System artifact, stored in
-- the repository and reviewable (spec section 5, layer 3).
systemPrompt :: Text
systemPrompt = T.unlines
  [ "You crystallize a loose program into a lips ENGINE: patterns (the"
  , "language), rules (the mechanisms), and demands (completeness). You never"
  , "state the program's meaning; the kernel derives it deterministically by"
  , "applying your patterns to the program text."
  , ""
  , "Your situation: you act exactly once. Afterwards the human edits the"
  , "program and the kernel re-reads it with your patterns, deterministically,"
  , "without you. So: replace EVERY program value with a hole, so edits flow"
  , "without regeneration. The engine you mint is pure data; there is no"
  , "escape to code. Never guess: where the program underdetermines a choice"
  , "you cannot justify, give low confidence -- refusal beats invention. Never"
  , "work around the value grammar (no packing computation into strings); if"
  , "something is inexpressible, give it low confidence so the kernel is"
  , "extended instead."
  , ""
  , "Output ONLY lines of these forms, no prose, no code fences. Every line"
  , "names its kind with a leading keyword (pattern|match|demand|expect), so a"
  , "pattern template may itself begin with any word:"
  , ""
  , "  <confidence> <id> pattern <template> => <kind> <subject> <strength> \"<assertion>\""
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
  , "kind: one of"
  , "concept fact oblige forbid allow invariant view assume steer glue meta."
  , "strength: stated. subject: invent a dotted vocabulary for this problem"
  , "(e.g. backup.source). Every hole used in the subject or assertion MUST"
  , "appear in the template. Patterns must be orthogonal: no input line may"
  , "match two of them."
  , ""
  , "RULES (ids r1, r2, ...): map EVERY subject your patterns produce to"
  , "NixOS option assignments; any decision no rule maps fails the build."
  , "Every <rhs> is wrapped in ONE pair of surrounding double quotes, and"
  , "inside it is a VALUE, not a Nix expression -- the kernel rejects"
  , "computation. The value forms are the Nix value algebra minus computation:"
  , "a string \\\"...\\\", a list [ ... ], true, false, null, an integer, a float,"
  , "a path (/x or ./x), and a TYPED HOLE (below). A string rhs looks like"
  , "\"\\\"<value>\\\"\" and a list rhs looks like \"[ \\\"timers.target\\\" ]\"."
  , "Inside Nix strings only two things beyond literal text parse: the holes"
  , "<value> (the matched decision's assertion) / <value.N> (its Nth"
  , "whitespace-separated token, 1-based; use it when a pattern's assertion"
  , "joins several holes) and ${pkgs.<name>} package references. No functions,"
  , "no splitString, no other ${...}. Template holes bind single tokens;"
  , "punctuation like a trailing period stays outside the hole."
  , ""
  , "TYPED HOLES: a NixOS option is typed. For a NON-string option (a port, a"
  , "count, a size, a toggle, a path) do NOT quote the hole; use a typed hole"
  , "naming the type: <value:int>, <value:bool>, <value:float>, <value:path>"
  , "(or <value.N:int> for the Nth token). It emits a value of that type and"
  , "fails if the program token is not of that type. Quote a hole"
  , "(\"\\\"<value>\\\"\") only for genuinely string-typed options. So a port rule"
  , "looks like services.nginx.defaultHTTPListenPort \"<value:int>\". Realize"
  , "work as systemd services and timers or other NixOS options."
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
  , "so realization and configurability are pinned."
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
promptWithDirection :: Maybe Text -> Text
promptWithDirection md = case md of
  Just d | not (T.null (T.strip d)) ->
    systemPrompt <> T.unlines
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
  _ -> systemPrompt

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
          Left e  -> go ls (e : errs) cands
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
  (_idTok, r2)  <- firstToken r1 ("no id in source header: " <> rawHeader)
  conf          <- parseConfidence confTok
  case T.words r2 of
    ["source", name, relpath] ->
      Right (ItemCandidate (ItemSource (SourceFile name relpath content)) (Confidence conf) rawHeader)
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
    other     -> Left ("unknown item kind '" <> other
                        <> "' (want pattern|match|demand|expect) in: " <> line)
  Right (ItemCandidate item (Confidence conf) line)
  where
    located = either (\e -> Left (e <> " in: " <> line)) Right
    firstWord t = case T.words t of { (w : _) -> w; [] -> "" }
    afterKeyword = T.stripStart . T.drop (T.length ("pattern" :: Text)) . T.stripStart

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseConfidence :: Text -> Either Text Double
parseConfidence t = case TR.double t of
  Right (d, rest) | T.null rest, d >= 0, d <= 1 -> Right d
  _ -> Left ("bad confidence: " <> t)

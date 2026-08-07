{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell    #-}

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
  , Gap (..)
  , ItemCandidate (..)
  , parseEngineCandidates
  , assemble
  , expectsOf
  , sourcesOf
  , unnamedSources
  , reportOf
  , gapsOf
  , carriesEngineMeaning
  , uncheckableExpects
  , claimlessBakedSource
  , unplaceableClaims
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR
import           Data.FileEmbed  (embedStringFile)

import Lips.Kernel.Engine.Data      (DemandSpec, Emit (..), MapRule (..), MergeSpec,
                                     parseDemandBody, parseMergeBody, parseRuleBody)
import Lips.Kernel.Engine.Value     (valueRefsDerivation)
import Lips.Generate.Harness (Confidence (..))
import Lips.Kernel.Clause.Vocabulary (Contract (..), Vocabulary (..))
import Lips.Runtime                 (schemeVocabulary)
import Lips.Nix.Target       (Target (..))
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Claim           (Claim (..), ClaimPlace (..))
import Lips.Kernel.Expect          (Expect (..), isGroundExpect, parseExpectBody)
import Lips.Kernel.Lang.Store        (EngineData (..), parsePatternBody)
import Lips.Kernel.Lang.Pattern     (Pattern)

-- | A generated source file for an artifact: its artifact name, the relative
-- path within the artifact's source tree, and the verbatim content. Written to
-- @<language>/artifacts/<name>/<path>@ and staged at @./artifacts/<name>@ for
-- the build (artifacts plan, option 1).
data SourceFile = SourceFile
  { sfArtifact :: Text
  , sfPath     :: Text
  , sfContent  :: Text
  }
  deriving (Eq, Show)

-- | The capability the mint found missing: a slug naming it, and the body
-- naming the line it blocked plus a minimal repro. A gap is not an excuse, it
-- is a bug filed against the kernel in the model's own words (invariant 4 -- a
-- mint that needs gymnastics means the physics is short, and the fix belongs
-- in the kernel, never in the prompt or in hand-edited output).
data Gap = Gap
  { gapSlug :: Text
  , gapBody :: Text
  }
  deriving (Eq, Show)

-- | One minted item: an engine part (pattern, rule, demand), a behavioral
-- assertion (the @.expect@ contract), or a generated source file (an artifact's
-- source, a separate committed file, not part of the engine).
data EngineItem
  = ItemPattern Pattern
  | ItemRule MapRule
  | ItemDemand DemandSpec
  -- | How one list-typed option aggregates several lines' contributions (set or
  -- list); absent means set, the default reading.
  | ItemMerge MergeSpec
  | ItemExpect Expect
  | ItemSource SourceFile
  -- | A plain-language reason a low-confidence item is unsure. Carries no
  -- engine meaning (dropped by 'assemble'\/'expectsOf'\/'sourcesOf'); it only
  -- feeds the refusal message, keyed by the id it shares with its item.
  | ItemNote Text
  -- | The language explained in plain words, written to @<language>/README.md@
  -- so a human reviewing a mint reads prose instead of reverse-engineering the
  -- @.lang@. Exactly one per mint (the requirement is enforced by @generate@).
  | ItemReport Text
  -- | A kernel capability the mint lacked; surfaced on both the success and
  -- the refusal path, so a dead mint yields a work item instead of a shrug.
  | ItemGap Gap
  deriving (Eq, Show)

-- | Which items the confidence gate governs: those that carry engine meaning.
-- Prose channels (a because-note, the report, a gap) are exempt -- a gap is
-- honest at low confidence by nature, and no prose may refuse a mint whose
-- engine is sure. Stated here, once, so a future item kind cannot slip under
-- the gate by omission at the call site.
carriesEngineMeaning :: EngineItem -> Bool
carriesEngineMeaning i = case i of
  ItemNote _   -> False
  ItemReport _ -> False
  ItemGap _    -> False
  ItemPattern _ -> True
  ItemRule _    -> True
  ItemDemand _  -> True
  ItemMerge _   -> True
  ItemExpect _  -> True
  ItemSource _  -> True

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

-- | The instruction given to the model: a versioned System artifact, stored
-- in the repository as reviewable markdown (spec section 5, layer 3), not as
-- escaped Haskell string literals. Prose lives as prose so an example can be a
-- real fenced code block instead of a list of quoted lines: see Task 2's
-- parse guard, which requires every ```lips-engine block below to parse.
-- 'embedStringFile' resolves its path against GHC's working directory. Both
-- the direct `ghc -isrc test/Spec.hs` invocation (run from kernel/, where
-- ".." is the repo root) and the flake build (which copies kernel/ to a
-- build/ directory and assets/ as build's SIBLING, then cds into build/) see
-- ".." as the repo root, so the same relative path resolves in both --
-- documented once, here, rather than by two different paths in two places.
bodyDoc :: Text
bodyDoc = T.pack $(embedStringFile "../assets/mint/body.md")

nixosDoc :: Text
nixosDoc = T.pack $(embedStringFile "../assets/mint/nixos.md")

homeManagerDoc :: Text
homeManagerDoc = T.pack $(embedStringFile "../assets/mint/home-manager.md")

kubenixDoc :: Text
kubenixDoc = T.pack $(embedStringFile "../assets/mint/kubenix.md")

terranixDoc :: Text
terranixDoc = T.pack $(embedStringFile "../assets/mint/terranix.md")

directionDoc :: Text
directionDoc = T.pack $(embedStringFile "../assets/mint/direction.md")

-- | The mint prompt for a target world: a world-steering preamble naming the
-- option namespaces to emit into, then the world-neutral body. The preamble is
-- the ONLY thing that differs per world; the body's grammar (patterns, rules,
-- typed holes, artifacts, expects) is identical.
systemPromptFor :: Target -> Text
systemPromptFor Nixos       = nixosDoc <> "\n" <> promptBody
systemPromptFor HomeManager = homeManagerDoc <> "\n" <> promptBody
systemPromptFor Kubenix     = kubenixDoc <> "\n" <> promptBody
systemPromptFor Terranix    = terranixDoc <> "\n" <> promptBody

-- | The body with the contract set substituted in. The list is rendered from the
-- shipped vocabulary rather than written into the markdown, so the prompt cannot
-- drift from what the gate will actually accept: a contract added to
-- @assets\/runtime\/@ appears here, and one removed disappears.
promptBody :: Text
promptBody = T.replace "{{CONTRACTS}}" contractList bodyDoc

contractList :: Text
contractList = T.unlines
  [ "  " <> cName c <> " (" <> T.pack (show (cArity c)) <> ") -- " <> cDoc c
  | c <- vContracts schemeVocabulary ]

-- | Kept for back-compat and the pinned-artifact test: the NixOS prompt.
systemPrompt :: Text
systemPrompt = systemPromptFor Nixos

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
    -- directionDoc carries the fixed wrapper text with a single {{DIRECTION}}
    -- placeholder line; substituting it (rather than building the wrapper as
    -- a Haskell literal) keeps this wording in the same reviewable markdown
    -- asset as the rest of the prompt.
    systemPromptFor t <> "\n" <> T.replace "{{DIRECTION}}" (T.strip d) directionDoc
  _ -> systemPromptFor t

-- | Parse a model reply into item candidates, collecting per-line errors.
-- Single-item lines parse individually; a @source@ block spans multiple lines
-- (a heredoc between @<<<lips@ and a closing @lips>>>@) so generated source can
-- contain anything. Outside a block, blank\/comment\/fence lines are ignored.
parseEngineCandidates :: Text -> ([Text], [ItemCandidate])
parseEngineCandidates reply = go (T.lines reply) [] []
  where
    -- A reply carrying no item at all is a failure, never an empty engine: with
    -- prose ignored, a model that answered in sentences alone would otherwise
    -- materialize as a language that reads nothing and refuses every program.
    go [] [] [] = (["the reply carried no engine lines at all"], [])
    go [] errs cands = (reverse errs, reverse cands)
    go (l : ls) errs cands
      | Just prefix <- blockHeader l =
          let (content, rest) = break (\x -> T.strip x == closeMarker) ls
           in case rest of
                [] -> go [] (("unterminated source block (missing " <> closeMarker <> "): " <> T.strip l) : errs) cands
                (_ : rest') -> case mkBlock prefix (T.strip l) (T.intercalate "\n" content) of
                  Left e  -> go rest' (e : errs) cands
                  Right c -> go rest' errs (c : cands)
      | ignorable (T.strip l) = go ls errs cands
      | prose (T.strip l) = go ls errs cands
      | otherwise = case parseLine (T.strip l) of
          -- Echo the raw line the model wrote, so a refusal naming an item by
          -- id ("...(item p1)") also shows what p1 actually was. Without it the
          -- id is a dead reference: the reply is discarded on refusal.
          Left e  -> go ls ((e <> "\n      as written: " <> T.strip l) : errs) cands
          Right c -> go ls errs (c : cands)
    ignorable t = T.null t || "#" `T.isPrefixOf` t || "```" `T.isPrefixOf` t

-- | Is this line a sentence the model wrapped its answer in, rather than an item
-- it meant? The prompt says to write items and nothing else, and a model still
-- closes with "I now have a fully verified engine." -- which cost two mints of
-- twenty minutes each, refused for a line carrying no engine meaning at all.
--
-- The rule is stated, not sensed, and it is deliberately reluctant: prose is a
-- line whose first token is not a confidence AND whose first three tokens hold no
-- item keyword. So a MANGLED item (@O.9 p1 pattern ...@) still fails loud, because
-- @pattern@ is right there -- the reading that drops something the model meant is
-- the one this must never take. A sentence that merely mentions a keyword
-- ("I expect this to work") is refused too, which is the safe direction.
prose :: Text -> Bool
prose l = not (isConfidence firstTok) && not (any (`elem` keywords) (take 3 toks))
  where
    toks = T.words l
    firstTok = case toks of { (w : _) -> w; [] -> "" }
    isConfidence t = case TR.double t of
      Right (_, rest) -> T.null rest
      Left _          -> False
    keywords :: [Text]
    keywords = ["pattern", "match", "merge", "demand", "expect", "because"]

closeMarker :: Text
closeMarker = "lips>>>"

-- | A block header ends with the open marker @<<<lips@; return the prefix
-- before it (@<confidence> <id> <keyword> ...@) to parse.
blockHeader :: Text -> Maybe Text
blockHeader l = T.stripSuffix "<<<lips" (T.stripEnd (T.strip l))

-- | Parse a block header and pair it with its collected content. Three block
-- kinds share the heredoc, so anything verbatim (program source, prose, a bug
-- report) rides it without escaping: @source <name> <relpath>@, @report@,
-- @gap <slug>@.
mkBlock :: Text -> Text -> Text -> Either Text ItemCandidate
mkBlock prefix rawHeader content = do
  (confTok, r1) <- firstToken prefix ("empty block header: " <> rawHeader)
  (idTok, r2)   <- firstToken r1 ("no id in block header: " <> rawHeader)
  conf          <- parseConfidence confTok
  item <- case T.words r2 of
    ["source", name, relpath] -> Right (ItemSource (SourceFile name relpath content))
    ["report"]                -> Right (ItemReport content)
    ["gap", slug]             -> Right (ItemGap (Gap slug content))
    _ -> Left ("block header must be '<confidence> <id> source <name> <relpath>', \
               \'<confidence> <id> report' or '<confidence> <id> gap <slug>', \
               \followed by '<<<lips': " <> rawHeader)
  Right (ItemCandidate item (Confidence conf) rawHeader idTok)

-- | Group parsed items into an engine (the @.lang@ artifact). Expects are not
-- part of the engine; see 'expectsOf'.
assemble :: [EngineItem] -> EngineData
assemble items =
  EngineData
    { edPatterns = [p | ItemPattern p <- items]
    , edRules    = [r | ItemRule r <- items]
    , edDemands  = [q | ItemDemand q <- items]
    , edMerges   = [m | ItemMerge m <- items]
    }

-- | The minted behavioral contract (the @.expect@ artifact).
expectsOf :: [EngineItem] -> [Expect]
expectsOf items = [e | ItemExpect e <- items]

-- | The minted artifact source files (written into the language folder's
-- @artifacts/@, committed and reviewable).
sourcesOf :: [EngineItem] -> [SourceFile]
sourcesOf items = [s | ItemSource s <- items]

-- | The source blocks whose artifact name still carries a @\<hole\>@ token. A
-- source tree is written to disk under that name, so a block minted for
-- @artifact.\<self\>@ creates a directory literally called @\<self\>@ and the
-- module's @src = ./artifacts/hello@ then points at nothing -- a defect two live
-- mints produced in a row. The remedy is a concrete name: the tree is baked for
-- the program as it stands (renaming the thing in the program is a regeneration,
-- which is what the staged-source gate says), while the RULE keeps the hole so
-- the same language serves the next instance.
unnamedSources :: [SourceFile] -> [SourceFile]
unnamedSources = filter (not . null . nameTokens . sfArtifact)

-- | The language explained in the mint's own words (the @README.md@ body).
-- The first report wins; @generate@ refuses a mint that has none.
reportOf :: [EngineItem] -> Maybe Text
reportOf items = case [r | ItemReport r <- items] of
  (r : _) -> Just r
  []      -> Nothing

-- | The kernel capabilities this mint found missing.
gapsOf :: [EngineItem] -> [Gap]
gapsOf items = [g | ItemGap g <- items]

-- | The expects that name an option a rule fills with a package or artifact
-- reference (a derivation, not a program value). A containment check against
-- such an option is meaningless and cannot be evaluated under the check's
-- empty @pkgs@ stub, so naming one is a mint defect. Returned so @generate@
-- and @check@ reject it loud (deduce-or-fail) rather than crash the eval.
uncheckableExpects :: [MapRule] -> [Expect] -> [Expect]
uncheckableExpects rules = filter uncheckable
  where
    -- An artifact arg or a claim section needs no eval at all (its value is a
    -- literal in the ground base, judged by
    -- 'Lips.Kernel.Expect.checkArtifactValues'), so a derivation-referencing one
    -- -- a claim command naming ${artifact.<name>}, say -- is checkable, not
    -- uncheckable.
    uncheckable e = not (isGroundExpect e) && exPath e `elem` derivationPaths
    derivationPaths =
      [ emPath em | r <- rules, em <- mrEmits r, valueRefsDerivation (emRhs em) ]

-- | Does this mint BAKE source without stating a single observable?
--
-- Where behaviour lives in minted code, the module text says nothing about what
-- that code does: every gate lips has reads the map, and the map is silent. So
-- without one experiment, nothing holds the implementation -- or any future
-- re-mint -- to the author's own words, and a reworded sentence or a rewritten
-- algorithm passes unseen.
--
-- A pure-configuration mint is deliberately unaffected: its behaviour IS its
-- option assignments, which the committed contract already pins.
--
-- WARNED, not refused (@generate@ says it in the report it prints): the witness
-- can only come from the author's own example, so a refusal here throws away an
-- engine that is otherwise correct and leaves the author with nothing to state
-- the example against. The prompt asks the mint for a claim and tells it to file
-- a gap where the program offers no example.
claimlessBakedSource :: [SourceFile] -> [Claim] -> Bool
claimlessBakedSource sources claims = not (null sources) && null claims

-- | The claims a world cannot observe, by id. A machine claim boots the realized
-- module, which only the NixOS world has; elsewhere an observable must be stated
-- over the program's own artifacts, which needs no machine.
--
-- Refused at the gate rather than at some later check, so an engine whose claims
-- could never run is never written.
unplaceableClaims :: Target -> [Claim] -> [Text]
unplaceableClaims Nixos _  = []
unplaceableClaims _     cs = [ clId c | c <- cs, clPlace c == PlaceMachine ]

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
    "merge"   -> ItemMerge   <$> located (parseMergeBody  idTok body)
    "expect"  -> ItemExpect  <$> located (parseExpectBody idTok body)
    "because" -> ItemNote    <$> located (parseNoteBody body)
    other     -> Left ("unknown item kind '" <> other
                        <> "' (want pattern|match|merge|demand|expect|because) in: "
                        <> line)
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

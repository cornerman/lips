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
  ( systemPromptFor
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
  , appendOnlyViolations
  , mergeGrammar
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
import Lips.World            (World (..))
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Decision     (Decision (..), DecisionId (..), Provenance (..), SourceLoc (..))
import Lips.Kernel.Reader       (readDecision)
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
  -- | Which world this item is for, written @\@\<world\>@ after the id.
  -- 'Nothing' is SHARED: a pattern, a source block, the report, a gap and a
  -- because-note belong to the language, not to one of its worlds.
  , icWorld      :: Maybe Text
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

directionDoc :: Text
directionDoc = T.pack $(embedStringFile "../assets/mint/direction.md")

-- | The wrapper around an inherited grammar, carried in the same reviewable
-- markdown as the rest of the prompt (the 'directionDoc' precedent): a section
-- that is APPENDED when there is one, rather than a placeholder that has to be
-- emptied on a first mint.
grammarDoc :: Text
grammarDoc = T.pack $(embedStringFile "../assets/mint/grammar.md")

-- | The wrapper telling a mint that other worlds follow it, so the grammar it
-- writes is shared and must stay neutral. Appended only when a world actually
-- follows, by the same rule as the two docs above.
sharedDoc :: Text
sharedDoc = T.pack $(embedStringFile "../assets/mint/shared.md")

-- | The mint prompt for a target world: a world-steering preamble naming the
-- option namespaces to emit into, then the world-neutral body. The preamble is
-- the ONLY thing that differs per world; the body's grammar (patterns, rules,
-- typed holes, artifacts, expects) is identical.
-- The preamble comes from the world's own file, so the world-steering half of
-- the prompt is data a house world supplies exactly as a shipped one does.
systemPromptFor :: World -> Text
systemPromptFor w = wPreamble w <> "\n" <> promptBody

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

-- | Compose the effective mint prompt: the fixed domain-blind physics, plus
-- (when present) the owner's per-program DIRECTION. Direction is mechanism
-- taste that steers /how/ the engine is minted (which package, which shape),
-- never /what/ must hold; the appended rule tells the model to treat it as
-- preference only, so an obligation cannot enter through this channel.
-- Because direction rides inside the system prompt, it is pinned into the
-- @.generation@ record and the @genId@ hash for free, and @run@\/@check@ never
-- see it. A blank direction file is ignored (no channel, no drift).
-- The inherited GRAMMAR rides in the same prompt, before the direction: a
-- second world's mint may only append to what the first one wrote, so it has to
-- see it. Absent on a first mint, and then the section is not there at all.
--
-- @later@ names the worlds this run mints AFTER this one. A mint that has
-- successors is writing a grammar it does not own alone, and must be told:
-- without that it bakes its own world's value syntax into the shared patterns
-- (systemd calendar syntax, measured on the first live two-world mint), and the
-- next world -- which cannot convert it, the value grammar having no
-- computation -- can only refuse.
promptWithDirection :: Maybe Text -> Maybe Text -> [Text] -> World -> Text
promptWithDirection md mg later w =
  systemPromptFor w <> section (Just (T.intercalate ", " later)) sharedDoc "{{WORLDS}}"
                    <> section mg grammarDoc "{{GRAMMAR}}"
                    <> section md directionDoc "{{DIRECTION}}"
  where
    -- Each doc carries the fixed wrapper text with a single placeholder line;
    -- substituting it (rather than building the wrapper as a Haskell literal)
    -- keeps this wording in the same reviewable markdown asset as the rest of
    -- the prompt.
    section (Just t) doc hole | not (T.null (T.strip t)) =
      "\n" <> T.replace hole (T.strip t) doc
    section _ _ _ = ""

-- | What a later world's mint did to the grammar an earlier one wrote: the ids
-- of pattern lines it changed or dropped. Empty means it only appended, which
-- is the only move a later world may make.
--
-- Compared decision by decision with the PROVENANCE set aside, because the
-- provenance is not the mint's to keep: a reply carries none, and lips stamps
-- every line it renders with the origin of the run that rendered it, so an
-- inherited pattern coming back out of world B's mint carries B's stamp (or a
-- draft's @\@lang:0@ before a record exists). What must not move is what the
-- pattern SAYS. The written grammar keeps world A's bytes anyway (see
-- 'mergeGrammar'), so A's stamps still re-hash against A's own record.
--
-- Parsed rather than string-trimmed: the provenance token is the one field to
-- ignore, and the reader is what knows where it ends.
--
-- Being this strict about the statement is safe: every committed program
-- already crystallizes under the old grammar, and two patterns reading one line
-- is already refused as an overlap, so a new pattern can only claim a line of a
-- program added in the SAME run -- adding one cannot break a world that already
-- holds.
appendOnlyViolations :: Text -> Text -> [Text]
appendOnlyViolations old new =
  [ i | (i, d) <- byId old, lookup i (byId new) /= Just d ]
  where
    byId t = [ (i, d { dProv = anywhere })
             | l <- T.lines t, Right d <- [readDecision (T.strip l)]
             , let DecisionId i = dId d ]
    -- One provenance for both sides, so the comparison cannot see the field.
    anywhere = FromSource (SourceLoc "" 0)

-- | The grammar to WRITE when a later world appends to an inherited one: every
-- committed line verbatim, then the ids this mint added. Verbatim because an
-- inherited line belongs to the mint that wrote it -- re-rendering would stamp
-- it with this run's record, churning a file no world asked to change and
-- losing the honest origin of the pattern.
mergeGrammar :: Text -> Text -> Text
mergeGrammar old new = old <> T.unlines
  [ l | l <- T.lines new, idOf l `notElem` map idOf (T.lines old) ]
  where idOf l = take 1 (T.words l)


-- | Parse a model reply into item candidates, collecting per-line errors.
-- Single-item lines parse individually; a @source@ block spans multiple lines
-- (a heredoc between @<<<lips@ and a closing @lips>>>@) so generated source can
-- contain anything. Outside a block, blank\/comment\/fence lines are ignored.
-- The world list is what the run is minting. It decides two things a line
-- cannot decide alone: whether a tag names a world at all, and whether a tag may
-- be left off (with one world there is nothing to disambiguate, so a reply
-- written for a single world is byte-identical to what mints wrote before tags
-- existed).
parseEngineCandidates :: [Text] -> Text -> ([Text], [ItemCandidate])
parseEngineCandidates worlds reply = go (T.lines reply) [] []
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
      | otherwise = case parseLine worlds (T.strip l) of
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
  -- A block is always shared: source, report and gap are the language's.
  Right (ItemCandidate item (Confidence conf) rawHeader idTok Nothing)

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

-- | The claims a world cannot observe, by id: those whose PLACE the world does
-- not host. A machine claim boots the realized module, which only a world with
-- a machine offers; elsewhere an observable must be stated over the program's
-- own artifacts, which needs no machine.
--
-- The hosted places come from the world file's @claims:@ header, so which
-- claims a world admits is data -- lips never asks which world this is.
--
-- Refused at the gate rather than at some later check, so an engine whose claims
-- could never run is never written.
unplaceableClaims :: [Text] -> [Claim] -> [Text]
unplaceableClaims hosted cs =
  [ clId c | c <- cs, placeSlug (clPlace c) `notElem` hosted ]

-- | What a world file calls each place a claim can be observed in.
placeSlug :: ClaimPlace -> Text
placeSlug PlaceMachine    = "machine"
placeSlug PlaceDerivation = "sandbox"

parseLine :: [Text] -> Text -> Either Text ItemCandidate
parseLine worlds line = do
  (confTok, r1) <- firstToken line "empty item line"
  (idTok, r2) <- firstToken r1 ("no id after confidence: " <> line)
  conf <- parseConfidence confTok
  -- The tag sits between the id and the kind, marked by @ so it can never be
  -- mistaken for a keyword or a template word.
  (tag, body0) <- case firstToken r2 "" of
    Right (t, rest) | Just w <- T.stripPrefix "@" t -> Right (Just w, rest)
    _                                               -> Right (Nothing, r2)
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
  -- Deduce-or-fail on the tag, once the kind is known: a shared item may not
  -- claim a world, a world-bound item may not name one this mint does not
  -- write, and it may only be left untagged where there is a single world to
  -- mean.
  world <- case (tag, shared item) of
    (Just w, True)  -> Left ("item " <> idTok <> " is tagged @" <> w
                              <> ", but a " <> kindWord item <> " is shared by every world")
    (Just w, False) | w `notElem` worlds ->
      Left ("item " <> idTok <> " is tagged @" <> w
              <> ", which is not a world this mint writes for ("
              <> T.intercalate ", " worlds <> ")")
    (Just w, False) -> Right (Just w)
    (Nothing, True) -> Right Nothing
    (Nothing, False) -> case worlds of
      [w] -> Right (Just w)
      _   -> Left ("item " <> idTok <> " names no world, and this mint writes for "
                     <> T.intercalate ", " worlds
                     <> " (tag it @<world> right after the id)")
  Right (ItemCandidate item (Confidence conf) line idTok world)
  where
    firstWord t = case T.words t of { (w : _) -> w; [] -> "" }
    -- A shared item is the language's own: how a program is READ, the source it
    -- bakes, and the prose about it. Everything else names an option path, and
    -- an option path exists only inside one world's namespace.
    shared it = case it of
      ItemPattern _ -> True
      ItemNote _    -> True
      ItemReport _  -> True
      ItemGap _     -> True
      ItemSource _  -> True
      _             -> False
    kindWord it = case it of
      ItemPattern _ -> "pattern"
      ItemNote _    -> "because-note"
      ItemReport _  -> "report"
      ItemGap _     -> "gap"
      ItemSource _  -> "source block"
      ItemRule _    -> "rule"
      ItemDemand _  -> "demand"
      ItemMerge _   -> "merge"
      ItemExpect _  -> "expect"
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

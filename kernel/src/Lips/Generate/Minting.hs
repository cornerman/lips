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
  , itemsFor
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
  , replyLinesOf
  , mergeReply
  , touchedIds
  , mergeGrammar
  , sharedFileViolations
  ) where

import           Data.Maybe      (isJust, mapMaybe)
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR
import           Data.FileEmbed  (embedStringFile)
import qualified System.FilePath as FP

import Lips.Kernel.Engine.Data      (DemandSpec, Emit (..), IgnoreSpec, MapRule (..), MergeSpec,
                                     parseDemandBody, parseIgnoreBody, parseMergeBody, parseRuleBody)
import Lips.Kernel.Engine.Value     (valueRefsDerivation)
import Lips.Generate.Harness (Confidence (..))
import Lips.Kernel.Clause.Vocabulary (Contract (..), Vocabulary (..))
import Lips.Runtime                 (schemeVocabulary)
import Lips.World            (World (..))
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Decision     (Assertion (..), Decision (..), DecisionId (..), Provenance (..), SourceLoc (..), Subject (..))
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
  -- | A fact THIS world cannot place, declared with the reason rather than left
  -- silent. World-bound like a rule: it is a statement about one lowering.
  | ItemIgnore IgnoreSpec
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
  ItemIgnore _  -> True
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

-- | The wrapper around a committed ENGINE a growth mint patches: what the ids
-- mean, and that a line it does not mention stays. Its own asset rather than a
-- paragraph of 'bodyDoc', because it is present only when something is inherited
-- -- a first mint must not read about patching an engine that does not exist.
patchDoc :: Text
patchDoc = T.pack $(embedStringFile "../assets/mint/patch.md")

-- | The rules that only apply when one mint writes for SEVERAL worlds: the
-- per-item world tag, the neutrality a shared fact needs, and demanding rather
-- than inventing what one world needs and the program does not state. Appended
-- only when there is more than one world, by the same rule as the two docs
-- above.
worldsDoc :: Text
worldsDoc = T.pack $(embedStringFile "../assets/mint/worlds.md")

-- | The mint prompt for the worlds one call writes for: each world's steering
-- preamble naming the option namespaces to emit into, then the world-neutral
-- body, then (with several worlds) the rules for writing across them. A
-- preamble comes from the world's own file, so the world-steering half of the
-- prompt is data a house world supplies exactly as a shipped one does.
--
-- ONE world keeps exactly the old shape, so every committed engine's prompt is
-- unchanged. SEVERAL worlds are each fenced into their own section, because a
-- preamble is absolute prose about one namespace ("never emit a NixOS option
-- here") and two of them read as one text contradict each other; the fence and
-- the sentence above it are what scope each to itself. Measured 2026-08-09: with
-- the fence, opus-5 wrote nixos and kubenix rules with no leakage either way.
systemPromptFor :: [World] -> Text
systemPromptFor [w] = wPreamble w <> "\n" <> promptBody
systemPromptFor ws  = scopedPreambles ws <> "\n" <> promptBody
                        <> "\n" <> T.replace "{{WORLDS}}" (T.intercalate ", " (map wName ws)) worldsDoc

-- | Every world's preamble, each fenced into its own section and introduced by
-- the sentence that scopes it.
scopedPreambles :: [World] -> Text
scopedPreambles ws = T.unlines $
  [ "YOU MINT ONE LANGUAGE FOR SEVERAL WORLDS: " <> T.intercalate ", " (map wName ws) <> "."
  , ""
  , "The PATTERNS you write are shared: one reading of the program, the same in"
  , "every world. The RULES, DEMANDS and EXPECTS are per world, and each world"
  , "has its own section below."
  , ""
  , "Each section is ABSOLUTE INSIDE ITSELF AND NOWHERE ELSE. While you write the"
  , "items for one world, obey that world's section and ignore every other"
  , "section. A prohibition in one section says nothing about any other world."
  , "" ]
  ++ concat [ [ "--- world " <> wName w <> " ---"
              , T.strip (wPreamble w)
              , "--- end world " <> wName w <> " ---", "" ] | w <- ws ]

-- | The body with the contract set substituted in. The list is rendered from the
-- shipped vocabulary rather than written into the markdown, so the prompt cannot
-- drift from what the gate will actually accept: a contract added to
-- @assets\/runtime\/@ appears here, and one removed disappears.
promptBody :: Text
promptBody = T.replace "{{PROCEDURES}}" procedureList
               (T.replace "{{CONTRACTS}}" contractList bodyDoc)

-- | The base notation, rendered from the same asset for the same reason: a model
-- that cannot see a name rediscovers it badly. Wrapped at a readable width and
-- indented, so it reads as a list rather than a wall.
procedureList :: Text
procedureList = T.unlines
  [ "  " <> T.unwords row | row <- chunk 10 (vProcedures schemeVocabulary) ]
  where
    chunk _ [] = []
    chunk n xs = take n xs : chunk n (drop n xs)

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
-- The inherited ENGINE (the growth mint's basis, patterns AND rules) rides
-- between them: it is what the direction steers, and a mint that sees it answers
-- a patch instead of a whole engine.
--
promptWithDirection :: Maybe Text -> Maybe Text -> Maybe Text -> [World] -> Text
promptWithDirection md mg me ws =
  systemPromptFor ws <> section mg grammarDoc "{{GRAMMAR}}"
                     <> section me patchDoc "{{ENGINE}}"
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

-- | What a mint may NOT change when it does not own the language level: the
-- grammar the other worlds' rules were lowered from, and the source tree they
-- all build. Returns one line per violation, empty when the mint only appends.
--
-- The grammar may be APPENDED to (a pattern for a line no world could read
-- before cannot break a world that already holds, since every committed program
-- already crystallizes and an overlap is refused). The source tree may not
-- change at all: it is one program's source, shared by the worlds that run it,
-- and a world minted later replacing it would silently delete the code an
-- earlier world's rules reference.
sharedFileViolations :: Text -> Text -> [(FilePath, Text)] -> [SourceFile] -> [Text]
sharedFileViolations old new committed minted =
  [ "pattern " <> i <> " changed, and other worlds are built on it"
  | i <- appendOnlyViolations old new ]
  ++ [ "artifacts/" <> T.pack p <> " would be rewritten"
     | (p, t) <- committed, lookup p mintedTree /= Just t ]
  ++ [ "artifacts/" <> T.pack p <> " would be added"
     | (p, _) <- mintedTree, p `notElem` map fst committed ]
  where
    mintedTree = [ (T.unpack (sfArtifact sf) FP.</> T.unpack (sfPath sf), sfContent sf)
                 | sf <- minted ]

-- | The grammar to WRITE when a later world appends to an inherited one: every
-- committed line verbatim, then the ids this mint added. Verbatim because an
-- inherited line belongs to the mint that wrote it -- re-rendering would stamp
-- it with this run's record, churning a file no world asked to change and
-- losing the honest origin of the pattern.
mergeGrammar :: Text -> Text -> Text
mergeGrammar old new = old <> T.unlines
  [ l | l <- T.lines new, idOf l `notElem` map idOf (T.lines old) ]
  where idOf l = take 1 (T.words l)

-- | A committed engine, rendered back into the line format a mint ANSWERS in.
--
-- This is what makes a patch cheap without inventing a second grammar: an engine
-- line carries the reply line's own text as its assertion, so handing the model
-- (and 'mergeReply') a committed engine costs a re-quote, not a translation.
-- Confidence 1.0, because a committed line has already passed every gate. The
-- world tag is added only when the run writes for several worlds, so a
-- single-world reply stays byte-identical to what mints wrote before tags
-- existed; patterns are shared, so their lines are never tagged.
replyLinesOf :: Maybe Text -> Text -> Text
replyLinesOf tag src = T.unlines
  [ T.unwords ([ "1.0", i ] ++ maybe [] (\w -> ["@" <> w]) tag ++ keyword s ++ [ a ])
  | l <- T.lines src
  , Right d <- [readDecision (T.strip l)]
  , let DecisionId i = dId d
  , let Assertion a = dAssertion d
  , let Subject s = dSubject d ]
  where
    -- One asymmetry of the stored form has to be undone here: a PATTERN's stored
    -- assertion is its template body, because the reading side consumed the
    -- leading @pattern@ keyword, while a rule, a demand and an ignore each keep
    -- theirs (@match@, @demand@, @ignore@). Restored from the subject, which is
    -- what the store keys the kind by; without it the inherited pattern comes
    -- back as a line no reply parser accepts, and every program stops
    -- crystallizing.
    keyword ("lang" : "pattern" : _) = ["pattern"]
    keyword _                        = []

-- | The engine a PATCH means: every inherited line, with the ones the patch
-- restates dropped, then the patch itself. An id the patch does not mention is
-- inherited verbatim, which is the whole point -- the model pays for what it
-- changes, not for what it keeps.
--
-- Merged BEFORE the reply is parsed, so every gate, every render and every write
-- below sees a complete engine and needs no notion of a patch at all.
--
-- Addressed in UNITS, not in lines, because the reply format is not a list of
-- lines: a heredoc block's body is verbatim text that may hold anything,
-- id-shaped words included. Reading it as lines made this merge disagree with
-- 'parseEngineCandidates', which reads the same reply, and the disagreement lost
-- bytes both ways: a report sentence "Pattern p1 reads the interval" deleted the
-- committed p1, and replacing a report left its old body and terminator behind
-- as orphans.
mergeReply :: Text -> Text -> Text
mergeReply inheritedLines patch = T.unlines
  (concat kept ++ T.lines patch)
  where
    touched = touchedIds patch
    kept = [ u | u <- replyUnits inheritedLines
               , maybe True (`notElem` touched) (unitId u) ]

-- | The ids a patch mentions, one per unit it carries.
touchedIds :: Text -> [Text]
touchedIds = mapMaybe unitId . replyUnits

-- | A reply, split into the units a patch can address: one item LINE, or one
-- BLOCK (its heredoc header, its body and its terminator). An unterminated block
-- runs to the end, which is the reading that keeps the merge from cutting a
-- block in half; the parser refuses it afterwards, naming the missing marker.
replyUnits :: Text -> [[Text]]
replyUnits = go . T.lines
  where
    go [] = []
    go (l : ls)
      | isJust (blockHeader l) =
          let (body, rest) = break (\x -> T.strip x == closeMarker) ls
           in case rest of
                []              -> [l : body]
                (marker : more)  -> (l : body ++ [marker]) : go more
      | otherwise = [l] : go ls

-- | Which id a unit carries, if any: token 2 of its FIRST line, and only where
-- token 1 is a confidence. A line that does not open with a confidence is prose
-- or a stray marker, so it names no id and no patch can address it -- which is
-- what keeps a body word shaped like an id from deleting a real line.
unitId :: [Text] -> Maybe Text
unitId (l : _) = case T.words l of
  (c : i : _) | isConfidenceTok c -> Just i
  _                               -> Nothing
unitId []      = Nothing

-- | Does this token read as a bare number? Token 1 of every item line is its
-- confidence, which is how an item is told from prose here and in 'prose'.
isConfidenceTok :: Text -> Bool
isConfidenceTok t = case TR.double t of
  Right (_, rest) -> T.null rest
  Left _          -> False


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
prose l = not (isConfidenceTok firstTok) && not (any (`elem` keywords) (take 3 toks))
  where
    toks = T.words l
    firstTok = case toks of { (w : _) -> w; [] -> "" }
    keywords :: [Text]
    keywords = ["pattern", "match", "merge", "demand", "ignore", "expect", "because"]

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

-- | The items one world's engine is built from: every SHARED item, plus the
-- items tagged for that world. The grammar is the shared half, so two worlds'
-- engines differ only below it.
--
-- Source blocks are deliberately not filtered here: 'sourcesOf' takes every
-- item, because a baked source tree is one program's source, shared by the
-- worlds that run it, and only a mint that saw every world may write it.
itemsFor :: Text -> [ItemCandidate] -> [EngineItem]
itemsFor world = map icItem . filter (\c -> icWorld c `elem` [Nothing, Just world])

-- | Group parsed items into an engine (the @.lang@ artifact). Expects are not
-- part of the engine; see 'expectsOf'.
assemble :: [EngineItem] -> EngineData
assemble items =
  EngineData
    { edPatterns = [p | ItemPattern p <- items]
    , edRules    = [r | ItemRule r <- items]
    , edDemands  = [q | ItemDemand q <- items]
    , edMerges   = [m | ItemMerge m <- items]
    , edIgnores  = [i | ItemIgnore i <- items]
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
-- REFUSED by @generate@ (since 2026-08-04): deducing the observable from the
-- program's own words is the mint's job, and `logscan` spent months as the
-- counter-example, baked source with every gate green. The prompt asks the mint
-- for a claim and tells it to file a gap where the program offers no example.
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
    "ignore"  -> ItemIgnore  <$> located (parseIgnoreBody idTok body)
    "expect"  -> ItemExpect  <$> located (parseExpectBody idTok body)
    "because" -> ItemNote    <$> located (parseNoteBody body)
    other     -> Left ("unknown item kind '" <> other
                        <> "' (want pattern|match|merge|demand|ignore|expect|because) in: "
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
      ItemIgnore _  -> "ignore"
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

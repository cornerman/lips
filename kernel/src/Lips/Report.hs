{-# LANGUAGE OverloadedStrings #-}

-- | Every message lips prints when something does not hold, in one place.
--
-- Pure by construction: each function turns a kernel or mint verdict into the
-- words a reader needs, and the CLI decides when to print or die. That split is
-- what lets the wording be read and reviewed without following the control flow
-- that produced it, and it is why one defect has ONE voice however many verbs
-- reach it.
--
-- The house shape is 'Lips.Cli.Output.report': what happened, the details, then
-- a single action line beginning with an arrow. A report naming no remedy costs
-- the reader a whole round, so a missing action line is a defect here rather
-- than a matter of taste.
module Lips.Report
  ( Failure (..)
  , failureReport
  , printFail
  , renderDiagnosis
  , plural
  , unanswerableReport
  , unreadable
  , nixMissing
  , nixEvalFailed
  , gapArtifact
  , refusalReport
  , uncheckableReport
  , demandGenerateFail
  , validationReport
  , renderParseError
  , niceSubject
  , loc
  ) where

import           Data.Text          (Text)
import qualified Data.Text          as T

import           Lips.Cli.Output               (report, reportHead, tshow)
import           Lips.Generate.Harness         (Confidence (..))
import           Lips.Generate.Minting         (Gap (..), ItemCandidate (..))
import           Lips.Generate.Record          (genId)
import           Lips.Kernel.Base              (Conflict (..))
import           Lips.Kernel.Decision
import           Lips.Kernel.Engine.Answerable (UnanswerableDemand)
import           Lips.Kernel.Engine.Gate       (unanswerableProblem)
import           Lips.Kernel.Expect            (Expect (..))
import           Lips.Kernel.Lang.Crystallize  (CrystError (..), LineOutcome (..))
import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..))
import           Lips.Kernel.Reader            (ParseError (..))
import           Lips.Kernel.Refine            (RefineError (..))
import           Lips.Kernel.Run               (RunError (..))

-- | Render the authoring diagnosis: a coverage headline, one line per program
-- line (matched to which pattern and subject, or unread, or ambiguous), then
-- the open questions. Pure view over 'diagnose'; a future editor paints the
-- same outcomes as squiggles.
renderDiagnosis :: FilePath -> Diagnosis -> Text
renderDiagnosis file d =
  T.intercalate "\n" (headline : map row (diagLines d)
                        ++ headBlock ++ inertBlock ++ restatedBlock ++ droppedBlock
                        ++ decorativeBlock ++ unfitBlock ++ openBlock)
  where
    headline = T.pack file <> ": " <> tshow (diagMatched d) <> " of "
                 <> tshow (diagTotal d) <> " lines crystallize."
    row (Matched n _ pid par decs) =
      "  line " <> tshow n <> "  ok        " <> pid <> "  "
        <> T.intercalate ", " (map (subjectPath . dSubject) decs)
        <> maybe "" (\b -> "  in the block at line " <> tshow b) par
    row (Unmatched n t) =
      "  line " <> tshow n <> "  no match  \"" <> t <> "\""
    row (Ambiguous n _ ids) =
      "  line " <> tshow n <> "  ambiguous " <> T.intercalate "," ids
    row (Orphan n _ qs) =
      "  line " <> tshow n <> "  no block  needs a line above it matching "
        <> T.intercalate " or " qs
    row (Illegible n _ why) =
      "  line " <> tshow n <> "  unreadable  " <> why
    -- A line the language reads and then drops realizes nothing, so editing it
    -- changes nothing. Naming it is the point: a heading is legitimately
    -- decorative, but so is a line the mint quietly declined to honor, and only
    -- the author can tell which this is.
    -- A line that opens a block realizes nothing itself, but the lines inside it
    -- carry its words, so it is not decoration and must not be listed as such.
    headBlock
      | null (diagHeads d) = []
      | otherwise =
          "" : ("opens a block (" <> tshow (length (diagHeads d))
                  <> ") -- realizes nothing itself; the lines inside it do:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  (" <> tshow k
                    <> (if k == 1 then " line" else " lines") <> " inside)"
                | (n, t, k) <- diagHeads d ]
    inertBlock
      | null (diagInert d) = []
      | otherwise =
          "" : ("decorative, realizing nothing (" <> tshow (length (diagInert d))
                  <> ") -- editing these changes no output:")
              : ["  line " <> tshow n <> "  \"" <> t <> "\"" | (n, t) <- diagInert d]
    -- A line whose fact an earlier line already stated: it merges away, so it
    -- produces nothing of its own and editing it changes no output. Two
    -- statements of one fact are one fact, so this is reported, never refused.
    restatedBlock
      | null (diagRestated d) = []
      | otherwise =
          "" : ("already stated (" <> tshow (length (diagRestated d))
                  <> ") -- these lines add nothing to an earlier line:")
              : [ "  line " <> tshow n <> "  repeats line " <> tshow earlier
                    <> "  (" <> subj <> ")"
                | (n, earlier, subj) <- diagRestated d ]
    -- A word the language binds and no rule carries: the line looks
    -- load-bearing and is not, so editing that word changes nothing. The gate
    -- refuses such an engine now; this names it for engines committed earlier.
    droppedBlock
      | null (diagDropped d) = []
      | otherwise =
          "" : ("read and discarded (" <> tshow (length (diagDropped d))
                  <> ") -- these words reach no output:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  <"
                    <> T.intercalate "> <" hs <> ">"
                | (n, t, hs) <- diagDropped d ]
    -- A word that reaches a concept and nothing else: the mint declared it
    -- decoration, so nothing is wrong with the engine -- but the author who
    -- edits that word gets no effect, and only this says so.
    decorativeBlock
      | null (diagDecorative d) = []
      | otherwise =
          "" : ("read as decoration (" <> tshow (length (diagDecorative d))
                  <> ") -- these words reach a concept only:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  <"
                    <> T.intercalate "> <" hs <> ">"
                | (n, t, hs) <- diagDecorative d ]
    -- A word the rule spending it cannot take. Refine refuses it a phase later
    -- naming a decision id; here it is named on the line the author wrote, which
    -- is the only place they can fix it.
    unfitBlock
      | null (diagUnfit d) = []
      | otherwise =
          "" : ("does not fit (" <> tshow (length (diagUnfit d))
                  <> ") -- these values are not what the option takes:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  " <> why
                | (n, t, whys) <- diagUnfit d, why <- whys ]
    openBlock
      | null (diagOpen d) = []
      | otherwise = "" : ("open questions (" <> tshow (length (diagOpen d)) <> "):")
                       : ["  - " <> q | q <- diagOpen d]
    subjectPath (Subject segs) = T.intercalate "." segs

-- | @3 options@ but @1 option@: a count a reader trips over is a count they
-- reread instead of acting on.
plural :: Int -> Text -> Text
plural n word = tshow n <> " " <> word <> (if n == 1 then "" else "s")

-- | One voice for the defect, whether it is caught at the mint gate or found in
-- an engine already committed: the wording lives with the gate
-- ('Lips.Kernel.Engine.Gate'), this only wraps it in the generate-time action.
unanswerableReport :: FilePath -> [UnanswerableDemand] -> Text
unanswerableReport file = validationReport file . unanswerableProblem

-- | A validation failure kept structured (not pre-rendered) so each command
-- picks the right next action: on print/run some are the author's to edit,
-- others mean regenerate; generate frames all of them as a mint that did not
-- hold up.
data Failure = FailRead [CrystError] | FailRun RunError

-- | What went wrong and where, in plain words, with no action line (the caller
-- appends the action, which depends on the command).
failureReport :: FilePath -> Failure -> Text
failureReport file (FailRead errs) =
  reportHead (T.pack file <> " has lines its setup doesn't handle:") (map crystDetail errs)
  where
    crystDetail (NoPattern n t)   = "line " <> tshow n <> ": " <> t
    crystDetail (Overlapping n _) = "line " <> tshow n <> ": the setup reads this line more than one way"
    -- The line is fine; what is missing is the line that should open its block
    -- above it. Naming that is the remedy, so say it rather than "unreadable".
    crystDetail (NoParentBlock n t _) =
      "line " <> tshow n <> ": " <> t <> " -- this belongs inside a block, and no line above it opens one"
    -- The setup names one of this line's words as an identity, and the word
    -- cannot be one: what the line states could not be written down and read
    -- back, so the decisions file would stop being readable text.
    crystDetail (Unreadable n t why) =
      "line " <> tshow n <> ": " <> t
        <> " -- what this line states cannot be written down and read back (" <> why <> ")"
failureReport file (FailRun err) = case err of
  ParseRejected es ->
    reportHead (T.pack file <> " has lines that couldn't be read:")
               [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  OpenQuestions qs ->
    reportHead (T.pack file <> " leaves questions its setup needs answered:") qs
  Conflicted cs ->
    reportHead (T.pack file <> " sets the same thing two ways:")
               [ niceSubject (conflictSubject c) <> ": "
                   <> loc (conflictLeft c) <> " and " <> loc (conflictRight c) | c <- cs ]
  -- A rewrite that fails is the one refine error whose cause can be EITHER side:
  -- a word the option cannot take (the program's) or a rule that cannot fill its
  -- own emit (the engine's). Both are named rather than one guessed, and the
  -- per-line report from 'diagnose' says which line stated the word.
  RefineFailed e@(RewriteFailed {}) ->
    reportHead ("lips could not fit what " <> T.pack file
                  <> " states into the setup it was built with:")
               [refineDetail e]
  RefineFailed e ->
    reportHead ("the setup lips built for " <> T.pack file <> " is broken, not your program:")
               [refineDetail e]
  Unmapped ds ->
    reportHead (T.pack file <> " asks for things its setup can't do:")
               [ loc d <> ": " <> niceSubject (dSubject d) | d <- ds ]
  Unrealizable rs ->
    reportHead ("the setup lips built for " <> T.pack file <> " can't be turned into a module:") rs

-- | The full message for a print/run failure: the diagnosis plus the action
-- that fits it -- edit the program (unanswered questions, a contradiction) or
-- rebuild the setup (everything else).
printFail :: FilePath -> Failure -> Text
printFail file f = failureReport file f <> "\n\n" <> act
  where
    act = case f of
      FailRun (OpenQuestions _) -> "→ answer each in " <> T.pack file <> ", then run again."
      FailRun (Conflicted _)    -> "→ keep only one of those lines in " <> T.pack file <> ", then run again."
      FailRun (RefineFailed (RewriteFailed {})) ->
        "→ state a value that fits in " <> T.pack file
          <> ", or rebuild the setup: lips generate " <> T.pack file
      _                         -> "→ rebuild the setup: lips generate " <> T.pack file

refineDetail :: RefineError -> Text
refineDetail (Overlap _ _)         = "two of its rules claim the same thing"
refineDetail (Nonterminating _)    = "its rules loop without settling"
refineDetail (RewriteFailed _ _ m) = m

-- | A subject as plain words: its dotted segments spaced out, so route./hello
-- reads as "route /hello".
niceSubject :: Subject -> Text
niceSubject (Subject segs) = T.intercalate " " segs

-- | Where a decision came from, in author terms: a file location, or a note
-- that the setup computed it.
loc :: Decision -> Text
loc d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived _ _                -> "(computed by the setup)"
  FromGeneration _           -> "(from the setup)"

-- | A committed file lips can't read back (corrupted or hand-edited).
unreadable :: FilePath -> Text -> [ParseError] -> Text
unreadable file suffix es = report
  (T.pack file <> suffix <> " is unreadable, so lips can't use it:")
  [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  ("→ rebuild it: lips generate " <> T.pack file)

-- | nix is needed but couldn't run: a missing-tool failure (install it), never
-- the fault of the program or the generated setup.
nixMissing :: FilePath -> Text -> Text -> Text -> Text
nixMissing file what cmd detail = report
  ("lips needs nix to " <> what <> ", but couldn't run it:")
  (T.lines detail)
  ("→ install nix, or run lips through it: nix run . -- " <> cmd <> " " <> T.pack file)

-- | nix ran but evaluation failed: usually a missing nixpkgs, not the setup.
nixEvalFailed :: FilePath -> Text -> Text -> Text
nixEvalFailed file cmd detail = report
  "lips couldn't evaluate the configuration to check it:"
  (T.lines detail)
  ("→ this usually means nixpkgs isn't available. Try: nix run . -- " <> cmd <> " " <> T.pack file)

-- | The machine-readable twin of 'refusalReport', written to 'gapPath'
-- whenever generate refuses. Same content the record for a SUCCESSFUL mint
-- would have carried (model, target, schema pin, thinking, confidence, the full system
-- prompt, program corpus, tool transcript and raw reply -- 'record', the same
-- function '.generation' uses), fingerprinted the same way ('genId'), plus
-- the refusal-specific summary up front: this is what makes it a shippable
-- bug report for the cross-repo escalation workflow (DESIGN Doctrine) rather
-- than only on-screen text. A mint-reported 'Gap' already names its own
-- blocked line and repro (the mint's job, not this renderer's), so it is
-- listed verbatim.
gapArtifact :: Text -> [Text] -> [ItemCandidate] -> [Gap] -> Text
gapArtifact rec errs unsure gaps = T.unlines $
  [ "# lips generate refusal report. Machine-readable; rewritten on every refusal, never hand-edited."
  , "# fingerprint: " <> genId rec <> " (re-hash the record below with the same function '.generation' uses to verify)"
  , ""
  , "--- refused lines (a line the AI wrote that lips's grammar can't express) ---"
  ] ++ (if null errs then ["(none)"] else map ("- " <>) errs) ++
  [ "", "--- underspecified (the program didn't pin these down with enough confidence) ---" ] ++
  (if null unsure then ["(none)"] else [ "- " <> icLine c | c <- unsure ]) ++
  [ "", "--- missing capability (the mint's own words; each names its blocked line and a repro) ---" ] ++
  (if null gaps then ["(none)"]
   else concat [ ("- " <> gapSlug g) : [ "    " <> l | l <- T.lines (T.strip (gapBody g)) ] | g <- gaps ]) ++
  [ "", "--- generation record (model, target, schema, thinking, confidence, system prompt, program, tool transcript, raw reply) ---", rec ]

-- | generate couldn't build a setup: either lines lips couldn't read (a
-- capability may be missing) or values the program leaves underspecified.
refusalReport :: FilePath -> FilePath -> Double -> [Text] -> [ItemCandidate] -> [(Text, Text)] -> [Gap] -> Text
refusalReport file gapFile _threshold errs unsure notes gaps = T.intercalate "\n" $
  ["lips couldn't build a setup for " <> T.pack file <> "."]
    ++ grammar ++ underspecified ++ missing
    ++ [ "", "\8594 the full refusal (refused lines, fingerprint, raw reply) is saved to " <> T.pack gapFile
       , "  -- a shippable artifact for a bug report if this looks like a lips gap." ]
  where
    -- A dead mint that names the capability it lacked yields a work item
    -- rather than a shrug: the gap is a kernel bug in the model's own words.
    missing
      | null gaps = []
      | otherwise =
          [ "", "The mint says lips is missing a capability here:" ]
          ++ concat [ ("  - " <> gapSlug g)
                        : [ "      " <> l | l <- T.lines (T.strip (gapBody g)) ]
                    | g <- gaps ]
          ++ [ ""
             , "→ this is a lips bug, not your program. Please report the text above." ]
    grammar
      | null errs = []
      | otherwise =
          [ "", "The AI wrote something lips can't express yet:" ]
          ++ [ "  - " <> e | e <- errs ]
          ++ [ ""
             , "→ if the same item (above) fails every time you run generate,"
             , "  lips is missing a capability it needs here; please report that"
             , "  line. If the failing item changes or it is one-off, run generate"
             , "  again and the model may phrase it differently." ]
    underspecified
      | null unsure = []
      | otherwise =
          [ "", "The program doesn't pin these down (the AI wasn't confident enough):" ]
          ++ concat [ [ "  - " <> icLine c <> "   [confidence " <> conf c <> "]" ]
                       ++ maybe [] (\r -> [ "      why: " <> r ]) (lookup (icId c) notes)
                    | c <- unsure ]
          ++ [ ""
             , "→ state the missing detail in " <> T.pack file <> " and run again."
             , "  If the choice is genuinely free, lower the bar: --confidence " <> suggestedBar ]
    conf c = let Confidence x = icConfidence c in tshow x
    -- Suggest the lowest dropped confidence itself: the filter keeps items with
    -- confidence >= threshold, so this bar admits every currently-unsure item
    -- (and no lower). A constant hint could repeat the value the user just used.
    suggestedBar = tshow (minimum [x | c <- unsure, let Confidence x = icConfidence c])

-- | A behavioral check names an option a rule fills with a package or artifact
-- reference (a derivation, not a program value). Such a check can neither be
-- evaluated under the check's stubs nor meaningfully satisfied, so it is
-- rejected loud instead of crashing the eval (deduce-or-fail).
uncheckableReport :: FilePath -> [Expect] -> Text
uncheckableReport file bad = report
  (T.pack file <> " checks options that hold a package or build, not a plain value:")
  [ T.intercalate "." (exPath e) <> " (check " <> exId e <> ")" | e <- bad ]
  ("→ a check must name an option that holds a value from " <> T.pack file
    <> ", not a package or build. Rebuild the setup: lips generate " <> T.pack file)

-- | A demand the minted engine leaves unmet at generate. Ambiguous by
-- construction (the kernel cannot tell a silent program from patterns that
-- misread a stated value), so it names BOTH remedies and lets the author, who
-- alone knows which, choose. Both paths re-enter generate: a value you add
-- still needs a fresh mint to grow a pattern that reads it.
demandGenerateFail :: FilePath -> [Text] -> Text
demandGenerateFail file qs = T.intercalate "\n" $
  [ T.pack file <> ": lips built a setup but left these unanswered:" , "" ]
    ++ [ "  " <> q | q <- qs ]
    ++ [ ""
       , "Either your program does not state these, or the setup lips built"
       , "misread them; for example, if a value is already there (\"on port 8080\"),"
       , "the setup read it wrong."
       , ""
       , "\x2192 run generate again. If the same facts keep coming up unanswered,"
       , "  state them in " <> T.pack file <> " or report it as a lips bug." ]

-- | generate built a setup but it did not hold up: wrap a diagnosis with the
-- generate-time action (mint again; report a lips bug if it persists). Not the
-- program's fault.
validationReport :: FilePath -> Text -> Text
validationReport file problem = T.intercalate "\n"
  [ "lips built a setup for " <> T.pack file <> ", but it didn't hold up:"
  , ""
  , problem
  , ""
  , "→ run generate again. If it keeps failing the same way, it's a lips bug;"
  , "  please report it with the text above."
  ]

renderParseError :: ParseError -> Text
renderParseError e = "  line " <> tshow (peLine e) <> ": " <> peMessage e

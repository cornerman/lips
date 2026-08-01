{-# LANGUAGE OverloadedStrings #-}

-- | The engine-level gates that need no schema and no nix: an engine is judged
-- against itself. Pure, so one implementation serves generate (which refuses a
-- mint), check (which refuses a committed or draft engine) and the conformance
-- suite (which asserts) -- the "functional core, imperative shell" split, with
-- the decision here and the exit at the call site.
--
-- The schema-dependent gate is NOT here: it needs an option document, and only
-- generate and options ever build one, which is what keeps check nixpkgs-free.
module Lips.Kernel.Engine.Gate
  ( engineViolations
  , unanswerableProblem
  ) where

import           Data.Maybe (mapMaybe)
import           Data.Text (Text)
import qualified Data.Text as T

import           Lips.Kernel.Engine.Answerable (UnanswerableDemand, renderUnanswerableDemand, unanswerableDemands)
import           Lips.Kernel.Engine.Data       (Emit (..), MapRule (..), renderAttrPath)
import           Lips.Kernel.Engine.Overlap    (patternOverlaps, renderPatternOverlap, renderRuleOverlap, ruleOverlaps)
import           Lips.Kernel.Engine.Reach      (droppedValues, renderDroppedValue)
import           Lips.Kernel.Engine.Value      (valuePathHoles)
import           Lips.Kernel.Lang.Store        (EngineData (..))

-- | Every way an engine can be unsound on its own terms, in the order the gates
-- have always run, one entry per rejecting gate. Empty means sound.
--
-- Each entry is the same problem text the human refusal has always shown, so a
-- model reading it and a human reading it see one wording. The caller reports
-- the FIRST entry, which is what dying on the first gate has always done: a
-- later gate's verdict is rarely meaningful once an earlier one rejected the
-- engine. Laziness makes that free -- asking whether the list is empty runs
-- only as many gates as it takes to find one.
engineViolations :: EngineData -> [Text]
engineViolations eng = mapMaybe ($ eng)
  [ patternsOrthogonal
  , rulesOrthogonal
  , valuesReach
  , noPathHoles
  , demandsAnswerable
  ]

-- | Two templates that could read one line leave the language with no single
-- reading of it. 'Lips.Kernel.Lang.Crystallize.crystallize' reports the clash
-- for a line some program actually states, so an ambiguity no example separates
-- ships inside the engine and fails later on the author's own program. The
-- multi-token hole makes this cheap to mint by accident: it reads lines of every
-- length, so it overlaps almost any template with the same prefix.
patternsOrthogonal :: EngineData -> Maybe Text
patternsOrthogonal eng = case patternOverlaps (edPatterns eng) of
  []  -> Nothing
  ovs -> Just
    ("two of its patterns read the same line, so it has no single reading:\n"
      <> T.unlines (map (("  - " <>) . renderPatternOverlap) ovs))

-- | The same argument one layer down: two rules whose left-hand sides unify
-- could claim one decision, so refinement would not be a function. The refiner
-- enforces the property at run time ('Lips.Kernel.Refine.Overlap'), but only for
-- an overlap some concrete decision witnesses -- and an engine may ship an
-- ambiguity no program in the corpus happens to hit, which then fails on the
-- author's machine instead of here.
rulesOrthogonal :: EngineData -> Maybe Text
rulesOrthogonal eng = case ruleOverlaps (edRules eng) of
  []  -> Nothing
  ovs -> Just
    ("two of its rules claim the same decision, so it has no single reading:\n"
      <> T.unlines (map (("  - " <>) . renderRuleOverlap) ovs))

-- | Deduce-or-fail applied to the engine's own reading: a word the language
-- binds and then discards makes a program line look load-bearing while changing
-- nothing, and no later stage can notice (the module it realizes is perfectly
-- valid Nix). Three honest ways out, named in the report because a refusal that
-- does not say what to write costs a whole round.
valuesReach :: EngineData -> Maybe Text
valuesReach eng = case droppedValues (edPatterns eng) (edRules eng) of
  []  -> Nothing
  dvs -> Just
    ("it reads words from the program and then discards them:\n"
      <> T.unlines (map (("  - " <>) . renderDroppedValue) dvs)
      <> "\nEach one wants one of three fixes: use the word (a <value>/<value.N>\n"
      <> "hole, or the capture aligned with the subject segment it fills); or, if\n"
      <> "it SELECTS a mechanism no value can carry (a builder, a service), spell\n"
      <> "it as a literal token of the template, so editing it stops the line\n"
      <> "matching and asks for a fresh language instead of governing nothing; or,\n"
      <> "if the line truly carries no value, read it as a concept.")

-- | A program word must never be coerced into a bare Nix path. A Nix path means
-- "copy this location into the store", so an absolute one is refused outright by
-- pure evaluation, and for a runtime directory (a document root, a data dir)
-- copying is never the intent: the option wants the string. A path is therefore
-- something the ENGINE writes as a literal (@.\/artifacts\/x@), never a coercion
-- of the author's word.
--
-- Caught here because nothing downstream can: the realized module is valid Nix
-- and evaluates until something forces the path, so the failure surfaces as an
-- opaque nix error far from the rule that caused it.
noPathHoles :: EngineData -> Maybe Text
noPathHoles eng =
  case [ (mrId r, emPath e, h)
       | r <- edRules eng, e <- mrEmits r, h <- valuePathHoles (emRhs e) ] of
    []  -> Nothing
    bad -> Just
      ("it turns a program word into a Nix path, which copies that location into the store:\n"
        <> T.unlines [ "  - rule " <> rid <> " fills " <> renderAttrPath pth
                         <> " with <" <> h <> ":path>"
                     | (rid, pth, h) <- bad ]
        <> "\nWrite the value as a quoted STRING instead (\"\\\"<value>\\\"\"): an\n"
        <> "option of type path accepts a string, and a directory the program names\n"
        <> "exists on the running machine, not in the store. Keep a Nix path for a\n"
        <> "literal the engine itself writes, like ./artifacts/<name>.")

-- | A demand no pattern can ever answer blocks every program in the language,
-- and reports itself as the author's missing fact (see
-- 'Lips.Kernel.Engine.Answerable'), so it is caught where the engine is still
-- rejectable and the model is still the one to fix it.
demandsAnswerable :: EngineData -> Maybe Text
demandsAnswerable eng = case unanswerableDemands (edPatterns eng) (edDemands eng) of
  []  -> Nothing
  uds -> Just (unanswerableProblem uds)

-- | One voice for the defect, whether it is caught at the mint gate or found in
-- an engine already committed (where check reaches it through the open
-- questions it explains).
unanswerableProblem :: [UnanswerableDemand] -> Text
unanswerableProblem uds =
  "it demands facts no program in this language can state:\n"
    <> T.unlines (map (("  - " <>) . renderUnanswerableDemand) uds)
    <> "\nA demand is met by a decision a pattern EMITS, matched segment for\n"
    <> "segment, so the demanded subject must be one of those families -- write\n"
    <> "the capture too (demand command.<name>, not demand command)."

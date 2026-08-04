{-# LANGUAGE OverloadedStrings #-}

-- | What type does the engine give a word the language reads?
--
-- An author writing a sentence knows what the words MEAN; only the engine knows
-- what each one must BE. A port is an int because some rule spends it as
-- @\<value:int\>@, a package name is a package because a rule spends it as
-- @\<value:pkg\>@, and a word keying an artifact is a name. That fact is
-- derivable offline, from the engine alone, and it is what lets an editor label
-- a hole and check a value while it is typed.
--
-- Domain-blind, like every other kernel judgment: it reads the closed value
-- grammar at the position the word lands in ('Lips.Kernel.Engine.Landing' finds
-- that position), never the word itself.
--
-- SILENT WHERE UNSURE. A word two rules spend at two types, and a word no rule
-- spends at all, get no answer: a wrong type reads to the author as their own
-- mistake when it is the engine's, and an editor showing nothing is honest.
module Lips.Kernel.Engine.Typing
  ( wordTypes
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe      (isJust)
import           Data.Text       (Text)

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Landing (Landing (..), Part (..), wordLandings)
import Lips.Kernel.Engine.Value   (WordType (..), holeIndex, narrowerWordType,
                                   valueHoleTypes)
import Lips.Kernel.Lang.Pattern   (Pattern (..), holesOf)

-- | The type of every word a pattern reads, where the engine fixes one.
-- Keyed by hole name, so the caller asks by the name the author sees in the
-- template.
wordTypes :: [Pattern] -> [MapRule] -> Pattern -> Map Text WordType
wordTypes pats rules p = Map.fromList
  [ (h, t) | h <- holesOf p, Just t <- [oneType (typesOf h)] ]
  where
    typesOf h = [ t | l <- wordLandings pats rules p h, r <- lgRules l, t <- siteTypes l r ]
    -- Every position the word fills constrains it, so the answer is the
    -- narrowest of them ('narrowerWordType'): a port written into source AND
    -- into an int option is an int. Positions that contradict give no answer at
    -- all -- the engine itself gives the word two shapes, which no label can
    -- state, and a wrong one reads as the author's mistake.
    oneType ts = case ts of
      []       -> Nothing
      (t : ts') -> foldl (\acc x -> acc >>= narrowerWordType x) (Just t) ts'

-- | The types one rule gives a word: from the assertion it reads, and from the
-- subject capture standing where the word lands.
siteTypes :: Landing -> MapRule -> [WordType]
siteTypes l r = assertionTypes ++ captureTypes
  where
    -- Every emit of the rule, not the first: one rule may write the word into
    -- several options, and each of those positions constrains it.
    rhsTypes = Map.fromListWith (++)
      [ (n, [t])
      | e <- mrEmits r, (n, t) <- Map.toList (valueHoleTypes (emRhs e)) ]
    -- The rhs hole that reads this word: <value> and <value.tail> read the whole
    -- assertion, an indexed <value.N> reads part N -- and reads a WORD of a
    -- one-part value, which is the same position.
    assertionTypes = case lgPart l of
      Nothing       -> []
      Just Whole    -> [ t | (n, ts) <- Map.toList rhsTypes, reads' n Nothing, t <- ts ]
      Just (Part i) -> [ t | (n, ts) <- Map.toList rhsTypes, reads' n (Just i), t <- ts ]
    reads' n mi = n == "value" || n == "value.tail"
                    || maybe (isJust (holeIndex n)) (\i -> holeIndex n == Just i) mi
    -- A capture the rule's subject binds at the segment the word lands in. A
    -- capture filling an emit PATH is a NAME (it keys an option slot, an
    -- artifact, a staged directory), which outranks the type of any value it
    -- also fills: the name is the binding constraint on the word.
    captureTypes =
      [ if inPath c then WName else t
      | i <- lgSegments l
      , Just c <- [captureName (segAt i)]
      , t <- Map.findWithDefault [] c rhsTypes
      ] ++
      [ WName
      | i <- lgSegments l
      , Just c <- [captureName (segAt i)]
      , inPath c
      , not (Map.member c rhsTypes)
      ]
    segAt i = case drop i (mrSubject r) of
      (s : _) -> s
      []      -> ""
    inPath c = or [ c `elem` concatMap nameTokens (emPath e) | e <- mrEmits r ]

{-# LANGUAGE OverloadedStrings #-}

-- | Turn a mint's REPLY into the contents of a language folder, so the ordinary
-- verifier can judge a draft engine exactly as it judges a committed one.
--
-- The draft arrives in reply format, not .lang format, deliberately: asking a
-- model to write one format for checking and another for answering would let
-- the two diverge, and the thing it checks must be the thing it ships.
--
-- Pure: it decides what the folder holds, and the caller writes it. So a test
-- states a draft and reads the verdict without touching a filesystem, and the
-- one place that writes minted source stays the one place (functional core,
-- imperative shell).
module Lips.Generate.Draft
  ( DraftTree (..)
  , materializeDraft
  , splitEngine
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

import           Lips.Generate.Minting  (ItemCandidate (..), SourceFile, assemble, expectsOf,
                                         parseEngineCandidates, sourcesOf)
import           Lips.Identity          (languageName)
import           Lips.Kernel.Expect     (renderExpect)
import           Lips.Kernel.Lang.Store (renderLang)
import           Lips.Kernel.Decision   (Provenance (..), SourceLoc (..))
import           System.FilePath        ((</>))

-- | Everything a throwaway language folder holds: where it goes, and the three
-- files that go in it. No @.generation@ and no README: nothing downstream of a
-- draft reads them, and a draft has no generation to record.
data DraftTree = DraftTree
  { dtLangDir :: FilePath     -- ^ the folder to point check at
  , dtWorld   :: Text         -- ^ the world this draft is minted into
  , dtGrammar :: Text         -- ^ the shared grammar, at the language level
  , dtRules   :: Text         -- ^ this world's lowering, inside its folder
  , dtExpect  :: Text         -- ^ the GOVERNING contract (see 'materializeDraft')
  , dtSources :: [SourceFile] -- ^ the baked source tree, staged under artifacts/
  }

-- | Build a language folder's contents from a reply. @root@ is a temporary
-- directory, @file@ the program the draft is for, @reply@ the mint's raw
-- answer, and @governing@ the contract that decides this mint: the committed
-- .expect on a regeneration, or Nothing to use the draft's own minted expects
-- (correct only on a first generation or under @--renew@).
--
-- Grading a model against expects it just wrote itself always passes and the
-- real gate then refuses, which is worse than no tool at all -- so the caller
-- resolves the contract with the same rule generate uses for itself, and this
-- function only obeys it.
--
-- The folder is NAMED after the language, because 'Lips.Identity.resolveLangDir'
-- refuses a folder whose basename is not the program's language.
materializeDraft :: FilePath -> Text -> FilePath -> Text -> Maybe Text -> Either [Text] DraftTree
materializeDraft root world file reply governing = case parseEngineCandidates [world] reply of
  (errs@(_ : _), _) -> Left errs
  ([], cands) ->
    let items = map icItem cands
        -- A draft has no generation id to stamp with, and says so in the
        -- provenance rather than inventing one that would not re-hash.
        (grammar, rules) = splitEngine (renderLang (FromSource (SourceLoc "draft" 0)) (assemble items))
     in Right DraftTree
          { dtLangDir = root </> languageName file
          , dtWorld   = world
          , dtGrammar = grammar
          , dtRules   = rules
          , dtExpect  = maybe (renderExpect (expectsOf items)) id governing
          , dtSources = sourcesOf items
          }

-- | Split a rendered engine into the shared grammar (the pattern lines) and one
-- world's rules. The subject prefix already carries the split -- @lang.*@ is the
-- language reading a program, @engine.*@ is its lowering into a world -- so this
-- is a partition of the same canonical text, and
-- 'Lips.Kernel.Lang.Store.readLang' reads the two back by concatenation.
--
-- One function, used by the draft path and by @generate@'s write step, because
-- a draft is judged as the committed engine will be read.
splitEngine :: Text -> (Text, Text)
splitEngine src = (unlines' isLang, unlines' (not . isLang))
  where
    ls = T.lines src
    unlines' p = T.unlines (filter p ls)
    -- Field 3 of a decision line is its subject; a rendered engine has no blank
    -- or comment lines, so a line too short to have one cannot occur and is
    -- kept with the rules, where readLang reports it.
    isLang l = case drop 2 (T.words l) of
      (subj : _) -> "lang." `T.isPrefixOf` subj
      []         -> False

{-# LANGUAGE OverloadedStrings #-}

-- | What a compiled site holds, decided without touching a filesystem.
--
-- Choosing a runtime, linking its adapters, assembling the entry and the claims:
-- all of it is a function from a realization to a list of files. The IO shell
-- around it only writes what this returns and deletes what it says is stale, so
-- the decisions are testable in the suite with no temp directory and no nix.
--
-- Split out of @app\/Main.hs@, where it had grown four jobs into one @do@ block:
-- choose, copy, assemble, prune. Functional core, imperative shell, applied to a
-- part of lips that had stopped obeying it.
module Lips.Site
  ( SitePlan (..)
  , planSite
  ) where

import           Data.Bifunctor (first)
import           Data.List (nub, sort)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Claim            (renderClauseClaim)
import Lips.Kernel.Clause.Catalogue (Harness (..), Runtime (..), clauseClaimsFile,
                                     coveringRuntime, entryDemand, entryFor, siteFile)
import Lips.Kernel.Run              (Realization (..))

-- | The WHOLE content of a site directory: every file it should hold, and
-- nothing else. Stated as a total content rather than a write list plus a delete
-- list, because the two could disagree -- and did: a delete list naming only the
-- claim files left a previous runtime's adapters behind when the covering chose
-- a different one. The shell removes whatever is in the directory and not here.
data SitePlan = SitePlan
  { spRuntime :: Runtime
  , spFiles   :: [(FilePath, Text)]  -- ^ path relative to the site dir, and its content
  }
  deriving (Eq, Show)

-- | Plan a site from a realization and the catalogue of runtimes lips ships.
--
-- 'Nothing' for a program that states no behaviour, which leaves every
-- configuration-only program untouched. A 'Left' is the covering computation
-- refusing to guess: no runtime provides what the clauses reach, or none has a
-- property the author required, or several fit and the author must say which.
--
-- The asset lookup is injected rather than imported, so this module never learns
-- where lips keeps its runtime files, and the suite can plan a site against a
-- runtime it invents.
planSite :: (Text -> FilePath -> Maybe Text) -> Text -> [Runtime] -> Realization
         -> Either (Text, Text) (Maybe SitePlan)
planSite asset lang runtimes rl = case rlCore rl of
  -- Claims over clauses a program does not state: the site directory would never
  -- be written, and the claim build would then die on a missing path naming
  -- neither lips nor a remedy.
  Nothing | not (null (rlClauseClaims rl)) -> Left
    ( "this setup states " <> plural' (length (rlClauseClaims rl)) "observable"
        <> " over the program's clauses, and the program states no clauses."
    , "\8594 rebuild the setup: lips generate <program>." )
  Nothing -> Right Nothing
  Just (core, contracts, defined) -> do
    rt0 <- first (\why -> (why, "\8594 state a requirement in the program, or add a\
                                \ runtime that covers it."))
            (coveringRuntime runtimes contracts (rlSiteProps rl))
    -- The runtime spells its entry with a hole, so the site starts the clause of
    -- THIS language (namespacing leaves no bare name to start).
    let rt = entryFor lang rt0
    -- The core must satisfy the runtime's entry, or the site builds and dies on
    -- first run with "wrong number of arguments" and every lips gate green.
    (entryName, entryArgs) <- first (\why -> (why, "\8594 this is a lips bug; report it."))
                                    (entryDemand rt)
    case lookup entryName defined of
      Just (Just n) | n == entryArgs -> Right ()
      Just (Just n) -> engineFault (T.pack (show entryName) <> " is defined with " <> plural n
                       <> ", but the " <> rName rt <> " runtime starts a program by\
                          \ calling it with " <> plural entryArgs <> " ("
                       <> rEntry rt <> "). Define it to take " <> plural entryArgs <> ".")
      -- A constant is not a procedure of no arguments. Reading it as one shipped a
      -- binary that died on first run with every gate green.
      Just Nothing -> engineFault (entryName <> " is defined as a constant, and the "
                       <> rName rt <> " runtime starts a program by calling it ("
                       <> rEntry rt <> "). Define it as a procedure of "
                       <> plural entryArgs <> ".")
      Nothing -> engineFault ("the " <> rName rt <> " runtime starts a program by calling "
                        <> entryName <> " (" <> rEntry rt <> "), and this program\
                           \ defines no clause of that name.")
    -- A run links the pure adapters, the real effects, then the core. A claim
    -- swaps the effects for the list-backed ones and the verdict harness, so the
    -- real ones are never loaded beside them.
    let runFiles   = rFiles rt <> rEffectFiles rt <> ["core.scm"]
        claimFiles = rFiles rt <> rClaimFiles rt <> ["core.scm"]
        claims     = rlClauseClaims rl
        adapters   = rBuild rt : rFiles rt <> rEffectFiles rt
                       <> (if null claims then [] else rClaimFiles rt)
    shipped <- traverse (fromAsset rt) (nub adapters)
    -- The plan is the site's WHOLE content, so one path may appear once. A
    -- runtime declaring the same file twice (in its pure list and its claim list)
    -- would otherwise write it twice and make "total content" a claim the type
    -- does not keep.
    case duplicates (map fst shipped <> ["core.scm", "main.scm", "claims.scm"]) of
      (dup : _) -> Left ("the " <> rName rt <> " runtime would write " <> T.pack dup
                          <> " twice into one site."
                        , "\8594 this is a lips bug; report it.")
      []        -> Right ()
    Right (Just SitePlan
      { spRuntime = rt
      , spFiles =
          shipped
            <> [ ("core.scm", core)
               , ("main.scm", siteFile rt runFiles) ]
            <> [ ("claims.scm", clauseClaimsFile rt claimFiles
                                  (concatMap (renderClauseClaim (harnessWords rt)) claims))
               | not (null claims) ]
      })
  where
    -- The engine is at fault, not the program: the remedy is a fresh mint.
    engineFault why = Left (why, "\8594 rebuild the setup: lips generate <program>.")
    plural 1 = "1 parameter"
    plural n = T.pack (show n) <> " parameters"
    duplicates xs = [ a | (a : b : _) <- window (sort xs), a == b ]
    window ys = [ drop i ys | i <- [0 .. length ys - 1] ]
    plural' 1 what = "1 " <> what
    plural' n what = T.pack (show n) <> " " <> what <> "s"
    -- The builder is written under a fixed name, so the module and the flake can
    -- import ./site/build.nix without knowing which runtime wrote it.
    fromAsset rt f = case asset (rName rt) f of
      Just body -> Right (if f == rBuild rt then "build.nix" else f, body)
      Nothing -> Left ("lips ships no file " <> T.pack f <> " for the " <> rName rt
                        <> " runtime, although that runtime declares it."
                       , "\8594 this is a lips bug; report it.")

-- | The four words a claim form is written with, in the order 'renderClauseClaim'
-- takes them. Pulled from the runtime so the kernel keeps the shapes and the
-- runtime keeps the vocabulary.
harnessWords :: Runtime -> (Text, Text, Text, Text)
harnessWords rt =
  ( hFeedArgs g, hFeedLines g, hJudge g, hList g )
  where g = rHarness rt

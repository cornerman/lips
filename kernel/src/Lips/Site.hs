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
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Claim            (renderClauseClaim)
import Lips.Kernel.Clause.Catalogue (Runtime (..), clauseClaimsFile, coveringRuntime,
                                     entryDemand, siteFile)
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
planSite :: (Text -> FilePath -> Maybe Text) -> [Runtime] -> Realization
         -> Either (Text, Text) (Maybe SitePlan)
planSite asset runtimes rl = case rlCore rl of
  Nothing -> Right Nothing
  Just (core, contracts, defined) -> do
    rt <- first (\why -> (why, "\8594 state a requirement in the program, or add a\
                                \ runtime that covers it."))
            (coveringRuntime runtimes contracts (rlSiteProps rl))
    -- The core must satisfy the runtime's entry, or the site builds and dies on
    -- first run with "wrong number of arguments" and every lips gate green.
    (entryName, entryArgs) <- first (\why -> (why, "\8594 this is a lips bug; report it."))
                                    (entryDemand rt)
    case lookup entryName defined of
      Just n | n == entryArgs -> Right ()
      Just n -> engineFault (T.pack (show entryName) <> " is defined with " <> plural n
                       <> ", but the " <> rName rt <> " runtime starts a program by\
                          \ calling it with " <> plural entryArgs <> " ("
                       <> rEntry rt <> "). Define it to take " <> plural entryArgs <> ".")
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
    shipped <- traverse (fromAsset rt) adapters
    Right (Just SitePlan
      { spRuntime = rt
      , spFiles =
          shipped
            <> [ ("core.scm", core)
               , ("main.scm", siteFile rt runFiles) ]
            <> [ ("claims.scm", clauseClaimsFile claimFiles
                                  (concatMap renderClauseClaim claims))
               | not (null claims) ]
      })
  where
    -- The engine is at fault, not the program: the remedy is a fresh mint.
    engineFault why = Left (why, "\8594 rebuild the setup: lips generate <program>.")
    plural 1 = "1 parameter"
    plural n = T.pack (show n) <> " parameters"
    -- The builder is written under a fixed name, so the module and the flake can
    -- import ./site/build.nix without knowing which runtime wrote it.
    fromAsset rt f = case asset (rName rt) f of
      Just body -> Right (if f == rBuild rt then "build.nix" else f, body)
      Nothing -> Left ("lips ships no file " <> T.pack f <> " for the " <> rName rt
                        <> " runtime, although that runtime declares it."
                       , "\8594 this is a lips bug; report it.")

{-# LANGUAGE OverloadedStrings #-}

-- | The disk side of a realization: what lips writes beside a module so that
-- what nix evaluates is what a compiled directory holds.
--
-- Two jobs, both file moves rather than judgments: write the site a plan
-- describes beside a module in a temp directory (so a gate evaluates the real
-- neighbourhood instead of a module floating alone), and write a whole compiled
-- directory. Nothing here decides whether anything is CORRECT; the gates in
-- @app\/Main.hs@ call in here to set the stage, then judge.
--
-- The decisions stay pure and outside: 'Lips.Site' plans a site, while this
-- module owns only the IO.
module Lips.Stage
  ( withTempDir
  , stageBeside
  , siteNameOf
  , writeSite
  , writeCompiled
  ) where

import           Control.Exception  (finally)
import           Control.Monad      (forM_, void, when)
import           Data.Maybe         (fromMaybe)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (createDirectoryIfMissing, doesFileExist,
                                     getTemporaryDirectory, listDirectory,
                                     removeDirectoryRecursive, removeFile)
import           System.FilePath    ((</>))
import           System.Posix.Temp  (mkdtemp)

import           Lips.Cli.Output       (die, report)
import           Lips.Identity         (languageName)
import           Lips.Kernel.Realize   (defaultSiteName)
import           Lips.Kernel.Run       (Realization (..))
import           Lips.Nix.Claims       (claimsFile)
import           Lips.Nix.Flake        (Rungs (..), SchemaInput, SiteRung (..), flakeText)
import           Lips.Runtime          (runtimeAsset, runtimes)
import           Lips.Site             (SitePlan (..), planSite)
import           Lips.World            (World)

-- | A fresh temporary directory, where lips writes a module and the site beside
-- it so a relative path the module names resolves at evaluation.
withTempDir :: (FilePath -> IO a) -> IO a
withTempDir act = do
  tmp <- getTemporaryDirectory
  dir <- mkdtemp (tmp </> "lips-")
  -- Removed even when the action dies (exitFailure throws), so a failing check
  -- does not leave a scratch tree behind on every run.
  act dir `finally` removeDirectoryRecursive dir

-- | Everything a realized module names beside itself: the site its clauses
-- build. Handed to a gate that materializes the module into a temp directory,
-- so what nix evaluates there is what a compiled directory holds.
stageBeside :: FilePath -> Realization -> FilePath -> IO ()
stageBeside file rl root = void (writeSite (T.pack (languageName file)) root rl)

-- | Write one world's compiled directory for a realization: the module, the
-- site, @artifact.nix@, @claims.nix@ and the @flake.nix@ assembled from the
-- world. The ONE writer, shared by @compile@ and by the gate that builds a
-- world's own verdict over the render, so the directory a mint judges is the
-- directory a compile writes.
--
-- Returns the artifact names and the rungs, which is what @compile@ prints.
writeCompiled :: World -> SchemaInput -> FilePath -> FilePath -> Realization -> IO ([Text], Rungs)
writeCompiled world si file out rl = do
  createDirectoryIfMissing True out
  TIO.writeFile (out </> "default.nix") (rlModule rl)
  -- The clause core, when the program states behaviour: one site directory
  -- holding the runtime's adapters, the minted core, the assembled entry and
  -- the runtime's own builder. A configuration-only program writes none, so
  -- its output stays byte-identical.
  hasSite <- writeSite (T.pack (languageName file)) out rl
  -- Always written, empty set when the program declares none: the flake text
  -- imports it unconditionally.
  let (artBody, artNames) = rlArtifact rl
  TIO.writeFile (out </> "artifact.nix") artBody
  -- The experiments the program states, beside the artifacts they observe. A
  -- claim-free program writes no file and its output stays byte-identical.
  hasClaims' <- case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
    Nothing   -> pure False
    Just body -> TIO.writeFile (out </> "claims.nix") body >> pure True
  let rungs = Rungs { hasArtifacts = not (null artNames), hasClaims = hasClaims'
                      -- The name the module binds, so every rung of the
                      -- compiled directory builds the same derivation.
                    , siteRung = if not hasSite then Nothing
                                 else Just (SiteRung (siteNameOf rl)
                                                     (not (null (rlClauseClaims rl)))) }
  TIO.writeFile (out </> "flake.nix") (flakeText world si rungs)
  pure (artNames, rungs)

-- | What the program is installed as. A realization names the site only where
-- something REFERENCES it, so a program whose module never mentions @${site}@
-- still needs a name for the flake's own rung -- and it must be the name the
-- module would have used, from the one definition of the default.
siteNameOf :: Realization -> Text
siteNameOf rl = fromMaybe defaultSiteName (rlSiteName rl)

-- | Write the site a plan describes, and remove what it says is stale. The
-- decisions (which runtime, which files, what to prune) are pure and live in
-- 'Lips.Site'; this is the shell that touches the disk. Returns whether a site
-- was written, which is what decides the compiled flake's rungs.
writeSite :: Text -> FilePath -> Realization -> IO Bool
writeSite lang outDirPath rl = case planSite runtimeAsset lang runtimes rl of
  Left (why, remedy) -> die (report
    "lips can't build this program's behaviour."
    [why]
    remedy)
  Right Nothing -> pure False
  Right (Just plan) -> do
    let siteDir = outDirPath </> "site"
    createDirectoryIfMissing True siteDir
    -- The plan is the whole content, so anything else in the directory is from a
    -- compile that no longer applies: a claims file for claims the program has
    -- dropped, an adapter from a runtime the covering no longer chooses. Left
    -- there, it would keep being loaded by an assembly nobody stated.
    present <- listDirectory siteDir
    mapM_ (removeIfPresent siteDir)
          (filter (`notElem` map fst (spFiles plan)) present)
    forM_ (spFiles plan) (\(name, body) -> TIO.writeFile (siteDir </> name) body)
    pure True

-- | Delete a derived file that should no longer be there. Compile writes into a
-- directory it may have written before, so a file it stops producing must be
-- removed rather than left to be loaded by a stale assembly.
removeIfPresent :: FilePath -> FilePath -> IO ()
removeIfPresent dir name = do
  let path = dir </> name
  there <- doesFileExist path
  when there (removeFile path)

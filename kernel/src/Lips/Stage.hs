{-# LANGUAGE OverloadedStrings #-}

-- | The disk side of a realization: what lips writes beside a module so that
-- what nix evaluates is what a compiled directory holds.
--
-- Three jobs, all of them file moves rather than judgments: stage a language's
-- committed trees into a temp directory (so a gate evaluates the real
-- neighbourhood instead of a module floating alone), fill a staged tree's
-- markers with the words the program stated, and write the site a plan
-- describes. Nothing here decides whether anything is CORRECT; the gates in
-- @app\/Main.hs@ call in here to set the stage, then judge.
--
-- The decisions stay pure and outside: 'Lips.Site' plans a site and
-- 'Lips.Kernel.Source' fills a tree, while this module owns only the IO.
module Lips.Stage
  ( withTempDir
  , writeSources
  , fillStagedTree
  , stageFromDisk
  , stageBeside
  , siteNameOf
  , writeSite
  , stagedSizes
  ) where

import           Control.Exception  (finally)
import           Control.Monad      (forM, forM_, void, when)
import           Data.Maybe         (fromMaybe)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (copyFile, createDirectoryIfMissing, doesDirectoryExist,
                                     doesFileExist, getPermissions, getTemporaryDirectory,
                                     listDirectory, removeDirectoryRecursive, removeFile,
                                     setOwnerWritable, setPermissions)
import           System.FilePath    (takeDirectory, (</>))
import           System.Posix.Temp  (mkdtemp)

import           Lips.Cli.Output       (die, report)
import           Lips.Generate.Minting (SourceFile (..))
import           Lips.Identity         (artifactsPathIn, languageName)
import           Lips.Kernel.Decision   (Subject (..))
import           Lips.Kernel.Grounding (Grounding, Unvouched (..), gStaged)
import           Lips.Kernel.Realize   (defaultSiteName)
import           Lips.Kernel.Run       (Realization (..))
import           Lips.Kernel.Source    (fillTree)
import           Lips.Runtime          (runtimeAsset, runtimes)
import           Lips.Site             (SitePlan (..), planSite)

-- | A fresh temporary directory. lips writes a module and its staged
-- @artifacts/@ tree here so a relative @src = ./artifacts/<name>@ resolves at
-- evaluation. (Left in place, matching the module temp files elsewhere.)
withTempDir :: (FilePath -> IO a) -> IO a
withTempDir act = do
  tmp <- getTemporaryDirectory
  dir <- mkdtemp (tmp </> "lips-")
  -- Removed even when the action dies (exitFailure throws), so a failing check
  -- does not leave a scratch tree behind on every run.
  act dir `finally` removeDirectoryRecursive dir

-- | Write minted source files under @<root>/<artifact>/<relpath>@. Used to
-- persist to the language folder's @artifacts/@ and to stage into a temp
-- module dir.
writeSources :: FilePath -> [SourceFile] -> IO ()
writeSources root = mapM_ one
  where
    one sf = do
      let p = root </> T.unpack (sfArtifact sf) </> T.unpack (sfPath sf)
      createDirectoryIfMissing True (takeDirectory p)
      TIO.writeFile p (sfContent sf)


-- | Fill a staged source tree in place: every @\@marker\@@ becomes the text the
-- engine declared for it (kernel physics, 'Lips.Kernel.Source.fillTree'), so a
-- word the program states reaches inside the compiled program. Each immediate
-- subdirectory of the staged root is one artifact's tree, which is where its own
-- fills apply; a file lying loose in the root belongs to no artifact and so has
-- no fills, and a marker in it is a defect like any other undeclared one.
fillStagedTree :: FilePath -> FilePath -> [(Text, Text, Text)] -> IO ()
fillStagedTree file root fills = do
  there <- doesDirectoryExist root
  when there $ do
    entries <- listDirectory root
    forM_ entries $ \e -> do
      isDir <- doesDirectoryExist (root </> e)
      let art   = if isDir then T.pack e else ""
          label = if isDir then art else "(staged root)"
          decl  = [ (m, t) | (a, m, t) <- fills, a == art ]
      -- Paths stay RELATIVE to the staged root: the root is a temp dir at the
      -- gate, so an absolute path would name a file the reader cannot look at.
      paths <- if isDir then map (e </>) <$> treeFiles (root </> e) else pure [e]
      texts <- mapM (TIO.readFile . (root </>)) paths
      case fillTree label decl (zip paths texts) of
        Left defects -> die (report
          (T.pack file <> ": the source lips bakes and the values it fills disagree:")
          defects
          ("→ the source tree and its fills are minted together, so rebuild both: "
            <> "lips generate " <> T.pack file))
        Right filled -> forM_ filled $ \(p, t) ->
          when (Just t /= lookup p (zip paths texts)) (TIO.writeFile (root </> p) t)

-- | Every file under a directory, recursively, named relative to it.
treeFiles :: FilePath -> IO [FilePath]
treeFiles dir = do
  entries <- listDirectory dir
  fmap concat $ forM entries $ \e -> do
    isDir <- doesDirectoryExist (dir </> e)
    if isDir then map (e </>) <$> treeFiles (dir </> e) else pure [e]


-- | Stage a language's committed @artifacts@ tree (found under @dir@) into
-- @dst@ (the temp module's @artifacts\/@). A no-op when the language has no
-- artifacts tree, since a program without artifacts stages nothing.
--
-- A copy failure is NOT swallowed: it used to shell out to @cp -rT@ and discard
-- every error, so an unreadable source tree surfaced later as a missing path or
-- a confusing nix eval. Any IO error now propagates, naming the file.
stageFromDisk :: FilePath -> FilePath -> FilePath -> IO ()
stageFromDisk dir file dst = do
  let src = artifactsPathIn dir file
  there <- doesDirectoryExist src
  when there (copyTree src dst)

-- | Everything a realized module names beside itself: the staged source tree and
-- the site its clauses build. Handed to a gate that materializes the module into
-- a temp directory, so what nix evaluates there is what a compiled directory
-- holds.
stageBeside :: FilePath -> FilePath -> Realization -> FilePath -> IO ()
stageBeside dir file rl root = do
  stageFromDisk dir file (root </> "artifacts")
  void (writeSite (T.pack (languageName file)) root rl)

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

-- | How much source each staged tree actually holds, in lines and files. The
-- number that matters for review: an unvouched path is cheap to write and
-- expensive to trust, and only its size says which it is.
stagedSizes :: FilePath -> FilePath -> Grounding -> IO [Text]
stagedSizes dir file g = mapM one (gStaged g)
  where
    one u = do
      let root = artifactsPathIn dir file
      (ls, fs) <- treeSize root
      pure ("  staged tree: " <> subjectDots (uSubject u) <> " holds "
             <> T.pack (show ls) <> " lines in " <> T.pack (show fs)
             <> (if fs == 1 then " file" else " files")
             <> ", vouched by nothing")
    subjectDots (Subject ss) = T.intercalate "." ss

-- | Total lines and file count under a directory, recursively. Zero for a path
-- that is not there, so a program whose tree is missing reports honestly rather
-- than failing here (the staged-source gate is the one that refuses).
treeSize :: FilePath -> IO (Int, Int)
treeSize root = do
  there <- doesDirectoryExist root
  if not there then pure (0, 0) else do
    entries <- listDirectory root
    sizes <- forM entries $ \e -> do
      let path = root </> e
      isDir <- doesDirectoryExist path
      if isDir then treeSize path else do
        body <- TIO.readFile path
        pure (length (T.lines body), 1)
    pure (sum (map fst sizes), sum (map snd sizes))

-- | Copy a directory tree, creating @dst@ and mirroring files and subdirectories
-- (the @cp -rT@ shape: contents of @src@ land directly in @dst@). Loud on any
-- IO error, by not catching it.
copyTree :: FilePath -> FilePath -> IO ()
copyTree src dst = do
  createDirectoryIfMissing True dst
  entries <- listDirectory src
  forM_ entries $ \e -> do
    isDir <- doesDirectoryExist (src </> e)
    if isDir then copyTree (src </> e) (dst </> e)
             else do
               copyFile (src </> e) (dst </> e)
               -- A staged tree is lips's own working copy: source fills WRITE into
               -- it. Copying preserves the mode, and a language folder read from
               -- the nix store is read-only (a compile inside a derivation), so
               -- the copy is made writable or the fill dies with EACCES.
               perms <- getPermissions (dst </> e)
               setPermissions (dst </> e) (setOwnerWritable True perms)

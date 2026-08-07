{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | The shipped runtime data, embedded at build time: the Scheme notation lips
-- emits into, and the contracts a clause may reach the world through.
--
-- This tier exists so the kernel stays a reader. 'Lips.Kernel.Clause.Gate' takes
-- a 'Vocabulary' as an argument and could be handed any other one; what lips
-- happens to ship is a decision of this module, and it is a reviewable asset
-- under @assets/runtime/@ rather than a list inside a gate.
--
-- ONE embed, of the whole directory. A runtime is a DIRECTORY holding a
-- @runtime@ declaration, discovered here rather than listed: adding one is
-- adding a directory, with no edit to this file, which is what makes breadth on
-- that axis cost no code. A per-runtime case would have made the doc's promise
-- false the first time somebody believed it.
--
-- Embedding mirrors 'Lips.Generate.Minting': the nix build copies @assets/@ as
-- a sibling of the sources it compiles, so the relative path resolves the same
-- way under @nix build@ and under a direct @ghc@ from @kernel/@.
module Lips.Runtime
  ( schemeVocabulary
  , guileRuntime
  , runtimes
  , runtimeAsset
  ) where

import           Data.FileEmbed     (embedDir)
import qualified Data.ByteString    as BS
import           Data.List          (sortOn)
import qualified Data.Text.Encoding as TE
import qualified Data.Text          as T
import           System.FilePath    (splitDirectories)

import Lips.Kernel.Clause.Catalogue  (Runtime (..), parseRuntime)
import Lips.Kernel.Clause.Vocabulary (Vocabulary (..), parseContracts, parseVocabulary)

-- | Every file under @assets/runtime@, embedded at build time, keyed by its path
-- relative to that directory (@guile/runtime@, @scheme/contracts@).
runtimeFiles :: [(FilePath, BS.ByteString)]
runtimeFiles = $(embedDir "../assets/runtime")

-- | One shipped file as text, or 'Nothing' when nothing ships under that path.
shipped :: FilePath -> Maybe T.Text
shipped path = TE.decodeUtf8 <$> lookup path runtimeFiles

-- | A shipped file that MUST be there: its absence is a defect in lips's own
-- build, so it fails loud on first use rather than degrading to something empty
-- that would then reject every honest clause.
required :: FilePath -> T.Text
required path =
  maybe (error ("lips ships no " <> path <> " (its assets did not embed)")) id (shipped path)

-- | The Scheme vocabulary with its contracts. A malformed asset is a build-time
-- defect of lips itself, so it fails loud on first use.
schemeVocabulary :: Vocabulary
schemeVocabulary =
  case ( parseVocabulary (required "scheme/vocabulary")
       , parseContracts (required "scheme/contracts") ) of
    (Right v, Right cs) -> v { vContracts = cs }
    (Left e, _)         -> error ("shipped scheme vocabulary is malformed: " <> T.unpack e)
    (_, Left e)         -> error ("shipped scheme contracts are malformed: " <> T.unpack e)

-- | Every runtime lips ships adapters for: every directory under
-- @assets/runtime@ holding a @runtime@ declaration. Ordered by name, so what a
-- caller (or a test) sees does not depend on the embedding order.
--
-- A directory WITHOUT that file is not a runtime and is skipped, which is how
-- @scheme/@ (a notation, shared by every runtime that speaks it) sits beside
-- them. A directory WITH a malformed one is a defect in lips's own assets and
-- fails loud.
runtimes :: [Runtime]
runtimes = sortOn rName
  [ either (\e -> error ("shipped " <> T.unpack dir <> " runtime is malformed: " <> T.unpack e))
           id
           (parseRuntime dir (TE.decodeUtf8 body))
  | (path, body) <- runtimeFiles
  , [d, "runtime"] <- [splitDirectories path]
  , let dir = T.pack d
  ]

-- | GNU Guile: the first runtime, and the one the falsifier ran on. Named for the
-- callers that want exactly it (the suite, the mint prompt); everything that
-- merely needs "the runtimes lips ships" takes 'runtimes'.
guileRuntime :: Runtime
guileRuntime = case [ r | r <- runtimes, rName r == "guile" ] of
  (r : _) -> r
  []      -> error "lips ships no guile runtime"

-- | One file a runtime ships (an adapter, its site builder), by runtime name and
-- file name. 'Nothing' when a runtime declares a file its directory does not
-- hold, which is a defect in lips's own assets and fails loud at the caller.
runtimeAsset :: T.Text -> FilePath -> Maybe T.Text
runtimeAsset name file = shipped (T.unpack name <> "/" <> file)

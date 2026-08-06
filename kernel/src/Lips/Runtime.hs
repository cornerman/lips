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
-- Embedding mirrors 'Lips.Generate.Minting': the nix build copies @assets/@ as
-- a sibling of the sources it compiles, so the relative path resolves the same
-- way under @nix build@ and under a direct @ghc@ from @kernel/@.
module Lips.Runtime
  ( schemeVocabulary
  , guileRuntime
  , runtimes
  , runtimeAsset
  ) where

import           Data.FileEmbed     (embedDir, embedStringFile)
import qualified Data.ByteString    as BS
import qualified Data.Text.Encoding as TE
import qualified Data.Text      as T

import Lips.Kernel.Clause.Catalogue  (Runtime, parseRuntime)
import Lips.Kernel.Clause.Vocabulary (Vocabulary (..), parseContracts, parseVocabulary)

-- | The Scheme vocabulary with its contracts. A malformed asset is a build-time
-- defect of lips itself, so it fails loud on first use rather than degrading to
-- an empty vocabulary that would reject every honest clause.
schemeVocabulary :: Vocabulary
schemeVocabulary =
  case (parseVocabulary formsText, parseContracts contractsText) of
    (Right v, Right cs) -> v { vContracts = cs }
    (Left e, _)         -> error ("shipped scheme vocabulary is malformed: " <> T.unpack e)
    (_, Left e)         -> error ("shipped scheme contracts are malformed: " <> T.unpack e)

formsText :: T.Text
formsText = T.pack $(embedStringFile "../assets/runtime/scheme/vocabulary")

contractsText :: T.Text
contractsText = T.pack $(embedStringFile "../assets/runtime/scheme/contracts")

-- | Every runtime lips ships adapters for. One today; adding another is adding a
-- directory under @assets\/runtime\/@, which is why breadth on this axis costs
-- no kernel change.
runtimes :: [Runtime]
runtimes = [guileRuntime]

-- | GNU Guile: the first runtime, and the one the falsifier ran on.
guileRuntime :: Runtime
guileRuntime = case parseRuntime "guile" guileText of
  Right r -> r
  Left e  -> error ("shipped guile runtime is malformed: " <> T.unpack e)

guileText :: T.Text
guileText = T.pack $(embedStringFile "../assets/runtime/guile/runtime")

-- | One file a runtime ships (an adapter, its site builder), by runtime name and
-- file name. 'Nothing' when a runtime declares a file its directory does not
-- hold, which is a defect in lips's own assets and fails loud at the caller.
runtimeAsset :: T.Text -> FilePath -> Maybe T.Text
runtimeAsset "guile" name = TE.decodeUtf8 <$> lookup name guileAssets
runtimeAsset _ _ = Nothing

-- | Every file under the guile runtime directory, embedded at build time. A file
-- added to the directory is shipped without a code change here, which is what
-- keeps adding a runtime a matter of data.
guileAssets :: [(FilePath, BS.ByteString)]
guileAssets = $(embedDir "../assets/runtime/guile")

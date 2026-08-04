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
  ) where

import           Data.FileEmbed (embedStringFile)
import qualified Data.Text      as T

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

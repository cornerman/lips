{-# LANGUAGE OverloadedStrings #-}

-- | The type a hole coerces a program token into, shared by every closed value
-- grammar the kernel emits into.
--
-- It lives alone because there are now two such grammars and they must agree on
-- what @\<value:int\>@ means: 'Lips.Kernel.Engine.Value' (the Nix value algebra
-- minus computation) and 'Lips.Kernel.Sexp' (the clause grammar). A single
-- definition is the only way a hole written in a program cannot mean two things.
--
-- Not every type is meaningful in every grammar: 'HPath' and 'HPkg' name Nix
-- notions, so the clause grammar refuses them loudly rather than inventing a
-- Scheme reading for them.
module Lips.Kernel.Hole
  ( HoleType (..)
  , parseHoleType
  , holeTypeText
  ) where

import Data.Text (Text)

-- | The type a bare (non-string) hole coerces its program token into. String
-- holes need no tag: inside a string the value is always text. 'HPkg' turns a
-- program token into a @pkgs.<token>@ derivation reference, so a package whose
-- name comes from the program can still be named without computation.
data HoleType = HInt | HBool | HFloat | HPath | HPkg
  deriving (Eq, Show)

holeTypeText :: HoleType -> Text
holeTypeText HInt   = "int"
holeTypeText HBool  = "bool"
holeTypeText HFloat = "float"
holeTypeText HPath  = "path"
holeTypeText HPkg   = "pkg"

parseHoleType :: Text -> Maybe HoleType
parseHoleType "int"   = Just HInt
parseHoleType "bool"  = Just HBool
parseHoleType "float" = Just HFloat
parseHoleType "path"  = Just HPath
parseHoleType "pkg"   = Just HPkg
parseHoleType _       = Nothing

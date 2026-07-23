{-# LANGUAGE OverloadedStrings #-}

-- | Pure parser for @generate@ CLI arguments, in the library so the
-- conformance suite can pin it. Flags (@--target@, @--confidence@, @--model@)
-- may appear in any position; then @[model] <program>...@. A malformed flag,
-- a duplicate @--model@, or no program fails loud (returns Nothing).
module Lips.Generate.Args
  ( parseGenerate
  ) where

import System.FilePath (takeFileName)
import Text.Read       (readMaybe)

import Lips.Nix.Target (Target, defaultTarget, parseTarget)

-- | Parse @generate@ arguments given the default confidence. Yields the target
-- world, the confidence threshold, an optional model id, and the program
-- files. The @--model@ flag wins outright: every positional is then a program
-- file. Without the flag, a leading positional is taken as the model when it
-- looks like a model id (a @provider/id@ whose final component has no dot) and
-- at least one program follows; every other positional is a program file. No
-- model at all: omit it so pi's own configured default applies.
parseGenerate :: Double -> [String] -> Maybe (Target, Double, Maybe String, [FilePath])
parseGenerate defConf = go Nothing Nothing Nothing []
  where
    go tgt conf model pos ("--target" : v : rest) =
      case parseTarget v of
        Just t | Nothing <- tgt -> go (Just t) conf model pos rest  -- set once
        _                       -> Nothing                          -- unknown or duplicate
    go _ _ _ _ ["--target"] = Nothing
    go tgt conf model pos ("--confidence" : v : rest)
      | Nothing <- conf, Just c <- readMaybe v, c >= 0, c <= 1 = go tgt (Just c) model pos rest
      | otherwise                                              = Nothing
    go _ _ _ _ ["--confidence"] = Nothing
    go tgt conf Nothing pos ("--model" : v : rest) = go tgt conf (Just v) pos rest
    go _ _ (Just _) _ ("--model" : _ : _) = Nothing  -- duplicate --model: fail loud, not last-wins
    go _ _ _ _ ["--model"] = Nothing
    go tgt conf model pos (a : rest) = go tgt conf model (pos ++ [a]) rest
    go tgt conf model pos [] =
      finish (maybe defaultTarget id tgt) (maybe defConf id conf) model pos
    finish _ _ _ []          = Nothing
    finish t c (Just m) ps   = Just (t, c, Just m, ps)
    finish t c Nothing (a : rest)
      | not (null rest), looksLikeModel a = Just (t, c, Just a, rest)
      | otherwise                         = Just (t, c, Nothing, a : rest)
    looksLikeModel s = '/' `elem` s && '.' `notElem` takeFileName s

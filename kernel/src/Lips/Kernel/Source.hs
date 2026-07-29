{-# LANGUAGE OverloadedStrings #-}

-- | Source fills: how a value the PROGRAM states reaches inside an artifact's
-- baked source.
--
-- An artifact's source tree is minted once and then committed verbatim, so
-- without this a program word could reach the builder (an arg) but never the
-- code: a command name had to be spelled twice, once in the program and once,
-- frozen, inside @go.mod@. Live mints answered that with shell smuggled through
-- a build argument (a @postInstall@ loop renaming the binary), which is exactly
-- the workaround the value grammar exists to forbid -- so the hole belongs in
-- the format (kernel invariant 4).
--
-- The grammar is two halves that must agree, and the kernel checks both
-- directions so neither half can drift silently:
--
--   * the engine DECLARES a fill per artifact, @artifact.\<name\>.fill.\<marker\>@,
--     whose rhs is an ordinary value in the closed grammar (so every hole
--     mechanism -- @\<value\>@, @\<value.N\>@, a capture -- already applies, and
--     computation stays unrepresentable);
--   * the staged source NAMES the marker as @\@marker\@@, the nixpkgs
--     @substituteAll@ spelling, at every place the value belongs.
--
-- Filling happens where the tree is staged (compile and the gates), never in
-- the committed tree: the committed source keeps its markers, so it stays the
-- template it is, and the compiled source is derived like every other output.
module Lips.Kernel.Source
  ( sourceMarkers
  , validMarker
  , fillTree
  ) where

import           Data.Char       (isAlpha, isAlphaNum)
import           Data.List       (nub)

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

-- | The markers a source text names, in order of appearance, without
-- duplicates. A marker is @\@name\@@ where the name starts with a letter and
-- carries letters, digits, @_@ or @-@ -- narrow on purpose, so an @\@@ that is
-- ordinary source text (a Python decorator, a Makefile recipe prefix, an email
-- address) is not read as a marker.
sourceMarkers :: Text -> [Text]
sourceMarkers = nub . go
  where
    go t = case T.uncons (T.dropWhile (/= '@') t) of
      Nothing      -> []
      Just (_, r0) ->
        let (name, r1) = T.span markerChar r0
         in case T.uncons r1 of
              Just ('@', r2)
                | not (T.null name), isAlpha (T.head name) -> name : go r2
              -- Not a marker: resume the scan after this @, so a stray @ never
              -- swallows the rest of the file.
              _ -> go r0

-- | A marker name's characters: narrow, so ordinary source text carrying an @
-- is never read as a marker.
markerChar :: Char -> Bool
markerChar c = isAlphaNum c || c == '_' || c == '-'

-- | Could a source file name this marker at all? The declaring half (an engine
-- subject segment) is free-form text, so a name no @\@marker\@@ could ever
-- spell is rejected where it is declared rather than reported later as unused.
validMarker :: Text -> Bool
validMarker m = case T.uncons m of
  Just (c, rest) -> isAlpha c && T.all markerChar rest
  Nothing        -> False

-- | Fill one artifact's staged source tree from its declared fills. Both
-- directions must agree, or the caller gets a plain-words refusal per defect:
--
--   * a declared fill no source file names is a value that reaches nothing --
--     the program's word would govern nothing while every gate stayed green;
--   * a marker in a source file that no fill declares would ship @\@name\@@
--     verbatim into the compiled program, a silently broken build.
--
-- On success every marker is replaced by its text in every file. Pure: the
-- caller reads and writes the files.
fillTree :: Text -> [(Text, Text)] -> [(FilePath, Text)] -> Either [Text] [(FilePath, Text)]
fillTree artifact declared files
  | not (null defects) = Left defects
  | otherwise          = Right [ (p, substitute t) | (p, t) <- files ]
  where
    decls = Map.fromList declared
    found = [ (p, m) | (p, t) <- files, m <- sourceMarkers t ]
    unused =
      [ "artifact " <> artifact <> " declares fill " <> m
          <> " but no source file names @" <> m <> "@"
      | m <- nub (map fst declared), m `notElem` map snd found ]
    undeclared =
      [ "artifact " <> artifact <> ": " <> T.pack p <> " names @" <> m
          <> "@, which the engine never declares as a fill"
      | (p, m) <- nub found, not (Map.member m decls) ]
    defects = unused ++ undeclared
    -- ONE pass, so a fill's own text is never rescanned: a value that happens to
    -- contain @other@ lands verbatim instead of substituting a second time (a
    -- program word must not be able to inject a marker).
    substitute t = case T.breakOn "@" t of
      (before, rest) -> case T.uncons rest of
        Nothing        -> before
        Just (_, r0)   ->
          let (name, r1) = T.span markerChar r0
           in case (T.uncons r1, Map.lookup name decls) of
                (Just ('@', r2), Just v) -> before <> v <> substitute r2
                _                        -> before <> "@" <> substitute r0

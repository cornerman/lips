{-# LANGUAGE OverloadedStrings #-}

-- | Which runtime a clause set runs on, computed rather than chosen.
--
-- Two sets meet here and neither is guessed. The CONTRACTS come from the clauses
-- ('Lips.Kernel.Clause.Gate.reachedContracts'), so they are derived from the
-- program and never stated. The PROPERTIES come from the author, because "runs
-- in a browser" or "is one static binary" is intent that lives nowhere else.
-- A runtime covers a program when it provides every contract and has every
-- property; the catalogue is data, maintained per runtime, exactly as nixpkgs is
-- data maintained per package.
--
-- The model never decides this, and cannot: a clause set names contracts only,
-- so the choice happens at compile time, after the mint is gone. Switching
-- runtime relinks adapters instead of re-minting, which is what lets one core
-- serve several places at once.
--
-- 'coveringRuntime' fails rather than guesses, in both directions. Nothing covering names
-- what is missing. Several covering lists the candidates, because an author
-- adding one requirement is cheaper than lips picking silently.
module Lips.Kernel.Clause.Catalogue
  ( Runtime (..)
  , parseRuntime
  , coveringRuntime
  , siteFile
  , clauseClaimsFile
  ) where

import           Data.List (intercalate)
import           Data.Text (Text)
import qualified Data.Text as T

-- | One place a clause set can run. @rFiles@ are the adapter files linked
-- before the core, in this order; @rClaimFiles@ replace the effect adapters when
-- a claim runs the core offline.
data Runtime = Runtime
  { rName       :: Text
  , rProperties :: [Text]
  , rProvides   :: [Text]
  , rPackages   :: [Text]
  , rFiles      :: [FilePath]
    -- ^ The PURE adapters, linked for every purpose: a run and a claim both need
    -- them, and neither touches the world.
  , rEffectFiles :: [FilePath]
    -- ^ The adapters that touch the world, linked for a real run only.
  , rClaimFiles :: [FilePath]
    -- ^ Linked INSTEAD of 'rEffectFiles' when a claim judges the core offline.
    -- Instead, not beside: loading the real effects and then shadowing them would
    -- work only by last-definition-wins, and any load-time effect would fire.
  , rEntry      :: Text
    -- ^ The last line of the assembled file: how this runtime hands a program
    -- its arguments and starts it. Data, because lips must not know that Guile
    -- spells it @command-line@ and something else spells it otherwise.
  , rBuild      :: FilePath
    -- ^ The Nix file that turns the linked site into a derivation. It takes
    -- @{ pkgs, name, src }@ and returns one; lips copies it and calls it,
    -- knowing nothing else about it.
  }
  deriving (Eq, Show)

-- | Parse a runtime declaration. The name comes from the caller (the directory
-- the file sits in), so the filesystem stays the index and a file cannot claim a
-- name its location contradicts.
parseRuntime :: Text -> Text -> Either Text Runtime
parseRuntime name txt = do
  decls <- traverse parseLine (meaningfulLines txt)
  Right (foldr add (Runtime name [] [] [] [] [] [] "" "") (concat decls))
  where
    add (DProperty p) r = r { rProperties = p : rProperties r }
    add (DProvides c) r = r { rProvides = c : rProvides r }
    add (DPackage p) r = r { rPackages = p : rPackages r }
    add (DFile f) r = r { rFiles = f : rFiles r }
    add (DEffectFile f) r = r { rEffectFiles = f : rEffectFiles r }
    add (DClaimFile f) r = r { rClaimFiles = f : rClaimFiles r }
    add (DEntry e) r = r { rEntry = e }
    add (DBuild f) r = r { rBuild = f }

data Decl
  = DProperty Text | DProvides Text | DPackage Text | DFile FilePath | DClaimFile FilePath
  | DEffectFile FilePath | DEntry Text | DBuild FilePath

meaningfulLines :: Text -> [Text]
meaningfulLines =
  filter (\l -> not (T.null l) && not ("#" `T.isPrefixOf` l))
    . map T.strip
    . T.lines

parseLine :: Text -> Either Text [Decl]
parseLine line = case T.words line of
  ("property" : ps) | not (null ps) -> Right (map DProperty ps)
  ("provides" : cs) | not (null cs) -> Right (map DProvides cs)
  ("package" : ps) | not (null ps) -> Right (map DPackage ps)
  ("file" : fs) | not (null fs) -> Right (map (DFile . T.unpack) fs)
  ("effect-file" : fs) | not (null fs) -> Right (map (DEffectFile . T.unpack) fs)
  ("claim-file" : fs) | not (null fs) -> Right (map (DClaimFile . T.unpack) fs)
  -- The entry keeps its whole tail: it is one expression in the runtime's own
  -- notation, and splitting it on spaces would destroy it.
  ("entry" : _ : _) -> Right [DEntry (T.strip (T.drop 5 (T.stripStart line)))]
  ["build", f] -> Right [DBuild (T.unpack f)]
  _ -> Left ("a runtime declares property, provides, package, file, effect-file,\
             \ claim-file, entry or build, but this line reads: " <> line)

-- | The one runtime covering these contracts and properties, or why none does.
-- A required property carries the author's reason for it, which travels into the
-- failure: told "no runtime has the property browser", an author still has to
-- remember why they asked, and the reason is the sentence they wrote.
coveringRuntime :: [Runtime] -> [Text] -> [(Text, Text)] -> Either Text Runtime
coveringRuntime runtimes needed requiredWith = case filter covers runtimes of
  [r] -> Right r
  []  -> Left noneCovers
  many -> Left ("several runtimes cover this program ("
                  <> commas (map rName many)
                  <> "), so lips will not pick for you. State one more\
                     \ requirement, or name the runtime you mean.")
  where
    required = map fst requiredWith
    covers r = all (`elem` rProvides r) needed && all (`elem` rProperties r) required

    noneCovers = case (unprovided, unmet) of
      (c : _, _) -> "no runtime provides the contract " <> c
                      <> ", which this program's behaviour needs. Adapters known: "
                      <> commas (map rName runtimes)
      (_, p : _) -> "no runtime has the property " <> p
                      <> ", which this program requires ("
                      <> maybe "no reason stated" id (lookup p requiredWith)
                      <> "). Runtimes known: " <> commas (map rName runtimes)
      _ -> "no runtime covers this program, and every contract and property is\
           \ met by some runtime, so no single one meets them together. Requirements: "
             <> commas required
    -- A contract, or a property, that not one runtime offers: the honest name to
    -- report, since a partial cover is confusing to read.
    unprovided = [ c | c <- needed, not (any (elem c . rProvides) runtimes) ]
    unmet = [ p | p <- required, not (any (elem p . rProperties) runtimes) ]

commas :: [Text] -> Text
commas = T.pack . intercalate ", " . map T.unpack

-- | The assembled file a runtime runs: its adapters loaded in declared order,
-- then the minted core, then the entry the runtime declares. Text, because a
-- runtime consumes a file; the structure lives in the decisions the core was
-- rendered from.
--
-- The kernel writes @(load "x")@ and nothing else, so the only thing it knows
-- about the notation is that a file can be loaded by name. Which files, in which
-- order, and how the program starts are all the runtime's own declarations.
siteFile :: Runtime -> [FilePath] -> Text
siteFile rt files = T.unlines
  ([ "; Assembled by lips. Do not edit: edit the program, or the runtime's adapters."
   , "; Adapters first, then the minted core, then this runtime's entry."
   ]
    <> [ "(load \"" <> T.pack f <> "\")" | f <- files ]
    <> [ rEntry rt ])

-- | The claims file a runtime runs: its pure adapters, then the adapters and
-- harness it substitutes for a claim (lists instead of stdin, a verdict printer),
-- then the minted core, then the claim forms, then the harness's own last word.
--
-- Same shape as 'siteFile' and the same ignorance: lips writes @(load "x")@ and
-- pastes the forms it was given. Which files, in which order, and how a failure
-- becomes an exit code are the runtime's declarations.
clauseClaimsFile :: [FilePath] -> [Text] -> Text
clauseClaimsFile files forms = T.unlines
  ([ "; Assembled by lips. The program's own behaviour, judged offline: no"
   , "; derivation to build, no machine to boot, no binary to compile."
   ]
    <> [ "(load \"" <> T.pack f <> "\")" | f <- files ]
    <> forms
    <> [ "(claims-done)" ])

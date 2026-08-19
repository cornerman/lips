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
  , Harness (..)
  , parseRuntime
  , coveringRuntime
  , siteFile
  , clauseClaimsFile
  , entryDemand
  , entryFor
  ) where

import           Data.List (intercalate)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Sexp (SExp (..), parseSexp)

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
  , rHarness    :: Harness
    -- ^ The words this runtime's harness answers to. lips owns the SHAPES (a file
    -- is loaded by name; a claim is judged by id, expression and expected value)
    -- and never the words, exactly as with 'rEntry'.
  }
  deriving (Eq, Show)

-- | The four words lips writes into a claims file, and the one it writes to load
-- a file. Declared per runtime for the same reason the DEFINING word is declared
-- per notation: @claims-done@ and @load@ are facts about Scheme, and the kernel
-- must not hold one. What the kernel owns is that a file is loaded by name and a
-- claim is judged by id, expression and expected value.
data Harness = Harness
  { hLoad      :: Text  -- ^ @(\<load\> "file")@
  , hFeedArgs  :: Text  -- ^ @(\<feed-args\> (list ...))@: the command line to serve
  , hFeedLines :: Text  -- ^ @(\<feed-lines\> (list ...))@: the input to serve
  , hJudge     :: Text  -- ^ @(\<claim\> "id" \<expr\> \<want\>)@
  , hDone      :: Text  -- ^ @(\<claims-done\>)@: the last form, which sets the status
  , hList      :: Text  -- ^ how this notation builds the list a feed is given
  }
  deriving (Eq, Show)

noHarness :: Harness
noHarness = Harness "" "" "" "" "" ""

-- | Parse a runtime declaration. The name comes from the caller (the directory
-- the file sits in), so the filesystem stays the index and a file cannot claim a
-- name its location contradicts.
parseRuntime :: Text -> Text -> Either Text Runtime
parseRuntime name txt = do
  decls <- traverse parseLine (meaningfulLines txt)
  let rt = foldr add (Runtime name [] [] [] [] [] [] "" "" noHarness) (concat decls)
  -- A runtime missing one of these fails HERE, naming the declaration, rather
  -- than at the door that needed it: an empty entry reads as "not a call" and an
  -- empty builder as "lips ships no file", neither of which names the cause.
  mapM_ (require rt)
    [ ("entry", rEntry), ("build", T.pack . rBuild)
    , ("harness-load", hLoad . rHarness), ("harness-feed-args", hFeedArgs . rHarness)
    , ("harness-feed-lines", hFeedLines . rHarness), ("harness-judge", hJudge . rHarness)
    , ("harness-done", hDone . rHarness), ("harness-list", hList . rHarness) ]
  Right rt
  where
    require rt (what, f)
      | T.null (f rt) = Left ("the " <> name <> " runtime declares no " <> what)
      | otherwise     = Right ()
    add (DProperty p) r = r { rProperties = p : rProperties r }
    add (DProvides c) r = r { rProvides = c : rProvides r }
    add (DPackage p) r = r { rPackages = p : rPackages r }
    add (DFile f) r = r { rFiles = f : rFiles r }
    add (DEffectFile f) r = r { rEffectFiles = f : rEffectFiles r }
    add (DClaimFile f) r = r { rClaimFiles = f : rClaimFiles r }
    add (DEntry e) r = r { rEntry = e }
    add (DBuild f) r = r { rBuild = f }
    add (DHarness g) r = r { rHarness = g (rHarness r) }

data Decl
  = DProperty Text | DProvides Text | DPackage Text | DFile FilePath | DClaimFile FilePath
  | DEffectFile FilePath | DEntry Text | DBuild FilePath
  | DHarness (Harness -> Harness)

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
  ["harness-load", w] -> harness (\g -> g { hLoad = w })
  ["harness-feed-args", w] -> harness (\g -> g { hFeedArgs = w })
  ["harness-feed-lines", w] -> harness (\g -> g { hFeedLines = w })
  ["harness-judge", w] -> harness (\g -> g { hJudge = w })
  ["harness-done", w] -> harness (\g -> g { hDone = w })
  ["harness-list", w] -> harness (\g -> g { hList = w })
  _ -> Left ("a runtime declares property, provides, package, file, effect-file,\
             \ claim-file, entry, build or harness-*, but this line reads: " <> line)
  where harness f = Right [DHarness f]

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
    <> map (loadForm rt) files
    <> [ rEntry rt ])

-- | @(\<load\> "file")@ in the runtime's own word for loading.
loadForm :: Runtime -> FilePath -> Text
loadForm rt f = "(" <> hLoad (rHarness rt) <> " \"" <> T.pack f <> "\")"

-- | The claims file a runtime runs: its pure adapters, then the adapters and
-- harness it substitutes for a claim (lists instead of stdin, a verdict printer),
-- then the minted core, then the claim forms, then the harness's own last word.
--
-- Same shape as 'siteFile' and the same ignorance: lips writes @(load "x")@ and
-- pastes the forms it was given. Which files, in which order, and how a failure
-- becomes an exit code are the runtime's declarations.
clauseClaimsFile :: Runtime -> [FilePath] -> [Text] -> Text
clauseClaimsFile rt files forms = T.unlines
  ([ "; Assembled by lips. The program's own behaviour, judged offline: no"
   , "; derivation to build, no machine to boot, no binary to compile."
   ]
    <> map (loadForm rt) files
    <> forms
    <> [ "(" <> hDone (rHarness rt) <> ")" ])

-- | What the runtime's entry demands of the minted core: the definition it calls
-- and how many arguments it passes. Derived from the entry expression itself, so
-- the requirement cannot drift from the call the way a second declaration would.
--
-- @entry (main)@ demands @main@ with no parameters; @entry (main (arguments))@
-- demands one. A 'Left' is a malformed entry, which is a defect in lips's own
-- runtime declaration and says so.
--
-- Without this check the entry and the core can disagree with every gate green:
-- two live mints defined @(define (main) ...)@ against an entry passing one
-- argument, and both binaries died at runtime with "wrong number of arguments".
-- | Fill a runtime's entry with the language whose site is being assembled.
-- Namespacing means every clause carries its language's prefix, so no language
-- can define a bare @main@; the runtime therefore spells its entry with a hole
-- (@entry (\<language\>-main)@) exactly as every other lips value carries one,
-- and keeps ownership of how it starts a program. The kernel substitutes a name
-- and learns no word: @main@ is the runtime's, not the kernel's.
entryFor :: Text -> Runtime -> Runtime
entryFor lang rt = rt { rEntry = T.replace "<language>" lang (rEntry rt) }

entryDemand :: Runtime -> Either Text (Text, Int)
entryDemand rt = case parseSexp (rEntry rt) of
  Right (SList (SSym n : args)) -> Right (n, length args)
  Right (SSym n)                -> Right (n, 0)
  _ -> Left ("the " <> rName rt <> " runtime's entry is not a call: " <> rEntry rt)

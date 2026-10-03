{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI (crystallization plan).
--
-- Every path it reads or writes comes from 'Lips.Identity': a program sits
-- alone beside a folder named after its language, which holds everything the
-- machine wrote (see that module for the shape).
--
--   * @lips generate [model] \<program\>@ is the one AI step: the model mints a
--     /language/ (patterns) for the loose program; the kernel crystallizes the
--     program with it and validates by a full run; only then are the language
--     (@\<language\>/\<language\>.lang@), the crystal witness
--     (@\<language\>/out/\<instance\>.decisions@), and the generation record
--     written.
--   * @lips compile \<program\>@ takes the loose program directly. It verifies
--     the committed @.expect@ contract, then crystallizes with the language's
--     @.lang@ and realizes into a DIRECTORY (@default.nix@ plus a staged
--     @artifacts/@), deterministically, with no AI. If the language is
--     missing, the program escaped it, or the module drops a promised value,
--     it fails loud (and names @generate@ where that is the remedy).
--   * @lips check \<program\>@ is the gate alone: diagnostics plus the
--     committed @.expect@ contract against the realized module, offline.
--   * Running is not a lips verb: @compile@ prints the stock @nix@ commands
--     over the compiled directory, and the user picks one.
module Main (main) where

import           Control.Concurrent (forkIO, threadDelay)
import           Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import           Control.Exception  (IOException, SomeException, bracket, catch, finally, fromException, try)
import           Control.Monad      (forM, forM_, unless, when, void)
import           Data.IORef         (IORef, newIORef, modifyIORef', readIORef, writeIORef)
import           Data.Bifunctor     (first)
import           Data.List          (intercalate, nub)
import           Data.Maybe         (fromMaybe, isJust)
import           Data.Time.Clock.POSIX (POSIXTime, getPOSIXTime)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getEnvironment, getExecutablePath, lookupEnv)
import           System.Exit        (ExitCode (..), exitFailure, exitWith)
import           GHC.IO.Encoding     (setLocaleEncoding)
import           System.IO          (BufferMode (..), hClose, hGetBuffering, hGetChar,
                                     hGetContents, hGetEcho, hIsEOF, hIsTerminalDevice,
                                     hReady, hSetBuffering, hSetEcho, hSetEncoding,
                                     stderr, stdin, stdout, utf8)
import           Control.Monad.Trans.Class  (lift)
import           Control.Monad.Trans.Except (runExceptT, throwE)
import           System.Directory   (createDirectoryIfMissing, doesDirectoryExist, doesFileExist,
                                     doesPathExist, getModificationTime,
                                     removePathForcibly)
import           System.FilePath    (takeDirectory, (</>))
import           System.Process     (CreateProcess (..), StdStream (..), callProcess, createProcess, proc,
                                     readProcessWithExitCode, waitForProcess)

import           Lips.Kernel.Engine.Aggregate   (assembleWith, mergeModeOf)
import           Lips.Kernel.Engine.Data       (Engine (..), IgnoreSpec (..), bindSelf, emitTemplate, keepsRepeats, renderAttrPath, toDemand, toRule)
import           Lips.Generate.Readme   (renderReadme)
import           Lips.Identity                 (watchedFiles, timingPathIn, languageTimingPathIn, requireProgram, readmePathIn, languageRecordPathIn, languageReadmePathIn, languageGapPathIn, gapPathIn, artifactsPathIn, compiledPath, decisionsPath, directionPath, expectPathIn, generationPathIn, grammarPathIn, instanceName, langDir, languageName, outDir, resolveLangDir, rulesPathIn, worldDirIn, worldPathIn)
import           Lips.Language                 (exportedClauses, grammarIsFrozen, mintTargets, mintedWorlds, orphanIgnores, soleWorld)
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), CheckOpts (..), OptionsOpts (..), ExportsOpts (..), WorldWhat (..), cliParserInfo, cliPrefs, defaultTargetName)
import           Lips.Cli.Output        (die, note, phaseLog, report, say, sayAnswer, setState, step, tshow)
import           Lips.Gate              (ExpectFail (..), artifactGate, claimGate,
                                        groundExpectFaults,
                                        clauseClaimGate, mintClaimGate, runExpects,
                                        stagedGate, worldGate)
import           Lips.Stage             (stageBeside,
                                         withTempDir, writeCompiled, writeSite)
import           Lips.Schema            (assertOptionsAdmissible, ensureOptionSchema,
                                         optionsQuery)
import           Lips.Report            (Failure (..), demandGenerateFail, emptySubmission, heldWorldReport, inferredWorldsLine, severalWorldsReport,
                                         committedSourceReport, failureReport, mintedSourceReport, noSubmission, unpinnedGlueReport,
                                         gapArtifact, nixEvalFailed, nixMissing, plural,
                                         printFail, refusalReport, renderDiagnosis,
                                         renderParseError, unanswerableReport, unansweredReport,
                                         uncheckableReport, unportableReport, unreadable, validationReport)
import           Options.Applicative    (customExecParser)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Draft    (DraftTree (..), materializeDraft, splitEngine)
import           Lips.Generate.Minting  (EngineItem (..), Gap (..), ItemCandidate (..), appendOnlyViolations, assemble, itemsFor, carriesEngineMeaning, mergeGrammar, mergeReply, replyLinesOf, touchedIds, expectsOf, gapsOf, parseEngineCandidates, promptWithDirection, reportOf, sourcesOf, uncheckableExpects, unplaceableClaims)
import           Lips.Generate.PiJson   (PiEvent (..), PiReply (..), abbreviate, parsePiReply,
                                         progressEvent, resultSummary)
import           Lips.Generate.Stats    (MintStats (..), renderStats, verdictOf)
import           Lips.Generate.Record   (corpusText, genId, record,
                                         recordedSchemaFor, recordedWorld, recordedWorldPin, renderStampFault, stampFaults, worldHash,
                                         worldSchemaPin)
import           Lips.Kernel.Decision
import qualified Lips.Kernel.Base       as Base
import           Lips.Kernel.Expect     (Compat (..), Expect (..), compatSlug, readExpect, rebless, renderExpect, smallestCompat)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Run
import           Lips.Kernel.Grounding  (Grounding (..), grounding, groundingReport)
import           Lips.Runtime            (schemeVocabulary)
import           Lips.Kernel.Clause.Vocabulary (withLent)
import           Lips.Kernel.Lang.Crystallize  (LineOutcome (..), crystallize)

import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..), diagnose)
import           Lips.Kernel.Lang.Store         (EngineData (..), readLang, renderLang)
import           Lips.Kernel.Engine.Answerable (unanswerableDemands)
import           Lips.Kernel.Engine.Gate       (engineViolations, unholdableExpects, unholdableProblem)
import           Lips.Nix.Flake                (Nixpkgs, compiledNixpkgs, runCommands)
import           Lips.World                     (World (..), parseWorld)
import           Lips.World.Resolve            (builtinNames, localWorldNames, resolveWorld, resolveWorldFrom)
import           Lips.World.Check               (SlotFault (..), checkNixSlots)
import           Lips.Lsp.Server               (runLsp)

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

-- | A minted language is admitted only if every pattern is at least this
-- certain; otherwise generate fails loud (deduce-or-fail), writing nothing.
-- Overridable per invocation with @--confidence@; the chosen value is pinned
-- into the generation record.
defaultConfidence :: Double
defaultConfidence = 0.7

main :: IO ()
main = do
  -- lips' messages carry non-ASCII (the "→" every remedy line opens with), and
  -- the handle encoding otherwise follows the ambient locale: under LANG=C a
  -- write would die with "cannot encode character", turning a helpful error
  -- into a crash. Pin UTF-8 so what lips prints does not depend on the
  -- environment it is run from. (@lsp@ sets its own binary mode afterwards.)
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  -- Both streams line-buffered, so what lips says arrives in the order it said
  -- it. Redirected to a file or a pipe, GHC would buffer stdout in blocks and
  -- a progress line on stderr would land in the middle of an answer on stdout
  -- (observed: a diagnosis table cut a verdict line in half).
  mapM_ (`hSetBuffering` LineBuffering) [stdout, stderr]
  -- Every FILE lips reads is UTF-8 too, and a committed record legitimately
  -- carries non-ASCII (a .generation embeds the mint prompt, em dashes and all).
  -- Without this the encoding of a READ follows the ambient locale, so the same
  -- committed engine decodes under LANG=C.UTF-8 and throws under LANG unset --
  -- which is exactly the environment a nix build runs in. That failure was
  -- silent where a reader treats "unreadable" as "absent", and it compiled a
  -- kubenix program into a NixOS flake. Pin it once, here.
  setLocaleEncoding utf8
  cmd <- customExecParser cliPrefs (cliParserInfo defaultConfidence)
  case cmd of
    Generate go -> do
      -- Every world is resolved before anything else runs: a name that names
      -- nothing must cost no model call and write no file, and that has to hold
      -- for the LAST name in the list as much as the first. Beside the FIRST
      -- program, which is the one whose language folder the mint writes; the
      -- CLI parser guarantees there is one.
      let rep  = case goFiles go of
                   (f : _) -> f
                   []      -> "."
          base = takeDirectory rep
          lang = T.pack (languageName rep)
      -- One language per invocation: the grammar is shared, so mixed extensions
      -- would mean two languages. Refused first, since every later question
      -- (which worlds, which grammar) is asked of ONE language folder.
      case [ f | f <- goFiles go, languageName f /= languageName rep ] of
        (_ : _) -> die (report
          "lips generate mints ONE language at a time, but these programs are not all the same language."
          [ T.pack f <> " is ." <> T.pack (languageName f) | f <- goFiles go ]
          ("→ generate the ." <> lang <> " programs together, other languages separately."))
        [] -> pure ()
      -- With no -t, the worlds come from the language folder, so a re-mint
      -- writes back what is committed and never grows a world nobody named.
      held <- mintedWorlds (langDir rep) rep
      names <- case mintTargets defaultTargetName (goTarget go) held of
        Right ws -> pure ws
        Left several -> die (severalWorldsReport (goFiles go) lang several)
      -- An inferred world is said aloud, and its refusal names where its file
      -- was looked for, since the human never typed this name.
      worlds <- if null (goTarget go)
        then do
          say (inferredWorldsLine lang held (T.intercalate ", " names))
          mapM (resolveHeldOrDie base (goWorlds go) rep) names
        else mapM (resolveWorldOrDie base (goWorlds go)) names
      -- ONE model call for the whole language. The patterns are shared by every
      -- world, so the call that writes them must see every world: a call that
      -- sees one bakes that world's spelling into the shared half, and the next
      -- world -- which cannot convert a value, the grammar having no
      -- computation -- can only refuse. Measured 2026-08-09.
      inherited <- inheritedGrammar names (goFiles go)
      generate worlds inherited (goSchema go) (goConfidence go) (goCompat go) (goFresh go) (goVerbose go) (goModel go) (goThinking go) (goFiles go)
    Compile co
      | coWatch co -> watchCompile (coOut co) (coLangDir co) (coNoContract co) (coFile co)
      | otherwise  -> compileLoose (coOut co) (coLangDir co) (coNoContract co) (coFile co)
    Check co
      | ceDraft co -> checkDraft (ceRunning co) (ceRestart co) (ceFile co)
      | otherwise  -> checkLoose True True (ceLangDir co) (ceFile co)
                        >>= exitUnlessEveryWorldHeld (ceFile co)
    Options oo  -> do
      -- A lookup has no program, so a house world is resolved against the
      -- directory the human stands in (or --worlds).
      world <- resolveWorldOrDie "." (ooWorlds oo) (ooTarget oo)
      optionsQuery world (ooSchema oo) (ooLimit oo) (T.pack (ooQuery oo))
    Exports xo  -> exportsListing (xoTarget xo) (xoLanguage xo)
    WorldCmd dir what -> worldVerb dir what
    Lsp         -> runLsp

-- | @exports@: the clauses another program may call from a language, one
-- @name arity@ line each (@-@ where the definition is not a literal one, so
-- nothing is guessed). Offline and read-only, like @options@ -- and for the
-- same reason: a mint composing with a language must be grounded against the
-- names that exist, not against its memory of them.
exportsListing :: Maybe Text -> String -> IO ()
exportsListing mtarget lang = do
  -- Every path here (the language folder, the grammar, a world's rules) is
  -- derived from the LANGUAGE alone, so the bare @<language>.lips@ names them
  -- all and no instance of it has to exist. The listing is per language for the
  -- same reason: a vocabulary belongs to the language, not to an instance.
  let file = lang <> ".lips"
      dir  = langDir file
  minted <- mintedWorlds dir file
  world <- case soleWorld mtarget minted of
    Right w  -> pure w
    Left how -> die (report
      ("lips can't list what ." <> T.pack lang <> " exports.") []
      ("\8594 " <> how))
  eng <- loadLangOrDie dir world file
  -- On stdout, one export per line and nothing else: this is read by a mint
  -- tool. A progress line here would corrupt a list a model counts.
  sayAnswer (T.unlines
    [ n <> " " <> maybe "-" tshow ar | (n, ar) <- exportedClauses eng ])

-- | The committed grammar a mint must REUSE, or 'Nothing' when it is free to
-- write its own ('Lips.Language.grammarIsFrozen' decides which). Read fresh
-- before each world of a run, so world two inherits what world one just wrote.
-- @upcoming@ is the worlds still to be minted, this one included.
inheritedGrammar :: [Text] -> [FilePath] -> IO (Maybe Text)
inheritedGrammar _ []                = pure Nothing
inheritedGrammar upcoming (rep : _)  = do
  let dir = langDir rep
  committed <- mintedWorlds dir rep
  if grammarIsFrozen committed upcoming then tryRead (grammarPathIn dir rep)
                                        else pure Nothing

-- | Resolve a world name or die naming the remedy. The one door: every verb
-- that takes @--target@ comes through here, so a name means the same thing
-- everywhere.
resolveWorldOrDie :: FilePath -> Maybe FilePath -> Text -> IO World
resolveWorldOrDie base override name = do
  r <- resolveWorld base override name
  case r of
    Right w  -> pure w
    Left why -> die (report ("lips can't use the world " <> name <> ":") [why]
                       "\8594 name a world lips ships (lips world), or write one beside the program.")

-- | Resolve a world the language holds, inferred because no @-t@ named it. Its
-- own door because the remedy differs: the human did not type this name, so
-- the refusal says where its file was looked for rather than "name a world".
resolveHeldOrDie :: FilePath -> Maybe FilePath -> FilePath -> Text -> IO World
resolveHeldOrDie base override file name = do
  r <- resolveWorld base override name
  case r of
    Right w  -> pure w
    Left why -> die (heldWorldReport file name (worldPathIn (maybe base id override) name) why)

-- | @world@: print the world a name resolves to, list every world reachable
-- from here, or check that a world file's Nix parses. The listing marks which
-- are local, because that is the difference a reader acts on: a local file is
-- theirs to edit, a shipped one is not.
worldVerb :: Maybe FilePath -> WorldWhat -> IO ()
worldVerb dir (WorldPrint name) = do
  w <- resolveWorldOrDie "." dir name
  -- On stdout, undecorated: this is what a human redirects into a file to
  -- start a house world, and what the migration one-off writes beside an engine.
  sayAnswer (wRaw w)
worldVerb dir WorldList = do
  let here = fromMaybe "." dir
  locals <- localWorldNames here
  -- Two groups under one heading each, rather than a tag repeated on every
  -- line: the origin is a property of the group, and a shipped list of four
  -- said it four times. A local world still carries its own path, since that
  -- differs per line and is the file the reader opens.
  let mine = [ n | n <- locals, n `notElem` builtinNames ]
  sayAnswer (T.unlines
    ([ "lips ships:" ] ++ [ "  " <> n | n <- builtinNames ]
      ++ (if null mine then []
          else "" : "beside your program:"
               : [ "  " <> n <> "   (" <> T.pack (worldPathIn here n) <> ")" | n <- mine ])))
worldVerb dir (WorldCheck mname) = do
  let here = fromMaybe "." dir
  -- Unnamed means every world reachable from here, the same default the listing
  -- takes. A local file taking a shipped name is INCLUDED: resolution refuses to
  -- read it, and a check that silently skipped it would call the directory sound.
  names <- case mname of
    Just n  -> pure [n]
    Nothing -> nub . (builtinNames ++) <$> localWorldNames here
  faults <- concat <$> mapM (checkOneWorld here dir) names
  mapM_ say faults
  if null faults
    then note ("nix parses every slot of " <> plural (length names) "world" <> ".")
    else exitFailure

-- | One world's verdict as the reports to print: its structural parse (the same
-- one every verb runs), then nix's own parser over each Nix-bearing slot. Empty
-- means it held.
checkOneWorld :: FilePath -> Maybe FilePath -> Text -> IO [Text]
checkOneWorld here dir name = do
  r <- resolveWorldFrom here dir name
  case r of
    Left why -> pure [report ("lips can't use the world " <> name <> ":") [why]
                        "\8594 fix that file, or delete it."]
    Right (w, origin) -> do
      -- A shipped world has no path; naming it @<name>.world@ keeps nix's
      -- file:line:column readable and the headline says where it came from.
      let display = fromMaybe (T.unpack name <> ".world") origin
          whose = maybe ("the world lips ships for " <> name)
                        (("the world file " <>) . T.pack) origin
      slots <- checkNixSlots display (wRaw w)
      case slots of
        Left why -> die (report
          "lips needs nix to check a world file's slots, but couldn't run it:"
          [why]
          ("\8594 install nix, or run lips through it: nix run . -- world --check " <> name))
        Right fs -> pure
          [ report ("lips can't use " <> whose <> ": its " <> sfSlot f <> " slot is not valid Nix.")
                   (T.lines (sfNix f))
                   "\8594 fix that slot; the line nix names is the line in that file."
          | f <- fs ]

-- | @compile@: verify the program's committed contract, then crystallize +
-- realize and materialize a DIRECTORY -- default @<language>/out/<instance>/@, or
-- @--out <dir>@ -- holding @default.nix@ plus a staged @artifacts/@ tree. A
-- directory, not stdout, so an engine with artifacts is complete and
-- @imports = [ ./<dir> ]@ resolves default.nix. The output is derived, and it
-- lands inside the language's @out/@, which 'ensureDerived' makes
-- self-ignoring, so it never gets committed by accident.
--
-- The behavioral gate runs FIRST (the same one @check@ runs), so compile never
-- materializes a module that dropped a pinned value: a misroute an offline edit
-- can introduce fails loud here instead of importing a silently-wrong config.
-- Nix is the compile target, so the gate's @nix eval@ is no new dependency
-- (every compile invocation already runs through nix, and the output is only
-- meaningful where nix runs); the output stays bit-identical and deterministic,
-- the gate only refuses a bad one.
-- Beside @default.nix@ it writes @flake.nix@ (the addressable
-- entry) and, when the program declares artifacts, @artifact.nix@ (the
-- buildable derivations, extracted from the same ground base as the module).
-- Then it prints the exact @nix@ commands that run it: running a lips program
-- is not a lips verb, it is stock @nix@ over this directory, so compile emits
-- the handles and names the commands (only those the program's shape supports,
-- so no impossible command is ever shown -- deduce-or-fail).
compileLoose :: Maybe FilePath -> Maybe FilePath -> Bool -> FilePath -> IO ()
compileLoose mout mLangDir noContract file = do
  dir <- either die pure (resolveLangDir file mLangDir)
  -- The gate runs first and hands back its realization, so compile writes the
  -- very output the contract judged (and the pipeline runs once, not twice).
  -- @--no-contract@ is the one caller that cannot gate (a compile inside a nix
  -- derivation has no nix to evaluate with); it still crystallizes and realizes.
  rls <- checkLoose (not noContract) (not noContract) mLangDir file
  forM_ [ (w, rl) | (w, Right rl) <- rls ] (compileWorld mout dir file)
  exitUnlessEveryWorldHeld file rls

-- | @compile --watch@: the edit loop. Compile is deterministic, offline and
-- takes milliseconds, so it runs again on every save; the terminal then says
-- what the program means now, or which line the language cannot read yet.
--
-- INVARIANT 1 IS INTACT, and this is the one place a reader might doubt it:
-- @compile@ never calls a model. When a line does not crystallize, the loop
-- OFFERS the remedy it already prints, and @g@ runs @lips generate@ as a
-- separate process -- a deliberate act by the human, with every gate of the
-- ordinary mint. The loop is a driver around two verbs, not a third verb that
-- mixes them.
--
-- Polling, not inotify: the dev shell has no fsnotify, half a dozen @stat@ calls
-- four times a second cost nothing, and a poll cannot miss a file that does not
-- exist yet (a grammar the next mint will write).
watchCompile :: Maybe FilePath -> Maybe FilePath -> Bool -> FilePath -> IO ()
watchCompile mout mLangDir noContract file = do
  tty <- hIsTerminalDevice stdin
  unless tty $ die (report
    "lips compile --watch needs a terminal: it reads single keypresses."
    ["stdin is not a terminal here."]
    ("\8594 run it in a terminal, or compile once: lips compile " <> T.pack file))
  exe <- getExecutablePath
  dir <- either die pure (resolveLangDir file mLangDir)
  -- Raw-ish stdin: one keypress, no line buffering, no echo of the key itself.
  -- Restored on every exit, including the exception a failing compile throws,
  -- so a terminal is never left mute.
  let withKeys act = bracket
        (do b <- hGetBuffering stdin; e <- hGetEcho stdin
            hSetBuffering stdin NoBuffering >> hSetEcho stdin False
            pure (b, e))
        (\(b, e) -> hSetBuffering stdin b >> hSetEcho stdin e)
        (const act)
  withKeys (loop exe dir Nothing True)
  where
    -- One pass, answering whether it HELD, with the failure reduced to what it
    -- printed: a program the language cannot read is the NORMAL state of an edit
    -- loop, so it must not end it (compile alone still exits nonzero, which is
    -- what CI reads).
    once = do
      r <- try (compileLoose mout mLangDir noContract file)
      ok <- case r of
        Right () -> pure True
        Left e | Just (_ :: ExitCode) <- fromException e -> pure False
               | otherwise -> say (tshow (e :: SomeException)) >> pure False
      -- The mint is OFFERED only where it is the remedy. A green pass means the
      -- language reads every line, so growing it would buy nothing and cost a
      -- model call -- and an offer standing there invites exactly that by a
      -- stray keypress.
      say (if ok then "\8594 watching. q quits."
                 else "\8594 watching. g grows the language (runs generate), q quits.")
      pure ok

    loop exe dir before held = do
      now <- stamps dir
      (held', before') <- if Just now /= before then (,) <$> once <*> pure (Just now)
                                                else pure (held, before)
      k <- key
      case k of
        Just 'q' -> say "stopped watching."
        Just 'g'
          -- Refused rather than silently ignored: a key the loop just stopped
          -- offering must say why, or it reads as a broken key.
          | held' -> do
              say ("\8594 nothing to grow: every line of " <> T.pack file
                    <> " reads. Changing the MECHANISM is a deliberate act:"
                    <> " lips generate --fresh " <> T.pack file)
              loop exe dir before' held'
          | otherwise -> do
              -- A separate process on purpose: the mint is the other verb, with
              -- its own gates, its own record and its own cost -- not something a
              -- compile can slide into.
              say ("\8594 " <> T.pack exe <> " generate " <> T.pack file)
              _ <- try (callProcess exe ["generate", file]) :: IO (Either SomeException ())
              loop exe dir Nothing held'
        _ -> loop exe dir before' held'

    -- Sleep, then ASK whether a key is waiting. 'hWaitForInput' is the obvious
    -- call and the wrong one: with NoBuffering it blocks past its timeout
    -- (measured -- a file touched ten seconds in went unnoticed for thirty),
    -- which would freeze the loop until a key arrived. 'hReady' answers now.
    --
    -- 250ms: fast enough that a save feels immediate, cheap enough that half a
    -- dozen stats four times a second are invisible.
    key = do
      threadDelay 250000
      ready <- hReady stdin `catch` \(_ :: SomeException) -> pure False
      if ready then Just <$> hGetChar stdin else pure Nothing

    stamps dir = do
      worlds <- mintedWorlds dir file
      forM (watchedFiles dir file worlds) $ \p -> do
        there <- doesFileExist p
        if there then Just <$> getModificationTime p else pure Nothing

-- | Stop with a failing exit code when any world did not hold, after the ones
-- that did have been reported and written. Deliberate: you get the artifact you
-- can have, and CI still cannot mistake a program that reaches only some of its
-- worlds for one that reaches them all.
exitUnlessEveryWorldHeld :: FilePath -> [(Text, Either Text Realization)] -> IO ()
exitUnlessEveryWorldHeld file rls = case [ w | (w, Left _) <- rls ] of
  []   -> pure ()
  bad  -> do
    say ""
    say (T.pack file <> " does not reach " <> T.intercalate ", " bad
           <> "; the other worlds above hold.")
    exitWith (ExitFailure 1)

-- | Materialize ONE world's module directory from the realization @check@
-- already validated. Every world the language was minted into is written, each
-- into its own directory: a compiled module is a world's shape, so two worlds
-- sharing one directory would leave only the last one written.
compileWorld :: Maybe FilePath -> FilePath -> FilePath -> (Text, Realization) -> IO ()
compileWorld mout dir file (w, rl) = do
  (world, nixpkgs) <- readRecordedWorld dir w file
  -- An explicit @--out@ splits by world too, for the same reason the default
  -- path does: the flag names where the outputs go, not which one survives.
  let outDirPath = maybe (compiledPath file w) (</> T.unpack w) mout
  (artNames, rungs) <- step ("write " <> T.pack outDirPath) $ do
    ensureDerived file
    writeCompiled world nixpkgs file outDirPath rl
  say ("→ run it with nix over " <> T.pack outDirPath <> ":")
  mapM_ note (runCommands world artNames rungs outDirPath)

-- | Create a language's derived subtree and make it ignore itself: @out/@ gets
-- a @.gitignore@ holding @*@. lips writes that rule rather than asking the
-- user's repo to carry one, so derived output (crystal witnesses, compiled
-- module dirs) stays untracked wherever a program lives, with no setup.
-- Written once; an existing file is left alone, so a user can edit it.
ensureDerived :: FilePath -> IO ()
ensureDerived file = do
  createDirectoryIfMissing True (outDir file)
  let ign = outDir file </> ".gitignore"
  there <- doesPathExist ign
  unless there (TIO.writeFile ign "*\n")

-- | The world an engine was minted into: named by its committed .generation
-- record, and READ from the copy that travels beside the engine. The copy is
-- required -- lips never falls back to what it ships, because a world is data
-- now and the shipped one may have moved on. When the record carries a pin, the
-- copy must hash to it, so a compiled flake can never come from physics the
-- record does not name.
--
-- Returned beside the world: the nixpkgs a compiled directory of it evaluates
-- against, read from the same record, so the schema that admitted the rules
-- and the nixpkgs that runs them are related by one reading ('compiledNixpkgs').
readRecordedWorld :: FilePath -> Text -> FilePath -> IO (World, Nixpkgs)
readRecordedWorld dir w file = do
  -- The world's own record when it was minted alone, else the language-level
  -- record of the call that covered it: one mint may write for several worlds,
  -- and its event belongs to none of them alone.
  own <- doesPathExist (generationPathIn dir w file)
  let path = if own then generationPathIn dir w file else languageRecordPathIn dir file
  there <- doesPathExist path
  m <- tryRead path
  src <- case (there, m) of
    (True, Nothing) -> die (report
      ("lips can't read the generation record at " <> T.pack path <> ",")
      ["so it cannot tell which world this engine was minted for."]
      "\8594 restore the file, or re-mint: lips generate <program>.")
    (_, Nothing) -> die (report
      ("lips can't compile " <> T.pack file <> ": there is no generation record at "
        <> T.pack path <> ".")
      []
      "\8594 mint it: lips generate <program>.")
    (_, Just s) -> pure s
  (name, mpin) <- case recordedWorldPin src w of
    Just pin -> pure pin
    -- A record that does not name this world at all cannot vouch for it. Older
    -- records name exactly one world, so they still read through recordedWorld.
    Nothing  -> either (\why -> die (report
      ("lips can't compile " <> T.pack file <> ": " <> why <> ".")
      [T.pack path <> " is the record it read."]
      "\8594 re-mint it: lips generate <program>.")) pure (recordedWorld src)
  -- The copy lives in the world's own folder, which is NAMED after the world
  -- the record declares, so the two cannot disagree about which world this is.
  let wpath = worldPathIn (worldDirIn dir name) name
  mraw <- tryRead wpath
  raw <- case mraw of
    Just r  -> pure r
    Nothing -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file is missing.")
      [ T.pack path <> " names the world " <> name <> ", and " <> T.pack wpath <> " is not there." ]
      ("\8594 restore it: lips world " <> name <> " > " <> T.pack wpath
        <> " (for a world lips ships), or put your own copy back."))
  world <- either (\why -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file does not read.")
      [T.pack wpath <> ": " <> why]
      "\8594 restore it from the copy the record was minted with.")) pure (parseWorld raw)
  -- A record from before the pin existed cannot be re-hashed (a committed
  -- record is sealed: editing one would invalidate every stamp it names), so
  -- the copy is required but unpinned there.
  case mpin of
    Just pin | worldHash world /= pin -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file is not the one it was minted with.")
      [ T.pack path <> " pins " <> pin <> ", and " <> T.pack wpath <> " hashes to " <> worldHash world ]
      "\8594 restore that world file, or re-mint against this one: lips generate <program>.")
    _ -> pure ()
  pure (world, compiledNixpkgs world (worldSchemaPin src name))

-- | @check@: verify the program's committed behavioral contract holds against
-- its realized module, deterministically (no AI). This is the offline guardian
-- of the @.expect@ spec; @generate@ runs the same check before accepting an
-- engine, and the flake check shells this per example.
-- Returns the realization it validated, so @compile@ -- which gates through
-- this same verb -- materializes that run's output instead of running the whole
-- pipeline a second time.
-- Two flags, one per gate, so each skip is named at the call site instead of
-- riding along with another. @contract@ is the behavioral gate: only a compile
-- inside a nix build passes 'False' (see @--no-contract@). @claims@ is the
-- observational gate, which builds and may boot: 'checkDraft' passes 'False'
-- for it alone, because a per-call VM boot would block a mint on a machine
-- without KVM. Everything before both -- crystallization, the open questions,
-- the staged-source check -- runs either way, because none of it needs nix.
-- Per world, the verdict is an 'Either': a world the program does not reach
-- fails alone (see 'unportableReport'), so the worlds that DO hold are still
-- reported, and still compiled.
checkLoose :: Bool -> Bool -> Maybe FilePath -> FilePath -> IO [(Text, Either Text Realization)]
checkLoose contract claims mLangDir file = do
  dir     <- either die pure (resolveLangDir file mLangDir)
  program <- readProgramOrDie file
  ws      <- mintedWorlds dir file
  when (null ws) $ die (report
    (T.pack file <> " isn't set up yet (" <> T.pack dir <> " holds no world).")
    []
    ("\8594 create it: lips generate " <> T.pack file))
  -- Provenance before content: an engine whose lines do not name a record
  -- beside it is not the engine those records produced, so every later verdict
  -- would be about an unidentified file (invariant 6). Once for the language,
  -- because the grammar and every world's rules are stamped against the same
  -- set of records.
  assertStamps dir ws file
  -- A property of the LANGUAGE, not of one world: a world may declare a fact it
  -- cannot place only where another world spends it. Judged once, over every
  -- world's engine, before any verdict about a single world.
  assertIgnoresPlaced dir ws file
  -- No per-program source written by a model: generate refuses to write a tree,
  -- so one found here was placed past that gate and is refused just the same.
  let tree = artifactsPathIn dir file
  hasTree <- doesDirectoryExist tree
  when hasTree $ die (committedSourceReport file tree)
  forM ws $ \w -> do
    r <- checkWorld contract claims dir w file program
    case r of
      Left why -> say why
      Right _  -> pure ()
    pure (w, r)

-- | Realize every program this one depends on, in the same world. A dependency
-- names a language and an instance, and the file it lives in is spelled the way
-- every program is: @\<instance\>.\<language\>.lips@, or the singleton
-- @\<language\>.lips@ when the instance IS the language. Beside the importer,
-- because a language is a directory's vocabulary.
--
-- Deduce-or-fail: a dependency naming a file that is not there stops the run and
-- says which name it looked for, rather than compiling a site with a hole in it.
resolveImports :: [FilePath] -> Text -> FilePath -> [(Text, Text)] -> IO [Realization]
resolveImports trail w file uses = forM uses $ \(lang, inst) -> do
  let here     = takeDirectory file
      fileName = (if inst == lang then lang else inst <> "." <> lang) <> ".lips"
      imported = here </> T.unpack fileName
  there <- doesFileExist imported
  unless there $ die (report
    (T.pack file <> " depends on " <> inst <> "." <> lang <> ", and that program is not here.")
    [T.pack imported]
    ("\8594 write it, or name the instance that exists."))
  -- A cycle would otherwise resolve for ever. Named in full, because "which two
  -- programs" is the whole question a reader has.
  when (imported `elem` trail) $ die (report
    "these programs depend on each other in a circle."
    [ T.pack p | p <- reverse (imported : trail) ]
    "\8594 break the circle: move the shared vocabulary into a language both use.")
  dir' <- either die pure (resolveLangDir imported Nothing)
  eng' <- loadLangOrDie dir' w imported
  prog' <- readProgramOrDie imported
  -- Depth first: a dependency may name a language of its own, and the names the
  -- whole chain lends must be grounded before this link realizes.
  deps <- resolveImports (imported : trail) w imported (usesOf imported eng' prog')
  case validate (lentNames deps) imported eng' prog' of
    Left ff -> die (printFail imported ff)
    Right r -> pure (composeWith deps r)

-- | The dependencies a program states, read BEFORE it is realized: the names an
-- import lends have to be in the vocabulary while the clause gate runs, and that
-- gate runs inside realization.
--
-- A program that does not crystallize states nothing here and fails loud in the
-- realization that follows immediately, which is where that failure is reported
-- from anyway -- so this stays a question about dependencies alone.
usesOf :: FilePath -> EngineData -> Text -> [(Text, Text)]
usesOf file eng program = case crystallize file (edPatterns eng) program of
  Left _     -> []
  Right base -> usesIn base

-- | One world's verdict on a program: its rules read on top of the shared
-- grammar, its diagnosis, its contract, its claims.
-- The one non-fatal defect is the world's own: ground decisions no rule of THIS
-- world places. Every other failure is a fact about the PROGRAM (a conflict, an
-- unanswered demand, a line no pattern reads) and holds in every world, so it
-- stays fatal -- reporting it once per world would repeat one defect N times.
checkWorld :: Bool -> Bool -> FilePath -> Text -> FilePath -> Text -> IO (Either Text Realization)
checkWorld contract claims dir w file program = do
  -- Each world is judged on its own and says so, because the verdicts genuinely
  -- differ: a line answered by one world's rules can stay open in another's, and
  -- only the pattern half of the diagnosis is shared. Said here rather than at
  -- the caller, so a draft judged in several worlds reads the same way.
  say ("world " <> w <> ":")
  eng <- loadLangOrDie dir w file
  openQuestions <- step ("crystallize " <> T.pack file) $ do
    -- An engine unsound on its own terms makes every later verdict meaningless
    -- (an ambiguous line reads as the author's problem when it is the engine's),
    -- so it fails before the diagnosis. Same gate generate runs before accepting
    -- a mint, so a committed engine cannot drift below what minting required.
    case engineViolations (T.pack (languageName file)) eng of
      []      -> pure ()
      (v : _) -> die (validationReport file v)
    -- First phase, pure and offline: how the program sits in its language.
    -- Always shown, so authoring is never blind; the behavioral gate runs only
    -- once the program crystallizes cleanly and completely.
    let d = diagnose file eng program
    sayAnswer (renderDiagnosis file d <> "\n")
    if any escapes (diagLines d)
      then die (report
             (T.pack file <> " has lines its language cannot read yet.")
             []
             ("→ grow the language: lips generate " <> T.pack file))
      else if not (null (diagOpen d))
        -- An open question is the author's to answer -- unless no program could:
        -- a demand outside every emitted subject family is an engine defect, and
        -- telling the author to state a fact they already stated sends them in
        -- circles. So blame the side that can fix it.
        then case unanswerableDemands (edPatterns eng) (edDemands eng) of
          -- The demands are THIS WORLD's (they live in its rules), so the
          -- question is this world's too: it is returned, not thrown, and the
          -- worlds that hold are still reported and still compiled.
          []  -> pure (diagOpen d)
          uds -> die (unanswerableReport file uds)
        else pure []
  case openQuestions of
    (_ : _) -> pure (Left (unansweredReport file w openQuestions))
    [] -> do
     -- The dependency chain is resolved BEFORE this program's own run, because
     -- a call into an imported definition is grounded DURING realization: the
     -- linked core that composeWith builds below arrives too late for that, and
     -- a program calling a name its dependency defines would be refused as
     -- ungrounded (measured on a two-language fixture, 2026-08-12).
     imports <- resolveImports [file] w file (usesOf file eng program)
     -- Validated ONCE, here, so the two readings of the outcome (is this world
     -- reachable, and does its contract hold) judge the same run.
     case validate (lentNames imports) file eng program of
      Left (FailRun (Unmapped ds)) -> pure (Left (unportableReport file w ds))
      Left ff -> die (printFail file ff)
      Right rl0 -> do
        -- Composition happens BEFORE the gates, so the claims judge the site a
        -- run would actually link: an imported clause is reachable from a claim
        -- exactly as a local one is.
        rl <- expectGate contract claims dir w file eng (composeWith imports rl0)
        -- What vouches for each assertion, always printed. An unvouched
        -- assertion (mint glue in a builder argument)
        -- is the one thing lips cannot check, so the count is stated on every
        -- run rather than discovered later by a reviewer reading generated code.
        let ground = groundingOf file eng rl
        mapM_ note (groundingReport ground)
        -- What this world drops, said on every run rather than left for a
        -- reviewer who opens the rules file: a declaration is cheap to write and
        -- must not be cheap to overlook.
        mapM_ note (ignoreNotes w eng)
        pure (Right rl)
  where
    escapes Matched{} = False
    escapes _         = True

-- | @check --draft@: judge an engine the mint has not committed yet. The draft
-- arrives on stdin in reply format; lips materializes it into a throwaway
-- language folder and runs the ordinary verifier over it, so what the model is
-- told is what lips itself would say -- there is no second, model-facing
-- verifier to drift.
--
-- The COMMAND claim gate is deliberately NOT run, and the output says so: a
-- sandbox claim compiles the artifact and a machine claim boots a VM, so it costs
-- minutes per call and hard-fails without KVM, which would be a false RED
-- blocking the model from validating at all. "Not verified" is stated, never
-- rendered as verified.
--
-- The CLAUSE claim gate IS run, for the same reason by the same rule: it costs a
-- small derivation, needs no machine and no compiler, so the cost argument that
-- excludes the others does not apply. That lets a model fix a failing claim
-- inside the one call instead of spending a whole mint on it.
--
-- A world's own GATE (its @gate@ slot) is run too, on the same argument: the
-- world declared it affordable on every mint, and its refusal (a validator
-- naming a field the schema could not) is exactly what the model can fix
-- in-call. It builds against the pinned nixpkgs, so the door needs one.
--
-- The gate that DECIDES is unchanged: generate still runs every one of these
-- checks afterwards, so a model that skips this door is refused exactly as
-- before.
-- A RESUBMISSION is a patch of the draft this call already submitted, not the
-- engine again: a refused submission used to cost a full re-emission, and output
-- tokens are the mint's wall clock (DESIGN 13). The running file carries the
-- call's submissions so far, and is rewritten whether or not the gates pass --
-- accumulating a REFUSED draft is the point, since fixing the line the gate just
-- named is exactly when the model has everything else already written.
checkDraft :: Maybe FilePath -> Bool -> FilePath -> IO ()
checkDraft running restart file = do
  submitted <- TIO.getContents
  -- The same merge the committed-engine basis gets below, one level in: a new id
  -- adds, a known id replaces, an unmentioned id stays. --restart voids the
  -- running draft, which is the only way back from a line a patch cannot delete.
  accumulated <- case running of
    Just p | not restart -> fmap (fromMaybe "") (tryRead p)
    _                    -> pure ""
  let patch = mergeReply accumulated submitted
  forM_ running $ \p -> TIO.writeFile p patch
  -- Which contract governs is generate's rule, not this function's: it exports
  -- the answer per world (the committed .expect on a regeneration, absent under
  -- --renew or on a first mint) so the two cannot drift apart.
  governing <- envPairs "LIPS_MINT_EXPECTS" >>= \ps ->
    fmap concat $ forM ps $ \(w, p) -> maybe [] (\t -> [(w, t)]) <$> tryRead p
  -- The worlds the draft is minted for decide which folders it gets, so the
  -- throwaway tree has the shape check reads. Named by generate, never guessed:
  -- a draft judged in the wrong world's namespace is a false verdict.
  ws <- draftWorlds
  -- A PATCH is judged as the engine it BECOMES. Judging it alone would refuse
  -- every growth mint, since a reply that keeps a committed pattern does not
  -- carry it. generate names the basis directory (LIPS_MINT_BASIS); nothing is
  -- guessed, and an absent one means the reply is the whole engine.
  basisDir <- lookupEnv "LIPS_MINT_BASIS"
  reply <- case basisDir of
    Just d | not (null d) -> do
      g  <- tryRead (grammarPathIn d file)
      rs <- forM (map wName ws) $ \w -> fmap ((,) w) <$> tryRead (rulesPathIn d w file)
      let tagOf w = if length ws > 1 then Just w else Nothing
          parts = maybe [] (\t -> [replyLinesOf Nothing t]) g
                    ++ [ replyLinesOf (tagOf w) t | Just (w, t) <- rs ]
      pure (if null parts then patch else mergeReply (T.concat parts) patch)
    _ -> pure patch
  withTempDir $ \root -> case materializeDraft root (map wName ws) file reply governing of
    Left errs -> die (validationReport file ("the draft cannot be read as an engine:\n"
                        <> T.unlines [ "  - " <> e | e <- errs ]))
    Right t   -> do
      -- The no-blob gate, in the door the model checks through, so a mint that
      -- reached for a source tree hears why while it can still write clauses.
      unless (null (dtSources t)) $ die (mintedSourceReport file (dtSources t))
      createDirectoryIfMissing True (dtLangDir t)
      TIO.writeFile (grammarPathIn (dtLangDir t) file) (dtGrammar t)
      forM_ (dtWorlds t) $ \(w, rules, expect) -> do
        createDirectoryIfMissing True (worldDirIn (dtLangDir t) w)
        TIO.writeFile (rulesPathIn (dtLangDir t) w file) rules
        TIO.writeFile (expectPathIn (dtLangDir t) w file) expect
      -- The schema gate cannot live in check, which stays nixpkgs-free so a
      -- committed engine is judged offline. The draft path runs on the mint
      -- side, where generate has already built every world's schema and hands
      -- over the paths, so it runs the gate itself: without it a draft naming an
      -- option that does not exist would read as clean here and be refused by
      -- the final gate, which is the false-green direction.
      schemas <- envPairs "LIPS_MINT_SCHEMAS"
      forM_ ws $ \w -> case lookup (wName w) schemas of
        Just p | not (null p) -> do
          eng <- loadLangOrDie (dtLangDir t) (wName w) file
          assertOptionsAdmissible w p file eng
        _ -> pure ()
      -- The cross-world invariant first, over the whole draft: a fact every
      -- world declares it cannot place is a word the program states and the
      -- language throws away. Judged HERE, in the door the model checks through,
      -- because this is the one gate a mint could otherwise walk around by
      -- declaring the same ignore in every world.
      assertIgnoresPlaced (dtLangDir t) (map wName ws) file
      -- Every world the draft is for is judged, because the committed engine
      -- will be judged in every one of them. A world the draft does not reach is
      -- this draft's verdict, and fatal here: the model is still writing it.
      program <- readProgramOrDie file
      -- The pin each world is being grounded against, handed over by generate
      -- because the draft has no record yet to read it from. Every build the
      -- door runs uses it, so the draft observes the nixpkgs `check` will read
      -- back from the record. A door run outside a mint has none: ambient.
      pins <- envPairs "LIPS_MINT_PINS"
      forM_ ws $ \w -> do
        let nixpkgs = compiledNixpkgs w (T.pack <$> lookup (wName w) pins)
        rl <- either die pure =<< checkWorld True False (dtLangDir t) (wName w) file program
        clauseClaimGate w nixpkgs file rl
        -- The glue gate generate runs, said in the door while the mint can still
        -- add the claim; check alone only reports unpinned glue.
        eng <- loadLangOrDie (dtLangDir t) (wName w) file
        case gUnpinned (groundingOf file eng rl) of
          [] -> pure ()
          us -> die (unpinnedGlueReport file (wName w) us)
        -- The world's own gate is a build the world declared affordable on every
        -- mint, so the door runs it too: the model then reads the validator's
        -- refusal inside its own call instead of paying a whole mint for it.
        when (isJust (wGate w)) $ worldGate nixpkgs w file rl
        -- The contract above is the GOVERNING one (the committed .expect on a
        -- regeneration), which cannot say whether the draft's NEW promises are
        -- evaluable at all. The ground half of those costs no nix, so the door
        -- judges it here rather than leaving the mint to find out from the final
        -- gate a quarter of an hour later.
        case groundExpectFaults (instanceName file) (concat [ es | (w', es) <- dtOwnExpects t, w' == wName w ]) rl of
          []   -> pure ()
          bad  -> die (report
            (T.pack file <> ": this draft's own contract cannot hold, in " <> wName w <> ":")
            bad
            "\8594 assert the slot the value actually reaches, or drop the check.")
      note "the command claim gate and the artifact build were NOT run"

-- | A @<name>=<value>@ list generate exports, one per line: the per-world
-- schema paths and governing contracts. Absent or empty is the empty list.
envPairs :: String -> IO [(Text, FilePath)]
envPairs name = do
  raw <- lookupEnv name
  pure [ (T.pack k, drop 1 v)
       | l <- maybe [] lines raw, not (null l)
       , let (k, v) = break (== '=') l, not (null v) ]

-- | Which worlds a draft is judged in. Read from the environment generate
-- controls, never defaulted: a silent default would judge a draft against the
-- wrong world's namespace and report the wrong names as missing.
--
-- A house world lips does not ship is resolved from the directory the draft's
-- programs live in, exactly as generate resolved it, so a draft for a house
-- world is judged by the same physics the mint aimed at.
draftWorlds :: IO [World]
draftWorlds = do
  raw <- lookupEnv "LIPS_MINT_WORLDS"
  progs <- lookupEnv "LIPS_MINT_PROGRAMS"
  let names = maybe [] (T.splitOn "," . T.pack) raw
      base = case maybe [] lines progs of
               (f : _) -> takeDirectory f
               []      -> "."
  case names of
    [] -> die (report
      "lips can't check this draft: the worlds it is minted for are not stated."
      ["LIPS_MINT_WORLDS is missing or empty."]
      "\8594 this is generate's to set; report it as a lips bug.")
    _  -> mapM (resolveWorldOrDie base Nothing) (filter (not . T.null) names)

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
-- Validates once, up front: the module, its artifacts and the paths it names
-- all come from that one run, so the staged-source gate below and the contract
-- judge the same realization.
expectGate :: Bool -> Bool -> FilePath -> Text -> FilePath -> EngineData -> Realization -> IO Realization
expectGate contract claims dir w file eng rl = do
  stagedGate (stageBeside file rl) file rl
  expSrc <- if contract then tryRead (expectPathIn dir w file) else pure Nothing
  case expSrc of
    -- A skipped or absent contract is stated, never rendered as a pass: the
    -- step's own ✓ would otherwise claim a gate that did not run.
    Nothing | not contract ->
      note "contract skipped (--no-contract): nix is needed to evaluate it"
    Nothing  -> note ("no contract yet: " <> T.pack (expectPathIn dir w file)
                        <> " is written by generate")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        -- An assertion that cannot hold for ANY program is the engine's defect,
        -- not this program's, so it is named as one rather than reported as a
        -- broken promise after the eval.
        | bad@(_ : _) <- unholdableExpects (edPatterns eng) (edRules eng) expects ->
            die (validationReport file (unholdableProblem bad))
        | otherwise -> step ("contract: " <> plural (length expects) "check") $ do
          -- Bind <self> in the contract's option paths to this instance, so it
          -- checks against the realized (already-bound) module.
          res <- runExpects (stageBeside file rl) (instanceName file) expects rl
          case res of
            Right () -> pure ()
            Left (ToolMissing e) -> die (nixMissing file "check the program" "check" e)
            Left (EvalFailed e)  -> die (nixEvalFailed file "check" e)
            Left (Violations fs _) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))
  when claims $ do
    (world, nixpkgs) <- readRecordedWorld dir w file
    claimGate world nixpkgs file rl
  pure rl

-- | The facts a world declares it cannot place, in the words of its own
-- declarations.
ignoreNotes :: Text -> EngineData -> [Text]
ignoreNotes w eng =
  [ w <> " ignores " <> renderAttrPath (igSubject ig) <> ": " <> igReason ig
  | ig <- edIgnores eng ]

-- | Invariant behind the @ignore@ declaration: every fact a world drops is
-- placed by some world of the same language. A fact NOBODY places is a word the
-- program states and the language throws away, and a declaration must not
-- launder that into silence.
assertIgnoresPlaced :: FilePath -> [Text] -> FilePath -> IO ()
assertIgnoresPlaced dir ws file = do
  engines <- forM ws (\w -> (,) w <$> loadLangOrDie dir w file)
  case orphanIgnores engines of
    []  -> pure ()
    bad -> die (report
      (T.pack file <> ": " <> plural (length bad) "fact"
        <> " a world says it cannot place, and no world of this language places:")
      [ w <> " ignores " <> subj <> " (" <> i <> ")" | (w, i, subj) <- bad ]
      ("\8594 place it in the world that needs it, or drop the line from "
        <> T.pack file <> ": an ignored fact must be spent somewhere."))

-- | Load and parse one world's engine: the shared grammar plus that world's
-- rules, read as the concatenation they are rendered from. Fails loud naming
-- @generate@ -- a missing grammar means the language was never minted, a
-- missing rules file means it was never minted INTO THIS WORLD, so the remedy
-- names the world.
loadLangOrDie :: FilePath -> Text -> FilePath -> IO EngineData
loadLangOrDie dir w file = do
  let grammarFile = grammarPathIn dir file
      rulesFile   = rulesPathIn dir w file
  mgrammar <- tryRead grammarFile
  grammar  <- case mgrammar of
    Nothing -> die (report
      (T.pack file <> " isn't set up yet (" <> T.pack grammarFile <> " is missing).")
      []
      ("→ create it: lips generate " <> T.pack file))
    Just g  -> pure g
  mrules <- tryRead rulesFile
  rules  <- case mrules of
    Nothing -> die (report
      (T.pack file <> " is not minted for the world " <> w <> " ("
        <> T.pack rulesFile <> " is missing).")
      []
      ("→ mint it there: lips generate --target " <> w <> " " <> T.pack file))
    Just r  -> pure r
  case readLang (grammar <> rules) of
    Left es  -> die (unreadable file ".lang" es)
    Right eng -> pure eng

-- | Invariant 6, enforced at the door every committed engine passes: re-hash
-- the @.generation@ beside the engine and refuse a @\@gen:@ stamp that
-- disagrees with it. Deterministic and offline, so @check@ stays nixpkgs-free.
--
-- Without it the invariant was a promise: a change to what the record CONTAINS
-- would silently invalidate every committed engine's stamps while all gates
-- stayed green, and only a reader re-hashing by hand would ever notice.
--
-- An engine with no record at all is judged the other way round ('stampFaults'):
-- it may claim no generation. A record that EXISTS and cannot be read is a loud
-- failure rather than the no-record reading, exactly as 'readRecordedWorld'
-- treats it -- guessing there would turn a broken repository into a green check.
assertStamps :: FilePath -> [Text] -> FilePath -> IO ()
assertStamps dir ws file = do
  -- Every record of the language: one per world minted alone, plus the
  -- language-level record of any call that covered several at once. A line is
  -- sound when it names one of them.
  recs <- fmap concat $ forM (languageRecordPathIn dir file
                                : [ generationPathIn dir w file | w <- ws ]) $ \recPath -> do
    there <- doesPathExist recPath
    mrec  <- tryRead recPath
    case (there, mrec) of
      -- No record at all is a hand-written engine, judged by the inverted rule
      -- (no line may claim a generation). A record that EXISTS and cannot be
      -- read is the other case entirely: reading it as absent is what would
      -- turn a damaged repository green.
      (False, _)      -> pure []
      (True, Nothing) -> die (report
        ("lips can't read the generation record at " <> T.pack recPath <> ",")
        ["so it cannot tell which generation wrote this engine."]
        "\8594 restore the file, or re-mint: lips generate <program>.")
      (True, Just r)  -> pure [r]
  -- File by file, so a reported line number is that file's own; a grammar line
  -- may name any world's mint, which is why every record is offered to each.
  faults <- forM (grammarPathIn dir file : [ rulesPathIn dir w file | w <- ws ]) $ \p -> do
    msrc <- tryRead p
    pure [ (p, f) | f <- maybe [] (stampFaults recs) msrc ]
  case concat faults of
    [] -> pure ()
    bad -> die (report
      (T.pack file <> "'s engine does not name the generations that wrote it:")
      [ T.pack p <> ": " <> renderStampFault f | (p, f) <- bad ]
      ("\8594 re-mint it: lips generate " <> T.pack file
        <> " (a minted file is never hand-edited)."))

-- | Read the program file, or fail with a plain message instead of a raw
-- exception when the path is wrong (a common typo at the shell).
readProgramOrDie :: FilePath -> IO Text
readProgramOrDie file = do
  -- The one door every verb reads a program through, so the .lips marker is
  -- checked once, here: a path without it would otherwise be reinterpreted by
  -- Lips.Identity (a .lang read as a program in language "lang").
  either die pure (requireProgram file)
  m <- tryRead file
  case m of
    Just t  -> pure t
    Nothing -> die (report
      ("lips can't read " <> T.pack file <> ".")
      []
      "→ check the path, or create the program file first.")

tryRead :: FilePath -> IO (Maybe Text)
tryRead p = either (const Nothing) Just <$> (try (TIO.readFile p) :: IO (Either IOException Text))

-- | @generate@: the one AI step. The model mints a whole engine (patterns,
-- rules, demands); the kernel crystallizes the program with it and validates
-- by a full run plus a Nix parse before writing anything.
-- The inherited grammar, when there is one, is both an INPUT (the mint is told
-- to reuse it, so it enters the prompt and the record) and a GUARD (what comes
-- back is checked against it).
generate :: [World] -> Maybe Text -> Maybe String -> Double -> Compat -> Bool -> Bool -> Maybe String -> String -> [FilePath] -> IO ()
-- Unreachable: Lips.Cli.generateOpts's `some` guarantees at least one file by
-- construction. Kept only so this function stays total (-Wall incomplete-patterns).
generate _ _ _ _ _ _ _ _ _ [] = die "lips generate needs at least one program (unreachable: the CLI parser requires one)."
generate worlds inherited mschema confidence compat fresh verbose mmodel thinking files@(rep : _) = do
  -- What the mint cost is recorded whatever the verdict, because a REFUSED mint
  -- spends a whole round and that is the number the feedback cycle turns on.
  -- Every refusal below goes through 'die', which throws, so the write hangs off
  -- 'finally' rather than off the success path -- one place, no exit to miss.
  t0 <- getPOSIXTime
  costCell <- newIORef Nothing
  flip finally (writeMintStats t0 costCell thinking worlds files) $ do
    let lang   = languageName rep
        dir    = langDir rep
        wnames = map wName worlds
    -- What this mint grows from, named by the record the committed engine was
    -- stamped from: an inherited engine steers the reply as much as the prompt
    -- does, so it is pinned like every other input (invariant 6). Read from the
    -- first world's governing record, because one call patches one language
    -- against one committed state.
    basis <- if fresh then pure "fresh" else do
      mr <- case wnames of
              (w : _) -> governingRecord dir w rep
              []      -> pure Nothing
      pure (maybe "fresh" (\r -> "inherited " <> genId r) mr)
    -- The engine this mint GROWS FROM, rendered back into the reply format: the
    -- shared grammar (never tagged -- patterns belong to the language) plus each
    -- world's rules, tagged only when the run writes for several worlds. Absent
    -- under --fresh and on a first mint, and then every step below is exactly the
    -- whole-engine path it always was.
    committedGrammar <- if fresh then pure Nothing else tryRead (grammarPathIn dir rep)
    basisEngine <- if fresh then pure Nothing else do
      let g = committedGrammar
      rs <- forM wnames $ \w -> fmap ((,) w) <$> tryRead (rulesPathIn dir w rep)
      let tagOf w = if length wnames > 1 then Just w else Nothing
          parts = maybe [] (\t -> [replyLinesOf Nothing t]) g
                    ++ [ replyLinesOf (tagOf w) t | Just (w, t) <- rs ]
      pure (if null parts then Nothing else Just (T.concat parts))
    progs <- forM files (\f -> (,) f <$> readProgramOrDie f)
    -- Owner taste is language-level (shared); read once from the language path.
    direction <- tryRead (directionPath rep)
    let prompt = promptWithDirection direction inherited basisEngine worlds
        -- The mint sees the whole example set at once, so the grammar generalizes
        -- across them (anti-unification): tokens that vary between examples become
        -- holes, tokens that agree stay literal. One program is the corpus-of-one
        -- case. The same set is the regeneration corpus below.
        corpus = corpusText progs
    -- Resolve EVERY world's grounding schema BEFORE the model runs: a schema is an
    -- input of the generation event (it decides which rules are admissible), it is
    -- recorded as such, and a schema that cannot be built must not cost an AI call
    -- first -- which has to hold for the last world as much as the first.
    grounds <- forM worlds $ \w -> do
      (p, pin) <- ensureOptionSchema w mschema ("generate " <> T.pack rep)
      pure (w, p, pin)
    -- A re-mint grounds against the pin this binary carries (or --schema), NOT
    -- against the one the committed record names: fresh grounding is the point of
    -- re-minting, and replaying an old one is impossible anyway. The only hole
    -- that leaves is silence, so say it -- a re-ground engine is a different
    -- engine, and the reader deserves to learn that here rather than from the
    -- .generation diff afterwards.
    forM_ grounds $ \(w, _, pin) -> do
      old <- (>>= (`recordedSchemaFor` wName w)) <$> governingRecord dir (wName w) rep
      case old of
        Just p | p /= pin -> do
          note ("re-grounding " <> wName w <> ": the committed engine was minted against " <> p)
          note ("this run grounds against " <> pin)
        _ -> pure ()
    -- The mint's validation tool judges a draft against the contract that will
    -- actually gate it: the committed .expect on a regeneration, the draft's own
    -- minted expects on a first mint or under --compat none. That rule is
    -- generate's (it is read again below, where the gate itself uses it), so the
    -- tool is told the answer instead of re-deriving it and drifting into a false
    -- green. One entry per world, because a contract is a world's.
    committedExpects <- if compat == None then pure [] else fmap concat $ forM worlds $ \w -> do
      let p = expectPathIn dir (wName w) rep
      there <- doesFileExist p
      pure [ (wName w, p) | there ]
    piReply <-
      step ("mint ." <> T.pack lang <> " from " <> plural (length files) "program"
              <> " for " <> T.intercalate ", " wnames) $
        callPi verbose mmodel thinking prompt corpus worlds files committedExpects
               [ (wName w, p) | (w, p, _) <- grounds ]
               [ (wName w, T.unpack pin) | (w, _, pin) <- grounds ]
               (maybe "" (const dir) basisEngine)
    -- From here on a refusal has a model call behind it, so the numbers the mint
    -- reported belong in the stats file however this run ends.
    writeIORef costCell (Just piReply)
    let patchReply = prReply piReply
        -- A patch is not an engine: merged with what it grows from BEFORE
        -- anything reads it, so every gate, every render and every write below
        -- sees a complete engine and needs no notion of a patch at all.
        reply      = maybe patchReply (`mergeReply` patchReply) basisEngine
        -- Which ids the model actually wrote, for the human: after a patch every
        -- line is RE-STAMPED with this run's record, and that is correct rather
        -- than a loss -- the record stores the MERGED reply, so it really does
        -- contain every line the engine now holds, and a stamp keeps meaning
        -- "the record beside me hashes to this" (invariant 6, which refuses a
        -- stamp naming a record that is no longer there). Where a line came from
        -- is carried by the record's own @basis:@ line, which names the record
        -- this one grew out of, and by git.
        touched    = fmap (const (touchedIds patchReply)) basisEngine
        model      = prModel piReply
        transcript = prTranscript piReply
    forM_ touched $ \ids -> note ("patching " <> plural (length ids) "line"
                                    <> ": " <> T.unwords ids)
    note ("minted by " <> model <> ", thinking " <> T.pack thinking)
    -- --verbose: echo the model's raw reply verbatim before parsing, so the
    -- whole minted engine is inspectable even when it validates cleanly (a
    -- refusal already shows the offending lines).
    when verbose $ say (T.unlines
      [ "--- raw model reply (" <> model <> ") ---", reply, "--- end reply ---" ])
    let (errs, candidates) = parseEngineCandidates wnames reply
        -- A because-note explains a low-confidence item; keyed by shared id, it
        -- never gates the build and never enters the engine.
        notes = [(icId c, r) | c <- candidates, ItemNote r <- [icItem c]]
        -- Deduce-or-fail: the programs are the only source of truth, so an item
        -- the model cannot confidently derive means they underspecify it.
        unsure = [c | c <- candidates, carriesEngineMeaning (icItem c)
                    , let Confidence x = icConfidence c, x < confidence]
        gaps = gapsOf (map icItem candidates)
        -- The whole event, pinning every world it aimed at. Built before the
        -- gates because a refusal is pinned exactly as an acceptance would be.
        rec = record model [ (wName w, worldHash w, pin) | (w, _, pin) <- grounds ]
                     (T.pack thinking) confidence basis prompt corpus transcript reply
    if not (null errs) || not (null unsure)
      then do
        -- Machine-readable twin of the on-screen refusal: the cross-repo
        -- escalation workflow (DESIGN Doctrine) needs a shippable artifact, not
        -- only text that scrolls off a terminal.
        -- Filed at the scope of the event: one call covering several worlds
        -- refused as a whole, so its gap sits at the language level.
        let gap = case wnames of
                    [w] -> gapPathIn dir w rep
                    _   -> languageGapPathIn dir rep
        createDirectoryIfMissing True (takeDirectory gap)
        TIO.writeFile gap (gapArtifact rec errs unsure gaps)
        die (refusalReport rep gap confidence errs unsure notes gaps)
      else do
        -- A mint without an explanation is incomplete: the human's review
        -- artifact is the report, not the engine. A structural guard, so the
        -- channel cannot rot into an optional pleasantry the model skips.
        reportBody <- case reportOf (map icItem candidates) of
          Just b | not (T.null (T.strip b)) -> pure b
          _ -> die (report
            ("the mint for ." <> T.pack lang <> " came back without a report block.")
            ["lips needs the language explained in plain words before it commits it."]
            ("\8594 run generate again: lips generate " <> T.pack rep))
        -- No per-program source written by a model, whatever else the mint
        -- holds: refused before any gate that costs a build.
        let minted = sourcesOf (map icItem candidates)
        unless (null minted) $ die (mintedSourceReport rep minted)
        -- What a realized module names beside itself is the site its clauses
        -- build, so that is what every gate stages.
        let stage rl root = void (writeSite (T.pack lang) root rl)
        -- The patterns are shared, so the append-only guard runs ONCE over the
        -- grammar this reply renders, before any gate that costs a build: a mint
        -- that does not own the language level may only add to what the worlds it
        -- is not re-minting were built on.
        -- Patterns are shared, so ANY world's engine renders the same grammar; the
        -- first is taken because the CLI parser guarantees at least one world.
        let sharedEng = assemble (itemsFor (T.concat (take 1 wnames)) candidates)
            freshGrammar = fst (splitEngine (renderLang (FromSource (SourceLoc "lang" 0)) sharedEng))
        case inherited of
          Nothing -> pure ()
          Just g ->
            case [ "pattern " <> i <> " changed, and other worlds are built on it"
                 | i <- appendOnlyViolations g freshGrammar ] of
              []   -> pure ()
              bad  -> do
                held <- mintedWorlds dir rep
                die (report
                  ("this mint would rewrite what the language's other worlds are built on:")
                  bad
                  ("\8594 re-mint every world together, so they agree: lips generate"
                    <> T.concat [ " -t " <> w | w <- held ++ [ w | w <- wnames, w `notElem` held ] ]
                    <> " " <> T.pack rep))
        -- The cross-world invariant, before any per-world gate: a fact a world
        -- declares it cannot place must be placed by some world of the language.
        -- The reply's worlds plus the committed engines of worlds this run does not
        -- re-mint, so a single-world mint is held to the same rule as a joint one.
        committedElsewhere <- do
          allWorlds <- mintedWorlds dir rep
          forM [ w | w <- allWorlds, w `notElem` wnames ] $ \w ->
            (,) w <$> loadLangOrDie dir w rep
        case orphanIgnores ([ (w, assemble (itemsFor w candidates)) | w <- wnames ]
                              ++ committedElsewhere) of
          []  -> pure ()
          bad -> die (report
            (T.pack rep <> ": " <> plural (length bad) "fact"
              <> " a world says it cannot place, and no world of this language places:")
            [ w <> " ignores " <> subj <> " (" <> i <> ")" | (w, i, subj) <- bad ]
            ("\8594 place it in the world that needs it, or mint again without the"
              <> " declaration: an ignored fact must be spent somewhere."))
        -- Every world is gated on its own engine (the shared grammar plus its own
        -- rules) and answers for itself: a world that cannot serve the program
        -- fails alone, and the worlds that hold are still written.
        results <- forM grounds $ \(w, schemaPath, pin) ->
          (,) w <$> gateOneWorld compat rep progs candidates stage w schemaPath pin
        let held = [ (w, r) | (w, Right r) <- results ]
            failed = [ (wName w, why) | (w, Left why) <- results ]
        -- Nothing is written for a world that failed, and the account of the
        -- event is filed at the scope of the event: one call covering several
        -- worlds writes one README at the language level.
        let (freshGrammarStamped, _) = splitEngine (renderLang (FromGeneration (genId rec)) sharedEng)
            grammarText = maybe freshGrammarStamped (`mergeGrammar` freshGrammarStamped) inherited
        unless (null held) $
          step ("write " <> T.pack dir) $ do
            createDirectoryIfMissing True dir
            -- Shared, and written only by a call that owns the language level:
            -- the grammar every world reads, the record of this event and its
            -- account.
            -- The grammar is always written: frozen means APPEND-ONLY, so a mint
            -- that added a pattern must land it, and 'mergeGrammar' keeps every
            -- inherited line's own bytes and stamp.
            TIO.writeFile (grammarPathIn dir rep) grammarText
            case wnames of
              [_] -> pure ()   -- a single-world mint files its record in its world folder
              _   -> do
                TIO.writeFile (languageRecordPathIn dir rep) rec
                TIO.writeFile (languageReadmePathIn dir) (renderReadme (T.pack lang) reportBody gaps)
            forM_ held $ \(w, wr) ->
              writeWorld dir rep lang rec reportBody gaps (length wnames == 1) w wr
            forM_ [ (f, rl) | (_, wr) <- held, (f, rl) <- wrValidated wr ] $ \(f, rl) -> do
              ensureDerived f
              TIO.writeFile (decisionsPath f) (renderBase (rlBase rl))
        -- The account of the mint, in the mint's own words: the first lines of the
        -- report, then where to read the rest.
        say ""
        unless (null held) $ do
          say ("✓ ." <> T.pack lang <> " holds for " <> plural (length files) "program"
                 <> " in " <> T.intercalate ", " [ wName w | (w, _) <- held ] <> ".")
          say ""
          mapM_ say (take 5 [ l | l <- T.lines (T.strip reportBody), not (T.null (T.strip l)) ])
        let account = case wnames of
                        [w] -> readmePathIn dir w
                        _   -> languageReadmePathIn dir
        unless (null gaps) $ do
          say ""
          say ("lips could not do these, and says why in " <> T.pack account <> ":")
          mapM_ (\g -> note ("- " <> gapSlug g)) gaps
        unless (null held) $ do
          say ""
          say ("→ read the whole account: " <> T.pack account)
          mapM_ (\f -> say ("→ build it:              lips compile " <> T.pack f)) files
        -- A world that could not be served is reported last, after everything that
        -- held is on disk, and it still fails the run: CI must not mistake a
        -- language that reaches some of its worlds for one that reaches them all.
        unless (null failed) $ do
          forM_ failed $ \(w, why) -> say ("\n" <> w <> ": " <> why)
          exitWith (ExitFailure 1)

-- | Write what this run of @generate@ cost, beside the record of what it was
-- made of ('Lips.Generate.Stats' says why the two are separate files).
--
-- Called on every exit, so it must be silent about a run that never minted: a
-- refusal before the model answered (a world that resolves to nothing, a schema
-- that will not build) has no cost to report, and a lone @.timing@ in a folder
-- that holds no engine yet would be a file about nothing. Hence the condition:
-- write when the folder already exists, or when the mint answered.
writeMintStats :: POSIXTime -> IORef (Maybe PiReply) -> String -> [World]
                -> [FilePath] -> IO ()
writeMintStats _ _ _ _ [] = pure ()
writeMintStats t0 costCell thinking worlds (rep : _) = do
  ps <- phaseLog
  mpi <- readIORef costCell
  now <- getPOSIXTime
  let dir = langDir rep
      stats = MintStats
        { mtVerdict  = verdictOf ps
        , mtModel    = maybe "" prModel mpi
        , mtThinking = T.pack thinking
        , mtWall     = realToFrac (now - t0)
        , mtPhases   = ps
        , mtTurns    = maybe 0 prTurns mpi
        , mtTools    = maybe [] prTools mpi
        , mtUsage    = mpi >>= prUsage
        }
      -- Filed at the scope of the event, exactly as the record and the refusal
      -- artifact are: one call is one cost, however many worlds it wrote for.
      path = case map wName worlds of
               [w] -> timingPathIn dir w rep
               _   -> languageTimingPathIn dir rep
  folder <- doesDirectoryExist (takeDirectory path)
  when (folder || isJust mpi) $ do
    createDirectoryIfMissing True (takeDirectory path)
    TIO.writeFile path (renderStats stats)
    note ("cost recorded in " <> T.pack path)

-- | What one world's mint produced, once every gate over it held. Kept so the
-- write step below can file each world's own files without re-running anything.
data WorldResult = WorldResult
  { wrEngine    :: EngineData
  , wrValidated :: [(FilePath, Realization)]
  , wrExpects   :: [Expect]
  , wrCommitted :: Maybe Text   -- ^ the contract as committed, to write only on change
  }

-- | Every gate one world must pass, over its own engine: the shared grammar
-- plus the rules tagged for it. A refusal is returned, not thrown, because a
-- world that cannot serve the program is that world's failure alone -- the
-- others are still written (the measurement's case: kubernetes needs a
-- container image the program never states, NixOS does not).
--
-- Two gates stay fatal for the whole run, deliberately. An option path that
-- exists in no schema means the mint hallucinated a name, and a mint that
-- invents is not a mint half of whose output should be kept; and the nixpkgs
-- lookup behind the artifact build is a tool failure, not a verdict.
gateOneWorld :: Compat -> FilePath -> [(FilePath, Text)] -> [ItemCandidate]
             -> (Realization -> FilePath -> IO ()) -> World -> FilePath -> Text
             -> IO (Either Text WorldResult)
gateOneWorld compat rep progs candidates stage world schemaPath pin = runExceptT $ do
  let wn   = wName world
      eng0 = assemble (itemsFor wn candidates)
  -- Validate the engine EXACTLY as it will be persisted: render and read it
  -- back, so any round-trip drift is caught at mint time rather than on a later
  -- compile. The read-back engine is what gets written.
  eng <- case readLang (renderLang (FromSource (SourceLoc "lang" 0)) eng0) of
    Left es -> throwE (validationReport rep ("the setup can't be saved and reloaded cleanly:\n"
                        <> T.unlines (map renderParseError es)))
    Right e -> pure e
  case engineViolations (T.pack (languageName rep)) eng of
    []      -> pure ()
    (v : _) -> throwE (validationReport rep v)
  lift (assertOptionsAdmissible world schemaPath rep eng)
  -- Every program must crystallize, run, and parse as Nix under this world's
  -- engine: the example set is the regeneration corpus.
  validated <- forM progs $ \(f, t) -> do
    -- The same composition check runs, so the gate that decides judges what the
    -- draft door judged: a program calling a name another language lends must
    -- not be accepted at the door and refused here.
    imports <- lift (resolveImports [f] wn f (usesOf f eng t))
    case validate (lentNames imports) f eng t of
     Left (FailRun (Unmapped ds))      -> throwE (unportableReport f wn ds)
    -- At mint time the remedy has two sides (state it in the program, or mint
    -- again so a rule fills it), so the existing message stands; what several
    -- worlds add is WHICH world is asking, since the kubernetes lowering wants
    -- an image the NixOS one does not.
     Left (FailRun (OpenQuestions qs)) -> throwE (demandGenerateFail f qs)
     Left ff                           -> throwE (validationReport f (failureReport f ff))
     Right rl0 -> do
      let rl = composeWith imports rl0
      nixCheck <- lift (nixParses (rlModule rl))
      case nixCheck of
        Left (NixToolMissing e) -> lift (die (nixMissing f "verify the output" "generate" e))
        Left (NixInvalid why)   -> throwE (validationReport f ("the configuration lips produced isn't valid Nix:\n" <> why))
        Right ()                -> pure (f, rl)
  let claims = concatMap (rlClaims . snd) validated
  case unplaceableClaims (wClaims world) claims of
    []  -> pure ()
    ids -> throwE (report
      (T.pack rep <> ": " <> plural (length ids) "claim"
        <> " must be observed in a booted machine, and the " <> wn <> " world has none.")
      ids
      ("\8594 state the observable over the program's own binary, which needs no"
        <> " machine, and mint again: lips generate " <> T.pack rep))
  -- Mint glue is what the next mint rewrites, so a claim must run it. Judged
  -- here, before anything costs a build: which artifact a claim runs is read
  -- off the realization, not observed.
  forM_ validated $ \(f, rl) -> case gUnpinned (groundingOf f eng rl) of
    [] -> pure ()
    us -> throwE (unpinnedGlueReport f wn us)
  -- Which contract governs is one word from the human (--compat), applied to the
  -- committed set and this run's minted one, per world: a contract pins option
  -- paths, and an option path exists inside one world's namespace only.
  committed <- lift (tryRead (expectPathIn (langDir rep) wn rep))
  committedExps <- case maybe (Right []) readExpect committed of
    Left es -> throwE (report
      (T.pack (expectPathIn (langDir rep) wn rep) <> " is unreadable, so lips can't verify against it:")
      [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
      ("→ fix or delete " <> T.pack (expectPathIn (langDir rep) wn rep) <> ", then run generate again."))
    Right xs -> pure xs
  expects <- case rebless compat (edRules eng) committedExps (expectsOf (itemsFor wn candidates)) of
    Right xs  -> pure xs
    Left kept -> throwE (report
      (T.pack rep <> ": this run drops " <> plural (length kept) "check"
        <> " the " <> wn <> " engine still fills, which --compat forwards does not permit:")
      [ renderAttrPath (exPath e) | e <- kept ]
      ("→ keep them (drop --compat forwards), or accept the loss deliberately: "
        <> "lips generate --compat none " <> T.pack rep))
  case uncheckableExpects (edRules eng) expects of
    bad@(_ : _) -> throwE (uncheckableReport rep bad)
    []          -> pure ()
  case unholdableExpects (edPatterns eng) (edRules eng) expects of
    bad@(_ : _) -> throwE (validationReport rep (unholdableProblem bad))
    []          -> pure ()
  -- Every relative path a module names must be in the tree this mint stages: a
  -- mint that emits `src ./artifacts/<name>` but writes its source under another
  -- name is refused here instead of shipping a broken build.
  forM_ validated $ \(f, rl) -> lift (stagedGate (stage rl) f rl)
  -- A phase line rather than a `step`: a world may refuse here while the others
  -- hold, and a step that printed a tick for a refusal would say the contract
  -- held when it did not.
  lift (note (wn <> " contract: " <> plural (length expects) "check"))
  forM_ validated $ \(f, rl) -> do
    gate <- lift (runExpects (stage rl) (instanceName f) expects rl)
    case gate of
      Left (ToolMissing e) -> lift (die =<< pure (nixMissing f "verify the output" "generate" e))
      Left (EvalFailed e)  -> throwE (nixEvalFailed f "generate" e)
      Left (Violations fs broken) -> throwE (report
        ("lips built a " <> wn <> " setup for " <> T.pack f
          <> ", but it doesn't produce what the program promises:")
        fs
        -- Name the SMALLEST mode that would admit this change.
        ("→ run generate again. If you changed the program on purpose, accept "
          <> "the new behavior: lips generate --compat "
          <> compatSlug (smallestCompat (edRules eng) broken) <> " " <> T.pack rep
          <> " (rewrites " <> T.pack (expectPathIn (langDir rep) wn rep) <> ")."))
      Right () -> pure ()
  -- The gates that observe rather than read, last, so a mint that fails for a
  -- readable reason never pays a build. Every one builds against the nixpkgs
  -- the compiled flake will name for the pin this mint records, so the mint
  -- observes what `check` reads back from the record and builds against.
  let nixpkgs = compiledNixpkgs world (Just pin)
  forM_ validated $ \(f, rl) -> lift (artifactGate nixpkgs (stage rl) f rl)
  -- The world's own verdict over its render, where the world declares one.
  forM_ validated $ \(f, rl) -> lift (worldGate nixpkgs world f rl)
  forM_ validated $ \(f, rl) -> lift (clauseClaimGate world nixpkgs f rl)
  forM_ validated $ \(f, rl) -> lift (mintClaimGate nixpkgs (stage rl) f rl)
  lift (mapM_ note (ignoreNotes wn eng))
  pure WorldResult { wrEngine = eng, wrValidated = validated
                   , wrExpects = expects, wrCommitted = committed }

-- | Write one world's own files. The record and the account are written here
-- only when the event covered this world ALONE; a call covering several files
-- both at the language level, where its outputs are.
writeWorld :: FilePath -> FilePath -> String -> Text -> Text -> [Gap] -> Bool
           -> World -> WorldResult -> IO ()
writeWorld dir rep lang rec reportBody gaps single world wr = do
  let w = wName world
      (_, rulesText) = splitEngine (renderLang (FromGeneration (genId rec)) (wrEngine wr))
  createDirectoryIfMissing True (worldDirIn dir w)
  TIO.writeFile (rulesPathIn dir w rep) rulesText
  -- The world travels WITH the engine: the record pins this copy by hash, and
  -- compile reads the copy, never the search path.
  TIO.writeFile (worldPathIn (worldDirIn dir w) w) (wRaw world)
  if single
    then do
      TIO.writeFile (generationPathIn dir w rep) rec
      TIO.writeFile (readmePathIn dir w) (renderReadme (T.pack lang) reportBody gaps)
    -- A joint mint files its record and its account at the language level, so
    -- any per-world pair left by an earlier single-world mint now describes an
    -- event that did NOT write these rules. Removed rather than left to be
    -- preferred by the next reader (invariant 6: a line's stamp must name the
    -- generation that wrote it).
    else do
      removePathForcibly (generationPathIn dir w rep)
      removePathForcibly (readmePathIn dir w)
  -- A refusal artifact describes a run that produced no engine, so it is a lie
  -- once one exists.
  removePathForcibly (gapPathIn dir w rep)
  -- Write the contract the mode settled on, and only when it differs from what
  -- is committed: --compat full writes nothing, a first mint bootstraps, and the
  -- two relaxing modes leave the .expect diff as the semantic changelog.
  let contract = renderExpect (wrExpects wr)
  when (wrCommitted wr /= Just contract) $ TIO.writeFile (expectPathIn dir w rep) contract
  mapM_ note
    [ T.pack (rulesPathIn dir w rep) <> "  the " <> w <> " lowering, "
        <> plural (length (edRules (wrEngine wr))) "rule"
    , T.pack (expectPathIn dir w rep) <> "  its contract, "
        <> plural (length (wrExpects wr)) "check" ]

-- | The record that governs a world: its own, when it was minted alone, else
-- the language-level record of the call that covered it.
governingRecord :: FilePath -> Text -> FilePath -> IO (Maybe Text)
governingRecord dir w file = do
  own <- tryRead (generationPathIn dir w file)
  case own of
    Just r  -> pure (Just r)
    Nothing -> tryRead (languageRecordPathIn dir file)

-- | Crystallize and fully run the program with a candidate engine; on success
-- return the crystal and the realized module.
-- The module and the artifact.nix (the buildable derivations, or Nothing) are
-- projected from the same bound rules and ground base, so the artifacts a
-- compiled flake addresses are exactly the ones the module @let@-binds.
-- @lent@ is the names other languages lend this one, in the clause vocabulary;
-- empty for a program that composes with nothing.
validate :: [Text] -> FilePath -> EngineData -> Text -> Either Failure Realization
validate lent file eng program =
  case crystallize file (edPatterns eng) program of
    Left errs  -> Left (FailRead errs)
    Right base ->
      -- Language reuse: the shared grammar names its per-instance attrsOf key by
      -- <self>, bound here to this program's instance name (its file basename).
      -- The merge mode is derived from the rule emits (a subject whose rule
      -- emits a VList rhs appends); the BOUND emits carry the instance name in
      -- place of <self>, so they match the concrete Meta subjects resolve sees.
      let inst       = instanceName file
          boundRules = map (bindSelf inst) (edRules eng)
          modeOf     = mergeModeOf boundRules
          runEngine  = Engine (map toRule boundRules) (map toDemand (edDemands eng))
                              (edIgnores eng)
          -- Whether a list option keeps repeated elements is knowledge about that
          -- option, so the engine states it; nothing declared means a set (two
          -- program lines naming one thing name it once).
          assembleList = assembleWith (keepsRepeats (edMerges eng))
      in first FailRun (runBase modeOf assembleList (withLent lent schemeVocabulary) budget runEngine base)

-- | What vouches for each assertion of a run, counted against the rules it was
-- run with: the mint-written words are read from those rules' templates, since
-- the ground decisions only hold the filled values.
groundingOf :: FilePath -> EngineData -> Realization -> Grounding
groundingOf file eng rl =
  grounding (emitTemplate (instanceName file) (edRules eng) (Base.toList (rlBase rl)))
            [ (dSubject d, d) | d <- Base.toList (rlGround rl) ]

-- | Check the realized module parses as Nix (closes the garbage-rhs hole at
-- mint time). A missing @nix-instantiate@ is a loud failure: an unverifiable
-- engine is not written (deduce-or-fail).
-- | Two outcomes of the Nix parse check, kept apart so the CLI can tell the
-- user to install nix (tool missing) rather than blame the generated setup
-- (invalid Nix).
data NixParse = NixToolMissing Text | NixInvalid Text

nixParses :: Text -> IO (Either NixParse ())
nixParses nixModule = do
  result <- try (readProcessWithExitCode "nix-instantiate" ["--parse", "-"] (T.unpack nixModule))
  pure $ case result of
    Left e -> Left (NixToolMissing (tshow (e :: IOException)))
    Right (ExitSuccess, _, _)   -> Right ()
    Right (ExitFailure _, _, e) -> Left (NixInvalid (T.pack e))

-- | Call pi in json print mode as the model gateway: no tools, no session, a
-- fixed system prompt, the program as the user prompt. pi handles provider
-- auth. lips picks no model by default: when none is given @--model@ is
-- omitted and pi's own configured default applies. Either way the json stream
-- reports the model actually used, which the caller records, so provenance
-- stays concrete without a model baked into the deliverable.
-- Returns the whole 'PiReply': the mint's own reply and provenance, plus what
-- the run COST (turns, tool counts, tokens), which the caller records beside the
-- engine. Handing back a tuple of the three fields it happened to need meant
-- the numbers pi already reported were parsed and dropped.
callPi :: Bool -> Maybe String -> String -> Text -> Text -> [World] -> [FilePath]
       -> [(Text, FilePath)] -> [(Text, FilePath)] -> [(Text, String)] -> FilePath -> IO PiReply
callPi verbose mmodel thinking system userPrompt worlds files expects schemas pins basisDir =
  -- The answer travels in a file, not in the model's words, so generate owns a
  -- scratch directory for the whole call and the tool writes into it. The
  -- directory is created and the file is NOT: its absence is the signal that no
  -- draft was ever submitted.
  withTempDir $ \answerDir -> do
  -- Two files, and the names say which is which: @answer@ is the last draft that
  -- passed every gate this door can run, @draft@ is everything submitted so far,
  -- which the next submission patches. Neither exists until the tool submits.
  let answerPath = answerDir </> "answer"
      draftPath  = answerDir </> "draft"
  -- The mint's tools ship with the binary; without them a mint would have to
  -- recall option names instead of looking them up, and could not check a draft
  -- before answering -- the guessing this whole path exists to prevent. So a
  -- missing extension is fatal, not a silent downgrade to a weaker mint.
  -- An EMPTY variable counts as unset: lookupEnv reports Just "" for it, which
  -- would hand pi a bare @-e ""@ and fail somewhere less obvious.
  toolsPath <- lookupEnv "LIPS_MINT_TOOLS"
  extArgs <- case toolsPath of
    Just p | not (null p) -> pure ["-e", p]
    _ -> die (report
      "lips can't run the mint: its tool extension is not installed."
      ["LIPS_MINT_TOOLS is unset."]
      "→ run the packaged lips: nix run . -- generate <program>")
  -- The extension reads the world to search from the environment, and refuses
  -- to load without it: a mint for one world must never be answered from
  -- another world's schema.
  --
  -- What the draft tool may NOT choose is also set here: the programs it is
  -- judged against (a model picking its own corpus could validate against one
  -- that is not being minted), the governing contract, and the schema this run
  -- was grounded against.
  parentEnv <- getEnvironment
  -- One entry per world, because one call may write for several: the tool asks
  -- about the world it names, and a draft is judged in every world it is for.
  let pairs xs = intercalate "\n" [ T.unpack w <> "=" <> p | (w, p) <- xs ]
      ours = [ ("LIPS_MINT_WORLDS",   intercalate "," (map (T.unpack . wName) worlds))
             , ("LIPS_MINT_PROGRAMS", intercalate "\n" files)
             -- Empty means "the draft's own minted expects govern", which is a
             -- first mint or --renew.
             , ("LIPS_MINT_EXPECTS",  pairs expects)
             , ("LIPS_MINT_SCHEMAS",  pairs schemas)
             -- The pin each schema was built from, as the record will name it:
             -- the door's clause claims build against it.
             , ("LIPS_MINT_PINS",     pairs pins)
             -- Where a checked draft becomes the answer. The tool stages here;
             -- nothing else lips runs writes this path.
             , ("LIPS_MINT_ANSWER",   answerPath)
             -- Where the call's submissions accumulate, so a REFUSED draft is
             -- fixed by restating the line the gate named instead of the whole
             -- engine (output tokens are the mint's wall clock, DESIGN 13).
             , ("LIPS_MINT_DRAFT",    draftPath)
             -- The language folder whose committed engine a PATCH is merged with
             -- before it is judged. Empty under --fresh and on a first mint, and
             -- then the draft tool judges the reply alone, as it always did. The
             -- directory, not the text: the tool reads the same files through
             -- Lips.Identity, so the two cannot drift.
             , ("LIPS_MINT_BASIS",    basisDir)
             ]
      childEnv = ours ++ filter ((`notElem` map fst ours) . fst) parentEnv
      -- Hermetic by explicit subtraction: -nbt drops pi's built-in tools (read,
      -- bash, edit, write, grep, find, ls -- none of which the mint may touch),
      -- --no-extensions/--no-skills/--no-prompt-templates drop whatever the user
      -- happens to have installed, -nc drops ambient AGENTS.md/CLAUDE.md context
      -- files (global, and walking up from cwd). What remains is the two tools
      -- this run loads on purpose, so the mint's world equals what the record
      -- pins -- no input steers generation without entering genId's hash.
      -- --mode json: so the model pi resolved, and every lookup it made, are
      -- machine-readable in the reply.
      args = [ "-p", "-nbt", "-nc", "--no-extensions", "--no-skills"
             , "--no-prompt-templates", "--no-session", "--mode", "json"
             , "--system-prompt", T.unpack system
             -- --thinking is ALWAYS passed: an inherited reasoning level would
             -- steer the mint without entering the record (invariant 6).
             , "--thinking", thinking ]
               ++ extArgs ++ maybe [] (\m -> ["--model", m]) mmodel
  -- Everything that goes out, before anything comes back: under --verbose the
  -- prompt is shown as SENT (system prompt, direction and corpus), so a mint is
  -- reproducible from what the terminal showed.
  when verbose $ do
    say "--- system prompt (as sent) ---"
    say system
    say "--- programs (as sent) ---"
    say userPrompt
    say "--- waiting for the model ---"
  (code, out, err) <- streamPi verbose ((proc "pi" args) { env = Just childEnv }) userPrompt
  case code of
    ExitSuccess   -> do
      let parsed = parsePiReply (T.pack out)
          model = prModel parsed
      -- The engine is what the mint SUBMITTED, never what it said: submit_draft
      -- stages a draft only once every gate lips can run before the answer
      -- passes it, so the checked draft and the answer are the same bytes by
      -- construction. The model's own words stay in the transcript as
      -- provenance and are read as nothing else.
      staged <- doesFileExist answerPath
      reply <- if staged then TIO.readFile answerPath else pure T.empty
      if not staged
        then die noSubmission
        else if T.null reply
          then die emptySubmission
        -- pi always reports the model; an empty value would break provenance.
        else if T.null model
          then die (report "pi didn't report which model it used, so lips can't record provenance." [] "→ update pi, then run generate again.")
          -- An empty transcript is legitimate: a mint that needed no lookup made
          -- none. Only a MISSING record of one it did make would break invariant 6.
          -- The engine travels in the staged answer file, not in the model's
          -- words, so the reply field is replaced by what was submitted.
          else pure parsed { prReply = reply }
    ExitFailure c -> die (report
      ("lips couldn't run the AI model (pi exited " <> tshow c <> "):")
      (T.lines (T.pack err))
      "→ check that pi is installed and authenticated, then run generate again.")

-- | Run pi and show what it does WHILE it does it. The mint is the one phase
-- that takes minutes, and reading its whole output at the end (which is what
-- @readCreateProcessWithExitCode@ does) made a working model and a hung one look
-- identical for that whole time.
--
-- Three streams, three jobs: the prompt is written by its own thread (a prompt
-- larger than a pipe buffer would deadlock if written inline, as soon as pi's
-- output filled ours), stderr is drained by another (it is only read on
-- failure, but an undrained pipe blocks the child), and the main loop reads
-- stdout line by line, showing each event and keeping every line -- so
-- 'parsePiReply' still sees the complete stream and the record is unchanged.
streamPi :: Bool -> CreateProcess -> Text -> IO (ExitCode, String, String)
streamPi verbose cp promptText = do
  (mIn, mOut, mErr, ph) <- createProcess cp
    { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe }
  (hin, hout, herr) <- case (mIn, mOut, mErr) of
    (Just a, Just b, Just c) -> pure (a, b, c)
    -- Unreachable: all three are CreatePipe above. Loud rather than a pattern
    -- match failure with no explanation.
    _ -> die (report "lips couldn't open a pipe to the AI model." []
                     "→ report this as a lips bug.")
  mapM_ (`hSetEncoding` utf8) [hin, hout, herr]
  hSetBuffering hout LineBuffering
  _ <- forkIO (TIO.hPutStr hin promptText `finally` hClose hin)
  errVar <- newEmptyMVar
  _ <- forkIO (hGetContents herr >>= \e -> length e `seq` putMVar errVar e)
  prose <- newIORef T.empty   -- partial line of the model's own words (verbose)
  seen  <- newIORef []        -- every stdout line, newest first
  let loop = do
        eof <- hIsEOF hout
        unless eof $ do
          l <- TIO.hGetLine hout
          modifyIORef' seen (l :)
          showEvent verbose prose (progressEvent l)
          loop
  loop
  leftover <- readIORef prose
  when (verbose && not (T.null leftover)) (say leftover)
  code <- waitForProcess ph
  errText <- takeMVar errVar
  ls <- reverse <$> readIORef seen
  pure (code, T.unpack (T.unlines ls), errText)

-- | Show one mint event. The ordinary view is one dim line per tool call and
-- one per answer, with the model's state on the live line; @--verbose@ adds the
-- model's own words as they arrive and the untruncated arguments and answers.
showEvent :: Bool -> IORef Text -> Maybe PiEvent -> IO ()
showEvent _ _ Nothing = pure ()
showEvent verbose prose (Just ev) = case ev of
  PiTool name args -> do
    setState ("running " <> name)
    note (name <> "  " <> if verbose then args else abbreviate 60 args)
  PiToolEnd name failed text -> do
    setState "waiting for the model"
    if verbose
      then note ("  → " <> name <> (if failed then " failed:" else " answered:")) >> say text
      else note ("  → " <> resultSummary failed text)
  PiState s -> setState s
  PiProse d -> do
    setState "writing the engine"
    -- Deltas arrive mid-word, so verbose prints them a LINE at a time: the
    -- remainder waits in the buffer until its newline shows up.
    when verbose $ do
      buffered <- readIORef prose
      let (whole, partial) = T.breakOnEnd "\n" (buffered <> d)
      writeIORef prose partial
      mapM_ say (T.lines whole)


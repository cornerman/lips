{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI (crystallization plan).
--
--   * @lips generate [model] \<program\>@ is the one AI step: the model mints a
--     /language/ (patterns) for the loose program; the kernel crystallizes the
--     program with it and validates by a full run; only then are the language
--     (@\<program\>.lang@), the crystal witness (@\<program\>.decisions@), and
--     the generation record written.
--   * @lips print \<program\>@ takes the loose program directly. It
--     crystallizes it with @\<program\>.lang@ and realizes it to a NixOS
--     module text on stdout, deterministically, with no AI. If the language is
--     missing, or the program escaped it, it fails loud and names @generate@.
--   * @lips run \<program\>@ goes one step further and literally runs the
--     realized module: it wraps it in a NixOS system and boots it as a local
--     QEMU VM (a Heile-Welt simulation of the target machine; the host is
--     never mutated). Host deployment stays a separate, explicit step.
module Main (main) where

import           Control.Exception  (IOException, try)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs, getProgName)
import           System.Exit        (ExitCode (..), exitFailure)
import           System.IO          (hFlush, stderr, stdout)
import           System.Process     (callCommand, readProcessWithExitCode)
import           Text.Read          (readMaybe)

import           Lips.Kernel.Engine.Data       (toDemand, toRule)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Minting  (ItemCandidate (..), SourceFile (..), assemble, expectsOf, parseEngineCandidates, promptWithDirection, sourcesOf, uncheckableExpects)
import           Lips.Generate.PiJson   (PiReply (..), parsePiReply)
import           Lips.Generate.Record   (genId, record)
import           Lips.Kernel.Base       (Conflict (..), Base)
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect     (Expect (..), checkValues, evalExpr, expectedValue, readExpect, renderExpect)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Refine     (RefineError (..))
import           Lips.Kernel.Run
import           Lips.Kernel.Lang.Crystallize  (CrystError (..), LineOutcome (..), crystallize)
import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..), diagnose)
import           Lips.Kernel.Lang.Lang         (EngineData (..), readLang, renderLang)
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
  args <- getArgs
  case args of
    ["print", file]      -> printLoose file
    ["run", file]        -> runVm file
    ["check", file]      -> checkLoose file
    ["lsp"]              -> runLsp
    ("generate" : rest)  -> case parseGenerate rest of
      Just (conf, mmodel, file) -> generate conf mmodel file
      Nothing                  -> usage >> exitFailure
    _                    -> usage >> exitFailure

-- | Parse @generate@ arguments: an optional @--confidence <0..1>@ flag in any
-- position, then @[model] <program-file>@. A malformed or out-of-range
-- threshold, or the wrong number of positionals, fails loud (returns Nothing).
parseGenerate :: [String] -> Maybe (Double, Maybe String, FilePath)
parseGenerate = go Nothing []
  where
    go _ pos ("--confidence" : v : rest)
      | Just c <- readMaybe v, c >= 0, c <= 1 = go (Just c) pos rest
      | otherwise                             = Nothing
    go _ _ ["--confidence"]      = Nothing
    go conf pos (a : rest)       = go conf (pos ++ [a]) rest
    go conf pos []               = finish (maybe defaultConfidence id conf) pos
    -- No model given: omit --model so pi's own configured default applies;
    -- the model pi reports is read back and recorded. An explicit model still
    -- works as the optional first positional.
    finish c [file]        = Just (c, Nothing, file)
    finish c [model, file] = Just (c, Just model, file)
    finish _ _             = Nothing

usage :: IO ()
usage = do
  name <- T.pack <$> getProgName
  TIO.hPutStr stderr $ T.unlines
    [ "lips turns a plain-English .loose program into a NixOS configuration."
    , ""
    , "usage:"
    , "  " <> name <> " generate [--confidence <0..1>] [model] <program.loose>"
    , "      Build the program's setup and verify it. The one step that uses AI."
    , "  " <> name <> " print <program.loose>"
    , "      Show the NixOS configuration the program produces."
    , "  " <> name <> " run <program.loose>"
    , "      Boot that configuration as a throwaway local VM."
    , "  " <> name <> " check <program.loose>"
    , "      Verify the program still produces what it promised."
    ]

-- | @print@: crystallize the loose program with its language, realize it, and
-- write the NixOS module text to stdout. Pure and deterministic (no AI).
printLoose :: FilePath -> IO ()
printLoose file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left f            -> die (printFail file f)
    Right (_, nixMod) -> TIO.putStr nixMod

-- | @run@: realize the program, then literally run it -- wrap the module in a
-- NixOS system and boot it as a local QEMU VM. The realization is the same
-- deterministic tail as @print@; only the booting is impure (it uses the
-- ambient @<nixpkgs>@, a Heile-Welt softness noted in the design). The host is
-- never touched; the VM is a throwaway simulation.
runVm :: FilePath -> IO ()
runVm file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left f            -> die (printFail file f)
    Right (_, nixMod) -> bootVm file (stageFromDisk file) nixMod

bootVm :: FilePath -> (FilePath -> IO ()) -> Text -> IO ()
bootVm file stage nixMod = do
  dir <- mkTempDir
  let tmp = dir <> "/module.nix"
  TIO.writeFile tmp nixMod
  stage (dir <> "/artifacts")
  TIO.hPutStrLn stderr "building a local NixOS VM from your configuration..."
  built <- try (readProcessWithExitCode "nix"
                  [ "build", "--impure", "--no-link", "--print-out-paths"
                  , "--expr", T.unpack (vmExpr tmp) ] "")
  case built of
    Left e -> die (nixMissing file "boot the VM" "run" (tshow (e :: IOException)))
    Right (ExitFailure _, _, err) ->
      die (report
        "the VM didn't build:"
        (T.lines (T.pack err))
        ("→ the run simulation needs nixpkgs. Try: nix run . -- run " <> T.pack file
          <> ", or set NIX_PATH to a nixpkgs."))
    Right (ExitSuccess, out, _) -> do
      let outPath = T.unpack (T.strip (T.pack out))
      TIO.hPutStrLn stderr "booting the VM (quit QEMU with Ctrl-a x)..."
      -- The qemu-vm module names the boot script run-<host>-vm; glob it so the
      -- hostname is not hard-coded. The shell inherits stdio for the console.
      callCommand (outPath <> "/bin/run-*-vm")

-- | An impure Nix expression that turns a realized module (at @modPath@) into a
-- bootable, headless local VM via the stock qemu-vm module.
vmExpr :: FilePath -> Text
vmExpr modPath = T.pack $ unlines
  [ "let"
  , "  system = builtins.currentSystem;"
  , "  nixpkgs = <nixpkgs>;"
  , "  cfg = import (nixpkgs + \"/nixos/lib/eval-config.nix\") {"
  , "    inherit system;"
  , "    modules = ["
  , "      (nixpkgs + \"/nixos/modules/virtualisation/qemu-vm.nix\")"
  , "      " <> modPath
  , "      { system.stateVersion = \"24.11\";"
  , "        virtualisation.graphics = false;"
  , "        users.users.root.password = \"\"; }"
  , "    ];"
  , "  };"
  , "in cfg.config.system.build.vm"
  ]

-- | @check@: verify the program's committed behavioral contract holds against
-- its realized module, deterministically (no AI). This is the offline guardian
-- of the @.expect@ spec; @generate@ runs the same check before accepting an
-- engine, and the flake check shells this per example.
checkLoose :: FilePath -> IO ()
checkLoose file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  -- First phase, pure and offline: how the program sits in its language.
  -- Always shown, so authoring is never blind; the behavioral gate runs only
  -- once the program crystallizes cleanly and completely.
  let d = diagnose file eng program
  TIO.putStrLn (renderDiagnosis file d)
  hFlush stdout  -- so the report lands before any stderr failure below
  if any escapes (diagLines d)
    then die (report
           (T.pack file <> " has lines its language cannot read yet.")
           []
           ("→ grow the language: lips generate " <> T.pack file))
    else if not (null (diagOpen d))
      then die (report
             (T.pack file <> " is incomplete while these questions stay open.")
             []
             "→ answer them by stating the detail in the program.")
      else expectGate file eng program
  where
    escapes Matched{} = False
    escapes _         = True

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
expectGate :: FilePath -> EngineData -> Text -> IO ()
expectGate file eng program = do
  expSrc <- tryRead (file <> ".expect")
  case expSrc of
    Nothing  -> TIO.putStrLn
      (T.pack file <> ": crystallizes cleanly; no behavioral contract yet ("
        <> T.pack file <> ".expect is missing, written by generate).")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        | otherwise -> case validate file eng program of
        Left f       -> die (printFail file f)
        Right (base, nixMod) -> do
          res <- runExpects (stageFromDisk file) expects base nixMod
          case res of
            Right () -> TIO.putStrLn (T.pack file <> ": all "
                          <> tshow (length expects) <> " checks pass.")
            Left (ToolMissing e) -> die (nixMissing file "check the program" "check" e)
            Left (EvalFailed e)  -> die (nixEvalFailed file "check" e)
            Left (Violations fs) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))

-- | Render the authoring diagnosis: a coverage headline, one line per program
-- line (matched to which pattern and subject, or unread, or ambiguous), then
-- the open questions. Pure view over 'diagnose'; a future editor paints the
-- same outcomes as squiggles.
renderDiagnosis :: FilePath -> Diagnosis -> Text
renderDiagnosis file d = T.intercalate "\n" (headline : map row (diagLines d) ++ openBlock)
  where
    headline = T.pack file <> ": " <> tshow (diagMatched d) <> " of "
                 <> tshow (diagTotal d) <> " lines crystallize."
    row (Matched n _ pid dec) =
      "  line " <> tshow n <> "  ok        " <> pid <> "  " <> subjectPath (dSubject dec)
    row (Unmatched n t) =
      "  line " <> tshow n <> "  no match  \"" <> t <> "\""
    row (Ambiguous n _ ids) =
      "  line " <> tshow n <> "  ambiguous " <> T.intercalate "," ids
    openBlock
      | null (diagOpen d) = []
      | otherwise = "" : ("open questions (" <> tshow (length (diagOpen d)) <> "):")
                       : ["  - " <> q | q <- diagOpen d]
    subjectPath (Subject segs) = T.intercalate "." segs

-- | Load and parse a program's @.lang@, or fail loud naming @generate@.
loadLangOrDie :: FilePath -> IO EngineData
loadLangOrDie file = do
  let langFile = file <> ".lang"
  msrc <- tryRead langFile
  case msrc of
    Nothing  -> die (report
      (T.pack file <> " isn't set up yet (" <> T.pack langFile <> " is missing).")
      []
      ("→ create it: lips generate " <> T.pack file))
    Just src -> case readLang src of
      Left es  -> die (unreadable file ".lang" es)
      Right eng -> pure eng

-- | Read the program file, or fail with a plain message instead of a raw
-- exception when the path is wrong (a common typo at the shell).
readProgramOrDie :: FilePath -> IO Text
readProgramOrDie file = do
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
generate :: Double -> Maybe String -> FilePath -> IO ()
generate confidence mmodel file = do
  program <- readProgramOrDie file
  -- Optional owner taste for this program (mechanism preference, not
  -- obligations). Rides in the system prompt, so it enters the .generation
  -- record and genId; absent or blank changes nothing.
  direction <- tryRead (file <> ".direction")
  let prompt = promptWithDirection direction
  (reply, model) <- callPi mmodel prompt program
  let (errs, candidates) = parseEngineCandidates reply
      -- Deduce-or-fail: the program is the only source of truth, so an item the
      -- model cannot confidently derive means the program underspecifies it.
      unsure = [c | c <- candidates, let Confidence x = icConfidence c, x < confidence]
  if not (null errs) || not (null unsure)
    then die (refusalReport file confidence errs unsure)
    else do
      let eng0 = assemble (map icItem candidates)
      -- Validate the engine EXACTLY as it will be persisted: render to .lang and
      -- read it back, so any render/read round-trip drift is caught at mint
      -- time, not on a later `print`. The read-back engine is what we write.
      case readLang (renderLang (FromSource (SourceLoc "lang" 0)) eng0) of
       Left es  -> die (validationReport file ("the setup can't be saved and reloaded cleanly:\n" <> T.unlines (map renderParseError es)))
       Right eng -> case validate file eng program of
        Left f -> die (validationReport file (failureReport file f))
        Right (base, nixModule) -> do
          nixCheck <- nixParses nixModule
          case nixCheck of
            Left (NixToolMissing e) -> die (nixMissing file "verify the output" "generate" e)
            Left (NixInvalid why)   -> die (validationReport file ("the configuration lips produced isn't valid Nix:\n" <> why))
            Right () -> do
              -- Sources are minted in memory; stage them (not yet on disk) so
              -- the behavioral gate can evaluate the artifact derivations.
              let minted = sourcesOf (map icItem candidates)
              -- Behavioral gate: the realized module must satisfy the
              -- contract. On regeneration the COMMITTED contract governs (the
              -- stable spec regeneration may not silently break); on first
              -- generation the minted assertions bootstrap it.
              let mintedExpects = expectsOf (map icItem candidates)
              committed <- tryRead (file <> ".expect")
              let contract = maybe (Right mintedExpects) readExpect committed
              case contract of
                Left es -> die (report
                  (T.pack file <> ".expect is unreadable, so lips can't verify against it:")
                  [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
                  ("→ fix or delete " <> T.pack file <> ".expect, then run generate again."))
                Right expects
                 | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
                     die (uncheckableReport file bad)
                 | otherwise -> do
                  gate <- runExpects (\dst -> writeSources dst minted) expects base nixModule
                  case gate of
                    Left (ToolMissing e) -> die (nixMissing file "verify the output" "generate" e)
                    Left (EvalFailed e)  -> die (nixEvalFailed file "generate" e)
                    Left (Violations fs) -> die (report
                      ("lips built a setup for " <> T.pack file <> ", but it doesn't produce what the program promises:")
                      fs
                      ("→ run generate again. If you changed the program on purpose, delete "
                        <> T.pack file <> ".expect first to accept the new behavior."))
                    Right () -> do
                      -- The record is written first-class and every engine line
                      -- is stamped with its content id: line -> event, checkable
                      -- by re-hashing the .generation file.
                      let rec = record model confidence prompt program reply
                      TIO.writeFile (file <> ".lang") (renderLang (FromGeneration (genId rec)) eng)
                      TIO.writeFile (file <> ".decisions") (renderBase base)
                      TIO.writeFile (file <> ".generation") rec
                      -- Persist minted source only now that the whole loop held.
                      writeSources (file <> ".artifacts") minted
                      -- Bootstrap the contract on first generation only; keep
                      -- the committed spec stable across regenerations.
                      maybe (TIO.writeFile (file <> ".expect") (renderExpect mintedExpects))
                            (const (pure ())) committed
                      -- Prose to stderr so stdout stays the pipeable module.
                      TIO.hPutStr stderr $ T.unlines
                        [ "lips set up " <> T.pack file <> " and verified it produces a valid NixOS configuration."
                        , ""
                        , "→ preview it:  lips print " <> T.pack file
                        , "→ boot it:     lips run " <> T.pack file ]
                      TIO.putStr nixModule

-- | Crystallize and fully run the program with a candidate engine; on success
-- return the crystal and the realized module.
validate :: FilePath -> EngineData -> Text -> Either Failure (Base, Text)
validate file eng program =
  case crystallize file (edPatterns eng) program of
    Left errs  -> Left (FailRead errs)
    Right base ->
      case runBase budget (map toRule (edRules eng)) (map toDemand (edDemands eng)) base of
        Left err        -> Left (FailRun err)
        Right nixModule -> Right (base, nixModule)

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
callPi :: Maybe String -> Text -> Text -> IO (Text, Text)
callPi mmodel system userPrompt = do
  (code, out, err) <-
    readProcessWithExitCode "pi"
      -- -nc: the mint must be hermetic. pi otherwise injects ambient AGENTS.md/CLAUDE.md
      -- context files (global + walking up from cwd) - inputs that would steer generation
      -- without entering the .generation record or the genId hash.
      -- --mode json: so the model pi resolved is machine-readable in the reply.
      ([ "-p", "-nt", "-nc", "--no-session", "--mode", "json", "--system-prompt", T.unpack system ]
        ++ maybe [] (\m -> ["--model", m]) mmodel)
      (T.unpack userPrompt)
  case code of
    ExitSuccess   -> do
      let PiReply { prReply = reply, prModel = model } = parsePiReply (T.pack out)
      if T.null reply
        then die (report "the AI model returned no usable reply." [] "→ run generate again.")
        -- pi always reports the model; an empty value would break provenance.
        else if T.null model
          then die (report "pi didn't report which model it used, so lips can't record provenance." [] "→ update pi, then run generate again.")
          else pure (reply, model)
    ExitFailure c -> die (report
      ("lips couldn't run the AI model (pi exited " <> tshow c <> "):")
      (T.lines (T.pack err))
      "→ check that pi is installed and authenticated, then run generate again.")

-- | Evaluate the realized module with @nix@ and judge a contract against it.
-- One eval reads every asserted option; the pure comparison lives in
-- 'Lips.Kernel.Expect'. An empty contract passes trivially.
-- | Three outcomes of the behavioral check, kept apart so the CLI gives the
-- right action: install nix (tool missing), fix the environment (eval failed),
-- or the config doesn't carry the promised values (violations).
data ExpectFail = ToolMissing Text | EvalFailed Text | Violations [Text]

runExpects :: (FilePath -> IO ()) -> [Expect] -> Base -> Text -> IO (Either ExpectFail ())
runExpects _     []      _    _         = pure (Right ())
runExpects stage expects base nixModule =
  case traverse (expectedValue base) expects of
    Left e    -> pure (Left (Violations ["lips can't match a check to the program: " <> e]))
    Right pvs -> do
      dir <- mkTempDir
      let tmp = dir <> "/module.nix"
      TIO.writeFile tmp nixModule
      stage (dir <> "/artifacts")
      let expr = evalExpr tmp expects
      res <- try (readProcessWithExitCode "nix"
                    ["eval", "--raw", "--impure", "--expr", T.unpack expr] "")
      pure $ case res of
        Left e -> Left (ToolMissing (tshow (e :: IOException)))
        Right (ExitSuccess, out, _) ->
          let evaled = T.splitOn "\n" (T.pack out)
           in if length evaled /= length expects
                then Left (Violations ["nix returned " <> tshow (length evaled)
                           <> " values for " <> tshow (length expects) <> " checks"])
                else case checkValues expects (zip pvs evaled) of
                       [] -> Right ()
                       fs -> Left (Violations fs)
        Right (ExitFailure _, _, err) -> Left (EvalFailed (T.pack err))

die :: Text -> IO a
die msg = TIO.hPutStrLn stderr msg >> exitFailure

-- | A fresh temporary directory. lips writes a module and its staged
-- @artifacts/@ tree here so a relative @src = ./artifacts/<name>@ resolves at
-- evaluation. (Left in place, matching the module temp files elsewhere.)
mkTempDir :: IO FilePath
mkTempDir = do
  (_, out, _) <- readProcessWithExitCode "mktemp" ["-d", "/tmp/lips-XXXXXX"] ""
  pure (T.unpack (T.strip (T.pack out)))

-- | Write minted source files under @<root>/<artifact>/<relpath>@. Used to
-- persist to @<program>.artifacts@ and to stage into a temp module dir.
writeSources :: FilePath -> [SourceFile] -> IO ()
writeSources root = mapM_ one
  where
    one sf = do
      let p = root <> "/" <> T.unpack (sfArtifact sf) <> "/" <> T.unpack (sfPath sf)
      callCommand ("mkdir -p " <> shq (parentDir p))
      TIO.writeFile p (sfContent sf)

-- | Stage a program's committed @<file>.artifacts@ tree into @dst@ (the temp
-- module's @artifacts/@). A no-op when the program has no artifacts.
stageFromDisk :: FilePath -> FilePath -> IO ()
stageFromDisk file dst = do
  _ <- (try (readProcessWithExitCode "cp" ["-rT", file <> ".artifacts", dst] "")
          :: IO (Either IOException (ExitCode, String, String)))
  pure ()

-- | The directory part of a path (everything up to and including the last @/@).
parentDir :: FilePath -> FilePath
parentDir = T.unpack . fst . T.breakOnEnd "/" . T.pack

-- | Minimal single-quote shell escaping for a path passed to @mkdir -p@.
shq :: FilePath -> String
shq s = "'" <> concatMap (\c -> if c == '\'' then "'\\''" else [c]) s <> "'"

-- | The standard message skeleton: a plain headline, optional indented detail
-- lines, and a final "→" action. Every error the CLI prints is built from it,
-- so the product speaks with one voice.
report :: Text -> [Text] -> Text -> Text
report headline details action =
  T.intercalate "\n" $ [headline] ++ detail ++ ["", action]
  where detail = if null details then [] else "" : map ("  " <>) details

-- | Same skeleton without the action line, for a diagnosis another command
-- wraps with its own action.
reportHead :: Text -> [Text] -> Text
reportHead headline details =
  T.intercalate "\n" $ [headline] ++ (if null details then [] else "" : map ("  " <>) details)

-- | A validation failure kept structured (not pre-rendered) so each command
-- picks the right next action: on print/run some are the author's to edit,
-- others mean regenerate; generate frames all of them as a mint that did not
-- hold up.
data Failure = FailRead [CrystError] | FailRun RunError

-- | What went wrong and where, in plain words, with no action line (the caller
-- appends the action, which depends on the command).
failureReport :: FilePath -> Failure -> Text
failureReport file (FailRead errs) =
  reportHead (T.pack file <> " has lines its setup doesn't handle:") (map crystDetail errs)
  where
    crystDetail (NoPattern n t)   = "line " <> tshow n <> ": " <> t
    crystDetail (Overlapping n _) = "line " <> tshow n <> ": the setup reads this line more than one way"
failureReport file (FailRun err) = case err of
  ParseRejected es ->
    reportHead (T.pack file <> " has lines that couldn't be read:")
               [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  OpenQuestions qs ->
    reportHead (T.pack file <> " leaves questions its setup needs answered:") qs
  Conflicted cs ->
    reportHead (T.pack file <> " sets the same thing two ways:")
               [ niceSubject (conflictSubject c) <> ": "
                   <> loc (conflictLeft c) <> " and " <> loc (conflictRight c) | c <- cs ]
  RefineFailed e ->
    reportHead ("the setup lips built for " <> T.pack file <> " is broken, not your program:")
               [refineDetail e]
  Unmapped ds ->
    reportHead (T.pack file <> " asks for things its setup can't do:")
               [ loc d <> ": " <> niceSubject (dSubject d) | d <- ds ]

-- | The full message for a print/run failure: the diagnosis plus the action
-- that fits it -- edit the program (unanswered questions, a contradiction) or
-- rebuild the setup (everything else).
printFail :: FilePath -> Failure -> Text
printFail file f = failureReport file f <> "\n\n" <> act
  where
    act = case f of
      FailRun (OpenQuestions _) -> "→ answer each in " <> T.pack file <> ", then run again."
      FailRun (Conflicted _)    -> "→ keep only one of those lines in " <> T.pack file <> ", then run again."
      _                         -> "→ rebuild the setup: lips generate " <> T.pack file

refineDetail :: RefineError -> Text
refineDetail (Overlap _ _)         = "two of its rules claim the same thing"
refineDetail (Nonterminating _)    = "its rules loop without settling"
refineDetail (RewriteFailed _ _ m) = m

-- | A subject as plain words: its dotted segments spaced out, so route./hello
-- reads as "route /hello".
niceSubject :: Subject -> Text
niceSubject (Subject segs) = T.intercalate " " segs

-- | Where a decision came from, in author terms: a file location, or a note
-- that the setup computed it.
loc :: Decision -> Text
loc d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived _ _                -> "(computed by the setup)"
  FromGeneration _           -> "(from the setup)"

-- | A committed file lips can't read back (corrupted or hand-edited).
unreadable :: FilePath -> Text -> [ParseError] -> Text
unreadable file suffix es = report
  (T.pack file <> suffix <> " is unreadable, so lips can't use it:")
  [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  ("→ rebuild it: lips generate " <> T.pack file)

-- | nix is needed but couldn't run: a missing-tool failure (install it), never
-- the fault of the program or the generated setup.
nixMissing :: FilePath -> Text -> Text -> Text -> Text
nixMissing file what cmd detail = report
  ("lips needs nix to " <> what <> ", but couldn't run it:")
  (T.lines detail)
  ("→ install nix, or run lips through it: nix run . -- " <> cmd <> " " <> T.pack file)

-- | nix ran but evaluation failed: usually a missing nixpkgs, not the setup.
nixEvalFailed :: FilePath -> Text -> Text -> Text
nixEvalFailed file cmd detail = report
  "lips couldn't evaluate the configuration to check it:"
  (T.lines detail)
  ("→ this usually means nixpkgs isn't available. Try: nix run . -- " <> cmd <> " " <> T.pack file)

-- | generate couldn't build a setup: either lines lips couldn't read (a
-- capability may be missing) or values the program leaves underspecified.
refusalReport :: FilePath -> Double -> [Text] -> [ItemCandidate] -> Text
refusalReport file _threshold errs unsure = T.intercalate "\n" $
  ["lips couldn't build a setup for " <> T.pack file <> "."]
    ++ grammar ++ underspecified
  where
    grammar
      | null errs = []
      | otherwise =
          [ "", "The AI produced instructions lips couldn't read:" ]
          ++ [ "  - " <> e | e <- errs ]
          ++ [ ""
             , "→ run generate again. If the same line keeps failing, it's a"
             , "  capability lips lacks; please report it." ]
    underspecified
      | null unsure = []
      | otherwise =
          [ "", "The program doesn't pin these down (the AI wasn't confident enough):" ]
          ++ [ "  - " <> icLine c <> "   [confidence " <> conf c <> "]" | c <- unsure ]
          ++ [ ""
             , "→ state the missing detail in " <> T.pack file <> " and run again."
             , "  If the choice is genuinely free, lower the bar: --confidence 0.5" ]
    conf c = let Confidence x = icConfidence c in tshow x

-- | A behavioral check names an option a rule fills with a package or artifact
-- reference (a derivation, not a program value). Such a check can neither be
-- evaluated under the check's stubs nor meaningfully satisfied, so it is
-- rejected loud instead of crashing the eval (deduce-or-fail).
uncheckableReport :: FilePath -> [Expect] -> Text
uncheckableReport file bad = report
  (T.pack file <> " checks options that hold a package or build, not a value:")
  [ T.intercalate "." (exPath e) <> " (check " <> exId e <> ")" | e <- bad ]
  ("→ a check must name an option carrying a value from " <> T.pack file
    <> ". Rebuild the setup: lips generate " <> T.pack file)

-- | generate built a setup but it did not hold up: wrap a diagnosis with the
-- generate-time action (mint again; report a lips bug if it persists). Not the
-- program's fault.
validationReport :: FilePath -> Text -> Text
validationReport file problem = T.intercalate "\n"
  [ "lips built a setup for " <> T.pack file <> ", but it didn't hold up:"
  , ""
  , problem
  , ""
  , "→ run generate again. If it keeps failing the same way, it's a lips bug;"
  , "  please report it with the text above."
  ]

renderParseError :: ParseError -> Text
renderParseError e = "  line " <> tshow (peLine e) <> ": " <> peMessage e

tshow :: Show a => a -> Text
tshow = T.pack . show

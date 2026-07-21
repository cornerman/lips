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
import           System.IO          (hClose, hPutStrLn, openTempFile, stderr)
import           System.Process     (callCommand, readProcessWithExitCode)
import           Text.Read          (readMaybe)

import           Lips.Kernel.Engine.Data       (toDemand, toRule)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Minting  (ItemCandidate (..), assemble, expectsOf, parseEngineCandidates, systemPrompt)
import           Lips.Generate.Record   (genId, record)
import           Lips.Kernel.Base       (Conflict (..), Base)
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect     (Expect, checkValues, evalExpr, expectedValue, readExpect, renderExpect)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Run
import           Lips.Kernel.Lang.Crystallize  (CrystError (..), crystallize)
import           Lips.Kernel.Lang.Lang         (EngineData (..), readLang, renderLang)

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

-- | Default generation model, routed through pi. Overridable with a second arg.
defaultModel :: String
defaultModel = "anthropic/claude-opus-4-8"

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
    ("generate" : rest)  -> case parseGenerate rest of
      Just (conf, model, file) -> generate conf model file
      Nothing                  -> usage >> exitFailure
    _                    -> usage >> exitFailure

-- | Parse @generate@ arguments: an optional @--confidence <0..1>@ flag in any
-- position, then @[model] <program-file>@. A malformed or out-of-range
-- threshold, or the wrong number of positionals, fails loud (returns Nothing).
parseGenerate :: [String] -> Maybe (Double, String, FilePath)
parseGenerate = go Nothing []
  where
    go _ pos ("--confidence" : v : rest)
      | Just c <- readMaybe v, c >= 0, c <= 1 = go (Just c) pos rest
      | otherwise                             = Nothing
    go _ _ ["--confidence"]      = Nothing
    go conf pos (a : rest)       = go conf (pos ++ [a]) rest
    go conf pos []               = finish (maybe defaultConfidence id conf) pos
    finish c [file]        = Just (c, defaultModel, file)
    finish c [model, file] = Just (c, model, file)
    finish _ _             = Nothing

usage :: IO ()
usage = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " generate [--confidence <0..1>] [model] <program-file>")
  hPutStrLn stderr ("       " <> name <> " print <program-file>   (emit the realized NixOS module)")
  hPutStrLn stderr ("       " <> name <> " run <program-file>     (boot it as a local NixOS VM)")
  hPutStrLn stderr ("       " <> name <> " check <program-file>")

-- | @print@: crystallize the loose program with its language, realize it, and
-- write the NixOS module text to stdout. Pure and deterministic (no AI).
printLoose :: FilePath -> IO ()
printLoose file = do
  program <- TIO.readFile file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left problem      -> die problem
    Right (_, nixMod) -> TIO.putStr nixMod

-- | @run@: realize the program, then literally run it -- wrap the module in a
-- NixOS system and boot it as a local QEMU VM. The realization is the same
-- deterministic tail as @print@; only the booting is impure (it uses the
-- ambient @<nixpkgs>@, a Heile-Welt softness noted in the design). The host is
-- never touched; the VM is a throwaway simulation.
runVm :: FilePath -> IO ()
runVm file = do
  program <- TIO.readFile file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left problem      -> die problem
    Right (_, nixMod) -> bootVm nixMod

bootVm :: Text -> IO ()
bootVm nixMod = do
  (tmp, h) <- openTempFile "/tmp" "lips-module.nix"
  TIO.hPutStr h nixMod
  hClose h
  TIO.hPutStrLn stderr "lips: building a local NixOS VM from the realized module..."
  built <- try (readProcessWithExitCode "nix"
                  [ "build", "--impure", "--no-link", "--print-out-paths"
                  , "--expr", T.unpack (vmExpr tmp) ] "")
  case built of
    Left e -> die ("nix unavailable: " <> tshow (e :: IOException))
    Right (ExitFailure _, _, err) ->
      die ("could not build the VM:\n" <> T.pack err
            <> "\n(the run simulation needs nixpkgs; use `nix run . -- run <program>` "
            <> "or set NIX_PATH to a nixpkgs)")
    Right (ExitSuccess, out, _) -> do
      let outPath = T.unpack (T.strip (T.pack out))
      TIO.hPutStrLn stderr "lips: booting the VM (quit QEMU with Ctrl-a x)..."
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
  program <- TIO.readFile file
  eng     <- loadLangOrDie file
  expSrc  <- tryRead (file <> ".expect")
  case expSrc of
    Nothing  -> die (T.pack file <> " has no behavioral contract ("
                     <> T.pack file <> ".expect missing); nothing to check")
    Just src -> case readExpect src of
      Left es       -> die ("corrupt .expect:\n" <> T.unlines (map renderParseError es))
      Right expects -> case validate file eng program of
        Left problem       -> die problem
        Right (base, nixMod) -> do
          res <- runExpects expects base nixMod
          case res of
            Right () -> TIO.putStrLn (T.pack file <> ": "
                          <> tshow (length expects) <> " behavioral assertion(s) hold")
            Left fs  -> die ("behavioral contract violated:\n" <> T.unlines fs)

-- | Load and parse a program's @.lang@, or fail loud naming @generate@.
loadLangOrDie :: FilePath -> IO EngineData
loadLangOrDie file = do
  let langFile = file <> ".lang"
  msrc <- tryRead langFile
  case msrc of
    Nothing  -> die (T.pack file <> " has no crystallized language (" <> T.pack langFile
                     <> " missing)\nrun: lips generate " <> T.pack file)
    Just src -> case readLang src of
      Left es  -> die ("corrupt language file:\n" <> T.unlines (map renderParseError es))
      Right eng -> pure eng

tryRead :: FilePath -> IO (Maybe Text)
tryRead p = either (const Nothing) Just <$> (try (TIO.readFile p) :: IO (Either IOException Text))

-- | @generate@: the one AI step. The model mints a whole engine (patterns,
-- rules, demands); the kernel crystallizes the program with it and validates
-- by a full run plus a Nix parse before writing anything.
generate :: Double -> String -> FilePath -> IO ()
generate confidence model file = do
  program <- TIO.readFile file
  reply   <- callPi model systemPrompt program
  let (errs, candidates) = parseEngineCandidates reply
      -- Deduce-or-fail: the program is the only source of truth, so an item the
      -- model cannot confidently derive means the program underspecifies it.
      unsure = [c | c <- candidates, let Confidence x = icConfidence c, x < confidence]
  if not (null errs) || not (null unsure)
    then die (refusalReport file confidence errs unsure)
    else do
      let eng = assemble (map icItem candidates)
      -- Validate the minted engine against the actual program: it must
      -- crystallize with full coverage, realize end to end, and the module
      -- must parse as Nix. Nothing is written unless the whole loop succeeds.
      case validate file eng program of
        Left problem -> die (validationReport file problem)
        Right (base, nixModule) -> do
          nixCheck <- nixParses nixModule
          case nixCheck of
            Left why -> die (validationReport file ("the realized module is not valid Nix:\n" <> why))
            Right () -> do
              -- Behavioral gate: the realized module must satisfy the
              -- contract. On regeneration the COMMITTED contract governs (the
              -- stable spec regeneration may not silently break); on first
              -- generation the minted assertions bootstrap it.
              let minted = expectsOf (map icItem candidates)
              committed <- tryRead (file <> ".expect")
              let contract = maybe (Right minted) readExpect committed
                  src      = maybe "minted" (const "committed") committed
              case contract of
                Left es -> die ("corrupt " <> T.pack file <> ".expect:\n"
                                <> T.unlines (map renderParseError es))
                Right expects -> do
                  gate <- runExpects expects base nixModule
                  case gate of
                    Left fs -> die ("minted engine rejected: behavioral contract (" <> src
                      <> ") violated:\n" <> T.unlines fs
                      <> "\n(regression -> fix; or intended change -> delete "
                      <> T.pack file <> ".expect and regenerate to re-bless)")
                    Right () -> do
                      -- The record is written first-class and every engine line
                      -- is stamped with its content id: line -> event, checkable
                      -- by re-hashing the .generation file.
                      let rec = record (T.pack model) confidence systemPrompt program reply
                      TIO.writeFile (file <> ".lang") (renderLang (FromGeneration (genId rec)) eng)
                      TIO.writeFile (file <> ".decisions") (renderBase base)
                      TIO.writeFile (file <> ".generation") rec
                      -- Bootstrap the contract on first generation only; keep
                      -- the committed spec stable across regenerations.
                      maybe (TIO.writeFile (file <> ".expect") (renderExpect minted))
                            (const (pure ())) committed
                      TIO.putStrLn ("wrote " <> T.pack file <> ".lang ("
                        <> tshow (length (edPatterns eng)) <> " patterns, "
                        <> tshow (length (edRules eng)) <> " rules, "
                        <> tshow (length (edDemands eng)) <> " demands, "
                        <> tshow (length expects) <> " assertions [" <> src <> "]), verified:")
                      TIO.putStr nixModule

-- | Crystallize and fully run the program with a candidate engine; on success
-- return the crystal and the realized module.
validate :: FilePath -> EngineData -> Text -> Either Text (Base, Text)
validate file eng program =
  case crystallize file (edPatterns eng) program of
    Left errs  -> Left (renderCrystErrors errs)
    Right base ->
      case runBase budget (map toRule (edRules eng)) (map toDemand (edDemands eng)) base of
        Left err        -> Left (renderRunError err)
        Right nixModule -> Right (base, nixModule)

-- | Check the realized module parses as Nix (closes the garbage-rhs hole at
-- mint time). A missing @nix-instantiate@ is a loud failure: an unverifiable
-- engine is not written (deduce-or-fail).
nixParses :: Text -> IO (Either Text ())
nixParses nixModule = do
  result <- try (readProcessWithExitCode "nix-instantiate" ["--parse", "-"] (T.unpack nixModule))
  pure $ case result of
    Left e -> Left ("nix-instantiate unavailable: " <> tshow (e :: IOException))
    Right (ExitSuccess, _, _)   -> Right ()
    Right (ExitFailure _, _, e) -> Left (T.pack e)

-- | Call pi in print mode as the model gateway: no tools, no session, a fixed
-- system prompt, the program as the user prompt. pi handles provider auth.
callPi :: String -> Text -> Text -> IO Text
callPi model system userPrompt = do
  (code, out, err) <-
    readProcessWithExitCode "pi"
      -- -nc: the mint must be hermetic. pi otherwise injects ambient AGENTS.md/CLAUDE.md
      -- context files (global + walking up from cwd) - inputs that would steer generation
      -- without entering the .generation record or the genId hash.
      [ "-p", "-nt", "-nc", "--no-session", "--model", model, "--system-prompt", T.unpack system ]
      (T.unpack userPrompt)
  case code of
    ExitSuccess   -> pure (T.pack out)
    ExitFailure c -> do
      hPutStrLn stderr ("pi failed (exit " <> show c <> "):\n" <> err)
      exitFailure

-- | Evaluate the realized module with @nix@ and judge a contract against it.
-- One eval reads every asserted option; the pure comparison lives in
-- 'Lips.Kernel.Expect'. An empty contract passes trivially.
runExpects :: [Expect] -> Base -> Text -> IO (Either [Text] ())
runExpects []      _    _         = pure (Right ())
runExpects expects base nixModule =
  case traverse (expectedValue base) expects of
    Left e    -> pure (Left ["cannot ground assertion in program: " <> e])
    Right pvs -> do
      (tmp, h) <- openTempFile "/tmp" "lips-module.nix"
      TIO.hPutStr h nixModule
      hClose h
      let expr = evalExpr tmp expects
      res <- try (readProcessWithExitCode "nix"
                    ["eval", "--raw", "--impure", "--expr", T.unpack expr] "")
      pure $ case res of
        Left e -> Left ["nix eval unavailable: " <> tshow (e :: IOException)]
        Right (ExitSuccess, out, _) ->
          let evaled = T.splitOn "\n" (T.pack out)
           in if length evaled /= length expects
                then Left ["expect: eval returned " <> tshow (length evaled)
                           <> " values for " <> tshow (length expects) <> " assertions"]
                else case checkValues expects (zip pvs evaled) of
                       [] -> Right ()
                       fs -> Left fs
        Right (ExitFailure _, _, err) -> Left ["nix eval failed:\n" <> T.pack err]

die :: Text -> IO a
die msg = TIO.hPutStrLn stderr msg >> exitFailure

-- | The one channel the user reads is this command's output. When generate
-- cannot write an engine, say what went wrong and what to do now -- no
-- questions, no dialogue (all truth lives in the program). Two causes here:
-- lines lips could not read (a mechanism may be missing) and items the model
-- could not derive from the program (the program underspecifies them).
refusalReport :: FilePath -> Double -> [Text] -> [ItemCandidate] -> Text
refusalReport file threshold errs unsure = T.intercalate "\n" $
  ["generate could not build an engine for " <> T.pack file <> "."]
    ++ section grammar ++ section underspecified
  where
    section ls = if null ls then [] else "" : ls
    grammar
      | null errs = []
      | otherwise =
          [ "lips could not read some lines the model produced:" ]
          ++ [ "  - " <> e | e <- errs ]
          ++ [ "what you can do: re-run generate; if the same line keeps being"
             , "rejected, it is a capability lips is missing -- report those lines"
             , "so the mechanism can be added, then upgrade lips and re-run." ]
    underspecified
      | null unsure = []
      | otherwise =
          [ "the program does not pin down these (model confidence below "
              <> tshow threshold <> "):" ]
          ++ [ "  - " <> icLine c <> "   [confidence " <> conf c <> "]" | c <- unsure ]
          ++ [ "what you can do: state the missing detail explicitly in " <> T.pack file
             , "and re-run generate. If the value is genuinely free to choose,"
             , "re-run with a lower --confidence to accept the model's choice." ]
    conf c = let Confidence x = icConfidence c in tshow x

-- | An engine was built but failed the kernel's own validation (it crystallizes
-- but does not realize, parse, or hold its contract). Not the program's fault.
validationReport :: FilePath -> Text -> Text
validationReport file problem = T.intercalate "\n"
  [ "generate built an engine for " <> T.pack file <> ", but it did not hold up:"
  , ""
  , problem
  , ""
  , "what you can do: this is a problem with the generated engine, not your"
  , "program. Re-run generate to mint a fresh one. If it keeps failing the same"
  , "way, it is a lips bug -- report it with the message above."
  ]

renderCrystErrors :: [CrystError] -> Text
renderCrystErrors errs = "the program escaped its language (run: lips generate):\n"
  <> T.unlines (map r errs)
  where
    r (NoPattern n t)     = "  line " <> tshow n <> ": no pattern matches: " <> t
    r (Overlapping n ids) = "  line " <> tshow n <> ": matched by " <> T.intercalate ", " ids

renderParseError :: ParseError -> Text
renderParseError e = "  line " <> tshow (peLine e) <> ": " <> peMessage e

renderRunError :: RunError -> Text
renderRunError (ParseRejected es) =
  "parse rejected:\n" <> T.unlines (map renderParseError es)
renderRunError (OpenQuestions qs) =
  "open questions (answer by adding lines, no AI needed):\n" <> T.unlines [ "  - " <> q | q <- qs ]
renderRunError (Conflicted cs) =
  "conflict (equal-strength contradiction):\n"
    <> T.unlines
         [ "  subject " <> showSubject (conflictSubject c)
             <> ": " <> showProv (conflictLeft c) <> " vs " <> showProv (conflictRight c)
         | c <- cs ]
renderRunError (RefineFailed e) = "refinement failed: " <> tshow e
renderRunError (Unmapped ds) =
  "unmapped (the program escaped the engine; regenerate to grow a mapping):\n"
    <> T.unlines
         [ "  " <> showSubject (dSubject d) <> " [" <> tshow (dKind d) <> "] from " <> showProv d
         | d <- ds ]

showSubject :: Subject -> Text
showSubject (Subject segs) = T.intercalate "." segs

showProv :: Decision -> Text
showProv d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived ids (RuleId r)     -> "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r
  FromGeneration gid         -> "gen:" <> gid

tshow :: Show a => a -> Text
tshow = T.pack . show

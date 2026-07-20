{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI (crystallization plan).
--
--   * @lips generate [model] \<program\>@ is the one AI step: the model mints a
--     /language/ (patterns) for the loose program; the kernel crystallizes the
--     program with it and validates by a full run; only then are the language
--     (@\<program\>.lang@), the crystal witness (@\<program\>.decisions@), and
--     the generation record written.
--   * @lips run \<program\>@ takes the loose program directly. It crystallizes
--     it with @\<program\>.lang@ and realizes it to a NixOS module,
--     deterministically, with no AI. If the language is missing, or the program
--     escaped it, run fails loud and names @generate@ as the remedy.
module Main (main) where

import           Control.Exception  (IOException, try)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs, getProgName)
import           System.Exit        (ExitCode (..), exitFailure)
import           System.IO          (hClose, hPutStrLn, openTempFile, stderr)
import           System.Process     (readProcessWithExitCode)
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
    ["run", file]        -> runLoose file
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
  hPutStrLn stderr ("       " <> name <> " run <program-file>")
  hPutStrLn stderr ("       " <> name <> " check <program-file>")

-- | @run@: crystallize the loose program with its language, then realize.
runLoose :: FilePath -> IO ()
runLoose file = do
  program <- TIO.readFile file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left problem      -> die problem
    Right (_, nixMod) -> TIO.putStr nixMod

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
  mapM_ (\e -> TIO.hPutStrLn stderr ("warning: " <> e)) errs
  -- Deduce-or-fail: refuse an engine the model is unsure of.
  let unsure = [c | c <- candidates, let Confidence x = icConfidence c, x < confidence]
  case unsure of
    (_ : _) -> do
      -- Make the refusal diagnosable: echo each hedged item verbatim with its
      -- confidence against the threshold, so the operator sees WHICH items the
      -- model was unsure of, not merely how many.
      mapM_
        (\c -> let Confidence x = icConfidence c
               in TIO.hPutStrLn stderr
                    ("unsure (confidence " <> tshow x <> " < threshold "
                     <> tshow confidence <> "): " <> icLine c))
        unsure
      die ("model is unsure of " <> tshow (length unsure) <> " item(s); refusing to write (deduce-or-fail)")
    [] -> do
      let eng = assemble (map icItem candidates)
      -- Validate the minted engine against the actual program: it must
      -- crystallize with full coverage, realize end to end, and the module
      -- must parse as Nix. Nothing is written unless the whole loop succeeds.
      case validate file eng program of
        Left problem -> die ("minted engine rejected:\n" <> problem)
        Right (base, nixModule) -> do
          nixCheck <- nixParses nixModule
          case nixCheck of
            Left why -> die ("minted engine rejected: realized module is not valid Nix:\n" <> why)
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

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
import           System.IO          (hPutStrLn, stderr)
import           System.Process     (readProcessWithExitCode)

import           Lips.Engine.Data       (toDemand, toRule)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Minting  (ItemCandidate (..), assemble, parseEngineCandidates, systemPrompt)
import           Lips.Generate.Record   (genId, record)
import           Lips.Kernel.Base       (Conflict (..), Base)
import           Lips.Kernel.Decision
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Run
import           Lips.Lang.Crystallize  (CrystError (..), crystallize)
import           Lips.Lang.Lang         (EngineData (..), readLang, renderLang)

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

-- | Default generation model, routed through pi. Overridable with a second arg.
defaultModel :: String
defaultModel = "anthropic/claude-opus-4-8"

-- | A minted language is admitted only if every pattern is at least this
-- certain; otherwise generate fails loud (deduce-or-fail), writing nothing.
confidenceThreshold :: Double
confidenceThreshold = 0.7

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["run", file]             -> runLoose file
    ["generate", file]        -> generate defaultModel file
    ["generate", model, file] -> generate model file
    _                         -> usage >> exitFailure

usage :: IO ()
usage = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " generate [model] <program-file>")
  hPutStrLn stderr ("       " <> name <> " run <program-file>")

-- | @run@: crystallize the loose program with its language, then realize.
runLoose :: FilePath -> IO ()
runLoose file = do
  program <- TIO.readFile file
  let langFile = file <> ".lang"
  langSrc <- try (TIO.readFile langFile) :: IO (Either IOException Text)
  case langSrc of
    Left _ -> die $
      T.pack file <> " has no crystallized language (" <> T.pack langFile <> " missing)\n"
        <> "run: lips generate " <> T.pack file
    Right src -> case readLang src of
      Left es   -> die ("corrupt language file:\n" <> T.unlines (map renderParseError es))
      Right eng -> case crystallize file (edPatterns eng) program of
        Left errs  -> die (renderCrystErrors errs)
        Right base ->
          case runBase budget (map toRule (edRules eng)) (map toDemand (edDemands eng)) base of
            Right nixModule -> TIO.putStr nixModule
            Left err        -> die (renderRunError err)

-- | @generate@: the one AI step. The model mints a whole engine (patterns,
-- rules, demands); the kernel crystallizes the program with it and validates
-- by a full run plus a Nix parse before writing anything.
generate :: String -> FilePath -> IO ()
generate model file = do
  program <- TIO.readFile file
  reply   <- callPi model systemPrompt program
  let (errs, candidates) = parseEngineCandidates reply
  mapM_ (\e -> TIO.hPutStrLn stderr ("warning: " <> e)) errs
  -- Deduce-or-fail: refuse an engine the model is unsure of.
  let unsure = [c | c <- candidates, let Confidence x = icConfidence c, x < confidenceThreshold]
  case unsure of
    (_ : _) -> die ("model is unsure of " <> tshow (length unsure) <> " item(s); refusing to write (deduce-or-fail)")
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
              -- The record is written first-class and every engine line is
              -- stamped with its content id: line -> event, checkable by
              -- re-hashing the .generation file.
              let rec = record (T.pack model) systemPrompt program reply
              TIO.writeFile (file <> ".lang") (renderLang (FromGeneration (genId rec)) eng)
              TIO.writeFile (file <> ".decisions") (renderBase base)
              TIO.writeFile (file <> ".generation") rec
              TIO.putStrLn ("wrote " <> T.pack file <> ".lang ("
                <> tshow (length (edPatterns eng)) <> " patterns, "
                <> tshow (length (edRules eng)) <> " rules, "
                <> tshow (length (edDemands eng)) <> " demands), verified to a module:")
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
      [ "-p", "-nt", "--no-session", "--model", model, "--system-prompt", T.unpack system ]
      (T.unpack userPrompt)
  case code of
    ExitSuccess   -> pure (T.pack out)
    ExitFailure c -> do
      hPutStrLn stderr ("pi failed (exit " <> show c <> "):\n" <> err)
      exitFailure

die :: Text -> IO ()
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

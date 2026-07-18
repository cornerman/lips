{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI. @lips generate <program>@ is the one AI step: it reads a
-- loose program and writes a canonical decision base, routing the model call
-- through @pi@. @lips run <program>@ then realizes canonical form to a NixOS
-- module, deterministically, with no AI (spec v2, section 5).
module Main (main) where

import           Data.Text    (Text)
import qualified Data.Text    as T
import qualified Data.Text.IO as TIO
import           System.Environment (getArgs, getProgName)
import           System.Exit  (ExitCode (..), exitFailure)
import           System.IO    (hPutStrLn, stderr)
import           System.Process (readProcessWithExitCode)

import qualified Lips.Engine.Feed  as Feed
import           Lips.Generate.Harness
import           Lips.Generate.Reading (parseCandidates, systemPrompt)
import           Lips.Kernel.Base     (Conflict (..), fromList)
import           Lips.Kernel.Decision
import           Lips.Kernel.Reader   (ParseError (..), renderBase)
import           Lips.Kernel.Run

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

-- | Default generation model, routed through pi. Overridable with a second arg.
defaultModel :: String
defaultModel = "anthropic/claude-opus-4-8"

-- | Admit only decisions the model is at least this sure of; the rest become
-- open questions carrying the model's candidate answer (deduce-or-fail).
confidenceThreshold :: Confidence
confidenceThreshold = Confidence 0.7

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["run", file] -> do
      src <- TIO.readFile file
      case run budget Feed.rules Feed.demands src of
        Right nixModule -> TIO.putStr nixModule
        Left err        -> TIO.hPutStr stderr (renderError err) >> exitFailure
    ["generate", file]        -> generate defaultModel file
    ["generate", model, file] -> generate model file
    _ -> usage >> exitFailure

usage :: IO ()
usage = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " generate [model] <program-file>")
  hPutStrLn stderr ("       " <> name <> " run <program-file>")

-- | The one AI step. Read the loose program, ask the model (via pi) to express
-- it in canonical form, admit only what it is sure of, and write the decision
-- base beside the program as @<file>.decisions@. Everything the model is unsure
-- of is printed as an open question and never written. A generation record is
-- written to @<file>.generation@ so the event is auditable (spec section 5).
generate :: String -> FilePath -> IO ()
generate model file = do
  program <- TIO.readFile file
  reply   <- callPi model systemPrompt program
  let (errs, candidates) = parseCandidates reply
      (admitted, questions) = admit confidenceThreshold candidates
      outFile = file <> ".decisions"
  mapM_ (\e -> TIO.hPutStrLn stderr ("warning: " <> e)) errs
  TIO.writeFile outFile (renderBase (fromList admitted))
  TIO.writeFile (file <> ".generation") (generationRecord model program reply)
  TIO.putStrLn ("wrote " <> T.pack outFile <> " (" <> tshow (length admitted) <> " decisions)")
  case questions of
    [] -> pure ()
    qs -> do
      TIO.hPutStrLn stderr "open questions (confirm or correct, then add lines to the program):"
      mapM_ (\q -> TIO.hPutStrLn stderr ("  - " <> renderOpenQuestion q)) qs

-- | Call pi in print mode as the model gateway: no tools, no session, a fixed
-- system prompt, the program as the user prompt. pi handles provider auth.
callPi :: String -> Text -> Text -> IO Text
callPi model system userPrompt = do
  (code, out, err) <-
    readProcessWithExitCode "pi"
      [ "-p", "-nt", "--no-session", "--model", model, "--system-prompt", T.unpack system ]
      (T.unpack userPrompt)
  case code of
    ExitSuccess -> pure (T.pack out)
    ExitFailure c -> do
      hPutStrLn stderr ("pi failed (exit " <> show c <> "):\n" <> err)
      exitFailure

-- | The auditable record of a generation event (spec section 5): what model
-- ran, what it was asked, and exactly what it returned.
generationRecord :: String -> Text -> Text -> Text
generationRecord model program reply = T.unlines
  [ "model: " <> T.pack model
  , "--- system prompt ---", systemPrompt
  , "--- program (input) ---", program
  , "--- raw reply ---", reply
  ]

-- | Render a run failure as the reviewable surface the spec describes: which
-- outcome, and the exact provenances or questions involved.
renderError :: RunError -> Text
renderError (ParseRejected es) =
  "parse rejected (a line no pattern reads):\n"
    <> T.unlines [ "  line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
renderError (OpenQuestions qs) =
  "open questions (answer by adding lines, no AI needed):\n"
    <> T.unlines [ "  - " <> q | q <- qs ]
renderError (Conflicted cs) =
  "conflict (equal-strength contradiction):\n"
    <> T.unlines
         [ "  subject " <> showSubject (conflictSubject c)
             <> ": " <> showProv (conflictLeft c) <> " vs " <> showProv (conflictRight c)
         | c <- cs
         ]
renderError (RefineFailed e) = "refinement failed: " <> tshow e
renderError (Unmapped ds) =
  "unmapped (the program escaped the engine; regenerate to grow a mapping):\n"
    <> T.unlines
         [ "  " <> showSubject (dSubject d) <> " [" <> tshow (dKind d) <> "] from " <> showProv d
         | d <- ds
         ]

showSubject :: Subject -> Text
showSubject (Subject segs) = T.intercalate "." segs

showProv :: Decision -> Text
showProv d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived ids (RuleId r)     -> "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r

tshow :: Show a => a -> Text
tshow = T.pack . show

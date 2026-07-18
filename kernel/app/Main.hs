{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI. @lips run <program>@ realizes a canonical-form program to a
-- NixOS module, deterministically, against the built-in example engine. This
-- is the reference @run@; there is no AI here (spec v2, section 5).
module Main (main) where

import           Data.Text    (Text)
import qualified Data.Text    as T
import qualified Data.Text.IO as TIO
import           System.Environment (getArgs, getProgName)
import           System.Exit  (exitFailure)
import           System.IO    (hPutStrLn, stderr)

import qualified Lips.Engine.Feed as Feed
import           Lips.Kernel.Base     (Conflict (..))
import           Lips.Kernel.Decision
import           Lips.Kernel.Reader   (ParseError (..))
import           Lips.Kernel.Run

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["run", file] -> do
      src <- TIO.readFile file
      case run budget Feed.rules Feed.demands src of
        Right nixModule -> TIO.putStr nixModule
        Left err        -> TIO.hPutStr stderr (renderError err) >> exitFailure
    _ -> usage >> exitFailure

usage :: IO ()
usage = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " run <program-file>")

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

showSubject :: Subject -> Text
showSubject (Subject segs) = T.intercalate "." segs

showProv :: Decision -> Text
showProv d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived ids (RuleId r)     -> "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r

tshow :: Show a => a -> Text
tshow = T.pack . show

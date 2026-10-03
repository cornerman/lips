{-# LANGUAGE OverloadedStrings #-}

-- | Corpus scan for TODO "Plurality is not a gate": which holes bind exactly
-- ONE distinct value across every committed program of their language, and
-- where each such hole lands. A "hole never contrasted" diagnostic would fire
-- on exactly these, so the list is that diagnostic's false-positive set (every
-- entry whose singleton is honest).
--
-- A throwaway measuring tool, not kernel code: it reuses the kernel's own
-- matcher ('matchTemplate') and landing join ('wordLandings'), so it reads the
-- engines exactly as crystallize and the reach gate do.
--
-- Usage: scan <program.lips>...  (language folder = dirname/<language>)
module Main (main) where

import           Control.Monad      (forM, forM_)
import           Data.List          (nub, sort)
import qualified Data.Map.Strict    as Map
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (doesFileExist, listDirectory)
import           System.Environment (getArgs)
import           System.FilePath    (takeDirectory, takeFileName, (</>))

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Landing (Landing (..), Part (..), wordLandings)
import Lips.Kernel.Engine.Value   (AssertionUse (..), assertionUses, valueCaptures)
import Lips.Kernel.Lang.Pattern
import Lips.Kernel.Lang.Store     (EngineData (..), readLang)
import Lips.Kernel.Reader         (commentOrBlank)

-- | @board.lips@ is language @board@; @api.web.lips@ is language @web@.
languageOf :: FilePath -> String
languageOf f = case T.splitOn "." (T.pack (takeFileName f)) of
  parts | length parts >= 2 -> T.unpack (parts !! (length parts - 2))
  _                         -> error ("not a program: " <> f)

main :: IO ()
main = do
  progs <- getArgs
  let byLang = Map.fromListWith (flip (++)) [ ((takeDirectory p, languageOf p), [p]) | p <- progs ]
  forM_ (Map.toList byLang) $ \((dir, lang), ps) -> do
    let ldir = dir </> lang
    grammar <- TIO.readFile (ldir </> lang <> ".grammar")
    entries <- listDirectory ldir
    worlds <- fmap concat . forM (sort entries) $ \w -> do
      ok <- doesFileExist (ldir </> w </> lang <> ".rules")
      if ok then do
        rules <- TIO.readFile (ldir </> w </> lang <> ".rules")
        case readLang (grammar <> "\n" <> rules) of
          Right eng -> pure [(w, eng)]
          Left errs -> error (show errs)
      else pure []
    pats <- case worlds of
      ((_, eng) : _) -> pure (edPatterns eng)
      []             -> fail ("no world under " <> ldir)
    srcs <- mapM TIO.readFile ps
    let binds = concatMap (bindingsOf pats) srcs
        values = Map.fromListWith (flip (++)) [ ((pid, h), [v]) | (pid, h, v) <- binds ]
    putStrLn ("== " <> ldir <> "  (" <> show (length ps) <> " program(s))")
    forM_ (Map.toList values) $ \((pid, h), vs) -> do
      let distinct = nub vs
          p = case [q | q <- pats, pId q == pid] of
                (q : _) -> q
                []      -> error ("unknown pattern " <> T.unpack pid)
          tag = if length distinct == 1 then "SINGLETON" else "contrasted" :: Text
      TIO.putStrLn ("  " <> tag <> "  " <> pid <> " <" <> h <> ">  "
                    <> T.pack (show (length vs)) <> " binding(s), "
                    <> T.pack (show (length distinct)) <> " distinct: "
                    <> T.intercalate " | " (take 3 distinct))
      forM_ worlds $ \(w, eng) -> do
        let sites = nub [ T.intercalate "." (emPath e)
                        | l <- wordLandings pats (edRules eng) p h
                        , r <- lgRules l, e <- mrEmits r, carries l r e ]
        TIO.putStrLn ("      " <> T.pack w <> " -> " <> T.intercalate ", " sites)

-- | Does this one emit of a matching rule carry the word? The reach gate's
-- own two tests ('Lips.Kernel.Engine.Reach'), asked per emit rather than per
-- rule, so the printed sites are where the word lands and not every option the
-- rule happens to set beside it.
carries :: Landing -> MapRule -> Emit -> Bool
carries l r e = readsWord (lgPart l) (assertionUses (emRhs e)) || namesCapture
  where
    namesCapture = or [ c `elem` concatMap nameTokens (emPath e) || c `elem` valueCaptures (emRhs e)
                      | (i, s) <- zip [0 :: Int ..] (mrSubject r), i `elem` lgSegments l
                      , Just c <- [captureName s] ]
    readsWord Nothing _ = False
    readsWord (Just Whole) uses = not (null uses)
    readsWord (Just (Part n)) uses = any entire uses
      where entire (UsePart m) = m == n
            entire _           = True

-- | Every (pattern, hole, value) one program binds: line patterns by their own
-- template, item patterns by the items their parent's list hole cut. A list
-- hole binds its items one value each, so a one-line list of two items is
-- contrasted, which is what it is.
bindingsOf :: [Pattern] -> Text -> [(Text, Text, Text)]
bindingsOf pats src = concat
  [ own p m ++ items p m
  | l <- T.lines src
  , let t = T.strip l
  , not (commentOrBlank t)
  , [(p, m)] <- [[ (p, m) | p <- pats, pItemHole p == Nothing
                          , Just m <- [matchTemplate (pTemplate p) (tokenizeLine t)] ]]
  ]
  where
    own p m = [ (pId p, h, v) | (h, v) <- Map.toList (mBinds m) ]
    items p m = concat
      [ (pId p, h, itemText toks)
          : concat [ [ (pId c, ch, cv) | (ch, cv) <- Map.toList (mBinds cm) ]
                   | c <- pats, pItemHole c == Just h, pId p `elem` pParents c
                   , Just cm <- [matchTemplate (pTemplate c) toks] ]
      | (h, its) <- Map.toList (mItems m), toks <- its ]

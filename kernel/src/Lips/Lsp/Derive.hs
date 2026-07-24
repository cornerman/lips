{-# LANGUAGE OverloadedStrings #-}

-- | The pure core of the language server: turn a language (its patterns) and a
-- program's 'Diagnosis' into the two things an editor shows -- completion items
-- and diagnostics -- as plain typed values, with no JSON and no IO. The server
-- shell ('Lips.Lsp.Server') maps these to the wire protocol. Keeping this pure
-- is functional-core/imperative-shell: the interesting logic is testable
-- without a socket, and it reuses the very same 'diagnose' that @lips check@
-- prints, so the editor never disagrees with the CLI.
module Lips.Lsp.Derive
  ( CItem (..)
  , completionItems
  , Diag (..)
  , diagsOf
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Lang.Crystallize (LineOutcome (..))
import Lips.Kernel.Lang.Diagnose    (Diagnosis (..))
import Lips.Kernel.Lang.Pattern     (Pattern (..), TplTok (..))

-- | One completion candidate: the human-readable sentence form of a pattern,
-- and a snippet with numbered tab-stops for its holes.
data CItem = CItem
  { ciLabel   :: Text -- ^ e.g. @back up \<src\> to \<dst\> daily@
  , ciSnippet :: Text -- ^ e.g. @back up ${1:src} to ${2:dst} daily@
  }
  deriving (Eq, Show)

-- | Every pattern in the language becomes one candidate. A lips language is a
-- fixed, small set of sentence forms, so offering them all (the client filters
-- by prefix) is the whole completion story.
completionItems :: [Pattern] -> [CItem]
completionItems = map item
  where
    item p =
      let (label, snippet, _) = foldl step ([], [], 1 :: Int) (pTemplate p)
       in CItem (T.unwords (reverse label)) (T.unwords (reverse snippet))
    step (ls, ss, n) (TLit t)   = (t : ls, t : ss, n)
    step (ls, ss, n) (THole h)  =
      ("<" <> h <> ">" : ls, "${" <> T.pack (show n) <> ":" <> h <> "}" : ss, n + 1)
    step (ls, ss, n) (TTail h)  =
      ("<" <> h <> ".tail>" : ls, "${" <> T.pack (show n) <> ":" <> h <> "}" : ss, n + 1)

-- | One diagnostic: a whole-line span (0-based line, character range) with a
-- severity (LSP: 1 error, 2 warning) and a message.
data Diag = Diag
  { dgLine     :: Int
  , dgStart    :: Int
  , dgEnd      :: Int
  , dgSeverity :: Int
  , dgMessage  :: Text
  }
  deriving (Eq, Show)

-- | Diagnostics for a program: a line the language cannot read, or reads
-- ambiguously, is an error on that line; a demand left open is a
-- whole-program warning (surfaced on the first line, since it belongs to no
-- single line). A cleanly matched line yields nothing.
diagsOf :: Diagnosis -> [Diag]
diagsOf d = concatMap lineDiag (diagLines d) ++ map openDiag (diagOpen d)
  where
    lineDiag (Matched {})       = []
    lineDiag (Unmatched n t)    =
      [Diag (n - 1) 0 (T.length t) 1
        "No pattern reads this line. Run: lips generate <program>"]
    lineDiag (Ambiguous n _ ids) =
      [Diag (n - 1) 0 0 1
        ("This line matches several patterns (" <> T.intercalate ", " ids
          <> "); the language is not orthogonal here.")]
    openDiag q = Diag 0 0 0 2 ("Open question: " <> q)

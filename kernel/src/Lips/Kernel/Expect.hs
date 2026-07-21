{-# LANGUAGE OverloadedStrings #-}

-- | The behavioral contract of a program: the @.expect@ file (ledger section
-- 13, "behavioral gate on regeneration"). Each assertion binds a NixOS option
-- path to a value the program specifies, /relationally/ -- it names the source
-- decision, not a frozen constant, so a legitimate value edit moves both sides
-- together (edit-tolerance) while an engine drift that relocates or drops the
-- option trips the gate (the intended re-bless decision surface).
--
-- Grammar, one assertion per line:
--
-- > <id> expect <option.path> from <subject>[#<n>]
--
-- @option.path@ is a NixOS option (dotted). @subject@ is a decision the
-- program's patterns produce; @#n@ optionally selects the nth whitespace token
-- of that decision's assertion (1-based), mirroring the @\<value.N\>@ hole in
-- rules. The check is /containment/: the program value must appear in the
-- evaluated option value. That is exactly "the specified value is realized
-- here", and it is uniform across strings, lists, and integers once the option
-- is rendered to JSON.
--
-- This module is pure. The IO that evaluates the realized module with @nix@
-- lives in the CLI; 'evalExpr' builds the expression it runs and 'checkValues'
-- judges the results.
module Lips.Kernel.Expect
  ( Expect (..)
  , renderExpect
  , readExpect
  , parseExpectBody
  , expectedValue
  , evalExpr
  , checkValues
  ) where

import           Data.List  (sortOn)
import           Data.Text  (Text)
import qualified Data.Text  as T
import           Text.Read  (readMaybe)

import Lips.Kernel.Base     (Base, toList)
import Lips.Kernel.Decision
import Lips.Kernel.Reader   (ParseError (..))

-- | One behavioral assertion: option 'exPath' carries the value drawn from
-- decision 'exFrom' (optionally its 'exToken'th token).
data Expect = Expect
  { exId    :: Text
  , exPath  :: [Text]
  , exFrom  :: Subject
  , exToken :: Maybe Int
  }
  deriving (Eq, Show)

-- | Render a contract to canonical @.expect@ text, ordered by id.
renderExpect :: [Expect] -> Text
renderExpect = T.unlines . map renderOne . sortOn exId
  where
    renderOne e =
      exId e <> " expect " <> dotted (exPath e) <> " from " <> renderFrom e

renderFrom :: Expect -> Text
renderFrom e = dotted segs <> maybe "" (\n -> "#" <> tshow n) (exToken e)
  where Subject segs = exFrom e

dotted :: [Text] -> Text
dotted = T.intercalate "."

-- | Read a contract, collecting per-line errors. Blank lines and @#@ comments
-- are ignored.
readExpect :: Text -> Either [ParseError] [Expect]
readExpect src =
  let real = [ (n, l)
             | (n, raw) <- zip [1 ..] (T.lines src)
             , let l = T.strip raw
             , not (T.null l), not ("#" `T.isPrefixOf` l) ]
      results = [ (n, parseOne l) | (n, l) <- real ]
      errs = [ ParseError n e | (n, Left e) <- results ]
   in if null errs then Right [ x | (_, Right x) <- results ] else Left errs
  where
    parseOne l = case firstToken l of
      Nothing          -> Left "empty expect line"
      Just (eid, rest) -> parseExpectBody eid rest

-- | Parse an assertion body (everything after the id), for reuse by @generate@
-- when the model mints assertions.
parseExpectBody :: Text -> Text -> Either Text Expect
parseExpectBody eid body =
  case T.words body of
    ["expect", pathTok, "from", fromTok] -> do
      (subjTok, tok) <- parseFrom fromTok
      Right Expect
        { exId    = eid
        , exPath  = T.splitOn "." pathTok
        , exFrom  = Subject (T.splitOn "." subjTok)
        , exToken = tok
        }
    _ -> Left ("expect " <> eid <> ": want `expect <path> from <subject>[#n]`, got: " <> body)
  where
    parseFrom t = case T.breakOn "#" t of
      (s, "") -> Right (s, Nothing)
      (s, r)  -> case readMaybe (T.unpack (T.drop 1 r)) of
        Just n | n >= 1 -> Right (s, Just n)
        _              -> Left ("expect " <> eid <> ": bad token index in " <> t)

-- | The value the program specifies for an assertion: the source decision's
-- assertion, or its nth token. A missing subject or out-of-range token fails
-- loud -- an assertion that cannot be grounded in the program is a defect.
expectedValue :: Base -> Expect -> Either Text Text
expectedValue base e =
  case [ a | d <- toList base, dSubject d == exFrom e, let Assertion a = dAssertion d ] of
    []      -> Left ("expect " <> exId e <> ": no decision with subject " <> renderFrom e)
    (a : _) -> case exToken e of
      Nothing -> Right a
      Just n  -> case drop (n - 1) (T.words a) of
        (t : _) -> Right t
        []      -> Left ("expect " <> exId e <> ": token #" <> tshow n
                          <> " out of range in " <> tshow a)

-- | Build the @nix eval --raw@ expression that reads every asserted option out
-- of the realized module. Stubs for @config@/@lib@/@pkgs@ suffice because the
-- asserted options carry program values (never @${pkgs...}@ machinery), so the
-- forced paths do not touch the stubs. A missing path yields @null@, which
-- fails containment cleanly instead of crashing eval.
evalExpr :: FilePath -> [Expect] -> Text
evalExpr modPath expects = T.concat
  [ "let m = import ", T.pack modPath, "; "
  , "cfg = m { config = {}; lib = {}; pkgs = {}; }; "
  , "get = path: builtins.foldl' "
  , "(acc: k: if builtins.isAttrs acc && builtins.hasAttr k acc then acc.${k} else null) "
  , "cfg path; "
  , "in builtins.concatStringsSep \"\\n\" (map (p: builtins.toJSON (get p)) [ "
  , T.intercalate " " (map nixPath expects)
  , " ])"
  ]
  where
    nixPath e = "[ " <> T.unwords (map quote (exPath e)) <> " ]"
    quote s   = "\"" <> s <> "\""

-- | Judge the eval results against the program values. Containment: each
-- program value must appear in its option's evaluated JSON. Returns one message
-- per failed assertion (empty = all pass).
checkValues :: [Expect] -> [(Text, Text)] -> [Text]
checkValues es pairs =
  [ fail' e pv ev | (e, (pv, ev)) <- zip es pairs, not (pv `T.isInfixOf` ev) ]
  where
    -- Plain, author-facing: name the NixOS option and the mismatch, no internal
    -- assertion id. The caller (CLI) indents and frames it.
    fail' e pv ev =
      dotted (exPath e) <> ": should contain " <> pv <> ", but is " <> ev

firstToken :: Text -> Maybe (Text, Text)
firstToken t = case T.words t of
  []      -> Nothing
  (w : _) -> Just (w, T.drop (T.length w) (T.stripStart t))

tshow :: Show a => a -> Text
tshow = T.pack . show

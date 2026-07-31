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
  , bindSelfExpect
  , expandExpects
  , parseExpectBody
  , expectedValue
  , evalExpr
  , checkValues
  , isGroundExpect
  , checkArtifactValues
  ) where

import           Data.List  (sortOn)
import           Data.Maybe (isJust)
import           Data.Text  (Text)
import qualified Data.Text  as T
import           Text.Read  (readMaybe)

import Lips.Kernel.Base     (Base, toList)
import Lips.Kernel.Capture  (captureName, fillCaptures, fillName, matchSubject, selfName)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Data (renderAttrPath, splitAttrPath)
import Lips.Kernel.Reader   (ParseError (..))
import Lips.Kernel.Surface  (valueText, valueTokens)

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
dotted = renderAttrPath

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
      path  <- splitAttrPath pathTok
      subj  <- splitAttrPath subjTok
      Right Expect
        { exId    = eid
        , exPath  = path
        , exFrom  = Subject subj
        , exToken = tok
        }
    _ -> Left ("expect " <> eid <> ": want `expect <path> from <subject>[#n]`, got: " <> body)
  where
    parseFrom t = case T.breakOn "#" t of
      (s, "") -> Right (s, Nothing)
      (s, r)  -> case readMaybe (T.unpack (T.drop 1 r)) of
        Just n | n >= 1 -> Right (s, Just n)
        _              -> Left ("expect " <> eid <> ": bad token index in " <> t)

-- | Bind the reserved @\<self\>@ option-path segment to the instance name, so
-- a shared language's contract is checked against the realized module, whose
-- @\<self\>@ is already bound the same way (plan 2026-07-22). Only the option
-- path is affected; the source subject ('exFrom') is program-side and never
-- carries @\<self\>@.
-- Filled by OCCURRENCE ('fillName', the call the rule side makes), not by
-- whole-segment comparison: a name is literal text with @\<token\>@
-- occurrences, so @\<self\>-core@ is as legal a segment as @\<self\>@. The
-- literal comparison this replaces left such a segment unbound, and the
-- assertion then read @null@ from the module instead of failing.
bindSelfExpect :: Text -> Expect -> Expect
bindSelfExpect name e = e { exPath = map (fillName resolve) (exPath e) }
  where
    resolve nm = if nm == selfName then Just name else Nothing

-- | Expand a value-keyed contract against a program's base. An expect whose
-- @from@ subject carries a capture (@route.<path>.status@) is a FAMILY: it
-- expands to one concrete expect per matching decision, its @from@ set to that
-- decision's subject and every @<name>@ in its option path filled with the
-- captured key -- the expect analogue of a rule fanning out. A plain expect
-- passes through unchanged (its subject is checked later by 'expectedValue'),
-- so older single-route contracts behave identically. A family that matches no
-- decision is a defect, named loud.
expandExpects :: Base -> [Expect] -> Either Text [Expect]
expandExpects base = fmap concat . traverse (expandOne base)

expandOne :: Base -> Expect -> Either Text [Expect]
expandOne base e
  | not (any (isJust . captureName) patSegs) = Right [e]
  | otherwise = case matches of
      [] -> Left ("expect " <> exId e <> ": no decision matches family " <> renderFrom e)
      xs -> sequence xs
  where
    Subject patSegs = exFrom e
    matches =
      [ (\p -> e { exFrom = dSubject d, exPath = p }) <$> fillPath caps
      | d <- toList base
      , Just caps <- [matchSubject patSegs (subjOf d)] ]
    subjOf d = case dSubject d of Subject xs -> xs
    fillPath caps =
      either (\r -> Left ("expect " <> exId e <> ": option path " <> r)) Right
             (traverse (fillCaptures caps) (exPath e))

-- | The value the program specifies for an assertion: the source decision's
-- assertion, or its nth token. A missing subject or out-of-range token fails
-- loud -- an assertion that cannot be grounded in the program is a defect.
expectedValue :: Base -> Expect -> Either Text Text
expectedValue base e =
  case [ a | d <- toList base, dSubject d == exFrom e, let Assertion a = dAssertion d ] of
    []      -> Left ("expect " <> exId e <> ": no decision with subject " <> renderFrom e)
    (a : _) -> case exToken e of
      Nothing -> Right (valueText a)
      -- The value's PARTS (a several-part value quotes them), so a contract on
      -- part #2 reads the same text the rule's <value.2> does.
      Just n  -> case drop (n - 1) (valueTokens a) of
        (t : _) -> Right t
        []      -> Left ("expect " <> exId e <> ": token #" <> tshow n
                          <> " out of range in " <> tshow a)

-- | Build the @nix eval --raw@ expression that reads every asserted option out
-- of the realized module. Stubs for @config@/@lib@/@pkgs@ suffice because a
-- checkable option carries a program value, never @${pkgs...}@\/@${artifact...}@
-- machinery; that precondition is enforced structurally by
-- 'Lips.Generate.Minting.uncheckableExpects' (a package\/artifact-referencing
-- option would force the empty @pkgs@ stub and abort the eval, which
-- @tryEval@ cannot catch for a missing attribute). A missing path yields
-- @null@, which fails containment cleanly instead of crashing eval.
evalExpr :: FilePath -> [Expect] -> Text
evalExpr modPath expects = T.concat
  [ "let m = import ", T.pack modPath, "; "
  , "cfg = m { config = {}; lib = {}; pkgs = {}; }; "
  , "get = path: builtins.foldl' "
  , "(acc: k: if builtins.isAttrs acc && builtins.hasAttr k acc then acc.${k} else null) "
  , "cfg path; "
  -- A path-typed option value (environmentFile = /etc/foo) must NOT go through
  -- toJSON: that coerces the path into the store and fails for an absolute
  -- system file that does not exist at eval time. toString yields its literal
  -- text without importing, and containment over strings is unchanged.
  , "render = v: if builtins.typeOf v == \"path\" then builtins.toString v else builtins.toJSON v; "
  , "in builtins.concatStringsSep \"\\n\" (map (p: render (get p)) [ "
  , T.intercalate " " (map nixPath expects)
  , " ])"
  ]
  where
    nixPath e = "[ " <> T.unwords (map quote (exPath e)) <> " ]"
    quote s   = "\"" <> s <> "\""

-- | Does this assertion name a slot the KERNEL realizes -- an artifact arg
-- (@artifact.\<name\>.args...@) or a claim section (@claim.\<id\>.stdout@) --
-- rather than a module option? Neither is part of the module a caller can
-- evaluate: an artifact arg is consumed by a builder, so it never reappears as
-- an attribute of the resulting derivation, and a claim section is consumed by
-- an experiment. Both ARE literals in the realized output, so the kernel judges
-- them itself -- no nix, no eval.
--
-- This is what an artifact-only or claim-bearing engine (a program whose whole
-- result is a built command, or whose behaviour is stated as an observable) can
-- pin; without it such a program had NOTHING to assert and its contract was
-- empty, which passes trivially. Pinning the claim slots is also what makes a
-- re-mint that DROPS an author's example trip the existing gate, with no new
-- gate to build.
isGroundExpect :: Expect -> Bool
isGroundExpect e = case exPath e of
  ("artifact" : _) -> True
  ("claim" : _)    -> True
  _                -> False

-- | Judge artifact assertions against the GROUND base -- the decisions realize
-- turned into @artifact.nix@ -- with the same containment rule 'checkValues'
-- uses on evaluated options. The assertion's option path IS the ground
-- subject, so an assertion whose slot no rule fills fails loud instead of
-- reading a silent @null@.
checkArtifactValues :: Base -> [(Expect, Text)] -> [Text]
checkArtifactValues ground pairs = concatMap judge pairs
  where
    judge (e, pv) = case [ a | d <- toList ground, dSubject d == Subject (exPath e)
                             , let Assertion a = dAssertion d ] of
      []      -> [ dotted (exPath e) <> ": nothing realizes this slot, so the "
                    <> "program value " <> pv <> " lands nowhere" ]
      (a : _) | pv `T.isInfixOf` a -> []
              | otherwise -> [ dotted (exPath e) <> ": should contain " <> pv
                                <> ", but is " <> a ]

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

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
  , Compat (..)
  , compatSlug
  , parseCompat
  , rebless
  , smallestCompat
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

import           Data.Char  (isSpace)
import           Data.List  (sortOn)
import           Data.Maybe (isJust)
import           Data.Text  (Text)
import qualified Data.Text  as T
import           Text.Read  (readMaybe)

import Lips.Kernel.Base     (Base, toList)
import Lips.Kernel.Capture  (captureName, fillCaptures, fillName, matchSubject, selfName)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Data (Emit (..), MapRule (..), renderAttrPath, splitAttrPath)
import Lips.Kernel.Engine.Value (parseValue, sourceText)
import Lips.Kernel.Reader   (ParseError (..))
import qualified Lips.Kernel.Surface as Q
import Lips.Kernel.Surface  (fillValueHoles, quoteText, valueText, valueTokens)

-- | One behavioral assertion: option 'exPath' carries the value drawn from
-- decision 'exFrom' (optionally its 'exToken'th token).
--
-- 'exTemplate' is the arm for an option whose text a rule ASSEMBLES from the
-- fact's parts (@\"*-*-* \<value.1\>:\<value.2\>:00\"@ for a systemd calendar).
-- Then the contract states the WHOLE text and is compared for equality, because
-- the parts joined by a space appear in no such notation and containment of one
-- part is a weaker claim than the words make. Without a template the comparison
-- is containment, exactly as it always was.
--
-- Such a contract restates what the rule assembles, and that is not vacuous: a
-- committed contract gates the NEXT mint, so an engine that later spells the
-- same fact differently (drops the seconds, reorders the fields) is refused.
data Expect = Expect
  { exId       :: Text
  , exPath     :: [Text]
  , exFrom     :: Subject
  , exToken    :: Maybe Int
  , exTemplate :: Maybe Text
  }
  deriving (Eq, Show)

-- | How much of the committed contract a re-mint may move. Two independent
-- permissions, so four points rather than the one word (@--renew@) this
-- replaces: may a committed assertion VANISH (drop), and may a freshly minted
-- one JOIN (add)?
--
-- Named from the caller's promise about the CONTRACT, not from the file
-- operation: @backwards@ keeps every check a committed contract makes (it can
-- only grow), @forwards@ keeps every check the new engine makes (it can only
-- shrink), @full@ keeps both promises and is therefore the default, @none@
-- keeps neither and rewrites.
data Compat = Full | Backwards | Forwards | None
  deriving (Eq, Show, Bounded, Enum)

-- | The word a caller writes for a mode, and reads back in a refusal.
compatSlug :: Compat -> Text
compatSlug Full      = "full"
compatSlug Backwards = "backwards"
compatSlug Forwards  = "forwards"
compatSlug None      = "none"

-- | Read a mode word. Derived from the type ('Bounded'\/'Enum'), so a mode
-- added later cannot be missing here.
parseCompat :: Text -> Maybe Compat
parseCompat w = lookup w [(compatSlug c, c) | c <- [minBound .. maxBound]]

-- | Two assertions are THE SAME when they pin the same option to the same
-- source: the @a1@\/@a2@ ids are minted fresh every run and carry no identity.
sameExpect :: Expect -> Expect -> Bool
sameExpect x y = exPath x == exPath y && exFrom x == exFrom y && exToken x == exToken y

-- | The contract a re-mint is judged by and writes back, from the committed set
-- C and the freshly minted set M, under one mode. @Left@ names the committed
-- assertions the mode does not permit to leave.
--
-- With nothing committed yet every mode bootstraps from M: there is no promise
-- to keep, and a first mint must write the contract it just earned.
--
-- The guard that keeps @forwards@ from letting the model choose which checks to
-- skip: an assertion may leave only when NO rule in the new engine assigns its
-- option path -- the engine genuinely stopped filling it. A path still filled
-- but no longer asserted refuses, so the one thing a re-mint cannot do is
-- quietly stop looking. Structural, the same shape as
-- 'Lips.Generate.Minting.uncheckableExpects' (invariant 2).
rebless :: Compat -> [MapRule] -> [Expect] -> [Expect] -> Either [Expect] [Expect]
rebless mode rules committed minted
  | null committed = Right minted
  | otherwise = case mode of
      Full      -> Right committed
      None      -> Right minted
      Backwards -> Right (committed ++ joining)
      Forwards  -> case filter (stillFilled rules) leaving of
        []  -> Right kept
        bad -> Left bad
  where
    kept    = [c | c <- committed, any (sameExpect c) minted]
    leaving = [c | c <- committed, not (any (sameExpect c) minted)]
    -- An extra keeps its own shape but never a committed id, so the file's
    -- diff shows one added line rather than a renumbering of every line.
    joining = [ m { exId = "a" <> tshow n }
              | (n, m) <- zip [length committed + 1 ..]
                              [m | m <- minted, not (any (sameExpect m) committed)] ]

-- | Does the engine still assign this assertion's option path? Then dropping
-- the assertion would leave a filled option unchecked.
stillFilled :: [MapRule] -> Expect -> Bool
stillFilled rules e = exPath e `elem` [emPath em | r <- rules, em <- mrEmits r]

-- | The smallest mode that would admit these committed assertions changing:
-- @forwards@ while every one of them names an option the engine stopped
-- filling, else @none@. Named in a refusal so the human reaches for the
-- narrowest word rather than the biggest hammer.
smallestCompat :: [MapRule] -> [Expect] -> Compat
smallestCompat rules es
  | any (stillFilled rules) es = None
  | otherwise                  = Forwards

-- | Render a contract to canonical @.expect@ text, ordered by id.
renderExpect :: [Expect] -> Text
renderExpect = T.unlines . map renderOne . sortOn exId
  where
    renderOne e =
      exId e <> " expect " <> dotted (exPath e) <> " from " <> renderFrom e
        <> maybe "" (\t -> " is " <> quoteText t) (exTemplate e)

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
  case peelTokens 4 body of
    Just (["expect", pathTok, "from", fromTok], tail') -> do
      (subjTok, tok) <- parseFrom fromTok
      path  <- splitAttrPath pathTok
      subj  <- splitAttrPath subjTok
      -- The keyword is `is`, not `equals`: this line reads as a sentence about an
      -- option's TEXT, while claim.<id>.equals compares a program's OUTPUT, and
      -- the two must not sound like the same operation.
      tpl <- case T.stripPrefix "is " tail' of
        Just quoted             -> Just <$> parseQuotedText eid (T.stripStart quoted)
        Nothing | T.null tail'  -> Right Nothing
                | otherwise     -> Left (badForm eid body)
      -- A template states the WHOLE text, so naming a part as well says two
      -- different things about one option.
      case (tok, tpl) of
        (Just _, Just _) -> Left ("expect " <> eid <> ": a template states the whole "
                                   <> "text, so it cannot also name part #N")
        _                -> Right ()
      Right Expect
        { exId       = eid
        , exPath     = path
        , exFrom     = Subject subj
        , exToken    = tok
        , exTemplate = tpl
        }
    _ -> Left (badForm eid body)
  where
    parseFrom t = case T.breakOn "#" t of
      (s, "") -> Right (s, Nothing)
      (s, r)  -> case readMaybe (T.unpack (T.drop 1 r)) of
        Just n | n >= 1 -> Right (s, Just n)
        _              -> Left ("expect " <> eid <> ": bad token index in " <> t)

-- | The first @n@ whitespace-separated tokens and the REST as text. The tail
-- carries a quoted template that may hold spaces, so it cannot be read back out
-- of 'T.words' -- and it must not be found by searching the body for the @is@
-- keyword either, since an option path may end in those letters
-- (@services.redis@).
peelTokens :: Int -> Text -> Maybe ([Text], Text)
peelTokens n t
  | n <= 0    = Just ([], T.stripStart t)
  | T.null w  = Nothing
  | otherwise = (\(ws, r) -> (w : ws, r)) <$> peelTokens (n - 1) rest
  where (w, rest) = T.break isSpace (T.stripStart t)

badForm :: Text -> Text -> Text
badForm eid body = "expect " <> eid
  <> ": want `expect <path> from <subject>[#n]` or"
  <> " `expect <path> from <subject> is \"<template>\"`, got: " <> body

-- | The quoted template, unescaped.
parseQuotedText :: Text -> Text -> Either Text Text
parseQuotedText eid t = case Q.parseQuoted t of
  Right (inner, rest) | T.null (T.strip rest) -> Right inner
  Right (_, rest) -> Left ("expect " <> eid <> ": trailing text after the template: " <> rest)
  Left why        -> Left ("expect " <> eid <> ": " <> why)

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
    -- A template is resolved HERE, so the pair 'runExpects' compares is already
    -- the whole text the option must carry.
    (a : _) | Just tpl <- exTemplate e ->
                either (\why -> Left ("expect " <> exId e <> ": " <> why)) Right
                       (fillValueHoles tpl a)
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
checkArtifactValues :: Base -> [(Expect, Text)] -> [(Expect, Text)]
checkArtifactValues ground pairs = concatMap judge pairs
  where
    judge (e, pv) = map ((,) e) $ case [ a | d <- toList ground, dSubject d == Subject (exPath e)
                             , let Assertion a = dAssertion d ] of
      []      -> [ dotted (exPath e) <> ": nothing realizes this slot, so the "
                    <> "program value " <> pv <> " lands nowhere" ]
      (a : _) | holds e pv (slotText a) -> []
              | isJust (exTemplate e) ->
                  [ dotted (exPath e) <> ": should be " <> pv <> ", but is " <> slotText a ]
              | otherwise -> [ dotted (exPath e) <> ": should contain " <> pv
                                <> ", but is " <> slotText a <> jointHint pv (slotText a) ]
    -- A slot holds a VALUE and the program states a value, so they are compared
    -- as VALUES, never as transport encodings. The canonical form escapes a
    -- quote (and a newline), while the program side is already decoded by
    -- 'expectedValue' through 'valueText' -- so without this a stated value
    -- carrying a quote could never be pinned: a JSON witness {"a":"1"} is stored
    -- as "{\"a\":\"1\"}" and does not contain itself as text. Found by a mint
    -- whose author example was exactly that.
    --
    -- A value with no text form (a list, an attrset, a bare reference) keeps its
    -- canonical text: that IS its only reading, and containment over it is what
    -- an artifact arg holding a derivation reference already relies on.
    slotText a = case parseValue a of
      Right v | Just t <- sourceText v -> t
      _                                -> a
    -- A SEVERAL-PART value pinned as a whole can be unsatisfiable by
    -- construction: the parts reach the slot, but the rule joins them its own way
    -- (a newline between two stdin lines), while the program side renders them
    -- space-joined -- so the whole text appears nowhere. That is not a value that
    -- failed to arrive, it is a contract that cannot hold, and the two read
    -- identically without saying so. Name the remedy instead: one assertion per
    -- part.
    jointHint pv slot
      | length parts > 1, inOrder parts slot =
          " (every part reaches this slot, but the rule joins them its own way, so"
            <> " this whole-value assertion can never hold: pin one part per"
            <> " assertion, `from <subject>#1`, `#2`, ...)"
      | otherwise = ""
      where parts = valueTokens pv
    -- Each part present, in the order stated.
    inOrder [] _ = True
    inOrder (p : ps) t = case T.breakOn p t of
      (_, rest) | T.null rest -> False
                | otherwise   -> inOrder ps (T.drop (T.length p) rest)

-- | Judge the eval results against the program values. Containment: each
-- program value must appear in its option's evaluated JSON. Returns the failed
-- assertion WITH its message (empty = all pass): the caller shows the message
-- and asks the assertion which re-bless mode would admit the change
-- ('smallestCompat').
checkValues :: [Expect] -> [(Text, Text)] -> [(Expect, Text)]
checkValues es pairs =
  [ (e, fail' e pv ev) | (e, (pv, ev)) <- zip es pairs, not (holds e pv (optionText ev)) ]
  where
    -- Plain, author-facing: name the NixOS option and the mismatch, no internal
    -- assertion id. The caller (CLI) indents and frames it.
    fail' e pv ev
      | isJust (exTemplate e) =
          dotted (exPath e) <> ": should be " <> pv <> ", but is " <> optionText ev
      | otherwise =
          dotted (exPath e) <> ": should contain " <> pv <> ", but is " <> ev

-- | The option's TEXT, out of the JSON @nix eval@ printed. A template states the
-- text an option carries, not the transport that carried it here, so the string
-- is unquoted before the comparison. Anything that is not a JSON string (a list,
-- a number, @null@) has no other reading and stays verbatim, where it then fails
-- the equality loud.
optionText :: Text -> Text
optionText ev = case Q.parseQuoted ev of
  Right (inner, rest) | T.null rest -> inner
  _                                 -> ev

-- | Does an actual text satisfy this assertion? A template states the WHOLE
-- text, so it is compared for EQUALITY; a plain expect keeps containment, which
-- is what "the specified value is realized here" means when the option's text is
-- the world's own notation. One definition, because a contract line must mean
-- the same on the evaluated-option path and on the ground-slot one.
holds :: Expect -> Text -> Text -> Bool
holds e expected actual
  | isJust (exTemplate e) = expected == actual
  | otherwise             = expected `T.isInfixOf` actual

firstToken :: Text -> Maybe (Text, Text)
firstToken t = case T.words t of
  []      -> Nothing
  (w : _) -> Just (w, T.drop (T.length w) (T.stripStart t))

tshow :: Show a => a -> Text
tshow = T.pack . show

{-# LANGUAGE OverloadedStrings #-}

-- | Claims: the one gate that observes a running thing instead of reading the
-- module text.
--
-- Every other gate lips has judges the MAP (an option assignment, a staged
-- path, a stamp). So a program whose behaviour lives in baked source could
-- state a sentence, have it minted into code, and then have that code drift
-- from the sentence with every gate green -- the module text says nothing about
-- what minted code DOES. A claim closes that by naming an observable the AUTHOR
-- stated: a command, what it is fed, what it must print, how it must exit.
--
-- Nothing here is domain knowledge. @claim.\<id\>@ is a reserved emit head
-- beside @artifact.\<name\>@ -- kernel vocabulary, not a target option -- with a
-- CLOSED section set, so an engine fills it and cannot extend it. The rhs stays
-- in the closed value grammar, so a claim cannot compute.
--
-- The PLACE is derived, never declared: a command naming only artifacts runs as
-- a plain derivation in the nix sandbox (fast, no KVM, no network), anything
-- else runs inside a booted machine. So a CLI program never pays for a boot, and
-- no new syntax carries the distinction.
module Lips.Kernel.Claim
  ( Claim (..)
  , ClaimPlace (..)
  , ClauseClaim (..)
  , Expected (..)
  , claimsFromDecisions
  , clauseClaimsFromDecisions
  , renderClauseClaim
  , claimPlace
  , comparisonPy
  , claimRooted
  ) where

import qualified Data.Map.Strict as Map
import           Data.List       (nub)
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision
import Lips.Kernel.Sexp         (SExp, parseSexp, renderSexp)
import Lips.Kernel.Engine.Value (Piece (..), Value (..), parseValue, sourceText,
                                 valueArtifactNames)

-- | Where a claim is observed. Derived from the command, not declared.
data ClaimPlace
  = -- | A plain derivation in the nix sandbox: the command names only the
    --   program's own artifacts, so nothing needs to boot.
    PlaceDerivation
  | -- | A booted machine (@nixosTest@): the command reaches beyond those
    --   artifacts, so the module itself must run.
    PlaceMachine
  deriving (Eq, Show)

-- | One observable the author stated.
data Claim = Claim
  { clId     :: Text
  , clRun    :: Value        -- ^ the command; may hold @${artifact.\<name\>}@
  , clStdin  :: Maybe Text
  , clStdout :: Maybe Text
  , clExit   :: Int
  , clPlace  :: ClaimPlace
  }
  deriving (Eq, Show)

-- | One observable over the program's own CLAUSES, judged by evaluating them
-- with the in-memory adapters linked: no derivation to build, no machine to
-- boot, no binary to compile. A claim states what to call and what it must
-- equal, and optionally the input lines the program is fed first.
--
-- A separate type from 'Claim', not a variant of it, because the two are
-- observed by different machinery entirely: a 'Claim' watches a process through
-- its stdin and stdout, and this watches an expression. Keeping them apart makes
-- a claim that is half command and half expression unrepresentable.
data ClauseClaim = ClauseClaim
  { ccId       :: Text
  , ccCall     :: SExp     -- ^ the expression to evaluate
  , ccExpected :: Expected -- ^ what it must equal
  , ccFeed     :: [Text]   -- ^ input lines served to @read-a-line@ first
  , ccArgs     :: [Text]   -- ^ the command line the program sees, served to @arguments@
  }
  deriving (Eq, Show)

-- | What a clause claim's expression must equal, stated one of two ways. A sum,
-- so a claim holding both expectations (or neither) cannot be constructed.
data Expected
  = -- | @equals@: one expression, written whole by one decision.
    Equals SExp
  | -- | @equals-lines@: a list of lines, the dual of @feed@. It is a Nix list, so
    --   several decisions contribute one element each and Append assembles them
    --   in source order; an example's printed lines then follow its item count
    --   the way its fed lines do, which one expression cannot.
    EqualsLines [Text]
  deriving (Eq, Show)

-- | The sections a clause claim is made of, closed for the same reason the
-- command sections are: a mint's typo must fail loud, never be dropped in
-- silence and pass by observing less than the author stated.
clauseSections :: [Text]
clauseSections = ["call", "equals", "equals-lines", "feed", "args"]

-- | Gather the clause claims out of a ground base. Deterministic (ordered by
-- id). An id carrying both a command section and a clause section is a loud
-- failure: one claim observes one thing.
clauseClaimsFromDecisions :: [(Subject, Decision)] -> Either Text [ClauseClaim]
clauseClaimsFromDecisions winners = traverse one (Map.toList grouped)
  where
    grouped = Map.fromListWith (flip (++))
      [ (cid, [(sec, d)])
      | (Subject ["claim", cid, sec], d) <- winners, sec `elem` clauseSections ]
    commandIds = [ cid | (Subject ["claim", cid, sec], _) <- winners, sec `elem` sections ]

    one (cid, parts)
      | cid `elem` commandIds =
          Left (pre <> "observes both a command and an expression; a claim observes one thing")
      | otherwise = do
          call <- need "call" parts
          want <- expected
          feed <- textList "feed" parts
          args <- textList "args" parts
          Right (ClauseClaim cid call want feed args)
      where
        pre = "claim " <> cid <> ": "
        expected = case (lookup "equals" parts, lookup "equals-lines" parts) of
          (Just _, Just _)  ->
            Left (pre <> "states both equals and equals-lines; a claim judges by one expectation")
          (Nothing, Nothing) ->
            Left (pre <> "no equals or equals-lines, so there is nothing to judge")
          (Just _, Nothing)  -> Equals <$> need "equals" parts
          (Nothing, Just _)  -> EqualsLines <$> textList "equals-lines" parts
        need sec ps = case lookup sec ps of
          Nothing -> Left (pre <> "no " <> sec <> ", so there is nothing to judge")
          Just d  -> case parseSexp (assertionOf d) of
            Right x -> Right x
            Left e  -> Left (pre <> sec <> " is not an expression: " <> e)
        -- A list of plain strings, or a single one written bare. Feed, args and
        -- equals-lines are BYTES the program sees or prints, so only a value
        -- with a text form can be one.
        textList sec ps = case lookup sec ps of
          Nothing -> Right []
          Just d  -> case parseValue (assertionOf d) of
            Right (VList vs) -> traverse (one' sec) vs
            Right v          -> (: []) <$> one' sec v
            Left e           -> Left (pre <> sec <> " is not a value: " <> e)
        one' sec v = case sourceText v of
          Just t  -> Right t
          Nothing -> Left (pre <> sec <> " must be plain text, got " <> renderish v)

    assertionOf d = case dAssertion d of Assertion a -> a

-- | The forms lips emits for one clause claim: the input lines, then the
-- judgment. Everything about HOW a verdict is printed lives in the runtime's own
-- harness, so these forms are the whole interface.
--
-- The WORDS come from the runtime ('Lips.Kernel.Clause.Catalogue.Harness'), never
-- from here: that a claim is judged by id, expression and expected value is a
-- fact about claims, while @claim@ and @feed-lines@ are facts about one runtime's
-- harness -- the same split that keeps the defining word out of the gate.
renderClauseClaim :: (Text, Text, Text, Text) -> ClauseClaim -> [Text]
renderClauseClaim (feedArgs, feedLines, judge, mkList) cc =
  [ call feedArgs [list (ccArgs cc)] | not (null (ccArgs cc)) ]
    <> [ call feedLines [list (ccFeed cc)] | not (null (ccFeed cc)) ]
    <> [ call judge [ schemeStr (ccId cc), renderSexp (ccCall cc), want ] ]
  where
    -- Expected lines are built by the runtime's own list word, exactly as a
    -- feed is, so the judge compares a list against the list it observed.
    want = case ccExpected cc of
      Equals x       -> renderSexp x
      EqualsLines ls -> list ls
    call w as = "(" <> T.unwords (w : as) <> ")"
    list xs = "(" <> T.unwords (mkList : map schemeStr xs) <> ")"
    -- A Scheme string literal: only a quote and a backslash need escaping, since
    -- Scheme has no interpolation.
    schemeStr t = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" t) <> "\""

-- | Is this path the claim vocabulary? Twin of
-- 'Lips.Kernel.OptionType.reservedRoot': neither head becomes a target option.
claimRooted :: [Text] -> Bool
claimRooted ("claim" : _) = True
claimRooted _             = False

-- | The closed section set. A section outside it is an engine defect: a mint's
-- typo (@stdOut@) would otherwise be dropped in silence, and the claim would
-- pass by observing less than the author stated.
sections :: [Text]
sections = ["run", "stdin", "stdout", "exit"]

-- | Gather the claims out of a ground base's @claim.\<id\>.\<section\>@
-- decisions. Deterministic (ordered by id). Every defect is a loud 'Left' in
-- plain words -- a malformed subject, an unknown section, a claim with no
-- command, a non-text stdin\/stdout, a non-integer exit -- because a claim lips
-- cannot read is a claim lips cannot run, and an unrun claim must never pass as
-- a held one.
claimsFromDecisions :: [(Subject, Decision)] -> Either Text [Claim]
claimsFromDecisions winners
  | (bad : _) <- malformed =
      Left ("claim " <> T.intercalate "." bad <> ": a claim is claim.<id>.<section>,"
             <> " with section one of " <> T.intercalate ", " sections)
  | (bad : _) <- unknownSections =
      Left ("claim section " <> bad <> " is not one of "
             <> T.intercalate ", " (sections <> clauseSections))
  | otherwise = traverse one (Map.toList grouped)
  where
    malformed = [ segs | (Subject segs@("claim" : _), _) <- winners, length segs /= 3 ]
    -- A section outside BOTH closed sets is an engine defect: a mint's typo
    -- (stdOut) would otherwise be dropped in silence. A section in the clause
    -- set belongs to 'clauseClaimsFromDecisions' and is skipped here, so the two
    -- kinds of observable coexist without either seeing the other's sections as
    -- garbage.
    unknownSections = nub [ sec | (Subject ["claim", _, sec], _) <- winners
                                , sec `notElem` sections, sec `notElem` clauseSections ]
    grouped = Map.fromListWith (flip (++))
      [ (cid, [(sec, d)])
      | (Subject ["claim", cid, sec], d) <- winners, sec `elem` sections ]

    one (cid, parts) = do
      vals <- traverse (\(s, d) -> (,) s <$> valueOf s d) parts
      runV <- case lookup "run" vals of
        Just v  -> Right v
        Nothing -> Left (pre <> "no run, so there is nothing to observe")
      inT  <- traverse (text "stdin") (lookup "stdin" vals)
      outT <- traverse (text "stdout") (lookup "stdout" vals)
      code <- case lookup "exit" vals of
        Nothing       -> Right 0
        Just (VInt n) -> Right (fromIntegral n)
        Just v        -> Left (pre <> "exit must be an integer, got " <> renderish v)
      Right Claim { clId = cid, clRun = runV, clStdin = inT, clStdout = outT
                  , clExit = code, clPlace = claimPlace runV }
      where
        pre = "claim " <> cid <> ": "
        valueOf sec d = case dAssertion d of
          Assertion a -> case parseValue a of
            Right v -> Right v
            Left e  -> Left (pre <> sec <> " is not a value: " <> e)
        -- stdin and stdout are BYTES a program reads and writes, so only a value
        -- with a text form can be one: a reference resolves to a store path only
        -- nix knows, and a list or attrset has no textual form at all.
        text sec v = case sourceText v of
          Just t  -> Right t
          Nothing -> Left (pre <> sec <> " must be plain text, got " <> renderish v)

-- | A value in a complaint: its constructor shape is what a mint needs to see,
-- and the kernel has no renderer that is safe for every case here.
renderish :: Value -> Text
renderish = T.pack . show

-- | The place, derived: only artifact references (and literal text) keep a claim
-- in the sandbox. A package reference or a bare command needs the booted system,
-- since what it observes is the running module, not a build.
claimPlace :: Value -> ClaimPlace
claimPlace v@(VStr ps)
  | all litOrArt ps && not (null (valueArtifactNames v)) = PlaceDerivation
  where
    litOrArt (PLit _) = True
    litOrArt (PArt _) = True
    litOrArt _        = False
claimPlace _ = PlaceMachine

-- | The comparison, as python lines over @out@ (the observed stdout, a str) and
-- @code@ (the observed exit status, an int).
--
-- ONE implementation for both places: a @nixosTest@ script is python already, so
-- rendering the comparison once is what keeps a sandbox claim and a machine
-- claim from judging by different rules.
--
-- EXACT, with exactly one trailing newline stripped: a program that prints a
-- line ends it in a newline, while the author states the line. Containment is
-- deliberately absent -- it is what let a minted @\"200\\n404\"@ pass as
-- @\"200n404\"@ unseen.
comparisonPy :: Claim -> [Text]
comparisonPy c =
  [ "expected_exit = " <> T.pack (show (clExit c))
  , "if out.endswith('\\n'): out = out[:-1]"
  , "if code != expected_exit:"
  , "    raise SystemExit('claim " <> pyBody (clId c)
      <> ": exit was %d, expected %d' % (code, expected_exit))"
  ] ++ outLines
  where
    outLines = case clStdout c of
      Nothing -> []
      Just s  ->
        [ "expected_out = " <> pyStr s
        , "if out != expected_out:"
        , "    raise SystemExit('claim " <> pyBody (clId c)
            <> ": stdout was %r, expected %r' % (out, expected_out))"
        ]

-- | A python single-quoted literal.
pyStr :: Text -> Text
pyStr t = "'" <> pyBody t <> "'"

-- | The inside of a python single-quoted literal: only @\\@ and @'@ need
-- escaping, and a newline is written as an escape so a rendered line stays one
-- line. Applied to the claim id too, so an id can never end the literal it sits
-- in (the id grammar is identifier text, and this keeps that from being a thing
-- the reader must know to trust the output).
pyBody :: Text -> Text
pyBody = T.concatMap esc
  where
    esc '\\' = "\\\\"
    esc '\'' = "\\'"
    esc '\n' = "\\n"
    esc ch   = T.singleton ch

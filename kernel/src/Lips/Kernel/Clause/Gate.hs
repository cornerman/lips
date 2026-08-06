{-# LANGUAGE OverloadedStrings #-}

-- | The subset gate: a clause reaches the world only through a declared
-- contract, and nothing else can slip in.
--
-- This is the whole safety argument of the logic axis. A general-purpose
-- language can do too much, so lips emits a SUBSET of one and checks the subset
-- mechanically. The prior art is the same shape: Joe-E verifies a
-- capability-safe subset of Java, SES one of JavaScript, SPARK one of Ada. lips
-- keeps somebody else's runtime and libraries and refuses the forms that let a
-- program reach the world unannounced.
--
-- The check is one traversal with a bound-name set. A symbol is grounded when it
-- is a parameter in scope, a declared form, a base procedure, a declared
-- contract, or another clause's name. Everything else is a mint defect, reported
-- by name.
--
-- Two deliberate limits, both making the gate weaker rather than wronger:
--
--   * Quoted data is not walked. @'(system)@ names no procedure; walking it
--     would reject honest clauses.
--   * Binder scoping is lenient: a @let@'s initializers are checked with its own
--     names already in scope, so a use-before-definition passes here. Scheme
--     itself rejects that, and the gate's job is grounding, not scope order.
--
-- The reference implementation this ports is
-- @experiments/logscan-clauses/gate.scm@, which proved the walk against the real
-- corpus before any Haskell existed.
module Lips.Kernel.Clause.Gate
  ( Clause (..)
  , GateFault (..)
  , gate
  , faultText
  , reachedContracts
  ) where

import           Data.List (nub, sort, sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Clause.Vocabulary (Contract (..), Vocabulary (..), Binder (..),
                                      BinderShape (..), contractNames)
import Lips.Kernel.Decision          (SourceLoc (..))
import Lips.Kernel.Sexp              (SExp (..), renderSexp, sexpSymbols)

-- | One minted definition, with the program lines that caused it. Provenance is
-- a field rather than a comment because a clause IS a decision: it already
-- carries provenance, and the emitted file prints it as a comment for the human.
data Clause = Clause
  { clName :: Text
  , clBody :: SExp
  , clFrom :: [SourceLoc]
  }
  deriving (Eq, Show)

data GateFault
  = -- | A clause names something no vocabulary grounds: the clause, the identifier.
    Ungrounded Text Text
  | -- | A clause no program line caused, so nothing in the program answers for it.
    Unprovenanced Text
  | -- | The body is not the one definition the clause claims to be: the clause, why.
    NotADefinition Text Text
  deriving (Eq, Show)

faultText :: GateFault -> Text
faultText (Ungrounded c n) =
  "clause " <> c <> " names " <> n <> ", which no form, procedure or contract\
  \ grounds. Behaviour reaches the world only through a declared contract."
faultText (Unprovenanced c) =
  "clause " <> c <> " names no program line. Every clause must be caused by\
  \ something the author wrote."
faultText (NotADefinition c why) =
  "clause " <> c <> " is not one definition of " <> c <> ": " <> why

-- | Every fault in the clause set, in clause order.
gate :: Vocabulary -> [Clause] -> [GateFault]
gate vocab clauses = concatMap check clauses
  where
    known = vForms vocab <> vProcedures vocab <> contractNames vocab
              <> map clName clauses
    check cl =
      [ Unprovenanced (clName cl) | null (clFrom cl) ]
        <> case definition (vDefiners vocab) (clName cl) (clBody cl) of
             Left why           -> [NotADefinition (clName cl) why]
             Right (bound, body) ->
               [ Ungrounded (clName cl) n | n <- nub (concatMap (free vocab known bound) body) ]

-- | Unpack the one shape a clause may have: @(define (name params...) body...)@
-- or @(define name expr)@, the constant a stated number becomes. Returns the
-- names the head binds and the body expressions.
--
-- The DEFINING WORD comes from the vocabulary, never from here. The kernel knows
-- that a clause is one named definition, which is a fact about clauses; it must
-- not know that Scheme spells it @define@, which is a fact about Scheme.
definition :: [Text] -> Text -> SExp -> Either Text ([Text], [SExp])
definition definers name (SList (SSym d : SList (SSym n : params) : body))
  | d `elem` definers
  , n /= name = Left (wrongName n)
  | d `elem` definers
  , null body = Left "its body is empty"
  | d `elem` definers = (\ps -> (ps, body)) <$> traverse param params
  where
    param (SSym p) = Right p
    param other    = Left ("a parameter must be a name, not " <> renderSexp other)
definition definers name (SList [SSym d, SSym n, value])
  | d `elem` definers
  , n /= name = Left (wrongName n)
  | d `elem` definers = Right ([], [value])
definition definers _ other =
  Left ("it reads " <> T.take 40 (renderSexp other)
         <> ", and a clause is exactly one definition ("
         <> T.intercalate " or " definers <> " ...)")

wrongName :: Text -> Text
wrongName n = "it defines " <> n <> " instead"

-- | Every ungrounded symbol in an expression, given what is in scope.
free :: Vocabulary -> [Text] -> [Text] -> SExp -> [Text]
free vocab known bound = go bound
  where
    go scope (SSym s)
      | s `elem` scope || s `elem` known = []
      | otherwise                        = [s]
    go scope (SList xs@(SSym h : _))
      | Just b <- lookupBinder h = binder scope b xs
      | otherwise                = concatMap (go scope) xs
    go scope (SList xs) = concatMap (go scope) xs
    go _ (SQuote _)     = []      -- data, not a call
    go _ _              = []

    lookupBinder h = lookup h [ (bForm b, bShape b) | b <- vBinders vocab ]

    -- A binder's own names enter scope for everything after its head, which
    -- includes its initializers (lenient by design, see the module header).
    binder scope shape xs =
      let names = binderNames shape xs
          scope' = names <> scope
          rest = drop (1 + shapeIndex shape) xs
          inits = binderInits shape xs
       in concatMap (go scope') (inits <> rest)

    shapeIndex (ParamsAt i)   = i
    shapeIndex (BindingsAt i) = i

    binderNames shape xs = case atIndex (shapeIndex shape) xs of
      Just (SList items) -> case shape of
        ParamsAt _   -> [ p | SSym p <- items ]
        BindingsAt _ -> [ p | SList (SSym p : _) <- items ]
      -- (lambda args body): a single name taking the whole argument list.
      Just (SSym p) -> [p]
      _             -> []

    binderInits shape xs = case (shape, atIndex (shapeIndex shape) xs) of
      (BindingsAt _, Just (SList items)) -> concat [ es | SList (SSym _ : es) <- items ]
      _                                  -> []

atIndex :: Int -> [a] -> Maybe a
atIndex i xs = case drop i xs of
  (x : _) -> Just x
  []      -> Nothing

-- | The contracts the clause set actually reaches, by name. This is the
-- program's reach into the world, and the covering computation
-- ('Lips.Kernel.Clause.Catalogue') takes it as its input. Sorted by name rather
-- than left in the vocabulary's own order, so reordering the shipped asset
-- cannot change what a caller (or a test) sees.
reachedContracts :: Vocabulary -> [Clause] -> [Contract]
reachedContracts vocab clauses =
  sortOn cName [ c | c <- vContracts vocab, cName c `elem` mentioned ]
  where
    -- The one symbol walk, shared with the gate: a private copy would drift, and
    -- the two must agree by construction, since what the gate grounds and what a
    -- runtime must provide are the same set.
    mentioned = sort (nub (concatMap (sexpSymbols . clBody) clauses))

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
  , gateClaim
  , faultText
  , paramCount
  , reachedContracts
  ) where

import           Data.List (nub, sort, sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Clause.Vocabulary (Contract (..), Vocabulary (..), Binder (..),
                                      BinderShape (..), claimContracts, clauseContracts)
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
  | -- | A call passes the wrong number of arguments: the clause, the callee, how
    --   many it takes, how many were passed. Declared arity was data nobody read
    --   until an entry mismatch shipped two binaries that died on first run with
    --   every gate green; the same hole one level down accepted @(emit)@ with no
    --   argument.
    WrongArity Text Text Int Int
  | -- | A call whose callee is a clause defining a CONSTANT: the clause, the
    --   callee. A constant is not a procedure of no arguments, and applying one
    --   is a runtime death the gate can see coming.
    NotCallable Text Text
  deriving (Eq, Show)

-- | The fault in plain words. @kind@ is the word for the thing at fault (a
-- clause, a claim), passed in because the WALK is shared: reporting a claim as a
-- clause sends a reader looking in the wrong place.
faultText :: Text -> GateFault -> Text
faultText kind (Ungrounded c n) =
  kind <> " " <> c <> " names " <> n <> ", which no form, procedure or contract\
  \ grounds. Behaviour reaches the world only through a declared contract."
faultText kind (Unprovenanced c) =
  kind <> " " <> c <> " names no program line. Every clause must be caused by\
  \ something the author wrote."
faultText kind (NotADefinition c why) =
  kind <> " " <> c <> " is not one definition of " <> c <> ": " <> why
faultText kind (WrongArity c callee takes given) =
  kind <> " " <> c <> " calls " <> callee <> " with " <> count given
    <> ", and " <> callee <> " takes " <> count takes <> "."
  where count 1 = "1 argument"
        count n = T.pack (show n) <> " arguments"
faultText kind (NotCallable c callee) =
  kind <> " " <> c <> " calls " <> callee <> ", which is a constant, not a\
  \ procedure. A constant holds a value; calling it stops the program."

-- | What grounds a name, and what each callable takes. Built one way for a
-- clause and another for a claim, so the WALK is shared and only the ground set
-- differs: a claim judged by looser rules than a clause could compute its own
-- answer and vouch for nothing.
data Grounds = Grounds
  { gKnown     :: [Text]          -- ^ names needing no further justification
  , gArities   :: [(Text, Int)]   -- ^ what each callable takes, where it is known
  , gConstants :: [Text]          -- ^ names holding a value, so not callable
  }

-- | What grounds a name in a clause: forms, base procedures, the contracts a real
-- run provides, and the other clauses.
clauseGrounds :: Vocabulary -> [Clause] -> Grounds
clauseGrounds vocab = groundsWith vocab (clauseContracts vocab)

-- | What grounds a name in a claim: everything a clause may name, plus the
-- observations the claim-time adapters add.
claimGrounds :: Vocabulary -> [Clause] -> Grounds
claimGrounds vocab = groundsWith vocab (claimContracts vocab)

groundsWith :: Vocabulary -> [Text] -> [Clause] -> Grounds
groundsWith vocab contracts clauses = Grounds
  { gKnown = vForms vocab <> vProcedures vocab <> contracts <> map clName clauses
    -- What every callable name takes. Contracts declare it; a clause's is the
    -- parameter count of its own definition. A base procedure declares none,
    -- because many are variadic (@+@, @list@, @append@), so those calls stay
    -- unchecked and the runtime is their judge.
  , gArities = [ (cName c, cArity c) | c <- vContracts vocab ]
                 <> [ (clName cl, n) | cl <- clauses, Just n <- [paramCount cl] ]
    -- The clauses holding a value rather than a procedure. Calling one is the
    -- same defect the entry check catches one level out, seen from inside.
  , gConstants = [ clName cl | cl <- clauses, paramCount cl == Nothing ]
  }

-- | Every fault in one expression: an ungrounded name, a call of the wrong width,
-- a call of something that holds a value. @who@ names the clause or claim the
-- fault belongs to, and @bound@ is what its own head already put in scope.
--
-- ONE walk for a clause and a claim. They were not, and that is how a claim came
-- to reach @(system "...")@ while a clause could not.
faultsIn :: Vocabulary -> Grounds -> Text -> [Text] -> SExp -> [GateFault]
faultsIn vocab gs who bound e =
  [ Ungrounded who n | n <- nub (free vocab (gKnown gs) bound e) ]
    <> [ WrongArity who callee takes given
       | (callee, given) <- made
       , Just takes <- [lookup callee (gArities gs)]
       , takes /= given ]
    <> [ NotCallable who callee
       | (callee, _) <- made, callee `elem` gConstants gs ]
  where made = calls vocab bound e

-- | Every fault in the clause set, in clause order.
gate :: Vocabulary -> [Clause] -> [GateFault]
gate vocab clauses = concatMap check clauses
  where
    gs = clauseGrounds vocab clauses
    check cl =
      [ Unprovenanced (clName cl) | null (clFrom cl) ]
        <> case definition (vDefiners vocab) (clName cl) (clBody cl) of
             Left why           -> [NotADefinition (clName cl) why]
             Right (bound, body) ->
               concatMap (faultsIn vocab gs (clName cl) bound) body

-- | Every fault in the expressions of one claim, named by the claim's id.
--
-- A claim runs with the core and the adapters loaded, so an ungrounded name there
-- reaches the world exactly as one in a clause would -- and a claim free to name
-- anything can compute the answer it is supposed to be checking. Proven before
-- this existed: a claim calling @(system "echo ...")@ spawned a shell and
-- reported @ok@.
gateClaim :: Vocabulary -> [Clause] -> Text -> [SExp] -> [GateFault]
gateClaim vocab clauses cid =
  concatMap (faultsIn vocab (claimGrounds vocab clauses) cid [])

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
    -- A dot is dotted-pair notation, not a name: (define (f . rest) ...) is a
    -- VARIADIC definition, and counting its two tokens as two parameters made the
    -- gate's arity disagree with the runtime's -- refusing an honest three-argument
    -- call and accepting a two-argument one that means something else.
    param (SSym ".") = Left "a variadic parameter list (. rest) is not in the clause\
                            \ grammar; give each parameter a name"
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

-- | How many parameters a clause's definition takes, or 'Nothing' when it
-- defines a CONSTANT (which is what a stated number becomes).
--
-- The distinction is the whole reason this returns a 'Maybe': a constant is not
-- a procedure of no arguments. Reading it as one is how a core defining @main@ as
-- a number satisfied a runtime entry calling @(main)@ and produced a binary that
-- died on first run with every gate green. One function answers the question, so
-- no second copy can answer it differently.
paramCount :: Clause -> Maybe Int
paramCount cl = case clBody cl of
  SList (_ : SList (_ : params) : _) -> Just (length params)
  _                                  -> Nothing

-- | Every call in an expression, as (callee, argument count). A name in the head
-- position only: a bare mention elsewhere is not a call, and a name a binder put
-- in scope is a parameter whose arity nothing here can know.
calls :: Vocabulary -> [Text] -> SExp -> [(Text, Int)]
calls vocab bound = go bound
  where
    go scope (SList xs@(SSym h : args))
      | Just b <- lookupBinder vocab h =
          let bp = binderParts b xs
           in concatMap (go (bpNames bp <> scope)) (bpInits bp <> bpBody bp)
      | h `elem` scope = concatMap (go scope) args
      | otherwise = (h, length args) : concatMap (go scope) args
    go scope (SList xs) = concatMap (go scope) xs
    go _ (SQuote _)     = []
    go _ _              = []

-- | Every ungrounded symbol in an expression, given what is in scope.
free :: Vocabulary -> [Text] -> [Text] -> SExp -> [Text]
free vocab known bound = go bound
  where
    go scope (SSym s)
      | s `elem` scope || s `elem` known = []
      | otherwise                        = [s]
    go scope (SList xs@(SSym h : _))
      | Just b <- lookupBinder vocab h =
          let bp = binderParts b xs
           -- A binder's own names enter scope for everything after its head,
           -- which includes its initializers (lenient by design, see the header).
           in concatMap (go (bpNames bp <> scope)) (bpInits bp <> bpBody bp)
      | otherwise = concatMap (go scope) xs
    go scope (SList xs) = concatMap (go scope) xs
    go _ (SQuote _)     = []      -- data, not a call
    go _ _              = []

lookupBinder :: Vocabulary -> Text -> Maybe BinderShape
lookupBinder vocab h = lookup h [ (bForm b, bShape b) | b <- vBinders vocab ]

atIndex :: Int -> [a] -> Maybe a
atIndex i xs = case drop i xs of
  (x : _) -> Just x
  []      -> Nothing

-- | How a binder's own form decomposes: the names it brings into scope, the
-- initializer expressions inside its list, and where its body starts.
--
-- ONE decomposition, shared by the grounding walk and the arity walk, so the two
-- cannot disagree about what is a parameter. They were separate and did: the
-- arity walk treated a binding list as an expression and only happened to reach
-- the right answer.
data BinderParts = BinderParts
  { bpNames :: [Text]
  , bpInits :: [SExp]
  , bpBody  :: [SExp]
  }

binderParts :: BinderShape -> [SExp] -> BinderParts
binderParts shape xs = case (shape, atIndex i xs) of
  -- @(lambda (x y) body)@: the names are the list at the shape's index.
  (ParamsAt _, Just (SList items)) ->
    BinderParts [ p | SSym p <- items ] [] (from (i + 1))
  -- @(lambda args body)@: a single name taking the whole argument list.
  (ParamsAt _, Just (SSym p)) -> BinderParts [p] [] (from (i + 1))
  -- @(let ((x 1)) body)@: each element's head is a name, its tail an initializer.
  (BindingsAt _, Just (SList items)) ->
    BinderParts (heads items) (inits items) (from (i + 1))
  -- @(let loop ((i 0)) body)@: a binder may NAME ITSELF before its bindings,
  -- which is how a lisp writes a loop -- the name is in scope for the body and
  -- the bindings are one place further along. A SHAPE, not a word: nothing here
  -- knows that Scheme spells this one @let@. Reading the name as the binding list
  -- reported every loop variable as ungrounded and refused honest clauses.
  (BindingsAt _, Just (SSym nm)) -> case atIndex (i + 1) xs of
    Just (SList items) ->
      BinderParts (nm : heads items) (inits items) (from (i + 2))
    _ -> BinderParts [nm] [] (from (i + 1))
  _ -> BinderParts [] [] (from (i + 1))
  where
    i = case shape of
      ParamsAt n   -> n
      BindingsAt n -> n
    from n = drop n xs
    heads items = [ p | SList (SSym p : _) <- items ]
    inits items = concat [ es | SList (SSym _ : es) <- items ]

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

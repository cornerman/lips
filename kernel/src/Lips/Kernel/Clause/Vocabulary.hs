{-# LANGUAGE OverloadedStrings #-}

-- | What grounds a name inside a clause, as data.
--
-- The kernel must never hold a list of Scheme forms, so it holds this type and
-- reads the list from a file. A name in a clause is grounded four ways, and the
-- kernel knows only the four SHAPES, never the members:
--
--   * a /definer/: the form that names a definition. A clause IS one definition,
--     so the kernel needs to know which form makes one, and it must not know
--     WHICH WORD that is: @define@ in Scheme, @defn@ in another Lisp.
--   * a /binder/: a form that brings names into scope for its body
--     (@lambda@, @let@). The declaration says where its names sit, because
--     @(lambda (x) ...)@ and @(let ((x 1)) ...)@ carry them differently.
--   * a /form/: a special form that binds nothing (@cond@, @if@, @or@).
--   * a /procedure/: part of the base notation, present on every runtime,
--     carrying no authority (@car@, @equal?@).
--   * a /contract/: a capability a runtime's adapter provides, and the ONLY way
--     a clause reaches the world. Its arity is part of the declared interface.
--
-- The file format is line-oriented and mirrors @.lang@, so a reviewer reads one
-- grammar everywhere:
--
-- > definer define
-- > binder lambda params 1
-- > binder let bindings 1
-- > form cond
-- > procedure null?
-- > pure json-parse 1 "text -> record, or #f when the text is not JSON"
-- > effect emit 1 "line -> writes it to the output, followed by a newline"
--
-- A line the parser does not recognize is a loud failure naming the line: a
-- vocabulary silently missing a declaration would make the gate reject honest
-- clauses, which is the worst failure this file can have.
module Lips.Kernel.Clause.Vocabulary
  ( Vocabulary (..)
  , Binder (..)
  , BinderShape (..)
  , Contract (..)
  , ContractKind (..)
  , parseVocabulary
  , parseContracts
  , contractNames
  , effectContracts
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

-- | Where a binder's names sit inside its own list.
data BinderShape
  = ParamsAt Int    -- ^ @(lambda ARGS body)@: the names are the list at this index
  | BindingsAt Int  -- ^ @(let BINDINGS body)@: each element's head is a name
  deriving (Eq, Show)

data Binder = Binder { bForm :: Text, bShape :: BinderShape }
  deriving (Eq, Show)

-- | Whether a contract has an effect. A pure contract can be called from a
-- claim with no adapter substitution; an effect contract is exactly what a
-- reviewer wants listed, because it is the program's reach into the world.
data ContractKind = Pure | Effect
  deriving (Eq, Show)

data Contract = Contract
  { cName  :: Text
  , cArity :: Int
  , cKind  :: ContractKind
  , cDoc   :: Text
  }
  deriving (Eq, Show)

data Vocabulary = Vocabulary
  { vDefiners   :: [Text]
  , vBinders    :: [Binder]
  , vForms      :: [Text]
  , vProcedures :: [Text]
  , vContracts  :: [Contract]
  }
  deriving (Eq, Show)

contractNames :: Vocabulary -> [Text]
contractNames = map cName . vContracts

-- | The contracts that reach the world. What a human reads instead of auditing
-- an implementation.
effectContracts :: Vocabulary -> [Contract]
effectContracts = filter ((== Effect) . cKind) . vContracts

-- | Parse a vocabulary file. Contract lines are accepted here too, so one file
-- can carry a whole notation if a runtime prefers that.
parseVocabulary :: Text -> Either Text Vocabulary
parseVocabulary txt = do
  decls <- traverse parseLine (meaningfulLines txt)
  Right (foldr add (Vocabulary [] [] [] [] []) (concat decls))
  where
    add (DDefiner d) v = v { vDefiners = d : vDefiners v }
    add (DBinder b) v = v { vBinders = b : vBinders v }
    add (DForm f) v = v { vForms = f : vForms v }
    add (DProcedure p) v = v { vProcedures = p : vProcedures v }
    add (DContract c) v = v { vContracts = c : vContracts v }

-- | Parse a contracts file: the same parser, restricted to contract lines, so a
-- form declared in the wrong file fails loud instead of being ignored.
parseContracts :: Text -> Either Text [Contract]
parseContracts txt = do
  v <- parseVocabulary txt
  if null (vDefiners v) && null (vBinders v) && null (vForms v) && null (vProcedures v)
    then Right (vContracts v)
    else Left "a contracts file declares only pure and effect contracts"

data Decl
  = DDefiner Text | DBinder Binder | DForm Text | DProcedure Text | DContract Contract

meaningfulLines :: Text -> [Text]
meaningfulLines =
  filter (\l -> not (T.null l) && not ("#" `T.isPrefixOf` l))
    . map T.strip
    . T.lines

parseLine :: Text -> Either Text [Decl]
parseLine line = case T.words body of
  ("definer" : ds) | not (null ds) -> Right (map DDefiner ds)
  ("binder" : form : shape : n : []) -> do
    idx <- readIndex n
    sh <- case shape of
      "params"   -> Right (ParamsAt idx)
      "bindings" -> Right (BindingsAt idx)
      _ -> bad "a binder is written: binder <form> params|bindings <index>"
    Right [DBinder (Binder form sh)]
  ("form" : fs) | not (null fs) -> Right (map DForm fs)
  ("procedure" : ps) | not (null ps) -> Right (map DProcedure ps)
  ("pure" : name : n : _) -> contract Pure name n
  ("effect" : name : n : _) -> contract Effect name n
  _ -> bad "a line declares a definer, binder, form, procedure, pure or effect"
  where
    -- The doc string is the quoted tail; splitting it off first keeps `words`
    -- from tearing a multi-word meaning apart.
    (body, doc) = T.breakOn "\"" line
    contract kind name n = do
      arity <- readIndex n
      Right [DContract (Contract name arity kind (T.dropAround (== '"') (T.strip doc)))]
    readIndex n = case decimal' n of
      Just i  -> Right i
      Nothing -> bad "expected a number"
    bad why = Left (why <> ", but this line reads: " <> line)

-- | A whole non-negative decimal, or 'Nothing'. Local because the one in
-- @Data.Text.Read@ returns the unconsumed tail, and a declaration with a tail
-- is a malformed declaration.
decimal' :: Text -> Maybe Int
decimal' t
  | not (T.null t), T.all (\c -> c >= '0' && c <= '9') t = Just (read (T.unpack t))
  | otherwise = Nothing

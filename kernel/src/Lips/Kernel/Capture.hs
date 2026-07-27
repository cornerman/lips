{-# LANGUAGE OverloadedStrings #-}

-- | The value-keyed capture primitive, shared by every stage that matches a
-- subject the model wrote (rules, expects, demands). A capture lets ONE minted
-- item address a FAMILY of concrete decisions: a subject segment written
-- @\<name\>@ binds any concrete segment (@route.\<path\>.status@ matches
-- @route./hello.status@), and the captured key then fills @\<name\>@
-- occurrences the item emits (an option path, an expect path). This is the
-- per-item analogue of the language-level @\<self\>@ instance key.
--
-- Kept in one module so the three stages cannot drift: a capability is
-- complete only when it works everywhere the grammar admits it, and a subject
-- the model may write with a capture must resolve identically wherever it is
-- matched.
module Lips.Kernel.Capture
  ( captureName
  , matchSubject
  , fillCaptures
  , NamePiece (..)
  , nameParse
  , nameTokens
  , fillName
  , selfName
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

-- | A subject segment written @\<name\>@ is a capture (binds any concrete
-- segment); anything else is a literal. An empty @\<\>@ is not a capture.
captureName :: Text -> Maybe Text
captureName s = do
  inner <- T.stripSuffix ">" =<< T.stripPrefix "<" s
  if T.null inner then Nothing else Just inner

-- | Match a subject pattern against a concrete subject: literals must be equal,
-- a @\<name\>@ capture binds its concrete segment (a repeated name must bind
-- consistently). 'Nothing' on any mismatch. With no captures this is exact
-- equality, so replacing an @==@ check with 'matchSubject' stays backward
-- compatible while gaining family matching.
matchSubject :: [Text] -> [Text] -> Maybe (Map Text Text)
matchSubject pat conc
  | length pat /= length conc = Nothing
  | otherwise                 = foldl' step (Just Map.empty) (zip pat conc)
  where
    step Nothing _ = Nothing
    step (Just m) (p, c) = case captureName p of
      Nothing -> if p == c then Just m else Nothing
      Just nm -> case Map.lookup nm m of
        Nothing              -> Just (Map.insert nm c m)
        Just prev | prev == c -> Just m
                  | otherwise -> Nothing

-- | Fill every @\<name\>@ occurrence in one emitted segment with its captured
-- binding. A name may be a whole segment OR embedded in one (a literal prefix
-- the model composes, e.g. @http-routes\<path\>@), so every occurrence is
-- substituted. A name the subject never bound, or an unterminated @\<@, is a
-- 'Left' naming the bare reason (the caller prefixes its own id) -- never a
-- silent literal that would collide.
fillCaptures :: Map Text Text -> Text -> Either Text Text
fillCaptures caps s = case nameParse s of
  Left _       -> Left ("unterminated <capture> in: " <> s)
  Right pieces -> T.concat <$> traverse fill pieces
  where
    fill (NLit t)  = Right t
    fill (NTok nm) = case Map.lookup nm caps of
      Just v  -> Right v
      Nothing -> Left ("capture <" <> nm <> "> is not bound by the subject")

-- | The reserved token that names the instance (spelled @\<self\>@). Kept as
-- one literal so every stage that fills or skips it agrees on the spelling: it
-- is not a capture (no rule subject binds it), it binds at realize time.
selfName :: Text
selfName = "self"

-- | One piece of a NAME: literal text, or a @\<token\>@ occurrence (a capture,
-- or the reserved @self@).
data NamePiece = NLit Text | NTok Text
  deriving (Eq, Show)

-- | The ONE name grammar: a name is literal text with @\<token\>@ occurrences
-- embedded, so @\<self\>-core@ is a name (the instance's own build, suffixed)
-- exactly as @http-routes\<path\>@ is. Shared by emit-path segments, path
-- literals and artifact-reference names, so a token fills the same way
-- wherever the grammar admits a name -- the asymmetry it replaces (a capture
-- filled embedded, @\<self\>@ only whole, an artifact name neither) made a
-- two-artifact program unwritable. An unterminated @\<@ or an empty @\<\>@ is
-- a 'Left' naming the reason.
nameParse :: Text -> Either Text [NamePiece]
nameParse s = case T.breakOn "<" s of
  (before, rest)
    | T.null rest -> Right (lit before)
    | otherwise   ->
        let (nm, after) = T.breakOn ">" (T.drop 1 rest)
         in if T.null after
              then Left ("unterminated < in: " <> s)
              else if T.null nm
                then Left ("an empty <> is not a name token, in: " <> s)
                else (\tl -> lit before ++ NTok nm : tl) <$> nameParse (T.drop 1 after)
  where
    lit t = [NLit t | not (T.null t)]

-- | Every @\<token\>@ a name mentions, in order. A malformed name yields none;
-- its caller reports the malformation through its own parse.
nameTokens :: Text -> [Text]
nameTokens s = either (const []) (\ps -> [nm | NTok nm <- ps]) (nameParse s)

-- | Fill the @\<token\>@ occurrences the resolver knows, leaving every other
-- one verbatim. The lenient twin of 'fillCaptures', for the stages that resolve
-- only part of a name: @\<self\>@ binds per instance and a capture per rule
-- match, so each pass must leave the other's tokens standing. A token nobody
-- ever fills is caught at realize, never rendered into a module.
fillName :: (Text -> Maybe Text) -> Text -> Text
fillName resolve s = case nameParse s of
  Left _       -> s
  Right pieces -> T.concat (map fill pieces)
  where
    fill (NLit t)  = t
    fill (NTok nm) = maybe ("<" <> nm <> ">") id (resolve nm)

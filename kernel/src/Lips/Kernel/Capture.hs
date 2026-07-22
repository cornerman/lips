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
fillCaptures caps = go
  where
    go s = case T.breakOn "<" s of
      (before, rest)
        | T.null rest -> Right before
        | otherwise   ->
            let (nm, after) = T.breakOn ">" (T.drop 1 rest)
             in if T.null after
                  then Left ("unterminated <capture> in: " <> s)
                  else case Map.lookup nm caps of
                    Just v  -> (\tl -> before <> v <> tl) <$> go (T.drop 1 after)
                    Nothing -> Left ("capture <" <> nm <> "> is not bound by the subject")

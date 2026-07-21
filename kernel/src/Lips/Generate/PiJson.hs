{-# LANGUAGE OverloadedStrings #-}

-- | Parse pi's @--mode json@ event stream (JSONL) to recover two things the
-- CLI needs from a mint: the assistant's reply text and the model pi actually
-- used. Reading the model back lets lips pick no model at all (it omits
-- @--model@ so pi's own configured default applies) while still recording a
-- concrete model in @.generation@, so provenance and @genId@ stay honest.
--
-- This lives in the Generate tier (the AI boundary), not the kernel: only here
-- does lips depend on @aeson@. The kernel proper stays base+containers+text.
module Lips.Generate.PiJson
  ( PiReply (..)
  , parsePiReply
  ) where

import           Data.Aeson            (Value (..), decode)
import qualified Data.Aeson.KeyMap     as KM
import qualified Data.ByteString.Lazy  as BL
import           Data.Foldable         (asum, toList)
import           Data.Maybe            (mapMaybe)
import           Data.Text             (Text)
import qualified Data.Text             as T
import qualified Data.Text.Encoding    as TE

-- | What the CLI extracts from a pi run: the assistant text (the minted
-- engine) and the concrete model that produced it.
data PiReply = PiReply
  { prReply :: Text
  , prModel :: Text
  }
  deriving (Eq, Show)

-- | Parse the whole JSONL stream. The reply is the assistant text carried by
-- the terminal @agent_end@ event (authoritative and complete); the model is
-- the first @model@ field seen anywhere in the stream (every message repeats
-- it, identically). Missing values come back empty, so the caller can fail
-- loud.
parsePiReply :: Text -> PiReply
parsePiReply out =
  PiReply
    { prReply = maybe "" id (asum (map replyFrom events))
    , prModel = maybe "" id (asum (map findModel events))
    }
  where
    events = mapMaybe decodeLine (T.lines out)
    decodeLine l = decode (BL.fromStrict (TE.encodeUtf8 l)) :: Maybe Value

-- | The assistant text of the @agent_end@ event: concatenate the text content
-- of its assistant messages (with tools disabled there is exactly one turn).
replyFrom :: Value -> Maybe Text
replyFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (T.concat (concatMap assistantText (toList msgs)))
replyFrom _ = Nothing

-- | Text pieces of a message, only if its role is assistant.
assistantText :: Value -> [Text]
assistantText (Object m)
  | KM.lookup "role" m == Just (String "assistant")
  , Just (Array content) <- KM.lookup "content" m =
      [ t
      | Object c <- toList content
      , KM.lookup "type" c == Just (String "text")
      , Just (String t) <- [KM.lookup "text" c]
      ]
assistantText _ = []

-- | The first non-empty @model@ string anywhere in a value tree.
findModel :: Value -> Maybe Text
findModel (Object o) =
  case KM.lookup "model" o of
    Just (String m) | not (T.null m) -> Just m
    _                                -> asum (map findModel (KM.elems o))
findModel (Array a) = asum (map findModel (toList a))
findModel _         = Nothing

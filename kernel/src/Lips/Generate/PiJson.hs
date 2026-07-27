{-# LANGUAGE OverloadedStrings #-}

-- | Parse pi's @--mode json@ event stream (JSONL) to recover three things the
-- CLI needs from a mint: the assistant's reply text, the model pi actually
-- used, and the schema lookups the mint made. Reading the model back lets lips
-- pick no model at all (it omits @--model@ so pi's own configured default
-- applies) while still recording a concrete model in @.generation@, so
-- provenance and @genId@ stay honest.
--
-- All three come out of the terminal @agent_end@ event, which carries the whole
-- message list: one traversal of one structure, rather than a second pass over
-- the @tool_execution_*@ events that repeat the same payload one level deeper.
--
-- This lives in the Generate tier (the AI boundary), not the kernel: only here
-- does lips depend on @aeson@. The kernel proper stays base+containers+text.
module Lips.Generate.PiJson
  ( PiReply (..)
  , parsePiReply
  ) where

import           Data.Aeson            (Value (..), decode, encode)
import qualified Data.Aeson.KeyMap     as KM
import qualified Data.ByteString.Lazy  as BL
import           Data.Foldable         (asum, toList)
import           Data.Maybe            (mapMaybe)
import           Data.Text             (Text)
import qualified Data.Text             as T
import qualified Data.Text.Encoding    as TE

-- | What the CLI extracts from a pi run: the assistant text (the minted
-- engine), the concrete model that produced it, and a transcript of every tool
-- call it made.
data PiReply = PiReply
  { prReply      :: Text
  , prModel      :: Text
  , prTranscript :: Text
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
    { prReply      = maybe "" id (asum (map replyFrom events))
    , prModel      = maybe "" id (asum (map findModel events))
    , prTranscript = maybe "" id (asum (map transcriptFrom events))
    }
  where
    events = mapMaybe decodeLine (T.lines out)
    decodeLine l = decode (BL.fromStrict (TE.encodeUtf8 l)) :: Maybe Value

-- | The minted engine is the text of the LAST assistant message of @agent_end@.
-- Not every assistant message: the mint has a tool, so it may act several times
-- before answering, and a model that narrates on the way ("let me look that
-- option up") would otherwise have its narration concatenated in front of the
-- engine, failing the engine parser for a reason that is not the model's fault.
-- The engine is what the model says once it has stopped looking things up.
replyFrom :: Value -> Maybe Text
replyFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (case reverse [ ts | m <- toList msgs, let ts = assistantText m, not (null ts) ] of
              (final : _) -> T.concat final
              []          -> "")
replyFrom _ = Nothing

-- | Every tool call and its answer, in order, as flat text for the record: a
-- lookup the model performed is evidence, where a fact it recalled is not, so
-- invariant 6 wants it hashed into the generation id alongside the reply.
--
-- The shapes are pi's, measured from a real stream: a call is a @toolCall@
-- content block of an assistant message (@name@, @arguments@), its answer a
-- message of role @toolResult@ (@toolName@, @content@ blocks, @isError@).
transcriptFrom :: Value -> Maybe Text
transcriptFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (T.concat (concatMap toolLines (toList msgs)))
transcriptFrom _ = Nothing

-- | The transcript lines a single message contributes: none for a plain
-- assistant or user message.
toolLines :: Value -> [Text]
toolLines (Object m)
  | KM.lookup "role" m == Just (String "toolResult") =
      [ "<- " <> name <> (if isError then " (FAILED)" else "") <> "\n"
          <> truncated (T.concat (textBlocks (KM.lookup "content" m))) <> "\n" ]
  | KM.lookup "role" m == Just (String "assistant")
  , Just (Array content) <- KM.lookup "content" m =
      [ "-> " <> callName c <> " " <> renderArgs c <> "\n"
      | Object c <- toList content
      , KM.lookup "type" c == Just (String "toolCall") ]
  where
    isError = KM.lookup "isError" m == Just (Bool True)
    name = case KM.lookup "toolName" m of
      Just (String n) -> n
      _               -> "?"
    callName c = case KM.lookup "name" c of
      Just (String n) -> n
      _               -> "?"
    -- The arguments verbatim, so the record shows the exact question asked.
    renderArgs c = case KM.lookup "arguments" c of
      Just (Object as) -> T.intercalate " "
        [ TE.decodeUtf8 (BL.toStrict (encode v)) | v <- KM.elems as ]
      _                -> ""
toolLines _ = []

-- | Text of a content field, which pi writes as an array of typed blocks.
textBlocks :: Maybe Value -> [Text]
textBlocks (Just (Array cs)) =
  [ t | Object c <- toList cs
      , KM.lookup "type" c == Just (String "text")
      , Just (String t) <- [KM.lookup "text" c] ]
textBlocks _ = []

-- | A schema answer can run to thousands of lines; the record needs evidence of
-- what the mint was told, not a second copy of the schema. The elision is
-- stated, so a reader knows the record is abridged and by how much.
truncated :: Text -> Text
truncated t
  | T.length t <= limit = t
  | otherwise = T.take limit t <> "\n\8230 [truncated, "
      <> T.pack (show (T.length t - limit)) <> " characters elided]"
  where limit = 4000

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

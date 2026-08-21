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
    -- * Live progress
  , Usage (..)
  , PiEvent (..)
  , progressEvent
  , abbreviate
  , resultSummary
  ) where

import           Data.Aeson            (Value (..), decode, encode)
import qualified Data.Aeson.KeyMap     as KM
import qualified Data.ByteString.Lazy  as BL
import           Data.Foldable         (asum, toList)
import qualified Data.Map.Strict       as M
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
  , prTurns      :: Int
  , prTools      :: [(Text, Int)]
  , prUsage      :: Maybe Usage
  }
  deriving (Eq, Show)

-- | What a mint cost, as pi's own accounting reports it. Read rather than
-- estimated: a token count lips computed itself would be a second opinion about
-- somebody else's billing.
-- Measured against a live @--mode json@ run (2026-08-20): an assistant message
-- of @agent_end@ carries @usage {input, output, cacheRead, cacheWrite,
-- totalTokens, cost {..., total}}@. The dollar figure is pi's own, so it is read
-- like the rest; lips never multiplies tokens by a price it would have to keep
-- true.
data Usage = Usage
  { usInput      :: Integer
  , usOutput     :: Integer
  , usCacheRead  :: Integer
  , usCacheWrite :: Integer
  , usCost       :: Double
  }
  deriving (Eq, Show)

-- | What one event of the stream is worth showing a human while the mint runs.
-- The mint is the only phase that takes minutes, and before this the terminal
-- said nothing at all for its whole duration, so a working model and a hung one
-- looked the same.
--
-- Rendered in full here and abbreviated at the point of display, so the same
-- events serve the ordinary view (one short line per tool call) and
-- @--verbose@ (everything, untruncated).
data PiEvent
  = PiTool Text Text        -- ^ a call: tool name, its arguments
  | PiToolEnd Text Bool Text -- ^ its answer: tool name, whether it failed, the text
  | PiState Text            -- ^ what the model is doing now
  | PiProse Text            -- ^ a chunk of the model's own words
  deriving (Eq, Show)

-- | Read one JSONL line as progress, or nothing when the event carries none.
--
-- No tool is named here: a tool call shows the name pi reports and the
-- arguments as given, so a mint tool added later is displayed without touching
-- this code.
progressEvent :: Text -> Maybe PiEvent
progressEvent line = decodeLine line >>= eventOf
  where
    decodeLine l = decode (BL.fromStrict (TE.encodeUtf8 l)) :: Maybe Value

eventOf :: Value -> Maybe PiEvent
eventOf (Object o) = case KM.lookup "type" o of
  Just (String "tool_execution_start") ->
    Just (PiTool (toolName o) (renderArgsOf (KM.lookup "args" o)))
  Just (String "tool_execution_end") ->
    Just (PiToolEnd (toolName o) (KM.lookup "isError" o == Just (Bool True))
                    (T.concat (textBlocks (resultContent (KM.lookup "result" o)))))
  Just (String "turn_start") -> Just (PiState "waiting for the model")
  Just (String "message_update") -> case KM.lookup "assistantMessageEvent" o of
    Just (Object e) -> case (KM.lookup "type" e, KM.lookup "delta" e) of
      (Just (String "text_delta"), Just (String d))     -> Just (PiProse d)
      (Just (String "thinking_delta"), _)               -> Just (PiState "thinking")
      _                                                -> Nothing
    _ -> Nothing
  _ -> Nothing
eventOf _ = Nothing

toolName :: KM.KeyMap Value -> Text
toolName o = case KM.lookup "toolName" o of
  Just (String n) -> n
  _               -> "?"

-- | A tool answer's content blocks, which pi nests under @result@.
resultContent :: Maybe Value -> Maybe Value
resultContent (Just (Object r)) = KM.lookup "content" r
resultContent _                 = Nothing

-- | Arguments as the model passed them, values only: a tool's parameter names
-- add no information a reader of one line needs (the tool name already says
-- what the value is), and the raw json quoting is what makes the exact question
-- visible.
renderArgsOf :: Maybe Value -> Text
renderArgsOf (Just (Object as)) = T.intercalate " " (map render (KM.elems as))
  where
    render (String s) = s
    render v          = TE.decodeUtf8 (BL.toStrict (encode v))
renderArgsOf _ = ""

-- | One line out of any text: its first line, cut to @n@ characters, with what
-- was left out stated. Used for the ordinary view; @--verbose@ shows the text
-- itself.
abbreviate :: Int -> Text -> Text
abbreviate n t
  | T.null rest, T.length first <= n = first
  | otherwise = T.take n first <> "\8230"
  where
    (first, rest) = T.breakOn "\n" (T.strip t)

-- | A tool answer in one phrase: how much came back, or -- when the tool
-- refused -- the first thing it said, which is the part that matters.
resultSummary :: Bool -> Text -> Text
resultSummary True  t = "failed: " <> abbreviate 60 t
resultSummary False t
  | T.null (T.strip t) = "ok"
  | n == 1             = abbreviate 60 t
  | otherwise          = "ok, " <> T.pack (show n) <> " lines"
  where n = length (T.lines (T.strip t))

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
    , prTurns      = maybe 0 id (asum (map turnsFrom events))
    , prTools      = maybe [] id (asum (map toolsFrom events))
    , prUsage      = maybe Nothing id (asum (map usageFrom events))
    }
  where
    events = mapMaybe decodeLine (T.lines out)
    decodeLine l = decode (BL.fromStrict (TE.encodeUtf8 l)) :: Maybe Value

-- | Assistant messages of the terminal event: one per model turn. Turn COUNT is
-- the larger factor in what a mint costs (DESIGN \167\&13), so it is the first
-- number the stats file wants. Counted from @agent_end@ rather than from the
-- @turn_start@ events, so every figure recorded about a mint is read off the one
-- message list that is authoritative and complete.
turnsFrom :: Value -> Maybe Int
turnsFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (length [ () | Object m <- toList msgs
                        , KM.lookup "role" m == Just (String "assistant") ])
turnsFrom _ = Nothing

-- | How often the mint called each tool, by name, sorted so two runs compare
-- line by line. The @check_draft@ count is the interesting one: it says whether
-- a mint's turns went into drafting or into thinking.
toolsFrom :: Value -> Maybe [(Text, Int)]
toolsFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (M.toAscList (M.fromListWith (+) [ (n, 1 :: Int) | n <- names msgs ]))
  where
    names msgs =
      [ n
      | Object m <- toList msgs
      , KM.lookup "role" m == Just (String "assistant")
      , Just (Array content) <- [KM.lookup "content" m]
      , Object c <- toList content
      , KM.lookup "type" c == Just (String "toolCall")
      , Just (String n) <- [KM.lookup "name" c] ]
toolsFrom _ = Nothing

-- | The run's token usage: the per-message figures summed. 'Nothing' when no
-- message carries any, which is stated rather than guessed -- a zero would read
-- as a mint that cost nothing.
usageFrom :: Value -> Maybe (Maybe Usage)
usageFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (case [ u | Object m <- toList msgs
                     , Just u <- [usageOf (KM.lookup "usage" m)] ] of
              [] -> Nothing
              us -> Just (foldr1 plus us))
  where
    plus a b = Usage (usInput a + usInput b) (usOutput a + usOutput b)
                     (usCacheRead a + usCacheRead b) (usCacheWrite a + usCacheWrite b)
                     (usCost a + usCost b)
usageFrom _ = Nothing

-- | One message's usage object. Every field is optional and defaults to zero:
-- the shape is pi's, not lips', so a field that moves must not lose the fields
-- that are still there.
usageOf :: Maybe Value -> Maybe Usage
usageOf (Just (Object u)) =
  Just (Usage (num "input") (num "output") (num "cacheRead") (num "cacheWrite") cost)
  where
    num k = case KM.lookup k u of
      Just (Number n) -> truncate n
      _               -> 0
    -- What this message billed, from pi's nested @cost.total@; absent bills as
    -- zero, which sums correctly with the messages that do carry it.
    cost = case KM.lookup "cost" u of
      Just (Object c) -> case KM.lookup "total" c of
        Just (Number n) -> realToFrac n
        _               -> 0
      _ -> 0
usageOf _ = Nothing

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

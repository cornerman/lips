{-# LANGUAGE OverloadedStrings #-}

-- | The language-server shell: a minimal LSP over stdio (JSON-RPC framed by
-- @Content-Length@). It is domain-blind -- one @lips lsp@ process serves every
-- lips language, because the language is data: for each document it loads the
-- @\<file\>.lang@ sitting beside it and derives completion and diagnostics from
-- that (via 'Lips.Lsp.Derive', reusing the same 'diagnose' as @lips check@).
--
-- Deliberately small: full-text sync, completion, and push diagnostics. No
-- caching (each event re-reads the @.lang@ from disk, so a regenerate is picked
-- up for free) and no model, ever -- the server is pure of AI, like @run@.
module Lips.Lsp.Server
  ( runLsp
  , uriToPath
  ) where

import           Control.Exception       (IOException, try)
import           Data.Aeson              (FromJSON (..), Value (..), decode, encode,
                                          object, withObject, (.!=), (.:), (.:?), (.=))
import           Data.Aeson.Types        (parseMaybe)
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Char8   as BC
import qualified Data.ByteString.Lazy    as BL
import           Data.Char               (digitToInt, isHexDigit)
import           Data.IORef
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Maybe              (fromMaybe)
import           Data.Text               (Text)
import qualified Data.Text               as T
import qualified Data.Text.Encoding      as TE
import qualified Data.Text.Encoding.Error as TEE
import qualified Data.Text.IO            as TIO
import           Data.Word               (Word8)
import           System.Exit             (exitSuccess)
import           System.IO
import           Text.Read               (readMaybe)

import Lips.Identity              (langPath)
import Lips.Kernel.Lang.Diagnose (diagnose)
import Lips.Kernel.Lang.Store     (EngineData (..), readLang)
import Lips.Lsp.Derive

-- | A decoded JSON-RPC message: its @id@ (present on a request, absent on a
-- notification), its @method@ (absent on a client's response, which this
-- server never awaits and so ignores), and its params.
data Msg = Msg (Maybe Value) (Maybe Text) Value

instance FromJSON Msg where
  parseJSON = withObject "Msg" $ \o ->
    Msg <$> o .:? "id" <*> o .:? "method" <*> o .:? "params" .!= Null

-- | Run the server: set stdio to binary, then loop over framed messages until
-- the client closes the stream.
runLsp :: IO ()
runLsp = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout NoBuffering
  docs <- newIORef Map.empty
  loop docs

loop :: IORef (Map Text Text) -> IO ()
loop docs = do
  m <- recvMessage
  case m of
    Nothing -> pure ()
    Just bs -> do
      maybe (pure ()) (dispatch docs) (decode bs)
      loop docs

dispatch :: IORef (Map Text Text) -> Msg -> IO ()
dispatch docs (Msg mid mmethod params) = case mmethod of
  Nothing     -> pure ()
  Just method -> case method of
    "initialize" -> respond mid initResult
    "shutdown"   -> respond mid Null
    "exit"       -> exitSuccess
    "textDocument/didOpen" ->
      withUriText (\uri text -> setDoc uri text >> publish uri text)
        (paramUri params) (docText params)
    "textDocument/didChange" ->
      withUriText (\uri text -> setDoc uri text >> publish uri text)
        (paramUri params) (changeText params)
    "textDocument/didSave" -> case paramUri params of
      Just uri -> readIORef docs >>= maybe (pure ()) (publish uri) . Map.lookup uri
      Nothing  -> pure ()
    "textDocument/didClose" -> case paramUri params of
      Just uri -> modifyIORef' docs (Map.delete uri)
      Nothing  -> pure ()
    "textDocument/completion" -> do
      let uri = fromMaybe "" (paramUri params)
      meng <- loadLang (uriToPath uri)
      respond mid (completionList (maybe [] (completionItems . edPatterns) meng))
    -- Any other request must still get a reply, or a strict client hangs.
    _ -> maybe (pure ()) (const (respond mid Null)) mid
  where
    setDoc uri text = modifyIORef' docs (Map.insert uri text)
    withUriText k mu mt = case (mu, mt) of
      (Just uri, Just text) -> k uri text
      _                     -> pure ()

-- | Load and diagnose a document, then push diagnostics. A missing or
-- unreadable @.lang@ clears diagnostics (an empty list), rather than erroring.
publish :: Text -> Text -> IO ()
publish uri text = do
  let path = uriToPath uri
  meng <- loadLang path
  let diags = case meng of
        Just eng -> map diagValue (diagsOf (diagnose path eng text))
        Nothing  -> []
  notify "textDocument/publishDiagnostics"
    (object ["uri" .= uri, "diagnostics" .= diags])

-- Server capabilities: full-text sync (1) and completion.
initResult :: Value
initResult = object
  [ "capabilities" .= object
      [ "textDocumentSync" .= (1 :: Int)
      , "completionProvider" .= object ["resolveProvider" .= False]
      ]
  , "serverInfo" .= object ["name" .= ("lips" :: Text)]
  ]

completionList :: [CItem] -> Value
completionList items = object
  [ "isIncomplete" .= False
  , "items" .= map citemValue items
  ]
  where
    citemValue (CItem label snip) = object
      [ "label" .= label
      , "kind" .= (15 :: Int)          -- Snippet
      , "insertText" .= snip
      , "insertTextFormat" .= (2 :: Int) -- Snippet syntax (${1:hole})
      ]

diagValue :: Diag -> Value
diagValue (Diag l s e sev msg) = object
  [ "range" .= object ["start" .= pos l s, "end" .= pos l e]
  , "severity" .= sev
  , "source" .= ("lips" :: Text)
  , "message" .= msg
  ]
  where pos ln ch = object ["line" .= ln, "character" .= ch]

-- Field extractors over the params object (return Nothing when absent).
paramUri :: Value -> Maybe Text
paramUri = parseMaybe (withObject "p" (\p -> p .: "textDocument" >>= (.: "uri")))

docText :: Value -> Maybe Text
docText = parseMaybe (withObject "p" (\p -> p .: "textDocument" >>= (.: "text")))

-- Full-sync change: the last content change carries the whole document text.
changeText :: Value -> Maybe Text
changeText = parseMaybe $ withObject "p" $ \p -> do
  changes <- p .: "contentChanges"
  case reverse changes of
    (c : _) -> withObject "change" (.: "text") c
    []      -> fail "no content changes"

-- | Load the program's shared language, resolved by extension (a program
-- @ledger.backup@ reads @backup.lang@ beside it), matching the CLI. Completion
-- and diagnostics are pattern-level (front half), so no @<self>@ binding is
-- needed here.
loadLang :: FilePath -> IO (Maybe EngineData)
loadLang path = do
  msrc <- tryReadFile (langPath path)
  pure $ case msrc of
    Just src -> either (const Nothing) Just (readLang src)
    Nothing  -> Nothing

-- | Strip the @file://@ scheme and percent-decode to a filesystem path. A
-- @%XX@ escape is a UTF-8 byte, so decoding collects raw bytes (each
-- non-escaped char re-encoded to its UTF-8 bytes) and then reads the whole
-- sequence back as UTF-8, so paths with spaces or non-ASCII round-trip.
-- Decoding is lenient rather than crashing the server loop on a malformed URI.
uriToPath :: Text -> FilePath
uriToPath uri =
  let stripped = fromMaybe uri (T.stripPrefix "file://" uri)
   in T.unpack (TE.decodeUtf8With TEE.lenientDecode (BS.pack (decodeBytes (T.unpack stripped))))

-- | Percent-decode a URI path into raw bytes: a @%XX@ pair is one byte; any
-- other char contributes its own UTF-8 bytes.
decodeBytes :: String -> [Word8]
decodeBytes [] = []
decodeBytes ('%' : h : l : rest)
  | isHexDigit h, isHexDigit l =
      fromIntegral (digitToInt h * 16 + digitToInt l) : decodeBytes rest
decodeBytes (c : rest) = BS.unpack (TE.encodeUtf8 (T.singleton c)) ++ decodeBytes rest

tryReadFile :: FilePath -> IO (Maybe Text)
tryReadFile p = either (const Nothing) Just <$> (try (TIO.readFile p) :: IO (Either IOException Text))

-- JSON-RPC responses and notifications.
respond :: Maybe Value -> Value -> IO ()
respond mid result = send $ object
  ["jsonrpc" .= ("2.0" :: Text), "id" .= fromMaybe Null mid, "result" .= result]

notify :: Text -> Value -> IO ()
notify method params = send $ object
  ["jsonrpc" .= ("2.0" :: Text), "method" .= method, "params" .= params]

-- Wire framing: a Content-Length header, a blank line, then the JSON body.
send :: Value -> IO ()
send v = do
  let body = encode v
      hdr  = BC.pack ("Content-Length: " ++ show (BL.length body) ++ "\r\n\r\n")
  BS.hPut stdout hdr
  BL.hPut stdout body
  hFlush stdout

recvMessage :: IO (Maybe BL.ByteString)
recvMessage = do
  mlen <- readHeaders Nothing
  case mlen of
    Nothing -> pure Nothing
    Just n  -> Just . BL.fromStrict <$> BS.hGet stdin n

-- Read header lines until the blank separator; return the Content-Length, or
-- Nothing at end of stream.
readHeaders :: Maybe Int -> IO (Maybe Int)
readHeaders acc = do
  ml <- readLineCRLF
  case ml of
    Nothing -> pure Nothing
    Just line
      | BS.null line -> pure acc
      | Just v <- BC.stripPrefix "Content-Length:" line ->
          readHeaders (readMaybe (filter (/= ' ') (BC.unpack v)))
      | otherwise -> readHeaders acc

-- Read one CRLF-terminated line (one byte at a time; headers are tiny). Nothing
-- signals end of stream before any byte of the line.
readLineCRLF :: IO (Maybe BS.ByteString)
readLineCRLF = go [] False
  where
    go acc got = do
      b <- BS.hGet stdin 1
      if BS.null b
        then pure (if got then Just (finish acc) else Nothing)
        else
          let c = BS.head b
           in if c == 10 then pure (Just (finish acc)) else go (c : acc) True
    finish acc =
      let fwd = reverse acc
       in BS.pack (if not (null fwd) && last fwd == 13 then init fwd else fwd)

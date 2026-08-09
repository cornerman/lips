{-# LANGUAGE OverloadedStrings #-}

-- | The language-server shell: a minimal LSP over stdio (JSON-RPC framed by
-- @Content-Length@). It is domain-blind -- one @lips lsp@ process serves every
-- lips language, because the language is data: for each document it loads the
-- grammar from the language folder beside it (@ledger.backup.lips@ ->
-- @backup/backup.grammar@, resolved by 'Lips.Identity.grammarPathIn') and derives
-- completion and diagnostics from
-- that (via 'Lips.Lsp.Derive', reusing the same 'diagnose' as @lips check@).
--
-- Deliberately small: full-text sync, completion, hover, and push diagnostics. No
-- caching (each event re-reads the grammar from disk, so a regenerate is picked
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
import           Data.Char               (digitToInt, isHexDigit, isSpace)
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
import           System.Directory        (doesDirectoryExist)
import           System.Exit             (exitSuccess)
import           System.IO
import           Text.Read               (readMaybe)

import Lips.Identity              (artifactsPathIn, grammarPathIn, instanceName,
                                   langDir, resolveLangDir)
import Lips.Kernel.Claim         (claimRooted)
import Lips.Kernel.Engine.Data   (Emit (..), MapRule (..))
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
      docsMap <- readIORef docs
      -- The buffer text is authoritative (it may be unsaved); fall back to the
      -- file on disk if the editor never opened the document here.
      mtext <- case Map.lookup uri docsMap of
        Just t  -> pure (Just t)
        Nothing -> tryReadFile (uriToPath uri)
      let (line, col) = fromMaybe (0, 0) (paramPos params)
          ltext = lineText mtext line
          startCol = min col (leadingCol ltext)
          items = maybe [] (\eng -> completionItemsAt eng ltext col) meng
      respond mid (completionList line startCol col items)
    -- What a line BECOMES, on demand: the machinery lips derives is otherwise
    -- only readable in the compiled module, and an author's whole artifact is
    -- the sentence. Pure ('hoverAt'), so it states what the build will do.
    "textDocument/hover" -> do
      let uri = fromMaybe "" (paramUri params)
          path = uriToPath uri
      meng <- loadLang path
      docsMap <- readIORef docs
      mtext <- case Map.lookup uri docsMap of
        Just t  -> pure (Just t)
        Nothing -> tryReadFile path
      let (line, _) = fromMaybe (0, 0) (paramPos params)
          mhover = do
            eng  <- meng
            text <- mtext
            hoverAt eng (instanceName path) (diagnose path eng text) line
      respond mid (maybe Null (hoverValue line (lineText mtext line)) mhover)
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
  -- Whether the language bakes source is a fact about the language folder, not
  -- about the program, so the server reads it and the derivation stays pure.
  bakes <- case resolveLangDir path Nothing of
    Left _    -> pure False
    Right dir -> doesDirectoryExist (artifactsPathIn dir path)
  let diags = case meng of
        Just eng ->
          let d = diagnose path eng text
              -- A claim reaches the program only through a rule emit, which is
              -- readable from the engine alone -- no realization needed, so the
              -- editor pays nothing.
              statesClaim = any (any (claimRooted . emPath) . mrEmits) (edRules eng)
           in map diagValue (diagsOf d ++ unobservedDiags bakes statesClaim d)
        Nothing  -> []
  notify "textDocument/publishDiagnostics"
    (object ["uri" .= uri, "diagnostics" .= diags])

-- Server capabilities: full-text sync (1) and completion.
initResult :: Value
initResult = object
  [ "capabilities" .= object
      [ "textDocumentSync" .= (1 :: Int)
      , "completionProvider" .= object ["resolveProvider" .= False]
      , "hoverProvider" .= True
      ]
  , "serverInfo" .= object ["name" .= ("lips" :: Text)]
  ]

completionList :: Int -> Int -> Int -> [CItem] -> Value
completionList line startCol endCol items = object
  [ -- Contextual: the snippet depends on the cursor, so the client must
    -- re-request as the user types rather than filter a cached list.
    "isIncomplete" .= True
  , "items" .= map citemValue items
  ]
  where
    citemValue (CItem label snip mdetail) = object $
      [ "label" .= label
      , "kind" .= (15 :: Int)          -- Snippet
      , "insertText" .= snip
      , "insertTextFormat" .= (2 :: Int) -- Snippet syntax (${1:hole})
      -- Replace the typed prefix with the whole sentence, so accepting completes
      -- what was started instead of duplicating it. The range spans from the
      -- first typed token (after any indentation) to the cursor.
      , "textEdit" .= object
          [ "range" .= object ["start" .= lspPos line startCol, "end" .= lspPos line endCol]
          , "newText" .= snip
          ]
      ]
      -- What each hole still to fill must BE, as the engine's rules fix it. Sent
      -- only when the engine types at least one, so an editor never shows an
      -- empty annotation.
      ++ [ "detail" .= detail | Just detail <- [mdetail] ]

-- | A hover: markdown, ranged over the whole line so the editor highlights the
-- sentence the answer is about.
hoverValue :: Int -> Text -> Text -> Value
hoverValue line ltext body = object
  [ "contents" .= object ["kind" .= ("markdown" :: Text), "value" .= body]
  , "range" .= object ["start" .= lspPos line 0, "end" .= lspPos line (T.length ltext)]
  ]

diagValue :: Diag -> Value
diagValue (Diag l s e sev msg) = object
  [ "range" .= object ["start" .= lspPos l s, "end" .= lspPos l e]
  , "severity" .= sev
  , "source" .= ("lips" :: Text)
  , "message" .= msg
  ]

lspPos :: Int -> Int -> Value
lspPos ln ch = object ["line" .= ln, "character" .= ch]

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

-- | The cursor position from a completion request: (line, character), both
-- 0-based. Absent on malformed params (the server then completes as if at the
-- start of the first line).
paramPos :: Value -> Maybe (Int, Int)
paramPos = parseMaybe $ withObject "p" $ \p -> do
  pos <- p .: "position"
  line <- pos .: "line"
  ch   <- pos .: "character"
  pure (line, ch)

-- | The text of the 0-based @n@th line of a document, or empty if the document
-- is missing or the line is out of range.
lineText :: Maybe Text -> Int -> Text
lineText mtext n = case mtext of
  Just t -> case drop n (T.lines t) of
    (l : _) -> l
    []      -> ""
  Nothing -> ""

-- | The column of the first non-space character on a line (its indentation
-- width). Completion begins here, so leading whitespace is preserved.
leadingCol :: Text -> Int
leadingCol = T.length . T.takeWhile isSpace

-- | Load the program's shared grammar, resolved by extension (a program
-- @ledger.backup.lips@ reads @backup/backup.grammar@ beside it), matching the
-- CLI because both call 'Lips.Identity.grammarPathIn'. Completion and
-- diagnostics are pattern-level (front half), so the grammar alone is the whole
-- answer: no world's rules and no @\<self\>@ binding are needed, and the editor
-- sees the same language whichever worlds the folder was minted into.
loadLang :: FilePath -> IO (Maybe EngineData)
loadLang path = do
  msrc <- tryReadFile (grammarPathIn (langDir path) path)
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

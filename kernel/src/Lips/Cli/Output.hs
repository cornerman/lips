{-# LANGUAGE OverloadedStrings #-}

-- | Every byte lips prints, decided here and nowhere else.
--
-- Before this module the wording lived at some forty call sites in @Main.hs@,
-- so each verb invented its own voice: one said @compiled X -> Y@ on stderr,
-- another @X: all 7 checks pass.@ on stdout, a third dumped a whole module.
-- Formatting is one concern; it gets one place.
--
-- The vocabulary is deliberately tiny -- four glyphs (@·@ a phase running, @✓@
-- one that held, @✗@ one that failed, @→@ the remedy), dim and bold, no hues.
-- All styling is dropped when stderr is not a terminal or @NO_COLOR@ is set,
-- and the words stay identical either way, so a piped run reads as the log of
-- an interactive one.
--
-- Streams: stdout carries only what a machine asked for (an @options@ answer, a
-- diagnosis table), stderr carries progress, verdicts and remedies. So a
-- pipeline keeps working while the human still sees what happened.
module Lips.Cli.Output
  ( -- * Live progress
    step
  , setState
  , note
    -- * Plain output
  , say
  , sayAnswer
  , die
    -- * The message skeleton
  , report
  , reportHead
  , tshow
    -- * Pure rendering (tested directly)
  , Style (..)
  , Verdict (..)
  , runningText
  , verdictText
  , elapsedText
  ) where

import Control.Concurrent     (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, newMVar, modifyMVar_, readMVar)
import Control.Exception      (SomeException, bracket, throwIO, try)
import Control.Monad          (forever, when)
import Data.IORef             (IORef, newIORef, readIORef, writeIORef)
import Data.Text              (Text)
import qualified Data.Text    as T
import qualified Data.Text.IO as TIO
import Data.Time.Clock.POSIX  (POSIXTime, getPOSIXTime)
import System.Exit            (exitFailure)
import System.Environment     (lookupEnv)
import System.IO              (hFlush, hIsTerminalDevice, stderr, stdout)
import System.IO.Unsafe       (unsafePerformIO)

-- | How much a terminal can do with what lips says. Resolved from stderr, since
-- that is the stream progress goes to.
data Style
  = Fancy  -- ^ a terminal: one line may be redrawn in place, styling applies
  | Plain  -- ^ a pipe, a file, or @NO_COLOR@: one line per event, no styling
  deriving (Eq, Show)

-- | How a phase ended: held, with how long it took, or failed.
data Verdict = Held Double | Failed Double
  deriving (Eq, Show)

-- | The live line, if a phase is running: its label, the state it reports (the
-- mint sets this), and when it started.
--
-- Module-level state, on purpose: a terminal has exactly one cursor, so the
-- line being redrawn is a singleton in the world lips prints to. Threading a
-- handle through every gate in @Main.hs@ would model that global resource as if
-- there could be several.
data Live = Live
  { lvLabel :: Text
  , lvState :: Text
  , lvStart :: POSIXTime
  }

liveRef :: MVar (Maybe Live)
liveRef = unsafePerformIO (newMVar Nothing)
{-# NOINLINE liveRef #-}

-- | Cached once: the tty test is a syscall and the answer cannot change within
-- a run.
styleRef :: IORef (Maybe Style)
styleRef = unsafePerformIO (newIORef Nothing)
{-# NOINLINE styleRef #-}

styleOf :: IO Style
styleOf = do
  cached <- readIORef styleRef
  case cached of
    Just s  -> pure s
    Nothing -> do
      tty <- hIsTerminalDevice stderr
      -- NO_COLOR is honored for any non-empty value, as the convention says.
      noColor <- maybe False (not . null) <$> lookupEnv "NO_COLOR"
      let s = if tty && not noColor then Fancy else Plain
      writeIORef styleRef (Just s)
      pure s

dim :: Style -> Text -> Text
dim Fancy t = "\ESC[2m" <> t <> "\ESC[0m"
dim Plain t = t

bold :: Style -> Text -> Text
bold Fancy t = "\ESC[1m" <> t <> "\ESC[0m"
bold Plain t = t

-- | A phase in progress: @· label  1.2s@, with the state the phase reports
-- appended when it has one. The clock IS the motion, so lips needs no spinner
-- alphabet on top of its four glyphs.
runningText :: Style -> Text -> Text -> Double -> Text
runningText st label state secs =
  "· " <> label <> extra <> "  " <> dim st (elapsedText secs)
  where extra = if T.null state then "" else dim st ("  " <> state)

-- | A finished phase: @✓ label (1.2s)@ or @✗ label (1.2s)@.
verdictText :: Style -> Text -> Verdict -> Text
verdictText st label v = case v of
  Held secs   -> "✓ " <> label <> "  " <> dim st ("(" <> elapsedText secs <> ")")
  Failed secs -> bold st ("✗ " <> label) <> "  " <> dim st ("(" <> elapsedText secs <> ")")

-- | A duration a human reads at a glance: tenths under ten seconds, whole
-- seconds under a minute, minutes and seconds above.
elapsedText :: Double -> Text
elapsedText secs
  | secs < 10  = T.pack (showFixed1 secs) <> "s"
  | secs < 60  = T.pack (show (round secs :: Int)) <> "s"
  | otherwise  = T.pack (show mins) <> "m " <> pad (round rest :: Int) <> "s"
  where
    mins = floor (secs / 60) :: Int
    rest = secs - fromIntegral mins * 60
    pad n = (if n < 10 then "0" else "") <> T.pack (show n)

-- | One decimal place without bringing in @printf@'s format-string machinery.
showFixed1 :: Double -> String
showFixed1 x = show (fromIntegral (round (x * 10) :: Int) / 10 :: Double)

-- | Run one phase of a verb under its own label: the line is live while the
-- action runs and becomes a verdict when it ends. An exception (including the
-- 'exitFailure' 'die' throws) prints the @✗@ form and is rethrown untouched, so
-- a failing phase can never leave a half-drawn line behind.
step :: Text -> IO a -> IO a
step label act = do
  st <- styleOf
  t0 <- getPOSIXTime
  modifyMVar_ liveRef (const (pure (Just (Live label "" t0))))
  -- Plain has no cursor to move, so the start of a phase is its own line;
  -- without it a piped log would go silent for the whole phase.
  when (st == Plain) (emit ("· " <> label))
  outcome <- bracket (startTicker st) (stopTicker st) (const (try act))
  case outcome of
    Right a -> finish st True >> pure a
    Left e  -> finish st False >> throwIO (e :: SomeException)

-- | Close the running phase with its verdict -- unless 'die' already closed it,
-- which is how a failure reads in the order it happened: the @✗@ line first,
-- then the report explaining it. Whoever gets there first prints the verdict,
-- and taking the live line is what says it has been printed.
finish :: Style -> Bool -> IO ()
finish st ok = do
  live <- readMVar liveRef
  case live of
    Nothing -> pure ()
    Just l  -> do
      clear
      modifyMVar_ liveRef (const (pure Nothing))
      now <- getPOSIXTime
      let secs = realToFrac (now - lvStart l)
      emit (verdictText st (lvLabel l) (if ok then Held secs else Failed secs))

-- | Report what the running phase is doing right now (the mint's state: waiting
-- on the model, looking an option up, writing the engine). Ignored in 'Plain',
-- where there is no line to update.
setState :: Text -> IO ()
setState s = modifyMVar_ liveRef (pure . fmap (\l -> l { lvState = s }))

-- | A detail line under the running phase: dim, indented, one fact per line
-- (a tool call the mint made, an artifact being built). Printed above the live
-- line, which is redrawn after it.
note :: Text -> IO ()
note t = do
  st <- styleOf
  emit ("  " <> dim st t)

-- | A message that is not a phase: a report, a remedy, a list of commands.
-- Multi-line text is fine; it goes to stderr, above the live line.
say :: Text -> IO ()
say = emit

-- | What the caller actually asked for, on stdout: an @options@ answer, a
-- diagnosis table. Never decorated, so it stays pipeable.
sayAnswer :: Text -> IO ()
sayAnswer t = do
  clear
  TIO.putStr t
  hFlush stdout
  redraw

-- | Print a report and stop with a failing exit code. The phase this happened
-- in (if any) is closed FIRST, so the @✗@ line stands above the report that
-- explains it rather than below it.
die :: Text -> IO a
die msg = do
  st <- styleOf
  finish st False
  say msg
  exitFailure

-- | The standard message skeleton: a plain headline, optional indented detail
-- lines, and a final "→" action. Every error lips prints is built from it, so
-- the product speaks with one voice.
report :: Text -> [Text] -> Text -> Text
report headline details action =
  T.intercalate "\n" $ [headline] ++ detail ++ ["", action]
  where detail = if null details then [] else "" : map ("  " <>) details

-- | Same skeleton without the action line, for a diagnosis another command
-- wraps with its own action.
reportHead :: Text -> [Text] -> Text
reportHead headline details =
  T.intercalate "\n" $ [headline] ++ (if null details then [] else "" : map ("  " <>) details)

-- | Write a finished line to stderr without disturbing the live line: erase it,
-- print, draw it again.
emit :: Text -> IO ()
emit t = do
  clear
  TIO.hPutStrLn stderr t
  hFlush stderr
  redraw

-- | Erase the live line, if one is drawn.
clear :: IO ()
clear = do
  st <- styleOf
  when (st == Fancy) $ do
    live <- readMVar liveRef
    case live of
      Nothing -> pure ()
      Just _  -> TIO.hPutStr stderr "\r\ESC[K" >> hFlush stderr

-- | Draw the live line at the current time.
redraw :: IO ()
redraw = do
  st <- styleOf
  when (st == Fancy) $ do
    live <- readMVar liveRef
    case live of
      Nothing -> pure ()
      Just l  -> do
        now <- getPOSIXTime
        TIO.hPutStr stderr ("\r\ESC[K" <> runningText st (lvLabel l) (lvState l)
                              (realToFrac (now - lvStart l)))
        hFlush stderr

-- | The clock that makes the live line move. Ten frames a second: fast enough
-- to read as alive, slow enough to cost nothing.
startTicker :: Style -> IO (Maybe ThreadId)
startTicker Plain = pure Nothing
startTicker Fancy = Just <$> forkIO (forever (redraw >> threadDelay 100000))

stopTicker :: Style -> Maybe ThreadId -> IO ()
stopTicker _ Nothing    = pure ()
stopTicker _ (Just tid) = killThread tid >> clear

-- | @show@ into 'Text'. Every message naming a line number or a count goes
-- through it, so it sits with the printing instead of being redefined wherever
-- a message is built.
tshow :: Show a => a -> Text
tshow = T.pack . show

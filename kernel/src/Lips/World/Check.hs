{-# LANGUAGE OverloadedStrings #-}

-- | Does a world file's Nix parse? 'Lips.World.parseWorld' is strict about
-- STRUCTURE (an unknown header, an unknown slot, a newer format all refuse
-- naming the offender), but the Nix-bearing slots are pasted VERBATIM into the
-- compiled flake and into the schema expression, so a typo in a hand-written
-- world file surfaces at nix naming the GENERATED @flake.nix@ -- a file the
-- human never wrote. The built-in worlds are covered by the suite and the flake
-- checks; a house world, which is the feature's whole point, was covered by
-- nothing until its first compile.
--
-- So @lips world --check \<name\>@ hands each Nix-bearing slot to nix's own
-- parser (syntax only, offline, nothing evaluated and nothing fetched). Nix's
-- parser is the authority on Nix syntax; lips owns no second one.
--
-- Deliberately NOT at compile time: compile is offline-and-deterministic over a
-- hash-pinned copy that already compiled once, so a per-compile parse of an
-- unchanged file buys nothing. The seam is authoring time, once.
module Lips.World.Check
  ( NixSlice (..)
  , SlotFault (..)
  , nixSlices
  , checkNixSlots
  ) where

import           Control.Exception  (IOException, try)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Exit        (ExitCode (..))
import           System.FilePath    (takeFileName, (</>))
import           System.Process     (readProcessWithExitCode)

import           Lips.Stage         (withTempDir)
import           Lips.World         (slotMarker)

-- | One slot, as the text nix is asked to parse: the slot's own lines, wrapped
-- into whatever standalone expression its embedding makes them part of.
data NixSlice = NixSlice
  { nsSlot :: Text  -- ^ which slot, for the message when it does not parse
  , nsText :: Text  -- ^ what nix parses, line-aligned with the world file
  }
  deriving (Eq, Show)

-- | A slot that did not parse, and nix's own words about it.
data SlotFault = SlotFault
  { sfSlot :: Text
  , sfNix  :: Text
  }
  deriving (Eq, Show)

-- | What every slice opens with. @nix-instantiate --parse@ also resolves
-- variables statically, and a slot legitimately reads names its surroundings
-- bind (@nixpkgs@, @pkgsFor@, the world's own @builds@), which this file cannot
-- see. Under a @with@ those lookups become dynamic, so an unbound name is no
-- longer an error while a syntax error still is -- which is exactly the question
-- being asked. Whether the names EXIST is answered by the compiled flake, at
-- eval, where the scope is real.
withScope :: Text
withScope = "with {}; "

-- | Which slots hold Nix, and what each one is a FRAGMENT of. The wrappers
-- mirror the embeddings exactly: 'Lips.Nix.Flake.flakeText' puts @inputs@ in
-- the flake's own attribute set, @builds@ in a @let@, @packages@ in an attrset
-- of derivations, and @apps@\/@devShells@ as the body of
-- @forSystems (system: ...)@; 'Lips.Schema.ensureOptionSchema' takes @schema@
-- as a whole expression. A slot missing from this table holds prose (@preamble@)
-- or lips's own line syntax (@rungs@), and nix would refuse it for saying so.
nixContexts :: [(Text, (Text, Text))]
nixContexts =
  [ ("schema",    ("", ""))
  , ("inputs",    ("{", "}"))
  , ("builds",    ("let", "in null"))
  , ("packages",  ("{", "}"))
  , ("apps",      ("", ""))
  , ("devShells", ("", ""))
  ]

-- | Every Nix-bearing slot of a world file, as text nix can parse on its own.
--
-- Line-aligned on purpose: slot line k lands on line k OF THE FILE, every other
-- line blanked, and the wrapper riding the marker lines that already fence the
-- slot. So nix's @file:line:column@ and its source excerpt point at the line the
-- human wrote, and the caller only has to swap the scratch path for the real
-- one. (The excerpt shows the wrapper where the fence line is, since that is
-- the one line the slice replaces; every line of the slot itself is verbatim.)
-- A slot holding nothing is skipped: an empty file is a parse error saying
-- nothing about the world.
nixSlices :: Text -> [NixSlice]
nixSlices raw =
  [ NixSlice slot (T.unlines (slice open close i j))
  | (slot, i, j) <- regions
  , Just (open, close) <- [lookup slot nixContexts]
  , any (not . blank) (bodyOf i j)
  ]
  where
    ls = T.lines raw
    total = length ls
    blank = T.null . T.strip
    markers = [ (name, i) | (i, l) <- zip [0 ..] ls, Just name <- [slotMarker l] ]
    -- Each marker owns the lines up to the next marker, or to the end of file.
    regions = [ (name, i, minimum ([ j | (_, j) <- markers, j > i ] ++ [total]))
              | (name, i) <- markers ]
    bodyOf i j = [ l | (k, l) <- zip [0 ..] ls, k > i, k < j ]
    slice open close i j =
      [ pick k l | (k, l) <- zip [0 ..] ls ]
        -- A last slot has no marker line after it to carry the closer.
        ++ [ close | j >= total, not (T.null close) ]
      where
        pick k l | k == i           = withScope <> open
                 | k == j           = close
                 | k > i && k < j   = l
                 | otherwise        = ""

-- | Parse every Nix-bearing slot with @nix-instantiate --parse@. @display@ is
-- the path a message names the file by (the world file's own path, or
-- @\<name\>.world@ for a world lips ships, which has no path); nix's words come
-- back with the scratch file it actually saw replaced by that name, which is
-- sound because the scratch file's lines ARE the world file's lines.
--
-- 'Left' means nix could not be run at all: an unverifiable world is not
-- reported as sound (deduce-or-fail), so the caller says to install nix.
checkNixSlots :: FilePath -> Text -> IO (Either Text [SlotFault])
checkNixSlots display raw = withTempDir $ \dir -> go (dir </> takeFileName display) (nixSlices raw)
  where
    go _ [] = pure (Right [])
    go scratch (s : ss) = do
      TIO.writeFile scratch (nsText s)
      res <- try (readProcessWithExitCode "nix-instantiate" ["--parse", scratch] "")
      case res of
        Left e -> pure (Left (T.pack (show (e :: IOException))))
        Right (ExitSuccess, _, _) -> go scratch ss
        Right (ExitFailure _, _, err) -> do
          let fault = SlotFault (nsSlot s)
                        (T.strip (T.replace (T.pack scratch) (T.pack display) (T.pack err)))
          fmap (fault :) <$> go scratch ss

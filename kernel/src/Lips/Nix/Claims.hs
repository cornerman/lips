{-# LANGUAGE OverloadedStrings #-}

-- | @claims.nix@: the program's stated observables, as buildable experiments.
--
-- Rendered beside @artifact.nix@ from the SAME ground base, so what @check@ runs
-- and what the module contains cannot disagree. Two shapes, chosen by the
-- claim's derived place and nothing else:
--
--   * 'PlaceDerivation' -- @runCommand@: run the command in the nix sandbox,
--     capture stdout and status, judge. No boot, no KVM, no network.
--   * 'PlaceMachine' -- @nixosTest@: boot the realized module and run the
--     command inside the machine, then judge the same way.
--
-- Both judge with 'comparisonPy', so exactness is implemented once and a
-- sandbox claim and a machine claim cannot drift apart.
--
-- Every value a program states reaches the file as a NIX STRING rendered by the
-- kernel's own 'renderValue' -- the escaping that already stops a program value
-- from opening an interpolation. The sandbox builder receives its data as
-- derivation ATTRIBUTES (environment variables), not spliced into the script, so
-- no stated byte is ever read as shell.
module Lips.Nix.Claims (claimsFile) where

import           Data.List (sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Claim        (Claim (..), ClaimPlace (..), comparisonPy)
import Lips.Kernel.Engine.Value (Piece (..), Value (..), renderRealized, renderValue)

-- | The file, or 'Nothing' when the program states no claims (so a claim-free
-- compile writes nothing and its output stays byte-identical to before).
-- @hasArtifacts@ decides whether the artifact bindings are in scope: a program
-- can state a machine claim without building anything, and importing an
-- @artifact.nix@ that was never written would fail at evaluation.
claimsFile :: Bool -> [Claim] -> Maybe Text
claimsFile _ [] = Nothing
claimsFile hasArtifacts cs = Just $ T.unlines $
  [ "# lips-realized claims. Generated from a ground decision base; do not edit."
  , "{ pkgs }:"
  , "let"
  ] ++ artifactLet ++
  [ "in {"
  ] ++ concatMap entry (sortOn clId cs) ++ [ "}" ]
  where
    artifactLet
      | hasArtifacts = [ "  artifact = import ./artifact.nix { inherit pkgs; };" ]
      -- A `let` with no bindings is legal Nix, so an artifact-free program needs
      -- no separate rendering path.
      | otherwise    = []

entry :: Claim -> [Text]
entry c = case clPlace c of
  PlaceDerivation ->
    [ "  " <> clId c <> " = pkgs.runCommand \"claim-" <> clId c <> "\""
    , "    { nativeBuildInputs = [ pkgs.python3 ];"
    -- The command keeps its ${artifact.<name>} interpolation live; everything
    -- else the program stated is escaped by the kernel's own renderer.
    , "      command = " <> renderRealized (clRun c) <> ";"
    , "      stdinText = " <> nixStr (maybe "" id (clStdin c)) <> ";"
    , "      judge = " <> nixStr (judgePy c) <> ";"
    , "    }"
    , "    ''"
    , "      printf '%s' \"$stdinText\" > stdin"
    -- The command's own failure is the observation, not the builder's: without
    -- `set +e` a non-zero exit would kill the build before the claim could judge
    -- it, and a claim stating exit 2 could never hold.
    , "      set +e"
    , "      sh -c \"$command\" < stdin > out 2> err"
    , "      echo $? > code"
    , "      set -e"
    , "      printf '%s' \"$judge\" > judge.py"
    , "      python3 judge.py"
    , "      touch $out"
    , "    '';"
    ]
  PlaceMachine ->
    -- testers.nixosTest, not the bare pkgs.nixosTest: the latter is an alias
    -- nixpkgs now refuses outright ("renamed to/replaced by testers.nixosTest"),
    -- so a machine claim rendered the old way fails at evaluation, before it ever
    -- boots.
    [ "  " <> clId c <> " = pkgs.testers.nixosTest {"
    , "    name = \"claim-" <> clId c <> "\";"
    , "    nodes.machine = { imports = [ ./default.nix ]; };"
    , "    testScript = " <> machineScript c <> ";"
    , "  };"
    ]

-- | The sandbox judge: read what the command did, then apply the shared
-- comparison.
judgePy :: Claim -> Text
judgePy c = T.unlines $
  [ "out = open('out').read()"
  , "code = int(open('code').read().strip())"
  ] ++ comparisonPy c

-- | The machine script: a nix string whose ONLY live interpolation is the
-- command, so a stated byte cannot open one.
--
-- Built by rendering the whole python text with a marker where the command
-- belongs (the kernel's escaping applies to all of it), then replacing the
-- marker with the command's own rendered pieces. The marker is ordinary
-- identifier text, so escaping leaves it untouched.
--
-- stderr goes to @\/dev\/null@ inside the machine, so the observed bytes are the
-- command's stdout exactly as in the sandbox: the two places must judge the same
-- thing, and the test driver otherwise hands back whatever it captured.
machineScript :: Claim -> Text
machineScript c = T.replace marker (interpolatedBody (clRun c)) (nixStr script)
  where
    marker = "@LIPS_CMD@"
    script = T.unlines $
      [ "machine.wait_for_unit(\"multi-user.target\")"
      , "cmd = r'''" <> marker <> " 2>/dev/null'''"
      ] ++ feed ++ comparisonPy c
    feed = case clStdin c of
      Nothing -> [ "code, out = machine.execute(cmd)" ]
      Just s  ->
        [ "stdin_text = " <> pyLiteral s
        , "code, out = machine.execute(\"cat <<'LIPS_STDIN' | \" + cmd + \"\\n\""
            <> " + stdin_text + \"\\nLIPS_STDIN\\n\")"
        ]

-- | A python single-quoted literal for text the program stated. Reuses the same
-- escaping rule 'comparisonPy' applies to a stated value.
pyLiteral :: Text -> Text
pyLiteral t = "'" <> T.concatMap esc t <> "'"
  where
    esc '\\' = "\\\\"
    esc '\'' = "\\'"
    esc '\n' = "\\n"
    esc ch   = T.singleton ch

-- | Arbitrary text as a Nix string literal, escaped by the kernel's own
-- renderer -- the one that already stops a program value from opening an
-- interpolation. One escaper for the whole system, rather than a second one
-- here that could disagree with it.
nixStr :: Text -> Text
nixStr t = renderValue (VStr [PLit t])

-- | The INSIDE of a rendered Nix string: the same escaped pieces, without the
-- surrounding quotes, so it can be spliced into a larger literal with its
-- @${artifact.\<name\>}@ interpolations still live.
interpolatedBody :: Value -> Text
interpolatedBody v = case T.stripPrefix "\"" (renderRealized v) >>= T.stripSuffix "\"" of
  Just body -> body
  -- A claim's command is a string by construction (the grammar's run section
  -- takes a value, and a non-string one is refused when the claim is read), so
  -- this branch is unreachable; rendering it verbatim keeps the function total
  -- rather than throwing inside a pure renderer.
  Nothing   -> renderRealized v

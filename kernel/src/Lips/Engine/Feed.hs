{-# LANGUAGE OverloadedStrings #-}

-- | An example engine: the @feed@ language, hand-written (spec v2, section
-- 12.4, \"one engine, reference compiler\"). A real engine is what @generate@
-- (the AI step) produces; this one is written by hand to exercise the
-- deterministic pipeline end to end. It mirrors a slice of the feed
-- meta-decision base from the language sketch: two demands and three
-- obligation-to-mechanism mappings that realize a ledger ingest service.
--
-- Every rule rewrites one input decision into ground NixOS option assignments,
-- so a satisfied feed program refines to a module with nothing left over.
module Lips.Engine.Feed
  ( rules
  , demands
  , vocabulary
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Base     (Base, toList)
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Refine

-- | The (kind, subject) targets this engine can refine and demands. @generate@
-- shows this to the model so the patterns it mints land on subjects the engine
-- actually maps. In the full system the engine is generated too and this hint
-- is intrinsic; here the engine is hand-written, so we state its vocabulary.
vocabulary :: [Text]
vocabulary =
  [ "fact feed.source     -- where files arrive (a path)"
  , "fact feed.cadence    -- how often the feed delivers (a schedule word)"
  , "oblige feed.ingest   -- the row-to-record obligation"
  ]

-- | The feed language's demands: an ingest needs to know where files arrive
-- and how often. An unmet demand becomes an open question, verbatim.
demands :: [Demand]
demands =
  [ Demand "feed-source"  "where do the files arrive?"    (hasSubject ["feed", "source"])
  , Demand "feed-cadence" "how often does the feed deliver?" (hasSubject ["feed", "cadence"])
  ]

hasSubject :: [Text] -> Base -> Bool
hasSubject segs = any ((== Subject segs) . dSubject) . toList

-- | The feed language's obligation-to-mechanism mappings.
rules :: [Rule]
rules =
  [ ruleFor "map-ingest"  Oblige ["feed", "ingest"]  ingestMechanism
  , ruleFor "map-cadence" Fact   ["feed", "cadence"] cadenceMechanism
  , ruleFor "map-source"  Fact   ["feed", "source"]  sourceMechanism
  ]

-- | Build a rule that fires on one kind at one subject, delegating the option
-- assignments it emits to a mechanism function of the matched assertion.
ruleFor :: Text -> Kind -> [Text] -> (Text -> [Decision]) -> Rule
ruleFor rid kind segs mechanism =
  Rule
    { rId      = RuleId rid
    , rMatches = \d -> dKind d == kind && dSubject d == Subject segs
    , rRewrite = \d -> mechanism (assertionText d)
    }
  where
    assertionText d = case dAssertion d of Assertion a -> a

-- | An ingest obligation realizes as an enabled, boot-wired systemd service.
ingestMechanism :: Text -> [Decision]
ingestMechanism _ =
  [ opt ["systemd", "services", "ledger-ingest", "enable"] "true"
  , opt ["systemd", "services", "ledger-ingest", "wantedBy"] "[ \"multi-user.target\" ]"
  ]

-- | The feed cadence realizes as the ingest timer's schedule.
cadenceMechanism :: Text -> [Decision]
cadenceMechanism cadence =
  [ opt ["systemd", "timers", "ledger-ingest", "timerConfig", "OnCalendar"] (nixStr cadence) ]

-- | The source location realizes as an environment variable for the service.
sourceMechanism :: Text -> [Decision]
sourceMechanism loc =
  [ opt ["systemd", "services", "ledger-ingest", "environment", "LEDGER_INBOX"] (nixStr loc) ]

-- | A ground option-assignment decision. Its id and provenance are overwritten
-- by the refiner, so only subject and assertion matter here.
opt :: [Text] -> Text -> Decision
opt segs rhs =
  Decision
    { dId        = DecisionId ""
    , dSubject   = Subject segs
    , dKind      = Meta
    , dAssertion = Assertion rhs
    , dStrength  = Stated
    , dProv      = FromSource (SourceLoc "" 0)
    , dRationale = Nothing
    }

-- | Render a plain value as a Nix string literal, escaping as needed.
nixStr :: Text -> Text
nixStr s = "\"" <> T.concatMap esc s <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = T.singleton c

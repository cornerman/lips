-- | The atom of lips: a decision, and the vocabulary that identifies and
-- ranks decisions. Everything in lips is made of these (spec v2, section 2).
--
-- Design choices fixed here answer open questions from the design doc
-- (section 11), kept minimal and documented:
--
--   * 'Subject' is an attribute path. It is the /merge key/: two decisions
--     compete only when they share a subject. Distinct subjects coexist, so
--     many concepts and obligations live side by side without interference.
--   * 'Strength' is a total order @Default < Stated < Law@. This promotes the
--     NixOS priority mechanism to kernel physics (spec section 2, merge). We
--     defer any cross-language strength; it is not needed yet.
module Lips.Kernel.Decision
  ( Subject (..)
  , DecisionId (..)
  , RuleId (..)
  , Strength (..)
  , SourceLoc (..)
  , Provenance (..)
  , Kind (..)
  , Assertion (..)
  , Decision (..)
  ) where

import Data.Text (Text)

-- | An attribute path, e.g. @["account","balance"]@. The key decisions merge
-- on: same subject means the decisions are about the same thing and compete.
newtype Subject = Subject [Text]
  deriving (Eq, Ord, Show)

-- | Stable identity of a decision within a base. Human decisions get ids from
-- the reader; derived decisions get fresh ids from the refiner.
newtype DecisionId = DecisionId Text
  deriving (Eq, Ord, Show)

-- | Identity of a refinement rule (a mapping from a language's engine).
newtype RuleId = RuleId Text
  deriving (Eq, Ord, Show)

-- | Merge precedence. A stronger decision overrides a weaker one about the
-- same subject; equal strength with differing assertions is a conflict, never
-- a silent pick. @Default@ is what the System asserts; @Stated@ is what a
-- human writes; @Law@ is an inviolable assertion.
data Strength = Default | Stated | Law
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Where a human decision came from, for line-anchored provenance.
data SourceLoc = SourceLoc
  { locFile :: Text
  , locLine :: Int
  }
  deriving (Eq, Ord, Show)

-- | Every decision knows its origin. Derived decisions link to the decisions
-- and the rule that produced them, so any chain is walkable to the metal
-- (spec section 2, provenance). The refiner stamps this; rule authors cannot
-- forge or omit it.
data Provenance
  = FromSource SourceLoc
  | Derived [DecisionId] RuleId
  deriving (Eq, Ord, Show)

-- | The closed set of kernel kinds (spec section 3). The kernel does not use
-- 'Kind' to drive merge; it is carried for higher layers and for readers.
data Kind
  = Concept
  | Fact
  | Oblige
  | Forbid
  | Allow
  | Invariant
  | View
  | Assume
  | Steer
  | Glue
  | Meta
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The content a decision asserts about its subject. The kernel treats it
-- opaquely, by equality only: two decisions about one subject /agree/ when
-- their assertions are equal and /conflict/ when they differ.
newtype Assertion = Assertion Text
  deriving (Eq, Ord, Show)

-- | The atom. A tuple of subject, assertion, scope (carried in the subject
-- path for now), strength, provenance, and rationale (spec section 2).
data Decision = Decision
  { dId        :: DecisionId
  , dSubject   :: Subject
  , dKind      :: Kind
  , dAssertion :: Assertion
  , dStrength  :: Strength
  , dProv      :: Provenance
  , dRationale :: Maybe Text
  }
  deriving (Eq, Ord, Show)

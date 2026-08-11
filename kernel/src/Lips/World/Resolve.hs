{-# LANGUAGE OverloadedStrings #-}

-- | How a world NAME becomes a world: a file beside the program, else one lips
-- ships. Local first, so a house world can exist at all; built-in names
-- reserved, so @nixos@ always means what lips ships and a reader never has to
-- ask which one a program meant.
module Lips.World.Resolve
  ( resolveWorld
  , resolveWorldFrom
  , localWorldNames
  , builtinNames
  ) where

import           Control.Exception  (IOException, try)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (doesFileExist, listDirectory)
import           System.FilePath    (dropExtension, takeExtension)

import           Lips.Identity      (worldPathIn)
import           Lips.World         (World (..), parseWorld)
import           Lips.World.Builtin (builtinWorlds)

-- | The worlds lips ships, by name. Reserved: a local file may not take one.
builtinNames :: [Text]
builtinNames = map fst builtinWorlds

-- | Resolve one name against a directory (the program's own, or @--worlds@).
-- A local @\<name\>.world@ wins, unless the name is a built-in's -- then it is
-- refused rather than shadowed, so @nixos@ names one thing everywhere.
resolveWorld :: FilePath -> Maybe FilePath -> Text -> IO (Either Text World)
resolveWorld base override name = fmap (fmap fst) (resolveWorldFrom base override name)

-- | Resolution, plus WHERE the world came from: the file the human owns, or
-- 'Nothing' for one lips ships. A message about a world file has to name that
-- file, and resolution is the only thing that knows which one won -- deciding it
-- a second time at a call site would be a second answer to the same question.
resolveWorldFrom :: FilePath -> Maybe FilePath -> Text -> IO (Either Text (World, Maybe FilePath))
resolveWorldFrom base override name = do
  let dir = maybe base id override
      path = worldPathIn dir name
  there <- doesFileExist path
  case (there, name `elem` builtinNames) of
    (True, True) -> pure (Left
      ("the name " <> name <> " is one lips ships, so " <> T.pack path
        <> " may not take it \8594 call yours house-" <> name <> ", or delete that file."))
    (True, False) -> do
      raw <- try (TIO.readFile path) :: IO (Either IOException Text)
      pure $ case raw of
        Left e -> Left ("lips can't read the world file " <> T.pack path <> ": " <> T.pack (show e))
        Right t -> case parseWorld t of
          Left why -> Left (T.pack path <> ": " <> why)
          -- The file's own header must agree with the name it was found under,
          -- or the record would pin a name nothing on disk answers to.
          Right w -> fmap (\x -> (x, Just path)) (checkName path name w)
    (False, _) -> case lookup name builtinWorlds of
      Just t  -> pure (either (Left . (("the world lips ships for " <> name <> " is broken: ") <>))
                              (\w -> Right (w, Nothing))
                              (parseWorld t))
      Nothing -> pure (Left
        ("lips doesn't know the world " <> name <> ": there is no " <> T.pack path
          <> ", and the worlds lips ships are " <> T.intercalate ", " builtinNames <> "."))

-- | The worlds a directory holds files for, by name. Every @\<name\>.world@ in
-- it, INCLUDING one taking a name lips ships: that file is a defect resolution
-- refuses to read, and a caller listing what is here must be able to see it.
localWorldNames :: FilePath -> IO [Text]
localWorldNames dir = do
  entries <- listDirectory dir
  pure [ T.pack (dropExtension f) | f <- entries, takeExtension f == ".world" ]

checkName :: FilePath -> Text -> World -> Either Text World
checkName path name w
  | wName w == name = Right w
  | otherwise = Left (T.pack path <> " declares world: " <> wName w <> ", not " <> name
                       <> " \8594 name the file after the world it declares.")

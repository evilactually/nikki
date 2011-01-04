
-- This is a replacment for cabal's autogenerated Paths_nikki.hs
-- Use this instead to find data files.
-- Needed for deployment in one folder

module Base.Paths (getDataFileName, getDataFiles) where


import Data.List

import System.Info
import System.FilePath
import System.Directory
import System.Environment.FindBin

import Utils

import Base.Monad
import Base.Configuration


getDataFileName :: FilePath -> M FilePath
getDataFileName p = do
    inPlace <- asks run_in_place
    if inPlace then
        return (".." </> "data" </> p)
      else do
        progPath <- io getProgPath
        case os of
            "linux" ->
                return (progPath </> "data" </> p)
            "mingw32" ->
                -- works if the application is deployed in one folder
                return (progPath </> "data" </> p)
            "darwin" ->
                -- works if the application is bundled in an app
                return (progPath </> ".." </> "Resources" </> p)
            x -> error ("unsupported os: " ++ os)

-- | returns unhidden files with a given extension in a given data directory.
getDataFiles :: FilePath -> (Maybe String) -> M [FilePath]
getDataFiles path_ extension = do
    path <- getDataFileName path_
    map (path </>) <$> io (getFiles path extension)

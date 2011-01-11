{-# language DeriveDataTypeable, ViewPatterns, ScopedTypeVariables #-}

module Main where


import Control.Monad

import System.Console.CmdArgs
import System.FilePath
import System.Directory
import System.Exit
import System.Process
import System.IO
import System.IO.Temp

import Distribution.AutoUpdate.Paths
import Distribution.AutoUpdate.Zip

import Version

import Utils hiding (ignore)


data Configuration = Configuration {
    localDeployedFolder :: FilePath,
    remoteRepo :: String
  }
    deriving (Show, Data, Typeable)

getConfiguration :: IO Configuration
getConfiguration = cmdArgs options

options :: Configuration
options =
    Configuration {
        localDeployedFolder = def
            &= argPos 0
            &= typ "DEPLOYED_DIRECTORY"

        , remoteRepo = def
            &= argPos 1
            &= typ "RELEASE_REPO"
      }
    &= program "Release.hs"
    &= summary ("script to push a deployed folder of \"Nikki and the Robots\" to a server for the auto-updating system to fetch.")
    &= helpArg [explicit, name "h", name "help", groupname "Common flags"]
    &= versionArg [ignore]
    &= details (
        "Nikki and the Robots is a 2D platformer from Joyride Laboratories." :
        "http://www.joyridelabs.de/" :
        "" :
        "DEPLOYED_DIRECTORY - local directory where the version of the game is deployed that should be uploaded." :
        "RELEASE_REPO - ssh style repo where the game should be uploaded to." :
        [])


main = withTempDirectory "." "nikki-release" $ \ (normalise -> tmpDir) -> do
    hSetBuffering stdout NoBuffering
    config <- getConfiguration
    putStrLn ("remote repository: " ++ remoteRepo config)
    checkNewerVersion config
    let zipName = "nikki-" ++ showVersion nikkiVersion <.> "zip"
    createDirectoryIfMissing True (tmpDir </> osRepoPath)
    zipArchive putStrLn (tmpDir </> osRepoPath </> zipName) (localDeployedFolder config)
    trySystem ("scp -r " ++ tmpDir </> "*" ++ " " ++ remoteRepo config)

    -- updating the version (making sure the version file gets updated after the zip file)
    writeFile (tmpDir </> osRepoPath </> "version") (showVersion nikkiVersion ++ "\n")
    trySystem ("scp " ++ tmpDir </> osRepoPath </> "version" ++ " " ++ remoteRepo config <//> unixRepoPath)

-- | checks if the current version was already uploaded (exits in case it was).
checkNewerVersion :: Configuration -> IO ()
checkNewerVersion config = withTempDirectory "." "serverVersion" $ \ tempDir -> do
    system ("scp " ++
        remoteRepo config <//> unixRepoPath <//> "version" ++ " " ++
        tempDir)
    let versionFile = (tempDir </> "version")
    exists <- doesFileExist versionFile
    if not exists then do
        -- couldn't download version file
        putStrLn "warning: couldn't download version file, repo seems to be empty."
        putStrLn "press Ctrl+C to abort."
        getLine
        return ()
      else do
        eServerVersion :: Either String Version <- parseVersion <$> readFile versionFile
        case eServerVersion of
            (Left m) -> do
                putStrLn ("error downloading remote version: " ++ m)
                putStrLn "uploading anyway"
            (Right serverVersion) -> do
                when (nikkiVersion <= serverVersion) $
                    error $ unlines ("This version was already uploaded." :
                                    ("local version: " ++ showVersion nikkiVersion) :
                                    ("remote version: " ++ showVersion serverVersion) :
                                    [])

-- | just for development
trySystem_ = putStrLn


module Distribution.Setup.Darwin where


import Data.List
import Data.Char

import Control.Applicative
import Control.Monad
import Control.Exception

import System.Directory
import System.FilePath
import System.Info
import System.Process

import Distribution.PackageDescription
import Distribution.Simple
import Distribution.Simple.Setup
import Distribution.Simple.LocalBuildInfo
import Distribution.MacOSX

import Utils


macUserHooks = 
    simpleUserHooks{postBuild = macPostBuild}

macResourcesDir = "resources"

macPostBuild :: Args -> BuildFlags -> PackageDescription -> LocalBuildInfo -> IO ()
macPostBuild args buildFlags packageDescription localBuildInfo =
    withTemporaryDirectoryCopy "../data" macResourcesDir $ do
        -- fiddle in the Qt nib directory
        qtLibDir <- trim <$> readProcess "qmake" ["-query", "QT_INSTALL_LIBS"] ""
        qtNibDir <- lookupQtNibDir qtLibDir
        copyDirectory qtNibDir (macResourcesDir </> "qt_menu.nib")

        -- build the app
        resources <- map (macResourcesDir </>) <$> getFilesRecursive macResourcesDir
        appBundleBuildHook [macApp resources] args buildFlags packageDescription localBuildInfo
        
        let bundle = "dist/build/nikki.app"
            bundleExecutableDir = bundle </> "Contents/MacOS"
            bundleResourcesDir = bundle </> "Contents/Resources"

        -- stripping of binaries
        mapM_ (strip . (bundleExecutableDir </>)) ("nikki" : "core" : [])
        writeFile (bundle </> "yes_nikki_is_deployed") ""
        copyDirectory bundle "./nikki.app"

-- | deployment on a mac
macApp :: [FilePath] -> MacApp
macApp resourceFiles = MacApp {
    -- use core executable for now (this results in correct dependency chasing,
    -- but the game gets started with the wrong executable, restarting after updates
    -- will not work)
    appName = "nikki",
    otherCompiledBins = "core" : [],
    appIcon = Just (macResourcesDir </> "png/icon.icns"),
    appPlist = Nothing,
    resources = resourceFiles,
    otherBins = [],
    appDeps = FilterDeps filterDeps
  }

-- | Decide, which dependencies to include
filterDeps :: FilePath -> Bool
filterDeps dep =
    libName dep `elem` deployedLibs
  where
    libName = takeBaseName >>> takeWhile (/= '.')

-- | list of libs that have to be deployed
deployedLibs :: [String]
deployedLibs =
    "QtOpenGL" :
    "QtGui" :
    "QtCore" :
    "libsndfile" :
    "libzip" :
    "libFLAC" :
    "libvorbisenc" :
    "libvorbis" :
    "libogg" :
    []

-- | searches the qt_menu.nib in both standard locations for
-- qt being installed via macports or binary distribution
lookupQtNibDir :: FilePath -> IO FilePath
lookupQtNibDir qtLibDir = do
    mPath <- searchInPaths qtMenuNibDirs "qt_menu.nib"
    return $ case mPath of
        Nothing -> error ("qt_menu.nib not found, looked in: \n" ++ unlines qtMenuNibDirs)
        Just x -> x
  where
    qtMenuNibDirs = map (qtLibDir </>) (
        "QtGui.framework/Versions/4/Resources" :
        "resources" :
        [])


-- * utils

-- | copy a directory, perform a given action, then delete the copy
withTemporaryDirectoryCopy :: FilePath -> FilePath -> IO a -> IO a
withTemporaryDirectoryCopy original copy action = do
    eDir <- doesDirectoryExist copy
    eFile <- doesFileExist copy
    when (eDir || eFile) $
        fail ("directory (or file?) already exists: " ++ copy)
    (copyDirectory original copy >> action) `finally` removeDirectoryRecursive copy

-- | remove surrounding whitespaces
trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | searches for a file or directory in a given list of paths
searchInPaths :: [FilePath] -> FilePath -> IO (Maybe FilePath)
searchInPaths [] _ = return Nothing
searchInPaths (a : r) file = do
    let candidate = a </> file
    fileExists <- doesFileExist candidate
    dirExists <- doesDirectoryExist candidate
    if fileExists || dirExists then
        return $ Just candidate
      else
        searchInPaths r file

-- | stripping an executable
strip :: FilePath -> IO ()
strip exe =
    trySystem ("strip " ++ exe)

{-# language NamedFieldPuns #-}

module Editor.MainLoop (editorLoop) where


import Data.Set (Set, empty, toList, insert, delete)
import Data.Indexable (modifyByIndex)
import Data.SelectTree

import Control.Concurrent
import Control.Monad.State

import Graphics.Qt

import Utils

import Base.Types
import Base.Events
import Base.Grounds

import Object

import Editor.Scene
import Editor.Scene.Types

import Top.Application hiding (selected)
import Top.Pickle


type MM o = StateT (EditorScene Sort_) IO o


updateSceneMVar :: Application -> MVar (EditorScene Sort_) -> MM ()
updateSceneMVar app mvar = do
    s <- get
    liftIO $ do
        swapMVar mvar s
        updateAppWidget $ window app


-- * menus and states

editorLoop :: Application -> AppState -> MVar (EditorScene Sort_)
    -> EditorScene Sort_ -> AppState
editorLoop app parent sceneMVar scene = AppState $ do
    setDrawingCallbackAppWidget (window app) (Just $ render sceneMVar)
    evalStateT worker scene
  where
    worker :: MM AppState
    worker = do
        event <- liftIO $ waitForAppEvent $ keyPoller app
        if event == Press StartButton then do
            s <- get
            return $ editorMenu app this sceneMVar s
          else do
            -- other events are handled below (in Editor.Scene)
            modifyState (updateEditorScene event)
            updateSceneMVar app sceneMVar
            worker

    this = editorLoop app parent sceneMVar scene

    render sceneMVar ptr = do
        scene <- readMVar sceneMVar
        renderEditorScene ptr scene


askSaveLevel :: Application -> AppState -> EditorScene Sort_ -> AppState
askSaveLevel app parent scene@EditorScene{levelPath = (Just path)} =
    Top.Application.menu app (Just ("save level (under name \"" ++ path ++ "\")?")) Nothing [
        ("yes", saveLevel app parent scene),
        ("no", parent)
      ]

saveLevel :: Application -> AppState -> EditorScene Sort_ -> AppState
saveLevel app parent EditorScene{levelPath = (Just path), editorObjects} = AppState $ do
    writeObjectsToDisk path editorObjects
    return parent

editorMenu :: Application -> AppState -> MVar (EditorScene Sort_)
    -> EditorScene Sort_ -> AppState
editorMenu app parent sceneMVar scene =
    Top.Application.menu app (Just "editor menu") (Just (edit scene))
      (
      lEnterOEM ++
      [
        ("select object", selectSort app parent sceneMVar scene),
        ("return to editing", edit scene),
        ("save level and exit editor", saveLevel app parent scene),
        ("exit editor without saving", reallyExitEditor app parent this)
      ])
  where
    this = editorMenu app parent sceneMVar scene
    lEnterOEM = case selected scene of
        Nothing -> []
        Just i -> case objectEditModeMethods $ editorSort $ getMainObject scene i of
            Nothing -> []
            Just _ -> [("edit object", 
                        edit scene{objectEditModeIndex = Just i, editorObjects = objects'})]
              where
                objects' = modifyMainLayer (modifyByIndex (modifyOEMState mod) i) $ editorObjects scene
                mod :: OEMState Sort_ -> OEMState Sort_
                mod = enterModeOEM scene
    edit :: EditorScene Sort_ -> AppState
    edit s = editorLoop app parent sceneMVar scene

reallyExitEditor app parent editorMenu =
    Top.Application.menu app (Just "really exit without saving?") (Just editorMenu) [
        ("no", editorMenu),
        ("yes", parent)
      ]

selectSort :: Application -> AppState -> MVar (EditorScene Sort_)
    -> EditorScene Sort_ -> AppState
selectSort app parent mvar scene =
    treeToMenu app parent (fmap (sortId >>> getSortId) $ availableSorts scene) select
  where
    select :: String -> AppState
    select n =
        editorLoop app parent mvar scene'
      where
        scene' = case selectFirstElement pred (availableSorts scene) of
            Just newTree -> scene{availableSorts = newTree}
        pred sort = SortId n == sortId sort


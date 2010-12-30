{-# language DeriveDataTypeable, NamedFieldPuns, MultiParamTypeClasses #-}

-- | objects that seem like tiles, but move when Nikki touches them

module Sorts.FallingTiles (sorts) where


import Data.Generics
import Data.Abelian
import Data.Set (member)

import System.FilePath
import System.Random

import qualified Physics.Hipmunk as H
import Physics.Chipmunk as CM hiding (Static)

import Graphics.Qt

import Utils

import Base

import Object

import Sorts.Box (boxMaterialMass)


-- * configuration

-- | Tiles that are available as falling tiles. Same format as in Sorts/Tiles.hs
names = [
    ("tiles/white-falling", (Position (- 1) (- 1)), Size 64 64)
  ]

-- | time in seconds, before the tiles start to fall after touching Nikki
timeBeforeGettingLoose :: Seconds
timeBeforeGettingLoose = 0.2

fallingTilesMaterialMass = boxMaterialMass

-- * loading

sorts :: M [Sort_]
sorts = do
    tiles <- mapM (\ (a, b, c) -> mkSort a b c) names
    return tiles

mkSort :: String -> Offset Int -> Size Double -> M Sort_
mkSort name offset size = do
    pngFile <- getDataFileName (pngDir </> name <.> "png")
    pixmap <- io $ newQPixmap pngFile
    return $ Sort_ $ TSort name (Pixmap pixmap size (fmap fromIntegral offset))


data TSort
    = TSort {
        name :: String,
        tilePixmap :: Pixmap
      }
    deriving (Show, Typeable)

data FallingTile
    = FallingTile {
        tileAttributes :: BodyAttributes,
        chipmunk :: Chipmunk,
        status :: Status
      }
  deriving (Show, Typeable)

data Status = Static | GettingLoose Seconds | Loose
  deriving (Show, Typeable)


instance Sort TSort FallingTile where
    sortId TSort{name} = SortId ("fallingTile/" ++ name)

    size (TSort _ pix) = pixmapSize pix

    sortRender sort ptr _ = do
        renderPixmapSimple ptr (tilePixmap sort)
        let Size w h = fmap (subtract 1) $ size sort
        -- draw a red cross on top
        setPenColor ptr red 2
        drawLine ptr zero (Position w h)
        drawLine ptr (Position w 0) (Position 0 h)

    initialize sort@TSort{} (Just space) editorPosition Nothing = do
        (chip, attributes) <- initializeBox space sort editorPosition
        modifyApplyForce chip (CM.scale (Vector 0 (- gravity)) staticMass)
        return $ FallingTile attributes chip Static

    immutableCopy t@FallingTile{chipmunk} =
        CM.immutableCopy chipmunk >>= \ x -> return t{chipmunk = x}

    chipmunks (FallingTile _ c _) = [c]

    updateNoSceneChange sort mode now contacts cd fallingTile =
        case status fallingTile of
            Static ->
                if any (`member` fallingTiles contacts) (shapes (chipmunk fallingTile)) then
                    return fallingTile{status = GettingLoose now}
                  else
                    return fallingTile
            GettingLoose t -> 
                if now - t >= timeBeforeGettingLoose then do
                    modifyApplyOnlyForce (chipmunk fallingTile) zero
                    let b = body $ chipmunk fallingTile
                    H.mass b $= (mass $ tileAttributes fallingTile)
                    moment b $= (inertia $ tileAttributes fallingTile)
                    angVel <- randomRIO (-2, 2)
                    modifyAngVel (chipmunk fallingTile) (const angVel)
                    return $ fallingTile{status = Loose}
                  else
                    return fallingTile
            Loose ->
                return fallingTile

    render t@FallingTile{chipmunk = ImmutableChipmunk{}} sort@TSort{tilePixmap} ptr offset _now = do
        (position, rad) <- getRenderPosition $ chipmunk t
        renderPixmap ptr offset position (Just rad) tilePixmap


initializeBox :: Space -> TSort -> EditorPosition -> IO (Chipmunk, BodyAttributes)
initializeBox space sort ep = do
    let (shape, baryCenterOffset) = mkShape sort
        shapeWithAttributes = (mkShapeDescription shapeAttributes shape)
        pos :: Vector
        pos = qtPosition2Vector (editorPosition2QtPosition sort ep)
                +~ baryCenterOffset
        bodyAttributes = mkMaterialBodyAttributes fallingTilesMaterialMass [shape] pos
        -- this is a hack: mass and inertia set to very large values to simulate static tiles
        staticBodyAttributes = bodyAttributes{mass = staticMass, inertia = staticInertia}
    chip <- initChipmunk space staticBodyAttributes [shapeWithAttributes] baryCenterOffset
    return (chip, bodyAttributes)

staticMass = 1000000000000
staticInertia = 1000000000000000000

mkShape :: TSort -> (ShapeType, Vector)
mkShape sort =
    (box, baryCenterOffset)
  where
    box = Polygon [
        upperLeft +~ xUnit,
        upperLeft +~ yUnit, 
        lowerLeft -~ yUnit, 
        lowerLeft +~ xUnit,
        lowerRight -~ xUnit, 
        lowerRight -~ yUnit,
        upperRight +~ yUnit,
        upperRight -~ xUnit]

    xUnit = Vector 1 0
    yUnit = Vector 0 1

    Size w h = size sort
    wh = w / 2
    hh = h / 2
    baryCenterOffset = Vector wh hh

    -- | falling tiles have to be smaller than normal
    -- to avoid them to be wedged in between normal tiles.
    -- Except for the upper edge, to allow smooth walking...
    low = hh        - 1
    up = (- hh)     -- + 1
    left = (- wh)   + 1
    right = wh      - 1

    upperLeft = Vector left up
    lowerLeft = Vector left low
    lowerRight = Vector right low
    upperRight = Vector right up

shapeAttributes :: ShapeAttributes
shapeAttributes = ShapeAttributes {
    elasticity    = 0.5,
    friction      = 2.0,
    collisionType = FallingTileCT
  }

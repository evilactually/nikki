
module Game.Scene.Camera (
    CameraState,
    getCenter,
  ) where


import Data.Abelian
import Data.Initial

import qualified Physics.Chipmunk as CM
import Physics.Chipmunk hiding (position, Position)

-- import Object


data CameraState
    = CS Vector
  deriving Show

instance Initial CameraState where
    initial = CS zero


-- returns the position the camera looks at
getCenter :: CM.Position -> CameraState -> IO (CM.Position, CameraState)
getCenter position (CS camPos) = do
    let distance = camPos - position
        xLimit = 200
        yLimit = 100
        newPos = Vector newX newY
        newX = if abs (vectorX distance) < xLimit then
                    vectorX camPos
                  else
                    vectorX position + signum (vectorX distance) * xLimit
        newY = if abs (vectorY distance) < yLimit then
                    vectorY camPos
                  else
                    vectorY position + signum (vectorY distance) * yLimit
    return (newPos, CS newPos)








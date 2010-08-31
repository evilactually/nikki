{-# language NamedFieldPuns #-}

-- | module for the detection and saving of collisions while chipmunk simulation

module Physics.Chipmunk.ContactRef (
    setMyCollisionType,

    ContactRef,
    Callback(..),
    Watcher(..),
    Permeability(..),
    initContactRef,
    resetContactRef,
    readContactRef
  ) where


import Data.IORef
import Data.Array.Storable

import Physics.Hipmunk hiding (Callback)


-- * collisionTypes

toNumber :: Enum collisionType => collisionType -> CollisionType
toNumber = toEnum . fromEnum

setMyCollisionType :: Enum collisionType => Shape -> collisionType -> IO ()
setMyCollisionType s ct = setCollisionType s (toNumber ct)


-- * contact ref stuff

data ContactRef x =
    ContactRef {empty :: x, modifier :: IORef x}

instance Show (ContactRef object) where
    show = const "<CollisionRef>"

data Callback collisionType x
    = Callback (Watcher collisionType x) Permeability

data Watcher collisionType x
    = DontWatch collisionType collisionType
    | Watch
        collisionType
        collisionType
        (Shape -> Shape -> x -> x)
    | FullWatch
        collisionType
        collisionType
        (Shape -> Shape -> StorableArray Int Contact -> CpFloat -> x -> x)

data Permeability = Permeable | Solid

isSolid :: Permeability -> Bool
isSolid Solid = True
isSolid _ = False

-- | needs an empty contacts value
initContactRef :: Enum collisionType =>
     Space -> x -> [Callback collisionType x] -> IO (ContactRef x)
initContactRef space empty callbacks = do
    ref <- newIORef empty
    mapM_ (installCallback ref) callbacks
    return $ ContactRef empty ref
  where
    installCallback _ref (Callback (DontWatch a b) permeability) = do
        addCallback space (toNumber a, toNumber b) $ Basic $ \ _ _ -> -- TODO: could be Constant, but it's buggy
            return $ isSolid permeability
    installCallback ref (Callback (Watch a b f) permeability) = do
        addCallback space (toNumber a, toNumber b) $
            Basic $ \ shapeA shapeB -> do
                modifyIORef ref (f shapeA shapeB)
                return (isSolid permeability)
    installCallback ref (Callback (FullWatch a b f) permeability) = do
        addCallback space (toNumber a, toNumber b) $
            Full $ \ shapeA shapeB contacts coefficient -> do
                modifyIORef ref (f shapeA shapeB contacts coefficient)
                return (isSolid permeability)


-- updating

-- | resets the ContactRef
resetContactRef :: ContactRef x -> IO ()
resetContactRef (ContactRef empty ref) = do
    writeIORef ref empty


-- | returns the actual state of the contacts
readContactRef :: ContactRef x -> IO x
readContactRef (ContactRef empty ref) =
    readIORef ref



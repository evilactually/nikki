-- Module for trees with one selected item, that can be stepped through

module Data.SelectTree (
    SelectTree(..),
    mkNode,
    addChild,
    getLabel,
    getChildren,
    getSelected,
    selectNext,
    selectPrevious,
    selectFirstElement,
    leafs,
    modifyLabelled,
    (-<),
  ) where

import Utils

import qualified Data.Indexable as I
import Data.Indexable hiding (length, toList, findIndices, fromList)
import qualified Data.Tree as T
import Data.Foldable (Foldable, foldMap)


data SelectTree a
    -- Invariant: length [SelectTree a] > Index
    = Node String (Indexable (SelectTree a)) Index
    | Leaf {fromLeaf :: a}
    | EmptyNode String
  deriving Show


instance Functor SelectTree where
    fmap f (Node label children index) = Node label (fmap (fmap f) children) index
    fmap f (Leaf a) = Leaf $ f a

instance Show a => PP (SelectTree a) where
    pp = T.drawTree . fmap show . toTree

instance Foldable SelectTree where
    foldMap f (Leaf a) = f a
    foldMap f (Node _ cs _) = foldMap (foldMap f) cs


mkNode :: String -> (Indexable (SelectTree a)) -> SelectTree a
mkNode label ix = Node label ix (head (keys ix))

-- | adds a child (at the end)
-- PRE: the second given tree is not a Leaf
addChild :: SelectTree a -> SelectTree a -> SelectTree a
addChild _ (Leaf _) = error "addChild"
addChild x (EmptyNode label) = mkNode label (I.fromList [x])
addChild x (Node label children selected) = Node label (children >: x) selected

getLabel :: SelectTree a -> Maybe String
getLabel (Node l _ _) = Just l
getLabel _ = Nothing

getChildren :: SelectTree a -> [SelectTree a]
getChildren (Node _ x _) = I.toList x
getChildren _ = []

getSelected :: SelectTree a -> a
getSelected (Node sn cs i) = getSelected (cs !!! i)
getSelected (Leaf a) = a

-- | selects the previous item in the tree.
-- steps through all the items in a tree.
-- wraps around in the beginning.
selectPrevious :: SelectTree a -> SelectTree a
selectPrevious = selectOther (subtract 1) resetSelectedLast

-- | selects the next item in the tree.
-- steps through all the items in a tree.
-- wraps around in the end.
selectNext :: SelectTree a -> SelectTree a
selectNext = selectOther (+ 1) resetSelectedsFirst

selectOther :: (Index -> Index) -> (SelectTree a -> SelectTree a) -> SelectTree a -> SelectTree a
selectOther updateSelected reset tree =
    case selectNextNotWrapping tree of
        -- wraps around (the whole tree, not subtrees, of course)
        Nothing -> reset tree
        -- child is updated
        Just new -> new
  where
    selectNextNotWrapping :: SelectTree a -> Maybe (SelectTree a)
    selectNextNotWrapping (Node label children selected) =
        case selectNextNotWrapping (children !!! selected) of
            -- child cannot be updated -> parent must be updated
            Nothing ->  let newSelected = updateSelected selected
                        in if newSelected `isIndexOf` children then
                            Just $ Node label children newSelected
                          else
                            Nothing
            -- child could be updated: must be inserted in list
            Just child ->
                Just $ Node label (modifyByIndex (const child) selected children) selected
    selectNextNotWrapping (Leaf a) = Nothing

-- resets the tree to select the first item in it and every child.
resetSelectedsFirst :: SelectTree a -> SelectTree a
resetSelectedsFirst (Leaf a) = Leaf a
resetSelectedsFirst (Node label children _) = Node label (fmap resetSelectedsFirst children) 0

resetSelectedLast :: SelectTree a -> SelectTree a
resetSelectedLast (Leaf a) = Leaf a
resetSelectedLast (Node label children _) =
    Node label (fmap resetSelectedLast children) (I.length children - 1)


leafs :: SelectTree a -> [a]
leafs (Node _ ll _) = concatMap leafs (I.toList ll)
leafs (Leaf a) = return a


selectFirstElement :: (e -> Bool) -> SelectTree e -> Maybe (SelectTree e)
selectFirstElement f tree = inner (length $ leafs tree) tree
  where
    inner n _ | n <= 0 = Nothing
    inner n tree =
        if f (getSelected tree) then
            Just tree
          else
            inner (n - 1) (selectNext tree)


-- | modifies the children of a given tree with a given function, if it has a given label
-- PRE: given tree can not be a Leaf
modifyLabelled :: String -> (SelectTree a -> SelectTree a) -> SelectTree a -> SelectTree a
modifyLabelled testLabel f (Node label children selected) =
    Node label (fmap inner children) selected
  where
    inner n = if getLabel n == Just testLabel then f n else n
modifyLabelled _ _ x = x


toTree :: Show a => SelectTree a -> T.Tree (Either String a)
toTree (Node snippet children _) = T.Node (Left snippet) (I.toList (fmap toTree children))
toTree (Leaf a) = T.Node (Right a) []
-- toTree x = es "toTree" x

(-<) :: SelectTree a -> Index -> SelectTree a
(Node _ children _) -< index = children !!! index

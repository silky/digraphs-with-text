    {-# LANGUAGE FlexibleContexts #-}
    module Dwt.Util
      ( module Dwt.Util
      ) where

    import Data.Graph.Inductive
    import qualified Data.Map as Map
    import Control.Monad.Except (MonadError, throwError)

-- for graphs
    negateGraph :: Graph Gr => Gr a b -> Gr a b
    negateGraph m = gmap (\(a,b,c,d) -> (negAdj a, -b, c, negAdj d)) m
      where negAdj = map (\(label,n) -> (label,-n))

    compressGraph :: DynGraph gr => gr a b -> gr a b
    compressGraph g = let ns = nodes g
                          ns' = [1 .. length ns]
                          mp = Map.fromList $ zip ns ns'
                          chNode n = mp Map.! n
                          chAdj (b,n) = (b, mp Map.! n)
      in gmap (\(a,b,lab,d) -> (map chAdj a, chNode b, lab, map chAdj d)) g

-- for monads
    -- TODO: This could use a higher-kinded function, lke eitherToMe, for Maybes
      -- should in that case take also a String to show if Nothing happens
    mapLookupMe :: (Ord k, Show k, Show a, MonadError String me) => -- TODO: bad?
      k -> Map.Map k a -> me a -- Is it bad to need this function?
    mapLookupMe k m = case Map.lookup k m of
      Just a -> return a
      Nothing -> throwError $ "mapLookupMe: " ++
      -- reports map; could be bad if map big
        show k ++ " not in map " ++ show m

    eitherToMe :: (Show e, MonadError String me) =>
      (a -> Either e t) -> a -> me t
    eitherToMe f x = case f x of Right y -> return y
                                 Left e -> throwError $ show e

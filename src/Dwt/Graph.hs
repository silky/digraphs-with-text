-- pragmas, export, import
    {-# LANGUAGE FlexibleContexts #-}

    module Dwt.Graph
      ( module Data.Graph.Inductive
      , module Dwt.Graph
      ) where

    import Data.Graph.Inductive
    import Data.Either (partitionEithers)
    import Data.List (intersect, sortOn, intercalate)
    import Data.Maybe (isJust, catMaybes, fromJust)
    import Control.Monad (mapM_)
    import Control.Monad.Except (MonadError, throwError)
    import qualified Data.Text as T

-- types
    type Arity = Int -- relationships, which some expressions are, have arities
    type RelPos = Int -- the k members of a k-ary Rel take RelPos values [1..k]
    data Expr = Str String | Tplt Arity [String] | Rel Arity
      deriving (Show,Read,Eq,Ord)
    data Role = AsTplt | AsPos RelPos
      deriving (Show,Read,Eq,Ord)
    type Mindmap = Gr Expr Role

-- build
  -- Tplt <-> String
    splitTpltStr :: String -> [String]
    splitTpltStr t = map T.unpack $ T.splitOn (T.pack "_") (T.pack t)

    stringToTplt :: String -> Expr
    stringToTplt s = Tplt (length ss-1) ss -- even length=0 works
      where ss = splitTpltStr s

    subInTplt :: Expr -> [String] -> String
    subInTplt (Tplt k ts) ss = let pairList = zip ts $ ss ++ [""] 
      -- append "" because there are n+1 segments in an n-ary Tplt; 
        -- zipper ends early otherwise
      in foldl (\s (a,b) -> s++a++b) "" pairList

  -- insert
    insStr :: String -> Mindmap -> Mindmap
    insStr str g = insNode (int, Str str) g
      where int = head $ newNodes 1 g

    insTplt :: String -> Mindmap -> Mindmap
    insTplt s g = insNode (newNode, stringToTplt s) g
      where newNode = head $ newNodes 1 g

    insRel :: (MonadError String m) => Node -> [Node] -> Mindmap -> m Mindmap
    insRel tn ns g =
      do mapM_ (gelemM g) $ tn:ns
         t <- tpltAt g tn
         a <- tpltArity t
         nodesMatchTplt ns t
         return $ let 
             newNode = head $ newNodes 1 g
             f []     g = g
             f (p:ps) g = f ps $ insEdge (newNode, fst p, AsPos $ snd p) g
             g' =                insEdge (newNode, tn, AsTplt)
                               $ insNode (newNode, Rel a) g
           in f (zip ns [1..a]) g'

  -- edit
    chExprAt :: (MonadError String m) => Mindmap -> Node -> Expr -> m Mindmap
    chExprAt g n e = do -- TODO : test
      gelemM g n
      return $ chExprAtUsf g n e

    -- chMbr :: Role -> Node -> Node -> Mindmap -> Mindmap
    -- chMbr role newMbr user g = ... -- TODO

-- query
  -- tests and lookups for smaller-than-graph types
    gelemM :: (MonadError String m) => Mindmap -> Node -> m ()
    gelemM g n = if gelem n g then return () 
                              else throwError $ "gelemM: Node "
                                   ++ show n ++ " not in Mindmap"

    tpltAt :: (MonadError String m) => Mindmap -> Node -> m Expr -- TODO test
    tpltAt g tn = case lab g tn of 
      Just t@(Tplt a b) -> return $ t
      Nothing           -> throwError "tpltAt: Node not in Mindmap"
      _                 -> throwError "tpltAt: Node does not index a Tplt"

    tpltArity :: (MonadError String m) => Expr -> m Arity
    tpltArity e = case e of Tplt a _ -> return a
                            _        -> throwError "tpltArity: Expr not a Tplt"

    nodesMatchTplt :: (MonadError String m) => [Node] -> Expr -> m () -- TODO test
    nodesMatchTplt ns e = case e of
      Tplt k _ -> if k /= length ns 
        then throwError "nodesMatchTplt: Tplt Arity /= number of member Nodes"
        else return ()
      _ -> throwError "nodesMatchTplt: Expr not a Tplt"

  -- Mindmap -> ...stuff... -> [Node]
    users :: (MonadError String m) => Mindmap -> Node -> m [Node]
    users g n = do gelemM g n
                   return $ [m | (m,n,label) <- inn g n]

    specUsersUsf :: Mindmap -> Role -> Arity -> Node -> [Node] --TODO test
    specUsersUsf g r k n = -- all k-ary Rels using Node n in Role r
      let isKAryRel m = lab g m == (Just $ Rel k)
      in [m | (m,n,r') <- inn g n, r' == r, isKAryRel m]

    specUsers :: (MonadError String m) => -- TODO: test
      Mindmap -> Role -> Arity -> Node -> m [Node]
    specUsers g r k n = do -- all k-ary Rels using Node n in Role r
      gelemM g n
      return $ let isKAryRel m = lab g m == (Just $ Rel k)
        in [m | (m,_,r') <- inn g n, r' == r, isKAryRel m]
          -- the _ is always n

    matchRel :: Mindmap -> [Maybe Node] -> [Node]
    matchRel g mns = listIntersect $ map f jns
      where arity = length mns - 1
            jns = filter (isJust . fst) $ zip mns [0..] :: [(Maybe Node, RelPos)]
            f (Just n, 0) = specUsersUsf g AsTplt    arity n
            f (Just n, k) = specUsersUsf g (AsPos k) arity n
            listIntersect [] = []
            listIntersect (x:xs) = foldl intersect x xs

-- view
    showExpr :: Mindmap -> Node -> String -- TODO: Either|Maybe
      -- BEWARE ? infinite loops
        -- if the graph is recursive, this could infinite loop
          -- such cycles seem unlikely to be intende, b/c recursive statements are
          -- confusing; c.f. Godel's impossibility theorem
        -- a solution: while building, keep list of visited nodes
          -- if visiting one already listed, display it as just its Node
          -- or Node ++ "already displayed higher in this (node view?)"
    showExpr g n = case lab g n of
      Nothing -> error $ "showExpr: node " ++ (show n) ++ " not in graph"
      Just (Str s) ->     (show n) ++ ": "       ++ s
      Just (Tplt _ ts) -> ":" ++ (show n) ++ " " ++ intercalate "_" ts
      Just (Rel _) ->
        let ledges = sortOn edgeLabel $ out g n
            (_,tpltNode,_) = head ledges
              -- head because Tplt sorts first, before Rel, in Ord Expr 
            Just tpltLab = lab g tpltNode :: Maybe Expr
            members = map (\(_,m,_)-> m) $ tail ledges :: [Node]
        in prefixRel tpltNode $ subInTplt tpltLab 
             $ map (bracket . showExpr g) members
      where prefixRel tn s = show n ++ ":" ++ show tn ++ " " ++ s
            bracket s = "[" ++ s ++ "]"

    view :: Mindmap -> [Node] -> IO ()
    view g ns = mapM_ putStrLn $ map (showExpr g) ns

-- non-monadic, unsafe duplicate functions; deprecating
    insRelUsf :: Node -> [Node] -> Mindmap -> Mindmap
    insRelUsf t ns g = if ti /= length ns -- t is tplt, otherwise like ns
        then error "insRelUsf: Tplt Arity /= number of members Nodes"
        else if any (==False) $ map (flip gelem g) $ (t:ns)
          then error "insRelUsf: One of those Nodes is not in the Mindmap." 
        else f (zip ns [1..ti]) g'
      where Tplt ti ts = fromJust $ lab g t -- can also error:
              -- by finding Str or Rel where expected Tplt
            newNode = head $ newNodes 1 g
            f []     g = g
            f (p:ps) g = f ps $ insEdge (newNode, fst p, AsPos $ snd p) g
            g' =                insEdge (newNode, t, AsTplt)
                              $ insNode (newNode, Rel ti) g

    chExprAtUsf :: Mindmap -> Node -> Expr -> Mindmap
    chExprAtUsf g n e = let (Just (a,b,c,d),g') = match n g
      in (a,b,e,d) & g'

    usersUsf :: Mindmap ->  Node -> [Node] -- TODO: test
    usersUsf g n = [m | (m,n,label) <- inn g n]

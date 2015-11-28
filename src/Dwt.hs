-- usually folded
  -- TODO
    -- make|keep my Node|Label notation consistent with tradition
    -- Kinds of view
      -- e.g. with Nodes, without
    -- Delete LNode
    -- Make another Rel type (called Rel'? RelSpec? RelRequest?)
      -- Rel' = (MmNode, [MmNode]), where data MmNode = MmNode Int | Blank
    -- ? Add [classes?] for checking arity
  -- types, vocab, language
    -- Node,Edge: FGL. Expr, Rel: DWT|Mindmap.
    -- how to read edges
      -- in (n,m,lab :: MmLab) :: LEdge MmLab, n is a Rel referring to m
        -- usj, m is an Str
      -- that is, predecessors refer to successors 
        -- (in that kind of relationship they do; maybe there will be others)
    -- abbreviations
      -- ch = change
      -- mbr = member
        -- in a a k-ary Rel, there are k AsPos Roles for k members to play,
        -- plus one more Role for the Tplt (which must be k-ary) to play
      -- Tplt = (relationship) template
      -- Rel = relationship

-- export & import
    module Dwt
      ( -- exports:
      module Data.Graph.Inductive -- export for testing, not production
      , module Dwt -- exports everything in this file
      -- , module Dwt.Graph -- etc. Will need to import below to match.
      ) where    
    import Data.Graph.Inductive
    import Data.String (String)
    import Data.Either (partitionEithers)
    import Data.List (intersect, sortOn, intercalate)
    import Data.Maybe (isJust, catMaybes, fromJust)
    import Control.Monad (mapM_)
    import qualified Data.Text as T

-- types
    type Arity = Int -- relationships, which some expressions are, have arities
    type RelPos = Int -- the k members of a k-ary Rel take RelPos values [1..k]
    data Expr = Str String | Tplt Arity [String] | Rel Arity
      deriving (Show,Read,Eq,Ord) -- relationships instantiate templates
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

    subInTplt :: Expr -> [String] -> String -- TODO ? Inexhaustive case
    subInTplt (Tplt k ts) ss = let pairList = zip ts $ ss ++ [""] -- append [""] because there are n+1 segments in an n-ary Tplt; zipper ends early otherwise
      in foldl (\s (a,b) -> s++a++b) "" pairList

  -- insert
    insStr :: String -> Mindmap -> Mindmap
    insStr str g = insNode (int, Str str) g
      where int = head $ newNodes 1 g

    insTplt :: String -> Mindmap -> Mindmap
    insTplt s g = insNode (newNode, stringToTplt s) g
      where newNode = head $ newNodes 1 g

    insRel :: Node -> [Node] -> Mindmap -> Mindmap -- TODO ? return Either
    insRel t ns g = if ti /= length ns -- t is tplt, otherwise like ns
        then error "insRel: Tplt arity /= number of members" -- TODO ? smelly
        else f (zip ns [1..ti]) g'
      where Tplt ti ts = fromJust $ lab g t -- TODO: consider case of Nothing?
                                            -- case of Just k, for k not Tplt?
            newNode = head $ newNodes 1 g
            g' = insEdge (newNode, t, AsTplt)
               $ insNode (newNode, Rel ti) g
            f []     g = g
            f (p:ps) g = f ps $ insEdge (newNode, fst p, AsPos $ snd p) g

  -- edit ("ch" = "change")
    chLNode :: Mindmap -> Node -> Expr -> Mindmap -- TODO: use Either
    chLNode g n me = let (Just (a,b,c,d),g') = match n g -- TODO: better Maybeing
      in (a,b,me,d) & g'

    -- chMbr :: Role -> Node -> Node -> Mindmap -> Mindmap -- TODO
    -- chMbr role newMbr user g = ...

-- query
    users :: Mindmap ->  Node -> [Node]
    users g n = [m | (m,n,label) <- inn g n]

    specUsers :: Mindmap -> Role -> Arity -> Node -> [Node]
    specUsers g r k n = -- all k-ary Rels using Node n in Role r
      let isKAryRel m = lab g m == (Just $ Rel k)
      in [m | (m,n,r') <- inn g n, r' == r, isKAryRel m]

    matchRel :: Mindmap -> [Maybe Node] -> [Node]
    matchRel g mns = listIntersect $ map f jns
      where arity = length mns - 1
            jns = filter (isJust . fst) $ zip mns [0..] :: [(Maybe Node, RelPos)]
            f (Just n, 0) = specUsers g AsTplt    arity n
            f (Just n, k) = specUsers g (AsPos k) arity n
            listIntersect [] = [] -- silly case
            listIntersect (x:xs) = foldl intersect x xs

-- view
    showExpr :: Mindmap -> Node -> String -- BEWARE ? infinite loops
     -- if the graph is recursive, this could infinite loop
       -- although such graphs seem unlikely, because recursive statements are
       -- difficult; c.f. Godel's impossibility theorem
     -- a solution: while building, keep list of visited nodes
       -- if visiting one already there, display it as just its number
       -- or number + "already displayed higher in this (node view?)"    
    showExpr g n = case lab g n of
      Nothing -> error $ "showExpr: node " ++ (show n) ++ " not in graph" -- TODO ? smelly
      Just (Str s) ->     prependNode s
      Just (Tplt k ts) -> prependNode $ "Tplt: " ++ intercalate "_" ts
      Just (Rel _) ->
        let ledges = sortOn (\(_,_,l)->l) $ out g n
            (_,tpltNode,_) = head ledges
              -- head because Tplt sorts first, before Rel, in Ord Expr 
            Just tpltLab = lab g tpltNode :: Maybe Expr
            members = map (\(_,m,_)-> m) $ tail ledges :: [Node]
        in prefixRel tpltNode $ subInTplt tpltLab 
             $ map (bracket . showExpr g) members
      where prependNode s = (show n) ++ ": " ++ s
            prefixRel tn s = show n ++ ":" ++ show tn ++ " " ++ s
            bracket s = "[" ++ s ++ "]"

    view :: Mindmap -> [Node] -> IO ()
    view g ns = mapM_ putStrLn $ map (showExpr g) ns

-- usually folded
  -- TODO
    -- Make another Rel type
      -- Rel' = (MmNode, [MmNode]), where data MmNode = MmNode Int | Blank
    -- Add classes for checking arity
  -- types, vocab, language
    -- Node,Edge: FGL. Expr, Rel: DWT|Mindmap.
    -- how to read edges
      -- in (n,m,lab :: MmLab) :: LEdge MmLab, n is a triplet referring to m
      -- that is, predecessors refer to successors 
        -- (in that kind of relationship they do; maybe there will be others)

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
    type Arity = Int
    data MmExpr =  MmString String | Tplt Arity String | Rel Arity
      deriving (Show,Read,Eq,Ord)
    data MmEdge = AsTplt | AsPos Arity -- MmEdgeLabel more accurate, but too long
      deriving (Show,Read,Eq,Ord)
    type Mindmap = Gr MmExpr MmEdge

-- build
    insStr :: String -> Mindmap -> Mindmap
    insStr str g = insNode (int, MmString str) g
      where int = head $ newNodes 1 g

    insTplt :: String -> Mindmap -> Mindmap
    insTplt s g = insNode (newNode, Tplt (countHoles s) s) g
      where newNode = head $ newNodes 1 g
            countHoles "" = 0
            countHoles ('_':s) = 1 + countHoles s
            countHoles (_:s) = countHoles s

    insRel :: Node -> [Node] -> Mindmap -> Mindmap -- TODO ? return Either Str Mm
    insRel t ns g = if ti /= length ns -- t is tplt, otherwise like ns
        then error "Tplt arity /= number of members"
        else f (zip ns [1..ti]) g'
      where Tplt ti ts = fromJust $ lab g t -- TODO: consider case of Nothing?
                                            -- case of Just k, for k not Tplt?
            newNode = head $ newNodes 1 g
            g' = insEdge (newNode, t, AsTplt)
               $ insNode (newNode, Rel ti) g
            f []     g = g
            f (p:ps) g = f ps $ insEdge (newNode, fst p, AsPos $ snd p) g

-- query
    mmReferents :: Mindmap -> MmEdge -> Arity -> Node -> [Node]
    mmReferents g e k n = -- returns all uses (of a type specified by e & k) of n
      let isKAryRel m = lab g m == (Just $ Rel k)
      in [m | (m,n,label) <- inn g n, label == e, isKAryRel m]

    mmRelps :: Mindmap -> [Maybe Node] -> [Node]
    mmRelps g mns = listIntersect $ map f jns
      where arity = length mns - 1
            jns = filter (isJust . fst) $ zip mns [0..] :: [(Maybe Node, Int)]
            f (Just n, 0) = mmReferents g AsTplt    arity n
            f (Just n, k) = mmReferents g (AsPos k) arity n
            listIntersect [] = [] -- silly case
            listIntersect (x:xs) = foldl intersect x xs

-- view
    splitTplt :: String -> [String]
    splitTplt t = map T.unpack $ T.splitOn (T.pack "_") (T.pack t)

    subInTplt :: String -> [String] -> String -- TODO: Tplt be already split
    subInTplt t ss = let tpltAsList = splitTplt t
                         pairList = zip tpltAsList ss
      in foldl (\s (a,b) -> s++a++b) "" pairList

    showExpr :: Mindmap -> Node -> Either String String -- WARNING|TODO
      -- if the graph is recursive, could this infinite loop?
        -- yes, but is that kind of graph probable?
    showExpr g n = case lab g n of
      Nothing -> Left $ "node " ++ (show n) ++ " not in graph"
      Just (MmString s) -> Right $ prefixNode s
      Just (Tplt k s) -> Right $ prefixNode $ "Tplt: " ++  s
      Just (Rel _) -> Right $ prefixNode $ intercalate ", " 
           $ (\(a,b)->a++b) $ partitionEithers $ map f
           $ sortOn (\(_,_,l)->l) $ out g n
        where f (n,m,label) = showExpr g m
      where prefixNode s = (show n) ++ ": " ++ s

    view :: Mindmap -> [Maybe Node] -> IO ()
    view g mns = mapM_ putStrLn $ map (eitherString . showExpr g) $ mmRelps g mns
      where eitherString (Left s) = s
            eitherString (Right s) = s

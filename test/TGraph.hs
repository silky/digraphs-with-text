-- setup
    {-# LANGUAGE FlexibleContexts #-}
    import Dwt
    import Test.HUnit
    import qualified Control.Lens.Lens as L -- not crit; for (&), only used once
    import qualified Data.List as List
    import Data.Maybe (fromJust)
    import Data.Either
    import System.IO
    import qualified Data.Map as Map
    import Data.Time as T

    import Control.Monad.Except -- from mtl library

-- main
    main = runTestTT $ TestList
      [   TestLabel "tBuildGraph" tBuildGraph
        , TestLabel "tAskMinor"   tAskMinor
        , TestLabel "tAskNodes"   tAskNodes
        , TestLabel "tShowExpr"   tShowExpr
        , TestLabel "tParseMm"    tParseMm
        , TestLabel "tMmTags"     tMmTags
      ]

-- "globals"
    g1,g1' :: Mindmap
    g1 = mkGraph
      [   (0, Str "dog"       )
        , (1, stringToTplt "_ wants _" )
        , (2, stringToTplt "_ needs _" )
        , (3, Str "water"     )
        , (4, Str "brandy"    )
        , (5, Rel 2           )
        , (6, Rel 2           )
        , (7, stringToTplt "_ needs _ for _")
        , (8, Rel 3           ) 
        , (9, stringToTplt "statement _ is _")
        , (10, Str "dubious"  )
        , (11, Rel 2          )
      ] [ (5,1, RelTplt), (5,0, RelMbr 1), (5,4,RelMbr 2) -- dog wants brandy
        , (6,2, RelTplt), (6,0, RelMbr 1), (6,3,RelMbr 2) -- dog needs water
        , (8,7, RelTplt), (8,0, RelMbr 1), (8,3,RelMbr 2), (8,4,RelMbr 3) 
          -- dog needs water for brandy
        , (11,9,RelTplt), (11,5,RelMbr 1), (11,10,RelMbr 2) 
          -- [dog wants brandy] is dubious
      ]

    g1' =   insRelUsf 9 [5,10] 
          $ insStr "dubious"    $ insTplt "statement _ is _"
          $ insRelUsf 7 [0,3,4]    $ insTplt "_ needs _ for _"
          $ insRelUsf 2 [0,3]      $ insRelUsf 1 [0,4]
          $ insStr "brandy"     $ insStr "water"
          $ insTplt "_ needs _" $ insTplt "_ wants _"
          $ insStr "dog"        $ empty :: Mindmap

-- tests
  -- buildGraph
    tBuildGraph = TestList [ TestLabel "tSubInTplt" tSubInTplt
                           , TestLabel "tInsert" tInsert
                           , TestLabel "tInsRelM" tInsRelM]

    tSubInTplt = TestCase $ do
      assertBool "1" $ subInTplt (fromJust $ lab g1 1) ["man","peace"]
        == "man wants peace"
      assertBool "2" 
        $ (lab g1 1 L.& fromJust L.& subInTplt $ ["man","peace"])
        == "man wants peace"

    tInsert = TestCase $ do
      assertBool "stringToTplt (and thereby splitTpltStr), insRelUsf, insStr, insTplt" $ g1 == g1'

    tInsRelM = TestCase $ do
      assertBool "1" $ (insRel 2 [0,0] g1 :: Either String Mindmap)
            == (Right $ insRelUsf  2 [0,0] g1)
      assertBool "2" $ (insRel 15 [0,0] g1 :: Either String Mindmap)
            == Left "gelemM: Node 15 absent."
      assertBool "3" $ (insRel 2 [100,0] g1 :: Either String Mindmap)
            == Left "gelemM: Node 100 absent."
      assertBool "4" $ (insRel 2 [1,1,1] g1 :: Either String Mindmap)
            == Left "nodesMatchTplt: Tplt Arity /= number of member Nodes."
      assertBool "5" $ (insRel 0 [1,1,1] g1 :: Either String Mindmap)
            == Left "tpltAt: LNode 0 not a Tplt."

  -- ask, minor
    tAskMinor = TestList [ TestLabel "tGelemM" tGelemM
                         , TestLabel "tHasLEdgeM" tHasLEdgeM
                         , TestLabel "tIsTplt" tIsTplt
                         , TestLabel "tTpltAt" tTpltAt
                         , TestLabel "tTpltForRelAt" tTpltForRelAt
                         , TestLabel "tTpltArity" tTpltArity ]

    tGelemM = TestCase $ do
      assertBool "1" $ gelemM g1 0 == Right ()
      assertBool "2" $ gelemM g1 100 == Left "gelemM: Node 100 absent."

    tHasLEdgeM = TestCase $ do
      assertBool "has it" $ hasLEdgeM g1 (5,0,RelMbr 1) == Right ()
      assertBool "lacks it" $ isLeft $ hasLEdgeM g1 (5,0,RelMbr 2)

    tIsTplt = TestCase $ do
      assertBool "is template" $ isTplt g1 1 == Right True
      assertBool "is not template" $ isTplt g1 0 == Right False
      assertBool "missing" $ isLeft $ isTplt g1 (-1)

    tTpltAt = TestCase $ do
      assertBool "normal" $ tpltAt g1 1 == ( Right $ Tplt 2 [""," wants ",""] )
      assertBool "notATplt" $ isLeft $ tpltAt g1 0
      assertBool "absent" $ isLeft $ tpltAt g1 (-1)

    tTpltForRelAt = TestCase $ do
      assertBool "normal" $ tpltForRelAt g1 5 ==
        ( Right $ Tplt 2 [""," wants ",""] )
      assertBool "not a Rel" $ isLeft $ tpltForRelAt g1 1
      assertBool "absent" $ isLeft $ tpltForRelAt g1 (-1)

    tTpltArity = TestCase $ do
      assertBool "j1" $ tpltArity (Tplt 3 []) == Right 3
      assertBool "j2" $ isLeft $ tpltArity (Str "nog")
      assertBool "j3" $ tpltArity (Str "rig") == 
        Left "tpltArity: Expr not a Tplt."

  -- ask [Node]
    tAskNodes = TestList [ TestLabel "tUsers" tUsers
                         , TestLabel "tMatchRel" tMatchRel]

    tUsers = TestCase $ do
      assertBool "1" $ users g1 0 == Right [5,6,8]
      assertBool "2" $ isLeft $ (users g1 100 :: Either String [Dwt.Node])

    tMatchRel = TestCase $ do
      assertBool "1--"  $ matchRel g1 [Just 1,  Nothing, Nothing] == [5]
      assertBool "-0-"  $ matchRel g1 [Nothing, Just 0,  Nothing] == [5,6]
      assertBool "--3"  $ matchRel g1 [Nothing, Nothing, Just 4 ] == [5]
      assertBool "---4" $ matchRel g1 [Nothing, Nothing, Nothing, Just 4] == [8]

  -- show
    tShowExpr = TestCase $ do
      assertBool "expr 5" $ showExpr g1 5 == "5:1 [0: dog] wants [4: brandy]"
      assertBool "expr 11" $ showExpr g1 11 == 
        "11:9 statement [5:1 [0: dog] wants [4: brandy]] is [10: dubious]"

  -- parse .mm(the xml format)
    tParseMm = TestList [ TestLabel "tMmStr" tMmStr
                        , TestLabel "tWord" tWord
                        , TestLabel "tComment" tComment
                        , TestLabel "tKeyValPair" tKeyValPair
                        , TestLabel "tStrip" tStrip
                        , TestLabel "tMlTag" tMlTag]

    tMmStr = TestCase $ do
      assertBool "mmStr" $ eParse2 mmStr "\"aygaw\"bbbb"
        == Right ("aygaw","bbbb")
      assertBool "the escape characters"
        $ eParse2 mmStr "\"&lt;&amp;&gt;  &apos;&quot;&#xa;\"111"
        == Right ("<&>  '\"\n","111")

    tWord = TestCase $ do
      assertBool "tWord"
        $ eParse2 (many $ word <* spaces) "bird thug_a\nMAZ3 \n 13;;;"
        == Right (["bird","thug_a","MAZ3","13"],";;;")

    tComment = TestCase $ do
      assertBool "tComment" $ eParse2 comment "<!--xxx-->yyy"
        == Right (Comment,"yyy")

    tKeyValPair = TestCase $ do
      assertBool "tKeyValPair" $ eParse2 keyValPair "word=\"nacho\""
        == Right( ("word","nacho"), "")
      assertBool "list of key-value pairs; lexme"
        $ eParse2 (many $ lexeme keyValPair) "a=\"1\" b=\"2\""
        == Right( [("a","1"), ("b","2")], "")

    tStrip = TestCase $ do
      assertBool "strip -- symbols" 
        $ eParse (strip $ string "--") "-a--b-c--dd---"
        == Right                       "-ab-cdd-"

    tMlTag = TestCase $ do
      assertBool "parse mlTag" $ eParse mlTag "<hi a=\"1\" bb =\"22\" >"
        == Right ( MlTag "hi" True False -- WHY can't I dollar these parens?
                         ( Map.fromList [("a","1"), ("bb","22")] )
                 )
      assertBool "parse mlTag" $ eParse mlTag "</hi a=\"1\" bb =\"22\" />"
        == Right ( MlTag "hi" False True -- WHY can't I dollar these parens?
                         ( Map.fromList [("a","1"), ("bb","22")] )
                 )

  -- manip mmTags
    tMmTags = TestList [ TestLabel "tParseId" tParseId
                       , TestLabel "tMmNLab" tMmNLab ]

    tParseId = TestCase $ do
      assertBool "parse ID strings" $ parseId "ID_123" == Right 123

    tMmNLab = TestCase $ do
      assertBool "parse an xml TEXT tag into an TextTag"
        $ (readMmNLabUsf $ MlTag { 
          title = "node"
          , isStart = True
          , isEnd = True
          , mlMap = Map.fromList [
              ("CREATED","1449389483215")
            , ("ID","ID_1033943189")
            , ("LOCALIZED_STYLE_REF","AutomaticLayout.level,2")
            , ("MODIFIED","1449389512135")
            , ("TEXT","c3, gold")]})
        == MmNLab "c3, gold" 1033943189 (Just "AutomaticLayout.level,2")
             (read "2015-12-06 08:11:23 UTC") (read "2015-12-06 08:11:52 UTC")

  -- parse a whole file
    -- "tDwtSpec", by hand: works
      -- x <- mmToMlTags "data/root+7.mm"
      -- let y = fromRight $ dwtSpec $ fromRight x
      -- result has 8 lnodes and 9 edges, which is correct
      --        the two arrow edges are corect
      --        and the first three edges
      --        and the last tree edge

    tFrame = do 
      x <- mmToMlTags "data/root+22ish.mm" -- root+22ish because it needs styles
      let y = fromRight $ dwtSpec $ fromRight x
        in return (frame $ frameOrphanStyles y :: Either String DwtFrame)

    tLoadNodes = do 
      mls <- mmToMlTags "data/root+22ish.mm" -- again, needs styles
      let spec = fromRight $ dwtSpec $ fromRight mls
          fr = frame $ frameOrphanStyles spec :: Either String DwtFrame
        in return $ (loadNodes (spec, fromRight fr) :: Either String Mindmap)

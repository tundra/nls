import Test.HUnit
import qualified Data.Map as Map
import qualified Data.List as List
import qualified Value as V
import qualified Sexp as S
import qualified Eval as E
import qualified Method as M
import qualified Syntax as Sx

aLi = V.Literal
aIn v = aLi (vIn v)
aVa = V.Variable
aSq = V.Sequence
sId = S.Ident
sIn = S.Int
sLi = S.List
sWd = S.Word
tDm = S.DelimToken
tId = S.IdentToken
tIn = S.IntToken
tOp = S.OpToken
tPn = tId 0
tWd = S.WordToken
vIn = V.Int
vSt = V.Str
vNl = V.Null
vBn = V.Bool
fIn = E.FlatInt
fSt = E.FlatStr
fNl = E.FlatNull
fBn = E.FlatBool
fIe = E.FlatInstance
fHk = E.FlatHook

testUidStream = TestLabel "uidStream" (TestList
  [ check (i0 == i0)
  , check (not (i0 == i1))
  , check (not (i0 == i2))
  , check (not (i1 == i0))
  , check (i1 == i1)
  , check (not (i1 == i2))
  , check (not (i2 == i0))
  , check (not (i2 == i1))
  , check (i2 == i2)
  ])
  where
    check v = TestCase (assertBool "" v)
    s0 = E.uidStreamStart
    (i0, s1) = E.nextUidFromStream s0
    (i1, s2) = E.nextUidFromStream s1
    (i2, s3) = E.nextUidFromStream s2

testTokenize = TestLabel "tokenize" (TestList
  [ check [tPn "foo"] "$foo"
  , check [tOp "foo"] " .foo "
  , check [tOp "<+>"] " <+> "
  , check [tOp "!"] " ! "
  , check [tDm ":="] " := "
  , check [tDm ";", tDm ";"] " ;; "
  , check [tWd "foo"] " foo "
  , check [tIn 3] " 3 "
  , check [tPn "foo", tPn "bar", tPn "baz"] "$foo$bar$baz"
  , check [tPn "foo", tPn "bar", tPn "baz"] "$foo $bar $baz"
  , check [tId (-1) "foo", tId (-2) "bar", tId (-3) "baz"] "@foo @@bar @@@baz"
  , check [tId 0 "foo", tId 1 "bar", tId 2 "baz"] "$foo $$bar $$$baz"
  , check [tDm "(", tPn "foo", tDm ")"] "($foo)"
  ])
  where
    check expected input = TestLabel input testCase
      where
        (found, rest) = S.tokenize input
        testCase = TestCase (assertEqual "" expected found)

testSexpParsing = TestLabel "sexpParsing" (TestList
  [ check (sWd "foo") "foo"
  , check (sId 0 "foo") "$foo"
  , check (sIn 10) "10"
  , check (sLi []) "()"
  , check (sLi [sWd "foo"]) "(foo)"
  , check (sLi [sWd "foo", sWd "bar"]) "(foo bar)"
  , check (sLi [sWd "foo", sWd "bar", sWd "baz"]) "(foo bar baz)"
  , check (sLi [sLi [sLi []]]) "((()))"
  ])
  where
    check expected input = TestLabel input testCase
      where
        found = S.parseSexp input
        testCase = TestCase (assertEqual "" expected found)

testExprParsing = TestLabel "exprParsing" (TestList
  [ check (aVa 0 (vSt "foo")) "$foo"
  , check (aIn 10) "10"
  , check (aLi vNl) "null"
  , check (aLi (vBn True)) "true"
  , check (aLi (vBn False)) "false"
  , check (aLi vNl) "(;)"
  , check (aIn 1) "(; 1)"
  , check (aSq [aIn 1, aIn 2]) "(; 1 2)"
  ])
  where
    check expected input = TestLabel input testCase
      where
        found = V.parseExpr input
        testCase = TestCase (assertEqual "" expected found)

-- Join a list of lines into a single string. Similar to unlines but without the
-- newline char which confuses the regexps for some reason.
multiline = foldr (++) ""

testEvalExpr = TestLabel "evalExpr" (TestList
  -- Primitive ops
  [ check fNl [] "(;)"
  , check fNl [] "null"
  , check (fBn True) [] "true"
  , check (fBn False) [] "false"
  , check (fIn 0) [] "0"
  , check (fIn 1) [] "1"
  , check (fIn 100) [] "100"
  , check (fIn 5) [] "(; 5)"
  , check (fIn 7) [] "(; 6 7)"
  , check (fIn 10) [] "(; 8 9 10)"
  -- Hooks
  , check (fHk V.LogHook) [] "$log"
  , check (fBn True) [fBn True] "(! $log true)"
  , check (fBn False) [fBn False] "(! ! $log false)"
  , check (fIn 4) [fIn 2, fIn 3, fIn 4] "(; (! $log 2) (! $log 3) (! $log 4))"
  , check (fIn 5) [] "(! + 2 3)"
  , check (fIn (-1)) [] "(! - 2 3)"
  -- Bindings
  , check (fIn 8) [] "(def $a := 8 in $a)"
  , check (fIn 9) [] "(def $a := 9 in (def $b := 10 in $a))"
  , check (fIn 12) [] "(def $a := 11 in (def $b := 12 in $b))"
  , check (fIn 13) [] "(def $a := 13 in (def $b := $a in $b))"
  , check (fIn 15) [fIn 14, fIn 15, fIn 16] (multiline
      [ "(def $a := (! $log 14) in"
      , "  (def $b := (! $log 15) in"
      , "    (; (! $log 16)"
      , "       $b)))"
      ])
  , check (fIn 18) [fIn 17] (multiline
      [ "(def $a := 17 in (;"
      , "  (! $log $a)"
      , "  (def $a := 18 in"
      , "    $a)))"
      ])
  -- Objects
  , check (fIe (V.Uid 0) V.emptyVaporInstanceState) [] "(new)"
  -- Escapes
  , check (fIn 5) [] "(with_escape $e do (! $e 5))"
  , check (fIn 6) [] "(with_escape $e do (! $log (! $e 6)))"
  , check (fIn 8) [fIn 7] (multiline
      [ "(with_escape $e do (;"
      , "  (! $log 7)"
      , "  (! $e 8)"
      , "  (! $log 9))))"
      ])
  , check (fIn 10) [fIn 10, fIn 11, fIn 10] (multiline
      [ "(! $log"
      , "  (after"
      , "    (! $log 10)"
      , "   ensure"
      , "    (! $log 11)))"
      ])
  , check (fIn 20) [fIn 12, fIn 13, fIn 16, fIn 19] (multiline
      [ "(with_escape $e do (;"
      , "  (! $log 12)"
      , "  (with_escape $f do"
      , "     (after (;"
      , "       (! $log 13)"
      , "       (! $e 14)"
      , "       (! $log 15))"
      , "      ensure (;"
      , "       (! $log 16)"
      , "       (! $f 17)"
      , "       (! $log 18))))"
      , "  (! $log 19)"
      , "  (! $e 20)"
      , "  (! $log 21)))"
      ])
  , check (fIn 26) [fIn 22, fIn 23, fIn 24, fIn 25, fIn 28, fIn 29, fIn 30] (multiline
      [ "(with_escape $e do (;"
      , "  (! $log 22)"
      , "  (after (;"
      , "    (! $log 23)"
      , "    (after (;"
      , "      (! $log 24)"
      , "      (after (;"
      , "        (! $log 25)"
      , "        (! $e 26)"
      , "        (! $log 27))"
      , "       ensure"
      , "        (! $log 28)))"
      , "     ensure"
      , "       (! $log 29)))"
      , "   ensure"
      , "     (! $log 30)))))"
      ])
  -- , check (fIn 5) [] "(+ 2 3)"
  -- Failures
  , checkFail (E.UnboundVariable (vSt "foo")) [] "$foo"
  , checkFail (E.UnboundVariable (vSt "b")) [] "(def $a := 9 in $b)"
  , checkFail (E.UnboundVariable (vSt "a")) [] "(def $a := $a in $b)"
  , checkFail (E.UnboundVariable (vSt "x")) [vIn 8] (multiline
      [ "(; (! $log 8)"
      , "   $x"
      , "   (! $log 9))"
      ])
  , checkFail E.AbsentNonLocal [] "(def $f := (with_escape $e do $e) in (! $f 5))"
  ])
  where
    -- Check that evaluation succeeds.
    check expected expLog input = TestLabel input testCase
      where
        ast = V.parseExpr input
        result = E.evalFlat testBehavior ast
        testCase = case result of
          E.Normal (found, log) -> checkResult found log
          E.Failure cause _ -> TestCase (assertFailure ("Unexpected failure, " ++ show cause))
        checkResult found foundLog = (TestList
          [ TestCase (assertEqual "" expected found)
          , TestCase (assertEqual "" expLog foundLog)
          ])
    -- Check that evaluation fails
    checkFail expected expLog input = TestLabel input testCase
      where
        ast = V.parseExpr input
        result = E.evalFlat testBehavior ast
        testCase = case result of
          E.Normal (found, log) -> TestCase (assertFailure ("Expected failure, found " ++ show found))
          E.Failure cause foundLog -> checkFailure cause foundLog
        checkFailure cause foundLog = (TestList
          [ TestCase (assertEqual "" expected cause)
          , TestCase (assertEqual "" expLog foundLog)
          ])
    testBehavior = V.Methodspace TestHierarchy M.emptySigTree

testEvalProgram = TestLabel "evalProgram" (TestList
  [ check (fSt "Integer") [] "(program (do (! .display_name $type (! $type 3))))"
  , check (fSt "Null") [] "(program (do (! .display_name $type (! $type null))))"
  , check (fSt "Bool") [] "(program (do (! .display_name $type (! $type true))))"
  , check (fSt "Bool") [] "(program (do (! .display_name $type (! $type false))))"
  , check (fIn 4) [] (multiline
      [ "(program"
      , "  (def $x := 4)"
      , "  (do $x))"
      ])
  , check (fIn 8) [fIn 0, fIn 2, fIn 1] (multiline
      [ "(program"
      , "  (def $x := (; (! $log 0) $y (! $log 1) $y))"
      , "  (def $y := (; (! $log 2) 8))"
      , "  (do $x))"
      ])
  , check fNl [fIn 5, fIn 6, fIn 7] (multiline
      [ "(program"
      , "  (def $a := (! $log 5))"
      , "  (def $b := (! $log 6))"
      , "  (def $c := (! $log 7)))"
      ])
  {-
  , check fNl [fIn 7, fIn 6, fIn 5] (multiline
      [ "(program"
      , "  (def $a := (! $log 5))"
      , "  (def @a := (! $log 6))"
      , "  (def @@a := (! $log 7)))"
      ])
  -}
  , checkFail (E.CircularReference (vSt "x")) [] (multiline
      [ "(program"
      , "  (def $x := $y)"
      , "  (def $y := $z)"
      , "  (def $z := $x)"
      , "  (do $x))"
      ])
  , checkFail (E.UnboundVariable (vSt "a")) [] (multiline
      [ "(program"
      , "  (def $x := (def $a := 9 in $y))"
      , "  (def $y := $a)"
      , "  (do $x))"
      ])
  ])
  where
    check expected expLog input = TestLabel input testCase
      where
        ast = V.parseProgram input
        result = E.evalProgramFlat ast
        testCase = case result of
          E.Normal (found, log) -> checkResult found log
          E.Failure cause _ -> TestCase (assertFailure ("Unexpected failure, " ++ show cause))
        checkResult found foundLog = (TestList
          [ TestCase (assertEqual "" expected found)
          , TestCase (assertEqual "" expLog foundLog)
          ])
    checkFail expected expLog input = TestLabel input testCase
      where
        ast = V.parseProgram input
        result = E.evalProgramFlat ast
        testCase = case result of
          E.Normal (found, log) -> TestCase (assertFailure ("Expected failure, found " ++ show found))
          E.Failure cause foundLog -> checkFailure cause foundLog
        checkFailure cause foundLog = (TestList
          [ TestCase (assertEqual "" expected cause)
          , TestCase (assertEqual "" expLog foundLog)
          ])


testMatchOrder = TestLabel "matchOrder" (TestList
  [ check (M.ScoreEq < M.ScoreIs 0)
  , check (M.ScoreIs 0 < M.ScoreIs 1)
  , check (M.ScoreIs 100 < M.ScoreIs 101)
  , check (M.ScoreIs 65536 < M.ScoreAny)
  ])
  where
    check v = TestCase (assertBool "" v)

-- An inheritance hiararchy that only gives nontrivial types to ints and where
-- the relationship between types is described explicitly by the map below.
data TestHierarchy = TestHierarchy

testInheritance = Map.fromList (
  -- 2 <: 1 <: 0
  [ (2, [1])
  , (1, [0])
  -- 14 <: 13 <: 12 <: 11 <: 0, also 14 <: 2 <: 1 <: 0
  , (14, [13, 2])
  , (13, [12])
  , (12, [11])
  , (11, [0])
  ])

instance M.TypeHierarchy TestHierarchy where
  typeOf _ (V.Int n) = V.Uid n
  typeOf _ _ = V.Uid 0
  superTypes _ (V.Uid n) = map V.Uid (Map.findWithDefault [] n testInheritance)

testSingleGuards = TestLabel "singleGuards" (TestList
  [ check M.ScoreAny V.Any (V.Str "foo")
  , check M.ScoreAny V.Any (V.Int 0)
  , check M.ScoreAny V.Any V.Null
  , check M.ScoreAny V.Any (V.Bool True)
  , check M.ScoreNone (V.Eq V.Null) (V.Str "foo")
  , check M.ScoreNone (V.Eq V.Null) (V.Int 0)
  , check M.ScoreEq (V.Eq V.Null) V.Null
  , check (M.ScoreIs 0) (V.Is (V.Uid 2)) (V.Int 2)
  , check (M.ScoreIs 1) (V.Is (V.Uid 1)) (V.Int 2)
  , check (M.ScoreIs 2) (V.Is (V.Uid 0)) (V.Int 2)
  , check M.ScoreNone (V.Is (V.Uid 2)) (V.Int 1)
  , check (M.ScoreIs 0) (V.Is (V.Uid 1)) (V.Int 1)
  , check (M.ScoreIs 1) (V.Is (V.Uid 0)) (V.Int 1)
  , check M.ScoreNone (V.Is (V.Uid 2)) (V.Int 0)
  , check M.ScoreNone (V.Is (V.Uid 1)) (V.Int 0)
  , check (M.ScoreIs 0) (V.Is (V.Uid 0)) (V.Int 0)
  , check (M.ScoreIs 3) (V.Is (V.Uid 0)) (V.Int 14)
  , check (M.ScoreIs 3) (V.Is (V.Uid 0)) (V.Int 13)
  , check (M.ScoreIs 2) (V.Is (V.Uid 0)) (V.Int 12)
  , check M.ScoreNone (V.Is (V.Uid 0)) (V.Int 15)
  ])
  where
    check expected guard value = TestCase (assertEqual "" expected result)
      where
        result = M.matchGuard TestHierarchy guard value

maybeMap f (Just v) = Just (f v)
maybeMap _ Nothing = Nothing

sAn = M.ScoreAny
sEq = M.ScoreEq
sIs = M.ScoreIs

-- Parse a signature string (say "(1 2: *, 3 4: =8; 5, 6: *)") into a cut
-- signature value. Writing out the signature values becomes pretty horrible as
-- they become long, this makes them more manageable.
parseCutSignature str = result
  where
    (tokens, _) = S.tokenize str
    parseList ((S.DelimToken "("):rest) params cuts = parseList rest params cuts
    parseList ((S.DelimToken ","):rest) params cuts = parseList rest params cuts
    parseList ((S.DelimToken ";"):rest) params cuts = parseList rest [] ((reverse params):cuts)
    parseList [S.DelimToken ")"] [] cuts = (reverse cuts, [])
    parseList list@[S.DelimToken ")"] params cuts = parseList ((S.DelimToken ";"):list) params cuts
    parseList list params cuts = parseParam list [] V.Any params cuts
    parseParam ((S.IntToken n):rest) tags guard params cuts
      = parseParam rest ((V.Int n):tags) guard params cuts
    parseParam ((S.OpToken ":"):(S.OpToken "*"):rest) tags _ params cuts
      = parseParam rest tags V.Any params cuts
    parseParam ((S.OpToken ":"):(S.OpToken "="):(S.IntToken n):rest) tags _ params cuts
      = parseParam rest tags (V.Eq (V.Int n)) params cuts
    parseParam ((S.OpToken ":"):(S.WordToken "is"):(S.IntToken n):rest) tags _ params cuts
      = parseParam rest tags (V.Is (V.Uid n)) params cuts
    parseParam rest tags guard params cuts = parseList rest (param:params) cuts
      where
        param = V.Parameter tags guard
    (result, _) = parseList tokens [] []

-- Parse a regular non-cut signature. Having cuts is still allowed, they just
-- get smushed together into the result.
parseSignature str = concat (parseCutSignature str)

testSignatureMatching = TestLabel "signatureMatching" (TestList
  [ check Nothing "(1: *, 2: *)" [(1, 3)]
  , check Nothing "(1: *, 2: *)" [(2, 3)]
  , check Nothing "(1: *, 2: *)" [(3, 3)]
  , check (Just [(1, sAn)]) "(1: *)" [(1, 3)]
  , check (Just [(1, sAn)]) "(1: *)" [(1, 3), (2, 4)]
  , check (Just [(1, sAn)]) "(1: *)" [(2, 5), (1, 6)]
  , check (Just [(1, sEq)]) "(1: =3)" [(1, 3)]
  , check Nothing "(1: =4)" [(1, 3)]
  , check (Just [(1, sIs 0)]) "(1: is 2)" [(1, 2)]
  , check (Just [(1, sIs 1)]) "(1: is 1)" [(1, 2)]
  , check (Just [(1, sIs 2)]) "(1: is 0)" [(1, 2)]
  , check (Just [(1, sAn), (2, sAn), (3, sAn)]) "(1: *, 2: *, 3: *)" [(1, 7), (2, 7), (3, 7)]
  , check (Just [(1, sAn), (3, sAn)]) "(1 2: *, 3 4: *)" [(1, 10), (3, 11)]
  , check (Just [(2, sAn), (3, sAn)]) "(1 2: *, 3 4: *)" [(2, 12), (3, 13)]
  , check (Just [(1, sAn), (4, sAn)]) "(1 2: *, 3 4: *)" [(1, 14), (4, 15)]
  , check (Just [(2, sAn), (4, sAn)]) "(1 2: *, 3 4: *)" [(2, 16), (4, 17)]
  ])
  where
    check expList sigStr invList = TestCase (assertEqual "" expected result)
      where
        signature = (parseSignature sigStr)
        invocation = Map.fromList [(V.Int key, V.Int value) | (key, value) <- invList]
        result = M.matchSignature TestHierarchy signature invocation
        expected = maybeMap wrapExpected expList
        wrapExpected scores = M.ScoreRecord [(V.Int tag, score) | (tag, score) <- scores]

testCompareScoreRecords = TestLabel "compareScoreRecords" (TestList
  [ check equal [] [] []
  , check equal [(1, sAn)] [(1, sAn)] [(1, sAn)]
  , check better [(1, sAn), (2, sAn)] [(1, sAn), (2, sAn)] [(1, sAn)]
  , check worse [(1, sAn), (2, sAn)] [(1, sAn)] [(1, sAn), (2, sAn)]
  , check equal [(1, sAn), (2, sAn)] [(1, sAn), (2, sAn)] [(1, sAn), (2, sAn)]
  , check equal [(1, sAn), (2, sAn)] [(1, sAn), (2, sAn)] [(2, sAn), (1, sAn)]
  , check ambiguous [(1, sAn), (2, sAn), (3, sAn)] [(1, sAn), (2, sAn)] [(1, sAn), (3, sAn)]
  ])
  where
    equal = M.ScoreRecordOrdering False False
    worse = M.ScoreRecordOrdering False True
    better = M.ScoreRecordOrdering True False
    ambiguous = M.ScoreRecordOrdering True True
    check expectedOrder expectedRecord a b = (TestList
      [ TestCase (assertEqual "" expectedOrder foundOrder)
      , TestCase (assertEqual "" (toRecord expectedRecord) foundRecord)
      ])
      where
        (foundOrder, foundRecord) = M.compareScoreRecords (toRecord a) (toRecord b)
        toRecord elms = M.ScoreRecord [(V.Int n, score) | (n, score) <- elms]

parseSigAssoc input = map parseEntry input
  where
    parseEntry (str, value) = (parseSignature str, value)

testSigAssocLookup = TestLabel "sigAssocLookup" (TestList
  [ check (M.Unique 1 [V.Int 1]) [("(1: *)", 1)] [(1, 0)]
  , check (M.Multiple [10, 11]) [("(1: *)", 10), ("(1: *)", 11)] [(1, 0)]
  , check (M.Unique 12 [V.Int 1]) [("(1: *)", 12)] [(1, 0), (2, 1)]
  , check (M.Unique 13 [V.Int 2]) [("(2: *)", 13)] [(1, 0), (2, 1)]
  , check (M.Unique 14 [V.Int 1, V.Int 2]) [("(1: *, 2: *)", 14)] [(1, 0), (2, 1)]
  , check (M.Unique 15 [V.Int 1, V.Int 2]) [("(1: *, 2: *)", 15), ("(1: *)", 16)] [(1, 0), (2, 1)]
  , check (M.Unique 17 [V.Int 1, V.Int 2]) [("(1: *, 2: *)", 17), ("(1: *)", 18), ("(2: *)", 19)] [(1, 0), (2, 1)]
  , check M.Ambiguous [("(1: *)", 20), ("(2: *)", 21)] [(1, 0), (2, 1)]
  , check (M.Unique 23 [V.Int 2]) [("(1: *)", 22), ("(2: *)", 23)] [(2, 1)]
  , check M.None [("(1: *)", 22), ("(3: *)", 23)] [(2, 1)]
  ])
  where
    check expected assocList argList = TestCase (assertEqual "" expected found)
      where
        assoc = parseSigAssoc assocList
        args = Map.fromList [(V.Int tag, V.Int value) | (tag, value) <- argList]
        found = M.sigAssocLookup TestHierarchy args assoc

-- Replaces the n'th element in the given list with the given value.
replace [] _ _ = []
replace (x:rest) 0 y = y:rest
replace (x:rest) n y = x:(replace rest (n - 1) y)

-- Parses a list of cut signature strings into a signature tree.
parseSigTree input = foldr parseAndMerge M.emptySigTree input
  where
    parseAndMerge (str, value) tree = merge tree (parseCutSignature str) value
    -- Merging into an empty tree node just replaces its value. There is no case
    -- for merging into a non-empty one because that's not really meaningful.
    merge (V.SigTree Nothing children) [] value = V.SigTree (Just value) children
    -- Merging into an existing tree. Here we look for an existing child that
    -- matches exactly and if there is one we merge into that. Otherwise we add
    -- a fresh child.
    merge (V.SigTree treeValue children) (next:rest) value = newTree
      where
        childSameAsNext (sig, tree) = (sig == next)
        newChildren = case List.findIndex childSameAsNext children of
          Nothing -> (next, merge M.emptySigTree rest value):children
          Just i -> replace children i (next, mergedChild)
            where
              (sig, child) = children !! i
              mergedChild = merge child rest value
        newTree = V.SigTree treeValue newChildren

testSigTreeLookup = TestLabel "sigTreeLookup" (TestList
  [ check (Just 1) emptyTree []
  , check Nothing anyTree [(1, 0)]
  , check (Just 1) anyTree [(1, 0), (2, 0)]
  , check (Just 2) anyTree [(1, 0), (2, 0), (3, 0)]
  , check Nothing anyTree [(1, 0), (2, 0), (3, 0), (4, 0)]
  , check (Just 3) anyTree [(1, 0), (2, 0), (4, 0)]
  , check (Just 4) anyTree [(1, 0), (2, 0), (5, 0)]
  , check (Just 1) eqTree [(1, 7)]
  , check (Just 2) eqTree [(1, 8)]
  , check (Just 3) eqTree [(1, 9)]
  , check (Just 4) eqTree [(1, 9), (2, 10)]
  , check Nothing eqTree [(1, 6)]
  , check (Just 1) flatIsTree [(1, 0)]
  , check (Just 2) flatIsTree [(1, 1)]
  , check (Just 3) flatIsTree [(1, 2)]
  , check (Just 4) flatIsTree [(1, 3)]
  , check (Just 00) fullUncutIsTree [(1, 0), (2, 0)]
  , check (Just 10) fullUncutIsTree [(1, 1), (2, 0)]
  , check (Just 20) fullUncutIsTree [(1, 2), (2, 0)]
  , check (Just 01) fullUncutIsTree [(1, 0), (2, 1)]
  , check (Just 11) fullUncutIsTree [(1, 1), (2, 1)]
  , check (Just 21) fullUncutIsTree [(1, 2), (2, 1)]
  , check (Just 02) fullUncutIsTree [(1, 0), (2, 2)]
  , check (Just 12) fullUncutIsTree [(1, 1), (2, 2)]
  , check (Just 22) fullUncutIsTree [(1, 2), (2, 2)]
  , check (Just 00) fullCutIsTree [(1, 0), (2, 0)]
  , check (Just 10) fullCutIsTree [(1, 1), (2, 0)]
  , check (Just 20) fullCutIsTree [(1, 2), (2, 0)]
  , check (Just 01) fullCutIsTree [(1, 0), (2, 1)]
  , check (Just 11) fullCutIsTree [(1, 1), (2, 1)]
  , check (Just 21) fullCutIsTree [(1, 2), (2, 1)]
  , check (Just 02) fullCutIsTree [(1, 0), (2, 2)]
  , check (Just 12) fullCutIsTree [(1, 1), (2, 2)]
  , check (Just 22) fullCutIsTree [(1, 2), (2, 2)]
  , check (Just 00) partialUncutIsTree [(1, 0), (2, 0)]
  , check (Just 10) partialUncutIsTree [(1, 1), (2, 0)]
  , check (Just 20) partialUncutIsTree [(1, 2), (2, 0)]
  , check (Just 01) partialUncutIsTree [(1, 0), (2, 1)]
  , check Nothing partialUncutIsTree [(1, 1), (2, 1)]
  , check Nothing partialUncutIsTree [(1, 2), (2, 1)]
  , check (Just 02) partialUncutIsTree [(1, 0), (2, 2)]
  , check Nothing partialUncutIsTree [(1, 1), (2, 2)]
  , check Nothing partialUncutIsTree [(1, 2), (2, 2)]
  , check (Just 00) partialCutIsTree [(1, 0), (2, 0)]
  , check (Just 10) partialCutIsTree [(1, 1), (2, 0)]
  , check (Just 20) partialCutIsTree [(1, 2), (2, 0)]
  , check (Just 01) partialCutIsTree [(1, 0), (2, 1)]
  , check (Just 10) partialCutIsTree [(1, 1), (2, 1)]
  , check (Just 20) partialCutIsTree [(1, 2), (2, 1)]
  , check (Just 02) partialCutIsTree [(1, 0), (2, 2)]
  , check (Just 10) partialCutIsTree [(1, 1), (2, 2)]
  , check (Just 20) partialCutIsTree [(1, 2), (2, 2)]
  ])
  where
    check expected sigtree argList = TestCase (assertEqual "" expected found)
      where
        found = M.sigTreeLookup TestHierarchy sigtree args
        args = Map.fromList [(V.Int key, V.Int value) | (key, value) <- argList]
    anyTree = parseSigTree
      [ ("(1: *; 2: *)", 1)
      , ("(1: *; 2: *; 3: *)", 2)
      , ("(1: *; 2: *; 4: *)", 3)
      , ("(1: *; 2: *; 5: *)", 4)
      ]
    eqTree = parseSigTree
      [ ("(1: =7)", 1)
      , ("(1: =8)", 2)
      , ("(1: =9)", 3)
      , ("(1: =9, 2: =10)", 4)
      ]
    flatIsTree = parseSigTree
      [ ("(1: is 0)", 1)
      , ("(1: is 1)", 2)
      , ("(1: is 2)", 3)
      , ("(1: *)", 4)
      ]
    fullUncutIsTree = parseSigTree
      [ ("(1: is 0, 2: is 0)", 00)
      , ("(1: is 1, 2: is 0)", 10)
      , ("(1: is 2, 2: is 0)", 20)
      , ("(1: is 0, 2: is 1)", 01)
      , ("(1: is 1, 2: is 1)", 11)
      , ("(1: is 2, 2: is 1)", 21)
      , ("(1: is 0, 2: is 2)", 02)
      , ("(1: is 1, 2: is 2)", 12)
      , ("(1: is 2, 2: is 2)", 22)
      ]
    fullCutIsTree = parseSigTree
      [ ("(1: is 0; 2: is 0)", 00)
      , ("(1: is 1; 2: is 0)", 10)
      , ("(1: is 2; 2: is 0)", 20)
      , ("(1: is 0; 2: is 1)", 01)
      , ("(1: is 1; 2: is 1)", 11)
      , ("(1: is 2; 2: is 1)", 21)
      , ("(1: is 0; 2: is 2)", 02)
      , ("(1: is 1; 2: is 2)", 12)
      , ("(1: is 2; 2: is 2)", 22)
      ]
    partialUncutIsTree = parseSigTree
      [ ("(1: is 0, 2: is 0)", 00)
      , ("(1: is 1, 2: is 0)", 10)
      , ("(1: is 2, 2: is 0)", 20)
      , ("(1: is 0, 2: is 1)", 01)
      , ("(1: is 0, 2: is 2)", 02)
      ]
    partialCutIsTree = parseSigTree
      [ ("(1: is 0; 2: is 0)", 00)
      , ("(1: is 1; 2: is 0)", 10)
      , ("(1: is 2; 2: is 0)", 20)
      , ("(1: is 0; 2: is 1)", 01)
      , ("(1: is 0; 2: is 2)", 02)
      ]
    emptyTree = parseSigTree [("()", 1)]

xIn = Sx.Infix
xIm = Sx.Implicit
xSx = Sx.Suffix
xPx = Sx.Prefix

testClassify = TestLabel "classify" (TestList
  [ check (Just [xIn "x"]) ["x"]
  , check (Just [xIm]) []
  , check (Just [xSx "a", xIn "x"]) ["a", "x"]
  , check (Just [xSx "a", xIn "x", xPx "b"]) ["a", "x", "b"]
  , check (Just [xSx "a", xSx "b", xIn "x"]) ["a", "b", "x"]
  , check (Just [xIn "x", xPx "b", xPx "a"]) ["x", "b", "a"]
  , check (Just [xIn "x", xPx "a", xPx "b"]) ["x", "a", "b"]
  , check Nothing ["x", "x"]
  ])
  where
    check expected input = TestLabel "" testCase
      where
        found = Sx.classify input
        testCase = TestCase (assertEqual "" expected found)

testAll = runTestTT (TestList
  [ testTokenize
  , testSexpParsing
  , testExprParsing
  , testUidStream
  , testEvalExpr
  , testMatchOrder
  , testSingleGuards
  , testSignatureMatching
  , testCompareScoreRecords
  , testSigAssocLookup
  , testSigTreeLookup
  , testEvalProgram
  , testClassify
  ])

main = testAll

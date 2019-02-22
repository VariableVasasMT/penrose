{-# LANGUAGE DeriveGeneric #-}

module SubstanceJSON where

import GHC.Generics
import Data.Aeson
import Debug.Trace
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as L

import qualified Env as E
import Substance

-------------------------------------------------------
-- | JSON schemas and derivations using Aeson

data FunctionSchema = FunctionSchema {
     varName :: String,
     fname :: String,
     fargNames :: [String]
} deriving (Generic, Show)

data PredicateSchema = PredicateSchema {
     pname :: String,
     pargNames :: [String]
} deriving (Generic, Show)

data ConstraintSchema = ConstraintSchema {
     functions :: [FunctionSchema],
     predicates :: [PredicateSchema]
} deriving (Generic, Show)

data ObjectSchema = ObjectSchema {
     objType :: String,
     objName :: String
} deriving (Generic, Show)

data SubSchema = SubSchema {
           objects :: [ObjectSchema]
         , constraints  :: ConstraintSchema
         } deriving (Generic, Show)

instance ToJSON ObjectSchema where
             toEncoding = genericToEncoding defaultOptions

instance FromJSON ObjectSchema

instance ToJSON PredicateSchema where
             toEncoding = genericToEncoding defaultOptions

instance FromJSON PredicateSchema

instance ToJSON FunctionSchema where
             toEncoding = genericToEncoding defaultOptions

instance FromJSON FunctionSchema

instance ToJSON ConstraintSchema where
             toEncoding = genericToEncoding defaultOptions

instance FromJSON ConstraintSchema

instance ToJSON SubSchema where
             toEncoding = genericToEncoding defaultOptions

instance FromJSON SubSchema

-------------------------------------------------------

targToSchema :: E.Arg -> String
targToSchema (E.AVar (E.VarConst s)) = s
targToSchema (E.AT t) = tToSchema t

tToSchema :: E.T -> String
tToSchema (E.TTypeVar typeVar) = E.typeVarName typeVar
tToSchema (E.TConstr typeCtorApp) = 
          let ctorString = E.nameCons typeCtorApp 
              args = E.argCons typeCtorApp in
          case args of
          [] -> ctorString -- "Set"
          _ -> ctorString ++ "(" ++ (L.intercalate ", " $ map targToSchema args) ++ ")" -- "List(Bounce)"

exprToSchema :: Expr -> String
exprToSchema (VarE (E.VarConst v)) = v
exprToSchema _ = error "Cannot convert anonymous expressions in function/val ctor arguments to JSON; must name them first"

prednameToSchema :: PredicateName -> String
prednameToSchema (PredicateConst s) = s

predargToSchema :: PredArg -> String
predargToSchema (PE expr) = exprToSchema expr
predargToSchema (PP pred) = error "Cannot convert nested predicate in predicate argument to JSON"

-- | Convert a Substance statement to a JSON format and adds it to the right list
-- | Note: do not rely on ordering in JSON, as this function does not guarantee preserving Substance program order.
-- | However, we do guarantee preserving argument order in function/valcons/predicate applications.
toSchema ::
  ([ObjectSchema], [FunctionSchema], [PredicateSchema])
  -> SubStmt -> ([ObjectSchema], [FunctionSchema], [PredicateSchema])
toSchema acc@(objSchs, fnSchs, predSchs) subLine =
         case subLine of
         Decl t (E.VarConst v) -> 
              let res = ObjectSchema { objType = tToSchema t, objName = v }
              in (res : objSchs, fnSchs, predSchs)
         DeclList t vs ->
              let decls = map (\v -> Decl t v) vs
              in foldl toSchema acc decls

         Bind (E.VarConst v) (ApplyFunc f) -> 
              let res = FunctionSchema { varName = v, fname = nameFunc f, fargNames = map exprToSchema $ argFunc f }
              in (objSchs, res : fnSchs, predSchs)
         Bind (E.VarConst v) (ApplyValCons f) -> 
              let res = FunctionSchema { varName = v, fname = nameFunc f, fargNames = map exprToSchema $ argFunc f }
              in (objSchs, res : fnSchs, predSchs)

         ApplyP p -> 
              let res = PredicateSchema { pname = prednameToSchema $ predicateName p, pargNames = map predargToSchema $ predicateArgs p }
              in (objSchs, fnSchs, res : predSchs)

         -- TODO: these forms are not sent to plugins
         Bind _ (VarE _) -> trace "WARNING: not sending Substance form to plugin!" acc
         Bind _ (DeconstructorE _) -> trace "WARNING: not sending Substance form to plugin!" acc
         EqualE _ _ -> trace "WARNING: not sending Substance form to plugin!" acc
         EqualQ _ _ -> trace "WARNING: not sending Substance form to plugin!" acc

         LabelDecl _ _ -> acc
         AutoLabel _ -> acc
         NoLabel _ -> acc

-- | Turn a Substance prog into the schema format defined above
subToSchema :: SubProg -> SubSchema
subToSchema prog = 
            let (objSchs, fnSchs, predSchs) = foldl toSchema ([], [], []) prog
            in SubSchema { 
                      objects = objSchs,
                      constraints = ConstraintSchema {
                                  functions = fnSchs,
                                  predicates = predSchs
                      }
            }

-- | This is the main function for converting a parsed Substance program to JSON format, called in ShadowMain
writeSubstanceToJSON :: FilePath -> SubOut -> IO ()
writeSubstanceToJSON file (SubOut subprog envs labels) = do
     let substanceSchema = subToSchema subprog
     let bytestr         = encode substanceSchema
     BL.writeFile file bytestr

--------------------------------------------------------

-- | Test writing a Substance program in JSON format
main :: IO ()
main = do
     -- let subProg = "Set A\nSet B\n IsSubset(A,B)\nSet C\nC := Union(A, B)\n\nPoint p\n PointIn(C, p)\nC := AddPoint(p, C)\n\nAutoLabel All"
     let testFile = "testSubstanceJSON.json"
     let info = SubSchema { objects = [ ObjectSchema { objType = "Set", objName = "A" } ], 
                            constraints = ConstraintSchema
                                          { functions = [ FunctionSchema { varName = "C",
                                                      fname ="Union", 
                                                      fargNames =["A", "B"] } ],
                                            predicates = [ PredicateSchema { 
                                                       pname = "IsSubset", pargNames = ["C", "p"]}]
                                          }
                          }
     let res = encode info
     BL.writeFile testFile res

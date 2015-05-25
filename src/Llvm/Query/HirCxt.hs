{-# LANGUAGE RecordWildCards #-}
module Llvm.Query.HirCxt where
import qualified Llvm.Hir.Data.Inst as Ci
import qualified Data.Map as M
import Llvm.Hir.Data
import Llvm.Hir.Data.DataLayoutInfo
import Llvm.Hir.Print

data TypeEnv = TypeEnv { dataLayout :: DataLayoutInfo
                       , targetTriple :: Ci.TargetTriple
                       , typedefs :: M.Map Ci.LocalId Ci.Dtype
                       , opaqueTypeDefs :: M.Map Ci.LocalId (Ci.Type OpaqueB D)
                       } deriving (Eq, Ord, Show)

data FunCxt = FunCxt { funName :: String 
                     , funParameters :: M.Map Ci.LocalId Ci.Dtype
                     } deriving (Eq, Ord, Show)

data GlobalCxt = GlobalCxt { typeEnv :: TypeEnv
                           , globals :: M.Map Ci.GlobalId (TlGlobal, Ci.Dtype)
                           , functions :: M.Map Ci.GlobalId Ci.FunctionPrototype
                           , attributes :: M.Map Word32 [FunAttr]
                           } deriving (Eq, Ord, Show)
                                
data IrCxt = IrCxt { globalCxt :: GlobalCxt
                   , funCxt :: FunCxt
                   } deriving (Eq, Ord, Show)

irCxtOfModule :: Module a -> IrCxt
irCxtOfModule (Module tl) = 
  let [ToplevelDataLayout (TlDataLayout dl)] = filter (\x -> case x of
                                                          ToplevelDataLayout _ -> True
                                                          _ -> False
                                                      ) tl
      [ToplevelTriple (TlTriple tt)] = filter (\x -> case x of
                                                  ToplevelTriple _ -> True
                                                  _ -> False
                                              ) tl
      tdefs = fmap (\(ToplevelTypeDef td) -> case td of
                       TlDatTypeDef lhs def -> (lhs, def)) 
              $ filter (\x -> case x of
                           ToplevelTypeDef (TlDatTypeDef _ _) -> True
                           _ -> False
                       ) tl
      glbs = fmap (\(ToplevelGlobal g@(TlGlobalDtype lhs _ _ _ _ _ _ _ _ t _ _ _ _)) -> (lhs, (g,t))) 
             $ filter (\x -> case x of
                          ToplevelGlobal _ -> True
                          _ -> False
                      ) tl
      funs = fmap (\tl -> case tl of
                      ToplevelDeclare (TlDeclare fp@FunctionPrototype{..}) -> (fp_fun_name, fp)
                      ToplevelDefine (TlDefine fp@FunctionPrototype{..} _ _) -> (fp_fun_name, fp)
                  )
             $ filter (\x -> case x of
                          ToplevelDeclare _ -> True
                          ToplevelDefine{..} -> True
                          _ -> False
                      ) tl
      attrs = fmap (\(ToplevelAttribute (TlAttribute n l)) -> (n, l))
              $ filter (\x -> case x of
                           ToplevelAttribute _ -> True
                           _ -> False
                       ) tl             
  in IrCxt { globalCxt = GlobalCxt { typeEnv = TypeEnv { dataLayout = getDataLayoutInfo dl
                                                       , targetTriple = tt
                                                       , typedefs = M.fromList tdefs
                                                       , opaqueTypeDefs = M.empty
                                                       }
                                   , globals = M.fromList glbs
                                   , functions = M.fromList funs
                                   , attributes = M.fromList attrs
                                   }
           , funCxt = FunCxt { funName = ""
                             , funParameters = M.empty
                             }
           }

instance IrPrint TypeEnv where
  printIr (TypeEnv dl tt td otd) = text "datalayout:" <+> printIr dl
                               $+$ text "triple:" <+> printIr tt
                               $+$ text "typedefs:" <+> printIr td
                               $+$ text "opaqueTypedefs:" <+> printIr otd                               

instance IrPrint GlobalCxt where
  printIr (GlobalCxt te gl fns atts) = text "typeEnv:" <+> printIr te
                                       $+$ text "globals:" <+> printIr gl
                                       $+$ text "functions:" <+> printIr fns
                                       $+$ text "attributes:" <+> printIr atts

instance IrPrint FunCxt where
  printIr (FunCxt fn p) = text "funName:" <+> text fn
                          $+$ text "funParameters:" <+> printIr p

instance IrPrint IrCxt where
  printIr (IrCxt g l) = text "globalCxt:" <+> printIr g
                        $+$ text "funCxt:" <+> printIr l
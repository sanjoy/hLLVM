module Llvm.Syntax.Parser.Module where
import Llvm.Data.Ast
import Llvm.Syntax.Parser.Basic
import Llvm.Syntax.Parser.Type
import Llvm.Syntax.Parser.Block
import Llvm.Syntax.Parser.Const
import Llvm.Syntax.Parser.Rhs
import Llvm.Syntax.Parser.DataLayout


pModule :: P Module
pModule = do { l <- many toplevel
             ; eof 
             ; return $ Module l
             }

toplevel :: P Toplevel
toplevel = choice [ try pNamedGlobal 
                  , try pToplevelTypeDef
                  , try pToplevelTarget
                  , try pToplevelDepLibs
                  , try pToplevelDeclare
                  , try pToplevelDefine
                  , pToplevelModuleAsm
                  , pToplevelAttributeGroup
                  , pToplevelComdat
                  , pStandaloneMd
                  ]


-- GlobalVar '=' OptionalVisibility ALIAS ...
-- GlobalVar '=' OptionalLinkage OptionalVisibility ... -> global variable
pNamedGlobal :: P Toplevel
pNamedGlobal = do { lhsOpt <- opt (pGlobalId >>= \x->chartok '=' >> return x)
                  ; linkOpt <- opt pLinkage -- (choice [try pExternalLinkage, pLinkage])
                  ; vis <- opt pVisibility
                  ; dllStorage <- opt pDllStorageClass
                  ; tlm <- opt pThreadLocalStorageClass
                  ; na <- option NamedAddr (reserved "unnamed_addr" >> return UnnamedAddr)
                  ; hasAlias <- option False (reserved "alias" >> return True)
                  ; case (lhsOpt, linkOpt, hasAlias) of
                    (Just lhs, Nothing, True) -> pAlias lhs vis dllStorage tlm na
                    (_, _, False) -> pGlobal lhsOpt linkOpt vis dllStorage tlm na
                  }

-- ParseAlias:
--   ::= GlobalVar '=' OptionalVisibility 'alias' OptionalLinkage Aliasee
-- Aliasee
--   ::= TypeAndValue
--   ::= 'bitcast' '(' TypeAndValue 'to' Type ')'
--   ::= 'getelementptr' 'inbounds'? '(' ... ')'
--
-- Everything through visibility has already been parsed.
--
pAlias :: GlobalId -> Maybe Visibility -> Maybe DllStorageClass -> Maybe ThreadLocalStorage -> AddrNaming -> P Toplevel
pAlias lhs vis dll tlm na = do { link <- option Nothing (liftM Just pAliasLinkage)
                               ; aliasee <- pAliasee
                               ; return $ ToplevelAlias (TlAlias lhs vis dll tlm na link aliasee)
                               }
    where pAliasee = 
            choice [ liftM AtV pTypedValue
                   , liftM Ac pConstConversion
                   , liftM AgEp pConstGetElemPtr
                   ]


-- ParseGlobal
--   ::= GlobalVar '=' OptionalLinkage OptionalVisibility OptionalThreadLocal
--       OptionalAddrSpace GlobalType Type Const
--   ::= OptionalLinkage OptionalVisibility OptionalThreadLocal
--       OptionalAddrSpace GlobalType Type Const
--
-- Everything through visibility has been parsed already.
--
pGlobal :: Maybe GlobalId -> Maybe Linkage -> Maybe Visibility -> Maybe DllStorageClass -> Maybe ThreadLocalStorage -> AddrNaming ->  P Toplevel
pGlobal lhs link vis dll tls na = 
  do { addrOpt <- opt pAddrSpace
     ; exti <- option (IsNot ExternallyInitialized) (reserved "externally_initialized" >> return (Is ExternallyInitialized))
     ; globalOpt <- pGlobalType
     ; t <- pType
     ; c <- if (hasInit link) then liftM Just pConst
            else return Nothing
     ; (s,cd,a) <- permute ((,,) <$?> (Nothing, try (comma >> liftM Just pSection))
                            <|?> (Nothing, try (comma >> liftM Just pComdat))
                            <|?> (Nothing, try (comma >> liftM Just pAlign))
                           )
     ; return $ ToplevelGlobal (TlGlobal lhs link vis dll tls na addrOpt exti
                                globalOpt t c s cd a)
     }
  where hasInit x = case x of 
          Just(LinkageExternWeak) -> False
          Just(LinkageExternal) -> False
          -- Just(DllImport) -> False
          Just(_) -> True
          Nothing -> True

data LocalIdOrQuoteStr = L LocalId | Q DqString deriving (Eq,Show)

pLhsType :: P LocalIdOrQuoteStr 
pLhsType = do { lhs <- choice [ liftM L pLocalId
                              , liftM (Q . DqString) pQuoteStr
                              ] 
              ; ignore (chartok '=')
              ; reserved "type"              
              ; return lhs
              }
           
pToplevelTypeDef :: P Toplevel           
pToplevelTypeDef = do { lhsOpt <- opt pLhsType
                      ; case lhsOpt of
                        Nothing -> liftM (ToplevelUnamedType . (TlUnamedType 1)) pType
                        Just (L x) -> liftM (ToplevelTypeDef . (TlTypeDef x)) pType
                        Just (Q _) -> error "irrefutable"
                      }

pToplevelTarget :: P Toplevel
pToplevelTarget = do { reserved "target"
                     ; choice [ do { reserved "triple"  
                                   ; ignore $ chartok '=' 
                                   ; tt <- lexeme (between (char '"') (char '"') pTargetTriple)
                                   ; return $ ToplevelTriple (TlTriple tt)
                                   }
                              , do { reserved "datalayout" 
                                   ; ignore $ chartok '='
                                   ; ls <- lexeme (between (char '"') (char '"') pDataLayout) 
                                   ; return $ ToplevelDataLayout (TlDataLayout ls) 
                                   }
                              ]
                     }

pToplevelDepLibs :: P Toplevel
pToplevelDepLibs = do { reserved "deplibs"
                      ; ignore (chartok '=')
                      ; l <- brackets (sepBy pQuoteStr comma)
                      ; return $ ToplevelDepLibs (TlDepLibs (fmap DqString l))
                      }

                     
pFunctionPrototype :: P FunctionPrototype
pFunctionPrototype = do { lopt <- opt pLinkage
                        ; vopt <- opt pVisibility
                        ; dllopt <- opt pDllStorageClass
                        ; copt <- opt pCallConv
                        ; as <- many pParamAttr
                        ; ret <- pType
                        ; name <- pGlobalId
                        ; params <- pFormalParamList
                        ; unnamed <- opt (reserved "unnamed_addr" >> return UnnamedAddr)
                        ; attrs <- pFunAttrCollection
                        ; sopt <- opt pSection
                        ; cdopt <- opt pComdat
                        ; aopt <- opt pAlign
                        ; gopt <- opt (liftM (Gc . DqString) (reserved "gc" >> pQuoteStr))
                        ; prefixOpt <- opt pPrefix
                        ; prologueOpt <- opt pPrologue
                        ; return (FunctionPrototype lopt vopt dllopt copt 
                                  as ret name params unnamed attrs sopt cdopt aopt gopt 
                                  prefixOpt prologueOpt)
                        }
                                          
pPrefix :: P Prefix                     
pPrefix = reserved "prefix" >> liftM Prefix pTypedConst

pPrologue :: P Prologue
pPrologue = reserved "prologue" >> liftM Prologue pTypedConst

pToplevelDefine :: P Toplevel
pToplevelDefine = do { reserved "define"
                     ; fh <- pFunctionPrototype
                     ; bs <- braces pBlocks
                     ; return $ ToplevelDefine (TlDefine fh bs)
                     }
                  
pToplevelAttributeGroup :: P Toplevel                  
pToplevelAttributeGroup = do { reserved "attributes" 
                             ; ignore (char '#')
                             ; n <- unsignedInt -- decimal
                             ; ignore (chartok '=')
                             ; l <- braces $ many pFunAttr
                             ; return $ ToplevelAttribute (TlAttribute n l)
                             }
                  
pToplevelDeclare :: P Toplevel                  
pToplevelDeclare = liftM ToplevelDeclare 
                   (reserved "declare" >> liftM TlDeclare pFunctionPrototype)

pToplevelModuleAsm :: P Toplevel
pToplevelModuleAsm = do { reserved "module"
                        ; reserved "asm"
                        ; s <- pQuoteStr
                        ; return $ ToplevelModuleAsm (TlModuleAsm (DqString s))
                        }
                     

pToplevelComdat :: P Toplevel
pToplevelComdat = do { l <- pDollarId
                     ; ignore (chartok '=')
                     ; reserved "comdat"
                     ; s <- pSelectionKind
                     ; return $ ToplevelComdat (TlComdat l s)
                     }

pMdNode :: P MdNode
pMdNode = (char '!' >> liftM MdNode intStrToken)

pStandaloneMd :: P Toplevel
pStandaloneMd = do { ignore (char '!')
                   ; choice [ do { n <- intStrToken
                                 ; ignore (chartok '=')
                                 ; choice [ do { t <- pMetaKindedConst -- Tmetadata
                                               ; return (ToplevelStandaloneMd (TlStandaloneMd n t))
                                               }
                                          ]
                                 }
                            , do { i <- lexeme pId
                                 ; ignore (chartok '=')
                                 ; ignore (lexeme (string "!{"))
                                 ; l <- sepBy pMdNode comma 
                                 ; ignore (chartok '}')
                                 ; return $ ToplevelNamedMd (TlNamedMd (MdVar i) l)
                                 }
                            ]
                   }
                   

{-# LANGUAGE GADTs #-}
{-# LANGUAGE CPP, TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, RecordWildCards #-}
module Llvm.AsmHirConversion.IntrinsicsSpecialization where

import Llvm.Hir
import Llvm.ErrorLoc
import Data.Maybe


#define FLC  (FileLoc $(srcLoc))

specializeCallSite :: Maybe LocalId -> FunPtr -> CallFunInterface -> Maybe Cinst
specializeCallSite lhs fptr csi = case (fptr, csi) of
  (FunId (GlobalIdAlphaNum "llvm.va_start"),
   CallFunInterface TcNon Ccc [] _ [ActualParamData t1 [] Nothing v] []) | isNothing lhs -> Just $ I_llvm_va_start v
  (FunId (GlobalIdAlphaNum "llvm.va_end"),
   CallFunInterface TcNon Ccc [] _ [ActualParamData t1 [] Nothing v] []) | isNothing lhs -> Just $ I_llvm_va_end v
  (FunId (GlobalIdAlphaNum "llvm.va_copy"),
   CallFunInterface TcNon Ccc [] _ [ActualParamData t1 [] Nothing v1
                                   ,ActualParamData t2 [] Nothing v2] []) | isNothing lhs -> Just $ I_llvm_va_copy v1 v2
  (FunId (GlobalIdAlphaNum nm), 
   CallFunInterface TcNon Ccc [] _ 
   [ActualParamData t1 [] Nothing v1 -- dest
   ,ActualParamData t2 [] Nothing v2 -- src or setValue
   ,ActualParamData t3 [] Nothing v3 -- len
   ,ActualParamData t4 [] Nothing v4 -- align
   ,ActualParamData t5 [] Nothing v5 -- volatile
   ] []) | isNothing lhs && (nm == "llvm.memcpy.p0i8.p0i8.i32" 
                             || nm == "llvm.memcpy.p0i8.p0i8.i64"
                             || nm == "llvm.memmove.p0i8.p0i8.i32"
                             || nm == "llvm.memmove.p0i8.p0i8.i64"
                             || nm == "llvm.memset.p0i8.i32" 
                             || nm == "llvm.memset.p0i8.i64") -> 
    let mod = case nm of
          "llvm.memcpy.p0i8.p0i8.i32" -> I_llvm_memcpy MemLenI32
                                         (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                         (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
          "llvm.memcpy.p0i8.p0i8.i64" -> I_llvm_memcpy MemLenI64
                                         (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                         (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
          "llvm.memmove.p0i8.p0i8.i32" -> I_llvm_memmove MemLenI32
                                          (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                          (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
          "llvm.memmove.p0i8.p0i8.i64" -> I_llvm_memmove MemLenI64
                                          (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                          (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
          "llvm.memset.p0i8.i32" -> I_llvm_memset MemLenI32
                                    (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                    (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
          "llvm.memset.p0i8.i64" -> I_llvm_memset MemLenI64
                                    (T (dcast FLC t1) v1) (T (dcast FLC t2) v2) (T (dcast FLC t3) v3)
                                    (T (dcast FLC t4) v4) (T (dcast FLC t5) v5)  
    in Just $ mod
  _ -> Nothing


unspecializeIntrinsics :: Cinst -> Maybe Cinst
unspecializeIntrinsics inst = case inst of
  I_llvm_va_start v -> 
    Just $ I_call_fun (FunId (GlobalIdAlphaNum "llvm.va_start")) 
    (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) [tvToAp (T (ptr0 i8) v)] []) Nothing
  I_llvm_va_end v -> 
    Just $ I_call_fun (FunId (GlobalIdAlphaNum "llvm.va_end"))
    (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) [tvToAp (T (ptr0 i8) v)] []) Nothing
  I_llvm_va_copy v1 v2 ->
    Just $ I_call_fun (FunId (GlobalIdAlphaNum "llvm.va_copy"))
    (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) 
     [tvToAp (T (ptr0 i8) v1), tvToAp (T (ptr0 i8) v2)] []) Nothing
  I_llvm_memcpy memLen tv1 tv2 tv3 tv4 tv5 -> 
    let nm = case memLen of
          MemLenI32 -> "llvm.memcpy.p0i8.p0i8.i32"
          MemLenI64 -> "llvm.memcpy.p0i8.p0i8.i64"
    in Just $ I_call_fun (FunId (GlobalIdAlphaNum nm))
       (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) 
        ([tvToAp tv1, tvToAp tv2, tvToAp tv3, tvToAp tv4, tvToAp tv5]) []) Nothing
  I_llvm_memmove memLen tv1 tv2 tv3 tv4 tv5 -> 
    let nm = case memLen of
          MemLenI32 -> "llvm.memmove.p0i8.p0i8.i32"
          MemLenI64 -> "llvm.memmove.p0i8.p0i8.i64"
    in Just $ I_call_fun (FunId (GlobalIdAlphaNum nm))
       (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) 
        ([tvToAp tv1, tvToAp tv2, tvToAp tv3, tvToAp tv4, tvToAp tv5]) []) Nothing
  I_llvm_memset memLen tv1 tv2 tv3 tv4 tv5 -> 
    let nm = case memLen of
          MemLenI32 -> "llvm.memset.p0i8.i32"
          MemLenI64 -> "llvm.memset.p0i8.i64"
    in Just $ I_call_fun (FunId (GlobalIdAlphaNum nm))
       (CallFunInterface TcNon Ccc [] (CallSiteTypeRet (RtypeVoidU Tvoid)) 
        ([tvToAp tv1, tvToAp tv2, tvToAp tv3, tvToAp tv4, tvToAp tv5]) []) Nothing
  _ -> Nothing
    
tvToAp :: Ucast t Dtype => T t Value -> ActualParam
tvToAp (T t v) = ActualParamData (ucast t) [] Nothing v
  
                 
                 
specializeTlGlobal :: TlGlobal -> Maybe TlIntrinsic
specializeTlGlobal tl = case tl of
  TlGlobalDtype {..} -> case tlg_lhs of
    GlobalIdAlphaNum nm | (nm == "llvm.used" 
                           || nm == "llvm.compiler.used" 
                           || nm == "llvm.global_ctors" 
                           || nm == "llvm.global_dtors") && tlg_linkage == Just LinkageAppending -> 
      
      let cnf = case nm of
            "llvm.used" -> TlIntrinsic_llvm_used
            "llvm.compiler.used" -> TlIntrinsic_llvm_compiler_used 
            "llvm.global_ctors" -> TlIntrinsic_llvm_global_ctors
            "llvm.global_dtors" -> TlIntrinsic_llvm_global_dtors
      in Just $ cnf (dcast FLC tlg_dtype) (fromJust tlg_const) tlg_section
    _ -> Nothing
  _ -> Nothing
  
  
unspecializeTlIntrinsics :: TlIntrinsic -> TlGlobal  
unspecializeTlIntrinsics tl = case tl of
  TlIntrinsic_llvm_used ty cnst sec -> mkGlobal "llvm.used" ty cnst sec
  TlIntrinsic_llvm_compiler_used ty cnst sec -> mkGlobal "llvm.compiler.used" ty cnst sec  
  TlIntrinsic_llvm_global_ctors ty cnst sec -> mkGlobal "llvm.global_ctors" ty cnst sec  
  TlIntrinsic_llvm_global_dtors ty cnst sec -> mkGlobal "llvm.global_dtors" ty cnst sec
  where mkGlobal str t c s = TlGlobalDtype { tlg_lhs = GlobalIdAlphaNum str
                                           , tlg_linkage = Just LinkageAppending
                                           , tlg_visibility = Nothing
                                           , tlg_dllstorage = Nothing
                                           , tlg_tls = Nothing
                                           , tlg_addrnaming = NamedAddr
                                           , tlg_addrspace = Nothing
                                           , tlg_externallyInitialized = IsNot ExternallyInitialized
                                           , tlg_globalType = GlobalType "global"
                                           , tlg_dtype = ucast t
                                           , tlg_const = Just c
                                           , tlg_section = s
                                           , tlg_comdat = Nothing
                                           , tlg_alignment = Nothing
                                           }
      
    
    
    

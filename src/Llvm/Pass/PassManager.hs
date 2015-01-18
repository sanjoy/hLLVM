module Llvm.Pass.PassManager where

import Llvm.Data.Ir
import Llvm.Pass.Mem2Reg
import Llvm.Pass.Liveness
import qualified Data.Set as Ds
import Llvm.Pass.Optimizer
import Compiler.Hoopl

data Step = Mem2Reg | Dce deriving (Show,Eq)

toPass :: Step -> Optimization (Ds.Set (Type, GlobalId))
toPass Mem2Reg = mem2reg
toPass Dce = dce

applyPasses1 :: [Optimization (Ds.Set (Type, GlobalId))] -> Module -> CheckingFuelMonad SimpleUniqueMonad Module
applyPasses1 steps m = foldl (\p e -> p >>= optModule e) (return m) steps


applySteps :: [Step] -> Module -> CheckingFuelMonad SimpleUniqueMonad Module
applySteps steps m = let passes = map toPass steps
                     in applyPasses1 passes m

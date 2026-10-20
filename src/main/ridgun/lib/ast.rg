-- ============================================================
-- src/main/ridgun/ast.rg
-- Token, AST, Type System, Analyzer, and Bytecode ADTs
-- for the Self-Hosted Ridgun Compiler (100% v0.9.0 Spec)
-- ============================================================

-- 1. Lexical Tokens produced by lexer.rg
type RToken = TokFn | TokOp | TokType | TokImport | TokGlobal | TokContext | TokShared | TokWith | TokDo | TokAtomic | TokHardware | TokWhere | TokOtherwise | TokMut | TokTrue | TokFalse | TokAnd | TokOr | TokXor | TokNot | TokIdent String | TokInt Int | TokReal String | TokStr String | TokRawStr String | TokColonColon | TokColon | TokFatArrow | TokArrow | TokEquals | TokEqEq | TokNeq | TokGt | TokLt | TokGtEq | TokLtEq | TokPlus | TokMinus | TokStar | TokSlash | TokPercent | TokAt | TokPipe | TokPipeDot | TokDoublePipe | TokDoublePipeDot | TokLParen | TokRParen | TokLBracket | TokIdxLBracket | TokRBracket | TokComma | TokEllipsis | TokNewline | TokEof

-- 2. Patterns in Function & Operator Cases
type RPattern = PatInt Int | PatReal String | PatStr String | PatBool Bool | PatVar String | PatWild | PatEmpty | PatCons RPattern RPattern | PatTuple [RPattern] | PatCtor String [RPattern] | PatSeqBind String

-- 3. Binary Operators
type RBinOp = OpAdd | OpSub | OpMul | OpDiv | OpMod | OpEq | OpNeq | OpGt | OpLt | OpGtEq | OpLtEq | OpAnd | OpOr | OpXor | OpConcat | OpFlatJoin | OpMatMul

-- 4. Statements inside an indented block
type RStmt = StmtLet String RExpr | StmtMut String RExpr | StmtExpr RExpr | StmtAtomic String RExpr | StmtIndexAssign String [RExpr] RExpr

-- 5. Where-block Producer-Consumer Binding (expr -> target_var or expr -> target_var[i, j])
type RWhereBind = WhereBind RExpr String [Int]

-- 6. Guarded branch (| cond = body)
type RGuard = GuardBranch RExpr RExpr

-- 7. Expressions (Full Ridgun v0.9.0 AST)
type RExpr = EInt Int | EReal String | EStr String | EStrInterp [RExpr] | EBool Bool | EUnit | EVar String | ENot RExpr | EOut RExpr | EBin RBinOp RExpr RExpr | ECall String [RExpr] | EEcho [RExpr] | EList [RExpr] | ETuple [RExpr] | ETensor [RExpr] | EEinsum [RExpr] [String] | EHadamard RBinOp RExpr String RExpr String | EIndex RExpr [RExpr] | EIndexAssign String [RExpr] RExpr | ESeqSelect RExpr String | EBlock [RStmt] | EGuard [RGuard] | EWhere RExpr [RWhereBind] | EParPipe [RExpr] | EWithCtx String RExpr RExpr | EWithRegion Int RExpr | EAtomicUpdate String RExpr | ELoadContext String RExpr | ELoadShared String RExpr

-- 8. Function Case & Function Definition
type RFnCase = FnCase [RPattern] [RGuard] RExpr

type RFnDef = FnDef String [String] String [RFnCase]

-- 9. Type Declarations (Sum Variants & Product Record Fields)
type RVariant = TypeVariant String [String]

type RField = TypeField String String

type RTypeDef = TypeDef String [RVariant] [RField]

-- 10. Complete Parsed Program
type RProgram = Program [RFnDef] [RTypeDef]

-- 11. Type System ADTs (for typecheck.rg)
type RType = TyInt | TyReal | TyChar | TyString | TyBool | TyUnit | TyList RType | TyTuple [RType] | TyTensor [String] | TyVariadic RType | TyFun [RType] RType | TyVar String

type RTypeBind = TypeBind String RType

type RDimBind = DimBind String String

type RTypeError = TypeError String String

-- 12. Static Analyzer ADTs (for analyzer.rg)
type RParamEffect = EffReadOnly | EffMutates

type RCostTier = TierTrivial | TierHeavyCPU | TierDynamicRecursive

type RExecStrategy = StratInlineSequential | StratKernelWorkerJob | StratLazyStealableTask | StratFullGreenThread

type RFnSummary = FnSummary String [RParamEffect] Bool RCostTier RExecStrategy

type RAnalysisError = ErrWhereCycle String String | ErrParallelMutation String String | ErrUseAfterSend String String

-- 13. Self-Hosted Bytecode Instruction Set
type RInstr = BPushInt Int | BPushReal String | BPushStr String | BStrInterp Int | BPushBool Bool | BPushUnit | BPushListEmpty | BListConcat Int | BListHead | BListTail | BMakeTuple Int | BTupleGet Int | BMakeAdt String Int | BAdtField Int | BMakeTensor Int | BTensorGet Int | BTensorSet Int | BTensorMatMul | BTensorEinsum [String] | BTensorHadamard RBinOp String String | BSeqFlatJoin | BPackSeq Int Int | BSeqSelectMask String | BLoadLocal Int | BStoreLocal Int | BPop | BAdd | BSub | BMul | BDiv | BMod | BCmpEq | BCmpNeq | BCmpGt | BCmpLt | BCmpGtEq | BCmpLtEq | BAnd | BOr | BXor | BNot | BEcho Int | BOut | BCall String Int | BPushCtx String | BPopCtx String | BLoadCtx String | BLoadShared String | BAtomicStore String | BEnterRegion Int | BExitRegion | BJump Int | BJumpIfFalse Int | BJumpIfNeq Int | BJumpIfEmpty Int | BJumpIfNotEmpty Int | BJumpIfNotAdt String Int | BReturn

type RCompiledFn = CompiledFn String Int [RInstr]

type RCompiledProg = CompiledProg [RCompiledFn]

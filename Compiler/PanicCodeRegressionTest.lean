import Compiler.CompilationModel
import Compiler.CodegenCommon
import Compiler.TypedIRLowering

namespace Compiler.PanicCodeRegressionTest

open Compiler.CompilationModel
open Compiler.Yul
open Verity.Core
open Verity.Core.Free

example : PanicCode.arithmeticOverflow.toNat = 0x11 := by rfl

example : PanicCode.divisionByZero.toNat = 0x12 := by rfl

example : (Stmt.panic .arithmeticOverflow).directMetadata.subexpressions = [] := by rfl

example : (Stmt.panic .arithmeticOverflow).directMetadata.termination = .alwaysTerminates := by rfl

example : (Stmt.controlFlow (Stmt.panic .divisionByZero)).mayRevert = true := by
  native_decide

def typedDivisionByZeroEvalRevertsWithCode : Bool :=
  match evalTStmt default (.panic .divisionByZero) with
  | .revert reason => reason == "Panic(18)"
  | _ => false

example : typedDivisionByZeroEvalRevertsWithCode = true := by native_decide

def typedOverflowPanicLowersDirectly : Bool :=
  match compileStmt [] [] [] .calldata [] false [] []
      (Stmt.panic .arithmeticOverflow) with
  | .ok [
      YulStmt.exprStmt (YulExpr.call "mstore" [
        YulExpr.lit 0,
        YulExpr.call "shl" [YulExpr.lit 224, YulExpr.hex 0x4e487b71]
      ]),
      YulStmt.exprStmt (YulExpr.call "mstore" [YulExpr.lit 4, YulExpr.lit 0x11]),
      YulStmt.exprStmt (YulExpr.call "revert" [YulExpr.lit 0, YulExpr.lit 36])
    ] => true
  | _ => false

example : typedOverflowPanicLowersDirectly = true := by native_decide

def typedDivisionByZeroPanicLowersDirectly : Bool :=
  match lowerTStmts [TStmt.panic .divisionByZero] with
  | [
      YulStmt.exprStmt (YulExpr.call "mstore" [
        YulExpr.lit 0,
        YulExpr.call "shl" [YulExpr.lit 224, YulExpr.hex 0x4e487b71]
      ]),
      YulStmt.exprStmt (YulExpr.call "mstore" [YulExpr.lit 4, YulExpr.lit 0x12]),
      YulStmt.exprStmt (YulExpr.call "revert" [YulExpr.lit 0, YulExpr.lit 36])
    ] => true
  | _ => false

example : typedDivisionByZeroPanicLowersDirectly = true := by native_decide

def panicMloadCachesCodeBeforePayloadStores : Bool :=
  match compileStmt [] [] [] .calldata [] false [] []
      (Stmt.panicCode (Expr.mload (Expr.literal 0))) with
  | .ok [YulStmt.block [
      YulStmt.let_ codeName (YulExpr.call "mload" [YulExpr.lit 0]),
      YulStmt.exprStmt (YulExpr.call "mstore" [
        YulExpr.lit 0,
        YulExpr.call "shl" [YulExpr.lit 224, YulExpr.hex 0x4e487b71]
      ]),
      YulStmt.exprStmt (YulExpr.call "mstore" [YulExpr.lit 4, YulExpr.ident payloadCodeName]),
      YulStmt.exprStmt (YulExpr.call "revert" [YulExpr.lit 0, YulExpr.lit 36])
    ]] =>
      codeName == "__panic_code" && payloadCodeName == codeName
  | _ => false

example : panicMloadCachesCodeBeforePayloadStores = true := by native_decide

def rawTypedIRPanicMappingReadCachesCodeBeforePayloadStores : Bool :=
  match lowerTStmts [TStmt.panicCode (TExpr.getMapping 0 TExpr.sender)] with
  | [YulStmt.block [
      YulStmt.let_ codeName
        (YulExpr.call "sload" [
          YulExpr.call "mappingSlot" [YulExpr.lit 0, YulExpr.call "caller" []]
        ]),
      YulStmt.exprStmt (YulExpr.call "mstore" [
        YulExpr.lit 0,
        YulExpr.call "shl" [YulExpr.lit 224, YulExpr.hex 0x4e487b71]
      ]),
      YulStmt.exprStmt (YulExpr.call "mstore" [YulExpr.lit 4, YulExpr.ident payloadCodeName]),
      YulStmt.exprStmt (YulExpr.call "revert" [YulExpr.lit 0, YulExpr.lit 36])
    ]] =>
      codeName == "__panic_code" && payloadCodeName == codeName
  | _ => false

example : rawTypedIRPanicMappingReadCachesCodeBeforePayloadStores = true := by native_decide

private def checkedArithmeticHelpersContract : Compiler.IRContract :=
  { name := "PanicRewriteRegression"
    deploy := []
    functions := []
    usesMapping := false
    internalFunctions := [
      checkedAddUint256Helper,
      checkedSubUint256Helper,
      checkedMulUint256Helper,
      checkedDivUint256Helper
    ] }

private def optimizeCheckedArithmeticRuntime (stmts : List YulStmt) : List YulStmt :=
  (Compiler.CodegenCommon.optimizeCheckedArithmeticObjectIfAvailable
      checkedArithmeticHelpersContract
      { name := "PanicRewriteRegression"
        deployCode := []
        runtimeCode := stmts }).runtimeCode

def mixedTypedAndRawPanicRewritesOnlyTyped : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let failCond := YulExpr.call "lt" [YulExpr.call "add" [lhs, rhs], lhs]
  let typedPair := [
    YulStmt.if_ failCond (solidityPanicPayload 0x11),
    YulStmt.let_ "typedResult" (YulExpr.call "add" [lhs, rhs])
  ]
  let rawGuard :=
    YulStmt.if_ failCond [YulStmt.block (
      YulStmt.let_ "__panic_code" (YulExpr.lit 0x11) ::
        solidityPanicPayloadExpr (YulExpr.ident "__panic_code"))]
  let rawPair := [
    rawGuard,
    YulStmt.let_ "rawResult" (YulExpr.call "add" [lhs, rhs])
  ]
  let object : YulObject :=
    { name := "PanicRewriteRegression"
      deployCode := []
      runtimeCode := typedPair ++ rawPair }
  match (Compiler.CodegenCommon.optimizeCheckedArithmeticObjectIfAvailable
      checkedArithmeticHelpersContract object).runtimeCode with
  | [ YulStmt.let_ "typedResult" (YulExpr.call helperName [typedLhs, typedRhs]),
      rawGuardActual,
      YulStmt.let_ "rawResult" (YulExpr.call "add" [rawLhs, rawRhs]) ] =>
      helperName == checkedAddUint256HelperName &&
        typedLhs == lhs && typedRhs == rhs &&
        rawGuardActual == rawGuard && rawLhs == lhs && rawRhs == rhs
  | _ => false

example : mixedTypedAndRawPanicRewritesOnlyTyped = true := by native_decide

def yulOptimizerStandaloneTypedPanicDoesNotRewrite : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let failCond := YulExpr.call "lt" [YulExpr.call "add" [lhs, rhs], lhs]
  let stmts := [YulStmt.if_ failCond (solidityPanicPayload 0x11)]
  optimizeCheckedArithmeticRuntime stmts == stmts

example : yulOptimizerStandaloneTypedPanicDoesNotRewrite = true := by native_decide

def yulOptimizerReversedSubtractionGuardDoesNotRewrite : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let stmts := [
    YulStmt.if_ (YulExpr.call "lt" [rhs, lhs]) (solidityPanicPayload 0x11),
    YulStmt.let_ "result" (YulExpr.call "sub" [lhs, rhs])]
  optimizeCheckedArithmeticRuntime stmts == stmts

example : yulOptimizerReversedSubtractionGuardDoesNotRewrite = true := by native_decide

def yulOptimizerWrongSubtractionPanicCodeDoesNotRewrite : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let stmts := [
    YulStmt.if_ (YulExpr.call "lt" [lhs, rhs]) (solidityPanicPayload 0x12),
    YulStmt.let_ "result" (YulExpr.call "sub" [lhs, rhs])]
  optimizeCheckedArithmeticRuntime stmts == stmts

example : yulOptimizerWrongSubtractionPanicCodeDoesNotRewrite = true := by native_decide

def yulOptimizerMismatchedSubtractionOperandsDoNotRewrite : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let other := YulExpr.ident "other"
  let stmts := [
    YulStmt.if_ (YulExpr.call "lt" [lhs, rhs]) (solidityPanicPayload 0x11),
    YulStmt.let_ "result" (YulExpr.call "sub" [lhs, other])]
  optimizeCheckedArithmeticRuntime stmts == stmts

example : yulOptimizerMismatchedSubtractionOperandsDoNotRewrite = true := by native_decide

def yulOptimizerRawArithmeticLookalikeDoesNotRewrite : Bool :=
  let lhs := YulExpr.ident "lhs"
  let rhs := YulExpr.ident "rhs"
  let failCond := YulExpr.call "lt" [YulExpr.call "add" [lhs, rhs], lhs]
  let rawBody := [YulStmt.block (
    YulStmt.let_ "__panic_code" (YulExpr.lit 0x11) ::
      solidityPanicPayloadExpr (YulExpr.ident "__panic_code"))]
  let stmts := [
    YulStmt.if_ failCond rawBody,
    YulStmt.let_ "result" (YulExpr.call "add" [lhs, rhs])]
  optimizeCheckedArithmeticRuntime stmts == stmts

example : yulOptimizerRawArithmeticLookalikeDoesNotRewrite = true := by native_decide

def unsafeYulArithmeticPairRemainsOpaque : Bool :=
  let lhs := YulExpr.call "sideEffectingOperand" []
  let rhs := YulExpr.call "anotherSideEffectingOperand" []
  let failCond := YulExpr.call "lt" [YulExpr.call "add" [lhs, rhs], lhs]
  let rawPair := [
    YulStmt.if_ failCond (solidityPanicPayload 0x11),
    YulStmt.let_ "result" (YulExpr.call "add" [lhs, rhs])]
  let fragment : UnsafeYulFragment := {
    label := "unsafe_arithmetic_pair"
    stmts := rawPair
    obligations := [] }
  match compileStmt [] [] [] .calldata [] false [] [] (Stmt.unsafeYul fragment) with
  | .ok lowered => optimizeCheckedArithmeticRuntime lowered == lowered
  | .error _ => false

example : unsafeYulArithmeticPairRemainsOpaque = true := by native_decide

private def sideEffectingEcmLookalike : Compiler.ECM.ExternalCallModule where
  name := "sideEffectingEcmLookalike"
  numArgs := 0
  resultVars := ["result"]
  writesState := true
  readsState := true
  compile := fun _ctx _args =>
    let lhs := YulExpr.call "bump" []
    let rhs := YulExpr.lit 2
    let failCond := YulExpr.call "lt" [YulExpr.call "add" [lhs, rhs], lhs]
    pure [
      YulStmt.if_ failCond (solidityPanicPayload 0x11),
      YulStmt.let_ "result" (YulExpr.call "add" [lhs, rhs])
    ]

def ecmArithmeticLookalikeRemainsOpaque : Bool :=
  match compileStmt [] [] [] .calldata [] false [] []
      (Stmt.ecm sideEffectingEcmLookalike []) with
  | .ok lowered => optimizeCheckedArithmeticRuntime lowered == lowered
  | .error _ => false

example : ecmArithmeticLookalikeRemainsOpaque = true := by native_decide

end Compiler.PanicCodeRegressionTest

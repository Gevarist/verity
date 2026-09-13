# Panic Surface #1999 Spec

## Implemented Contract

Compiler-generated checked arithmetic uses a closed panic-code domain through
the compilation model and typed IR:

- `Verity.Core.PanicCode` has exactly two constructors:
  `arithmeticOverflow` maps to `0x11`, and `divisionByZero` maps to `0x12`.
- `Stmt.panic PanicCode` and `TStmt.panic PanicCode` carry this type until Yul
  lowering. The conversion to a numeric ABI word is explicit at that boundary.
- `addPanic`, `subPanic`, and `mulPanic` lower to
  `Stmt.panic .arithmeticOverflow`; `divPanic` lowers to
  `Stmt.panic .divisionByZero`.
- The checked-arithmetic model is an exact pair of adjacent statements: a
  guarded typed panic followed by the arithmetic result binding. Together,
  those statements form the guard/panic/arithmetic sequence.
- Typed panics lower directly to the canonical `Panic(uint256)` body. The body
  stores selector `0x4e487b71` at offset 0, stores code `0x11` or `0x12` at
  offset 4, and executes `revert(0, 36)`.
- Usage analysis and the post-codegen peephole recognize only the exact typed
  shape with matching guard, operands, operation, and panic constructor.
  Standalone, reversed, mismatched, wrong-code, and raw-panic lookalikes do not
  enable the checked helpers. `Stmt.unsafeYul` fragments are lowered with
  comment-only provenance markers and are optimizer-opaque, so handwritten
  Yul cannot be rewritten as a typed helper call.

The direct Lean implementations in `Verity.Stdlib.Math` retain their existing
diagnostic strings for executable/model use. Those strings are not the compiled
contract's revert encoding: macro-generated contracts bypass that compatibility
path and emit canonical `Panic(uint256)` bytes rather than `Error(string)`.

## Raw Compatibility Boundary

The typed arithmetic domain intentionally coexists with the raw expression
constructors `Stmt.panicCode Expr` and `TStmt.panicCode (TExpr .uint256)`.
General `panic(code)` syntax, runtime-supplied codes, and generated enum-range
guards such as `panic(0x21)` remain raw. Raw lowering still evaluates and caches
the code expression before constructing the canonical payload. A raw literal
`0x11` therefore does not become typed arithmetic evidence and is not rewritten
by the checked-arithmetic peephole.

This separation keeps the local two-code specification strict without claiming
that the full Solidity panic-code catalog has been modeled as `PanicCode`.

## Proof and Regression Coverage

- `Compiler.Proofs.IRGeneration.PanicPayloadIR` proves the selector, exact code
  word, 36-byte revert, and preservation of all other memory for both typed
  constructors. Its general numeric theorem continues to cover the raw payload
  builder for every in-range code.
- Feature tests cover all four arithmetic wrappers, both typed code mappings,
  direct typed lowering, cached raw lowering, raw runtime panic, raw enum code
  `0x21`, and mixed typed/raw Yul where only the typed pair is rewritten.

## Completion Criteria

This slice is complete when all of the following hold:

1. Checked arithmetic is typed through the model and typed IR, with the exact
   two-constructor mapping above.
2. Both typed payloads have canonical backend proof and regression coverage.
3. Runtime raw panic and generated `0x21` enum behavior remain compatible.
4. The audit, trust, axiom, and arithmetic-profile documents are synchronized,
   and the trust/documentation checks pass.

## Independent Follow-ups

These are separate proof projects and do not block this slice:

1. Prove that the checked-arithmetic Yul peephole rewrite preserves semantics.
   Its current assurance is exact fail-closed structural matching plus positive
   and adversarial regression tests. This is the higher-priority follow-up.
2. Admit typed panic statements into the generic whole-contract `SupportedSpec`
   proof fragment. Payload correctness alone does not establish that broader
   source-to-IR theorem.
3. Add a shared source-model byte-level revert observable and connect it to the
   proved backend payload.
4. Model more of Solidity's panic-code catalog as typed constructors if a later
   feature requires it.

No project-level axiom is added by this implementation.

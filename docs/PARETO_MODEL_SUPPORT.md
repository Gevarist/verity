# Pareto Credit Vault model support

This note tracks the four Verity language features needed to model the Pareto
Credit Vault (`IdleCDOCreditVault`, `IdleCDOEpochVariant`, `IdleCreditVault`)
as `verity_contract` sources that read one-to-one against the Solidity.

The inheritance chain in Solidity is

```
IdleCDOEpochVariant
  is IdleCDOCreditVault
    is PausableUpgradeable,
       GuardedLaunchUpgradable(Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable),
       IdleCDOStorage
```

and the strategy is

```
IdleCreditVault is Initializable, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable
```

The vault calls the strategy about forty times, the strategy reads vault
getters about a dozen times, both call ERC20 tokens, and the vault wraps
three external self-calls in `try/catch`. Signed `int256` arithmetic appears
in the price waterfall and in withdraw-request adjustments.

## Feature 1: checked Int256 arithmetic and int256 storage

**Syntax.** `Int256` is already a word-like value type. New operations:

| Surface | Meaning |
|---------|---------|
| `Int256.safeAdd` / `safeSub` / `safeMul` / `safeDiv` / `safeNeg` / `safeMod` | `Option Int256`; `none` on the Solidity 0.8 failure boundary |
| `addPanic` / `subPanic` / `mulPanic` / `divPanic` | `Contract` wrappers, overloaded on `Uint256` and `Int256` |
| `negPanic` / `modPanic` | signed-only `Contract` wrappers |
| `slt` / `sgt` / `sle` / `sge` / `isNeg` | signed comparisons; lower to Yul `slt`/`sgt` |
| `Uint256.toInt256` / `Int256.toUint256` | bit-reinterpretation; **no range check** |

`ofNatChecked` / `toNatChecked` are omitted: Pareto's `uint256(int256(x))`
pattern is the bit-reinterpretation already provided by `toUint256`.

**Storage.** `storage last : Int256 := slot 0` now emits
`FieldType.int256` (one EVM word, layout-identical to `uint256`) so the
field round-trips through `Storage.lean`, layout reports, and
`#check_contract`. The executable slot remains a `Uint256` word; the DSL
and compilation model keep the signed tag.

**Compilation model.** Bound `let x ← addPanic a b` with `Int256`
operands lowers to wrapping `add`/`sub`/`mul` plus an `slt`-based overflow
guard, or to `sdiv`/`smod` with divide-by-zero and `minValue / -1` guards.
The panic codes match the unsigned wrappers: `Panic(0x11)` overflow,
`Panic(0x12)` division by zero.

**Proofs.** Option-level success/failure is definitional in
`Verity/Core/Int256.lean`. Wrapping ≡ unbounded `Int` on the success side
is in `Verity/Proofs/Stdlib/Int256.lean` (mathlib): two's-complement
residues modulo `2^256` are unique in range, so `add`/`sub`/`mul`/`neg`
agree with `Int` exactly when the mathematical result is in range.
`divPanic`/`modPanic` success is `Int.tdiv`/`Int.tmod` (towards-zero,
sign-of-dividend remainder). No `sorry`, no new axioms.

**Alternative considered.** Putting the `Contract` wrappers in
`Verity/Core/Int256.lean` would import the `Contract` monad into the core
numeric module (circular with `Verity.Core`). Option-level `*Panic` lives
in `Int256.lean`; `Contract` wrappers live next to the unsigned ones in
`Verity.Stdlib.Math` and dispatch through small typeclasses so the source
spelling stays `addPanic`. Heavy wrapping proofs live under
`Verity.Proofs.Stdlib` rather than Core so the numeric module stays
mathlib-free.

## Feature 2: modeled-callee calls (planned)

Preferred shape: a `linked_contracts` section binding an interface-typed
value to a modeled `verity_contract`, e.g.

```
linked_contracts strategy : IStrategy := IdleCreditVault
```

Existing `interfaces` grammar is unchanged. Semantics: a hop in
`Verity.MultiContract.MultiWorld`. Compilation-model lowering stays an ABI
call; the binding is a model-level assumption (see `TRUST_ASSUMPTIONS.md`).

## Feature 3: real try/catch (planned)

Replace the `tryCatch` stub with a construct over a modeled call or
self-call. On revert the handler starts from the pre-call snapshot; a
revert inside the success continuation is not caught.

## Feature 4: multi-parent `is A, B, C` (planned)

Left-to-right flattening of the existing single-parent flatten. No C3
linearization; diamonds are rejected.

## How to translate an OpenZeppelin-style contract chain

1. Declare each parent as its own `verity_contract` (storage-only mixins
   with explicit slots, `Pausable`-like parents with modifiers, `Ownable`-like
   parents with an owner slot).
2. Flatten with `is A, B, C` in Solidity declaration order once Feature 4
   lands. Today, chain them one parent at a time.
3. Bind cross-contract interfaces with `linked_contracts` once Feature 2
   lands; keep unbound `interfaces` for ERC-20 tokens whose bodies are
   not modeled.
4. Replace Solidity `try this.f(...) catch` with the Feature 3 construct.
5. Use `addPanic` / `subPanic` / `Int256` storage for signed price math.

See `Contracts/Smoke/Arithmetic.lean` (`Int256CheckedSmoke`) for Feature 1.

# Verity Phase 1: Reading and Elaborating a Contract

Phase 1 happens when Lean compiles your Verity source file, before `verity-compiler` is run.

For example:

```lean
verity_contract ERC20 where
  ...
```

in [`Contracts/ERC20/ERC20.lean:9`](../Contracts/ERC20/ERC20.lean#L9).

The process is:

```text
ERC20.lean
   ↓
Lean parser
   ↓
Verity elaborator
   ↓
generated Lean declarations
   ↓
type checking and proof checking
   ↓
ERC20.olean
```

## 1. Verity registers its syntax

`Contracts.Common` imports `Verity.Macro` at [`Contracts/Common.lean:6`](../Contracts/Common.lean#L6).

`Verity.Macro` imports `Elaborate.lean` at [`Verity/Macro.lean:4`](../Verity/Macro.lean#L4).

This makes Lean aware of the special command:

```lean
verity_contract
```

Its grammar is defined in [`Verity/Macro/Syntax.lean:231`](../Verity/Macro/Syntax.lean#L231).

## 2. Lean parses the contract

Lean reads the text and creates a syntax tree.

For example, it recognizes:

```lean
storage
  balancesSlot : Address → Uint256 := slot 2
```

as a Verity storage declaration, and recognizes each function, constructor, event, and so on.

## 3. Lean invokes Verity’s elaborator

This registration connects the syntax to the handler:

```lean
@[command_elab verityContractCmd]
def elabVerityContract : CommandElab := fun stx =>
  elabVerityContractOrMixin stx
```

This is in [`Verity/Macro/Elaborate.lean:292`](../Verity/Macro/Elaborate.lean#L292).

The main work begins at [`Elaborate.lean:68`](../Verity/Macro/Elaborate.lean#L68):

```lean
let parsed ← parseContractSyntax stx
```

`parseContractSyntax` converts the syntax tree into a structured record containing:

```text
contract name
storage fields
functions
constructor
events
errors
```

It is implemented in [`Verity/Macro/Translate.lean:3741`](../Verity/Macro/Translate.lean#L3741).

## 4. Verity validates the declarations

`Elaborate.lean` checks things such as:

- duplicate names;
- valid storage declarations;
- valid function declarations;
- valid external declarations;
- valid constants and immutables.

If a declaration is invalid, Lean reports an error and compilation stops.

## 5. It generates ordinary Lean code

Verity now generates normal Lean commands using `elabCommand`.

For each function, `mkFunctionCommandsPublic` generates three important declarations:

```lean
def transfer          -- executable Core function
def transfer_modelBody -- list of CompilationModel statements
def transfer_model     -- FunctionSpec
```

The generation happens in [`Verity/Macro/Translate.lean:4435`](../Verity/Macro/Translate.lean#L4435).

This is where Verity creates both:

- the executable Core implementation;
- the compiler-facing model of that implementation.

It also generates a bridge theorem connecting the function to its model.

## 6. It generates the contract `spec`

At [`Elaborate.lean:186–199`](../Verity/Macro/Elaborate.lean#L186), Verity creates:

```lean
def spec : CompilationModel.CompilationModel := ...
```

This `spec` contains the complete compiler description of the contract:

```text
contract name
storage layout
constructor model
function models
events
errors
external calls
```

This is the value that Phase 2 later loads.

## 7. It generates additional theorems

After creating the `spec`, Verity may generate theorems for:

- semantic bridges;
- view functions;
- pure functions;
- no-external-call functions;
- frame conditions;
- CEI compliance;
- non-reentrancy;
- role-based access control.

These are generated in the rest of [`Elaborate.lean:211–285`](../Verity/Macro/Elaborate.lean#L211).

Lean type-checks all these theorem declarations immediately.

## 8. It closes the namespace

Finally:

```lean
elabCommand (← `(end $contractName))
```

at [`Elaborate.lean:287`](../Verity/Macro/Elaborate.lean#L287) closes the namespace.

## Complete Phase 1 flow

```text
parseContractSyntax stx
   ↓
extract contract parts
   ↓
validate declarations
   ↓
generate executable Lean functions
   ↓
generate CompilationModel functions
   ↓
generate contract spec
   ↓
generate proofs and bridges
   ↓
Lean checks everything
   ↓
compiled .olean module
```

The most important result is that Phase 1 creates both:

```text
executable Core code
```

and:

```text
spec : CompilationModel
```

Phase 2 later loads that `spec`.

One important distinction:

- `Contracts.ERC20.spec` is a `CompilationModel` data value used by the compiler.
- A theorem such as `transfer_spec` is a logical statement describing desired behavior.

They are related, but they are not the same thing.

So Phase 1 means:

> Lean reads the Verity source, checks it, generates executable code, generates the compilation model, checks the proofs, and saves all of it in the compiled module.

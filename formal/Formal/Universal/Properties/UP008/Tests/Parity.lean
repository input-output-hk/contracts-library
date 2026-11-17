import Formal.Universal.Properties.UP008.Definition
import Formal.Universal.Properties.UP014.Tests.Parity
import Formal.Universal.Standalone.LinearVesting.JunkToken

/-! Kernel equivalences with the original helpers and standalone propositions.
The helper proofs come from UP-014 tests; historical solver observations are not imported. -/

namespace Formal.Universal.Properties.UP008.Tests.Parity

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (ScriptContext TxOut TxOutRef validScriptContext)
open Formal.Universal.Support.Continuations
open UP000.Tests.Parity (claimToLegacy claimFromLegacy preparedAccepts)
open UP004.Tests.Parity (preparedRejects)

theorem withOutputsParity : withOutputs = Formal.Universal.Support.withOutputs :=
  UP014.Tests.Parity.withOutputsParity

theorem keyAddrParity : keyAddr = Formal.Universal.Support.keyAddr := UP014.Tests.Parity.keyAddrParity

theorem ownInputParity : ownInput? = Formal.Universal.Support.ownInput? := UP014.Tests.Parity.ownInputParity

theorem redirectParity : redirectContinuations = Formal.Universal.Support.redirectContinuations :=
  UP014.Tests.Parity.redirectParity

theorem changeContinuationParity : changeContinuation = Formal.Universal.Support.changeContinuation :=
  UP014.Tests.Parity.changeContinuationParity

theorem unrelatedKeyParity : unrelatedKey = Formal.Universal.Support.unrelatedKey := rfl

theorem lastPolicyParity : lastPolicy = Formal.Universal.Support.lastPolicy := rfl

theorem addJunkFromParity : addJunkFrom = Formal.Universal.Support.addJunkFrom := by
  funext ctx ref lovelace
  simp only [addJunkFrom, Formal.Universal.Support.addJunkFrom,
    keyAddrParity, unrelatedKeyParity, lastPolicyParity, changeContinuationParity]

theorem changeFirstLength (predicate : TxOut → Bool) (transform : TxOut → TxOut)
    (outputs : List TxOut) :
    (changeFirst predicate transform outputs).length = outputs.length := by
  induction outputs with
  | nil => rfl
  | cons output rest ih =>
      simp only [changeFirst]
      split <;> simp only [List.length_cons, ih]

theorem addedInputShape (ctx : ScriptContext) (ref : TxOutRef) (lovelace : Int) :
    (addJunkFrom ctx ref lovelace).scriptContextTxInfo.txInfoInputs =
      ctx.scriptContextTxInfo.txInfoInputs ++
        [⟨ref, ⟨keyAddr unrelatedKey,
          [(.B "", .Map [(.B "", .I lovelace)]),
           (.B lastPolicy, .Map [(.B lastPolicy, .I 1)])], .NoOutputDatum, none⟩⟩] := rfl

theorem addsOneOutput (ctx : ScriptContext) (ref : TxOutRef) (lovelace : Int) :
    (addJunkFrom ctx ref lovelace).scriptContextTxInfo.txInfoOutputs.length =
      ctx.scriptContextTxInfo.txInfoOutputs.length + 1 := by
  simp only [addJunkFrom, changeContinuation, withOutputs, changeFirstLength,
    List.append_eq, List.length_append, List.length_singleton]

theorem changedOutputPreservesFields (output : TxOut) :
    let changed : TxOut :=
      { output with txOutValue :=
          List.append output.txOutValue [(.B lastPolicy, .Map [(.B lastPolicy, .I 1)])] }
    changed.txOutValue = List.append output.txOutValue
      [(.B lastPolicy, .Map [(.B lastPolicy, .I 1)])] ∧
    changed.txOutAddress = output.txOutAddress ∧
    changed.txOutDatum = output.txOutDatum ∧
    changed.txOutReferenceScript = output.txOutReferenceScript := ⟨rfl, rfl, rfl, rfl⟩

theorem changedContextPreservesFields (ctx : ScriptContext) (ref : TxOutRef) (lovelace : Int) :
    let changed := addJunkFrom ctx ref lovelace
    changed.scriptContextRedeemer = ctx.scriptContextRedeemer ∧
    changed.scriptContextScriptInfo = ctx.scriptContextScriptInfo ∧
    { changed.scriptContextTxInfo with
        txInfoInputs := ctx.scriptContextTxInfo.txInfoInputs
        txInfoOutputs := ctx.scriptContextTxInfo.txInfoOutputs } = ctx.scriptContextTxInfo :=
  ⟨rfl, rfl, rfl⟩

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.junkToken_claim :=
  ⟨fun h p ref lovelace => h (claimFromLegacy p) ref lovelace,
    fun h p ref lovelace => h (claimToLegacy p) ref lovelace⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.junkToken_claim_applies :=
  ⟨fun ⟨p, ref, lovelace, evidence⟩ => ⟨claimToLegacy p, ref, lovelace, evidence⟩,
    fun ⟨p, ref, lovelace, evidence⟩ => ⟨claimFromLegacy p, ref, lovelace, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts rejects context) :
    statement valid accepts rejects context :=
  fun p ref lovelace original accepted redirected changed =>
    False.elim (absent ⟨p, ref, lovelace, original, accepted, redirected, changed⟩)

end Formal.Universal.Properties.UP008.Tests.Parity

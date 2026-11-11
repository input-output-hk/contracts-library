import Formal.Properties.Universal.UP014.Definition
import Formal.Properties.Universal.UP004.Tests.Parity
import Formal.Vesting.Linear.Blueprint.ContinuationOtherDatum

/-! Kernel equivalences with the original helpers and standalone propositions.
The standalone solver observations are not imported. -/

namespace Formal.Properties.Universal.UP014.Tests.Parity

open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOut validScriptContext)
open Formal.Support.Continuations
open UP000.Tests.Parity (claimToLegacy claimFromLegacy preparedAccepts)
open UP004.Tests.Parity (preparedRejects)

theorem withOutputsParity : withOutputs = Formal.Support.withOutputs := rfl

theorem keyAddrParity : keyAddr = Formal.Support.keyAddr := rfl

theorem ownInputParity : ownInput? = Formal.Support.ownInput? := rfl

theorem attackerKeyParity : attackerKey = Formal.Support.attackerKey := rfl

theorem redirectParity : redirectContinuations = Formal.Support.redirectContinuations := rfl

theorem isContinuationParity : isContinuation = Formal.Support.isContinuation := rfl

theorem changeFirstParity : changeFirst = Formal.Support.changeFirst := by
  funext predicate transform outputs
  induction outputs with
  | nil => rfl
  | cons output rest ih =>
      simp only [changeFirst, Formal.Support.changeFirst, ih]

theorem changeContinuationParity : changeContinuation = Formal.Support.changeContinuation := by
  funext ctx transform
  simp only [changeContinuation, Formal.Support.changeContinuation,
    withOutputsParity, isContinuationParity, changeFirstParity]

theorem firstContinuationParity : firstContinuation? = Formal.Support.firstContinuation? := rfl

theorem replacementEncoding (c1 c2 : Credential) (start finish recovery : Int) :
    IsData.toData
      ({ beneficiary := c1, locker := c2, vesting := [], start_time := start,
          end_time := finish, recovery_time := recovery } :
        Formal.Vesting.Linear.Blueprint.Vesting.Types.VestingDatum) =
      Data.Constr 0 [IsData.toData c1, IsData.toData c2, Data.List [],
        Data.I start, Data.I finish, Data.I recovery] := rfl

theorem changedOutputPreservesFields (o : TxOut) (c1 c2 : Credential)
    (start finish recovery : Int) :
    let changed : TxOut := { o with txOutDatum := .OutputDatum (Data.Constr 0
      [IsData.toData c1, IsData.toData c2, Data.List [],
        Data.I start, Data.I finish, Data.I recovery]) }
    changed.txOutAddress = o.txOutAddress ∧
    changed.txOutValue = o.txOutValue ∧
    changed.txOutReferenceScript = o.txOutReferenceScript := ⟨rfl, rfl, rfl⟩

theorem restoringOutputsRestoresContext (ctx : ScriptContext) (c1 c2 : Credential)
    (start finish recovery : Int) :
    withOutputs (changeContinuation ctx (fun o =>
      { o with txOutDatum := .OutputDatum (Data.Constr 0
        [IsData.toData c1, IsData.toData c2, Data.List [],
          Data.I start, Data.I finish, Data.I recovery]) }))
      ctx.scriptContextTxInfo.txInfoOutputs = ctx := rfl

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      Formal.Vesting.Linear.Blueprint.continuationOtherDatum_claim :=
  ⟨fun h p c1 c2 start finish recovery => h (claimFromLegacy p) c1 c2 start finish recovery,
    fun h p c1 c2 start finish recovery => h (claimToLegacy p) c1 c2 start finish recovery⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      Formal.Vesting.Linear.Blueprint.continuationOtherDatum_claim_applies :=
  ⟨fun ⟨p, c1, c2, start, finish, recovery, evidence⟩ =>
      ⟨claimToLegacy p, c1, c2, start, finish, recovery, evidence⟩,
    fun ⟨p, c1, c2, start, finish, recovery, evidence⟩ =>
      ⟨claimFromLegacy p, c1, c2, start, finish, recovery, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts rejects context) :
    statement valid accepts rejects context :=
  fun p c1 c2 start finish recovery original accepted redirected unequal changed =>
    False.elim (absent ⟨p, c1, c2, start, finish, recovery,
      original, accepted, redirected, unequal, changed⟩)

end Formal.Properties.Universal.UP014.Tests.Parity

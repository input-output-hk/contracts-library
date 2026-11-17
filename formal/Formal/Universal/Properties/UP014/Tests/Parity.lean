import Formal.Universal.Properties.UP014.Definition
import Formal.Universal.Properties.Tests.ParitySupport
import Formal.Universal.Standalone.LinearVesting.ContinuationOtherDatum

/-! Kernel equivalences with the original helpers and standalone propositions.
The standalone solver observations are not imported. -/

namespace Formal.Universal.Properties.UP014.Tests.Parity

open Formal.Universal.Properties.Tests.ParitySupport
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOut validScriptContext)
open Formal.Universal.Support.Continuations

theorem replacementEncoding (c1 c2 : Credential) (start finish recovery : Int) :
    IsData.toData
      ({ beneficiary := c1, locker := c2, vesting := [], start_time := start,
          end_time := finish, recovery_time := recovery } :
        Formal.Universal.Standalone.LinearVesting.Vesting.Types.VestingDatum) =
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
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationOtherDatum_claim :=
  ⟨fun h p c1 c2 start finish recovery => h (claimFromLegacy p) c1 c2 start finish recovery,
    fun h p c1 c2 start finish recovery => h (claimToLegacy p) c1 c2 start finish recovery⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationOtherDatum_claim_applies :=
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

end Formal.Universal.Properties.UP014.Tests.Parity

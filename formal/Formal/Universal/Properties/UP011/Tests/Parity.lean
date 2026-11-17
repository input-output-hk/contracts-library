import Formal.Universal.Properties.UP011.Definition
import Formal.Universal.Properties.Tests.ParitySupport
import Formal.Universal.Standalone.LinearVesting.ContinuationElsewhere

/-! Kernel equivalences with the original helpers and standalone propositions.
The standalone solver observations are not imported. -/

namespace Formal.Universal.Properties.UP011.Tests.Parity

open Formal.Universal.Properties.Tests.ParitySupport
open CardanoLedgerApi.V3 (Credential ScriptContext TxOut validScriptContext)

theorem changedOutputPreservesFields (o : TxOut) (c : Credential) :
    let changed : TxOut := { o with
      txOutAddress := { o.txOutAddress with addressCredential := c } }
    changed.txOutAddress.addressStakingCredential = o.txOutAddress.addressStakingCredential ∧
    changed.txOutValue = o.txOutValue ∧
    changed.txOutDatum = o.txOutDatum ∧
    changed.txOutReferenceScript = o.txOutReferenceScript := ⟨rfl, rfl, rfl, rfl⟩

theorem restoringOutputsRestoresContext (ctx : ScriptContext) (c : Credential) :
    withOutputs (changeContinuation ctx (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressCredential := c } }))
      ctx.scriptContextTxInfo.txInfoOutputs = ctx := rfl

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationElsewhere_claim :=
  ⟨fun h p c => h (claimFromLegacy p) c, fun h p c => h (claimToLegacy p) c⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationElsewhere_claim_applies :=
  ⟨fun ⟨p, c, evidence⟩ => ⟨claimToLegacy p, c, evidence⟩,
    fun ⟨p, c, evidence⟩ => ⟨claimFromLegacy p, c, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts rejects context) :
    statement valid accepts rejects context :=
  fun p c original accepted redirected unequal changed =>
    False.elim (absent ⟨p, c, original, accepted, redirected, unequal, changed⟩)

end Formal.Universal.Properties.UP011.Tests.Parity

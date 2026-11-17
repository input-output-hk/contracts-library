import Formal.Universal.Properties.UP007.Definition
import Formal.Universal.Properties.Tests.ParitySupport
import Formal.Universal.Standalone.LinearVesting.ContinuationStake

/-! Kernel equivalences with the original helpers and standalone propositions.
Shared support preserves independent native and legacy helper comparisons. -/

namespace Formal.Universal.Properties.UP007.Tests.Parity

open Formal.Universal.Properties.Tests.ParitySupport
open CardanoLedgerApi.V3 (ScriptContext StakingCredential TxOut validScriptContext)
open Formal.Universal.Support.Continuations

theorem changedOutputPreservesFields (o : TxOut) (sc : Option StakingCredential) :
    let changed : TxOut :=
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }
    changed.txOutAddress.addressStakingCredential = sc ∧
    changed.txOutAddress.addressCredential = o.txOutAddress.addressCredential ∧
    changed.txOutValue = o.txOutValue ∧
    changed.txOutDatum = o.txOutDatum ∧
    changed.txOutReferenceScript = o.txOutReferenceScript := ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem changedContextPreservesFields (ctx : ScriptContext) (sc : Option StakingCredential) :
    let changed := changeContinuation ctx (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })
    changed.scriptContextRedeemer = ctx.scriptContextRedeemer ∧
    changed.scriptContextScriptInfo = ctx.scriptContextScriptInfo ∧
    { changed.scriptContextTxInfo with txInfoOutputs := ctx.scriptContextTxInfo.txInfoOutputs } =
      ctx.scriptContextTxInfo := ⟨rfl, rfl, rfl⟩

theorem restoringOutputsRestoresContext (ctx : ScriptContext) (sc : Option StakingCredential) :
    withOutputs (changeContinuation ctx (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }))
      ctx.scriptContextTxInfo.txInfoOutputs = ctx := rfl

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationStake_claim :=
  ⟨fun h p sc => h (claimFromLegacy p) sc,
    fun h p sc => h (claimToLegacy p) sc⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      Formal.Universal.Standalone.LinearVesting.continuationStake_claim_applies :=
  ⟨fun ⟨p, sc, evidence⟩ => ⟨claimToLegacy p, sc, evidence⟩,
    fun ⟨p, sc, evidence⟩ => ⟨claimFromLegacy p, sc, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts rejects context) :
    statement valid accepts rejects context :=
  fun p sc original accepted redirected unequal changed =>
    False.elim (absent ⟨p, sc, original, accepted, redirected, unequal, changed⟩)

end Formal.Universal.Properties.UP007.Tests.Parity

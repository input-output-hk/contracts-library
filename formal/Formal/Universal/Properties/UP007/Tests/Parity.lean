import Formal.Universal.Properties.UP007.Definition
import Formal.Universal.Properties.UP014.Tests.Parity
import Formal.Universal.Standalone.LinearVesting.ContinuationStake

/-! Kernel equivalences with the original helpers and standalone propositions.
The UP-014 helper proofs are reused only by tests; historical solver observations are not imported. -/

namespace Formal.Universal.Properties.UP007.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext StakingCredential TxOut validScriptContext)
open Formal.Universal.Support.Continuations
open UP000.Tests.Parity (claimToLegacy claimFromLegacy preparedAccepts)
open UP004.Tests.Parity (preparedRejects)

theorem withOutputsParity : withOutputs = Formal.Universal.Support.withOutputs :=
  UP014.Tests.Parity.withOutputsParity

theorem keyAddrParity : keyAddr = Formal.Universal.Support.keyAddr := UP014.Tests.Parity.keyAddrParity

theorem ownInputParity : ownInput? = Formal.Universal.Support.ownInput? := UP014.Tests.Parity.ownInputParity

theorem attackerKeyParity : attackerKey = Formal.Universal.Support.attackerKey := UP014.Tests.Parity.attackerKeyParity

theorem redirectParity : redirectContinuations = Formal.Universal.Support.redirectContinuations :=
  UP014.Tests.Parity.redirectParity

theorem isContinuationParity : isContinuation = Formal.Universal.Support.isContinuation :=
  UP014.Tests.Parity.isContinuationParity

theorem changeFirstParity : changeFirst = Formal.Universal.Support.changeFirst := UP014.Tests.Parity.changeFirstParity

theorem changeContinuationParity : changeContinuation = Formal.Universal.Support.changeContinuation :=
  UP014.Tests.Parity.changeContinuationParity

theorem firstContinuationParity : firstContinuation? = Formal.Universal.Support.firstContinuation? :=
  UP014.Tests.Parity.firstContinuationParity

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

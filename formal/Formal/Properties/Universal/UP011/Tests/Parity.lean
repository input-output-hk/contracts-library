import Formal.Properties.Universal.UP011.Definition
import Formal.Properties.Universal.UP004.Tests.Parity
import Formal.Vesting.Linear.Blueprint.ContinuationElsewhere

/-! Kernel equivalences with the original helpers and standalone propositions.
The standalone solver observations are not imported. -/

namespace Formal.Properties.Universal.UP011.Tests.Parity

open CardanoLedgerApi.V3 (Credential ScriptContext TxOut validScriptContext)
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
      simp only [changeFirst, Formal.Support.Continuations.changeFirst, Formal.Support.changeFirst, ih]

theorem changeContinuationParity : changeContinuation = Formal.Support.changeContinuation := by
  funext ctx transform
  simp only [changeContinuation, Formal.Support.Continuations.changeContinuation, Formal.Support.changeContinuation,
    withOutputsParity, isContinuationParity, changeFirstParity]

theorem firstContinuationParity : firstContinuation? = Formal.Support.firstContinuation? := rfl

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
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      Formal.Vesting.Linear.Blueprint.continuationElsewhere_claim :=
  ⟨fun h p c => h (claimFromLegacy p) c, fun h p c => h (claimToLegacy p) c⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      Formal.Vesting.Linear.Blueprint.continuationElsewhere_claim_applies :=
  ⟨fun ⟨p, c, evidence⟩ => ⟨claimToLegacy p, c, evidence⟩,
    fun ⟨p, c, evidence⟩ => ⟨claimFromLegacy p, c, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts rejects context) :
    statement valid accepts rejects context :=
  fun p c original accepted redirected unequal changed =>
    False.elim (absent ⟨p, c, original, accepted, redirected, unequal, changed⟩)

end Formal.Properties.Universal.UP011.Tests.Parity

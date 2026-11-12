import Formal.Support.Continuations

namespace Formal.Properties.Universal.UP007

open CardanoLedgerApi.V3 (ScriptContext StakingCredential)
open Formal.Support.Continuations

/-- Changing the first continuation's staking credential requires rejection under these five guards. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p (sc : Option StakingCredential),
    valid (context p) = true →
    accepts (context p) →
    rejects (redirectContinuations (context p)) →
    (firstContinuation? (context p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
      false →
    valid (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true →
    rejects (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }))

/-- A context and optional staking credential satisfying all five guards witness applicability. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, ∃ (sc : Option StakingCredential),
    valid (context p) = true ∧
    accepts (context p) ∧
    rejects (redirectContinuations (context p)) ∧
    (firstContinuation? (context p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
      false ∧
    valid (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true

end Formal.Properties.Universal.UP007

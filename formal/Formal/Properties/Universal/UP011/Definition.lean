import Formal.Support.Continuations

namespace Formal.Properties.Universal.UP011

open CardanoLedgerApi.V3

abbrev withOutputs := Formal.Support.Continuations.withOutputs

abbrev keyAddr := Formal.Support.Continuations.keyAddr

abbrev ownInput? := Formal.Support.Continuations.ownInput?

abbrev attackerKey := Formal.Support.Continuations.attackerKey

abbrev redirectContinuations := Formal.Support.Continuations.redirectContinuations

abbrev isContinuation := Formal.Support.Continuations.isContinuation

abbrev changeFirst := Formal.Support.Continuations.changeFirst

abbrev changeContinuation := Formal.Support.Continuations.changeContinuation

abbrev firstContinuation? := Formal.Support.Continuations.firstContinuation?

/-- Changing the first continuation's payment credential requires rejection under these five guards. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p (c : Credential),
    valid (context p) = true →
    accepts (context p) →
    rejects (redirectContinuations (context p)) →
    (firstContinuation? (context p)).any (fun o => o.txOutAddress.addressCredential == c) = false →
    valid (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true →
    rejects (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressCredential := c } }))

/-- A context and credential satisfying all five guards witness applicability. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, ∃ (c : Credential),
    valid (context p) = true ∧
    accepts (context p) ∧
    rejects (redirectContinuations (context p)) ∧
    (firstContinuation? (context p)).any (fun o => o.txOutAddress.addressCredential == c) = false ∧
    valid (changeContinuation (context p) (fun o =>
      { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true

end Formal.Properties.Universal.UP011

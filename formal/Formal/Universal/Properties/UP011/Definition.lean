import Formal.Universal.Support.Continuations

namespace Formal.Universal.Properties.UP011

open CardanoLedgerApi.V3

abbrev withOutputs := Formal.Universal.Support.Continuations.withOutputs

abbrev keyAddr := Formal.Universal.Support.Continuations.keyAddr

abbrev ownInput? := Formal.Universal.Support.Continuations.ownInput?

abbrev attackerKey := Formal.Universal.Support.Continuations.attackerKey

abbrev redirectContinuations := Formal.Universal.Support.Continuations.redirectContinuations

abbrev isContinuation := Formal.Universal.Support.Continuations.isContinuation

abbrev changeFirst := Formal.Universal.Support.Continuations.changeFirst

abbrev changeContinuation := Formal.Universal.Support.Continuations.changeContinuation

abbrev firstContinuation? := Formal.Universal.Support.Continuations.firstContinuation?

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

end Formal.Universal.Properties.UP011

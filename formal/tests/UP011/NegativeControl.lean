import Blaster
import Formal.Vesting.Linear.Blueprint.Tx
import tests.UP011.Fixture

set_option Elab.async false
set_option warningAsError true

namespace Tests.UP011

open CardanoLedgerApi.V3 (Credential validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint (claim)

#eval Fixture.checkSource

-- Exact Claim formulas with only the executed program changed to the faulty fixture.
def ignoresPaymentCredential_claim : Prop :=
    ∀ p (c : Credential),
      validScriptContext (claim p) = true →
      Fixture.accepts ledgerFuel (claim p) →
      Fixture.rejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressCredential == c) = false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true →
      Fixture.rejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } }))

/-- The faulty validator must satisfy the same applicability premises. -/
def ignoresPaymentCredential_claim_applies : Prop :=
    ∃ p, ∃ (c : Credential),
      validScriptContext (claim p) = true ∧
      Fixture.accepts ledgerFuel (claim p) ∧
      Fixture.rejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressCredential == c) = false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true

-- Expected: Falsified property and Valid applicability. The false property is
-- observed by a command, never declared as a theorem with an admitted proof.
#blaster (solve-result: 1) [ignoresPaymentCredential_claim]
#blaster [ignoresPaymentCredential_claim_applies]

end Tests.UP011

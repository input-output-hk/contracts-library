import Formal.Vesting.Linear.Blueprint.JunkToken

namespace Tests.UP008.Enforcing

open PlutusCore.UPLC.Term (Program Term Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext TxOutRef validScriptContext)
open Formal.Universal.Properties
open Formal.Vesting.Linear.Blueprint (claim)

/-!
Compiled from tests/UP008/Project/validators/enforcing.ak with
Aiken v1.1.21+42babe5, stdlib v3.0.0, and Plutus V3. The source project is
Apache-2.0. Artifacts.lean checks source hashes against the frozen blueprint and
provides a separate optional check of the rebuilt program.
-/

def compiledCode : String := "5901e401010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cc0200092225980099b8748008c01cdd500144c8c8cc896600266e1d2000300b3754005132325980099b8748008c034dd5000c4c96600266ebcc048c03cdd5180918079baa0013374a900119808980918079baa0024bd7044cdc399199119801001000912cc00400600713233225980099b914881087a7a7a7a6a756e6b000028acc004cdc7a441087a7a7a7a6a756e6b000028800c01901344cc014014c0640110131bae3012001375a6026002602a0028098c8c8cc004004dd5980318091baa0042259800800c00e2646644b3001337229101087a7a7a7a6a756e6b000028acc004cdc7a441087a7a7a7a6a756e6b000028800c01901444cc014014c0680110141bae301300137566028002602c00280a052f5bded8c0290002400114a08068c044dd618089809180918071baa0078b20183010300d37546020601a6ea8c004c034dd5180818069baa0032301030110018b201432330010013758601c60166ea8010896600200314c0103d87a80008992cc004cdd7980818069baa001004899ba548000cc03c0052f5c11330030033011002402c601e0028068c034c038008c030004c020dd50014590060c020004c00cdd5004452689b2b20021"

def declaredScriptHash : String := "e21ca2707f829187d132ebade676ffabe0bcb43cb191625ee4143e5f"

def program : Program := singleCborEncodedScriptFromHexM "5901e401010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cc0200092225980099b8748008c01cdd500144c8c8cc896600266e1d2000300b3754005132325980099b8748008c034dd5000c4c96600266ebcc048c03cdd5180918079baa0013374a900119808980918079baa0024bd7044cdc399199119801001000912cc00400600713233225980099b914881087a7a7a7a6a756e6b000028acc004cdc7a441087a7a7a7a6a756e6b000028800c01901344cc014014c0640110131bae3012001375a6026002602a0028098c8c8cc004004dd5980318091baa0042259800800c00e2646644b3001337229101087a7a7a7a6a756e6b000028acc004cdc7a441087a7a7a7a6a756e6b000028800c01901444cc014014c0680110141bae301300137566028002602c00280a052f5bded8c0290002400114a08068c044dd618089809180918071baa0078b20183010300d37546020601a6ea8c004c034dd5180818069baa0032301030110018b201432330010013758601c60166ea8010896600200314c0103d87a80008992cc004cdd7980818069baa001004899ba548000cc03c0052f5c11330030033011002402c601e0028068c034c038008c030004c020dd50014590060c020004c00cdd5004452689b2b20021"

def args (ctx : ScriptContext) : List Term := [toTerm ctx]

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin program (args ctx) fuel

/-- Same Claim model, mutation, guards, and fuel as the original proposition;
    only the evaluated program changes to the enforcing control. -/
def junkToken_claim : Prop :=
    ∀ p (r : TxOutRef) (a : Int),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      validScriptContext (addJunkFrom (claim p) r a) = true →
      rejects ledgerFuel (addJunkFrom (claim p) r a)

/-- The enforcing control has an accepted, model-valid baseline and a
    model-valid mutation while retaining the continuation-reliance guard. -/
def junkToken_claim_applies : Prop :=
    ∃ p, ∃ (r : TxOutRef), ∃ (a : Int),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      validScriptContext (addJunkFrom (claim p) r a) = true

end Tests.UP008.Enforcing

import Formal.Vesting.Linear.Blueprint.ContinuationStake

namespace Formal.Tests.UP007

open PlutusCore.UPLC.Term (Term Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open PlutusCore.UPLC.PlutusScript
open CardanoLedgerApi.V3 (ScriptContext StakingCredential validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint (claim args)

/-- Frozen Aiken v1.1.21 control; see Project/validators/stake_control.ak and artifact.json. -/
def controlScript : PlutusScript :=
  ⟨.PlutusV3, singleCborEncodedScriptFromHexM "58f301010029800aba2aba1aab9faab9eaab9dab9a48888896600264653001300700198039804000cc01c0092225980099b8748008c01cdd500144c8cc8a600264660020026eb0c038c030dd5002912cc0040062d1325980099baf3010300e375400200b13004300e375400313300300330110024030601e0028072601a6eb0c034c038c038c02cdd50024c034c03800d2225980099baf3010300e37546020601c6ea8008c040c038dd5180818071baa003899baf3004300e37546020601c6ea8008c010c038dd5180818071baa0038a504030300b0012300c300d0013008375400516401830070013003375400f149a26cac80081"⟩

def controlProgram : Program := controlScript.script

def controlScriptHashHex : String := "d94e30a6868bb280eba4c6479283a5cfd60f78d40698410ed383a590"

/-- Successful unit halt within the same CEK bound used by the original candidate. -/
def controlAccepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram controlProgram (args ctx) fuel = .Halt (.VCon Const.Unit)

def controlRejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin controlProgram (args ctx) fuel

/-- The original Claim rejection proposition with only the executed program replaced. -/
def controlClaim : Prop :=
    ∀ p (sc : Option StakingCredential),
      validScriptContext (claim p) = true →
      controlAccepts ledgerFuel (claim p) →
      controlRejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true →
      controlRejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }))

def controlClaimApplies : Prop :=
    ∃ p, ∃ (sc : Option StakingCredential),
      validScriptContext (claim p) = true ∧
      controlAccepts ledgerFuel (claim p) ∧
      controlRejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true

end Formal.Tests.UP007

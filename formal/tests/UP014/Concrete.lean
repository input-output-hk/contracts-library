import tests.UP014.Support

namespace Tests.UP014.Concrete

open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (initialState applyParams)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint (ClaimLeaves claim args)

/-- A concrete witness in the unchanged Claim model. -/
def leaves : ClaimLeaves :=
  { beneficiary := "01", locker := "02", name := "00", total := 10,
    start := 0, finish := 100, recovery := 200,
    script := "4acb3c5a1cc296397cc47d74bd21269e2fa7c64264851de8bc89306b",
    prevTx := "00", txId := "01", scriptAda := 10, feeInputAda := 10,
    keptAda := 10, kept := 5, fee := 1, now := 50, signer := "01" }

def baseline : ScriptContext := claim leaves

def replacement : Data := .Constr 0 [.Constr 0 [.B "01"], .Constr 0 [.B "02"],
  .List [], .I 0, .I 100, .I 200]

def differentDatum : Bool :=
  (firstContinuation? baseline).any (fun o => o.txOutDatum == .OutputDatum replacement) == false

def withReplacement (ctx : ScriptContext) : ScriptContext :=
  changeContinuation ctx (fun o => { o with txOutDatum := .OutputDatum replacement })

def mutated : ScriptContext := withReplacement baseline

def vestingBaseline : ScriptContext :=
  claim { leaves with script := "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a" }

/-- Classify the bounded execution without treating exhaustion as rejection. -/
def result (program : Program) (ctx : ScriptContext) : String :=
  match program with
  | .Program _ body =>
    match runFor (initialState (applyParams body (args ctx))) ledgerFuel with
    | some (.Halt (.VCon Const.Unit)) => "accepted"
    | some .Error => "rejected"
    | some (.Halt _) => "rejected"
    | _ => "exhausted"

#eval do
  unless validScriptContext baseline && validScriptContext mutated &&
      validScriptContext vestingBaseline && validScriptContext (withReplacement vestingBaseline) do
    throw (IO.userError "UP014 concrete baseline or mutation is not model-valid")
  unless differentDatum do
    throw (IO.userError "UP014 concrete replacement must differ from the baseline")
  for (label, program, ctx, expected) in [
      ("synthetic baseline", Control.program, baseline, "accepted"),
      ("synthetic changed datum", Control.program, mutated, "accepted"),
      ("synthetic redirection", Control.program, redirectContinuations baseline, "rejected"),
      ("vesting baseline", Formal.Vesting.Linear.Blueprint.program, vestingBaseline, "accepted"),
      ("vesting changed datum", Formal.Vesting.Linear.Blueprint.program,
        withReplacement vestingBaseline, "rejected"),
      ("vesting redirection", Formal.Vesting.Linear.Blueprint.program,
        redirectContinuations vestingBaseline, "rejected")] do
    let observed := result program ctx
    unless observed == expected do
      throw (IO.userError s!"UP014 {label}: expected {expected}, got {observed}")
    IO.println s!"UP014 {label}: {observed}"

end Tests.UP014.Concrete

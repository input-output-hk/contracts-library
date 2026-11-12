import Formal.Properties.Universal.UP006.Tests.Standalone.Fixture

namespace UP006

open Formal.Support.ReturnDatum (allReturnDatumsValid)
open Formal.Support (ledgerFuel)
open CardanoLedgerApi.V3 (validScriptContext)

theorem originalConforms :
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      original.scriptContextTxInfo.txInfoOutputs = true := rfl

/-- The third output has the actual script credential and no datum. -/
theorem extraOutputPredicateFalse :
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      extraOutput.scriptContextTxInfo.txInfoOutputs = false := rfl

/-- Predicate-only control: a matching output with a conforming inline datum passes.
This statement does not claim validator acceptance of the modified context. -/
theorem inlineDatumSensitivity :
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      [continuation, payout 5000000, { extraDatumless with txOutDatum := .OutputDatum datum }]
      = true := rfl

/-- Inline presence alone is insufficient: the decoder rejects an integer datum. -/
theorem malformedDatumSensitivity :
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      [continuation, payout 5000000, { extraDatumless with txOutDatum := .OutputDatum (.I 0) }]
      = false := rfl

/-- A datumless output to another payment credential is outside the predicate. -/
theorem paymentCredentialSensitivity :
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      [continuation, payout 5000000,
       { extraDatumless with txOutAddress := ⟨.ScriptCredential "other", none⟩ }]
      = true := rfl

/-- Specializing the unrestricted goal to this witness yields a contradiction. -/
theorem returnDatumFalsifiedOfWitness
    (hValid : validScriptContext extraOutput = true)
    (hAccepted : accepts ledgerFuel extraOutput) : ¬ returnDatumGoal := by
  intro hGoal
  have hTrue := hGoal extraOutput hValid hAccepted
  have hImpossible : false = true := extraOutputPredicateFalse.symm.trans hTrue
  cases hImpossible

end UP006

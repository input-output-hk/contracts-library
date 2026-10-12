/-
Universal properties of the V3 ledger model: true for every transaction the model
accepts (`validTxInfo`), independent of any validator.
-/
import Blaster
import CardanoLedgerApi

namespace Formal.Universal.Ledger

open CardanoLedgerApi.IsData.Class
open CardanoLedgerApi.V3
open PlutusCore.Integer (Integer)

/-- A valid transaction spends at least one input. -/
theorem inputs_ne_nil
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true) :
  ctx.scriptContextTxInfo.txInfoInputs ≠ [] := by
    simp_all [validTxInfo, validInputs]
    intro h
    simp [h] at hValid

/-- A valid transaction pays a strictly positive fee. -/
theorem fee_pos
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true) :
  0 < ctx.scriptContextTxInfo.txInfoFee := by
    blaster

/-- A valid transaction never mints or burns ada. -/
theorem mint_lovelace_eq_zero
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true) :
  lovelaceOf ctx.scriptContextTxInfo.txInfoMint = 0 := by
    unfold lovelaceOf
    split
    · simp_all [validTxInfo, Contexts.validMintValue, Contexts.validMintValue.validCurrencySymbol, adaSymbol]
    · rfl

/-- If nothing is minted, non-ada tokens are conserved. -/
theorem tokens_conserved_of_no_mint
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true)
  (hNoMint : ctx.scriptContextTxInfo.txInfoMint = []) :
  withoutLovelace (valueSpent ctx) = withoutLovelace (valueProduced ctx) := by
    have mergeNil (v : Value) : merge v [] = v := by
      cases v <;> simp [merge, CardanoLedgerApi.V1.Value.merge.cs_visit]
    simp_all [validTxInfo, isBalanced]

/-- The model's ada rule: input ada = output ada + fee. On chain, withdrawals,
refunds, deposits and donations also move ada; the model ignores them. -/
theorem ada_balanced
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true) :
  lovelaceOf (valueSpent ctx) = lovelaceOf (valueProduced ctx) + ctx.scriptContextTxInfo.txInfoFee := by
    blaster

/-- In the model, outputs hold strictly less ada than inputs. -/
theorem ada_decreases
  (ctx : ScriptContext)
  (hValid : validTxInfo ctx = true) :
  lovelaceOf (valueProduced ctx) < lovelaceOf (valueSpent ctx) := by
    simp_all [validTxInfo, isBalanced]
    blaster

/-- `ada_balanced` restricted to transactions with no withdrawals, certificates,
proposals or donation: the scope where the model's rule matches the chain's. The
extra hypotheses state that scope; the proof does not need them. -/
theorem ada_balanced_of_simple_tx (ctx : ScriptContext)
    (hValid : validTxInfo ctx = true)
    (_hNoWdrl : ctx.scriptContextTxInfo.txInfoWdrl = [])
    (_hNoCert : ctx.scriptContextTxInfo.txInfoTxCerts = [])
    (_hNoProp : ctx.scriptContextTxInfo.txInfoProposalProcedures = [])
    (_hNoDon : ctx.scriptContextTxInfo.txInfoTreasuryDonation = IsData.toData (none : Option Integer)) :
    lovelaceOf (valueSpent ctx) = lovelaceOf (valueProduced ctx) + ctx.scriptContextTxInfo.txInfoFee := by
      simp_all [validTxInfo, isBalanced]

end Formal.Universal.Ledger

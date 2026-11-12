import Blaster
import Formal.Vault.Blueprint.UP009Structural

set_option Elab.async false

namespace Formal.Vault.Blueprint.UP009

open CardanoLedgerApi.V3
open Formal.Support (ledgerFuel)

theorem hashed_valid : validScriptContext Tx.hashed = true := by
  blaster

theorem hashed_accepts : accepts ledgerFuel Tx.hashed := by
  blaster

/-- One concrete accepted hashed-datum spend proves the existential property. -/
theorem hashed_datum_spendable : statement :=
  ⟨Tx.hashed, hashed_valid, hashed_own_input, hashed_accepts⟩

/-- Supplying a datum without its matching witness-map entry is inconsistent. -/
theorem missing_map_invalid : validScriptContext Tx.missingMap = false := by
  blaster

/-- The map must contain the supplied datum, not merely the expected lookup key. -/
theorem wrong_map_value_invalid : validScriptContext Tx.wrongMapValue = false := by
  blaster

/-- The model permits this context even though the vault requires its owner signature. -/
theorem missing_signature_valid : validScriptContext Tx.missingSignature = true := by
  blaster

theorem missing_signature_rejected : rejects ledgerFuel Tx.missingSignature := by
  blaster

theorem inline_valid : validScriptContext Tx.inline = true := by
  blaster

theorem inline_accepts : accepts ledgerFuel Tx.inline := by
  blaster

end Formal.Vault.Blueprint.UP009

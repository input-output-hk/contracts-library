import Formal.Vault.Blueprint.UP009Definition

set_option Elab.async false

namespace Formal.Vault.Blueprint.UP009

open CardanoLedgerApi.V3

/-- Resolving a singleton input by its own reference returns that input. -/
theorem resolveInput_singleton (own : TxInInfo) :
    resolveInput own.txInInfoOutRef [own] = some own := by
  change (if own.txInInfoOutRef == own.txInInfoOutRef then some own else none) = some own
  simp

/-- Looking up a singleton datum map returns its datum for every hash value. -/
theorem findDatum_singleton (hash : DatumHash) (datum : Datum) :
    CardanoLedgerApi.V2.findDatum hash [(hash, datum)] = some datum := by
  change (if hash == hash then some datum else none) = some datum
  simp

/-- Bind the hash input to the actual datum, rather than an arbitrary map key. -/
theorem actualDatum_serializes :
    PlutusCore.Cbor.encodeData Tx.actualDatum = some Tx.datumBytes := by
  decide

theorem hashed_own_input : hashedOwnInput Tx.hashed := by
  refine ⟨Tx.ownRef, Tx.actualDatum, Tx.ownInput, Tx.datumBytes, rfl, ?_, rfl,
    actualDatum_serializes, rfl, ?_⟩
  · exact resolveInput_singleton Tx.ownInput
  · exact findDatum_singleton Tx.datumHash Tx.actualDatum

end Formal.Vault.Blueprint.UP009

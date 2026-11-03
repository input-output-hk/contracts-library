import Formal.Vault.Blueprint.Tx

namespace Formal.Vault.Blueprint.UP009

open CardanoLedgerApi.V3
open Formal.Universal.Properties (ledgerFuel)

/-- The current spending input uses the hash of its supplied datum's serialized bytes,
and the transaction's datum map resolves that hash to the supplied datum. -/
def hashedOwnInput (ctx : ScriptContext) : Prop :=
  ∃ ref datum own bytes,
    ctx.scriptContextScriptInfo = .SpendingScript ref (some datum) ∧
    resolveInput ref ctx.scriptContextTxInfo.txInfoInputs = some own ∧
    own.txInInfoResolved.txOutAddress.addressCredential = .ScriptCredential scriptHash ∧
    PlutusCore.Cbor.encodeData datum = some bytes ∧
    own.txInInfoResolved.txOutDatum = .OutputDatumHash (Tx.hashDatumBytes bytes) ∧
    CardanoLedgerApi.V2.findDatum (Tx.hashDatumBytes bytes)
      ctx.scriptContextTxInfo.txInfoData = some datum

/-- UP-009 for this frozen vault: at least one valid model context spends a hashed
own input with its datum provided and is accepted within 1,000,000 CEK steps. -/
def statement : Prop :=
  ∃ ctx, validScriptContext ctx = true ∧ hashedOwnInput ctx ∧ accepts ledgerFuel ctx

end Formal.Vault.Blueprint.UP009

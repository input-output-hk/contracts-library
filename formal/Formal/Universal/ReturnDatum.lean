import CardanoLedgerApi

namespace Formal.Universal.ReturnDatum

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (ScriptHash TxOut)

/-- Every output to `scriptHash` must have an inline datum accepted by `hasType`.
    All matching payment credentials count, regardless of position, staking
    credential, or whether the protocol requires that output. -/
def allReturnDatumsValid
    (scriptHash : ScriptHash) (hasType : Data → Bool) (outputs : List TxOut) : Bool :=
  outputs.all fun output =>
    if output.txOutAddress.addressCredential == .ScriptCredential scriptHash then
      match output.txOutDatum with
      | .OutputDatum datum => hasType datum
      | _ => false
    else true

end Formal.Universal.ReturnDatum

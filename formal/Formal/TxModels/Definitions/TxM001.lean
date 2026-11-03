import Formal.TxModels.Common

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EveryMint where
  txInfo : TxInfo
  policy : CurrencySymbol

def EveryMint.ctx (t : EveryMint) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.MintingScript t.policy)

namespace TxM001

def metadata : Metadata := {
  id := "TxM-001"
  title := "Open minting context"
  plutus_version := "v3"
  description := "Minting contexts with arbitrary transaction information, policy ID, and redeemer. The constructor fixes the script purpose to minting and adds no ledger-validity conditions." }

end TxM001
end Formal.TxModels

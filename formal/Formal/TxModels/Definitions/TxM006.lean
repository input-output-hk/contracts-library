import Formal.TxModels.Common

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EverySpend where
  txInfo : TxInfo
  ref : TxOutRef
  datum : Option Datum

def EverySpend.ctx (t : EverySpend) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.SpendingScript t.ref t.datum)

namespace TxM006

def metadata : Metadata := {
  id := "TxM-006"
  title := "Open spending context"
  plutus_version := "v3"
  description := "Spending contexts with arbitrary transaction information, spent-output reference, optional datum, and redeemer. The constructor fixes the script purpose to spending and adds no ledger-validity conditions." }

end TxM006
end Formal.TxModels

import Formal.TxModels.Common
import Formal.TxModels.Runnable

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EveryWithdraw where
  txInfo : TxInfo
  cred : Credential

def EveryWithdraw.ctx (t : EveryWithdraw) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.RewardingScript t.cred)

namespace TxM002

def metadata : Metadata := {
  id := "TxM-002"
  title := "Open withdrawal context"
  plutus_version := "v3"
  description := "Reward withdrawal contexts with arbitrary transaction information, credential, and redeemer. The constructor fixes the script purpose to rewarding and adds no ledger-validity conditions." }

/-- Expose the unchanged context family to property-owned runs. -/
def runnable : Runnable := {
  metadata
  context := ``EveryWithdraw.ctx
  admission := .unparameterizedV3
  purpose := some .withdraw }

end TxM002
end Formal.TxModels

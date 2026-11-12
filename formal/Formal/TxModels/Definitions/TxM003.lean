import Formal.TxModels.Common
import Formal.TxModels.Runnable

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EveryPublish where
  txInfo : TxInfo
  idx : Int
  cert : TxCert

def EveryPublish.ctx (t : EveryPublish) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.CertifyingScript t.idx t.cert)

namespace TxM003

def metadata : Metadata := {
  id := "TxM-003"
  title := "Open certificate context"
  plutus_version := "v3"
  description := "Certifying contexts with arbitrary transaction information, certificate index, certificate, and redeemer. The constructor fixes the script purpose to certifying and adds no ledger-validity conditions." }

/-- Expose the unchanged context family to property-owned runs. -/
def runnable : Runnable := {
  metadata
  context := ``EveryPublish.ctx
  admission := .unparameterizedV3
  purpose := some .publish }

end TxM003
end Formal.TxModels

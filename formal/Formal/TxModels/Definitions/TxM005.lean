import Formal.TxModels.Common

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EveryPropose where
  txInfo : TxInfo
  idx : Int
  proposal : ProposalProcedure

def EveryPropose.ctx (t : EveryPropose) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.ProposingScript t.idx t.proposal)

namespace TxM005

def metadata : Metadata := {
  id := "TxM-005"
  title := "Open proposal context"
  plutus_version := "v3"
  description := "Proposing contexts with arbitrary transaction information, proposal index, proposal procedure, and redeemer. The constructor fixes the script purpose to proposing and adds no ledger-validity conditions." }

end TxM005
end Formal.TxModels

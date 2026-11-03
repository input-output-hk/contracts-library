import Formal.TxModels.Common

namespace Formal.TxModels

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

structure EveryVote where
  txInfo : TxInfo
  voter : Voter

def EveryVote.ctx (t : EveryVote) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.VotingScript t.voter)

namespace TxM004

def metadata : Metadata := {
  id := "TxM-004"
  title := "Open voting context"
  plutus_version := "v3"
  description := "Voting contexts with arbitrary transaction information, voter, and redeemer. The constructor fixes the script purpose to voting and adds no ledger-validity conditions." }

end TxM004
end Formal.TxModels

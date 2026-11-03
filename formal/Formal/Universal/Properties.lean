import PlutusCore.UPLC
import CardanoLedgerApi
import Formal.TxModels.Index

/-! Execution and script-context helpers used by generated blueprint checks.
Extracted from fork PR #44 at 99a5734f0e036b6abfb4c3f121a298e35fa2eff6.
-/

namespace Formal.Universal.Properties

open PlutusCore.UPLC.Term (Program Term Const)
open PlutusCore.UPLC.CekMachine (State step initialState applyParams)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

/-- CEK step bound used by generated checks; not a ledger CPU or memory budget. -/
abbrev ledgerFuel : Nat := 1000000

/-- `none` means the step bound was exhausted before a halt or error. -/
def runFor : State → Nat → Option State
  | .Halt v, _ => some (.Halt v)
  | .Error, _ => some .Error
  | _, 0 => none
  | s, n + 1 => runFor (step default s) n

/-- Error or a non-unit halt within `fuel` steps. Exhaustion is not rejection. -/
def rejectedWithin (p : Program) (args : List Term) (fuel : Nat) : Prop :=
  match p with
  | .Program _ body =>
      match runFor (initialState (applyParams body args)) fuel with
      | some .Error => True
      | some (.Halt v) => v ≠ .VCon Const.Unit
      | _ => False

/-- Compatibility names for the models now owned by Formal.TxModels. -/
abbrev mkCtx := Formal.TxModels.mkCtx

abbrev EverySpend := Formal.TxModels.EverySpend
abbrev EverySpend.ctx := Formal.TxModels.EverySpend.ctx

abbrev EveryMint := Formal.TxModels.EveryMint
abbrev EveryMint.ctx := Formal.TxModels.EveryMint.ctx

abbrev EveryWithdraw := Formal.TxModels.EveryWithdraw
abbrev EveryWithdraw.ctx := Formal.TxModels.EveryWithdraw.ctx

abbrev EveryPublish := Formal.TxModels.EveryPublish
abbrev EveryPublish.ctx := Formal.TxModels.EveryPublish.ctx

abbrev EveryVote := Formal.TxModels.EveryVote
abbrev EveryVote.ctx := Formal.TxModels.EveryVote.ctx

abbrev EveryPropose := Formal.TxModels.EveryPropose
abbrev EveryPropose.ctx := Formal.TxModels.EveryPropose.ctx

def signatoriesOf (h : ScriptContext) : List PubKeyHash := h.scriptContextTxInfo.txInfoSignatories

def withSignatories (h : ScriptContext) (sigs : List PubKeyHash) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoSignatories := sigs } }

end Formal.Universal.Properties

namespace Formal.Universal.TxBuilder

abbrev ada := Formal.TxModels.TxBuilder.ada
abbrev adaAnd := Formal.TxModels.TxBuilder.adaAnd
abbrev keyAddress := Formal.TxModels.TxBuilder.keyAddress
abbrev scriptAddress := Formal.TxModels.TxBuilder.scriptAddress
abbrev toKey := Formal.TxModels.TxBuilder.toKey
abbrev toScript := Formal.TxModels.TxBuilder.toScript
abbrev input := Formal.TxModels.TxBuilder.input
abbrev Spend := Formal.TxModels.TxBuilder.Spend
abbrev Spend.context := Formal.TxModels.TxBuilder.Spend.context

end Formal.Universal.TxBuilder

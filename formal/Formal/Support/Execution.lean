import PlutusCore.UPLC
import CardanoLedgerApi

/-! Evaluator and context operations without a transaction-model catalogue dependency. -/

namespace Formal.Support

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

def signatoriesOf (h : ScriptContext) : List PubKeyHash := h.scriptContextTxInfo.txInfoSignatories

def withSignatories (h : ScriptContext) (sigs : List PubKeyHash) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoSignatories := sigs } }


end Formal.Support

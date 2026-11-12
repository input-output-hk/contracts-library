import Formal.Properties.Universal.UP000.Definition
import Formal.TxModels.Definitions.TxM007
import Formal.TxModels.Definitions.TxM008
import Formal.Vesting.Linear.Blueprint.Tx

/-! Kernel equivalences with the frozen standalone context and evaluator definitions.
The historical existential proofs are deliberately not imported. -/

namespace Formal.Properties.Universal.UP000.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

def claimToLegacy (p : TxModels.TxM007.ClaimLeaves) :
    Formal.Vesting.Linear.Blueprint.ClaimLeaves := {
  beneficiary := p.beneficiary
  locker := p.locker
  name := p.name
  total := p.total
  start := p.start
  finish := p.finish
  recovery := p.recovery
  script := p.script
  prevTx := p.prevTx
  txId := p.txId
  scriptAda := p.scriptAda
  feeInputAda := p.feeInputAda
  keptAda := p.keptAda
  kept := p.kept
  fee := p.fee
  now := p.now
  signer := p.signer }

def claimFromLegacy (p : Formal.Vesting.Linear.Blueprint.ClaimLeaves) :
    TxModels.TxM007.ClaimLeaves := {
  beneficiary := p.beneficiary
  locker := p.locker
  name := p.name
  total := p.total
  start := p.start
  finish := p.finish
  recovery := p.recovery
  script := p.script
  prevTx := p.prevTx
  txId := p.txId
  scriptAda := p.scriptAda
  feeInputAda := p.feeInputAda
  keptAda := p.keptAda
  kept := p.kept
  fee := p.fee
  now := p.now
  signer := p.signer }

def cancelToLegacy (p : TxModels.TxM008.CancelLeaves) :
    Formal.Vesting.Linear.Blueprint.CancelLeaves := {
  beneficiary := p.beneficiary
  locker := p.locker
  name := p.name
  total := p.total
  start := p.start
  finish := p.finish
  recovery := p.recovery
  script := p.script
  prevTx := p.prevTx
  txId := p.txId
  scriptAda := p.scriptAda
  feeInputAda := p.feeInputAda
  fee := p.fee
  now := p.now
  signer := p.signer }

def cancelFromLegacy (p : Formal.Vesting.Linear.Blueprint.CancelLeaves) :
    TxModels.TxM008.CancelLeaves := {
  beneficiary := p.beneficiary
  locker := p.locker
  name := p.name
  total := p.total
  start := p.start
  finish := p.finish
  recovery := p.recovery
  script := p.script
  prevTx := p.prevTx
  txId := p.txId
  scriptAda := p.scriptAda
  feeInputAda := p.feeInputAda
  fee := p.fee
  now := p.now
  signer := p.signer }

theorem claimContext (p : TxModels.TxM007.ClaimLeaves) :
    TxModels.TxM007.claim p = Formal.Vesting.Linear.Blueprint.claim (claimToLegacy p) := rfl

theorem cancelContext (p : TxModels.TxM008.CancelLeaves) :
    TxModels.TxM008.cancel p = Formal.Vesting.Linear.Blueprint.cancel (cancelToLegacy p) := rfl

theorem claimContextFromLegacy (p : Formal.Vesting.Linear.Blueprint.ClaimLeaves) :
    TxModels.TxM007.claim (claimFromLegacy p) = Formal.Vesting.Linear.Blueprint.claim p := rfl

theorem cancelContextFromLegacy (p : Formal.Vesting.Linear.Blueprint.CancelLeaves) :
    TxModels.TxM008.cancel (cancelFromLegacy p) = Formal.Vesting.Linear.Blueprint.cancel p := rfl

-- Tests.lean checks that generated support and the frozen Types embed the same bytes.
def preparedAccepts (program : Program) (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

theorem evaluatorParity (fuel : Nat) (ctx : ScriptContext) :
    preparedAccepts Formal.Vesting.Linear.Blueprint.program fuel ctx ↔
      Formal.Vesting.Linear.Blueprint.accepts fuel ctx := Iff.rfl

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      ∃ p, validScriptContext (Formal.Vesting.Linear.Blueprint.claim p) = true ∧
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.claim p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

theorem cancelStatement :
    statement validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p, validScriptContext (Formal.Vesting.Linear.Blueprint.cancel p) = true ∧
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.cancel p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem rejectingPredicateCannotPass {A : Type} (valid : ScriptContext → Bool)
    (context : A → ScriptContext) : ¬ statement valid (fun _ => False) context :=
  fun ⟨_, _, impossible⟩ => impossible

end Formal.Properties.Universal.UP000.Tests.Parity

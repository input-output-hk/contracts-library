import Formal.Universal.TxModels.Definitions.TxM007
import Formal.Universal.TxModels.Definitions.TxM008
import Formal.Universal.Standalone.LinearVesting.Tx
import Formal.Universal.Support.CandidateHelpers
import Formal.Universal.Support.Continuations

namespace Formal.Universal.Properties.Tests.ParitySupport

open CardanoLedgerApi.V3 (ScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open Formal.Universal.Support.Continuations

def claimToLegacy (p : TxModels.TxM007.ClaimLeaves) :
    Formal.Universal.Standalone.LinearVesting.ClaimLeaves := {
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

def claimFromLegacy (p : Formal.Universal.Standalone.LinearVesting.ClaimLeaves) :
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
    Formal.Universal.Standalone.LinearVesting.CancelLeaves := {
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

def cancelFromLegacy (p : Formal.Universal.Standalone.LinearVesting.CancelLeaves) :
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
    TxModels.TxM007.claim p = Formal.Universal.Standalone.LinearVesting.claim (claimToLegacy p) := rfl

theorem cancelContext (p : TxModels.TxM008.CancelLeaves) :
    TxModels.TxM008.cancel p = Formal.Universal.Standalone.LinearVesting.cancel (cancelToLegacy p) := rfl

theorem claimContextFromLegacy (p : Formal.Universal.Standalone.LinearVesting.ClaimLeaves) :
    TxModels.TxM007.claim (claimFromLegacy p) = Formal.Universal.Standalone.LinearVesting.claim p := rfl

theorem cancelContextFromLegacy (p : Formal.Universal.Standalone.LinearVesting.CancelLeaves) :
    TxModels.TxM008.cancel (cancelFromLegacy p) = Formal.Universal.Standalone.LinearVesting.cancel p := rfl

-- Property unit suites compare generated support with the frozen program bytes.
def preparedAccepts (program : Program) (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

theorem acceptanceEvaluatorParity (fuel : Nat) (ctx : ScriptContext) :
    preparedAccepts Formal.Universal.Standalone.LinearVesting.program fuel ctx ↔
      Formal.Universal.Standalone.LinearVesting.accepts fuel ctx := Iff.rfl

def preparedRejects (program : Program) (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Universal.Support.rejectedWithin program [toTerm ctx] fuel

theorem rejectionEvaluatorParity (fuel : Nat) (ctx : ScriptContext) :
    preparedRejects Formal.Universal.Standalone.LinearVesting.program fuel ctx ↔
      Formal.Universal.Standalone.LinearVesting.rejects fuel ctx := Iff.rfl

theorem withOutputsParity : withOutputs = Formal.Universal.Support.withOutputs := rfl

theorem keyAddrParity : keyAddr = Formal.Universal.Support.keyAddr := rfl

theorem ownInputParity : ownInput? = Formal.Universal.Support.ownInput? := rfl

theorem attackerKeyParity : attackerKey = Formal.Universal.Support.attackerKey := rfl

theorem redirectParity : redirectContinuations = Formal.Universal.Support.redirectContinuations := rfl

theorem isContinuationParity : isContinuation = Formal.Universal.Support.isContinuation := rfl

theorem changeFirstParity : changeFirst = Formal.Universal.Support.changeFirst := by
  funext predicate transform outputs
  induction outputs with
  | nil => rfl
  | cons output rest ih =>
      simp only [changeFirst, Formal.Universal.Support.changeFirst, ih]

theorem changeContinuationParity : changeContinuation = Formal.Universal.Support.changeContinuation := by
  funext ctx transform
  simp only [changeContinuation, Formal.Universal.Support.changeContinuation,
    withOutputsParity, isContinuationParity, changeFirstParity]

theorem firstContinuationParity : firstContinuation? = Formal.Universal.Support.firstContinuation? := rfl

end Formal.Universal.Properties.Tests.ParitySupport

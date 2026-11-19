import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.Spec

/-!
# Transaction builders for linear vesting

The transaction shapes the agreement theorems are stated over. Each shape is a
structure with a field for every part of the transaction the validator reads; every
other field of the transaction info comes from `rest` and is left arbitrary.

Assumptions such as "the beneficiary is a key" are not part of the shapes: they are
hypotheses of the theorems, so one shape serves several theorems.
-/

namespace Formal.LinearVesting.TxBuilder

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open PlutusCore.UPLC.Term (Program)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Value (CurrencySymbol TokenName)
open CardanoLedgerApi.V3
  (Address Credential POSIXTimeRange PubKeyHash ScriptContext ScriptHash TxInInfo TxInfo
    TxOut TxOutRef)
open Formal.Shared.Common (validatorAccepts)
open Formal.LinearVesting.Spec
  (VestingDatum VestingRedeemer datumData redeemerData specAccepts)

/-! ## Agreement between a validator and the spec -/

/-- Everything `validator` accepts, the spec accepts. -/
def Sound (validator : Program) (d : VestingDatum) (r : VestingRedeemer)
    (ctx : ScriptContext) : Prop :=
  validatorAccepts ctx validator → specAccepts d r ctx = true

/-- Everything the spec accepts, `validator` accepts. -/
def Complete (validator : Program) (d : VestingDatum) (r : VestingRedeemer)
    (ctx : ScriptContext) : Prop :=
  specAccepts d r ctx = true → validatorAccepts ctx validator

/-- `validator` and the spec accept exactly the same transactions. -/
def Agrees (validator : Program) (d : VestingDatum) (r : VestingRedeemer)
    (ctx : ScriptContext) : Prop :=
  Sound validator d r ctx ∧ Complete validator d r ctx

/-! ## Inputs and outputs -/

/-- The vesting UTxO being spent: at the script `sh`, with the inline datum `d`. -/
def ownInput (ref : TxOutRef) (sh : ScriptHash) (value : List (Data × Data))
    (d : VestingDatum) : TxInInfo :=
  ⟨ref, ⟨⟨.ScriptCredential sh, none⟩, value, .OutputDatum (datumData d), none⟩⟩

/-- An output at a script address with no staking credential, with any datum,
holding ada and one other asset. -/
structure ScriptOut where
  scriptHash : ScriptHash
  datum      : Data
  ada        : Integer
  policy     : CurrencySymbol
  name       : TokenName
  qty        : Integer

def ScriptOut.toTxOut (o : ScriptOut) : TxOut :=
  ⟨⟨.ScriptCredential o.scriptHash, none⟩,
   [(Data.B "", Data.Map [(Data.B "", Data.I o.ada)]),
    (Data.B o.policy, Data.Map [(Data.B o.name, Data.I o.qty)])],
   .OutputDatum o.datum, none⟩

/-- An output at any address (key or script, any staking credential), with any
datum, holding ada and one other asset. -/
structure AnyOut where
  address : Address
  datum   : Data
  ada     : Integer
  policy  : CurrencySymbol
  name    : TokenName
  qty     : Integer

def AnyOut.toTxOut (o : AnyOut) : TxOut :=
  ⟨o.address,
   [(Data.B "", Data.Map [(Data.B "", Data.I o.ada)]),
    (Data.B o.policy, Data.Map [(Data.B o.name, Data.I o.qty)])],
   .OutputDatum o.datum, none⟩

/-- A wallet input paying the fee: at a key address with no staking credential, no
datum, any value. -/
structure WalletIn where
  ref   : TxOutRef
  key   : PubKeyHash
  value : List (Data × Data)

def WalletIn.toTxInInfo (w : WalletIn) : TxInInfo :=
  ⟨w.ref, ⟨⟨.PubKeyCredential w.key, none⟩, w.value, .NoOutputDatum, none⟩⟩

/-- A payout: at a key address with no staking credential, no datum, any value. -/
structure KeyOut where
  key   : PubKeyHash
  value : List (Data × Data)

def KeyOut.toTxOut (o : KeyOut) : TxOut :=
  ⟨⟨.PubKeyCredential o.key, none⟩, o.value, .NoOutputDatum, none⟩

/-- A spend of `ownRef` with datum `d` and redeemer `r`. The listed parts replace
those of `rest`; everything else comes from `rest`. -/
def spendCtx (rest : TxInfo) (inputs : List TxInInfo) (outputs : List TxOut)
    (withdrawals : List (Credential × Integer)) (range : POSIXTimeRange)
    (signatories : List PubKeyHash) (r : VestingRedeemer) (ownRef : TxOutRef)
    (d : VestingDatum) : ScriptContext :=
  { scriptContextTxInfo :=
      { rest with
        txInfoInputs := inputs
        txInfoOutputs := outputs
        txInfoWdrl := withdrawals
        txInfoValidRange := IsData.toData range
        txInfoSignatories := signatories }
    scriptContextRedeemer := redeemerData r
    scriptContextScriptInfo := .SpendingScript ownRef (some (datumData d)) }

/-! ## Cancel -/

/-- A cancel: the vesting UTxO first among the inputs, followed by the inputs of
`rest`. The outputs come from `rest`, since cancel does not read them. -/
structure CancelTx where
  datum       : VestingDatum
  ownRef      : TxOutRef
  scriptHash  : ScriptHash
  ownValue    : List (Data × Data)
  range       : POSIXTimeRange
  signatories : List PubKeyHash
  withdrawals : List (Credential × Integer)
  rest        : TxInfo

def CancelTx.ctx (tx : CancelTx) : ScriptContext :=
  spendCtx tx.rest (ownInput tx.ownRef tx.scriptHash tx.ownValue tx.datum :: tx.rest.txInfoInputs)
    tx.rest.txInfoOutputs tx.withdrawals tx.range tx.signatories .cancel tx.ownRef tx.datum

/-! ## Claim -/

/-- A claim. The inputs are the vesting UTxO being validated, then optionally a
sibling vesting UTxO at the same script with the same datum, then optionally a wallet
input. The outputs are the continuations, each at a script address, then optionally
a payout at a key address. -/
structure ClaimTx where
  datum         : VestingDatum
  ownRef        : TxOutRef
  scriptHash    : ScriptHash
  ownValue      : List (Data × Data)
  sibling       : Option (TxOutRef × List (Data × Data))
  wallet        : Option WalletIn
  range         : POSIXTimeRange
  signatories   : List PubKeyHash
  withdrawals   : List (Credential × Integer)
  continuations : List ScriptOut
  payout        : Option KeyOut
  rest          : TxInfo

def ClaimTx.ctx (tx : ClaimTx) : ScriptContext :=
  spendCtx tx.rest
    (ownInput tx.ownRef tx.scriptHash tx.ownValue tx.datum ::
      ((tx.sibling.map fun s => ownInput s.1 tx.scriptHash s.2 tx.datum).toList ++
        (tx.wallet.map WalletIn.toTxInInfo).toList))
    (tx.continuations.map ScriptOut.toTxOut ++ (tx.payout.map KeyOut.toTxOut).toList)
    tx.withdrawals tx.range tx.signatories .claim tx.ownRef tx.datum

/-- A claim with the vesting UTxO as the only input and exactly one output, at any
address. -/
structure ClaimAnyOutTx where
  datum       : VestingDatum
  ownRef      : TxOutRef
  scriptHash  : ScriptHash
  ownValue    : List (Data × Data)
  range       : POSIXTimeRange
  signatories : List PubKeyHash
  withdrawals : List (Credential × Integer)
  output      : AnyOut
  rest        : TxInfo

def ClaimAnyOutTx.ctx (tx : ClaimAnyOutTx) : ScriptContext :=
  spendCtx tx.rest [ownInput tx.ownRef tx.scriptHash tx.ownValue tx.datum]
    [tx.output.toTxOut] tx.withdrawals tx.range tx.signatories .claim tx.ownRef tx.datum

end Formal.LinearVesting.TxBuilder

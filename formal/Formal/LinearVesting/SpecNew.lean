import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3

namespace Formal.LinearVesting.SpecNew

open PlutusCore.Data
open CardanoLedgerApi.IsData.Class
open CardanoLedgerApi.V1.Credential
open CardanoLedgerApi.V1.Value
open CardanoLedgerApi.V1.Time
open CardanoLedgerApi.V3
open CardanoLedgerApi.V3.Contexts

def vested (T start finish now : Int) : Int :=
  if now ≤ start then 0
  else if finish ≤ now then T
  else T * (now - start) / (finish - start)

def required (T start finish now : Int) : Int :=
  T - vested T start finish now

theorem vested_preStart (T start finish now : Int) (h : now ≤ start) :
    vested T start finish now = 0 := by
  unfold vested
  blaster

theorem vested_full (T start finish now : Int)
    (hs : start < finish) (h : finish ≤ now) :
    vested T start finish now = T := by
  unfold vested
  blaster

theorem vested_le_total (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    vested T start finish now ≤ T := by
  unfold vested
  blaster

theorem required_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ required T start finish now := by
  unfold required vested
  blaster

theorem vested_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ vested T start finish now := by
  unfold vested
  blaster

theorem vested_mono (T start finish n₁ n₂ : Int)
    (hT : 0 ≤ T) (hs : start < finish) (h : n₁ ≤ n₂) :
    vested T start finish n₁ ≤ vested T start finish n₂ := by
  unfold vested
  blaster

structure VestedAsset where
  policy : CurrencySymbol
  name   : TokenName
  total  : Int

def assetData (a : VestedAsset) : Data :=
  Data.Constr 0 [IsData.toData a.policy, IsData.toData a.name, Data.I a.total]

structure VestingDatum where
  beneficiary  : Credential
  locker       : Credential
  vesting      : List VestedAsset
  startTime    : POSIXTime
  endTime      : POSIXTime
  recoveryTime : POSIXTime

def datumData (d : VestingDatum) : Data :=
  Data.Constr 0
    [ IsData.toData d.beneficiary,
      IsData.toData d.locker,
      Data.List (d.vesting.map assetData),
      Data.I d.startTime,
      Data.I d.endTime,
      Data.I d.recoveryTime ]

inductive VestingRedeemer where
  | claim
  | cancel

def redeemerData : VestingRedeemer → Data
  | .claim  => Data.Constr 0 []
  | .cancel => Data.Constr 1 []

def validityLowerBound (range : Data) : Option LowerBound :=
  match (IsData.fromData range : Option POSIXTimeRange) with
  | some r => some r.ivFrom
  | none => none

def authorized (c : Credential) (info : TxInfo) : Bool :=
  match c with
  | .PubKeyCredential h => txSignedBy h info
  | .ScriptCredential _ => credentialInWithdrawals c info.txInfoWdrl

def claimOk (d : VestingDatum) (own : TxOut) (info : TxInfo) (now : POSIXTime) : Bool :=
  let ownCred := own.txOutAddress.addressCredential
  let inline : OutputDatum := .OutputDatum (datumData d)
  let atScriptWithDatum (o : TxOut) : Bool :=
    o.txOutAddress.addressCredential == ownCred && o.txOutDatum == inline
  let k := (info.txInfoInputs.filter (fun i => atScriptWithDatum i.txInInfoResolved)).length
  let conts := info.txInfoOutputs.filter atScriptWithDatum
  let holdsRequired (o : TxOut) : Bool :=
    d.vesting.all (fun a =>
      valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime now)
  d.startTime < d.endTime &&
  authorized d.beneficiary info &&
  own.txOutDatum == inline &&
  (now ≥ d.endTime || (k ≤ conts.length && conts.all holdsRequired))

def cancelOk (d : VestingDatum) (info : TxInfo) (low : LowerBound) : Bool :=
  let afterRecovery : Bool :=
    match low with
    | .FiniteLowerBound t true  => d.recoveryTime < t
    | .FiniteLowerBound t false => d.recoveryTime ≤ t
    | .InfiniteLowerBound .NegInf => false
    | .InfiniteLowerBound .PosInf => true
  d.startTime < d.endTime && d.endTime < d.recoveryTime &&
  authorized d.locker info &&
  afterRecovery

def specAccepts (d : VestingDatum) (r : VestingRedeemer) (ctx : ScriptContext) : Bool :=
  let info := ctx.scriptContextTxInfo
  match ctx.scriptContextScriptInfo, validityLowerBound info.txInfoValidRange with
  | .SpendingScript ref _, some low =>
      match r with
      | .claim =>
          match low, resolveInput ref info.txInfoInputs with
          | .FiniteLowerBound now _, some own => claimOk d own.txInInfoResolved info now
          | _, _ => false
      | .cancel => cancelOk d info low
  | _, _ => false

def TxSane (d : VestingDatum) (r : VestingRedeemer) (ctx : ScriptContext) : Prop :=
  validScriptContext ctx = true ∧
  ctx.scriptContextRedeemer = redeemerData r ∧
  ∃ ref, ctx.scriptContextScriptInfo = .SpendingScript ref (some (datumData d))

end Formal.LinearVesting.SpecNew

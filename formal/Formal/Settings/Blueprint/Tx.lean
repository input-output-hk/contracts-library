-- Fixed Settings Mint model. See README.md for scope and validation status.
import Formal.Settings.Blueprint.Types

namespace Formal.Settings.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3
open Formal.Universal.TxBuilder

-- ByteString stores one character per byte. These are bytes, not ASCII hex text.
def ownPolicy : ByteString :=
  ⟨String.mk (([0x50, 0xdc, 0x52, 0xe6, 0xbf, 0x8d, 0xb4, 0x17,
    0xd8, 0xe5, 0xb7, 0x0b, 0xbd, 0x2c, 0x1c, 0xaa,
    0x6a, 0x45, 0xa5, 0xca, 0x78, 0x54, 0xa5, 0x1d,
    0x99, 0xb6, 0x3e, 0x60] : List Nat).map Char.ofNat)⟩

def seedTxId : ByteString :=
  ⟨String.mk (List.replicate 32 (Char.ofNat 0x11))⟩

def applyKey : ByteString :=
  ⟨String.mk (List.replicate 28 (Char.ofNat 0x33))⟩

def transactionId : ByteString :=
  ⟨String.mk (List.replicate 32 (Char.ofNat 0x44))⟩

def tokenName : ByteString :=
  ⟨String.mk (([0x55, 0x50, 0x30, 0x31, 0x36] : List Nat).map Char.ofNat)⟩

structure MintLeaves where
  ada0 : Int
  ada1 : Int
  fee : Int
  validFrom : Int
  current : Int

def settingsDatum (current : Int) : Data :=
  IsData.toData
    ({ current := .I current, next := none, next_apply := none }
      : Settings.Types.SettingsDatum)

def mintRedeemer : Data := IsData.toData (Settings.Types.MintRedeemer.Mint 0)

def protectedOutput (p : MintLeaves) : TxOut :=
  toScript ownPolicy (adaAnd p.ada0 ownPolicy tokenName 1) (settingsDatum p.current)

def changeOutput (p : MintLeaves) : TxOut :=
  toKey applyKey (ada p.ada1)

/-- One ADA-only key input, the protected NFT output, and a funded change output. -/
def original (p : MintLeaves) : ScriptContext :=
  let seed := input seedTxId 0 (toKey applyKey (ada (p.ada0 + p.ada1 + p.fee)))
  { scriptContextTxInfo :=
      { txInfoInputs := [seed]
        txInfoReferenceInputs := []
        txInfoOutputs := [protectedOutput p, changeOutput p]
        txInfoFee := p.fee
        txInfoMint := [(.B ownPolicy, .Map [(.B tokenName, .I 1)])]
        txInfoTxCerts := []
        txInfoWdrl := []
        txInfoValidRange := IsData.toData (CardanoLedgerApi.V1.Time.after p.validFrom)
        txInfoSignatories := [applyKey]
        txInfoRedeemers := [(.Minting ownPolicy, mintRedeemer)]
        txInfoData := []
        txInfoId := transactionId
        txInfoVotes := []
        txInfoProposalProcedures := []
        txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
        txInfoTreasuryDonation := IsData.toData (none : Option Int) }
    scriptContextRedeemer := mintRedeemer
    scriptContextScriptInfo := .MintingScript ownPolicy }

/-- Shape-specific paired update. The proposed property explicitly requires delta > 0.
The total definition also permits diagnostic controls outside that property domain.
-/
def changed (p : MintLeaves) (delta : Int) : ScriptContext :=
  let h := original p
  let recipient := changeOutput p
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with
      txInfoMint := CardanoLedgerApi.V1.Value.add ownPolicy tokenName delta
        h.scriptContextTxInfo.txInfoMint
      txInfoOutputs :=
        [protectedOutput p,
         { recipient with txOutValue :=
             CardanoLedgerApi.V1.Value.add ownPolicy tokenName delta recipient.txOutValue }] } }

end Formal.Settings.Blueprint

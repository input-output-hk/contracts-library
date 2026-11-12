import Formal.Vault.Blueprint.Types
import PlutusCore.Cbor.Basic
import Cryptograph.Blake2b

namespace Formal.Vault.Blueprint.Tx

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3
open Formal.Support.TxBuilder (ada toKey)

/-- Blake2b-256 on the CBOR byte string, without UTF-8 re-encoding. -/
def hashDatumBytes (bytes : String) : ByteString :=
  ⟨String.mk ((Cryptograph.Blake2b.blake2b_256
    (bytes.data.map Char.toUInt8)).map Char.ofUInt8)⟩

/-- One concrete 28-byte owner key hash. -/
def owner : ByteString := "0000000000000000000000000000"

def actualDatum : Data := .Constr 0 [.B owner]

/-- CBOR for constructor zero with the 28-byte owner as its only field. -/
def datumBytes : String := "\xd8\x79\x9f\x58\x1c" ++ owner.data ++ "\xff"

def datumHash : ByteString := hashDatumBytes datumBytes

def ownRef : TxOutRef := ⟨"11111111111111111111111111111111", 0⟩

def redeemer : Data := .Constr 0 []

/-- The script input stores the datum hash, with no inline datum. -/
def ownInput : TxInInfo :=
  ⟨ownRef,
    ⟨⟨.ScriptCredential scriptHash, none⟩, ada 2000000,
      .OutputDatumHash datumHash, none⟩⟩

/-- A fixed owner-authorized spend: 2 ADA in, 1.8 ADA out, and a 0.2 ADA fee. -/
def hashed : ScriptContext :=
  { scriptContextTxInfo :=
      { txInfoInputs := [ownInput]
        txInfoReferenceInputs := []
        txInfoOutputs := [toKey owner (ada 1800000)]
        txInfoFee := 200000
        txInfoMint := []
        txInfoTxCerts := []
        txInfoWdrl := []
        txInfoValidRange := IsData.toData (CardanoLedgerApi.V1.Time.after 0)
        txInfoSignatories := [owner]
        txInfoRedeemers := [(.Spending ownRef, redeemer)]
        txInfoData := [(datumHash, actualDatum)]
        txInfoId := "22222222222222222222222222222222"
        txInfoVotes := []
        txInfoProposalProcedures := []
        txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
        txInfoTreasuryDonation := IsData.toData (none : Option Int) }
    scriptContextRedeemer := redeemer
    scriptContextScriptInfo := .SpendingScript ownRef (some actualDatum) }

/-- Keep the supplied datum but remove its witness-map entry. -/
def missingMap : ScriptContext :=
  { hashed with scriptContextTxInfo := { hashed.scriptContextTxInfo with txInfoData := [] } }

/-- Keep the hash and supplied datum but replace the witness-map value. -/
def wrongMapValue : ScriptContext :=
  { hashed with scriptContextTxInfo :=
      { hashed.scriptContextTxInfo with txInfoData := [(datumHash, .I 0)] } }

/-- Keep the hashed input and matching datum witness but remove the owner signature. -/
def missingSignature : ScriptContext :=
  { hashed with scriptContextTxInfo :=
      { hashed.scriptContextTxInfo with txInfoSignatories := [] } }

/-- The same owner-authorized spend with an inline datum and no datum-map entry. -/
def inline : ScriptContext :=
  { hashed with scriptContextTxInfo :=
      { hashed.scriptContextTxInfo with
        txInfoInputs := [{ ownInput with txInInfoResolved :=
          { ownInput.txInInfoResolved with txOutDatum := .OutputDatum actualDatum } }]
        txInfoData := [] } }

end Formal.Vault.Blueprint.Tx

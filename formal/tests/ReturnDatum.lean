import Formal.Universal.ReturnDatum

namespace ReturnDatumTests
open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (TxOut OutputDatum)
open Formal.Universal.ReturnDatum

-- Structural predicate tests; these outputs are not complete transactions.
def output (script : ByteString) (datum : OutputDatum) : TxOut :=
  ⟨⟨.ScriptCredential script, none⟩, [], datum, none⟩

def isInteger (datum : Data) : Bool := (IsData.fromData datum : Option Int).isSome
def good : TxOut := output "self" (.OutputDatum (.I 1))

example : allReturnDatumsValid "self" isInteger [] = true := rfl
example : allReturnDatumsValid "self" isInteger [good, good] = true := rfl
example : allReturnDatumsValid "self" isInteger [output "other" .NoOutputDatum] = true := rfl
example : allReturnDatumsValid "self" isInteger [output "self" .NoOutputDatum] = false := rfl
example : allReturnDatumsValid "self" isInteger [output "self" (.OutputDatumHash "datum")] = false := rfl
example : allReturnDatumsValid "self" isInteger [output "self" (.OutputDatum (.B "wrong"))] = false := rfl
example : allReturnDatumsValid "self" isInteger
    [good, output "other" .NoOutputDatum, output "self" .NoOutputDatum] = false := rfl
example : allReturnDatumsValid "self" isInteger
    [output "self" .NoOutputDatum, good] = false := rfl
example : allReturnDatumsValid "self" isInteger
    [{ good with txOutAddress := ⟨.PubKeyCredential "self", none⟩, txOutDatum := .NoOutputDatum }] = true := rfl
example : allReturnDatumsValid "self" isInteger
    [good,
     { good with
       txOutAddress := ⟨.ScriptCredential "self", some (.StakingHash (.PubKeyCredential "stake"))⟩
       txOutDatum := .NoOutputDatum }] = false := rfl

end ReturnDatumTests

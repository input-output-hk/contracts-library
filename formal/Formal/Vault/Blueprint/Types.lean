import PlutusCore.UPLC
import CardanoLedgerApi
import Formal.Support.Compatibility

namespace Formal.Vault.Blueprint

open PlutusCore.UPLC.Term (Term Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)

/-- The frozen owner-checking vault in Formal/Properties/Universal/UP009/Tests/Standalone/Inputs/plutus.json. -/
def program : Program := singleCborEncodedScriptFromHexM "58bc01010029800aba2aba1aab9faab9eaab9dab9a48888896600264646644b30013370e900118031baa00189919912cc004cdc3a400060126ea800626466446600400400244b30010018a508acc004cdc79bae300f0010038a518998010011808000a01640386eb0c034c038c038c038c038c038c038c038c038c02cdd518068041bae300c300a3754601860146ea80062c8040c028004c028c02c004c01cdd5000c59005180380098039804000980380098019baa0078a4d1365640041"

/-- Recomputed with Aiken from the frozen V3 compiled bytes. -/
def scriptHash : ByteString := "\x7e\xe3\x3b\x92\x68\x34\xbd\x7d\x98\x3c\xa9\xd4\x33\xce\xe0\xcc\x19\x18\xed\x5b\xcb\x5f\x78\xab\x79\x5d\x70\x57"

/-- The unparameterized V3 program receives one encoded script context. -/
def args (ctx : ScriptContext) : List Term := [toTerm ctx]

/-- Unit halt within the supplied CEK step bound. -/
def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)

/-- A bounded error or non-unit halt; exhaustion is not rejection. -/
def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Support.rejectedWithin program (args ctx) fuel

end Formal.Vault.Blueprint

import Formal.Support.Continuations

namespace Formal.Properties.Universal.UP014

open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Credential ScriptContext)
open Formal.Support.Continuations

/-- Replacing the first continuation's datum with the original empty-list constructor
    requires rejection under these five guards. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p (c1 c2 : Credential) (start finish recovery : Int),
    valid (context p) = true →
    accepts (context p) →
    rejects (redirectContinuations (context p)) →
    (firstContinuation? (context p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
      [IsData.toData c1, IsData.toData c2, Data.List [], Data.I start, Data.I finish,
        Data.I recovery])) = false →
    valid (changeContinuation (context p) (fun o =>
      { o with txOutDatum := .OutputDatum (Data.Constr 0
        [IsData.toData c1, IsData.toData c2, Data.List [], Data.I start, Data.I finish,
          Data.I recovery]) })) = true →
    rejects (changeContinuation (context p) (fun o =>
      { o with txOutDatum := .OutputDatum (Data.Constr 0
        [IsData.toData c1, IsData.toData c2, Data.List [], Data.I start, Data.I finish,
          Data.I recovery]) }))

/-- A context and replacement fields satisfying all five guards witness applicability. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, ∃ (c1 c2 : Credential), ∃ (start finish recovery : Int),
    valid (context p) = true ∧
    accepts (context p) ∧
    rejects (redirectContinuations (context p)) ∧
    (firstContinuation? (context p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
      [IsData.toData c1, IsData.toData c2, Data.List [], Data.I start, Data.I finish,
        Data.I recovery])) = false ∧
    valid (changeContinuation (context p) (fun o =>
      { o with txOutDatum := .OutputDatum (Data.Constr 0
        [IsData.toData c1, IsData.toData c2, Data.List [], Data.I start, Data.I finish,
          Data.I recovery]) })) = true

end Formal.Properties.Universal.UP014

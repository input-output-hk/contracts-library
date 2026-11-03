import Blaster
import Formal.Universal.Properties
import tests.UP005.Fixture

set_option Elab.async false

namespace Tests.UP005

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open Formal.Universal.Properties
open Fixture (accepts)

/-!
The eight unparameterized statements emitted by PR #50's malformedRedeemer
helper for this fixture. EverySpend keeps the entire TxInfo, spending reference,
and optional raw datum open. ledgerFuel is 1,000,000 CEK steps. Exhaustion
satisfies nonacceptance; no ledger-validity premise or explicit error is required.
-/

#eval Fixture.checkSource

theorem malformedRedeemer_spend_wrongForm_int :
    ∀ (n : Int) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.I n)) := by blaster

theorem malformedRedeemer_spend_wrongForm_bytes :
    ∀ (b : ByteString) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.B b)) := by blaster

theorem malformedRedeemer_spend_wrongForm_list :
    ∀ (l : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.List l)) := by blaster

theorem malformedRedeemer_spend_wrongForm_map :
    ∀ (m : List (Data × Data)) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Map m)) := by blaster

theorem malformedRedeemer_spend_unknownIndex2 :
    ∀ (fs : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 2 fs)) := by blaster

theorem malformedRedeemer_spend_unknownIndex3 :
    ∀ (fs : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 3 fs)) := by blaster

theorem malformedRedeemer_spend_Claim_extraField :
    ∀ (x1 : Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 0 [x1])) := by blaster

theorem malformedRedeemer_spend_Cancel_extraField :
    ∀ (x1 : Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 1 [x1])) := by blaster

#print axioms malformedRedeemer_spend_wrongForm_int
#print axioms malformedRedeemer_spend_wrongForm_bytes
#print axioms malformedRedeemer_spend_wrongForm_list
#print axioms malformedRedeemer_spend_wrongForm_map
#print axioms malformedRedeemer_spend_unknownIndex2
#print axioms malformedRedeemer_spend_unknownIndex3
#print axioms malformedRedeemer_spend_Claim_extraField
#print axioms malformedRedeemer_spend_Cancel_extraField

end Tests.UP005

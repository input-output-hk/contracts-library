import Blaster
import Formal.Universal.Properties
import tests.UP001.Fixture

set_option Elab.async false

namespace Tests.UP001

open PlutusCore.Data (Data)
open Formal.Universal.Properties
open Fixture (accepts)

/-!
The five unparameterized statements emitted by PR #49's otherPurpose generator.
All raw redeemers, transaction information, and purpose fields remain open.
The shared ledgerFuel is 1,000,000 CEK steps. Exhaustion satisfies nonacceptance;
these claims do not require explicit rejection or impose ledger validity.
-/

#eval Fixture.checkSource

theorem otherPurpose_mint :
    ∀ (r : Data) (t : EveryMint),
      ¬ accepts ledgerFuel (EveryMint.ctx t r) := by blaster

theorem otherPurpose_withdraw :
    ∀ (r : Data) (t : EveryWithdraw),
      ¬ accepts ledgerFuel (EveryWithdraw.ctx t r) := by blaster

theorem otherPurpose_publish :
    ∀ (r : Data) (t : EveryPublish),
      ¬ accepts ledgerFuel (EveryPublish.ctx t r) := by blaster

theorem otherPurpose_vote :
    ∀ (r : Data) (t : EveryVote),
      ¬ accepts ledgerFuel (EveryVote.ctx t r) := by blaster

theorem otherPurpose_propose :
    ∀ (r : Data) (t : EveryPropose),
      ¬ accepts ledgerFuel (EveryPropose.ctx t r) := by blaster

#print axioms otherPurpose_mint
#print axioms otherPurpose_withdraw
#print axioms otherPurpose_publish
#print axioms otherPurpose_vote
#print axioms otherPurpose_propose

end Tests.UP001

import Blaster
import CardanoLedgerApi.V3
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.TxBuilder

/-!
# Cancel: soundness

Everything the compiled validator accepts as a cancel, the spec accepts: the
`Sound` half of agreement for `CancelTx`. An adapted validator that only adds
restrictions to cancel needs to re-prove this file alone.

The bounds: fewer than 3 signatories for a key locker, fewer than 3 withdrawals for a
script locker. Everything else is arbitrary.
-/

namespace Formal.LinearVesting.CancelSound

open Formal.LinearVesting.Script (spendValidator)
open Formal.LinearVesting.TxBuilder


theorem cancel_sound
    (tx : CancelTx)
    (hSig : ∀ lk, tx.datum.locker = .PubKeyCredential lk → tx.signatories.length < 3)
    (hWdrl : ∀ ls, tx.datum.locker = .ScriptCredential ls → tx.withdrawals.length < 3) :
    Sound spendValidator tx.datum .cancel tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, ⟨low, up⟩, sigs, wdrl,
      rest⟩
  unfold Sound
  rcases locker with lk | ls
  · have h : sigs.length < 3 := hSig lk rfl
    clear hSig hWdrl
    rcases bene with _ | _ <;>
    rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
    repeat' (first
      | (simp only [List.length_cons, List.length_nil] at h; exfalso; omega)
      | (rcases sigs with _ | ⟨_, sigs⟩))
    all_goals (clear h; blaster)
  · have h : wdrl.length < 3 := hWdrl ls rfl
    clear hSig hWdrl
    rcases bene with _ | _ <;>
    rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
    rcases up with ⟨_, _ | _⟩ | (_ | _) <;>
    repeat' (first
      | (simp only [List.length_cons, List.length_nil] at h; exfalso; omega)
      | (rcases wdrl with _ | ⟨⟨_ | _, _⟩, wdrl⟩))
    all_goals (clear h; blaster)

end Formal.LinearVesting.CancelSound

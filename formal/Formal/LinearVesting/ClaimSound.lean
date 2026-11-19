import Blaster
import CardanoLedgerApi.V3
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.TxBuilder

/-!
# Claim: soundness

Everything the compiled validator accepts as a claim, the spec accepts: the `Sound`
half of agreement, for each claim shape. An adapted validator that only adds
restrictions to claim needs to re-prove this file alone.

Each theorem fixes which optional parts of `ClaimTx` are present (sibling, wallet,
payout), so it can be run and timed on its own.

The limits follow one rule: up to one more continuation than there are vesting
inputs, at most 2 signatories, at most 1 withdrawal where a script beneficiary reads
them, and any validity range. Every theorem assumes a single vested asset.
-/

namespace Formal.LinearVesting.ClaimSound

open PlutusCore.Data (Data)
open Formal.LinearVesting.Script (spendValidator)
open Formal.LinearVesting.TxBuilder
open CardanoLedgerApi.V3 (PubKeyHash ScriptHash TxOutRef)
open Formal.LinearVesting.Spec (VestedAsset)

/-- `claim_sound` for a key beneficiary, the vesting UTxO as the only input, at most 2
continuations and no payout. -/
theorem claim_sound
    (tx : ClaimTx) (bh : PubKeyHash) (asset : VestedAsset)
    (hB : tx.datum.beneficiary = .PubKeyCredential bh)
    (hV : tx.datum.vesting = [asset])
    (hS : tx.sibling = none) (hW : tx.wallet = none) (hP : tx.payout = none)
    (hSig : tx.signatories.length < 3)
    (hOut : tx.continuations.length < 3) :
    Sound spendValidator tx.datum .claim tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, sib, wal,
      ⟨low, up⟩, sigs, wdrl, outs, pay, rest⟩
  simp only at hB hV hS hW hP
  subst hB hV hS hW hP
  unfold Sound
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hSig hOut; exfalso; omega)
    | (rcases sigs with _ | ⟨_, sigs⟩)
    | (rcases outs with _ | ⟨_, outs⟩))
  all_goals (clear hSig hOut; blaster)

/-- `claim_sound` for a script beneficiary, authorized by a withdrawal, with the vesting
UTxO as the only input, at most 2 continuations and no payout. The signatories are not
read on this path, so they are left arbitrary. -/
theorem claim_sound_script
    (tx : ClaimTx) (bs : ScriptHash) (asset : VestedAsset)
    (hB : tx.datum.beneficiary = .ScriptCredential bs)
    (hV : tx.datum.vesting = [asset])
    (hS : tx.sibling = none) (hW : tx.wallet = none) (hP : tx.payout = none)
    (hWd : tx.withdrawals.length < 2)
    (hOut : tx.continuations.length < 3) :
    Sound spendValidator tx.datum .claim tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, sib, wal,
      ⟨low, up⟩, sigs, wdrl, outs, pay, rest⟩
  simp only at hB hV hS hW hP
  subst hB hV hS hW hP
  unfold Sound
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hWd hOut; exfalso; omega)
    | (rcases wdrl with _ | ⟨⟨_ | _, _⟩, wdrl⟩)
    | (rcases outs with _ | ⟨_, outs⟩))
  all_goals (clear hWd hOut; blaster)

/-- `claim_sound` for a batched claim: the vesting UTxO and a sibling sharing its datum,
at most 3 continuations, no wallet input and no payout. -/
theorem claim_sound_batch
    (tx : ClaimTx) (bh : PubKeyHash) (asset : VestedAsset)
    (s : TxOutRef × List (Data × Data))
    (hB : tx.datum.beneficiary = .PubKeyCredential bh)
    (hV : tx.datum.vesting = [asset])
    (hS : tx.sibling = some s) (hW : tx.wallet = none) (hP : tx.payout = none)
    (hSig : tx.signatories.length < 3)
    (hOut : tx.continuations.length < 4) :
    Sound spendValidator tx.datum .claim tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, sib, wal,
      ⟨low, up⟩, sigs, wdrl, outs, pay, rest⟩
  simp only at hB hV hS hW hP
  subst hB hV hS hW hP
  rcases s with ⟨sref, sval⟩
  unfold Sound
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hSig hOut; exfalso; omega)
    | (rcases sigs with _ | ⟨_, sigs⟩)
    | (rcases outs with _ | ⟨_, outs⟩))
  all_goals (clear hSig hOut; blaster)

/-- `claim_sound` for the typical claim: the vesting UTxO and a wallet input paying the
fee, at most 2 continuations, and a payout to a key address. With no continuation
this is the usual claim after the end of vesting; with one, the usual partial claim. -/
theorem claim_sound_typical
    (tx : ClaimTx) (bh : PubKeyHash) (asset : VestedAsset) (w : WalletIn) (p : KeyOut)
    (hB : tx.datum.beneficiary = .PubKeyCredential bh)
    (hV : tx.datum.vesting = [asset])
    (hS : tx.sibling = none) (hW : tx.wallet = some w) (hP : tx.payout = some p)
    (hSig : tx.signatories.length < 3)
    (hOut : tx.continuations.length < 3) :
    Sound spendValidator tx.datum .claim tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, sib, wal,
      ⟨low, up⟩, sigs, wdrl, outs, pay, rest⟩
  simp only at hB hV hS hW hP
  subst hB hV hS hW hP
  rcases w with ⟨wref, wkey, wval⟩
  rcases p with ⟨pkey, pval⟩
  unfold Sound
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hSig hOut; exfalso; omega)
    | (rcases sigs with _ | ⟨_, sigs⟩)
    | (rcases outs with _ | ⟨_, outs⟩))
  all_goals (clear hSig hOut; blaster)

/-- `claim_sound` for a claim with exactly one output, at any address. The validator
compares only the output's payment credential, so the staking credential is left
arbitrary. -/
theorem claim_sound_any_out
    (tx : ClaimAnyOutTx) (bh : PubKeyHash) (asset : VestedAsset)
    (hB : tx.datum.beneficiary = .PubKeyCredential bh)
    (hV : tx.datum.vesting = [asset])
    (hSig : tx.signatories.length < 3) :
    Sound spendValidator tx.datum .claim tx.ctx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, ⟨low, up⟩,
      sigs, wdrl, ⟨⟨outCred, outStake⟩, outDatum, ada, pol, nm, qty⟩, rest⟩
  simp only at hB hV
  subst hB hV
  unfold Sound
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  rcases outCred with _ | _ <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hSig; exfalso; omega)
    | (rcases sigs with _ | ⟨_, sigs⟩))
  all_goals (clear hSig; blaster)

end Formal.LinearVesting.ClaimSound

import Blaster
import tests.UP007.Control

set_option Elab.async false

open Formal.Vesting.Linear.Blueprint
open Formal.Tests.UP007

-- Expected Falsified: the original Claim model admits a stake mutation.
theorem originalClaim_rejection : continuationStake_claim := by blaster

-- Expected Valid: the Claim mutation is applicable.
theorem originalClaim_applicability : continuationStake_claim_applies := by blaster

-- Expected Valid, paired with failed applicability below: no applicable Cancel coverage.
theorem originalCancel_rejection : continuationStake_cancel := by blaster

-- Expected Falsified: Cancel has no continuation in the fixed model.
theorem originalCancel_applicability : continuationStake_cancel_applies := by blaster

-- Expected Valid: the synthetic control rejects every guarded Claim stake mutation.
theorem enforcingClaim_rejection : controlClaim := by blaster

-- Expected Valid: the synthetic control accepts a baseline and rejects redirection.
theorem enforcingClaim_applicability : controlClaimApplies := by blaster

import Formal.Properties.Universal.UP001.Definition

namespace Workflow.Tests.UP001.DefinitionEquivalence

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.Universal.Properties

variable (accepts : Nat → ScriptContext → Prop)

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EveryMint.ctx) ↔
    (∀ (r : Data) (t : EveryMint), ¬ accepts 5000000 (EveryMint.ctx t r)) := Iff.rfl

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EveryWithdraw.ctx) ↔
    (∀ (r : Data) (t : EveryWithdraw), ¬ accepts 5000000 (EveryWithdraw.ctx t r)) := Iff.rfl

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EveryPublish.ctx) ↔
    (∀ (r : Data) (t : EveryPublish), ¬ accepts 5000000 (EveryPublish.ctx t r)) := Iff.rfl

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EveryVote.ctx) ↔
    (∀ (r : Data) (t : EveryVote), ¬ accepts 5000000 (EveryVote.ctx t r)) := Iff.rfl

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EveryPropose.ctx) ↔
    (∀ (r : Data) (t : EveryPropose), ¬ accepts 5000000 (EveryPropose.ctx t r)) := Iff.rfl

example : (Formal.Properties.Universal.UP001.statement (accepts 5000000) EverySpend.ctx) ↔
    (∀ (r : Data) (t : EverySpend), ¬ accepts 5000000 (EverySpend.ctx t r)) := Iff.rfl

end Workflow.Tests.UP001.DefinitionEquivalence

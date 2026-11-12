import Formal.Support.Execution
import Formal.TxModels.Definitions.TxM001
import Formal.TxModels.Definitions.TxM002
import Formal.TxModels.Definitions.TxM003
import Formal.TxModels.Definitions.TxM004
import Formal.TxModels.Definitions.TxM005
import Formal.TxModels.Definitions.TxM006

/-! Compatibility aliases for existing purpose models and transaction builders. -/

namespace Formal.Support

/-- Compatibility names for the models now owned by Formal.TxModels. -/
abbrev mkCtx := Formal.TxModels.mkCtx

abbrev EverySpend := Formal.TxModels.EverySpend
abbrev EverySpend.ctx := Formal.TxModels.EverySpend.ctx

abbrev EveryMint := Formal.TxModels.EveryMint
abbrev EveryMint.ctx := Formal.TxModels.EveryMint.ctx

abbrev EveryWithdraw := Formal.TxModels.EveryWithdraw
abbrev EveryWithdraw.ctx := Formal.TxModels.EveryWithdraw.ctx

abbrev EveryPublish := Formal.TxModels.EveryPublish
abbrev EveryPublish.ctx := Formal.TxModels.EveryPublish.ctx

abbrev EveryVote := Formal.TxModels.EveryVote
abbrev EveryVote.ctx := Formal.TxModels.EveryVote.ctx

abbrev EveryPropose := Formal.TxModels.EveryPropose
abbrev EveryPropose.ctx := Formal.TxModels.EveryPropose.ctx


end Formal.Support

namespace Formal.Support.TxBuilder

abbrev ada := Formal.TxModels.TxBuilder.ada
abbrev adaAnd := Formal.TxModels.TxBuilder.adaAnd
abbrev keyAddress := Formal.TxModels.TxBuilder.keyAddress
abbrev scriptAddress := Formal.TxModels.TxBuilder.scriptAddress
abbrev toKey := Formal.TxModels.TxBuilder.toKey
abbrev toScript := Formal.TxModels.TxBuilder.toScript
abbrev input := Formal.TxModels.TxBuilder.input
abbrev Spend := Formal.TxModels.TxBuilder.Spend
abbrev Spend.context := Formal.TxModels.TxBuilder.Spend.context

end Formal.Support.TxBuilder

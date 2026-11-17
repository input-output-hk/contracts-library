import Formal.Universal.Support.Execution
import Formal.Universal.TxModels.Definitions.TxM001
import Formal.Universal.TxModels.Definitions.TxM002
import Formal.Universal.TxModels.Definitions.TxM003
import Formal.Universal.TxModels.Definitions.TxM004
import Formal.Universal.TxModels.Definitions.TxM005
import Formal.Universal.TxModels.Definitions.TxM006

/-! Compatibility aliases for existing purpose models and transaction builders. -/

namespace Formal.Universal.Support

/-- Compatibility names for the models now owned by Formal.Universal.TxModels. -/
abbrev mkCtx := Formal.Universal.TxModels.mkCtx

abbrev EverySpend := Formal.Universal.TxModels.EverySpend
abbrev EverySpend.ctx := Formal.Universal.TxModels.EverySpend.ctx

abbrev EveryMint := Formal.Universal.TxModels.EveryMint
abbrev EveryMint.ctx := Formal.Universal.TxModels.EveryMint.ctx

abbrev EveryWithdraw := Formal.Universal.TxModels.EveryWithdraw
abbrev EveryWithdraw.ctx := Formal.Universal.TxModels.EveryWithdraw.ctx

abbrev EveryPublish := Formal.Universal.TxModels.EveryPublish
abbrev EveryPublish.ctx := Formal.Universal.TxModels.EveryPublish.ctx

abbrev EveryVote := Formal.Universal.TxModels.EveryVote
abbrev EveryVote.ctx := Formal.Universal.TxModels.EveryVote.ctx

abbrev EveryPropose := Formal.Universal.TxModels.EveryPropose
abbrev EveryPropose.ctx := Formal.Universal.TxModels.EveryPropose.ctx


end Formal.Universal.Support

namespace Formal.Universal.Support.TxBuilder

abbrev ada := Formal.Universal.TxModels.TxBuilder.ada
abbrev adaAnd := Formal.Universal.TxModels.TxBuilder.adaAnd
abbrev keyAddress := Formal.Universal.TxModels.TxBuilder.keyAddress
abbrev scriptAddress := Formal.Universal.TxModels.TxBuilder.scriptAddress
abbrev toKey := Formal.Universal.TxModels.TxBuilder.toKey
abbrev toScript := Formal.Universal.TxModels.TxBuilder.toScript
abbrev input := Formal.Universal.TxModels.TxBuilder.input
abbrev Spend := Formal.Universal.TxModels.TxBuilder.Spend
abbrev Spend.context := Formal.Universal.TxModels.TxBuilder.Spend.context

end Formal.Universal.Support.TxBuilder

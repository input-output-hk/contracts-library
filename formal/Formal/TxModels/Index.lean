import Formal.TxModels.Definitions.TxM001
import Formal.TxModels.Definitions.TxM002
import Formal.TxModels.Definitions.TxM003
import Formal.TxModels.Definitions.TxM004
import Formal.TxModels.Definitions.TxM005
import Formal.TxModels.Definitions.TxM006
import Formal.TxModels.Definitions.TxM007
import Formal.TxModels.Definitions.TxM008
import Formal.TxModels.Definitions.TxM009

namespace Formal.TxModels.Index

/-- Maintained model catalogue. Implementations and metadata live in the imported modules. -/
def metadata : Array Metadata := #[
  TxM001.metadata, TxM002.metadata, TxM003.metadata, TxM004.metadata, TxM005.metadata, TxM006.metadata, TxM007.metadata, TxM008.metadata, TxM009.metadata]

/-- Export the catalogue for consumers of the transaction-model JSON schema. -/
def toJson : Lean.Json := .arr (metadata.map Metadata.toJson)

end Formal.TxModels.Index

import Lean

namespace Formal.Properties

/-- Code-owned reference to one maintained property definition and its metadata. -/
structure Entry where
  id : String
  definitionVersion : Int
  primary : Lean.Name
  metadataPath : System.FilePath

end Formal.Properties

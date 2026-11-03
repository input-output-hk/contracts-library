import Formal.Properties.Common
import Formal.Properties.Universal.UP001.Definition
import Formal.Properties.Universal.UP012.Definition
import Formal.Properties.Universal.UP015.Definition

namespace Formal.Properties.Universal.Index

def up001 : Entry := {
  id := "UP-001"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP001.statement
  metadataPath := "Formal/Properties/Universal/UP001/metadata.json" }

def up012 : Entry := {
  id := "UP-012"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP012.statement
  metadataPath := "Formal/Properties/Universal/UP012/metadata.json" }

def up015 : Entry := {
  id := "UP-015"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP015.statement
  metadataPath := "Formal/Properties/Universal/UP015/metadata.json" }

def entries : Array Entry := #[up001, up012, up015]

end Formal.Properties.Universal.Index

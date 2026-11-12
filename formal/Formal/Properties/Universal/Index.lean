import Formal.Properties.Common
import Formal.Properties.Universal.UP000.Definition
import Formal.Properties.Universal.UP001.Definition
import Formal.Properties.Universal.UP004.Definition
import Formal.Properties.Universal.UP007.Definition
import Formal.Properties.Universal.UP011.Definition
import Formal.Properties.Universal.UP012.Definition
import Formal.Properties.Universal.UP013.Definition
import Formal.Properties.Universal.UP014.Definition
import Formal.Properties.Universal.UP015.Definition

namespace Formal.Properties.Universal.Index

def up000 : Entry := {
  id := "UP-000"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP000.statement
  metadataPath := "Formal/Properties/Universal/UP000/metadata.json" }

def up001 : Entry := {
  id := "UP-001"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP001.statement
  metadataPath := "Formal/Properties/Universal/UP001/metadata.json" }

def up004 : Entry := {
  id := "UP-004"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP004.statement
  metadataPath := "Formal/Properties/Universal/UP004/metadata.json" }

def up007 : Entry := {
  id := "UP-007"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP007.statement
  metadataPath := "Formal/Properties/Universal/UP007/metadata.json" }

def up011 : Entry := {
  id := "UP-011"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP011.statement
  metadataPath := "Formal/Properties/Universal/UP011/metadata.json" }

def up012 : Entry := {
  id := "UP-012"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP012.statement
  metadataPath := "Formal/Properties/Universal/UP012/metadata.json" }

def up013 : Entry := {
  id := "UP-013"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP013.statement
  metadataPath := "Formal/Properties/Universal/UP013/metadata.json" }

def up014 : Entry := {
  id := "UP-014"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP014.statement
  metadataPath := "Formal/Properties/Universal/UP014/metadata.json" }

def up015 : Entry := {
  id := "UP-015"
  definitionVersion := 1
  primary := ``Formal.Properties.Universal.UP015.statement
  metadataPath := "Formal/Properties/Universal/UP015/metadata.json" }

def entries : Array Entry := #[up000, up001, up004, up007, up011, up012, up013, up014, up015]

end Formal.Properties.Universal.Index

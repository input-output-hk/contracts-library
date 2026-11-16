import Formal.Universal.Properties.Common
import Formal.Universal.Properties.UP000.Definition
import Formal.Universal.Properties.UP001.Definition
import Formal.Universal.Properties.UP004.Definition
import Formal.Universal.Properties.UP007.Definition
import Formal.Universal.Properties.UP008.Definition
import Formal.Universal.Properties.UP011.Definition
import Formal.Universal.Properties.UP012.Definition
import Formal.Universal.Properties.UP013.Definition
import Formal.Universal.Properties.UP014.Definition
import Formal.Universal.Properties.UP015.Definition

namespace Formal.Universal.Properties.Index

def up000 : Entry := {
  id := "UP-000"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP000.statement
  metadataPath := "Formal/Universal/Properties/UP000/metadata.json" }

def up001 : Entry := {
  id := "UP-001"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP001.statement
  metadataPath := "Formal/Universal/Properties/UP001/metadata.json" }

def up004 : Entry := {
  id := "UP-004"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP004.statement
  metadataPath := "Formal/Universal/Properties/UP004/metadata.json" }

def up007 : Entry := {
  id := "UP-007"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP007.statement
  metadataPath := "Formal/Universal/Properties/UP007/metadata.json" }

def up008 : Entry := {
  id := "UP-008"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP008.statement
  metadataPath := "Formal/Universal/Properties/UP008/metadata.json" }

def up011 : Entry := {
  id := "UP-011"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP011.statement
  metadataPath := "Formal/Universal/Properties/UP011/metadata.json" }

def up012 : Entry := {
  id := "UP-012"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP012.statement
  metadataPath := "Formal/Universal/Properties/UP012/metadata.json" }

def up013 : Entry := {
  id := "UP-013"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP013.statement
  metadataPath := "Formal/Universal/Properties/UP013/metadata.json" }

def up014 : Entry := {
  id := "UP-014"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP014.statement
  metadataPath := "Formal/Universal/Properties/UP014/metadata.json" }

def up015 : Entry := {
  id := "UP-015"
  definitionVersion := 1
  primary := ``Formal.Universal.Properties.UP015.statement
  metadataPath := "Formal/Universal/Properties/UP015/metadata.json" }

def entries : Array Entry := #[up000, up001, up004, up007, up008, up011, up012, up013, up014, up015]

end Formal.Universal.Properties.Index

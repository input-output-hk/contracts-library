import Candidates.Catalogue
import Workflow.Input

open Lean Workflow
open Workflow.Generator

namespace Workflow.Tests.Unit.Metadata.Bindings

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def purposeModels : Array (Purpose × String × String) := #[
  (.spend, "TxM-006", "EverySpend"), (.mint, "TxM-001", "EveryMint"),
  (.withdraw, "TxM-002", "EveryWithdraw"), (.publish, "TxM-003", "EveryPublish"),
  (.vote, "TxM-004", "EveryVote"), (.propose, "TxM-005", "EveryPropose")]

private def target (purposes : Array Purpose := #[]) : TargetDescription :=
  { name := "fixture.target", plutusVersion := "v3", compiledCode := "480100002221200101"
    handlers := purposes.map fun purpose =>
      { name := s!"fixture.target.{purpose.name}", purpose := some purpose,
        datum := none, redeemer := none, declaredHash := none }
    parameters := none, definitions := none, compiler := none }

private def generated (provider : Provider) (input : TargetDescription) : IO GenerationPlan :=
  IO.ofExcept ((Generator.generate provider input "Generated.MetadataBinding").mapError toString)

private def sameProgram (plain described : GenerationPlan) : Bool :=
  plain.modules.map (fun source => (source.name, source.source)) ==
      described.modules.map (fun source => (source.name, source.source)) &&
    plain.jobs.map (fun job => (job.propertyId, job.name, job.moduleName, job.statement,
      job.expected, job.scope, job.role, job.applicability)) ==
      described.jobs.map (fun job => (job.propertyId, job.name, job.moduleName, job.statement,
        job.expected, job.scope, job.role, job.applicability))

private def boundTo (job : CheckJob) (propertyId modelId : String) : Bool :=
  job.propertyId == propertyId && job.txModelId == some modelId &&
    job.binding.any fun binding =>
      binding.combinedCheck.propertyId? == some propertyId &&
      binding.combinedCheck.definitionVersion? == some 1 &&
      binding.combinedCheck.txModelId? == some modelId &&
      binding.txModel.id? == some modelId && binding.txModel.plutusVersion? == some "v3"

def run : IO Unit := do
  let definitions ← Formal.Properties.Index.entries.mapM fun entry => do
    IO.ofExcept (← PropertyDefinition.readRecord entry.metadataPath)
  let models ← IO.ofExcept (TransactionModel.parseList Formal.TxModels.Index.toJson)
  let combinations ← IO.ofExcept (← CombinedCheck.read "Candidates/combined-checks.json")
  let provider ← IO.ofExcept (Candidates.Catalogue.withBindings (some "UP-001")
    definitions models combinations)
  let loaded ← IO.ofExcept (← Candidates.Catalogue.loadProvider (some "UP-001"))
  check "native index loading and pure catalogue association retain identical snapshots"
    (loaded.propertyDefinition == provider.propertyDefinition && loaded.bindings == provider.bindings)
  check "UP001 registration loads six model combinations"
    (provider.bindings.any (fun bindings => bindings.size == 6))

  let allPurposes := purposeModels.map (fun (purpose, _, _) => purpose)
  let allJobs ← generated provider target
  let plainAll ← generated Candidates.UP001.provider target
  check "no declared purposes emits six bound property obligations"
    (allJobs.bindingsRequired && allJobs.jobs.size == 6 && allJobs.validateBindings.isOk)
  check "binding all UP001 models preserves generated source and propositions"
    (sameProgram plainAll allJobs)
  for (purpose, modelId, contextName) in purposeModels do
    let selected := allJobs.jobs.filter (·.name == s!"otherPurpose_{purpose.name}")
    check s!"UP001 {purpose.name} selects its registered context model"
      (selected.size == 1 && selected.all fun job =>
        boundTo job "UP-001" modelId && job.role == .property && job.applicability.isNone &&
          (job.statement.splitOn s!"{contextName}.ctx").length == 2 &&
          (job.statement.splitOn "Formal.Properties.Universal.UP001.statement").length == 2)
    let input := target (allPurposes.filter (· != purpose))
    let onlyMissing ← generated provider input
    check s!"only undeclared {purpose.name} generates a check"
      (onlyMissing.jobs.size == 1 && onlyMissing.jobs.all (fun job => boundTo job "UP-001" modelId))
    check s!"metadata preserves the single-purpose {purpose.name} source"
      (sameProgram (← generated Candidates.UP001.provider input) onlyMissing)
  let spendingTarget := target #[.spend]
  let spendingPlan ← generated provider spendingTarget
  check "the spend-only example retains the five nonspending model checks"
    (spendingPlan.jobs.map (·.txModelId) ==
      #[some "TxM-001", some "TxM-002", some "TxM-003", some "TxM-004", some "TxM-005"])
  let noJobs ← generated provider (target allPurposes)
  check "all declared purposes retain an empty plan without invented observations"
    (noJobs.jobs.isEmpty && noJobs.modules.isEmpty && noJobs.status == .noObligations &&
     noJobs.bindingsRequired && noJobs.validateBindings.isOk)

  check "unregistered property cannot obtain executable model bindings"
    (!(Candidates.Catalogue.withBindings (some "UP-unknown") definitions models combinations).isOk)
  for missing in [#[], models.filter (fun model => model.id? != some "TxM-001")] do
    check "registered provider rejects a missing maintained model"
      (!(Candidates.Catalogue.withBindings (some "UP-001") definitions missing combinations).isOk)
  check "registered provider rejects duplicated model records"
    (!(Candidates.Catalogue.withBindings (some "UP-001") definitions (models ++ models) combinations).isOk)
  for missing in [#[], combinations.filter (fun item => item.txModelId? != some "TxM-001")] do
    check "registered provider rejects a missing combination"
      (!(Candidates.Catalogue.withBindings (some "UP-001") definitions models missing).isOk)
  check "registered provider rejects duplicated combinations"
    (!(Candidates.Catalogue.withBindings (some "UP-001") definitions models
      (combinations ++ combinations)).isOk)
  let wrongVersion : CombinedCheck := { value := Json.mkObj [
    ("property", Json.mkObj [("id", .str "UP-001"), ("definition_version", toJson (2 : Int))]),
    ("tx_model", .str "TxM-001")] }
  let wrongVersionChecks := combinations.map fun item =>
    if item.txModelId? == some "TxM-001" then wrongVersion else item
  check "another property version cannot substitute for the registered combination"
    (!(Candidates.Catalogue.withBindings (some "UP-001") definitions models wrongVersionChecks).isOk)

  let v2Model : TransactionModel := { value := Json.mkObj [
    ("id", .str "TxM-001"), ("plutus_version", .str "v2")] }
  let wrongFormatModels := models.map fun model =>
    if model.id? == some "TxM-001" then v2Model else model
  let wrongFormatProvider ← IO.ofExcept (Candidates.Catalogue.withBindings (some "UP-001")
    definitions wrongFormatModels combinations)
  check "model language mismatch fails generation against a V3 target"
    (!(Generator.generate wrongFormatProvider spendingTarget "Generated.MetadataBinding").isOk)
  let missingMarker : Provider := { provider with generate := fun input modulePrefix => do
    let plan ← provider.generate input modulePrefix
    return { plan with jobs := plan.jobs.map (fun job => { job with txModelId := none }) } }
  check "complete metadata cannot replace the registered construction marker"
    (!(Generator.generate missingMarker spendingTarget "Generated.MetadataBinding").isOk)
  let missingBindings := { provider with bindings := some #[] }
  check "metadata-enabled provider cannot silently omit selected bindings"
    (!(Generator.generate missingBindings spendingTarget "Generated.MetadataBinding").isOk)
  let some bindings := provider.bindings | throw (IO.userError "missing registered bindings")
  let duplicatedBindings := { provider with bindings := some (bindings ++ bindings) }
  check "generator rejects ambiguous supplied bindings"
    (!(Generator.generate duplicatedBindings spendingTarget "Generated.MetadataBinding").isOk)

  let some definition := provider.propertyDefinition | throw (IO.userError "missing property metadata")
  let some mintBinding := bindings.find? (fun binding => binding.txModel.id? == some "TxM-001")
    | throw (IO.userError "missing mint binding")
  let preattached (binding : CheckBinding) : Provider := {
    id := "UP-001"
    propertyDefinition := some definition
    bindings := none
    generate := fun input modulePrefix => .ok {
      targetName := input.name
      modules := #[⟨s!"{modulePrefix}.Checks", "-- direct provider fixture\n"⟩]
      jobs := #[{
        propertyId := "UP-001"
        name := "direct"
        moduleName := s!"{modulePrefix}.Checks"
        statement := "True"
        expected := .valid
        scope := "direct provider fixture"
        txModelId := some "TxM-001"
        binding := some binding }] } }
  check "direct provider may retain a consistent preattached V3 binding"
    ((Generator.generate (preattached mintBinding) spendingTarget "Generated.MetadataBinding").isOk)
  check "direct provider cannot bypass target language matching with preattached metadata"
    (!(Generator.generate (preattached { mintBinding with txModel := v2Model })
      spendingTarget "Generated.MetadataBinding").isOk)
  check "explicitly metadata-free provider remains usable without official labels"
    (plainAll.jobs.all (·.binding.isNone) && plainAll.propertyDefinition.isNone && !plainAll.bindingsRequired)

  let vesting ← IO.ofExcept ((← Input.read "Workflow/Tests/UP012/Inputs/plutus.json"
    "linear_vesting.linear_vesting").mapError toString)
  let vestingProvider ← IO.ofExcept (← Candidates.Catalogue.loadProvider (some "UP-012"))
  let vestingPlan ← generated vestingProvider vesting.target
  check "UP012 preserves four obligations across two combinations"
    (vestingPlan.bindingsRequired && vestingPlan.jobs.size == 4 &&
      vestingProvider.bindings.any (fun values => values.size == 3) && vestingPlan.validateBindings.isOk)
  check "UP012 binding preserves sources, propositions, expectations, and support references"
    (sameProgram (← generated Workflow.Tests.UP012.Profile.provider vesting.target) vestingPlan)
  for (action, modelId) in [("claim", "TxM-007"), ("cancel", "TxM-008")] do
    let some mainJob := vestingPlan.jobs.find? (·.name == s!"dropSigner_{action}")
      | throw (IO.userError s!"missing {action} property job")
    let some support := vestingPlan.jobs.find? (·.name == s!"dropSigner_{action}_applies")
      | throw (IO.userError s!"missing {action} applicability job")
    check s!"UP012 {action} uses the same exact binding for main and applicability"
      (boundTo mainJob "UP-012" modelId && boundTo support "UP-012" modelId &&
       mainJob.binding == support.binding && mainJob.role == .property &&
       support.role == .applicability && support.applicability.isNone &&
       mainJob.applicability == some { moduleName := support.moduleName, name := support.name })
  IO.println "Catalogue model-binding integration checks passed."

end Workflow.Tests.Unit.Metadata.Bindings

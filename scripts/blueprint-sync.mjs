/**
 * Blueprint sync: single source of truth for the pinned MeshJS off-chain
 * blueprints.
 *
 * Reads `onchain/plutus.json` (the Aiken blueprint emitted by the on-chain
 * build) and regenerates the hand-held blueprint.ts modules under
 * `offchain/meshjs/lib/src` plus the `blueprint` hash map in
 * `offchain/meshjs/lib/package.json`.
 *
 * The per-file shapes (doc comments, export names, quirks such as
 * `event_triggered` having no hash constants) are described by the mapping
 * table below; the script itself is shape-agnostic.
 *
 *   node scripts/blueprint-sync.mjs --check   # exit 1 on any drift (CI)
 *   node scripts/blueprint-sync.mjs --write   # regenerate on drift
 *
 * Idempotent: running --write twice produces identical output.
 *
 * Note on variants: a validator's mint/spend/else/publish/withdraw purposes
 * share one script hash and one compiled program, so any variant qualifies as
 * the pinned source. The table picks one deterministically (the first
 * purpose-ful variant) so regeneration is stable.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

const PLUTUS_JSON = join(REPO_ROOT, "onchain/plutus.json");
const LIB_PACKAGE = join(REPO_ROOT, "offchain/meshjs/lib/package.json");

/** Rendering template shared by every `blueprint.ts`. */
function renderBlueprint({ headerComment, entries, plutusVersion }) {
  if (!Array.isArray(headerComment)) {
    throw new TypeError(
      `headerComment must be an array (got ${typeof headerComment})`,
    );
  }
  for (const e of entries) {
    if (!e.codeExport || typeof e.code !== "string") {
      throw new TypeError(
        `entry ${JSON.stringify(e.mapKey ?? e.codeExport)} lacks code`,
      );
    }
  }
  const out = [];
  out.push("/**", ...headerComment.map((l) => ` * ${l}`), " */", "");
  for (const e of entries) {
    if (e.codeDoc) {
      const docs = Array.isArray(e.codeDoc) ? e.codeDoc : [e.codeDoc];
      out.push("/**", ...docs.map((l) => ` * ${l}`), " */");
    }
    out.push(`export const ${e.codeExport} =`, `  "${e.code}";`, "");
    if (e.hashExport) {
      if (e.hashDoc) {
        const docs = Array.isArray(e.hashDoc) ? e.hashDoc : [e.hashDoc];
        out.push("/**", ...docs.map((l) => ` * ${l}`), " */");
      }
      out.push(`export const ${e.hashExport} =`, `  "${e.hash}";`, "");
    }
  }
  if (plutusVersion) {
    out.push('export const plutusVersion = "V3" as const;');
  }
  while (out.length > 0 && out[out.length - 1] === "") {
    out.pop();
  }
  return `${out.join("\n")}\n`;
}

/** The blueprint modules, their mapping table and hand-held headers. */
const BLUEPRINTS = [
  {
    file: "offchain/meshjs/lib/src/vesting/blueprint.ts",
    header: [
      "Pinned on-chain blueprint for the linear vesting validator.",
      "GENERATED ARTIFACT — do not hand-edit. Regenerate with",
      "`npm run blueprint:update` (scripts/blueprint-sync.mjs) from",
      "`onchain/plutus.json` when the validator changes, and bump the",
      "off-chain package version alongside it, per docs/ARCHITECTURE.md §2.2 —",
      "off-chain pins to a specific blueprint so the two layers cannot",
      "silently drift.",
      "Source: onchain/plutus.json",
      "Compiler: @{compiler}",
      "Plutus version: V3",
    ],
    entries: [
      {
        mapKey: "vesting",
        title: "linear_vesting.linear_vesting.spend",
        codeExport: "compiledCode",
        codeDoc: [
          "Raw, single-CBOR-encoded compiled code as emitted by Aiken.",
        ],
        hashExport: "validatorHash",
        hashDoc: [
          "Blake2b-224 hash of the validator script (= script's payment credential).",
        ],
      },
    ],
    plutusVersion: true,
  },
  {
    file: "offchain/meshjs/lib/src/dao/blueprint.ts",
    header: [
      "Pinned on-chain blueprints for the DAO validators (proposal, stake, vote)",
      "and the reference poll-effect candidate (poll_effect).",
      "GENERATED ARTIFACT — do not hand-edit. Regenerate with",
      "`npm run blueprint:update` (scripts/blueprint-sync.mjs) from",
      "`onchain/plutus.json` when the validators change.",
      "Source: onchain/plutus.json",
      "Compiler: @{compiler}",
      "Plutus version: V3",
      "Each validator's mint/spend/else purposes share one script hash; the",
      "`compiledCode` below is that single (parameterizable) script, exactly as",
      "emitted by Aiken (single-CBOR-encoded, ready for `applyParamsToScript`).",
      "Hash constants are copied verbatim from the Aiken blueprint's `hash`",
      "field (Blake2b-224, Aiken's own script hashing).",
    ],
    entries: [
      {
        mapKey: "dao.proposal",
        title: "dao/proposal.proposal.mint",
        codeExport: "proposalCompiledCode",
        hashExport: "proposalValidatorHash",
        hashDoc: [
          "Blake2b-224 hash of the proposal validator script (= its policy id / payment credential).",
        ],
      },
      {
        mapKey: "dao.stake",
        title: "dao/stake.stake.mint",
        codeExport: "stakeCompiledCode",
        hashExport: "stakeValidatorHash",
        hashDoc: [
          "Blake2b-224 hash of the stake validator script (= its policy id / payment credential).",
        ],
      },
      {
        mapKey: "dao.vote",
        title: "dao/vote.vote.mint",
        codeExport: "voteCompiledCode",
        hashExport: "voteValidatorHash",
        hashDoc: [
          "Blake2b-224 hash of the vote validator script (= its policy id / payment credential).",
        ],
      },
      {
        // Candidate script: pinned for polling usage, not in the package map.
        title: "dao/poll_effect.poll_effect.withdraw",
        codeExport: "pollEffectCompiledCode",
        codeDoc: [
          "Raw (unparameterized) poll-effect candidate script; parameterize with the",
          "proposal validator's hash before use (see `pollEffectScript`).",
        ],
      },
    ],
    plutusVersion: true,
  },
  {
    file: "offchain/meshjs/lib/src/settings/blueprint.ts",
    header: [
      "Pinned on-chain blueprint for the settings validator.",
      "GENERATED ARTIFACT — do not hand-edit. Regenerate with",
      "`npm run blueprint:update` (scripts/blueprint-sync.mjs) from",
      "`onchain/plutus.json` when the validator changes.",
      "Source: onchain/plutus.json",
      "Compiler: @{compiler}",
      "Plutus version: V3",
    ],
    entries: [
      {
        mapKey: "settings",
        title: "settings/settings.settings.spend",
        codeExport: "compiledCode",
        codeDoc: [
          "Raw, single-CBOR-encoded compiled code as emitted by Aiken (unparameterized).",
        ],
        hashExport: "validatorHash",
        hashDoc: [
          "Blake2b-224 hash of the validator script (= script's payment credential).",
        ],
      },
      {
        mapKey: "settings_typed",
        title: "settings/settings_typed.settings_typed.spend",
        codeExport: "typedCompiledCode",
        hashExport: "typedValidatorHash",
      },
    ],
    plutusVersion: true,
  },
  {
    file: "offchain/meshjs/lib/src/smart_wallet/blueprint.ts",
    header: [
      "Pinned on-chain blueprints for the smart wallet validators.",
      "GENERATED ARTIFACT — do not hand-edit. Regenerate with",
      "`npm run blueprint:update` (scripts/blueprint-sync.mjs) from",
      "`onchain/plutus.json` when the validators change.",
      "Source: onchain/plutus.json",
      "Compiler: @{compiler}",
      "Plutus version: V3",
    ],
    entries: [
      {
        mapKey: "smart_wallet",
        title: "smart_wallet/smart_wallet.smart_wallet.spend",
        codeExport: "smartWalletCode",
        codeDoc: [
          "Raw compiled code for the `smart_wallet` multivalidator (unparameterized).",
        ],
        hashExport: "smartWalletHash",
        hashDoc: ["Blake2b-224 hash of the `smart_wallet` validator script."],
      },
      ...[
        "spending_limit",
        "spending_window",
        "spending_period_limit",
        "full_recipient_allow_list",
        "full_recipient_deny_list",
        "payment_staking_allow_list",
        "payment_staking_deny_list",
        "asset_allow_list",
        "asset_deny_list",
        "asset_deposit_allow_list",
        "asset_deposit_deny_list",
      ].map((slug) => {
        const name = slug
          .split("_")
          .map((w, i) => (i === 0 ? w : w[0].toUpperCase() + w.slice(1)))
          .join("");
        return {
          mapKey: `smart_wallet.${slug}`,
          title: `smart_wallet/withdrawal_scripts/${slug}.${slug}.publish`,
          codeExport: `${name}Code`,
          codeDoc: [
            `Raw compiled code for the \`${slug}\` withdrawal script (unparameterized).`,
          ],
          hashExport: `${name}Hash`,
          hashDoc: [`Blake2b-224 hash of the \`${slug}\` withdrawal script.`],
        };
      }),
    ],
    plutusVersion: true,
  },
  {
    file: "offchain/meshjs/lib/src/event_triggered/blueprint.ts",
    header: [
      "Pinned on-chain blueprint for the event-triggered assets (tokenized bond)",
      "substandard — six validators per docs/event-triggered-assets/spec.md.",
      "GENERATED ARTIFACT — do not hand-edit. Regenerate with",
      "`npm run blueprint:update` (scripts/blueprint-sync.mjs) from",
      "`onchain/plutus.json` when the validators change.",
      "All six validators are parameterized (Aiken `validator f(p: ...)`); the code",
      "below is the unparameterized form, and the builders apply each deployment's",
      "parameters at runtime via `applyParamsToScript` (see event_triggered.ts).",
      "Source: onchain/plutus.json",
      "Plutus version: V3",
    ],
    // The module historically exposes only the compiled code (consumers take
    // the hashes from the registry scripts' deployment), so no hash constants.
    entries: [
      {
        mapKey: "event_triggered.issuance",
        title: "event_triggered_assets.issuance.withdraw",
        codeExport: "issuanceCompiledCode",
        codeDoc: [
          "Issuance logic (withdraw-0) — registration, the permissionless deposit, the coupon claim advance and the maturity retirement (§4.1, §4.2, §4.5, §4.7).",
        ],
      },
      {
        mapKey: "event_triggered.transfer",
        title: "event_triggered_assets.transfer.withdraw",
        codeExport: "transferCompiledCode",
        codeDoc: [
          "Transfer logic (withdraw-0) — name monotonicity: the claim state never rewinds (§4.3).",
        ],
      },
      {
        mapKey: "event_triggered.third_party",
        title: "event_triggered_assets.third_party.withdraw",
        codeExport: "thirdPartyCompiledCode",
        codeDoc: [
          "Third-party logic (withdraw-0) — the opt-in issuer trigger (§4.5, §4.7).",
        ],
      },
      {
        mapKey: "event_triggered.vault",
        title: "event_triggered_assets.vault.spend",
        codeExport: "vaultCompiledCode",
        codeDoc: [
          "Vault spending validator — deposit and burn-to-pay redemption, paired by the vault NFT (§3.1, §4.2, §4.6).",
        ],
      },
      {
        mapKey: "event_triggered.coupon_policy",
        title: "event_triggered_assets.coupon_policy.mint",
        codeExport: "couponPolicyCompiledCode",
        codeDoc: [
          "Coupon policy (mint) — the scheduled step coupons and the principal coupon (§3.2, §4.5, §4.7).",
        ],
      },
      {
        mapKey: "event_triggered.vault_nft_policy",
        title: "event_triggered_assets.vault_nft_policy.mint",
        codeExport: "vaultNftPolicyCompiledCode",
        codeDoc: [
          "Vault NFT policy (mint) — one authority-minted NFT per vault (§3.1, I10).",
        ],
      },
    ],
    plutusVersion: false,
  },
];

function loadInputs() {
  const plutus = JSON.parse(readFileSync(PLUTUS_JSON, "utf8"));
  const libPackage = JSON.parse(readFileSync(LIB_PACKAGE, "utf8"));
  const compilerString = `aiken-${plutus.preamble?.compiler?.version ?? ""}`;
  return { plutus, libPackage, compilerString };
}

/** Recompute every artifact (file bodies + package.json blueprint map). */
function compute({ plutus }) {
  const validators = new Map(plutus.validators.map((v) => [v.title, v]));
  const results = [];
  const enrichedPerSpec = [];

  for (const spec of BLUEPRINTS) {
    const entries = spec.entries.map((e) => {
      const v = validators.get(e.title);
      if (!v) {
        throw new Error(`onchain/plutus.json has no validator "${e.title}"`);
      }
      return {
        ...e,
        code: v.compiledCode,
        hash: v.hash,
      };
    });
    enrichedPerSpec.push(entries);

    const header = spec.header.map((l) =>
      l.replace(
        "@{compiler}",
        `Aiken ${plutus.preamble?.compiler?.version ?? ""}`,
      ),
    );
    const body = renderBlueprint({
      headerComment: header.filter((l) => l !== ""),
      entries,
      plutusVersion: spec.plutusVersion,
    });
    results.push({ kind: "file", file: spec.file, body });
  }

  // Regenerate the package.json blueprint map in table order (compiler last).
  const newMap = {};
  for (const entries of enrichedPerSpec) {
    for (const e of entries) {
      if (e.mapKey) newMap[e.mapKey] = e.hash;
    }
  }
  newMap.compiler = `aiken-${plutus.preamble?.compiler?.version ?? ""}`;
  results.push({ kind: "package", map: newMap });

  return results;
}

function main() {
  const mode = process.argv[2] ?? "--check";
  if (mode !== "--check" && mode !== "--write") {
    console.error("usage: node scripts/blueprint-sync.mjs [--check|--write]");
    process.exit(2);
  }

  const drift = [];
  const { plutus, libPackage } = loadInputs();
  const artifacts = compute({ plutus });

  // Validate the compiler pin in package.json.
  const expectedCompiler = `aiken-${plutus.preamble?.compiler?.version ?? ""}`;
  if (libPackage.blueprint?.compiler !== expectedCompiler) {
    drift.push(
      `offchain/meshjs/lib/package.json: "blueprint.compiler" is ${JSON.stringify(libPackage.blueprint?.compiler)}, expected ${JSON.stringify(expectedCompiler)}`,
    );
  }

  for (const art of artifacts) {
    if (art.kind === "file") {
      const path = join(REPO_ROOT, art.file);
      const current = readFileSync(path, "utf8");
      if (current !== art.body) {
        drift.push(
          `${art.file}: blueprint file is out of sync with onchain/plutus.json`,
        );
        if (mode === "--write") {
          writeFileSync(path, art.body);
          drift[drift.length - 1] = `${art.file}: regenerated ✓`;
        }
      }
    } else if (art.kind === "package") {
      const actualMap = libPackage.blueprint ?? {};
      if (JSON.stringify(actualMap) !== JSON.stringify(art.map)) {
        drift.push(
          'offchain/meshjs/lib/package.json: "blueprint" hash map out of sync',
        );
        if (mode === "--write") {
          libPackage.blueprint = art.map;
          writeFileSync(
            LIB_PACKAGE,
            `${JSON.stringify(libPackage, null, 2)}\n`,
          );
          drift[drift.length - 1] =
            "offchain/meshjs/lib/package.json: blueprint map regenerated ✓";
        }
      }
    }
  }

  if (drift.length === 0) {
    console.log(
      "blueprint sync: everything in sync with onchain/plutus.json ✓",
    );
    return;
  }

  if (mode === "--write") {
    console.log(
      `blueprint sync: ${drift.filter((d) => d.includes("✓")).length} artifact(s) regenerated · run with --check to verify idempotency`,
    );
    drift.forEach((d) => {
      console.log(`  ${d}`);
    });
    return;
  }

  console.error(
    `blueprint sync: ${drift.length} drift issue(s) — run \`npm run blueprint:update\` to regenerate:\n${drift.map((d) => `  - ${d}`).join("\n")}`,
  );
  process.exit(1);
}

main();

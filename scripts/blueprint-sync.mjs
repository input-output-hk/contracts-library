/**
 * Blueprint sync — pins the MeshJS off-chain blueprints to `onchain/plutus.json`.
 *
 * Each blueprint.ts module already holds every doc and export definition; this
 * script only patches the values that change when the on-chain layer moves:
 * the compiled code hex and the script hash of each pinned validator, plus the
 * `blueprint` hash map in `offchain/meshjs/lib/package.json`.
 *
 *   node scripts/blueprint-sync.mjs --check   # exit 1 on any drift (CI)
 *   node scripts/blueprint-sync.mjs --write   # patch values in place
 *
 * Purpose variants (mint/spend/else/publish/withdraw) share code and hash, so
 * any variant qualifies as the pinned source; the table names one
 * deterministically. Adding a validator: hand-write its block in blueprint.ts
 * once (doc included), then add the entry to the table below.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");

const PINS = [
  {
    file: "offchain/meshjs/lib/src/vesting/blueprint.ts",
    entries: [
      {
        mapKey: "vesting",
        title: "linear_vesting.linear_vesting.spend",
        codeExport: "compiledCode",
        hashExport: "validatorHash",
      },
    ],
  },
  {
    file: "offchain/meshjs/lib/src/dao/blueprint.ts",
    entries: [
      {
        mapKey: "dao.proposal",
        title: "dao/proposal.proposal.mint",
        codeExport: "proposalCompiledCode",
        hashExport: "proposalValidatorHash",
      },
      {
        mapKey: "dao.stake",
        title: "dao/stake.stake.mint",
        codeExport: "stakeCompiledCode",
        hashExport: "stakeValidatorHash",
      },
      {
        mapKey: "dao.vote",
        title: "dao/vote.vote.mint",
        codeExport: "voteCompiledCode",
        hashExport: "voteValidatorHash",
      },
      {
        // Candidate script: not pinned in the package map.
        title: "dao/poll_effect.poll_effect.withdraw",
        codeExport: "pollEffectCompiledCode",
      },
    ],
  },
  {
    file: "offchain/meshjs/lib/src/settings/blueprint.ts",
    entries: [
      {
        mapKey: "settings",
        title: "settings/settings.settings.spend",
        codeExport: "compiledCode",
        hashExport: "validatorHash",
      },
      {
        mapKey: "settings_typed",
        title: "settings/settings_typed.settings_typed.spend",
        codeExport: "typedCompiledCode",
        hashExport: "typedValidatorHash",
      },
    ],
  },
  {
    file: "offchain/meshjs/lib/src/smart_wallet/blueprint.ts",
    entries: [
      {
        mapKey: "smart_wallet",
        title: "smart_wallet/smart_wallet.smart_wallet.spend",
        codeExport: "smartWalletCode",
        hashExport: "smartWalletHash",
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
      ].map((slug) => ({
        mapKey: `smart_wallet.${slug}`,
        title: `smart_wallet/withdrawal_scripts/${slug}.${slug}.publish`,
        codeExport: `${camel(slug)}Code`,
        hashExport: `${camel(slug)}Hash`,
      })),
    ],
  },
  {
    file: "offchain/meshjs/lib/src/event_triggered/blueprint.ts",
    entries: [
      ["issuance", "withdraw"],
      ["transfer", "withdraw"],
      ["third_party", "withdraw"],
      ["vault", "spend"],
      ["coupon_policy", "mint"],
      ["vault_nft_policy", "mint"],
    ].map(([slug, purpose]) => ({
      mapKey: `event_triggered.${slug}`,
      title: `event_triggered_assets.${slug}.${purpose}`,
      codeExport: `${camel(slug)}CompiledCode`,
    })),
  },
];

function camel(slug) {
  return slug
    .split("_")
    .map((w, i) => (i === 0 ? w : w[0].toUpperCase() + w.slice(1)))
    .join("");
}

/** {plutus, pins: [{file, title, mapKey?, code, hash?}], compilerPin} */
function inputs() {
  const plutus = JSON.parse(
    readFileSync(join(REPO, "onchain/plutus.json"), "utf8"),
  );
  const byTitle = new Map(plutus.validators.map((v) => [v.title, v]));
  const pins = [];
  for (const spec of PINS) {
    for (const e of spec.entries) {
      const v = byTitle.get(e.title);
      if (!v)
        throw new Error(`onchain/plutus.json has no validator "${e.title}"`);
      pins.push({ file: spec.file, ...e, code: v.compiledCode, hash: v.hash });
    }
  }
  return {
    plutus,
    pins,
    compilerPin: `aiken-${plutus.preamble?.compiler?.version ?? ""}`,
  };
}

const constRe = (name) =>
  new RegExp(`(export const ${name}\\s*=\\s*")([0-9a-fA-F]+)(")`);

/** Set `export const NAME = "…"` to VALUE, in place; null when already set. */
function patchConst(text, name, value) {
  const re = constRe(name);
  const m = text.match(re);
  if (!m) throw new Error(`no \`export const ${name}\` to patch`);
  return m[2] === value ? null : text.replace(re, `$1${value}$3`);
}

function main() {
  const mode = process.argv[2] ?? "--check";
  if (mode !== "--check" && mode !== "--write") {
    console.error("usage: node scripts/blueprint-sync.mjs [--check|--write]");
    process.exit(2);
  }

  const { pins, compilerPin } = inputs();
  const libPackage = JSON.parse(
    readFileSync(join(REPO, "offchain/meshjs/lib/package.json"), "utf8"),
  );

  // {fileText: Map<file, text>, patches: [{file, name, kind: "code"|"hash"|"map"|"compiler"}]}
  const texts = new Map();
  const patched = [];

  for (const p of pins) {
    if (!texts.has(p.file))
      texts.set(p.file, readFileSync(join(REPO, p.file), "utf8"));
    const text = texts.get(p.file);

    const nextCode = patchConst(text, p.codeExport, p.code);
    if (nextCode !== null) {
      texts.set(p.file, nextCode);
      patched.push(`${p.file}: \`${p.codeExport}\` patched`);
    }
    if (p.hashExport) {
      const nextHash = patchConst(texts.get(p.file), p.hashExport, p.hash);
      if (nextHash !== null) {
        texts.set(p.file, nextHash);
        patched.push(`${p.file}: \`${p.hashExport}\` patched`);
      }
    }
    if (p.mapKey && libPackage.blueprint?.[p.mapKey] !== p.hash) {
      libPackage.blueprint[p.mapKey] = p.hash;
      patched.push(`lib/package.json: "blueprint.${p.mapKey}" patched`);
    }
  }
  if (libPackage.blueprint?.compiler !== compilerPin) {
    libPackage.blueprint.compiler = compilerPin;
    patched.push('lib/package.json: "blueprint.compiler" patched');
  }

  if (patched.length === 0) {
    console.log("blueprint sync: in sync with onchain/plutus.json ✓");
    return;
  }
  if (mode === "--check") {
    console.error(
      `blueprint sync: ${patched.length} values out of sync with onchain/plutus.json — run \`npm run blueprint:update\`:\n${patched.map((d) => `  - ${d}`).join("\n")}`,
    );
    process.exit(1);
  }

  for (const [file, text] of texts) {
    writeFileSync(join(REPO, file), text);
  }
  writeFileSync(
    join(REPO, "offchain/meshjs/lib/package.json"),
    `${JSON.stringify(libPackage, null, 2)}\n`,
  );
  console.log(`blueprint sync: ${patched.length} value(s) patched ✓`);
  for (const d of patched) {
    console.log(`  ${d}`);
  }
}

main();

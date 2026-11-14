<script lang="ts">
  import DatumTree from "./DatumTree.svelte";
  import type { DiagramUtxo } from "./schema.js";
  import { formatUtxoId } from "./utxo-id.js";

  let {
    utxo,
    variant = "input",
    fallbackIndex,
    hideConnectorOnMobile = false,
    dataChainPort,
  }: {
    utxo: DiagramUtxo;
    variant?: "input" | "output";
    fallbackIndex: number;
    hideConnectorOnMobile?: boolean;
    dataChainPort?: string | undefined;
  } = $props();

  const roleLabel = $derived(
    variant === "output" ? "Output" : utxo.reference ? "Reference input" : "Input",
  );
  const label = $derived(
    utxo.name || (variant === "output" ? `OUTPUT ${fallbackIndex}` : `INPUT ${fallbackIndex}`),
  );
  const accessibleLabel = $derived(utxo.name || fallbackIndex);

  function renderValue(
    value: Record<string, string> | undefined,
  ): { asset: string; amount: string }[] {
    if (!value) {
      return [];
    }
    return Object.entries(value).map(([asset, amount]) => ({ asset, amount }));
  }
</script>

{#if utxo.dots}
  <div
    class="tx-dots"
    role="img"
    aria-label={variant === "output" ? "Additional outputs omitted" : "Additional inputs omitted"}
  >
    •••
  </div>
{:else}
  <div
    class="tx-utxo"
    class:tx-reference={utxo.reference}
    class:tx-hide-conn-mobile={hideConnectorOnMobile}
    data-chain-port={dataChainPort}
    role="group"
    aria-label={`${roleLabel} ${accessibleLabel}`}
  >
    <div class="tx-utxo-header">
      <span class="tx-utxo-name">
        {#if variant !== "output" && utxo.redeemer}
          <span class="tx-redeemer-dot" aria-hidden="true"></span>
        {/if}
        <span class="tx-utxo-label" title={utxo.name ? "UTxO name" : undefined}>{label}</span>
      </span>
      {#if utxo.id}
        <span class="tx-utxo-id" title={utxo.id}>{formatUtxoId(utxo.id)}</span>
      {/if}
      {#if variant !== "output" && utxo.redeemer}
        <span class="tx-redeemer" title="Redeemer on UTxO spending">
          <span class="tx-redeemer-glyph" aria-hidden="true">▸</span>
          {utxo.redeemer}
        </span>
      {/if}
    </div>
    {#if utxo.address}
      <div class="tx-utxo-address" title="UTxO address">{utxo.address}</div>
    {/if}
    {#if utxo.value}
      <div class="tx-section">
        <span class="tx-section-label">Value:</span>
        {#each renderValue(utxo.value) as { asset, amount } (asset)}
          <div class="tx-value-row" class:tx-value-ada={asset === "ADA"}>
            <span class="tx-value-amount">{amount}</span>
            {#if asset === "ADA"}
              <span class="tx-value-asset">{asset}</span>
            {:else}
              <span class="tx-value-asset tx-value-asset-id">{asset}</span>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
    {#if utxo.datum}
      <div class="tx-section">
        <span class="tx-section-label">Datum:</span>
        <DatumTree datum={utxo.datum} />
      </div>
    {/if}
    <div
      class="tx-conn"
      class:tx-conn-in={variant !== "output"}
      class:tx-conn-out={variant === "output"}
      class:tx-reference={utxo.reference}
      aria-hidden="true"
    ></div>
  </div>
{/if}

<style>
  .tx-utxo {
    position: relative;
    box-sizing: border-box;
    min-width: 12rem;
    max-width: 100%;
    border: 1px solid var(--_txd-stroke);
    border-radius: var(--_txd-radius-md);
    padding: 12px;
    background: var(--_txd-surface-sunken);
  }

  @media (max-width: 767px) {
    .tx-utxo {
      min-width: 0;
    }

    .tx-utxo.tx-hide-conn-mobile .tx-conn {
      display: none;
    }
  }

  .tx-utxo.tx-reference {
    border-style: dashed;
    border-color: var(--_txd-accent);
  }

  .tx-utxo-header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 8px;
    margin-bottom: 4px;
  }

  .tx-utxo-label {
    font-size: var(--_txd-text-2xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--_txd-fg-1);
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .tx-utxo-name {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .tx-reference .tx-utxo-label {
    color: var(--_txd-accent);
  }

  .tx-utxo-id {
    font-family: var(--_txd-font-mono);
    font-size: var(--_txd-text-2xs);
    font-weight: 400;
    color: var(--_txd-fg-4);
    overflow-wrap: anywhere;
  }

  .tx-redeemer {
    display: inline-flex;
    align-items: center;
    font-size: var(--_txd-text-2xs);
    padding: 2px 6px;
    border-radius: var(--_txd-radius-sm);
    background: color-mix(in oklch, var(--_txd-primary) 22%, transparent);
    color: var(--_txd-fg-1);
    font-weight: 600;
  }

  .tx-redeemer-glyph {
    color: var(--_txd-primary-deep);
    margin-right: 3px;
    font-size: 0.75em;
    line-height: 1;
  }

  .tx-redeemer-dot {
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--_txd-primary);
    flex-shrink: 0;
  }

  .tx-utxo-address {
    font-size: var(--_txd-text-xs);
    font-weight: 600;
    color: var(--_txd-accent-soft);
    margin-bottom: 8px;
    font-family: var(--_txd-font-mono);
    overflow-wrap: anywhere;
  }

  .tx-section {
    margin-top: 8px;
  }

  .tx-section + .tx-section {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid var(--_txd-stroke-soft);
  }

  .tx-section-label {
    font-size: var(--_txd-text-2xs);
    font-weight: 500;
    color: var(--_txd-fg-2);
    display: block;
    margin-bottom: 4px;
  }

  /* Value rows — ADA-first hierarchy, register alignment */
  .tx-value-row {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0 4px;
    font-family: var(--_txd-font-mono);
    font-size: var(--_txd-text-xs);
    line-height: 1.6;
    font-variant-numeric: tabular-nums;
  }

  .tx-value-amount {
    color: var(--_txd-fg-1);
    font-weight: 400;
  }

  .tx-value-ada .tx-value-amount {
    font-weight: 600;
  }

  .tx-value-amount {
    white-space: nowrap;
  }

  .tx-value-asset {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .tx-value-asset {
    color: var(--_txd-fg-2);
  }

  .tx-value-asset-id {
    color: var(--_txd-accent-soft);
  }

  /* Horizontal connectors from each UTxO to the transaction box */
  .tx-conn {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    height: 3px;
    width: 16px;
    background: var(--_txd-primary);
    border-radius: 2px;
    z-index: 1;
  }

  .tx-conn-in {
    right: -17px;
  }

  .tx-conn-out {
    left: -17px;
  }

  .tx-conn.tx-reference {
    background: var(--_txd-accent);
  }

  .tx-dots {
    font-size: var(--_txd-text-xl);
    color: var(--_txd-fg-3);
    text-align: center;
    padding: 24px 0;
    letter-spacing: 0.3em;
  }
</style>

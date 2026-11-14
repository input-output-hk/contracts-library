<script lang="ts">
  import DatumTree from "./DatumTree.svelte";
  import type { Datum } from "./schema.js";

  let { datum, label }: { datum: Datum; label?: string } = $props();

  function isBranch(value: unknown): value is object {
    return typeof value === "object" && value !== null;
  }

  function hasChildren(value: unknown): value is object {
    return isBranch(value) && Object.keys(value).length > 0;
  }

  function hasValue(value: unknown): boolean {
    return value !== undefined && value !== "";
  }
</script>

{#snippet renderEntries(entries: [string, string | Datum][])}
  {#each entries as [key, value] (key)}
    {#if hasChildren(value)}
      <DatumTree datum={value} label={key} />
    {:else}
      <div class="tx-datum-leaf">
        <span
          class="tx-datum-key"
          class:tx-datum-key-constructor={isBranch(value) || !hasValue(value)}>{key}</span
        >
        {#if !isBranch(value) && hasValue(value)}
          <span class="tx-datum-sep">:</span>
          <span class="tx-datum-val">{value}</span>
        {/if}
      </div>
    {/if}
  {/each}
{/snippet}

{#if label === undefined}
  <div class="tx-datum-root">
    {#if Object.keys(datum).length === 0}
      <span class="tx-datum-empty">Empty object</span>
    {:else}
      {@render renderEntries(Object.entries(datum))}
    {/if}
  </div>
{:else}
  <details class="tx-datum-disclosure" open>
    <summary class="tx-datum-summary">
      <svg class="tx-datum-chevron" viewBox="0 0 16 16" aria-hidden="true"
        ><path d="M6 3.5 10.5 8 6 12.5" /></svg
      >
      <span class="tx-datum-summary-label">{label}</span>
    </summary>

    <div class="tx-datum-children">
      {#if Object.keys(datum).length === 0}
        <span class="tx-datum-empty">Empty object</span>
      {:else}
        {@render renderEntries(Object.entries(datum))}
      {/if}
    </div>
  </details>
{/if}

<style>
  .tx-datum-disclosure {
    font-family: var(--_txd-font-mono);
    font-size: var(--_txd-text-xs);
  }

  .tx-datum-root {
    font-family: var(--_txd-font-mono);
    font-size: var(--_txd-text-xs);
  }

  .tx-datum-summary {
    display: flex;
    min-height: 28px;
    align-items: center;
    gap: 5px;
    width: fit-content;
    max-width: 100%;
    cursor: pointer;
    color: var(--_txd-fg-1);
    font-weight: 600;
    line-height: 1.4;
    list-style: none;
  }

  .tx-datum-summary::-webkit-details-marker {
    display: none;
  }

  .tx-datum-summary:hover .tx-datum-summary-label {
    color: var(--_txd-accent-soft);
  }

  .tx-datum-summary:focus-visible {
    border-radius: var(--_txd-radius-sm);
    outline: 2px solid var(--_txd-accent);
    outline-offset: 2px;
  }

  .tx-datum-chevron {
    width: 0.875rem;
    height: 0.875rem;
    flex-shrink: 0;
    fill: none;
    stroke: var(--_txd-accent);
    stroke-width: 1.75;
    stroke-linecap: round;
    stroke-linejoin: round;
    transition: transform 160ms cubic-bezier(0.25, 1, 0.5, 1);
  }

  .tx-datum-disclosure[open] > .tx-datum-summary > .tx-datum-chevron {
    transform: rotate(90deg);
  }

  .tx-datum-summary-label {
    overflow: hidden;
    text-overflow: ellipsis;
    transition: color 160ms ease-out;
  }

  .tx-datum-children {
    margin-left: 6px;
    padding-left: 12px;
    border-left: 1px solid var(--_txd-stroke-soft);
  }

  .tx-datum-leaf {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    min-height: 26px;
    line-height: 1.5;
  }

  .tx-datum-key {
    color: var(--_txd-fg-2);
  }

  .tx-datum-key-constructor {
    color: var(--_txd-fg-1);
    font-weight: 600;
  }

  .tx-datum-sep {
    color: var(--_txd-fg-5);
    margin: 0 4px;
  }

  .tx-datum-val {
    min-width: 0;
    color: var(--_txd-fg-1);
    overflow-wrap: anywhere;
  }

  .tx-datum-empty {
    display: block;
    min-height: 26px;
    color: var(--_txd-fg-4);
    font-family: var(--_txd-font-sans);
    font-style: italic;
    line-height: 1.6;
  }

  @media (prefers-reduced-motion: reduce) {
    .tx-datum-chevron,
    .tx-datum-summary-label {
      transition: none;
    }
  }
</style>

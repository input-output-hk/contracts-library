<script lang="ts">
  import type { TransactionDiagramData } from "./schema.js";

  let {
    transaction,
    title,
    stackOnMobile = true,
    dataChainPort,
  }: {
    transaction: TransactionDiagramData;
    title: string;
    stackOnMobile?: boolean;
    dataChainPort?: string | undefined;
  } = $props();
</script>

<div
  class="tx-box"
  class:tx-stack={stackOnMobile}
  data-chain-port={dataChainPort}
  role="group"
  aria-label="Transaction behavior"
>
  <h3 class="tx-box-title">{title}</h3>

  {#if transaction.mint.length > 0}
    <div class="tx-box-section">
      <span class="tx-box-section-label">MINT</span>
      {#each transaction.mint as entry, i (i)}
        <div
          class="tx-box-entry"
          class:tx-burn={entry.amount.startsWith("-")}
          class:tx-mint-gain={!entry.amount.startsWith("-")}
        >
          {entry.amount}
          {entry.token}
        </div>
      {/each}
    </div>
  {/if}

  {#if transaction.signatures.length > 0}
    <div class="tx-box-section">
      <span class="tx-box-section-label">SIGNATURES</span>
      {#each transaction.signatures as sig, i (i)}
        <div class="tx-box-entry">• {sig}</div>
      {/each}
    </div>
  {/if}

  {#if transaction.certificates.length > 0}
    <div class="tx-box-section">
      <span class="tx-box-section-label">CERTIFICATES</span>
      {#each transaction.certificates as certificate, i (i)}
        <div class="tx-box-entry">• {certificate}</div>
      {/each}
    </div>
  {/if}

  {#if transaction.withdrawals.length > 0}
    <div class="tx-box-section">
      <span class="tx-box-section-label">WITHDRAWALS</span>
      {#each transaction.withdrawals as wd, i (i)}
        <div class="tx-box-entry">• {wd}</div>
      {/each}
    </div>
  {/if}

  {#if transaction.validRange}
    <div class="tx-box-section">
      <span class="tx-box-section-label">VALID RANGE</span>
      <div class="tx-box-entry">
        {#if transaction.validRange.lower && transaction.validRange.upper}
          {transaction.validRange.lower} ≤ slot ≤ {transaction.validRange.upper}
        {:else if transaction.validRange.lower}
          slot ≥ {transaction.validRange.lower}
        {:else if transaction.validRange.upper}
          slot ≤ {transaction.validRange.upper}
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .tx-box {
    min-width: 11rem;
    max-width: 22rem;
    border: 1px solid var(--_txd-stroke);
    border-radius: var(--_txd-radius-md);
    padding: 16px;
    background: var(--_txd-surface);
    margin: 0 16px;
  }

  @media (max-width: 767px) {
    .tx-box.tx-stack {
      margin: 12px 0;
      max-width: unset;
    }
  }

  .tx-box-title {
    font-size: var(--_txd-text-base);
    font-weight: 700;
    text-align: center;
    margin: 0 0 12px;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--_txd-stroke);
    color: var(--_txd-fg-1);
    overflow-wrap: anywhere;
    text-wrap: balance;
  }

  .tx-box-section {
    margin-bottom: 12px;
  }

  .tx-box-section:last-child {
    margin-bottom: 0;
  }

  .tx-box-section-label {
    font-size: var(--_txd-text-2xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--_txd-accent-soft);
    display: block;
    margin-bottom: 4px;
  }

  .tx-box-entry {
    font-size: var(--_txd-text-2xs);
    color: var(--_txd-fg-1);
    font-family: var(--_txd-font-mono);
    line-height: 1.6;
    overflow-wrap: anywhere;
  }

  .tx-box-entry.tx-burn {
    color: var(--_txd-primary-bright);
  }

  .tx-box-entry.tx-mint-gain {
    color: var(--_txd-success);
  }
</style>

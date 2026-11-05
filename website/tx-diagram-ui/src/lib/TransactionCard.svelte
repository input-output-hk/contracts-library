<script lang="ts">
  import type { Snippet } from "svelte";
  import TransactionBox from "./TransactionBox.svelte";
  import type { TransactionDiagramData } from "./schema.js";

  let {
    transaction,
    title,
    inputs,
    outputs,
    stackOnMobile = true,
    className = "",
    dataChainPort,
  }: {
    transaction: TransactionDiagramData;
    title: string;
    inputs: Snippet;
    outputs: Snippet;
    stackOnMobile?: boolean;
    className?: string;
    dataChainPort?: string | undefined;
  } = $props();
</script>

<div class="tx-card tx-grid {className}" class:tx-stack={stackOnMobile}>
  <div class="tx-column tx-inputs" role="group" aria-label="Transaction inputs">
    {@render inputs()}
  </div>
  <TransactionBox {transaction} {title} {stackOnMobile} {dataChainPort} />
  <div class="tx-column tx-outputs" role="group" aria-label="Transaction outputs">
    {@render outputs()}
  </div>
</div>

<style>
  .tx-card {
    display: grid;
    grid-template-columns: minmax(min-content, 1fr) auto minmax(min-content, 1fr);
    gap: 0;
    min-width: 0;
    align-items: stretch;
  }

  .tx-column {
    display: flex;
    flex-direction: column;
    gap: 12px;
    justify-content: center;
  }

  .tx-inputs {
    align-items: end;
  }

  .tx-outputs {
    align-items: start;
  }

  @media (max-width: 767px) {
    .tx-card.tx-stack {
      grid-template-columns: 1fr;
      min-width: unset;
    }

    .tx-card.tx-stack .tx-inputs,
    .tx-card.tx-stack .tx-outputs {
      align-items: stretch;
    }
  }
</style>

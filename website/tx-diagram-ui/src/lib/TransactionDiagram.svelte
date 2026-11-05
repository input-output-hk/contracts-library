<script lang="ts">
  import DiagramFrame from "./DiagramFrame.svelte";
  import NotesDisclosure from "./NotesDisclosure.svelte";
  import TransactionCard from "./TransactionCard.svelte";
  import UtxoCard from "./UtxoCard.svelte";
  import type { TransactionDiagramProps } from "./schema.js";

  let { transaction, title, element = $bindable() }: TransactionDiagramProps = $props();
</script>

<DiagramFrame bind:element ariaLabel="Transaction diagram: {title}">
  <div class="tx-diagram-scroll">
    <TransactionCard {transaction} {title}>
      {#snippet inputs()}
        {#each transaction.inputs as utxo, i (i)}
          <UtxoCard {utxo} variant="input" fallbackIndex={i + 1} hideConnectorOnMobile={true} />
        {/each}
      {/snippet}
      {#snippet outputs()}
        {#each transaction.outputs as utxo, i (i)}
          <UtxoCard {utxo} variant="output" fallbackIndex={i + 1} hideConnectorOnMobile={true} />
        {/each}
      {/snippet}
    </TransactionCard>
  </div>

  {#if transaction.notes}
    <NotesDisclosure notes={transaction.notes} />
  {/if}
</DiagramFrame>

<style>
  .tx-diagram-scroll {
    width: 100%;
    overflow-x: auto;
  }

  :global(.tx-diagram[data-png-export] .tx-diagram-scroll) {
    width: auto;
    overflow: visible;
  }

  :global(.tx-diagram[data-png-export] .tx-grid:not(.tx-chain-card)) {
    grid-template-columns: minmax(min-content, 1fr) auto minmax(min-content, 1fr);
    min-width: max-content;
  }

  :global(.tx-diagram[data-png-export] .tx-inputs) {
    align-items: end;
  }

  :global(.tx-diagram[data-png-export] .tx-outputs) {
    align-items: start;
  }

  :global(.tx-diagram[data-png-export] .tx-box) {
    margin: 0 16px;
  }

  :global(.tx-diagram[data-png-export] .tx-conn) {
    display: block;
  }
</style>

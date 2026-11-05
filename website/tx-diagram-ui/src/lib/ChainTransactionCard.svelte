<script lang="ts">
  import NotesDisclosure from "./NotesDisclosure.svelte";
  import TransactionCard from "./TransactionCard.svelte";
  import UtxoCard from "./UtxoCard.svelte";
  import { chainInputsPort, chainOutputPort, chainTransactionPort } from "./chain-ports.js";
  import type { ChainLayout } from "./chain-layout.js";
  import type { ChainTransaction, DiagramUtxo } from "./schema.js";

  let {
    transaction,
    txIndex,
    layout,
  }: { transaction: ChainTransaction; txIndex: number; layout: ChainLayout } = $props();

  function isChainedInput(input: DiagramUtxo): boolean {
    return Boolean(input.id && !input.dots && !input.reference && layout.outputById.has(input.id));
  }

  const chainedInput = $derived(transaction.inputs.find((input) => isChainedInput(input)));
  const hasChainedInput = $derived(chainedInput !== undefined);
  const extraInputs = $derived(
    transaction.inputs
      .map((input, index) => ({ input, index }))
      .filter(({ input }) => !isChainedInput(input)),
  );

  function resolveInput(input: DiagramUtxo): DiagramUtxo {
    if (!input.id) {
      return input;
    }
    const output = layout.outputById.get(input.id);
    if (!output) {
      return input;
    }
    const { redeemer: _redeemer, ...outputData } = output.output;
    return {
      ...outputData,
      name: input.name,
      ...(input.address !== undefined ? { address: input.address } : {}),
      ...(input.value !== undefined ? { value: input.value } : {}),
      ...(input.datum !== undefined ? { datum: input.datum } : {}),
      ...(input.redeemer !== undefined ? { redeemer: input.redeemer } : {}),
      reference: input.reference === true,
      dots: input.dots === true,
    };
  }

  function isConsumedOutput(output: DiagramUtxo): boolean {
    return Boolean(output.id && layout.consumed.has(output.id));
  }
</script>

<div class="tx-chain-card-wrap" data-chain-card={txIndex}>
  <TransactionCard
    {transaction}
    title={transaction.title}
    stackOnMobile={false}
    className={`tx-chain-card${extraInputs.length > 0 ? " tx-chain-has-extra" : ""}`}
    dataChainPort={hasChainedInput ? chainTransactionPort(txIndex) : undefined}
  >
    {#snippet inputs()}
      {#if chainedInput}
        <div class="tx-chain-input-spacer">
          <span class="tx-sr-only">
            {chainedInput.redeemer
              ? `Redeemer ${chainedInput.redeemer} on ${chainedInput.name || "input"}`
              : `Input ${chainedInput.name || "input"}`}
          </span>
        </div>
      {/if}
      {#if extraInputs.length > 0}
        <div class="tx-chain-extra-inputs" data-chain-port={chainInputsPort(txIndex)}>
          {#each extraInputs as { input, index } (index)}
            <UtxoCard utxo={resolveInput(input)} variant="input" fallbackIndex={index + 1} />
          {/each}
        </div>
      {/if}
    {/snippet}
    {#snippet outputs()}
      {#each transaction.outputs as output, i (i)}
        <UtxoCard
          utxo={output}
          variant="output"
          fallbackIndex={i + 1}
          dataChainPort={isConsumedOutput(output) ? chainOutputPort(txIndex, i) : undefined}
        />
      {/each}
    {/snippet}
  </TransactionCard>

  {#if transaction.notes}
    <NotesDisclosure notes={transaction.notes} inline />
  {/if}
</div>

<style>
  .tx-chain-card-wrap {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  /* The shared TransactionCard grid gives both UTxO columns `1fr`, which leaves
     a large empty gutter around the chain edge. In a chain the surrounding
     columns only need to fit their actual content. */
  .tx-chain-card-wrap :global(.tx-chain-card) {
    grid-template-columns: max-content auto max-content;
  }

  /* Cards with reference or other extra inputs need a clear corridor below
     them so the incoming edge can reach the transaction box without crossing
     a UTxO card. */
  .tx-chain-card-wrap :global(.tx-chain-has-extra .tx-inputs) {
    padding-bottom: 24px;
  }

  /* A chained input has no card of its own: the edge from the producer carries
     it. The spacer keeps the other inputs clear of the edge's horizontal run
     and keeps the grid's height stable. */
  .tx-chain-input-spacer {
    width: 0;
    height: 1.4rem;
  }

  .tx-chain-extra-inputs {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .tx-sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
</style>

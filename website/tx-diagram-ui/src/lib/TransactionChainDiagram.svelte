<script module lang="ts">
  let chainId = 0;
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import ChainTransactionCard from "./ChainTransactionCard.svelte";
  import DiagramFrame from "./DiagramFrame.svelte";
  import NotesDisclosure from "./NotesDisclosure.svelte";
  import {
    CHAIN_LANE_HEIGHT,
    CHAIN_LANE_TOP,
    chainLaneY,
    computeChainEdgeGeometry,
  } from "./chain-edge-geometry.js";
  import {
    chainCardSelector,
    chainInputsPort,
    chainOutputPort,
    chainPortSelector,
    chainTransactionPort,
  } from "./chain-ports.js";
  import { computeChainLayout, needsChainLane } from "./chain-layout.js";
  import type { TransactionChainProps } from "./schema.js";

  type EdgePath = { id: string; d: string };
  type EdgeLabel = { id: string; text: string; x: number; y: number };

  let { chain, title, element = $bindable() }: TransactionChainProps = $props();

  const layout = $derived(computeChainLayout(chain));
  const laneCount = $derived(
    layout.edges.filter((edge) => needsChainLane(edge, layout.columnByIndex)).length,
  );
  const topPadding = $derived(
    laneCount === 0 ? 12 : CHAIN_LANE_TOP + (laneCount - 1) * CHAIN_LANE_HEIGHT + 8,
  );

  let content = $state<HTMLDivElement>();
  let markerId = $state("");
  let paths = $state<EdgePath[]>([]);
  let labels = $state<EdgeLabel[]>([]);
  let frame = 0;

  onMount(() => {
    chainId += 1;
    markerId = `tx-chain-arrow-${chainId}`;
  });

  function scheduleMeasure() {
    if (!content) {
      return;
    }
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      frame = 0;
      measure();
    });
  }

  function measure() {
    if (!content) {
      return;
    }

    const contentRect = content.getBoundingClientRect();
    let laneIndex = 0;
    const nextPaths: EdgePath[] = [];
    const nextLabels: EdgeLabel[] = [];

    for (const edge of layout.edges) {
      const from = content.querySelector<HTMLElement>(
        chainPortSelector(chainOutputPort(edge.fromTxIndex, edge.fromOutputIndex)),
      );
      const to = content.querySelector<HTMLElement>(
        chainPortSelector(chainTransactionPort(edge.toTxIndex)),
      );
      if (!from || !to) {
        continue;
      }

      const fromRect = from.getBoundingClientRect();
      const toRect = to.getBoundingClientRect();
      const startX = fromRect.right - contentRect.left;
      const startY = fromRect.top + fromRect.height / 2 - contentRect.top;
      const endX = toRect.left - contentRect.left;
      const producerCard = content.querySelector<HTMLElement>(chainCardSelector(edge.fromTxIndex));
      const riseX = producerCard
        ? producerCard.getBoundingClientRect().right - contentRect.left + 8
        : startX + 8;
      const card = content.querySelector<HTMLElement>(chainCardSelector(edge.toTxIndex));
      const entryX = card ? card.getBoundingClientRect().left - contentRect.left - 4 : endX;
      const boxTop = toRect.top - contentRect.top;
      const boxBottom = toRect.bottom - contentRect.top;
      const boxCenter = boxTop + toRect.height / 2;
      // Aim the edge at the producer's height so it reads as one straight line.
      // Clamp into the consumer box when the box is shorter than that.
      const minY = boxTop + 8;
      const maxY = boxBottom - 8;
      let endY = minY <= maxY ? Math.min(Math.max(startY, minY), maxY) : boxCenter;

      // Other inputs (reference inputs, ordinary inputs) sit in the consumer's
      // input column, in the edge's path. Route around them when the producer
      // height would cross them.
      const extraInputs = content.querySelector<HTMLElement>(
        chainPortSelector(chainInputsPort(edge.toTxIndex)),
      );
      if (extraInputs) {
        const extraRect = extraInputs.getBoundingClientRect();
        const extraTop = extraRect.top - contentRect.top;
        const extraBottom = extraRect.bottom - contentRect.top;
        const clearance = 8;
        if (startY > extraTop - clearance && startY < extraBottom + clearance) {
          const above = extraTop - clearance;
          const below = extraBottom + clearance;
          const aboveFits = above >= minY && above <= maxY;
          const belowFits = below >= minY && below <= maxY;
          if (belowFits && (!aboveFits || startY >= (extraTop + extraBottom) / 2)) {
            endY = below;
          } else if (aboveFits) {
            endY = above;
          }
        }
      }
      const needsLane = needsChainLane(edge, layout.columnByIndex);
      const laneY = needsLane ? chainLaneY(laneIndex) : null;
      if (needsLane) {
        laneIndex += 1;
      }

      const id = `${edge.fromTxIndex}-${edge.fromOutputIndex}-${edge.toTxIndex}-${edge.toInputIndex}`;
      const geometry = computeChainEdgeGeometry(startX, startY, riseX, entryX, endX, endY, laneY);
      nextPaths.push({ id, d: geometry.d });

      if (edge.redeemer) {
        nextLabels.push({
          id: `${id}-label`,
          text: edge.redeemer,
          x: geometry.label.x,
          y: geometry.label.y,
        });
      }
    }

    paths = nextPaths;
    labels = nextLabels;
  }

  $effect(() => {
    const { edges, columns } = layout;
    if (!content) {
      return;
    }
    if (edges.length === 0 && columns.length === 0) {
      paths = [];
      labels = [];
      return;
    }

    scheduleMeasure();
    const observer = new ResizeObserver(scheduleMeasure);
    observer.observe(content);
    void document.fonts.ready.then(scheduleMeasure);

    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  });
</script>

<DiagramFrame bind:element ariaLabel="Transaction chain: {title}" className="tx-chain">
  <div class="tx-chain-scroll">
    <div
      class="tx-chain-content"
      bind:this={content}
      style={`--tx-chain-top-padding: ${topPadding}px`}
    >
      <h2 class="tx-chain-title">{title}</h2>

      <div class="tx-chain-columns">
        {#each layout.columns as column, columnIndex (columnIndex)}
          <div class="tx-chain-column">
            <div class="tx-chain-block-label">{column.label}</div>
            {#each column.transactions as placed (placed.index)}
              <ChainTransactionCard
                transaction={placed.transaction}
                txIndex={placed.index}
                {layout}
              />
            {/each}
          </div>
        {/each}
      </div>

      {#if paths.length > 0 && markerId}
        <svg class="tx-chain-edges" aria-hidden="true" style="color: var(--_txd-primary)">
          <defs>
            <marker
              id={markerId}
              viewBox="0 0 6 6"
              refX="5"
              refY="3"
              markerWidth="6"
              markerHeight="6"
              orient="auto-start-reverse"
            >
              <path d="M 0 0 L 6 3 L 0 6 z" fill="currentColor" />
            </marker>
          </defs>
          {#each paths as path (path.id)}
            <path
              class="tx-chain-edge"
              d={path.d}
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linejoin="round"
              stroke-linecap="round"
              marker-end={`url(#${markerId})`}
            />
          {/each}
        </svg>
      {/if}

      {#if labels.length > 0}
        <div class="tx-chain-labels" aria-hidden="true">
          {#each labels as label (label.id)}
            <span
              class="tx-chain-edge-label"
              style={`left: ${label.x}px; top: ${label.y}px`}
              title={label.text}
            >
              <span class="tx-chain-edge-label-glyph">▸</span>{label.text}
            </span>
          {/each}
        </div>
      {/if}
    </div>
  </div>

  {#if chain.notes}
    <NotesDisclosure notes={chain.notes} />
  {/if}
</DiagramFrame>

<style>
  .tx-chain-scroll {
    width: 100%;
    overflow-x: auto;
  }

  .tx-chain-content {
    position: relative;
    box-sizing: border-box;
    width: max-content;
    min-width: 100%;
    padding: var(--tx-chain-top-padding, 12px) 12px 24px;
  }

  .tx-chain-title {
    margin: 0 0 12px;
    font-size: var(--_txd-text-base);
    font-weight: 700;
    color: var(--_txd-fg-1);
    overflow-wrap: anywhere;
  }

  .tx-chain-columns {
    display: flex;
    align-items: flex-start;
    /* The gutter between a producer's Output card and the next transaction box
       carries the chain edge and its redeemer tag. */
    gap: 148px;
  }

  .tx-chain-column {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
  }

  .tx-chain-block-label {
    font-size: var(--_txd-text-2xs);
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--_txd-fg-3);
  }

  .tx-chain-edges {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
    color: var(--_txd-primary);
  }

  .tx-chain-edge {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linejoin: round;
    stroke-linecap: round;
  }

  .tx-chain-labels {
    position: absolute;
    inset: 0;
    z-index: 1;
    pointer-events: none;
  }

  /* The redeemer rides above the edge instead of interrupting it. */
  .tx-chain-edge-label {
    position: absolute;
    box-sizing: border-box;
    max-width: 140px;
    overflow: hidden;
    pointer-events: auto;
    transform: translate(-50%, -100%);
    padding: 2px 7px;
    border: 1px solid color-mix(in oklch, var(--_txd-primary) 40%, transparent);
    border-radius: var(--_txd-radius-sm);
    background: color-mix(in oklch, var(--_txd-primary) 20%, var(--_txd-surface));
    color: var(--_txd-fg-1);
    font-family: var(--_txd-font-sans);
    font-size: var(--_txd-text-2xs);
    font-weight: 600;
    line-height: 1.4;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .tx-chain-edge-label-glyph {
    margin-right: 3px;
    color: var(--_txd-primary-deep);
    font-size: 0.75em;
  }

  :global(.tx-diagram[data-png-export] .tx-chain-scroll) {
    width: auto;
    overflow: visible;
  }

  :global(.tx-diagram[data-png-export] .tx-chain-content) {
    width: max-content;
    min-width: max-content;
  }
</style>

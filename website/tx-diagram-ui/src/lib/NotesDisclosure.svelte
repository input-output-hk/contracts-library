<script lang="ts">
  let { notes, inline = false }: { notes: string; inline?: boolean } = $props();
</script>

<svelte:element
  this={inline ? "div" : "figcaption"}
  class="tx-diagram-caption"
  class:tx-notes-inline={inline}
>
  <details class="tx-notes" open>
    <summary class="tx-notes-summary">
      <svg class="tx-chevron" viewBox="0 0 16 16" aria-hidden="true"
        ><path d="M6 3.5 10.5 8 6 12.5" /></svg
      >
      <span>Notes</span>
    </summary>
    <div class="tx-diagram-caption-body">{notes}</div>
  </details>
</svelte:element>

<style>
  .tx-diagram-caption {
    box-sizing: border-box;
    width: 100%;
    margin: 16px 0 0;
    padding: 12px 14px;
    border: 1px solid var(--_txd-stroke);
    border-radius: var(--_txd-radius-md);
    background: var(--_txd-surface);
    color: var(--_txd-fg-2);
    font-size: var(--_txd-text-xs);
    line-height: 1.5;
  }

  .tx-diagram-caption.tx-notes-inline {
    margin: 0;
    padding: 0 12px;
    border: 0;
    background: transparent;
    font-size: var(--_txd-text-2xs);
  }

  @media (min-width: 768px) {
    .tx-diagram-caption:not(.tx-notes-inline):has(.tx-notes[open]) {
      position: sticky;
      bottom: max(16px, env(safe-area-inset-bottom));
      z-index: 2;
      max-height: min(14rem, 33vh);
      overflow: hidden;
    }

    .tx-diagram-caption:not(.tx-notes-inline) .tx-notes[open] {
      display: flex;
      flex-direction: column;
      max-height: calc(min(14rem, 33vh) - 26px);
    }
  }

  .tx-notes-summary {
    display: flex;
    width: fit-content;
    min-height: 28px;
    align-items: center;
    gap: 5px;
    cursor: pointer;
    list-style: none;
    color: var(--_txd-accent-soft);
    font-size: var(--_txd-text-2xs);
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .tx-notes-summary::-webkit-details-marker {
    display: none;
  }

  .tx-notes-summary:focus-visible {
    border-radius: var(--_txd-radius-sm);
    outline: 2px solid var(--_txd-accent);
    outline-offset: 2px;
  }

  .tx-chevron {
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

  .tx-notes[open] > .tx-notes-summary > .tx-chevron {
    transform: rotate(90deg);
  }

  .tx-diagram-caption-body {
    min-height: 0;
    margin-top: 6px;
    overflow-y: auto;
    overscroll-behavior: contain;
    white-space: pre-wrap;
    word-break: break-word;
  }

  @media (prefers-reduced-motion: reduce) {
    .tx-chevron {
      transition: none;
    }
  }

  :global(
    .tx-diagram[data-png-export] .tx-diagram-caption:not(.tx-notes-inline):has(.tx-notes[open])
  ) {
    position: static;
    box-sizing: border-box;
    width: 720px;
    max-width: 100%;
    margin-right: auto;
    margin-left: auto;
    max-height: none;
    overflow: visible;
  }

  :global(.tx-diagram[data-png-export] .tx-notes[open]) {
    max-height: none;
  }

  :global(.tx-diagram[data-png-export] .tx-diagram-caption-body) {
    overflow: visible;
  }
</style>

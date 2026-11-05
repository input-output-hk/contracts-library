<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    ariaLabel,
    className = "",
    element = $bindable(),
    children,
  }: {
    ariaLabel: string;
    className?: string;
    element?: HTMLElement | undefined;
    children: Snippet;
  } = $props();
</script>

<figure bind:this={element} class="tx-diagram {className}" aria-label={ariaLabel}>
  {@render children()}
</figure>

<style>
  .tx-diagram {
    --_txd-surface: var(--tx-diagram-surface, oklch(99% 0 0));
    --_txd-surface-sunken: var(--tx-diagram-surface-sunken, oklch(96% 0 0));
    --_txd-fg-1: var(--tx-diagram-fg-1, oklch(22% 0 0));
    --_txd-fg-2: var(--tx-diagram-fg-2, oklch(38% 0 0));
    --_txd-fg-3: var(--tx-diagram-fg-3, oklch(50% 0 0));
    --_txd-fg-4: var(--tx-diagram-fg-4, oklch(58% 0 0));
    --_txd-fg-5: var(--tx-diagram-fg-5, oklch(68% 0 0));
    --_txd-primary: var(--tx-diagram-primary, oklch(45% 0.015 260));
    --_txd-primary-bright: var(--tx-diagram-primary-bright, oklch(56% 0.18 25));
    --_txd-primary-deep: var(--tx-diagram-primary-deep, oklch(36% 0.015 260));
    --_txd-accent: var(--tx-diagram-accent, oklch(54% 0.12 240));
    --_txd-accent-soft: var(--tx-diagram-accent-soft, oklch(44% 0.1 240));
    --_txd-success: var(--tx-diagram-success, oklch(50% 0.12 160));
    --_txd-stroke: var(--tx-diagram-stroke, oklch(0% 0 0 / 16%));
    --_txd-stroke-soft: var(--tx-diagram-stroke-soft, oklch(0% 0 0 / 8%));
    --_txd-font-sans: var(--tx-diagram-font-sans, ui-sans-serif, system-ui, sans-serif);
    --_txd-font-mono: var(--tx-diagram-font-mono, ui-monospace, SFMono-Regular, Menlo, monospace);
    --_txd-text-2xs: var(--tx-diagram-text-2xs, 0.6875rem);
    --_txd-text-xs: var(--tx-diagram-text-xs, 0.8125rem);
    --_txd-text-base: var(--tx-diagram-text-base, 1rem);
    --_txd-text-xl: var(--tx-diagram-text-xl, 1.44rem);
    --_txd-radius-sm: var(--tx-diagram-radius-sm, 4px);
    --_txd-radius-md: var(--tx-diagram-radius-md, 8px);
    --_txd-export-background: var(--tx-diagram-export-background, oklch(100% 0 0));
    position: relative;
    isolation: isolate;
    width: 100%;
  }

  :global(.tx-diagram[data-png-export]) {
    width: max-content;
    min-width: 960px;
    padding: 24px;
    background: var(--_txd-export-background);
  }
</style>

/**
 * Pure geometry for a single chain edge. Kept out of the Svelte component so
 * the routing and the redeemer-tag anchor can be tested without a DOM.
 */
export type ChainEdgeLabelAnchor = {
  /** Horizontal centre of the label, in content coordinates. */
  x: number;
  /** Bottom edge of the label, in content coordinates. */
  y: number;
};

export type ChainEdgeGeometry = {
  /** SVG path for the edge, from the producer output to the consumer box. */
  d: string;
  /** Where the redeemer tag sits, or null when the edge has no redeemer. */
  label: ChainEdgeLabelAnchor;
};

/** Top lane reserved for edges that skip a column or run inside one column. */
export const CHAIN_LANE_TOP = 36;
/** Must stay taller than the redeemer tag so consecutive lanes cannot overlap. */
export const CHAIN_LANE_HEIGHT = 36;
/** Gap between a horizontal run and the bottom of its label. */
const LABEL_GAP = 6;

export function chainLaneY(laneIndex: number): number {
  return CHAIN_LANE_TOP + laneIndex * CHAIN_LANE_HEIGHT;
}

/**
 * @param startX  Right edge of the producer Output card.
 * @param startY  Vertical centre of the producer Output card.
 * @param riseX   Right edge of the producer card/column, where a lane rises.
 * @param entryX  Left edge of the consumer card, where the edge turns.
 * @param endX    Left edge of the consumer transaction box.
 * @param endY    Height at which the edge enters the transaction box.
 * @param laneY   Top lane for non-adjacent edges, or null for adjacent ones.
 */
export function computeChainEdgeGeometry(
  startX: number,
  startY: number,
  riseX: number,
  entryX: number,
  endX: number,
  endY: number,
  laneY: number | null,
): ChainEdgeGeometry {
  const labelX = (riseX + entryX) / 2;

  if (laneY !== null) {
    return {
      d: `M ${startX} ${startY} H ${riseX} V ${laneY} H ${entryX - 8} V ${endY} H ${endX}`,
      label: { x: labelX, y: laneY - 4 },
    };
  }

  if (Math.abs(endY - startY) < 0.5) {
    return {
      d: `M ${startX} ${startY} H ${endX}`,
      label: { x: labelX, y: startY - LABEL_GAP },
    };
  }

  return {
    d: `M ${startX} ${startY} H ${entryX} V ${endY} H ${endX}`,
    label: { x: labelX, y: startY - LABEL_GAP },
  };
}

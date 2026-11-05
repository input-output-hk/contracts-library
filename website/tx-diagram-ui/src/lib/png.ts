export type TransactionDiagramPngOptions = {
  backgroundColor?: string;
  pixelRatio?: number;
};

const themeProperties = [
  "--tx-diagram-surface",
  "--tx-diagram-surface-sunken",
  "--tx-diagram-fg-1",
  "--tx-diagram-fg-2",
  "--tx-diagram-fg-3",
  "--tx-diagram-fg-4",
  "--tx-diagram-fg-5",
  "--tx-diagram-primary",
  "--tx-diagram-primary-bright",
  "--tx-diagram-primary-deep",
  "--tx-diagram-accent",
  "--tx-diagram-accent-soft",
  "--tx-diagram-success",
  "--tx-diagram-stroke",
  "--tx-diagram-stroke-soft",
  "--tx-diagram-font-sans",
  "--tx-diagram-font-mono",
  "--tx-diagram-text-2xs",
  "--tx-diagram-text-xs",
  "--tx-diagram-text-base",
  "--tx-diagram-text-xl",
  "--tx-diagram-radius-sm",
  "--tx-diagram-radius-md",
  "--tx-diagram-export-background",
] as const;

function waitForPaint(): Promise<void> {
  return new Promise((resolve) => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        resolve();
      });
    });
  });
}

function copyTheme(source: HTMLElement, target: HTMLElement): CSSStyleDeclaration {
  const computedStyle = getComputedStyle(source);
  for (const property of themeProperties) {
    const value = computedStyle.getPropertyValue(property);
    if (value) {
      target.style.setProperty(property, value);
    }
  }
  return computedStyle;
}

export async function transactionDiagramToPng(
  element: HTMLElement,
  options: TransactionDiagramPngOptions = {},
): Promise<Blob> {
  if (typeof document === "undefined" || typeof window === "undefined") {
    throw new Error("Transaction diagrams can only be exported in a browser.");
  }

  const cloneNode = element.cloneNode(true);
  if (!(cloneNode instanceof HTMLElement)) {
    throw new Error("The transaction diagram could not be prepared for export.");
  }

  const computedStyle = copyTheme(element, cloneNode);
  const themeBackground = computedStyle.getPropertyValue("--tx-diagram-export-background").trim();
  const backgroundColor = options.backgroundColor ?? (themeBackground || "#ffffff");

  cloneNode.dataset.pngExport = "";
  cloneNode.setAttribute("aria-hidden", "true");

  for (const notes of cloneNode.querySelectorAll(".tx-notes")) {
    if (notes instanceof HTMLDetailsElement && !notes.open) {
      notes.closest(".tx-diagram-caption")?.remove();
    }
  }

  const stagingArea = document.createElement("div");
  stagingArea.style.position = "fixed";
  stagingArea.style.inset = "0 auto auto -100000px";
  stagingArea.style.zIndex = "-1";
  stagingArea.style.pointerEvents = "none";
  stagingArea.append(cloneNode);
  document.body.append(stagingArea);

  try {
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
    await document.fonts?.ready;
    await waitForPaint();

    const { toBlob } = await import("html-to-image");
    const renderOptions = {
      backgroundColor: backgroundColor || "#ffffff",
      pixelRatio: options.pixelRatio ?? 2,
      width: cloneNode.scrollWidth,
      height: cloneNode.scrollHeight,
    };
    const blob = await toBlob(cloneNode, renderOptions);
    if (!blob) {
      throw new Error("The transaction diagram could not be rendered as a PNG.");
    }
    return blob;
  } finally {
    stagingArea.remove();
  }
}

export async function copyTransactionDiagramPng(
  element: HTMLElement,
  options: TransactionDiagramPngOptions = {},
): Promise<void> {
  if (typeof window === "undefined") {
    throw new Error("Transaction diagrams can only be copied in a browser.");
  }
  if (!window.isSecureContext) {
    throw new Error("Copying images requires a secure connection.");
  }
  // Runtime feature detection; DOM typings declare these as always present.
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  if (!("ClipboardItem" in window) || !navigator.clipboard?.write) {
    throw new Error("This browser does not support copying PNG images.");
  }
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  if (ClipboardItem.supports && !ClipboardItem.supports("image/png")) {
    throw new Error("This browser cannot write PNG images to the clipboard.");
  }

  const png = transactionDiagramToPng(element, options);
  const clipboardItem = new ClipboardItem({ "image/png": png });
  await navigator.clipboard.write([clipboardItem]);
}

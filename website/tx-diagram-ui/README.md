# tx-diagram-ui (vendored)

Snapshot of the private `tx-diagram-ui` package (`packages/tx-diagram`), taken
from commit `08d76f9` (`feat/tx-diagram: add transaction chains`). It is
vendored because the package is not published to npm.

The website imports it by name:

```ts
import { TransactionDiagram, TransactionDiagramSchema } from "tx-diagram-ui";
```

Replacing this directory with a published release later only requires changing
the dependency in `../package.json` and deleting this directory.

Licensed under Apache-2.0; see [`LICENSE`](LICENSE). The upstream package's
`*.test.ts` files are not included because the website build does not run them.

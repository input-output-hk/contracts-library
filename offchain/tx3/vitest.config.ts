import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // trix's devnet binds fixed ports (TRP 8164, minibf 3164), so two
    // suites can't boot devnets concurrently: run files in sequence.
    fileParallelism: false,
  },
});

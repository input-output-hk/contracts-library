import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Devnet round-trips (submit + confirm + waiting for schedule times) are slow.
    testTimeout: 180_000,
    hookTimeout: 120_000,
    fileParallelism: false,
    pool: "forks",
    // Vitest 4: `poolOptions.forks.singleFork` became `maxWorkers` + `isolate`.
    maxWorkers: 1,
    isolate: false,
  },
});

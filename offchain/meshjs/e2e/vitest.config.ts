import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Devnet round-trips (submit + confirm + waiting for schedule times) are slow.
    testTimeout: 180_000,
    hookTimeout: 120_000,
    // One devnet, shared state: run serially.
    fileParallelism: false,
    pool: "forks",
    poolOptions: { forks: { singleFork: true } },
  },
});

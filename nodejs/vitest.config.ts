import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    // The harness under scripts/ is plain ESM and is not part of the published
    // build, so its tests are .mjs — a .ts test importing an untyped .mjs would
    // only fail `tsc --noEmit`, which does not look at scripts/ at all.
    include: ['test/**/*.test.ts', 'test/**/*.test.mjs'],
    coverage: {
      include: ['src/**/*.ts'],
      exclude: ['src/index.ts'],
    },
  },
});

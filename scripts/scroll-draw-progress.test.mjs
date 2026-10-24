import assert from "node:assert/strict"
import { scrollDrawProgress } from "./scroll-draw-progress.mjs"

assert.equal(scrollDrawProgress(900, 1000), 0)
assert.equal(scrollDrawProgress(860, 1000), 0)
assert.equal(scrollDrawProgress(580, 1000), 0.5)
assert.equal(scrollDrawProgress(300, 1000), 1)
assert.equal(scrollDrawProgress(-100, 1000), 1)

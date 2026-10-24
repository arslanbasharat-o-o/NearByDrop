/** @param {number} top @param {number} viewport */
export function scrollDrawProgress(top, viewport) {
  return Math.max(0, Math.min(1, (viewport * 0.86 - top) / (viewport * 0.56)))
}

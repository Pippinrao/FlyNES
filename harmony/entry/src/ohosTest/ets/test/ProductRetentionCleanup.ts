/** Test-only cleanup; all independent restorations must get their own attempt. */
export async function retentionCleanup(steps: Array<() => Promise<void>>): Promise<string[]> {
  const errors: string[] = [];
  for (const step of steps) {
    try { await step(); }
    catch (error) { errors.push(error instanceof Error ? error.message : String(error)); }
  }
  return errors;
}

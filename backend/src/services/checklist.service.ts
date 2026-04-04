// Integration with sports card checklist databases (e.g. TCDB, Beckett)
// Used to standardize card naming and numbering during collection add flow

export async function lookupCard(query: string): Promise<object[]> {
  // TODO: Implement checklist provider API call
  console.log(`Looking up checklist for: ${query}`);
  return [];
}

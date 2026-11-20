export function csvCell(value: string): string {
  // Quoting alone does not stop spreadsheets from evaluating formulas.
  const safe = /^[\s]*[=+@-]/.test(value) ? `'${value}` : value;
  return `"${safe.replaceAll('"', '""')}"`;
}

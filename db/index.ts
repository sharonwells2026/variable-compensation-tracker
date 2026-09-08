// Legacy database adapter retained only for compatibility with earlier template code.
// The compensation tracker uses Supabase as its authoritative datastore.
// Do not introduce Cloudflare D1 bindings into the Netlify/Next.js application.

export function getDb(): never {
  throw new Error(
    "Cloudflare D1 is not configured for this application. Use the Supabase data layer instead."
  );
}

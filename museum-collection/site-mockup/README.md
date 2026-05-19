# Museum Collection Site Mockup

Static public catalog prototype notes.

The generated/public HTML and catalog JSON are intentionally not committed in this first sanitized GitHub publish because they embed full catalog data and runtime configuration. Keep template work source-controlled only after Supabase URL/key handling is parameterized and generated data is separated from source.

Expected local workflow:

1. Keep source data outside Git.
2. Run `museum-collection/scripts/build_catalog.py` from the full local workspace.
3. Publish generated output through the deployment pipeline, not through this source repo.

# Third-Party Notices

This package bundles a copy of the following third-party software for use by the
`--offline` HTML export flag, so the generated report can render without any
outbound network requests (e.g. on air-gapped CI runners).

## vis-network

- **Version bundled:** 10.1.0 (standalone UMD, minified build)
- **Location in this package:** `lib/src/assets/vis_network_asset.dart` (base64-encoded)
- **Homepage:** https://visjs.github.io/vis-network/
- **Source:** https://github.com/visjs/vis-network
- **License:** Dual-licensed under the Apache License 2.0 and the MIT License. See the
  upstream repository for full license text.

vis-network is used only to render the interactive dependency graph in the HTML report
(`-f html`). It is loaded from `unpkg.com` by default, and inlined from the bundled copy
above only when `--offline` is passed.

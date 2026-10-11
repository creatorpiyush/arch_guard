# Reports: HTML, Mermaid, DOT, JSON, SARIF, Markdown

Every format, written for the [cycles](../cycles/README.md) case:

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/cycles -f all -o build/reports
```

| File | Format | Use it for |
| :--- | :--- | :--- |
| `dependency_graph.html` | `-f html` | Exploring the graph in a browser. Add `--offline` to inline every asset. |
| `dependency_graph.mmd` | `-f mermaid` | Diagrams in GitHub or GitLab Markdown. |
| `dependency_graph.dot` | `-f dot` | Graphviz: `dot -Tsvg build/reports/dependency_graph.dot > graph.svg`. |
| `dependency_graph.json` | `-f json` | Scripts and dashboards; cycles carry `scc.suggestedBreak`. |
| `arch_guard.sarif` | `-f sarif` | GitHub Code Scanning; results point at the import line. |
| `arch_guard_report.md` | `-f markdown` | PR comments and CI job summaries. |

`-f` can be repeated (`-f sarif -f markdown`). By default the graphs show only the cycles and the files next to them. Use `--scope all` for the full graph.

The Markdown report for this case begins:

```markdown
## arch_guard report

❌ **Architecture problems found.**

| | Total | New |
| :--- | ---: | ---: |
| Circular dependency groups | 2 | 2 |
| Layer violations | 0 | 0 |
| Forbidden package imports | 0 | 0 |
| Groups over `max_scc_size` (2) | 2 | 2 |
| Files scanned | 6 | |

### New circular dependencies

- **Cycle 1** (3 files): `lib/account/settings.dart` → `lib/account/profile.dart` → `lib/account/settings.dart` Suggested fix: remove `lib/account/profile.dart:1` → `lib/account/settings.dart` (shrinks it to 2 files).
- **Cycle 2** (3 files): `lib/shop/cart.dart` → `lib/shop/checkout.dart` → `lib/shop/cart.dart` Suggested fix: remove `lib/shop/cart.dart:1` → `lib/shop/checkout.dart`.
```

Learn more: [Output formats](https://creatorpiyush.github.io/arch_guard/cli.html#output-formats) · [GitHub Action](https://creatorpiyush.github.io/arch_guard/ci.html#github-action)

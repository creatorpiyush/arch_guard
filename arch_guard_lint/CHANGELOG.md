## 0.3.0

- **`layer_violation` follows barrels.** Importing a file in no layer that re-exports another layer is now reported on the import, with `(via lib/exports.dart)` in the message, as the CLI does.
- **`layer_violation` checks `part` directives.** A library whose `part` file lies in another layer is now reported, as the CLI already did.
- Requires `arch_guard` ^1.10.0.

## 0.2.0

- **New: quick fixes.**
  - *Remove this import* on every warning. For a conditional import, only the `if (…) '…'` clause is removed.
  - *Allow layer X to import Y* on `layer_violation`: adds the layer to `allowed_imports` in the file the config came from. This covers `arch_guard.yaml`, the `pubspec.yaml` section and legacy `dep_graph.yaml`. For a preset layer, it writes an override that keeps the preset's list.
- **New: `circular_dependency`.** A warning on the one import whose removal breaks (or shrinks most) each cycle among the files in the package's `lib/`, with a quick fix to remove it.
  - Cycles in the baseline stay quiet.
  - It works without an `arch_guard.yaml`.
  - Turn it off with `diagnostics: circular_dependency: false`.
- Requires `arch_guard` ^1.8.0.

## 0.1.2

- **Conditional imports:** `layer_violation` now also checks the URIs in conditional imports and exports (`import 'a.dart' if (dart.library.io) 'b.dart'`), as `forbidden_package` already did.
- **Legacy config:** editing a legacy `dep_graph.yaml` now takes effect without restarting the analysis server.
- **Development:** the `analyzer_testing` dev dependency floor is raised to 0.1.7, the first version the tests compile with. CI now analyses with the lowest allowed dependencies.

# 0.1.1

- Add an example (`example/README.md`) and library documentation.

# 0.1.0

- First release: `layer_violation` and `forbidden_package` warnings from `arch_guard.yaml`, in the IDE and `dart analyze`. Honours `arch_guard_baseline.json`.

## 0.1.2

- **Conditional imports:** `layer_violation` now also checks the URIs in conditional imports and exports (`import 'a.dart' if (dart.library.io) 'b.dart'`), as `forbidden_package` already did.
- **Legacy config:** editing a legacy `dep_graph.yaml` now takes effect without restarting the analysis server.
- **Development:** the `analyzer_testing` dev dependency floor is raised to 0.1.7, the first version the tests compile with. CI now analyses with the lowest allowed dependencies.

# 0.1.1

- Add an example (`example/README.md`) and library documentation.

# 0.1.0

- First release: `layer_violation` and `forbidden_package` warnings from `arch_guard.yaml`, in the IDE and `dart analyze`. Honours `arch_guard_baseline.json`.

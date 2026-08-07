/// Version of the compiled-content format produced by `ContentBuild` and
/// consumed by the app. Bumped when `graph.json`'s shape changes.
///
/// Deliberately not named `GraphCore`: a type sharing its module's name shadows
/// the module, which makes `GraphCore.Node` unresolvable from a target that also
/// imports Yams (which exports its own `Node`).
public enum ContentFormat {
    public static let version = 1
}

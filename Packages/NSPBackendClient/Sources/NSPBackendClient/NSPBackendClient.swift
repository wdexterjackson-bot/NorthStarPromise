#if !LOCAL_ONLY
    /// Marker type confirming the NSPBackendClient module target compiles and links.
    ///
    /// Real domain logic lands ticket by ticket per docs/09-BACKLOG.md; this file
    /// is replaced incrementally, never deleted wholesale.
    public enum NSPBackendClientModule {
        public static let name = "NSPBackendClient"
    }
#endif

// Everything above is compiled out entirely under `-DLOCAL_ONLY` (NSP-017,
// docs/01 §4, docs/06 §7 POL-004): the `LocalOnly` build configuration
// proves the local path has no cloud dependency by making a stray reference
// to this module a compile error, not a runtime check. `make test
// LOCAL_ONLY=1` builds and runs every package with that flag set.

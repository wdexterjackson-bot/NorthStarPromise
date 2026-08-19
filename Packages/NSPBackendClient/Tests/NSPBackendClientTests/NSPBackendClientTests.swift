import Testing

@testable import NSPBackendClient

#if !LOCAL_ONLY
    @Suite("NSPBackendClient module")
    struct NSPBackendClientTests {
        @Test func test_module_name_matchesPackage() {
            #expect(NSPBackendClientModule.name == "NSPBackendClient")
        }
    }
#else
    /// Under `-DLOCAL_ONLY` the module exposes nothing — this suite existing
    /// and compiling at all *is* the proof (NSP-017): if it still referenced
    /// `NSPBackendClientModule` here, the build would fail.
    @Suite("NSPBackendClient module — LocalOnly")
    struct NSPBackendClientLocalOnlyTests {
        @Test func test_moduleCompilesToEmptyUnderLocalOnly() {
            #expect(Bool(true))
        }
    }
#endif

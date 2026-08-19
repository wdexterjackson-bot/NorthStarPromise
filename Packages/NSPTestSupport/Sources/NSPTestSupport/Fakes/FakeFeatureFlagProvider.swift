import NSPCore

/// A `FeatureFlagProviding` a test configures explicitly, rather than the
/// shipping `AllFlagsOffProvider` default.
public struct FakeFeatureFlagProvider: FeatureFlagProviding {
    private let enabledFlags: Set<FeatureFlag>

    public init(enabled: Set<FeatureFlag> = []) {
        self.enabledFlags = enabled
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFlags.contains(flag)
    }
}

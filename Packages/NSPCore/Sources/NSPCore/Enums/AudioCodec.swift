/// Speech-optimized codecs evaluated by the `NSP-003` spike (docs/01 §2).
public enum AudioCodec: String, Sendable, Hashable, Codable, CaseIterable {
    case aacLC = "aac-lc"
    case heAAC = "he-aac"
}

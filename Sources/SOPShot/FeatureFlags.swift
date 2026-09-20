import Foundation

enum FeatureFlags {
    /// Debug jump assistant: enabled when building from the `release` branch.
    static var showsDebugAssistant: Bool {
        #if SOPSHOT_DEBUG_ASSISTANT
        true
        #else
        false
        #endif
    }
}

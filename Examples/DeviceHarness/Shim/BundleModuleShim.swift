// The package's tests load QECirc circuits through SwiftPM's `Bundle.module`.
// In this Xcode test bundle the same files are copied as a "qecirc" folder,
// so `Bundle.module` points at the test bundle itself.

import Foundation

private final class BundleToken {}

extension Bundle {
    static var module: Bundle { Bundle(for: BundleToken.self) }
}

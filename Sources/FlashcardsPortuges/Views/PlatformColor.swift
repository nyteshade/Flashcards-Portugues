import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Cross-platform color shims for the shared views. SwiftUI exposes
/// `Color(nsColor:)` only on macOS and `Color(uiColor:)` only on iOS;
/// shared views call into these helpers instead of branching inline.
extension Color {
  /// A subtle "card surface" tint distinct from the list/page
  /// background. macOS uses `NSColor.windowBackgroundColor`; iOS uses
  /// `UIColor.secondarySystemBackground` (the closest visual match —
  /// `systemBackground` is the plain page surface).
  static var platformWindowBackground: Color {
    #if os(macOS)
    return Color(nsColor: .windowBackgroundColor)
    #elseif os(iOS)
    return Color(uiColor: .secondarySystemBackground)
    #else
    return Color.gray.opacity(0.1)
    #endif
  }
}

import UIKit

/// A navigation controller that lets the screen on top decide the status bar style.
///
/// A plain `UINavigationController` decides by itself, from its navigation bar. After a full-screen
/// dark screen (the preview) has been dismissed, it kept answering "light text" even in light mode,
/// and the clock disappeared on the white background. The screens here use the default style,
/// which follows light and dark mode.
final class AppNavigationController: UINavigationController {

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }
}

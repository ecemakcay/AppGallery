import UIKit

extension UIView {

    /// Every view of the given type below this one, however deep.
    func descendants<View: UIView>(ofType type: View.Type) -> [View] {
        subviews.flatMap { subview in
            ((subview as? View).map { [$0] } ?? []) + subview.descendants(ofType: type)
        }
    }
}

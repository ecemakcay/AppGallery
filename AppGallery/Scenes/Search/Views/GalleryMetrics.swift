import CoreGraphics

/// The measurements of a screenshot gallery for a given container width.
///
/// Everything follows from the width that is available, never from the kind of device.
/// That is why iPhone, iPad, rotation and Split View need no special cases.
struct GalleryMetrics: Equatable {

    /// Height over width of a tile. A screenshot with another ratio is fitted inside, never cropped.
    static let tileAspectRatio: CGFloat = 16.0 / 9.0
    static let cornerRadius: CGFloat = 16

    /// How many tiles a row shows. The half tile cut off at the edge is the only hint that the row scrolls.
    let visibleTileCount: CGFloat
    /// Distance from the leading edge to the first tile, and the inset of the texts.
    let margin: CGFloat
    let spacing: CGFloat
    let tileSize: CGSize

    init(containerWidth: CGFloat) {
        switch containerWidth {
        case ..<600:
            // iPhone in portrait, and an iPad app squeezed into a narrow Split View.
            visibleTileCount = 2.5
            margin = 16
            spacing = 10
        case ..<900:
            // iPad 11-inch in portrait, iPhone in landscape.
            visibleTileCount = 3.5
            margin = 20
            spacing = 12
        default:
            // iPad 13-inch, and any iPad in landscape.
            visibleTileCount = 4.5
            margin = 20
            spacing = 14
        }

        // A row starts at the margin and runs to the trailing edge. That width is shared
        // by the visible tiles and by the gaps between them (one gap per whole tile).
        let gaps = visibleTileCount.rounded(.down) * spacing
        let width = max(0, ((containerWidth - margin - gaps) / visibleTileCount).rounded(.down))
        tileSize = CGSize(width: width, height: (width * Self.tileAspectRatio).rounded())
    }
}

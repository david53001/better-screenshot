import CoreGraphics

/// Where a selected text's handles go, in canvas view points (top-left origin, like the canvas).
/// The four corners (which scale the text) are round and sit just outside the box's corners; the
/// two sides (which set the box width) are thin bars just outside its left and right edges. So the
/// handles don't cover the first and last letters, and the two kinds look different. The side bars
/// are left out when the box is too short for them to clear the corners (a one-line text zoomed out).
public enum TextHandles {
    public static let cornerDiameter: CGFloat = 9
    /// Corner centres (and the bars' centre lines) sit this far outside the box.
    public static let outset: CGFloat = 4
    public static let barWidth: CGFloat = 4
    public static let maxBarHeight: CGFloat = 16
    public static let minBarHeight: CGFloat = 6
    /// Gap kept between a side bar and the corner circles above and below it.
    public static let clearance: CGFloat = 2

    /// Corner handle indices (the canvas's numbering): 0 top-left, 2 top-right, 5 bottom-left, 7 bottom-right.
    public static let corners = [0, 2, 5, 7]
    /// Side handle indices: 3 middle-left, 4 middle-right.
    public static let sides = [3, 4]

    /// Handle index → rect for `box`. Corners always; sides only when they fit.
    public static func rects(for box: CGRect) -> [Int: CGRect] {
        let r = cornerDiameter / 2
        let left = box.minX - outset, right = box.maxX + outset
        let top = box.minY - outset, bottom = box.maxY + outset
        func circle(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - r, y: y - r, width: cornerDiameter, height: cornerDiameter)
        }
        var rects: [Int: CGRect] = [0: circle(left, top), 2: circle(right, top),
                                    5: circle(left, bottom), 7: circle(right, bottom)]
        // Free height between the top and bottom corner circles, minus the clearance each side.
        let free = (bottom - r) - (top + r) - 2 * clearance
        let barHeight = min(maxBarHeight, free)
        if barHeight >= minBarHeight {
            func bar(_ x: CGFloat) -> CGRect {
                CGRect(x: x - barWidth / 2, y: box.midY - barHeight / 2, width: barWidth, height: barHeight)
            }
            rects[3] = bar(left)
            rects[4] = bar(right)
        }
        return rects
    }
}

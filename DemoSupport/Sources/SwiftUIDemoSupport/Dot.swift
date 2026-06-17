import SwiftUI

/// A small colored status dot.
public struct Dot: View
{
    private let color: Color

    public init(color: Color)
    {
        self.color = color
    }

    public var body: some View
    {
        Circle().fill(color).frame(width: 10, height: 10)
    }
}

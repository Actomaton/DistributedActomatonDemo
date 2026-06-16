import SwiftUI

/// Assigns a stable color to a node/peer name so the same participant looks consistent everywhere.
public enum DemoPalette
{
    private static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]

    public static func color(for key: String) -> Color
    {
        var hash = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) ^ Int(byte)
        }
        let index = ((hash % colors.count) + colors.count) % colors.count
        return colors[index]
    }
}

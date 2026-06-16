import SwiftUI

/// Rounded, material-backed container used for every panel in the demos.
public struct DemoCard<Content: View>: View
{
    private let content: Content

    public init(@ViewBuilder content: () -> Content)
    {
        self.content = content()
    }

    public var body: some View
    {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary)
            }
    }
}

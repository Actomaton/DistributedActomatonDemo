import SwiftUI

/// Title + explanatory subtitle banner shared by the demos.
public struct DemoHeader: View
{
    private let title: String
    private let subtitle: String

    public init(title: String, subtitle: String)
    {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

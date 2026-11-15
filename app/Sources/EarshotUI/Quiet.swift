import AppKit
import EarshotCore
import SwiftUI

// The quiet look of the panel and the window (dk, 2026-11-15, prototype B): white text on black, few lines,
// large titles, short captions. The colors are the same as on the website and on the plugin pages.

/// The colors of the quiet look.
public enum Quiet {
    public static let background = Color.black
    public static let text = Color.white
    /// Secondary text. On black, its contrast is about 7:1.
    public static let dim = Brand.hex(0x9A9A9A)
    /// The thin line between rows.
    public static let line = Brand.hex(0x1F1F1F)
    /// The fill of a selected control.
    public static let fill = Brand.hex(0x1C1C1C)
    /// A late item, or a failed command.
    public static let late = Brand.hex(0xFF8A7A)
}

/// A row of text links at the top of the window. The selected link is white and has a line below it.
struct TopLinks<Page: Hashable>: View {
    let pages: [(page: Page, title: String)]
    @Binding var selection: Page

    var body: some View {
        HStack(spacing: 28) {
            ForEach(pages, id: \.page) { item in
                let on = item.page == selection
                Button { selection = item.page } label: {
                    VStack(spacing: 6) {
                        Text(item.title).font(.system(size: 14, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Quiet.text : Quiet.dim)
                        Rectangle().fill(on ? Quiet.text : Color.clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// The large title of a page, with one optional line under it.
struct PageTitle: View {
    let title: String
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 34, weight: .semibold)).tracking(-0.6)
            if let sub { Text(sub).font(.system(size: 14)).foregroundStyle(Quiet.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small uppercase heading over a group of rows.
struct GroupHeading: View {
    let text: String
    var color: Color = Quiet.dim
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(color)
    }
}

/// A round button with a thin outline, or filled white for the main action.
struct PillButtonStyle: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: filled ? .semibold : .regular))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(filled ? Color.black : Quiet.text)
            .background(Capsule().fill(filled ? Quiet.text : Color.clear))
            .overlay(Capsule().stroke(filled ? Color.clear : Brand.hex(0x333333), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

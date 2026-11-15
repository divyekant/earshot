import AppKit
import SwiftUI

// The controls of the design system "earshot": keys, quiet links, the switch, the segmented choice, the field,
// the pick, chips, keycaps, the voice bars, the orb, the banner and the mode card. They replace the Mac form
// controls, so that the panel and the window look the same as the design canvas.

/// A glyph of earshot, stroked in the current foreground color.
public struct Glyph: View {
    let kind: GlyphKind
    var size: CGFloat
    var weight: CGFloat?

    public init(_ kind: GlyphKind, size: CGFloat = 16, weight: CGFloat? = nil) {
        self.kind = kind; self.size = size; self.weight = weight
    }

    public var body: some View {
        GlyphShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: (weight ?? kind.weight) * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The path of a glyph, scaled from the 24-unit grid to the frame.
struct GlyphShape: Shape {
    let kind: GlyphKind
    func path(in rect: CGRect) -> Path {
        kind.path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24))
    }
}

// MARK: - Keys

/// A key: the button of earshot. `ink` is the one main action of a place, `line` is any other action.
public struct KeyStyle: ButtonStyle {
    public enum Kind: Sendable { case ink, line }
    var kind: Kind
    var small: Bool

    public init(_ kind: Kind = .line, small: Bool = false) { self.kind = kind; self.small = small }

    public func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, kind: kind, small: small)
    }

    struct KeyBody: View {
        let configuration: Configuration
        let kind: Kind
        let small: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let radius: CGFloat = small ? 8 : 9
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .textStyle(small ? .keySmall : .key)
                .lineLimit(1)
                .padding(.horizontal, small ? 10 : 13)
                .frame(height: small ? 26 : 30)
                .foregroundStyle(kind == .ink ? Palette.paper : Palette.ink)
                .background(shape.fill(kind == .ink ? Palette.ink : Palette.hex(0x1A1A19)))
                .overlay(shape.strokeBorder(kind == .ink ? Color.clear : (hover && enabled ? Palette.lineHi : Palette.line), lineWidth: 1))
                // The hard edge under the key, as on the site. A pressed key goes down onto it.
                .background(shape.fill(kind == .ink ? Palette.ink3 : Color.black).offset(y: pressed ? 0 : 2))
                .offset(y: pressed ? 2 : 0)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(shape)
                .onHover { h in withAnimation(Motion.hover) { hover = h } }
                .animation(.easeOut(duration: 0.09), value: pressed)
        }
    }
}

/// A quiet link: text that acts, with no box. ink2, and ink under the pointer.
public struct QuietStyle: ButtonStyle {
    var style: TextStyle
    public init(_ style: TextStyle = TextStyle(13, 18, 500)) { self.style = style }

    public func makeBody(configuration: Configuration) -> some View { QuietBody(configuration: configuration, style: style) }

    struct QuietBody: View {
        let configuration: Configuration
        let style: TextStyle
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .textStyle(style)
                .foregroundStyle(hover && enabled ? Palette.ink : Palette.ink2)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
                .onHover { h in withAnimation(Motion.hover) { hover = h } }
        }
    }
}

// MARK: - Switch, segmented choice, field, pick

/// The switch: a white track when on.
public struct SwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return HStack(spacing: 10) {
            configuration.label
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Palette.ink : Palette.fill)
                    .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.line, lineWidth: 1))
                Circle().fill(on ? Palette.paper : Palette.ink2).frame(width: 13, height: 13).padding(3)
            }
            .frame(width: 32, height: 19)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.control) { configuration.isOn.toggle() } }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAction { configuration.isOn.toggle() }
        }
    }
}

/// A choice of two to four short words in one control. The selected word sits on a raised segment.
public struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var full: Bool
    @Namespace private var space

    public init(selection: Binding<Value>, options: [(value: Value, title: String)], full: Bool = false) {
        _selection = selection; self.options = options; self.full = full
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Text(option.title)
                    .textStyle(TextStyle(13, 18, 500), on ? Palette.ink : Palette.ink2)
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .frame(maxWidth: full ? .infinity : nil)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fill)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                                .matchedGeometryEffect(id: "segment", in: space)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.control) { selection = option.value } }
                    .accessibilityElement()
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.raise))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
    }
}

/// A text field in the look of earshot. `onCommit` runs on Return and when the field loses focus.
public struct Field: View {
    @Binding var text: String
    var prompt: String
    var mono: Bool
    var secure: Bool
    var onCommit: () -> Void
    /// True if the field also commits when it loses the focus. A field that runs something commits on Return only.
    var commitOnBlur: Bool
    @FocusState private var focused: Bool

    public init(text: Binding<String>, prompt: String = "", mono: Bool = false, secure: Bool = false,
                commitOnBlur: Bool = true, onCommit: @escaping () -> Void = {}) {
        _text = text; self.prompt = prompt; self.mono = mono; self.secure = secure; self.onCommit = onCommit
        self.commitOnBlur = commitOnBlur
    }

    public var body: some View {
        let style = mono ? TextStyle(12.5, 18, mono: true) : TextStyle(13, 18)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(prompt).foregroundColor(Palette.ink3))
            } else {
                TextField("", text: $text, prompt: Text(prompt).foregroundColor(Palette.ink3))
            }
        }
        .textFieldStyle(.plain)
        .textStyle(style, Palette.ink)
        .focused($focused)
        .onSubmit(onCommit)
        .onChange(of: focused) { _, now in if !now && commitOnBlur { onCommit() } }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(shape.fill(Palette.raise))
        .overlay(shape.strokeBorder(focused ? Palette.ink2 : Palette.line, lineWidth: 1))
        .background(shape.stroke(Palette.ink.opacity(focused ? 0.10 : 0), lineWidth: 6))
        .animation(Motion.hover, value: focused)
    }
}

/// A pick: a short choice from a list, in a menu.
public struct Pick<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        _selection = selection; self.options = options
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    if option.value == selection { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .textStyle(TextStyle(13, 18, 500), Palette.ink)
                    .lineLimit(1)
                PickChevrons().stroke(Palette.ink3, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 12)
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.raise))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The up and down marks of a pick.
struct PickChevrons: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.36))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.36))
        p.move(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.36))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.36))
        return p
    }
}

// MARK: - Chips, dots, keycaps

/// A small fact in mono type: "0.54 sure", "6 ms", "chat".
public struct Chip: View {
    let text: String
    var tone: Color
    public init(_ text: String, tone: Color = Palette.ink2) { self.text = text; self.tone = tone }
    public var body: some View {
        Text(text)
            .textStyle(TextStyle(12, 16, mono: true), tone)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.raise))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
    }
}

/// A status dot. A live dot has a ring that pulses.
public struct Dot: View {
    public enum Tone: Sendable { case live, still, amber, coral }
    let tone: Tone
    @State private var pulse = false
    public init(_ tone: Tone) { self.tone = tone }

    public var body: some View {
        let color: Color = switch tone {
        case .live: Palette.ink
        case .still: Palette.ink2
        case .amber: Palette.amber
        case .coral: Palette.coral
        }
        Circle().fill(color).frame(width: 6, height: 6)
            .background {
                if tone == .live {
                    Circle().stroke(Palette.ink.opacity(pulse ? 0 : 0.12), lineWidth: pulse ? 5 : 3)
                        .frame(width: pulse ? 16 : 12, height: pulse ? 16 : 12)
                        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                }
            }
            .onAppear { if tone == .live { pulse = true } }
    }
}

/// A key on the keyboard, for the hold key: "⌥ right".
public struct Keycap: View {
    public enum Size: Sendable { case mini, normal, big }
    let text: String
    var size: Size
    public init(_ text: String, size: Size = .normal) { self.text = text; self.size = size }

    public var body: some View {
        let (h, minW, font, radius, pad): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = switch size {
        case .mini: (18, 18, 10.5, 5, 5)
        case .normal: (24, 26, 12, 7, 7)
        case .big: (56, 64, 22, 14, 14)
        }
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Text(text)
            .font(Typeface.font(TextStyle(font, font + 4, 500)))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, pad)
            .frame(minWidth: minW, minHeight: h, maxHeight: h)
            .background(shape.fill(LinearGradient(colors: [Palette.hex(0x2A2A28), Palette.raise2], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            // The light on the top edge of the key.
            .overlay(shape.inset(by: 1).stroke(LinearGradient(colors: [Color.white.opacity(0.10), .clear],
                                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)),
                                               lineWidth: 1))
            .background(shape.fill(Color.black).offset(y: size == .big ? 3 : 2))
            .shadow(color: size == .big ? .black.opacity(0.7) : .clear, radius: 8, y: 8)
            .fixedSize()
    }
}

/// The state chip at the top right of the window: a dot, the state in bold, and a short rest.
public struct StateChip: View {
    let dot: Dot.Tone
    let state: String
    let rest: String
    var key: String?
    public init(dot: Dot.Tone, state: String, rest: String, key: String? = nil) {
        self.dot = dot; self.state = state; self.rest = rest; self.key = key
    }
    public var body: some View {
        HStack(spacing: 8) {
            Dot(dot)
            Text(state).textStyle(TextStyle(12, 16, 600), Palette.ink)
            if !rest.isEmpty { Text(rest).textStyle(TextStyle(12, 16, 500), Palette.ink2).lineLimit(1) }
            if let key { Keycap(key, size: .mini) }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Palette.raise))
        .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Voice bars and the orb

/// The level of the open turn, 0 to 1, for the voice bars. Used on the main thread only.
public final class VoiceLevel: ObservableObject {
    @Published public private(set) var value: Double = 0
    public init() {}

    /// Sets the level from the loudest frame of the last 100 ms, in dB above the noise floor.
    public func set(dbAboveFloor: Double) {
        let next = min(1, max(0, dbAboveFloor / 30))
        // Rise at once, fall slowly, so that the bars are easy to read.
        value = next >= value ? next : value * 0.6 + next * 0.4
    }
}

/// The voice bars: they move with the voice. With no level, they move by themselves (a picture of a voice).
public struct VoiceBars: View {
    var count: Int
    var height: CGFloat
    var level: VoiceLevel?
    var color: Color

    public init(count: Int = 5, height: CGFloat = 18, level: VoiceLevel? = nil, color: Color = Palette.ink) {
        self.count = count; self.height = height; self.level = level; self.color = color
    }

    public var body: some View {
        if let level { Live(count: count, height: height, level: level, color: color) } else { Idle(count: count, height: height, color: color) }
    }

    /// The delay of each bar, so that the bars do not move together (the same as the canvas).
    static let delays: [Double] = [0, 0.12, 0.24, 0.36, 0.48, 0.16, 0.30, 0.06, 0.42, 0.20, 0.34, 0.10]

    /// The height of a bar at a phase 0...1 of its 900 ms loop: 4, up to 16 at 40 %, 9 at 70 %, back to 4.
    static func wave(_ phase: Double) -> Double {
        switch phase {
        case ..<0.4: return 4 + 12 * ease(phase / 0.4)
        case ..<0.7: return 16 - 7 * ease((phase - 0.4) / 0.3)
        default: return 9 - 5 * ease((phase - 0.7) / 0.3)
        }
    }

    static func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    struct Idle: View {
        let count: Int, height: CGFloat, color: Color
        var body: some View {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        let phase = ((t - VoiceBars.delays[i % 12]) / 0.9).truncatingRemainder(dividingBy: 1)
                        let h = VoiceBars.wave(phase < 0 ? phase + 1 : phase)
                        Capsule().fill(color.opacity(0.55 + 0.45 * (h - 4) / 12)).frame(width: 2.5, height: h * height / 18)
                    }
                }
                .frame(height: height)
            }
        }
    }

    struct Live: View {
        let count: Int, height: CGFloat
        @ObservedObject var level: VoiceLevel
        let color: Color
        var body: some View {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        // Each bar moves on its own wave. The voice level sets how far the bars move.
                        let phase = ((t - VoiceBars.delays[i % 12]) / 0.9).truncatingRemainder(dividingBy: 1)
                        let wave = (VoiceBars.wave(phase < 0 ? phase + 1 : phase) - 4) / 12
                        let h = 3 + 13 * level.value * (0.35 + 0.65 * wave)
                        Capsule().fill(color.opacity(0.45 + 0.55 * level.value)).frame(width: 2.5, height: h * height / 18)
                    }
                }
                .frame(height: height)
            }
        }
    }
}

/// The orb of the panel header: the ear in a circle. It shows what earshot does now.
public struct Orb: View {
    public enum Look: Equatable, Sendable {
        /// Waits for the hold key.
        case still
        /// Always on: a ring breathes while earshot waits for the phrase.
        case breathe
        /// A turn is open: the voice bars.
        case hearing
        /// The follow-up window: the ring empties until `until`.
        case next(until: Date, seconds: Double)
        /// earshot waits for words to type.
        case text
        /// Paused, or earshot needs you: amber.
        case paused
        case needsYou
    }

    let look: Look
    var level: VoiceLevel?
    @State private var breathe = false
    public init(_ look: Look, level: VoiceLevel? = nil) { self.look = look; self.level = level }

    public var body: some View {
        ZStack {
            Circle().fill(Palette.raise)
            Circle().strokeBorder(edge, lineWidth: 1)
            content
        }
        .frame(width: 40, height: 40)
        .background {
            if look == .breathe {
                Circle().stroke(Palette.ink.opacity(breathe ? 0 : 0.5), lineWidth: 1)
                    .scaleEffect(breathe ? 1.5 : 1)
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 2.4).repeatForever(autoreverses: false), value: breathe)
            }
        }
        .overlay {
            if case let .next(until, seconds) = look {
                TimelineView(.animation) { context in
                    let left = max(0, until.timeIntervalSince(context.date)) / max(0.1, seconds)
                    Circle().trim(from: 0, to: left)
                        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 46, height: 46)
                }
            }
        }
        .onAppear { breathe = true }
        .accessibilityHidden(true)
    }

    private var edge: Color {
        switch look {
        case .paused, .needsYou: return Palette.amber.opacity(0.45)
        case .hearing: return Palette.lineHi
        default: return Palette.rule
        }
    }

    @ViewBuilder private var content: some View {
        switch look {
        case .hearing: VoiceBars(count: 5, height: 18, level: level)
        case .text: Glyph(.text, size: 18).foregroundStyle(Palette.ink)
        case .paused: Glyph(.pause, size: 18).foregroundStyle(Palette.amber)
        case .needsYou: Glyph(.ear, size: 18).foregroundStyle(Palette.amber)
        default: Glyph(.ear, size: 18).foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - Banner, mode card, rows and groups

/// One line that needs the owner, in amber: what is wrong, and one way to fix it.
public struct Banner<Action: View>: View {
    let title: String
    let detail: String
    let action: Action
    public init(_ title: String, detail: String = "", @ViewBuilder action: () -> Action) {
        self.title = title; self.detail = detail; self.action = action()
    }
    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(.failed).foregroundStyle(Palette.amber).padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(TextStyle(12.5, 17), Palette.ink)
                if !detail.isEmpty { Text(detail).textStyle(TextStyle(12.5, 17), Palette.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            action
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.amberWash))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.amber.opacity(0.28), lineWidth: 1))
    }
}

extension Banner where Action == EmptyView {
    public init(_ title: String, detail: String = "") { self.init(title, detail: detail) { EmptyView() } }
}

/// A large card for one of two ways, with a picture, a title and one sentence.
public struct ModeCard<Picture: View>: View {
    let title: String
    let detail: String
    let on: Bool
    let picture: Picture
    let choose: () -> Void
    @State private var hover = false

    public init(title: String, detail: String, on: Bool, choose: @escaping () -> Void, @ViewBuilder picture: () -> Picture) {
        self.title = title; self.detail = detail; self.on = on; self.choose = choose; self.picture = picture()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            picture
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
                .padding(.bottom, 12)
            Text(title).textStyle(.section, Palette.ink)
            Text(detail).textStyle(TextStyle(12.5, 17), Palette.ink2).padding(.top, 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(shape.fill(on ? Palette.hex(0x1A1A19) : Palette.raise))
        .overlay(shape.strokeBorder(on ? Palette.ink : (hover ? Palette.lineHi : Palette.line), lineWidth: on ? 1.5 : 1))
        .overlay(alignment: .topTrailing) {
            ZStack {
                if on {
                    Circle().fill(Palette.ink)
                    Glyph(.check, size: 12, weight: 2.4).foregroundStyle(Palette.paper)
                } else {
                    Circle().strokeBorder(Palette.line, lineWidth: 1.5)
                }
            }
            .frame(width: 18, height: 18)
            .padding(14)
        }
        .contentShape(shape)
        .onTapGesture { withAnimation(Motion.control) { choose() } }
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A group of rows on a slightly raised card.
public struct RowGroup<Content: View>: View {
    let content: Content
    var edge: Color
    public init(edge: Color = Palette.rule, @ViewBuilder content: () -> Content) { self.content = content(); self.edge = edge }
    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 18).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.hex(0x111110)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }
}

/// One setting: its name, one line about it, and its control on the right. A line under it, except for the last.
public struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    var detailTone: Color
    var last: Bool
    let control: Control

    public init(_ title: String, detail: String = "", detailTone: Color = Palette.ink2, last: Bool = false,
                @ViewBuilder control: () -> Control) {
        self.title = title; self.detail = detail; self.detailTone = detailTone; self.last = last; self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.body, Palette.ink)
                if !detail.isEmpty { Text(detail).textStyle(.detail, detailTone).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Palette.rule).frame(height: 1) } }
    }
}

/// The title of a group of settings, with one plain sentence under it.
public struct GroupTitle: View {
    let title: String
    var sub: String
    public init(_ title: String, sub: String = "") { self.title = title; self.sub = sub }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textStyle(.head, Palette.ink)
            if !sub.isEmpty { Text(sub).textStyle(.call, Palette.ink2).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A thin line between rows.
public struct Rule: View {
    public init() {}
    public var body: some View { Rectangle().fill(Palette.rule).frame(height: 1) }
}

/// A search field with the search glyph, for the top of a page.
public struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var width: CGFloat
    public init(text: Binding<String>, prompt: String, width: CGFloat = 230) {
        _text = text; self.prompt = prompt; self.width = width
    }
    public var body: some View {
        HStack(spacing: 8) {
            Glyph(.search, size: 14).foregroundStyle(Palette.ink3)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Palette.ink3))
                .textFieldStyle(.plain).textStyle(TextStyle(13, 18), Palette.ink)
            if !text.isEmpty {
                Button { text = "" } label: { Glyph(.remove, size: 12).foregroundStyle(Palette.ink3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 11).frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.raise))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// The first letter of a name on a small raised tile: the mark of an app or a plugin.
public struct Tile: View {
    let name: String
    var size: CGFloat
    var dim: Bool
    public init(_ name: String, size: CGFloat = 28, dim: Bool = false) { self.name = name; self.size = size; self.dim = dim }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Text(String(name.first.map { String($0).uppercased() } ?? "·"))
            .textStyle(TextStyle(size * 0.46, size * 0.6, 650), Palette.ink)
            .frame(width: size, height: size)
            .background(shape.fill(LinearGradient(colors: [Palette.hex(0x3A3A37), Palette.fill], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            .opacity(dim ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

/// A chip with a remove mark, for a name that the owner can take away.
public struct RemovableChip: View {
    let text: String
    let remove: () -> Void
    @State private var hover = false
    public init(_ text: String, remove: @escaping () -> Void) { self.text = text; self.remove = remove }
    public var body: some View {
        HStack(spacing: 4) {
            Text(text).textStyle(TextStyle(12.5, 16), Palette.ink)
            Button(action: remove) {
                Glyph(.remove, size: 11).foregroundStyle(hover ? Palette.ink2 : Palette.ink4).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 8).padding(.trailing, 5).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.raise2))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
    }
}

/// Keycaps for a shortcut text of the menus, for example "cmd+k" gives ⌘ and K.
public struct ShortcutCaps: View {
    let keys: String
    public init(_ keys: String) { self.keys = keys }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.caps(keys).enumerated()), id: \.offset) { _, cap in Keycap(cap, size: .mini) }
        }
    }

    /// "cmd+shift+k" gives ["⇧", "⌘", "K"], in the order of the Mac menus.
    public static func caps(_ keys: String) -> [String] {
        let parts = keys.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let order: [(String, String)] = [("ctrl", "⌃"), ("opt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
        let named: [String: String] = ["return": "↩", "enter": "⌤", "tab": "⇥", "escape": "esc", "space": "space",
                                       "delete": "⌫", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        var out = order.filter { parts.contains($0.0) }.map(\.1)
        for p in parts where !order.contains(where: { $0.0 == p }) {
            out.append(named[p] ?? p.uppercased())
        }
        return out
    }
}

/// A state in the middle of a page: a glyph on a tile, a title, one or two sentences and up to two keys.
public struct CenterState<Actions: View>: View {
    public enum Tone: Sendable { case plain, amber, coral }
    let glyph: GlyphKind?
    let cap: String?
    let tone: Tone
    let title: String
    let detail: String
    let actions: Actions

    public init(glyph: GlyphKind? = nil, cap: String? = nil, tone: Tone = .plain, title: String, detail: String,
                @ViewBuilder actions: () -> Actions) {
        self.glyph = glyph; self.cap = cap; self.tone = tone; self.title = title; self.detail = detail; self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            mark.padding(.bottom, 22)
            Text(title).textStyle(.title, Palette.ink).multilineTextAlignment(.center)
            Text(detail).textStyle(TextStyle(13.5, 19), Palette.ink2)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400).padding(.top, 8)
            HStack(spacing: 10) { actions }.padding(.top, 20)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    @ViewBuilder private var mark: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if let cap {
            Keycap(cap, size: .big)
        } else if let glyph {
            let (color, wash, edge): (Color, Color, Color) = switch tone {
            case .plain: (Palette.ink, Palette.raise, Palette.line)
            case .amber: (Palette.amber, Palette.amberWash, Palette.amberEdge)
            case .coral: (Palette.coral, Palette.coralWash, Palette.coralEdge)
            }
            Glyph(glyph, size: 20).foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(shape.fill(wash))
                .overlay(shape.strokeBorder(edge, lineWidth: 1))
        }
    }
}

extension CenterState where Actions == EmptyView {
    public init(glyph: GlyphKind? = nil, cap: String? = nil, tone: Tone = .plain, title: String, detail: String) {
        self.init(glyph: glyph, cap: cap, tone: tone, title: title, detail: detail) { EmptyView() }
    }
}

/// Puts its children in rows, left to right, and starts a new row when a row is full. For chips.
public struct Flow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) { self.spacing = spacing; self.lineSpacing = lineSpacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let next = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if next > width && !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

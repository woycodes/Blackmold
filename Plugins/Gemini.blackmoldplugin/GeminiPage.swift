import BlackmoldKit
import SwiftUI

/// Gemini in the notch, through the Gemini API.
///
/// - No key yet: a field to paste one.
/// - Otherwise the composer: what to ask, the model, mic, photo and Live.
/// - Once something is asked the notch grows down to show the conversation,
///   with a field for the next question. New chat goes back to the composer.
/// - Live: a spoken conversation with a glow that follows the voices.
struct GeminiPage: View {
    @Bindable var controller: GeminiPlugin

    var body: some View {
        let chat = controller.gemini
        Group {
            if !chat.hasKey {
                GeminiKeyEntry(controller: controller)
            } else if let live = chat.live {
                GeminiLiveView(live: live)
            } else if chat.showingModels {
                ModelList(chat: chat)
            } else if chat.hasConversation {
                GeminiConversation(controller: controller)
            } else {
                GeminiComposer(controller: controller)
            }
        }
        .modifier(GeminiFrame(boxed: boxed, height: controller.pageHeight))
        .animation(.easeOut(duration: 0.2), value: chat.hasConversation)
        .animation(.easeOut(duration: 0.2), value: chat.showingModels)
    }

    /// The composer and Live sit straight on the black, like Gemini's own app;
    /// the rest goes in the Mirror's box.
    private var boxed: Bool {
        let chat = controller.gemini
        return !chat.hasKey || chat.showingModels || chat.live == nil && chat.hasConversation
    }

    /// Inside the box, everything keeps this gap from its edges.
    static let inset: CGFloat = 12
}

/// The Mirror's box (same corners, bottom gap equal to the side gap), or
/// the bare page down to the notch's own bottom edge.
private struct GeminiFrame: ViewModifier {
    let boxed: Bool
    let height: CGFloat

    func body(content: Content) -> some View {
        if boxed {
            content
                .padding(GeminiPage.inset)
                .frame(maxWidth: .infinity)
                .frame(height: height - NotchSize.contentTop - NotchSize.pageInset, alignment: .top)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, NotchSize.contentTop)
        } else {
            content
                .frame(maxWidth: .infinity)
                .frame(height: height - NotchSize.contentTop, alignment: .top)
                .padding(.top, NotchSize.contentTop)
        }
    }
}

// MARK: Typing

/// A text field in the notch pins it open while it has focus, and lets go on Escape.
private struct NotchTyping: ViewModifier {
    let controller: GeminiPlugin
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .focused(focus)
            .onChange(of: focus.wrappedValue) { _, focused in
                if focused { controller.beginTyping() }
            }
            .onExitCommand { controller.endTyping() }
    }
}
private extension View {
    func notchTyping(_ controller: GeminiPlugin, _ focus: FocusState<Bool>.Binding) -> some View {
        modifier(NotchTyping(controller: controller, focus: focus))
    }
}

private let geminiBlue = Color(red: 0.27, green: 0.52, blue: 1)

// MARK: Key

private struct GeminiKeyEntry: View {
    @Bindable var controller: GeminiPlugin
    @State private var key = ""
    @State private var problem: String?
    @State private var checking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Connect Gemini")
                .font(.system(size: 14, weight: .semibold))
            Text("Paste a Gemini API key. It is kept in your keychain and can be changed in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SecureField("API key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.1), in: Capsule())
                    .notchTyping(controller, $focused)
                    .onSubmit(save)
                Button(action: save) {
                    Group {
                        if checking { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)) }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                }
                .buttonStyle(.zoom)
                .disabled(checking)
            }

            HStack {
                if let problem {
                    Text(problem)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(1)
                }
                Spacer()
                Link("Get a key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(geminiBlue)
            }
        }
    }

    private func save() {
        guard !checking else { return }
        checking = true
        problem = nil
        Task {
            problem = await controller.gemini.setKey(key)
            checking = false
            if problem == nil {
                key = ""
                controller.endTyping()
            }
        }
    }
}

// MARK: Composer

private struct GeminiComposer: View {
    @Bindable var controller: GeminiPlugin
    @FocusState private var focused: Bool
    /// Starts hidden after a Live with nothing said, so the entrance plays once
    /// from nothing; visible from the first frame otherwise.
    @State private var shown: Bool

    init(controller: GeminiPlugin) {
        self.controller = controller
        _shown = State(initialValue: !controller.gemini.composerEntrance)
    }

    var body: some View {
        let chat = controller.gemini
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Type, talk, or share a photo to Gemini", text: Bindable(chat).draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(3)
                    .notchTyping(controller, $focused)
                    .onSubmit { controller.send() }
                    .modifier(Staggered(shown: shown, order: 0))
                AttachmentChips(chat: chat)
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ModelMenu(chat: chat).modifier(Pop(shown: shown, order: 0))
                MicCameraPill(chat: chat).modifier(Pop(shown: shown, order: 1))
                Spacer(minLength: 0)
                Group {
                    if chat.canSend {
                        SendButton { controller.send() }
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        LiveButton { controller.startLive() }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .modifier(Pop(shown: shown, order: 2))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: chat.canSend)
            .padding(.bottom, 14)
        }
        .onAppear {
            guard chat.composerEntrance else { return }
            chat.composerEntrance = false
            DispatchQueue.main.async { shown = true }
        }
    }
}

/// The model in use; a click grows the notch to the model list.
private struct ModelMenu: View {
    @Bindable var chat: GeminiChat

    var body: some View {
        Button { chat.showingModels = true } label: {
            HStack(spacing: 4) {
                Text(chat.modelName.replacingOccurrences(of: "Gemini ", with: ""))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(maxWidth: 130)
            .background(.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.zoom)
        .fixedSize()
    }
}

/// Every model the key can use; picking one goes back to the composer.
private struct ModelList: View {
    @Bindable var chat: GeminiChat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { chat.showingModels = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.zoom)
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(chat.models) { model in
                        let current = model.id == chat.modelID
                        Button {
                            chat.modelID = model.id
                            chat.showingModels = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.name).font(.system(size: 13, weight: .medium))
                                    Text(model.id).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                Spacer()
                                if current { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(current ? .white.opacity(0.1) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// The white pill with the mic and the photo, as in Gemini's own app.
private struct MicCameraPill: View {
    @Bindable var chat: GeminiChat

    var body: some View {
        HStack(spacing: 0) {
            Button(action: chat.toggleVoice) {
                Group {
                    if let since = chat.recordingSince {
                        RecordingDot(since: since)
                    } else {
                        Image(systemName: "mic").font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
            }
            .help(chat.recordingSince == nil ? "Ask by voice" : "Stop and send")
            Rectangle().fill(.black.opacity(0.15)).frame(width: 1, height: 16)
            Button(action: chat.pickPhoto) {
                Image(systemName: "camera").font(.system(size: 13, weight: .medium))
                    .frame(width: 38, height: 30)
                    .contentShape(Rectangle())
            }
            .help("Share a photo")
        }
        .buttonStyle(.zoom)
        .foregroundStyle(.black.opacity(0.75))
        .background(.white.opacity(0.92), in: Capsule())
    }
}

private struct RecordingDot: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 0.5)) { context in
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 6, height: 6)
                    .opacity(Int(context.date.timeIntervalSince(since) * 2) % 2 == 0 ? 1 : 0.35)
                Text(TimeFormatting.short(context.date.timeIntervalSince(since)))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
        }
    }
}

/// The Live button: bars and a spark, like Gemini Live's mark.
private struct LiveButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LiveMark()
                .frame(width: 16, height: 16)
                .frame(width: 32, height: 32)
                .background(.white.opacity(hovered ? 0.2 : 0.12), in: Circle())
                .scaleEffect(hovered ? 1.08 : 1)
        }
        .buttonStyle(.zoom)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .help("Talk with Gemini Live")
    }
}

/// Three bars and a small four-pointed spark.
struct LiveMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { index in
                    let heights: [CGFloat] = [0.4, 0.8, 0.4]
                    Capsule()
                        .frame(width: w * 0.13, height: h * heights[index])
                        .offset(x: w * (0.02 + 0.25 * CGFloat(index)), y: h * (0.6 - heights[index] / 2))
                }
                GeminiStar()
                    .frame(width: w * 0.34, height: h * 0.34)
                    .offset(x: w * 0.64, y: 0)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct SendButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(.white, in: Circle())
        }
        .buttonStyle(.zoom)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

/// A photo or voice clip waiting to go with the next question.
private struct AttachmentChips: View {
    @Bindable var chat: GeminiChat

    var body: some View {
        if !chat.attachments.isEmpty {
            HStack(spacing: 6) {
                ForEach(chat.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = attachment.thumbnail {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "waveform").font(.system(size: 14))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.white.opacity(0.12))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button { chat.remove(attachment) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 14, height: 14)
                                .background(.white, in: Circle())
                        }
                        .buttonStyle(.zoom)
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
    }
}

// MARK: Conversation

private struct GeminiConversation: View {
    @Bindable var controller: GeminiPlugin
    @FocusState private var focused: Bool

    var body: some View {
        let chat = controller.gemini
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(chat.turns.indices, id: \.self) { index in
                            TurnView(turn: chat.turns[index])
                        }
                        if chat.isThinking, chat.turns.last?.role != .model {
                            ThinkingLines()
                        }
                        if let error = chat.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onChange(of: chat.turns.last?.text.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: chat.turns.count) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .mask {
                // Text fades out under the top edge rather than being cut.
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04)],
                               startPoint: .top, endPoint: .bottom)
            }

            HStack(spacing: 6) {
                AttachmentChips(chat: chat)
                TextField("Ask Gemini", text: Bindable(chat).draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .notchTyping(controller, $focused)
                    .onSubmit { controller.send() }
                if chat.canSend {
                    Button { controller.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.zoom)
                } else {
                    Button(action: chat.toggleVoice) {
                        Group {
                            if let since = chat.recordingSince { RecordingDot(since: since) }
                            else { Image(systemName: "mic").font(.system(size: 13)) }
                        }
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.zoom)
                    .disabled(chat.isThinking)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 38)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }
}

private struct TurnView: View {
    let turn: GeminiTurn

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(turn.parts.enumerated()), id: \.offset) { _, part in
                        if case .file(let mime, let data) = part {
                            if mime.hasPrefix("image"), let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                Label("Voice message", systemImage: "waveform")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                    if !turn.text.isEmpty {
                        Text(turn.text)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .model:
            MarkdownText(text: turn.text)
        }
    }
}

/// Shimmering lines while the answer is on its way.
private struct ThinkingLines: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<3, id: \.self) { line in
                    Capsule()
                        .fill(LinearGradient(
                            colors: [geminiBlue.opacity(0.25), Color(red: 0.6, green: 0.5, blue: 1).opacity(0.55), geminiBlue.opacity(0.25)],
                            startPoint: UnitPoint(x: (t * 0.8).truncatingRemainder(dividingBy: 2) - 1, y: 0),
                            endPoint: UnitPoint(x: (t * 0.8).truncatingRemainder(dividingBy: 2), y: 0)))
                        .frame(height: 9)
                        .frame(maxWidth: line == 2 ? 160 : .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Enough Markdown for chat answers: headings, lists, code blocks, and
/// bold, italic, code and links inside lines.
private struct MarkdownText: View {
    let text: String

    private enum Block: Hashable {
        case paragraph(String), heading(String), bullet(String, indent: Int), numbered(String, String), code(String)
    }

    private var blocks: [Block] {
        var blocks: [Block] = []
        var code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { continue }
            let indent = (raw.count - raw.drop(while: { $0 == " " }).count) / 2
            if line.hasPrefix("#") {
                blocks.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("* ") || line.hasPrefix("- ") {
                blocks.append(.bullet(String(line.dropFirst(2)), indent: indent))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                blocks.append(.numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        return blocks
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let line):
                    inline(line).font(.system(size: 13)).lineSpacing(2)
                case .heading(let line):
                    inline(line).font(.system(size: 14, weight: .semibold)).padding(.top, 2)
                case .bullet(let line, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.white.opacity(0.5))
                        inline(line).lineSpacing(2)
                    }
                    .font(.system(size: 13))
                    .padding(.leading, CGFloat(indent) * 12)
                case .numbered(let number, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(number).foregroundStyle(.white.opacity(0.5)).monospacedDigit()
                        inline(line).lineSpacing(2)
                    }
                    .font(.system(size: 13))
                case .code(let code):
                    ScrollView(.horizontal) {
                        Text(code).font(.system(size: 11, design: .monospaced)).padding(10)
                    }
                    .scrollIndicators(.never)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .tint(geminiBlue)
        .foregroundStyle(.white.opacity(0.92))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Live

/// Gemini Live: a soft glow at the bottom that swells with the voices,
/// what Gemini says as a caption, and Hold and End.
private struct GeminiLiveView: View {
    let live: GeminiLive
    /// Drives the way in and the way out, which play the same steps in reverse.
    @State private var shown = false
    /// The blue, apart from `shown` so it moves on its own ease-in-out.
    @State private var glowUp = false

    private static let inOut = Animation.easeInOut(duration: 0.7)

    var body: some View {
        ZStack(alignment: .bottom) {
            // The blue rises from the bottom edge, and sinks back on End.
            LiveGlow(live: live)
                .padding(.horizontal, -NotchSize.pageInset)
                // Squashed into the bottom edge rather than slid: the blue is a thin
                // band there, so a slide would hide it in the first few frames.
                .scaleEffect(x: 1, y: glowUp ? 1 : 0.02, anchor: .bottom)
                .offset(y: glowUp ? 0 : 20)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: status)
                    .modifier(Staggered(shown: shown, order: 0))
                Spacer(minLength: 0)
                HStack(spacing: 34) {
                    LiveControl(symbol: live.phase == .held ? "play.fill" : "pause.fill",
                                label: live.phase == .held ? "Resume" : "Hold",
                                fill: .white.opacity(0.16), shown: shown, order: 1, action: live.toggleHold)
                    LiveControl(symbol: "xmark", label: "End", fill: Color(red: 0.86, green: 0.2, blue: 0.18),
                                shown: shown, order: 2, action: end)
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            shown = true
            withAnimation(Self.inOut) { glowUp = true }
        }
    }

    /// Everything leaves first, the blue sinks, then the session closes.
    private func end() {
        shown = false
        withAnimation(Self.inOut) { glowUp = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { live.end() }
    }

    private var status: String {
        switch live.phase {
        case .connecting: "Connecting…"
        case .listening: live.caption.isEmpty ? "Listening…" : live.caption
        case .speaking: live.caption.isEmpty ? "…" : live.caption
        case .held: "On hold"
        case .failed(let reason): reason
        }
    }
}

/// One step of the Live way in: in order on the way in, in reverse on the way out.
private struct Staggered: ViewModifier {
    let shown: Bool
    let order: Int
    var steps = 4

    func body(content: Content) -> some View {
        let delay = 0.08 * Double(shown ? order : steps - 1 - order) + (shown ? 0.15 : 0)
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .animation(.easeInOut(duration: 0.3).delay(delay), value: shown)
    }
}

private struct LiveControl: View {
    let symbol: String
    let label: String
    let fill: Color
    let shown: Bool
    let order: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(fill, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.zoom)
            .modifier(Pop(shown: shown, order: order - 1))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .modifier(Staggered(shown: shown, order: order + 1))
        }
    }
}

/// Pops in: grows past full size and settles, one after another; shrinks away in reverse.
private struct Pop: ViewModifier {
    let shown: Bool
    let order: Int
    var count = 3

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .animation(shown ? .spring(response: 0.4, dampingFraction: 0.5).delay(0.2 + 0.08 * Double(order))
                             : .easeIn(duration: 0.2).delay(0.08 * Double(count - 1 - order)), value: shown)
    }
}

/// Blurred blue and violet clouds along the bottom that drift and swell with the level.
struct LiveGlow: View {
    let live: GeminiLive

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = CGFloat(live.phase == .held ? 0 : live.level)
            let idle: CGFloat = live.phase == .connecting ? 0.38 : 0.55
            Canvas { gc, size in
                gc.addFilter(.blur(radius: 22))
                let colors: [Color] = [
                    Color(red: 0.35, green: 0.62, blue: 1), Color(red: 0.75, green: 0.88, blue: 1),
                    Color(red: 0.55, green: 0.55, blue: 1), Color(red: 0.3, green: 0.75, blue: 1),
                ]
                for index in 0..<4 {
                    let phase = t * (0.6 + Double(index) * 0.17) + Double(index) * 1.7
                    let x = size.width * (0.18 + 0.22 * CGFloat(index)) + CGFloat(sin(phase)) * 22
                    let height = size.height * (idle + 0.5 * level) * (0.75 + 0.25 * CGFloat(sin(phase * 1.3)))
                    let width = size.width * 0.42
                    let rect = CGRect(x: x - width / 2, y: size.height - height * 0.7, width: width, height: height * 1.4)
                    gc.fill(Ellipse().path(in: rect), with: .color(colors[index].opacity(0.8)))
                }
            }
        }
    }
}

// MARK: The mark

/// The four-pointed Gemini star in its colors.
struct GeminiLogo: View {
    var body: some View {
        GeminiStar()
            .fill(AngularGradient(
                stops: [
                    .init(color: Color(red: 0.19, green: 0.53, blue: 1), location: 0),
                    .init(color: Color(red: 0.19, green: 0.53, blue: 1), location: 0.12),
                    .init(color: Color(red: 0.05, green: 0.74, blue: 0.37), location: 0.27),
                    .init(color: Color(red: 0.98, green: 0.74, blue: 0.02), location: 0.5),
                    .init(color: Color(red: 1, green: 0.27, blue: 0.25), location: 0.72),
                    .init(color: Color(red: 0.19, green: 0.53, blue: 1), location: 0.88),
                    .init(color: Color(red: 0.19, green: 0.53, blue: 1), location: 1),
                ],
                center: .center))
    }
}

/// The star, turning while Gemini works.
struct GeminiSpinningLogo: View {
    var spinning: Bool

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeminiLogo()
                .rotationEffect(.degrees(spinning ? (t * 200).truncatingRemainder(dividingBy: 360) : 0))
                .scaleEffect(spinning ? 0.88 + 0.12 * sin(t * 5) : 1)
        }
    }
}

struct GeminiStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width / 2, h = rect.height / 2
        let top = CGPoint(x: c.x, y: rect.minY), right = CGPoint(x: rect.maxX, y: c.y)
        let bottom = CGPoint(x: c.x, y: rect.maxY), left = CGPoint(x: rect.minX, y: c.y)
        // Each side bows in towards the centre, past the straight line.
        let pull: CGFloat = 0.2
        var path = Path()
        path.move(to: top)
        path.addQuadCurve(to: right, control: CGPoint(x: c.x + w * pull, y: c.y - h * pull))
        path.addQuadCurve(to: bottom, control: CGPoint(x: c.x + w * pull, y: c.y + h * pull))
        path.addQuadCurve(to: left, control: CGPoint(x: c.x - w * pull, y: c.y + h * pull))
        path.addQuadCurve(to: top, control: CGPoint(x: c.x - w * pull, y: c.y - h * pull))
        path.closeSubpath()
        return path
    }
}

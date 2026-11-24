import BlackmoldKit
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The Gemini conversation behind the notch page: the key, the chosen model,
/// what was said, and what is going on right now.
@MainActor
@Observable
final class GeminiChat {
    enum Phase: Equatable {
        case idle
        /// Waiting for, or streaming, an answer.
        case thinking(since: Date)
    }

    struct Attachment: Equatable, Identifiable {
        let id = UUID()
        enum Kind { case photo, voice }
        let kind: Kind
        let mimeType: String
        let data: Data
        /// Shown in the composer.
        let thumbnail: NSImage?
        var duration: TimeInterval = 0

        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    private(set) var hasKey = GeminiKey.load() != nil
    private(set) var turns: [GeminiTurn] = []
    private(set) var phase: Phase = .idle
    private(set) var error: String?
    var draft = ""
    private(set) var attachments: [Attachment] = []

    private(set) var models: [GeminiModel] = GeminiAPI.fallbackModels
    private(set) var liveModels: [GeminiModel] = []
    var modelID: String {
        didSet { UserDefaults.standard.set(modelID, forKey: Self.modelKey) }
    }
    var modelName: String { models.first { $0.id == modelID }?.name ?? modelID }

    /// Live just ended with nothing said: the composer comes back with its entrance.
    var composerEntrance = false

    /// The model list is open in the notch.
    var showingModels = false

    /// A Gemini Live conversation, while one runs.
    private(set) var live: GeminiLive?

    /// Voice clip being recorded from the mic button.
    private(set) var recordingSince: Date?
    @ObservationIgnored private var recorder: AVAudioRecorder?

    /// Called when an answer finishes, and whether it was an error.
    @ObservationIgnored var onAnswer: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let modelKey = "gemini.chatModel"

    init() {
        modelID = UserDefaults.standard.string(forKey: Self.modelKey) ?? GeminiAPI.fallbackModels[0].id
        if hasKey { refreshModels() }
    }

    var isThinking: Bool { if case .thinking = phase { true } else { false } }
    /// The page grows to show the conversation.
    var hasConversation: Bool { !turns.isEmpty || error != nil }

    // MARK: Key

    /// Checks the key by listing the models, and keeps it only if that works.
    func setKey(_ key: String) async -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Paste a key first." }
        do {
            let found = try await GeminiAPI.models(key: key)
            GeminiKey.save(key)
            hasKey = true
            apply(found)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeKey() {
        GeminiKey.delete()
        hasKey = false
        newChat()
    }

    func refreshModels() {
        guard let key = GeminiKey.load() else { return }
        Task {
            if let found = try? await GeminiAPI.models(key: key) { apply(found) }
        }
    }

    private func apply(_ found: (chat: [GeminiModel], live: [GeminiModel])) {
        if !found.chat.isEmpty { models = found.chat }
        liveModels = found.live
        if !models.contains(where: { $0.id == modelID }) {
            modelID = models.first { $0.id == "gemini-flash-latest" }?.id ?? models[0].id
        }
    }

    // MARK: Chat

    var canSend: Bool {
        !isThinking && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    func send() {
        guard canSend, let key = GeminiKey.load() else { return }
        var parts: [GeminiPart] = attachments.map { .file(mimeType: $0.mimeType, data: $0.data) }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append(.text(text)) }
        else if attachments.contains(where: { $0.kind == .voice }) {
            parts.append(.text("Answer what I said in this voice message."))
        }
        turns.append(GeminiTurn(role: .user, parts: parts))
        draft = ""
        attachments = []
        error = nil
        phase = .thinking(since: Date())

        let history = turns
        let model = modelID
        task = Task { [weak self] in
            do {
                try await GeminiAPI.stream(turns: history, model: model, key: key) { piece in
                    guard let self else { return }
                    if self.turns.last?.role != .model { self.turns.append(GeminiTurn(role: .model, parts: [.text("")])) }
                    self.turns[self.turns.count - 1].parts = [.text(self.turns[self.turns.count - 1].text + piece)]
                }
                guard let self, !Task.isCancelled else { return }
                if self.turns.last?.role != .model { self.error = "Gemini sent back an empty answer." }
            } catch {
                guard let self, !Task.isCancelled else { return }
                if case GeminiError.badKey = error { self.hasKey = false }
                self.error = error.localizedDescription
            }
            guard let self, !Task.isCancelled else { return }
            self.phase = .idle
            self.onAnswer?()
        }
    }

    func newChat() {
        task?.cancel()
        task = nil
        cancelVoice()
        turns = []
        draft = ""
        attachments = []
        error = nil
        phase = .idle
        showingModels = false
    }

    // MARK: Photo

    func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo to share with Gemini"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addPhoto(at: url)
    }

    func addPhoto(at url: URL) {
        guard let image = NSImage(contentsOf: url), let jpeg = Self.jpeg(image, longestSide: 1600) else { return }
        attachments.removeAll { $0.kind == .photo }
        attachments.append(Attachment(kind: .photo, mimeType: "image/jpeg", data: jpeg, thumbnail: image))
    }

    func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    private static func jpeg(_ image: NSImage, longestSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, longestSide / CGFloat(max(cg.width, cg.height)))
        let size = CGSize(width: (CGFloat(cg.width) * scale).rounded(), height: (CGFloat(cg.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(origin: .zero, size: size))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: Voice clip

    /// First press records; the second stops and sends the clip.
    func toggleVoice() {
        if recorder != nil {
            finishVoice()
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor [weak self] in
                guard granted else {
                    self?.error = "Blackmold needs microphone access (System Settings › Privacy & Security › Microphone)."
                    return
                }
                self?.startVoice()
            }
        }
    }

    private var voiceURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("blackmold-gemini-voice.wav") }

    private func startVoice() {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        guard let recorder = try? AVAudioRecorder(url: voiceURL, settings: settings), recorder.record() else {
            error = "The microphone could not start."
            return
        }
        self.recorder = recorder
        recordingSince = Date()
    }

    private func finishVoice() {
        guard let recorder else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        recordingSince = nil
        guard duration > 0.4, let data = try? Data(contentsOf: voiceURL) else { return }
        try? FileManager.default.removeItem(at: voiceURL)
        attachments.removeAll { $0.kind == .voice }
        attachments.append(Attachment(kind: .voice, mimeType: "audio/wav", data: data, thumbnail: nil, duration: duration))
        send()
    }

    private func cancelVoice() {
        recorder?.stop()
        recorder = nil
        recordingSince = nil
    }

    // MARK: Live

    var canGoLive: Bool { hasKey }

    func startLive() {
        guard live == nil, let key = GeminiKey.load() else { return }
        // The newest plain Live model; translate, transcribe and thinking variants are for other jobs.
        let model = liveModels.first { $0.id.contains("live") && !["translate", "transcribe", "thinking"].contains(where: $0.id.contains) }?.id
            ?? liveModels.first?.id
            ?? "gemini-3.8-live"
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.error = "Blackmold needs microphone access for Gemini Live."
                    return
                }
                let session = GeminiLive()
                // What was said stays as a conversation, to read or carry on in text.
                session.onEnd = { [weak self, weak session] in
                    let transcript = session?.transcript ?? []
                    self?.turns += transcript
                    self?.composerEntrance = transcript.isEmpty
                    self?.live = nil
                }
                self.live = session
                session.start(key: key, model: model)
            }
        }
    }

    #if DEBUG
    func debugPretendKey() { hasKey = true }

    func debugLive() {
        let session = GeminiLive()
        session.onEnd = { [weak self] in
            self?.composerEntrance = true
            self?.live = nil
        }
        live = session
    }

    func debugThink() {
        turns = [GeminiTurn(role: .user, parts: [.text("What's a good name for a black notch app?")])]
        phase = .thinking(since: Date())
    }

    func debugAnswer() {
        turns = [
            GeminiTurn(role: .user, parts: [.text("What's a good name for a black notch app?")]),
            GeminiTurn(role: .model, parts: [.text("""
            A few ideas that fit a dark, minimal notch app:

            ## Short and dark
            * **Blackmold** – already a strong, memorable name.
            * **Umbra** – the darkest part of a shadow.
            * **Inkwell** – a pool of black at the top of the screen.

            ## Playful
            1. **Notchy**
            2. **Island** – a nod to the *Dynamic Island*.

            Use `Umbra` if you want something calm, or keep **Blackmold** for character.
            """)]),
        ]
        phase = .idle
        onAnswer?()
    }
    #endif
}

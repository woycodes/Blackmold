import BlackmoldKit
import SwiftUI

/// Gemini in the notch through the Gemini API: a page to ask from (type,
/// talk, share a photo, or talk live), its state on the closed notch, and
/// "Ask Gemini" in search.
@Observable
final class GeminiPlugin: BlackmoldPlugin {
    let gemini = GeminiChat()
    @ObservationIgnored private var host: PluginHost?
    /// The "Done" line under the closed notch, just before it opens on the answer.
    private var notice = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    private static let page = "gemini"

    init() {}

    func start(_ host: PluginHost) {
        self.host = host
        gemini.onAnswer = { [weak self] in self?.answered() }

        var page = PluginPage(id: Self.page, title: "Gemini", symbol: "sparkle", takesKeyboard: true,
                              height: { [weak self] in self?.pageHeight ?? NotchSize.pageHeight },
                              isPreferred: { [weak self] in
                                  guard let self else { return false }
                                  return self.gemini.live != nil || self.gemini.isThinking || self.notice
                              },
                              content: { [weak self] in
                                  if let self { GeminiPage(controller: self) }
                              })
        page.leftEar = { [weak self] in
            AnyView(GeminiSpinningLogo(spinning: self?.gemini.isThinking == true).padding(2))
        }
        page.rightEar = { [weak self] in AnyView(self.map { NewChatButton(plugin: $0) }) }
        host.addPage(page)

        host.addSearchAction(PluginSearchAction(label: "Ask Gemini", icon: { GeminiLogo() }) { [weak self] text in
            guard let self else { return }
            self.gemini.draft = text
            self.send()
        })
        observeActivity()
    }

    func stop() {
        noticeTask?.cancel()
        gemini.live?.end()
        host?.show(nil)
    }

    // MARK: What the page asks for

    /// The composer at the usual height; a conversation or the model list grows it.
    var pageHeight: CGFloat {
        gemini.hasKey && (gemini.showingModels || gemini.live == nil && gemini.hasConversation)
            ? NotchSize.tallPageHeight : NotchSize.pageHeight
    }

    /// Sends the question and gives the keyboard back, so the notch can close
    /// to the working ears once the pointer leaves.
    func send() {
        guard gemini.canSend else { return }
        withAnimation(Motion.notch) { gemini.send() }
        host?.endTyping()
    }

    func startLive() {
        host?.endTyping()
        gemini.startLive()
    }

    func newChat() {
        withAnimation(Motion.notch) { gemini.newChat() }
    }

    func beginTyping() { host?.beginTyping() }
    func endTyping() { host?.endTyping() }

    // MARK: The closed notch

    /// Keeps the ears in step with Gemini: working, in Live, or just done.
    private func observeActivity() {
        withObservationTracking {
            _ = (gemini.isThinking, gemini.live == nil, notice)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateActivity()
                self?.observeActivity()
            }
        }
        updateActivity()
    }

    private func updateActivity() {
        guard gemini.isThinking || gemini.live != nil || notice else {
            host?.show(nil)
            return
        }
        let done = notice
        let chat = gemini
        if done {
            host?.show(PluginActivity(priority: 30,
                                      left: { GeminiLeftEar(chat: chat, done: true) },
                                      right: { GeminiRightEar(chat: chat, done: true) },
                                      line: {
                                          Text("Done").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                      }))
        } else {
            host?.show(PluginActivity(priority: 30,
                                      left: { GeminiLeftEar(chat: chat, done: false) },
                                      right: { GeminiRightEar(chat: chat, done: false) }))
        }
    }

    /// Open on Gemini: the answer just grows in. Closed: "Done" for a moment,
    /// then the notch opens on the answer and stays until it has been visited.
    private func answered() {
        host?.tick()
        if host?.isOpen == true {
            host?.open(page: Self.page, untilVisited: false)
            return
        }
        noticeTask?.cancel()
        notice = true
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, !Task.isCancelled else { return }
            self.host?.open(page: Self.page, untilVisited: true)
            self.notice = false
        }
    }

    // MARK: Settings

    var settingsView: AnyView? { AnyView(GeminiSettings(chat: gemini)) }
}

/// New chat, in the right ear once there is a conversation to leave.
private struct NewChatButton: View {
    let plugin: GeminiPlugin

    var body: some View {
        let chat = plugin.gemini
        let shown = chat.hasConversation && chat.live == nil && chat.hasKey
        Button { plugin.newChat() } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.zoom)
        .help("New chat")
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.6)
        .allowsHitTesting(shown)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: shown)
    }
}

/// The Gemini API key and model.
private struct GeminiSettings: View {
    @Bindable var chat: GeminiChat
    @State private var key = ""
    @State private var problem: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chat.hasKey {
                HStack {
                    Text("API key saved in your keychain").foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) { chat.removeKey() }
                }
                Picker("Model", selection: $chat.modelID) {
                    ForEach(chat.models) { Text($0.name).tag($0.id) }
                }
            }
            HStack {
                SecureField(chat.hasKey ? "New API key" : "API key", text: $key)
                    .onSubmit(save)
                Button(chat.hasKey ? "Replace" : "Save", action: save)
                    .disabled(key.isEmpty || checking)
            }
            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            HStack(spacing: 4) {
                Text("Make a free key in Google AI Studio.").font(.callout).foregroundStyle(.secondary)
                Link("Get a key", destination: URL(string: "https://aistudio.google.com/apikey")!).font(.callout)
            }
        }
    }

    private func save() {
        checking = true
        problem = nil
        Task {
            problem = await chat.setKey(key)
            checking = false
            if problem == nil { key = "" }
        }
    }
}

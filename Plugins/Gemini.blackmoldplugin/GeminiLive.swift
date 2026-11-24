import BlackmoldKit
import AVFoundation
import Foundation
import os

/// A spoken conversation over the Gemini Live API.
///
/// The microphone goes up as 16 kHz 16-bit PCM over a WebSocket; Gemini's
/// voice comes back as 24 kHz PCM and plays through the same audio engine,
/// whose voice processing keeps Gemini from hearing itself.
@MainActor
@Observable
final class GeminiLive {
    enum Phase: Equatable {
        case connecting, listening, speaking, held
        case failed(String)
    }

    private(set) var phase: Phase = .connecting
    /// What Gemini is saying, as text, for the line under the glow.
    private(set) var caption = ""
    /// Both sides as text, turn by turn.
    private(set) var transcript: [GeminiTurn] = []
    /// 0...1, the louder of the two sides, for the glow.
    var level: Float { audio.level }

    var onEnd: (() -> Void)?

    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private let audio = LiveAudio()
    @ObservationIgnored private var captionDone = false

    func start(key: String, model: String) {
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        let socket = URLSession.shared.webSocketTask(with: components.url!)
        self.socket = socket
        socket.resume()
        send([
            "setup": [
                "model": "models/\(model)",
                "generationConfig": ["responseModalities": ["AUDIO"]],
                "inputAudioTranscription": [String: Any](),
                "outputAudioTranscription": [String: Any](),
                "systemInstruction": ["parts": [["text": "You are a friendly voice assistant. Keep replies brief and conversational."]]],
            ],
        ])
        receive()
    }

    func toggleHold() {
        if phase == .held {
            audio.isMuted = false
            phase = .listening
        } else if phase == .listening || phase == .speaking {
            audio.isMuted = true
            audio.stopPlayback()
            phase = .held
        }
    }

    func end() {
        audio.stop()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        onEnd?()
    }

    // MARK: Socket

    private func send(_ message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.socket != nil else { return }
                switch result {
                case .failure(let error):
                    self.fail(self.closeReason() ?? error.localizedDescription)
                case .success(let message):
                    let data: Data? = switch message {
                    case .data(let data): data
                    case .string(let text): text.data(using: .utf8)
                    @unknown default: nil
                    }
                    if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.handle(json)
                    }
                    self.receive()
                }
            }
        }
    }

    private func closeReason() -> String? {
        guard let data = socket?.closeReason, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    private func handle(_ message: [String: Any]) {
        if message["setupComplete"] != nil {
            do {
                try audio.start { [weak self] chunk in
                    Task { @MainActor in
                        self?.send(["realtimeInput": ["audio": ["data": chunk.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]]])
                    }
                }
                phase = .listening
            } catch {
                fail("The microphone could not start.")
            }
            return
        }
        if message["goAway"] != nil { fail("Gemini ended the session.") }
        guard let content = message["serverContent"] as? [String: Any] else { return }

        if content["interrupted"] as? Bool == true {
            audio.stopPlayback()
            if phase != .held { phase = .listening }
        }
        if let turn = content["modelTurn"] as? [String: Any], let parts = turn["parts"] as? [[String: Any]] {
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any],
                      let base64 = inline["data"] as? String, let pcm = Data(base64Encoded: base64) else { continue }
                guard phase != .held else { continue }
                audio.play(pcm)
                phase = .speaking
            }
        }
        if let heard = (content["inputTranscription"] as? [String: Any])?["text"] as? String {
            record(heard, as: .user)
        }
        if let said = (content["outputTranscription"] as? [String: Any])?["text"] as? String {
            if captionDone { caption = ""; captionDone = false }
            caption += said
            record(said, as: .model)
        }
        if content["turnComplete"] as? Bool == true {
            captionDone = true
            // Back to listening once the queued voice has played out.
            audio.whenPlaybackEnds { [weak self] in
                Task { @MainActor in
                    if self?.phase == .speaking { self?.phase = .listening }
                }
            }
        }
    }

    private func record(_ text: String, as role: GeminiTurn.Role) {
        if transcript.last?.role == role {
            transcript[transcript.count - 1].parts = [.text(transcript[transcript.count - 1].text + text)]
        } else {
            transcript.append(GeminiTurn(role: role, parts: [.text(text)]))
        }
    }

    private func fail(_ reason: String) {
        audio.stop()
        socket?.cancel()
        socket = nil
        phase = .failed(reason)
    }
}

/// Microphone in, Gemini's voice out, through one engine.
private final class LiveAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var running = false

    private struct Shared {
        var muted = false
        var level: Float = 0
        var queued = 0
    }
    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    var isMuted: Bool {
        get { shared.withLock { $0.muted } }
        set { shared.withLock { $0.muted = newValue } }
    }

    var level: Float {
        shared.withLock { state in
            state.level *= 0.9
            return state.level
        }
    }

    func start(onChunk: @escaping @Sendable (Data) -> Void) throws {
        let input = engine.inputNode
        // Echo cancellation: Gemini should not hear its own voice from the speakers.
        try? input.setVoiceProcessingEnabled(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFormat)

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: mono, to: sendFormat)
        input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !self.isMuted, let channel = buffer.floatChannelData?[0],
                  let first = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength) else { return }
            first.frameLength = buffer.frameLength
            first.floatChannelData![0].update(from: channel, count: Int(buffer.frameLength))
            self.meter(channel, count: Int(buffer.frameLength))

            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / mono.sampleRate) + 32
            guard let converter = self.converter,
                  let out = AVAudioPCMBuffer(pcmFormat: self.sendFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return first
            }
            guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }
            onChunk(Data(bytes: samples, count: Int(out.frameLength) * 2))
        }
        engine.prepare()
        try engine.start()
        player.play()
        running = true
    }

    /// 16-bit little-endian PCM at 24 kHz.
    func play(_ pcm: Data) {
        guard running else { return }
        let count = pcm.count / 2
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let out = buffer.floatChannelData![0]
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<count { out[i] = Float(Int16(littleEndian: samples[i])) / 32768 }
        }
        meter(out, count: count)
        shared.withLock { $0.queued += 1 }
        player.scheduleBuffer(buffer) { [weak self] in
            self?.shared.withLock { $0.queued -= 1 }
        }
    }

    func whenPlaybackEnds(_ done: @escaping @Sendable () -> Void) {
        DispatchQueue.global().async { [weak self] in
            while let self, self.running, self.shared.withLock({ $0.queued }) > 0 { usleep(50_000) }
            done()
        }
    }

    func stopPlayback() {
        guard running else { return }
        player.stop()
        shared.withLock { $0.queued = 0 }
        player.play()
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
    }

    private func meter(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var energy: Float = 0
        for i in 0..<count { energy += samples[i] * samples[i] }
        let rms = (energy / Float(count)).squareRoot()
        let value = min(1, rms * 6)
        shared.withLock { $0.level = max($0.level, value) }
    }
}

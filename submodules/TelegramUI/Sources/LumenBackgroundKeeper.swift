import Foundation
import AVFAudio
import TelegramCore

// MARK: Lumen

/// Keeps the app running while it is in the background by playing silence, so the connection
/// stays up and new messages arrive (and are shown as local notifications). Sideloaded builds
/// get no push from Telegram's servers, so without this the app sleeps ~30 s after closing.
///
/// The session mixes with other audio, so music in other apps keeps playing. Telegram's own
/// playback takes the session over: SharedWakeupManager stops the keeper while it plays.
final class LumenBackgroundKeeper {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []

    /// Called on the main queue when the system stopped the audio (interruption, reset).
    var stateChanged: (() -> Void)?

    private(set) var isRunning = false

    init() {
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, self.isRunning else {
                return
            }
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if rawType == AVAudioSession.InterruptionType.began.rawValue {
                Logger.shared.log("Lumen", "background keeper interrupted")
                self.tearDown()
                self.stateChanged?()
            }
        }))
        self.observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self, self.isRunning else {
                return
            }
            self.tearDown()
            self.stateChanged?()
        }))
        self.observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, self.isRunning, let engine = notification.object as? AVAudioEngine, engine === self.engine else {
                return
            }
            // The output route changed (headphones, Bluetooth): the engine stopped itself.
            self.tearDown()
            self.start()
        }))
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.tearDown()
    }

    func start() {
        if self.isRunning {
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Logger.shared.log("Lumen", "background keeper: audio session failed: \(error)")
            return
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else {
            return
        }
        buffer.frameLength = buffer.frameCapacity
        if let channels = buffer.floatChannelData {
            for index in 0 ..< Int(buffer.frameLength) {
                channels[0][index] = 0.0
            }
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            Logger.shared.log("Lumen", "background keeper: engine failed: \(error)")
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        self.engine = engine
        self.player = player
        self.isRunning = true
        Logger.shared.log("Lumen", "background keeper started")
    }

    /// `deactivate` hands the audio session back (only when nothing else in the app uses it).
    func stop(deactivate: Bool) {
        if !self.isRunning {
            return
        }
        self.tearDown()
        if deactivate {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        Logger.shared.log("Lumen", "background keeper stopped")
    }

    private func tearDown() {
        self.player?.stop()
        self.engine?.stop()
        self.player = nil
        self.engine = nil
        self.isRunning = false
    }
}

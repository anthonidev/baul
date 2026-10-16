import AppKit
import BaulCore
import BaulPersistence
import BaulSystem
import BaulUI
import KeyboardShortcuts
import Observation
import os
import SwiftUI

/// Raíz de composición: crea todas las piezas, las conecta y arranca la captura.
@Observable
final class AppModel {
    let panelController: PanelController
    let settingsModel: SettingsModel

    /// Estado de pausa, persistido entre reinicios.
    private(set) var pause: PauseState {
        didSet { Preferences.pause = pause }
    }

    var isPaused: Bool { pause.isPaused(at: .now) }

    @ObservationIgnored private let store: SQLiteLibraryStore
    @ObservationIgnored private let images: FileImageStore
    @ObservationIgnored private let recorder: ClipRecorder
    @ObservationIgnored private let clipboard: ClipboardController
    @ObservationIgnored private var monitor: PasteboardMonitor?
    @ObservationIgnored private var excludedBundleIDs: Set<String> = []
    @ObservationIgnored private var backgroundTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pauseExpiryTask: Task<Void, Never>?
    @ObservationIgnored private let onboarding = OnboardingWindowController()
    @ObservationIgnored private let logger = Logger(subsystem: "dev.tonis.baul", category: "app")

    init() throws {
        let support = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Baul", directoryHint: .isDirectory)
        let database = try AppDatabase.onDisk(at: support.appending(path: "baul.sqlite"))
        store = SQLiteLibraryStore(database: database)
        images = try FileImageStore(directory: support.appending(path: "media", directoryHint: .isDirectory))
        recorder = ClipRecorder(store: store, images: images)

        let panelModel = PanelViewModel(store: store, images: images)
        panelController = PanelController(model: panelModel)
        settingsModel = SettingsModel(store: store, images: images, databaseSize: database.fileSize)
        clipboard = ClipboardController(store: store, images: images, panel: panelController)
        panelModel.actions = clipboard
        pause = Preferences.pause
    }

    func start() {
        let monitor = PasteboardMonitor { [weak self] item in self?.capture(item) }
        self.monitor = monitor
        clipboard.monitor = monitor
        clipboard.onMissingAccessibility = { [weak self] in self?.showOnboarding() }
        monitor.start()

        panelController.model.start()
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.panelController.toggle()
        }

        backgroundTasks.append(Task { [weak self, store] in
            do {
                for try await apps in store.observeExcludedApps() {
                    self?.excludedBundleIDs = Set(apps.map(\.bundleID))
                }
            } catch {
                self?.logger.error("No se pudieron leer las apps excluidas: \(error.localizedDescription, privacy: .public)")
            }
        })
        backgroundTasks.append(Task { [weak self] in
            // Limpieza del historial al arrancar y luego cada hora.
            while !Task.isCancelled {
                await self?.purgeOldHistory()
                try? await Task.sleep(for: .seconds(3_600))
            }
        })
        schedulePauseExpiry()

        if !Preferences.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    // MARK: - Captura

    private var policy: CapturePolicy {
        CapturePolicy(excludedBundleIDs: excludedBundleIDs, pause: pause)
    }

    private func capture(_ item: CapturedItem) {
        let policy = policy
        Task {
            do {
                let result = try await recorder.record(item, policy: policy)
                if case .recorded(.inserted(let clip)) = result, case .link(let url, nil) = clip.content {
                    await fetchTitle(for: clip.id, url: url)
                }
            } catch {
                logger.error("No se pudo guardar lo copiado: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fetchTitle(for clipID: ClipID, url: URL) async {
        guard let title = await LinkTitleFetcher.title(for: url) else { return }
        try? await store.setLinkTitle(title, for: clipID)
    }

    private func purgeOldHistory() async {
        do {
            let cutoff = RetentionPolicy.standard.cutoff(now: .now)
            let orphans = try await store.purgeHistory(copiedBefore: cutoff)
            await images.remove(hashes: orphans)
            if !orphans.isEmpty { logger.info("Limpieza: \(orphans.count) imágenes borradas") }
        } catch {
            logger.error("Falló la limpieza del historial: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pausa

    func pause(for duration: Duration?) {
        pause = .paused(until: duration.map { Date.now.addingTimeInterval(TimeInterval($0.components.seconds)) })
        schedulePauseExpiry()
    }

    func resume() {
        pause = .active
        schedulePauseExpiry()
    }

    /// Vuelve a `.active` cuando vence la pausa, para que el menú lo refleje.
    private func schedulePauseExpiry() {
        pauseExpiryTask?.cancel()
        guard case .paused(let until?) = pause else { return }
        pauseExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(until.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.pause = .active
        }
    }

    // MARK: - Ventanas

    func showOnboarding() {
        onboarding.show {
            Preferences.hasCompletedOnboarding = true
        }
    }

    func togglePanel() {
        panelController.toggle()
    }
}

/// Preferencias simples en UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    static var pause: PauseState {
        get {
            guard let data = defaults.data(forKey: "pause"),
                  let state = try? JSONDecoder().decode(PauseState.self, from: data)
            else { return .active }
            return state
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "pause") }
    }
}

/// Ventana de bienvenida (AppKit, porque la app no tiene ventana principal).
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(onFinish: @escaping () -> Void) {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
                onFinish()
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.title = "Bienvenida"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

//
//  BetterEmojiPickerApp.swift
//  BetterEmojiPicker
//
//  The main entry point for the Better Emoji Picker (BEP) application.
//  This sets up the menu bar app, global hotkey, and picker window.
//

import SwiftUI
import AppKit

/// The main application structure.
///
/// BEP runs as a menu bar app (no dock icon) that:
/// 1. Shows a menu bar icon with status and preferences
/// 2. Registers a global hotkey (Ctrl+Cmd+Space)
/// 3. Shows/hides the floating emoji picker when the hotkey is pressed
///
/// SwiftUI notes for newcomers:
/// - `@main` marks this as the application entry point
/// - `@NSApplicationDelegateAdaptor` connects SwiftUI to AppKit's delegate pattern
/// - `MenuBarExtra` creates a menu bar item (macOS 13+)
@main
struct BetterEmojiPickerApp: App {

    /// The app delegate handles low-level app lifecycle events.
    /// We need this for registering global hotkeys (not possible in pure SwiftUI).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar item with dropdown menu
        #if DEBUG
        MenuBarExtra("🚧 BEP", systemImage: "hammer.fill") {
            MenuBarView(appDelegate: appDelegate)
        }
        #else
        MenuBarExtra("BEP", systemImage: "face.smiling") {
            MenuBarView(appDelegate: appDelegate)
        }
        #endif

        // Native Settings window (opened via SettingsLink or Cmd+,)
        Settings {
            SettingsView(
                settingsService: SettingsService.shared,
                emojiStore: appDelegate.emojiStore
            )
        }
    }
}

// MARK: - Menu Bar View

/// The dropdown menu shown when clicking the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status section
            statusSection

            Divider()

            // Actions
            Button("Show Emoji Picker") {
                appDelegate.showPicker()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("Setup Assistant...") {
                appDelegate.showSetupWizard()
            }

            Divider()

            // App info
            Text("Shortcut: ⌃⌘Space")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Quit button
            Button("Quit BEP") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    /// Status section showing permission and hotkey status
    @ViewBuilder
    private var statusSection: some View {
        if appDelegate.hasAccessibilityPermission {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Button {
                appDelegate.showSetupWizard()
            } label: {
                Label("Setup Required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - App Delegate

/// Handles application lifecycle and coordinates the picker system.
///
/// Why an AppDelegate?
/// - SwiftUI's declarative approach doesn't support global hotkey registration
/// - We need to run code at specific app lifecycle points
/// - AppKit's NSApplicationDelegate provides these hooks
///
/// This class:
/// 1. Initializes all services (EmojiStore, HotkeyService, PasteService)
/// 2. Registers the global hotkey
/// 3. Creates and manages the floating picker panel
/// 4. Coordinates emoji insertion
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // MARK: - Published State

    /// Whether we have accessibility permission (for showing status in menu)
    @Published var hasAccessibilityPermission: Bool = false

    /// Whether the picker is pinned (stays open on click-away)
    @Published var isPinned: Bool = false

    // MARK: - Services

    /// The emoji data store (internal for SettingsView access)
    /// Initialized in init() so it's available when Settings scene body is evaluated
    private(set) var emojiStore: EmojiStore

    /// The picker view model (internal for PickerContentView access)
    private(set) var pickerViewModel: PickerViewModel

    /// The setup wizard view model
    private var setupViewModel: SetupViewModel?

    // MARK: - Initialization

    override init() {
        // Initialize services that need to be available immediately for Settings scene
        emojiStore = EmojiStore()
        pickerViewModel = PickerViewModel(emojiStore: emojiStore)
        super.init()
    }

    /// The floating panel containing the picker
    private var pickerPanel: FloatingPanel?

    /// The setup wizard window
    private var setupWindow: NSWindow?

    /// The app that was frontmost before we showed the picker
    /// Used to return focus for emoji insertion
    private var previousApp: NSRunningApplication?

    /// Global mouse monitor for click-away-to-close
    private var globalMouseMonitor: Any?

    // MARK: - App Lifecycle

    /// Called when the application finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 BEP: Application launched")

        // Initialize services
        initializeServices()

        // Check and request permissions
        checkPermissions()

        // Register global hotkey
        registerHotkey()

        // Hide dock icon (should already be set via Info.plist, but ensure it)
        NSApp.setActivationPolicy(.accessory)

        // Show setup wizard on first run
        if !SetupViewModel.hasCompletedSetup() {
            showSetupWizard()
        }
    }

    /// Called when the application is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 BEP: Application terminating")

        // Unregister hotkey
        HotkeyService.shared.unregisterAll()
    }

    /// Initializes remaining services not needed for Settings scene.
    private func initializeServices() {
        // Create the setup view model (only needed when wizard is shown)
        setupViewModel = SetupViewModel()
    }

    // MARK: - Permissions

    /// Checks current permission status.
    private func checkPermissions() {
        hasAccessibilityPermission = PasteService.shared.hasPermission()

        if !hasAccessibilityPermission {
            print("⚠️ BEP: Accessibility permission not granted")
        }
    }

    /// Requests accessibility permission from the user.
    func requestAccessibilityPermission() {
        PasteService.shared.requestPermission()

        // Check again after a delay (permission granted async)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkPermissions()
        }
    }

    // MARK: - Hotkey Registration

    /// Registers the global hotkey (Ctrl+Cmd+Space).
    private func registerHotkey() {
        let success = HotkeyService.shared.register(
            keyCode: KeyCode.space,
            modifiers: ModifierFlags.controlCommand,
            handler: { [weak self] in
                Task { @MainActor in
                    self?.togglePicker()
                }
            }
        )

        if !success {
            print("⚠️ BEP: Failed to register hotkey. The system shortcut may still be enabled.")
        }
    }

    // MARK: - Picker Management

    /// Shows the emoji picker.
    func showPicker() {
        // Remember the frontmost app so we can return focus for pasting
        previousApp = NSWorkspace.shared.frontmostApplication

        // Create panel if needed
        if pickerPanel == nil {
            createPickerPanel()
        }

        // Position and show – always centred on the current screen.
        pickerPanel?.positionCenteredOnScreen()
        pickerPanel?.orderFrontRegardless()
        pickerPanel?.makeKey()

        // Start monitoring for clicks outside the picker
        startClickAwayMonitor()

        // Notify view model
        pickerViewModel.onShow()
    }

    /// Hides the emoji picker.
    func hidePicker() {
        pickerPanel?.orderOut(nil)
        pickerViewModel.onHide()
        stopClickAwayMonitor()

        // Reset pin state when hiding (user explicitly dismissed or clicked away)
        isPinned = false
    }

    /// Toggles the emoji picker visibility.
    func togglePicker() {
        if pickerPanel?.isVisible == true {
            if isPinned && !pickerPanel!.isKeyWindow {
                // If pinned but not focused, refocus instead of hiding
                pickerPanel?.makeKey()
            } else {
                // If not pinned, or already focused - close it
                hidePicker()
            }
        } else {
            showPicker()
        }
    }

    /// Toggles the pinned state of the picker.
    func togglePin() {
        isPinned.toggle()
    }

    // MARK: - Click-Away Monitor

    /// Starts monitoring for mouse clicks outside the picker window.
    private func startClickAwayMonitor() {
        stopClickAwayMonitor()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  let panel = self.pickerPanel,
                  panel.isVisible else {
                return
            }

            // If pinned, don't close on click-away
            if self.isPinned {
                return
            }

            // Check if the click is outside the picker panel
            let screenLocation = NSEvent.mouseLocation

            // Get the panel frame in screen coordinates
            let panelFrame = panel.frame

            if !panelFrame.contains(screenLocation) {
                Task { @MainActor in
                    self.hidePicker()
                }
            }
        }
    }

    /// Stops the click-away monitor.
    private func stopClickAwayMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    /// Creates the floating picker panel.
    private func createPickerPanel() {
        pickerPanel = FloatingPanel {
            PickerContentView(appDelegate: self)
        }
    }

    // MARK: - Setup Wizard

    /// Shows the setup wizard window.
    func showSetupWizard() {
        // Reset the view model for a fresh wizard experience
        let viewModel = SetupViewModel()
        setupViewModel = viewModel

        // Always recreate the window to ensure fresh state
        let wizardView = SetupWizardView(viewModel: viewModel) { [weak self] in
            self?.closeSetupWizard()
            // Refresh permission status after setup
            self?.checkPermissions()
        }

        setupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        setupWindow?.contentView = NSHostingView(rootView: wizardView)
        setupWindow?.title = "Setup BEP"
        setupWindow?.isReleasedWhenClosed = false
        setupWindow?.center()

        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the setup wizard window.
    private func closeSetupWizard() {
        setupWindow?.close()
    }

    // MARK: - Emoji Insertion

    /// Inserts an emoji into the currently focused application.
    func insertEmoji(_ emoji: Emoji, keepOpen: Bool = true) {
        // Check permission
        guard PasteService.shared.hasPermission() else {
            print("⚠️ BEP: Cannot insert emoji - no accessibility permission")
            requestAccessibilityPermission()
            return
        }

        // Get the target process ID before we do anything
        let targetPID = previousApp?.processIdentifier

        // Resign key status from our panel so paste doesn't go to our search field
        pickerPanel?.resignKey()

        // Activate the previous app
        previousApp?.activate(options: .activateIgnoringOtherApps)

        // Paste with target process ID for reliable delivery
        DispatchQueue.main.async { [weak self] in
            let success = PasteService.shared.paste(text: emoji.emoji, targetPID: targetPID)

            if success {
                print("✅ BEP: Inserted \(emoji.emoji)")
                if keepOpen {
                    // Mark that we just inserted an emoji - enables backspace forwarding
                    self?.pickerViewModel.markEmojiInserted()
                } else {
                    // If caller requested the picker to close after insert, hide it now
                    self?.hidePicker()
                }
            } else {
                print("⚠️ BEP: Failed to insert emoji")
            }

            // Restore key status after a brief delay only when keeping open
            if keepOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    self?.pickerPanel?.makeKey()
                }
            }
        }
    }

    // MARK: - Emoji Copy

    /// Copies an emoji to the clipboard without pasting.
    func copyEmoji(_ emoji: Emoji) {
        PasteService.shared.copyToClipboard(text: emoji.emoji)
        print("📋 BEP: Copied \(emoji.emoji) to clipboard")
    }

    // MARK: - Keystroke Forwarding

    /// Forwards a backspace keystroke to the target application.
    /// Used to "undo" a just-inserted emoji.
    func forwardBackspace() {
        guard PasteService.shared.hasPermission() else {
            print("⚠️ BEP: Cannot forward backspace - no accessibility permission")
            return
        }

        let targetPID = previousApp?.processIdentifier

        // Resign key status so the event goes to the target app
        pickerPanel?.resignKey()
        previousApp?.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.async { [weak self] in
            PasteService.shared.sendBackspace(to: targetPID)

            // Restore key status after backspace is processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self?.pickerPanel?.makeKey()
            }
        }
    }

    /// Forwards a Cmd+Z (undo) keystroke to the target application.
    /// Used to undo a just-inserted emoji.
    func forwardUndo() {
        guard PasteService.shared.hasPermission() else {
            print("⚠️ BEP: Cannot forward undo - no accessibility permission")
            return
        }

        let targetPID = previousApp?.processIdentifier

        // Resign key status so the event goes to the target app
        pickerPanel?.resignKey()
        previousApp?.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.async { [weak self] in
            PasteService.shared.sendUndo(to: targetPID)

            // Restore key status after undo is processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self?.pickerPanel?.makeKey()
            }
        }
    }
}

// MARK: - Picker Content View

/// A wrapper view that observes the AppDelegate for pin state changes.
/// This is needed because PickerView needs to react to isPinned changes.
struct PickerContentView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        PickerView(
            viewModel: appDelegate.pickerViewModel,
            isPinned: appDelegate.isPinned,
            onInsertEmoji: { emoji, keepOpen in
                appDelegate.insertEmoji(emoji, keepOpen: keepOpen)
            },
            onCopyEmoji: { emoji in
                appDelegate.copyEmoji(emoji)
            },
            onTogglePin: {
                appDelegate.togglePin()
            },
            onDismiss: {
                appDelegate.hidePicker()
            },
            onForwardBackspace: {
                appDelegate.forwardBackspace()
            },
            onForwardUndo: {
                appDelegate.forwardUndo()
            }
        )
    }
}

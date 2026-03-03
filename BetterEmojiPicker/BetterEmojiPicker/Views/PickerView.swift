//
//  PickerView.swift
//  BetterEmojiPicker
//
//  The main emoji picker view combining search field and emoji grid.
//

import SwiftUI
import AppKit

/// The main emoji picker interface.
struct PickerView: View {

    @ObservedObject var viewModel: PickerViewModel

    let isPinned: Bool
    let onInsertEmoji: (Emoji, Bool) -> Void
    let onCopyEmoji: (Emoji) -> Void
    let onTogglePin: () -> Void
    let onDismiss: () -> Void
    let onForwardBackspace: () -> Void
    let onForwardUndo: () -> Void

    @State private var showCopiedToast = false

    private let panelWidth: CGFloat = 400
    private let panelHeight: CGFloat = 320
    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Search bar with pin button
                HStack(spacing: 8) {
                    searchField

                    pinButton
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                EmojiGridView(
                    sections: viewModel.sections,
                    displayedEmojis: viewModel.displayedEmojis,
                    selectedIndex: viewModel.selectedIndex,
                    scrollToTopTrigger: viewModel.scrollToTopTrigger,
                    onSelect: handleEmojiClick
                )
            }

            // Toast overlay - positioned at bottom
            if showCopiedToast {
                VStack {
                    Spacer()
                    ToastView(message: "Copied!")
                        .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Use NSEvent-based keyboard handling for macOS 13 compatibility
        .background(
            KeyboardEventHandler(
                onUpArrow: { viewModel.moveUp() },
                onDownArrow: { viewModel.moveDown() },
                onLeftArrow: { viewModel.moveLeft() },
                onRightArrow: { viewModel.moveRight() },
                onReturn: { handleEnterKey() },
                onEscape: { onDismiss() },
                onCopy: { handleCopyKey() },
                onBackspace: { handleBackspaceKey() },
                onUndo: { handleUndoKey() }
            )
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            FocusableTextField(
                text: $viewModel.searchQuery,
                placeholder: "Search emojis...",
                onSubmit: { handleEnterKey() }
            )
            .frame(height: 20)

            if !viewModel.searchQuery.isEmpty {
                Button(action: { viewModel.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundColor(isPinned ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin (closes on click away)" : "Pin (stays open on click away)")
    }

    private func handleEnterKey() {
        if let emoji = viewModel.confirmSelection() {
            onInsertEmoji(emoji, false)
        }
    }

    private func handleEmojiClick(_ emoji: Emoji) {
        let selectedEmoji = viewModel.selectEmoji(emoji)
        onInsertEmoji(selectedEmoji, true)
    }

    private func handleCopyKey() {
        guard let emoji = viewModel.selectedEmoji else { return }
        viewModel.recordUsage(of: emoji)
        onCopyEmoji(emoji)

        // Show toast briefly
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopiedToast = true
        }

        // Hide toast and dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopiedToast = false
            }
            // Dismiss picker after toast fades
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onDismiss()
            }
        }
    }

    /// Handles backspace key: forwards to target app if last edit was emoji insert.
    private func handleBackspaceKey() -> Bool {
        // Only forward backspace if last edit was emoji insert
        guard viewModel.justInsertedEmoji else {
            return false  // Let backspace pass through to search field
        }

        // Don't clear the flag - keep forwarding until user types in filter
        onForwardBackspace()
        return true
    }

    /// Handles Cmd+Z: forwards undo to target app if last edit was emoji insert.
    private func handleUndoKey() -> Bool {
        // Only forward undo if last edit was emoji insert
        guard viewModel.justInsertedEmoji else {
            return false  // Let Cmd+Z pass through (e.g., undo in search field)
        }

        // Don't clear the flag - keep forwarding until user types in filter
        onForwardUndo()
        return true
    }
}

// MARK: - Keyboard Event Handler

/// A SwiftUI view that monitors keyboard events using NSEvent.
/// This provides macOS 13.0 compatibility since onKeyPress requires macOS 14.0+.
struct KeyboardEventHandler: NSViewRepresentable {

    let onUpArrow: () -> Void
    let onDownArrow: () -> Void
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void
    let onCopy: () -> Void
    let onBackspace: () -> Bool  // Returns true if backspace was handled (forwarded to target app)
    let onUndo: () -> Bool       // Returns true if Cmd+Z was handled (forwarded to target app)

    func makeNSView(context: Context) -> KeyboardHandlerView {
        let view = KeyboardHandlerView()
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.onCopy = onCopy
        view.onBackspace = onBackspace
        view.onUndo = onUndo
        return view
    }

    func updateNSView(_ nsView: KeyboardHandlerView, context: Context) {
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        nsView.onCopy = onCopy
        nsView.onBackspace = onBackspace
        nsView.onUndo = onUndo
    }
}

/// Custom NSView that captures keyboard events.
class KeyboardHandlerView: NSView {

    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCopy: (() -> Void)?
    var onBackspace: (() -> Bool)?  // Returns true if handled (forwarded to target app)
    var onUndo: (() -> Bool)?       // Returns true if handled (forwarded to target app)

    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitor()
    }

    private func setupMonitor() {
        // Monitor keyboard events locally (when our window has focus)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check for Cmd+C (copy)
            if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                self.onCopy?()
                return nil
            }

            // Check for Cmd+Z (undo) - conditionally forward to target app
            if event.keyCode == 6 && event.modifierFlags.contains(.command) {
                if let handler = self.onUndo, handler() {
                    return nil  // Consumed - forwarded to target app
                }
                return event  // Let it pass through
            }

            // Check for special keys
            switch event.keyCode {
            case 126: // Up arrow
                self.onUpArrow?()
                return nil // Consume the event

            case 125: // Down arrow
                self.onDownArrow?()
                return nil

            case 123: // Left arrow
                self.onLeftArrow?()
                return nil

            case 124: // Right arrow
                self.onRightArrow?()
                return nil

            case 36: // Return
                self.onReturn?()
                return nil

            case 53: // Escape
                self.onEscape?()
                return nil

            case 51: // Backspace
                if let handler = self.onBackspace, handler() {
                    return nil  // Consumed - forwarded to target app
                }
                return event  // Let it pass to search field

            default:
                return event // Let other keys pass through
            }
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

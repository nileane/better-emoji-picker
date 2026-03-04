//
//  FloatingPanel.swift
//  BetterEmojiPicker
//
//  A custom NSPanel subclass that provides a floating, non-activating window.
//

import AppKit
import SwiftUI

/// A floating panel window that doesn't steal focus from other applications.
class FloatingPanel: NSPanel {

    init<Content: View>(
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 400, height: 320),
        @ViewBuilder content: () -> Content
    ) {
        // Remove .titled to hide the title bar and window buttons entirely
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        self.contentView = NSHostingView(rootView: content())
    }

    private func configurePanel() {
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        // Allow panel to receive key events
        self.becomesKeyOnlyIfNeeded = false  // Changed: always become key when shown

        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.animationBehavior = .utilityWindow

        // match the SwiftUI corner radius so the underlying window
        // itself is clipped. this keeps the panel shape consistent when
        // dragging or when shadows extend.
        if let view = self.contentView {
            view.wantsLayer = true
            view.layer?.cornerRadius = 25
            view.layer?.masksToBounds = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func positionCenteredOnScreen() {
        let mouseLocation = NSEvent.mouseLocation

        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        let screenFrame = screen.visibleFrame

        let originX = screenFrame.minX + (screenFrame.width - self.frame.width) / 2

        // shift up by 10% of the screen’s height so the panel sits slightly above
        // exact centre (better visual balance when typing at the top of the screen)
        let verticalOffset = screenFrame.height * 0.1
        var originY = screenFrame.minY + (screenFrame.height - self.frame.height) / 2 + verticalOffset

        // ensure we don’t push the panel off the top of the visible frame
        if originY + self.frame.height > screenFrame.maxY {
            originY = screenFrame.maxY - self.frame.height - 10
        }

        self.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

#if os(macOS)
    import Foundation
    import Library
    import Shows

    /// The single dispatcher of live commands (keys now, pedals and MIDI in phase 6).
    public extension LiveSession {
        /// Handles `command`. Returns false when it does not apply right now.
        @discardableResult
        func dispatch(_ command: LiveCommand) -> Bool {
            guard !isEnding else { return false }
            notice = nil
            if overlay == .endConfirm, command != .endShow {
                return false
            }
            switch command.scope {
            case .show:
                guard let action = command.showAction else { return false }
                if action == .playNextRequest, queuedRequests.isEmpty {
                    notice = "No requests queued."
                    return true
                }
                perform(action)
            case .viewport:
                dispatchViewport(command)
            case .chrome:
                dispatchChrome(command)
            }
            return true
        }

        private func dispatchViewport(_ command: LiveCommand) {
            switch command {
            case .scrollPageDown: pageDown()
            case .scrollPageUp: pageUp()
            case .toggleAutoScroll: toggleAutoScroll()
            case .scrollFaster: nudgeScrollSpeed(faster: true)
            case .scrollSlower: nudgeScrollSpeed(faster: false)
            case .restartScroll: restartScroll()
            case .toggleCollapseRepeats: toggleCollapseRepeats()
            default: dispatchZoom(command)
            }
        }

        private func dispatchZoom(_ command: LiveCommand) {
            switch command {
            case .zoomIn: zoom(1)
            case .zoomOut: zoom(-1)
            case .resetZoom: zoom(0)
            case .cycleColumns: cycleColumns()
            default: break
            }
        }

        private func dispatchChrome(_ command: LiveCommand) {
            switch command {
            case .openSearch:
                openSearch()
            case .toggleRequests:
                showsRequests.toggle()
            case .toggleSidebar:
                showsDrawer.toggle()
            case .endShow:
                overlay = overlay == .endConfirm ? nil : .endConfirm
            default:
                break
            }
        }

        internal func openSearch() {
            search.reset()
            overlay = .search
        }

        /// Esc: closes the topmost overlay or panel. Returns false when nothing was open.
        @discardableResult
        func dismissTopmost() -> Bool {
            if overlay != nil {
                overlay = nil
                return true
            }
            if showsDrawer {
                showsDrawer = false
                return true
            }
            if showsRequests {
                showsRequests = false
                return true
            }
            return false
        }

        // MARK: Search actions

        /// What the search overlay does with the selected song.
        enum SearchAction: Sendable, CaseIterable {
            case playNow
            case addRequest
            case insertNext

            var title: String {
                switch self {
                case .playNow: "Play Now"
                case .addRequest: "Add to Requests"
                case .insertNext: "Insert Next"
                }
            }
        }

        /// Applies `action` to `song` and closes the overlay (back at the same scroll
        /// position: the scroller is untouched unless the current song changes).
        func searchAction(_ action: SearchAction, song: SongID) {
            overlay = nil
            switch action {
            case .playNow: perform(.playNow(song))
            case .addRequest: perform(.addRequest(song, note: nil))
            case .insertNext: perform(.insertNext(song))
            }
        }
    }
#endif

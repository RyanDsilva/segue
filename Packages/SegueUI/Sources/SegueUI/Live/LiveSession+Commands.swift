#if os(macOS)
    import Foundation
    import Library
    import Services
    import Shows

    /// The single dispatcher of live commands (keys now, MIDI in phase 6).
    public extension LiveSession {
        /// Handles `command`. Returns false when it does not apply right now.
        @discardableResult
        func dispatch(_ command: LiveCommand) -> Bool {
            guard !isEnding else { return false }
            notice = nil
            if overlay == .endConfirm, command != .endShow {
                return false
            }
            // The key help never traps the performer: any other command closes it and
            // still runs (A39).
            if overlay == .keys, command != .showKeys {
                overlay = nil
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
            recordStageFeature(command)
            return true
        }

        /// Row 8 for the stage aids (WS3 spec 5); auto-scroll also counts toward
        /// `Segue.Show.ended`'s `segue.autoScrollUsed`.
        private func recordStageFeature(_ command: LiveCommand) {
            let feature: FeatureKey? = switch command {
            case .toggleAutoScroll: .autoScroll
            case .openSearch: .stageSearch
            case .playNextRequest, .toggleRequests: .requests
            case .cycleColumns: .columnsCycle
            case .resetZoom, .zoomIn, .zoomOut: .stageZoom
            default: nil
            }
            if command == .toggleAutoScroll {
                autoScrollUsed = true
            }
            if let feature {
                services.record(.featureUsed(feature, .stage))
            }
        }

        private func dispatchViewport(_ command: LiveCommand) {
            switch command {
            case .scrollPageDown: pageDown()
            case .scrollPageUp: pageUp()
            case .pageForward: pageForward()
            case .pageBack: pageBack()
            case .toggleAutoScroll: toggleAutoScroll()
            case .scrollFaster: nudgeScrollSpeed(faster: true)
            case .scrollSlower: nudgeScrollSpeed(faster: false)
            case .restartScroll: restartScroll()
            case .toggleBassNotes: toggleBassNotes()
            default: dispatchZoom(command)
            }
        }

        private func dispatchZoom(_ command: LiveCommand) {
            if let index = command.jumpIndex {
                jump(toPass: index)
                return
            }
            if command == .toggleLoop {
                toggleLoop()
                return
            }
            if command == .togglePlayAlong {
                togglePlayAlong()
                return
            }
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
            case .showKeys:
                overlay = overlay == .keys ? nil : .keys
            case .toggleMetronome, .toggleMetronomeClick:
                dispatchMetronome(command)
            case .endShow:
                if overlay == .endConfirm {
                    cancelEnd()
                } else {
                    overlay = .endConfirm
                }
            default:
                break
            }
        }

        /// Cmd-W, Cmd-Q (`quitting`) or a quit from the Dock while on stage: always through
        /// the end confirmation, never a silent close.
        func requestEnd(quitting: Bool) {
            guard !isEnding else { return }
            notice = nil
            quitsAfterEnding = quitsAfterEnding || quitting
            overlay = .endConfirm
        }

        /// "Keep Playing": closes the end confirmation (and forgets a pending quit).
        func cancelEnd() {
            quitsAfterEnding = false
            if overlay == .endConfirm {
                overlay = nil
            }
        }

        internal func openSearch() {
            search.reset()
            overlay = .search
        }

        /// Esc: closes the topmost overlay or panel. Returns false when nothing was open.
        @discardableResult
        func dismissTopmost() -> Bool {
            if overlay == .endConfirm {
                cancelEnd()
                return true
            }
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
        /// "Add to Requests" first asks for an optional note (`commitRequest()`). A song
        /// already in the show is refused first, in the overlay (R102).
        func searchAction(_ action: SearchAction, song: SongID) {
            if refuseRepeat(action, song: song) {
                return
            }
            if action == .addRequest,
               let record = search.results.first(where: { $0.id == song })
            {
                search.beginRequest(record)
                return
            }
            overlay = nil
            services.record(.featureUsed(action == .playNow ? .playNow : .requests, .stage))
            switch action {
            case .playNow: perform(.playNow(song))
            case .addRequest: perform(.addRequest(song, note: nil))
            case .insertNext: perform(.insertNext(song))
            }
        }

        /// Return in the results: acts on the selected result, or, while the results still
        /// belong to an earlier query (typing outran the search), on the first result of the
        /// query as typed once it lands.
        func submitSearch(_ action: SearchAction) {
            search.submit { [weak self] song in
                guard let self, overlay == .search else { return }
                searchAction(action, song: song.id)
            }
        }

        /// Adds the song waiting for its note to the requests (Return; a blank note is
        /// skipped) and closes the overlay.
        func commitRequest() {
            guard let song = search.requesting else { return }
            let note = search.trimmedNote
            overlay = nil
            search.cancelRequest()
            perform(.addRequest(song.id, note: note))
        }
    }
#endif

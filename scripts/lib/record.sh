#!/usr/bin/env bash
# Shared by scripts/docs-shots.sh (guide clips) and scripts/store-shots.sh (App Store
# preview). Source it from the repo root.
#
# record_start <out.mov> <x,y,w,h points, top-left of the main screen> <cursor 0|1>
#   Records Segue's own windows in that rectangle with scripts/record-app.swift
#   (ScreenCaptureKit, built once into .build/tools), in the background. A whole-screen
#   recording was dropped: `screencapture -v` hung past its time limit once the stage had
#   been up, and any screen recording also caught other apps and XCUITest's "Automation
#   Running" banner.
# record_stop
#   Stops the recording cleanly and waits for it; then `recorded_started` holds the first
#   frame's wall-clock time (epoch seconds), for cutting at the test's markers.
# Needs Screen Recording permission for the terminal ([RYAN], once).

recorder_pid=""
recorder_started_file=""
recorded_started=""

record_start() {
    local out="$1" rect="$2" cursor="$3" tool=.build/tools/record-app
    if [[ ! -x "$tool" || scripts/record-app.swift -nt "$tool" ]]; then
        mkdir -p .build/tools
        xcrun swiftc -O -o "$tool" scripts/record-app.swift
    fi
    recorder_started_file="$out.started"
    rm -f "$recorder_started_file"
    "$tool" "$out" dev.ryandsilva.segue "$rect" "$cursor" "$recorder_started_file" &
    recorder_pid=$!
}

record_stop() {
    [[ -n "$recorder_pid" ]] || return 0
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" || true
    recorder_pid=""
    recorded_started=$(tr -d '[:space:]' <"$recorder_started_file" 2>/dev/null || true)
}

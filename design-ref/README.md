# design-ref

Fork-only dev tools from the ui-polish work.

- `tools/build-fast.sh [--install]`: incremental `make local`. It reuses `.local-build`, signs with the machine's Apple Development certificate (see CLAUDE.md), and with `--install` replaces and relaunches `/Applications/VoiceInk.app`.
- `tools/capture.sh <clip> <right-option|right-command> [seconds]`: screen-records one dictation of a fixed spoken phrase.
- `tools/compare`, `tools/frames`, `tools/press`: before/after stills, videos and GIFs; contact sheets of clip frames; a real right-modifier key press. Build each one before first use:

  ```bash
  cd design-ref/tools
  swiftc -O -parse-as-library compare.swift -o compare   # uses @main
  swiftc -O frames.swift -o frames
  swiftc -O press.swift -o press
  ```

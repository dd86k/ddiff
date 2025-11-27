# ddiff

Binary diff utility

Usage: `ddiff <file1> <file2>`

Options: Use `--help`

Why?
- https://www.zynamics.com/bindiff.html / https://github.com/google/bindiff
  - Java
  - GUI, I want results inline.
- https://diffing.quarkslab.com/differs/bindiff.html
  - Python
- https://www.cjmweb.net/vbindiff/ / https://github.com/madsen/vbindiff
  - Last worked on in 2017.
  - TUI is nice, but I want results inline.
  - Mentions PuTTY issues.
  - Mentions 4 GiB limit.
- https://github.com/jmacd/xdelta
  - Last worked on in 2017.
  - Meant for data compression and transmission, not comparison.
- My ddgst utility compares using digests, so only an indicator.
- My ddhx utility does not have a diff mode, yet. Why not mess around?
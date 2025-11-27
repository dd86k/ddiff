# ddiff

Binary diff utility:
```text
...
-00000030 61 61 61+61 61 61 61 61 61 61 61 61 61 61 61 61 aaaaaaaaaaaaaaaa
+00000030 61 61 61+ff 61 61 61 61 61 61 61 61 61 61 61 61 aaa.aaaaaaaaaaaa
...
```

Usage: `ddiff <file1> <file2>`

Options:
- `--columns=`: Number of bytes (elements) per row. Defaults to 16.
- `--side`: Compares side-by-side instead of per-row.
- `--style=`: Defaults to `plain`, but `mono` offers monochrome coloring instead
- `--summary`: Prints list of changes without data.

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
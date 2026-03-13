# ddiff

Binary diff utility:
```text
...
-00000030 61 61 61+61 61 61 61 61 61 61 61 61 61 61 61 61 aaaaaaaaaaaaaaaa
+00000030 61 61 61+ff 61 61 61 61 61 61 61 61 61 61 61 61 aaa.aaaaaaaaaaaa
...
```

Usage: `ddiff [OPTIONS] <file1> <file2>`

Options:
- `--columns=`: Number of bytes (elements) per row. Defaults to 8 columns.
- `--side`: Compares side-by-side instead of per-row.
- `--style=`: Defaults to `plain`. `mono` offers monochrome coloring instead.
- `--regions`: Prints list of regions. Tab separated position, length, and status.
- `--summary`: Print a short summary of difference count and size..
- `--brief`: Only print `identical` or `different` (eager exit).

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
- My ddgst utility compares using digests, slower.
- My ddhx utility does not have a diff mode, yet. Why not mess around?

# Examples

## Normal

```text
$ ddiff a b
-00000000+64+64+64+64+64 61 61 61 dddddaaa
+00000000+61+61+61+61+61 61 61 61 aaaaaaaa
...
-00000030+61 61 61+61 61 61+61 61 aaaaaaaa
+00000030+62 61 61+62 61 61+62 61 baabaaba
-00000038 61+61 61 61 61 61 61 61 aaaaaaaa
+00000038 61+62 61 61 61 61 61 61 abaaaaaa
```

## Side-by-Side

```text
$ ddiff a b --side
00000000+64+64+64+64+64 61 61 61 dddddaaa |+61+61+61+61+61 61 61 61 aaaaaaaa
...
00000030+61 61 61+61 61 61+61 61 aaaaaaaa |+62 61 61+62 61 61+62 61 baabaaba
00000038 61+61 61 61 61 61 61 61 aaaaaaaa | 61+62 61 61 61 61 61 61 abaaaaaa
```

## Summary

```text
$ ddiff a b --summary
10 regions (5 differ, 50.0%), 9 / 64 Bytes differ
```

## Regions

```text
$ ddiff a b --regions
0	5	different
5	43	identical
48	1	different
49	2	identical
51	1	different
52	2	identical
54	1	different
55	2	identical
57	1	different
58	6	identical
```

## Brief

```text
$ ddiff a b --brief
different
```
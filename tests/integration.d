module integration;

import std.process : execute, executeShell;
import std.file : write, tempDir, remove, exists, mkdirRecurse;
import std.path : buildPath;
import std.stdio : writeln, writefln, stderr, File;
import std.string : indexOf, strip, splitLines, startsWith;
import std.conv : text, to;
import std.array : split, join;
import std.algorithm : count, canFind, startsWith;
import std.format : format;

private:

string tmpPath(string name)
{
    return buildPath(tempDir(), "ddiff-integration-test", name);
}

string ddiffBin;

shared static this()
{
    mkdirRecurse(buildPath(tempDir(), "ddiff-integration-test"));
    // Locate the ddiff binary relative to this test or from env
    import std.file : getcwd, thisExePath;
    auto cwd = getcwd();
    ddiffBin = buildPath(cwd, "ddiff");
    if (!exists(ddiffBin))
    {
        // Try building it
        auto build = execute(["dub", "build"]);
        assert(build.status == 0, "Failed to build ddiff: " ~ build.output);
    }
    assert(exists(ddiffBin), "ddiff binary not found at " ~ ddiffBin);
}

shared static ~this()
{
    import std.file : rmdirRecurse;
    auto dir = buildPath(tempDir(), "ddiff-integration-test");
    if (exists(dir))
        rmdirRecurse(dir);
}

void mkfile(string name, ubyte[] data)
{
    write(tmpPath(name), data);
}

auto ddiff(string[] extraArgs...)
{
    return execute([ddiffBin] ~ extraArgs);
}

/// Count occurrences of needle in haystack
size_t countOccurrences(string haystack, string needle)
{
    size_t count = 0;
    size_t idx = 0;
    while (idx < haystack.length)
    {
        auto pos = haystack[idx .. $].indexOf(needle);
        if (pos < 0) break;
        count++;
        idx += pos + needle.length;
    }
    return count;
}

//
// CLI argument handling
//

// No arguments: exit 1 with error
unittest
{
    auto r = ddiff();
    assert(r.status == 1, text("expected exit 1, got ", r.status));
    assert(r.output.indexOf("Need two files") >= 0, "expected 'Need two files' in: " ~ r.output);
}

// One argument: exit 1
unittest
{
    mkfile("one_arg", [1]);
    auto r = ddiff(tmpPath("one_arg"));
    assert(r.status == 1);
}

// Zero columns: exit 1
unittest
{
    mkfile("zcol_a", [1]);
    mkfile("zcol_b", [2]);
    auto r = ddiff("-c", "0", tmpPath("zcol_a"), tmpPath("zcol_b"));
    assert(r.status == 1);
    assert(r.output.indexOf("zero or negative") >= 0);
}

// Negative columns: exit 1
unittest
{
    mkfile("ncol_a", [1]);
    mkfile("ncol_b", [2]);
    auto r = ddiff("-c", "-1", tmpPath("ncol_a"), tmpPath("ncol_b"));
    assert(r.status == 1);
}

// Invalid style: error
unittest
{
    mkfile("isty_a", [1]);
    mkfile("isty_b", [2]);
    auto r = ddiff("--style=invalid", tmpPath("isty_a"), tmpPath("isty_b"));
    assert(r.status == 1);
    assert(r.output.indexOf("Unknown style") >= 0);
}

// Invalid layout: error
unittest
{
    mkfile("ilay_a", [1]);
    mkfile("ilay_b", [2]);
    auto r = ddiff("--layout=invalid", tmpPath("ilay_a"), tmpPath("ilay_b"));
    assert(r.status == 1);
    assert(r.output.indexOf("Unknown layout") >= 0);
}

// Help: exit 0 with usage info
unittest
{
    auto r = ddiff("-h");
    assert(r.status == 0, text("expected exit 0, got ", r.status));
    assert(r.output.indexOf("Usage:") >= 0);
    assert(r.output.indexOf("Options:") >= 0);
}

//
// Identical files
//

// Identical files: no output
unittest
{
    mkfile("id_a", [1, 2, 3, 4, 5]);
    mkfile("id_b", [1, 2, 3, 4, 5]);
    auto r = ddiff(tmpPath("id_a"), tmpPath("id_b"));
    assert(r.status == 0);
    assert(r.output.strip() == "", "expected empty output for identical files, got: " ~ r.output);
}

//
// Empty files
//

// Two empty files: no output
unittest
{
    mkfile("emp_a", []);
    mkfile("emp_b", []);
    auto r = ddiff(tmpPath("emp_a"), tmpPath("emp_b"));
    assert(r.status == 0);
    assert(r.output.strip() == "");
}

// Empty vs non-empty: shows diff
unittest
{
    mkfile("empne_a", []);
    mkfile("empne_b", [72, 69, 76, 76, 79]);
    auto r = ddiff(tmpPath("empne_a"), tmpPath("empne_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0, "expected address in output");
}

// Non-empty vs empty: shows diff
unittest
{
    mkfile("nemp_a", [72, 69, 76, 76, 79]);
    mkfile("nemp_b", []);
    auto r = ddiff(tmpPath("nemp_a"), tmpPath("nemp_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

//
// Basic diffs
//

// Single byte diff: shows -/+ lines
unittest
{
    mkfile("bas_a", [1, 2, 3, 4, 5]);
    mkfile("bas_b", [1, 2, 99, 4, 5]);
    auto r = ddiff(tmpPath("bas_a"), tmpPath("bas_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("-00000000") >= 0, "expected minus line");
    assert(r.output.indexOf("+00000000") >= 0, "expected plus line");
}

//
// Column option
//

// 16 columns renders wider rows
unittest
{
    ubyte[16] a, b;
    foreach (i; 0 .. 16) { a[i] = cast(ubyte)i; b[i] = cast(ubyte)i; }
    b[15] = 99;
    mkfile("col16_a", a[]);
    mkfile("col16_b", b[]);
    auto r = ddiff("-c", "16", tmpPath("col16_a"), tmpPath("col16_b"));
    assert(r.status == 0);
    // With 16 columns, byte 0x10 (value 16) should not appear as address
    // All data fits in one row at address 00000000
    auto lines = r.output.splitLines();
    foreach (line; lines)
    {
        if (line.startsWith("-"))
        {
            // Should contain hex for byte at index 15 (0x0f)
            assert(line.indexOf(" f") >= 0 || line.indexOf("+f") >= 0,
                "expected byte 0x0f in 16-col line: " ~ line);
            break;
        }
    }
}

//
// Summary mode
//

// Summary shows regions
unittest
{
    mkfile("sum_a", [1, 2, 3, 4, 5]);
    mkfile("sum_b", [1, 2, 99, 4, 5]);
    auto r = ddiff("--summary", tmpPath("sum_a"), tmpPath("sum_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("true") >= 0, "expected 'true' (identical) in summary");
    assert(r.output.indexOf("false") >= 0, "expected 'false' (different) in summary");
    auto lines = r.output.strip().splitLines();
    assert(lines.length == 3, text("expected 3 regions, got ", lines.length));
}

// Summary region integrity — offsets contiguous, cover whole file
unittest
{
    mkfile("ri_a", [1, 0, 1, 0, 1, 0, 1, 0]);
    mkfile("ri_b", [1, 1, 1, 1, 1, 1, 1, 1]);
    auto r = ddiff("--summary", tmpPath("ri_a"), tmpPath("ri_b"));
    assert(r.status == 0);
    _assertRegionIntegrity(r.output, 8);
}

// Summary region integrity with tail (different lengths)
unittest
{
    mkfile("rl_a", [1, 2, 3, 4, 5, 6, 7, 8]);
    mkfile("rl_b", [1, 2, 3]);
    auto r = ddiff("--summary", tmpPath("rl_a"), tmpPath("rl_b"));
    assert(r.status == 0);
    _assertRegionIntegrity(r.output, 8);
}

void _assertRegionIntegrity(string output, ulong expectedTotal)
{
    import std.regex : regex, matchFirst;
    auto re = regex(`DiffRegion\((\d+), (\d+), (true|false)\)`);
    ulong total = 0;
    foreach (line; output.strip().splitLines())
    {
        auto m = matchFirst(line, re);
        assert(!m.empty, "failed to parse region: " ~ line);
        ulong offset = m[1].to!ulong;
        ulong length = m[2].to!ulong;
        assert(offset == total, text("gap: expected offset ", total, ", got ", offset));
        total += length;
    }
    assert(total == expectedTotal, text("total: expected ", expectedTotal, ", got ", total));
}

//
// Side-by-side layout
//

// Side layout uses pipe separator, no +/- prefixes
unittest
{
    mkfile("side_a", [1, 2, 3, 4, 5]);
    mkfile("side_b", [1, 2, 99, 4, 5]);
    auto r = ddiff("--side", tmpPath("side_a"), tmpPath("side_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("|") >= 0, "expected pipe separator in side layout");
    assert(r.output.indexOf("-00000000") < 0, "side layout should not have -address prefix");
}

// --layout=side same as --side
unittest
{
    mkfile("sides_a", [1, 2, 3, 4, 5]);
    mkfile("sides_b", [1, 2, 99, 4, 5]);
    auto r1 = ddiff("--side", tmpPath("sides_a"), tmpPath("sides_b"));
    auto r2 = ddiff("--layout=side", tmpPath("sides_a"), tmpPath("sides_b"));
    assert(r1.output == r2.output, "--side and --layout=side differ");
}

//
// Inline layout
//

// Default is inline, --layout=inline produces same output
unittest
{
    mkfile("inl_a", [1, 2, 3, 4, 5]);
    mkfile("inl_b", [1, 2, 99, 4, 5]);
    auto r1 = ddiff(tmpPath("inl_a"), tmpPath("inl_b"));
    auto r2 = ddiff("--layout=inline", tmpPath("inl_a"), tmpPath("inl_b"));
    assert(r1.output == r2.output, "default and --layout=inline differ");
}

//
// Files of different lengths
//

// Longer file1 shows tail data
unittest
{
    ubyte[16] a;
    foreach (i; 0 .. 16) a[i] = cast(ubyte)(i + 1);
    mkfile("diffl_a", a[]);
    mkfile("diffl_b", [1, 2, 3]);
    auto r = ddiff(tmpPath("diffl_a"), tmpPath("diffl_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

// Longer file2 shows tail data
unittest
{
    ubyte[16] b;
    foreach (i; 0 .. 16) b[i] = cast(ubyte)(i + 1);
    mkfile("diffr_a", [1, 2, 3]);
    mkfile("diffr_b", b[]);
    auto r = ddiff(tmpPath("diffr_a"), tmpPath("diffr_b"));
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

//
// Style options
//

// Plain and mono styles produce different output
unittest
{
    mkfile("sty_a", [1, 2, 3]);
    mkfile("sty_b", [1, 9, 3]);
    auto plain = ddiff("--style=plain", tmpPath("sty_a"), tmpPath("sty_b"));
    auto mono = ddiff("--style=mono", tmpPath("sty_a"), tmpPath("sty_b"));
    assert(plain.output != mono.output, "plain and mono should produce different output");
}

// -C is alias for --style=mono
unittest
{
    mkfile("stya_a", [1, 2, 3]);
    mkfile("stya_b", [1, 9, 3]);
    auto mono = ddiff("--style=mono", tmpPath("stya_a"), tmpPath("stya_b"));
    auto color = ddiff("-C", tmpPath("stya_a"), tmpPath("stya_b"));
    assert(mono.output == color.output, "-C differs from --style=mono");
}

// --color is alias for --style=mono
unittest
{
    mkfile("styb_a", [1, 2, 3]);
    mkfile("styb_b", [1, 9, 3]);
    auto mono = ddiff("--style=mono", tmpPath("styb_a"), tmpPath("styb_b"));
    auto color = ddiff("--color", tmpPath("styb_a"), tmpPath("styb_b"));
    assert(mono.output == color.output, "--color differs from --style=mono");
}

//
// Large files
//

// Large file with single byte diff
unittest
{
    ubyte[] data;
    data.length = 10240;
    foreach (i; 0 .. data.length)
        data[i] = cast(ubyte)(i & 0xFF);
    mkfile("lrg_a", data);
    data[5000] = cast(ubyte)((data[5000] + 1) & 0xFF);
    mkfile("lrg_b", data);
    auto r = ddiff(tmpPath("lrg_a"), tmpPath("lrg_b"));
    assert(r.status == 0);
    // Should render exactly 1 diff region (2 data lines in inline mode)
    size_t minusLines = 0;
    foreach (line; r.output.splitLines())
        if (line.startsWith("-"))
            minusLines++;
    assert(minusLines == 1, text("expected 1 minus line, got ", minusLines));
}

// Identical large files: no output
unittest
{
    ubyte[] data;
    data.length = 10240;
    foreach (i; 0 .. data.length)
        data[i] = cast(ubyte)(i & 0xFF);
    mkfile("lrgi_a", data);
    mkfile("lrgi_b", data);
    auto r = ddiff(tmpPath("lrgi_a"), tmpPath("lrgi_b"));
    assert(r.status == 0);
    assert(r.output.strip() == "");
}

//
// Sample files
//

// abc1 vs abc2
unittest
{
    auto r = ddiff("samples/abc1", "samples/abc2");
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

// a1 vs a2
unittest
{
    auto r = ddiff("samples/a1", "samples/a2");
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

// e1 vs e2
unittest
{
    auto r = ddiff("samples/e1", "samples/e2");
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0);
}

// m1 vs m2 — diffs at start and near end
unittest
{
    auto r = ddiff("samples/m1", "samples/m2");
    assert(r.status == 0);
    assert(r.output.indexOf("00000000") >= 0, "m1 vs m2 missing first diff");
    assert(r.output.indexOf("00000030") >= 0, "m1 vs m2 missing second diff region");
}

//
// Known bugs (regression markers)
// These tests document current buggy behavior. When a bug is fixed,
// the test should be flipped to assert the correct behavior.
//

// BUG: Stale diff[] markers from previous row leak into next row
// when one file is shorter, causing wrong + markers on tail bytes.
// Affected code: main.d render loop — diff[] not reset between rows.
unittest
{
    // Row 0: positions 4-7 differ (ADD stored in diff[4..7])
    // Row 1: file1 has 4 bytes, file2 has 8: diff[4..7] stale
    ubyte[12] a = [1,1,1,1, 0xAA,0xAA,0xAA,0xAA, 0xBB,1,1,1];
    ubyte[16] b = 1;
    mkfile("stale_a", a[]);
    mkfile("stale_b", b[]);
    auto r = ddiff(tmpPath("stale_a"), tmpPath("stale_b"));
    assert(r.status == 0);

    // Find the second + line (row 1 of file2)
    string secondPlus;
    int plusCount = 0;
    foreach (line; r.output.splitLines())
    {
        if (line.startsWith("+"))
        {
            plusCount++;
            if (plusCount == 2)
            {
                secondPlus = line;
                break;
            }
        }
    }
    assert(secondPlus.length > 0, "expected two + lines");

    // BUG: The second + line has stale "+ 1+ 1+ 1+ 1" for positions 4-7
    // Once fixed, these bytes should show " 1 1 1 1" (SAME markers, no +)
    bool hasStaleMarkers = secondPlus.indexOf("+ 1+ 1+ 1+ 1") >= 0;
    assert(hasStaleMarkers,
        "STALE DIFF BUG seems fixed! Update this test. Line: " ~ secondPlus);
}

// BUG: Multi-row diff regions only render first row.
// If a DiffRegion spans more bytes than `columns`, only the first
// aligned row is rendered; subsequent rows are silently skipped.
// Affected code: main.d render loop — no inner loop over rows.
unittest
{
    // abc1 vs abc2 equivalent: DiffRegion(4, 12, false) spans rows 0 and 8
    ubyte[16] a = [0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                   0x69,0x6a,0x6b,0x6c,0x6d,0x6e,0x6f,0x70];
    ubyte[16] b = [0x61,0x62,0x63,0x64,0x77,0x78,0x79,0x7a,
                   0x65,0x66,0x67,0x68,0x65,0x66,0x67,0x68];
    mkfile("mrow_a", a[]);
    mkfile("mrow_b", b[]);
    auto r = ddiff("-c", "8", tmpPath("mrow_a"), tmpPath("mrow_b"));
    assert(r.status == 0);

    // BUG: row at offset 0x08 is not rendered
    bool hasRow8 = r.output.indexOf("00000008") >= 0;
    assert(!hasRow8,
        "MULTI-ROW BUG seems fixed! Update this test. Output:\n" ~ r.output);
}

// BUG: Nonexistent file produces stack trace instead of clean error.
// The File() constructor at main.d:275 is outside the try/catch.
unittest
{
    auto r = ddiff("/tmp/ddiff_nonexistent_test_file", "samples/a1");
    assert(r.status != 0, "expected non-zero exit for nonexistent file");

    // BUG: Output contains stack trace lines like "source/main.d:275" or "??:?"
    bool hasStackTrace = r.output.indexOf("??:?") >= 0 ||
                         r.output.indexOf("source/main.d") >= 0;
    assert(hasStackTrace,
        "STACK TRACE BUG seems fixed! Update this test. Output:\n" ~ r.output);
}


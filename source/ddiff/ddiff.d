module ddiff.ddiff;

import std.algorithm : min, max;
import std.stdio : File;

static immutable string DDIFF_VERSION = "0.0.1";

struct DiffRegion
{
    ulong offset;
    ulong length;
    bool identical;
}

struct BinDiff
{
    this(File source, File target, size_t bufSize = 8192)
    {
        file1 = source;
        file2 = target;
        buf1 = new ubyte[bufSize];
        buf2 = new ubyte[bufSize];

        size1 = file1.size();
        size2 = file2.size();
        minimum = min(size1, size2);

        if (minimum > 0)
            _fillBuffers(0);

        // Prime the first region
        if (!_done)
            _primeNext();
    }

    bool empty()
    {
        return _done;
    }

    DiffRegion front()
    {
        return _current;
    }

    void popFront()
    {
        _primeNext();
    }

private:
    void _fillBuffers(ulong position)
    {
        bufStart = position;
        file1.seek(position);
        file2.seek(position);
        auto r1 = file1.rawRead(buf1);
        auto r2 = file2.rawRead(buf2);
        bufLen1 = r1.length;
        bufLen2 = r2.length;
    }

    void _primeNext()
    {
        if (i < minimum)
        {
            if (i >= bufStart + bufLen1 || i >= bufStart + bufLen2)
                _fillBuffers(i);

            size_t off = cast(size_t)(i - bufStart);
            bool currentMatch = (buf1[off] == buf2[off]);
            ulong start = i;

            // Extend region while status remains same
            i++;
            while (i < minimum)
            {
                if (i >= bufStart + bufLen1 || i >= bufStart + bufLen2)
                    _fillBuffers(i);

                off = cast(size_t)(i - bufStart);
                if ((buf1[off] == buf2[off]) != currentMatch)
                    break;
                i++;
            }

            _current = DiffRegion(start, i - start, currentMatch);
        }
        // Handle tail if files differ in length
        else if (i == minimum && size1 != size2)
        {
            ulong longer = max(size1, size2);
            _current = DiffRegion(minimum, longer - minimum, false);
            i++; // Move past minimum to trigger _done next time
        }
        else
        {
            _done = true;
        }
    }

    File file1; long size1;
    File file2; long size2;

    ubyte[] buf1, buf2;
    size_t bufLen1, bufLen2;
    ulong bufStart;

    ulong i;
    ulong minimum;
    bool _done = false;
    DiffRegion _current;
}

// Unit test utilities

private File _tmpFileFrom(ubyte[] data)
{
    auto f = File.tmpfile();
    if (data.length > 0)
        f.rawWrite(data);
    f.seek(0);
    return f;
}

private DiffRegion[] _collectRegions(ref BinDiff diff)
{
    DiffRegion[] regions;
    while (!diff.empty)
    {
        regions ~= diff.front;
        diff.popFront();
    }
    return regions;
}

// Identical files
unittest
{
    auto a = _tmpFileFrom([1, 2, 3, 4, 5]);
    auto b = _tmpFileFrom([1, 2, 3, 4, 5]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 5, true));
}

// Completely different files of equal length
unittest
{
    auto a = _tmpFileFrom([0, 0, 0]);
    auto b = _tmpFileFrom([1, 1, 1]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 3, false));
}

// Single byte files - identical
unittest
{
    auto a = _tmpFileFrom([42]);
    auto b = _tmpFileFrom([42]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 1, true));
}

// Single byte files - different
unittest
{
    auto a = _tmpFileFrom([0]);
    auto b = _tmpFileFrom([1]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 1, false));
}

// Both files empty
unittest
{
    auto a = _tmpFileFrom([]);
    auto b = _tmpFileFrom([]);
    auto diff = BinDiff(a, b);

    assert(diff.empty);
}

// Difference at the start, then identical
unittest
{
    auto a = _tmpFileFrom([0, 0, 3, 4, 5]);
    auto b = _tmpFileFrom([1, 1, 3, 4, 5]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 2, false));
    assert(regions[1] == DiffRegion(2, 3, true));
}

// Identical at the start, then different
unittest
{
    auto a = _tmpFileFrom([1, 2, 3, 0, 0]);
    auto b = _tmpFileFrom([1, 2, 3, 9, 9]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 3, true));
    assert(regions[1] == DiffRegion(3, 2, false));
}

// Difference in the middle
unittest
{
    auto a = _tmpFileFrom([1, 2, 99, 4, 5]);
    auto b = _tmpFileFrom([1, 2,  0, 4, 5]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 2, true));
    assert(regions[1] == DiffRegion(2, 1, false));
    assert(regions[2] == DiffRegion(3, 2, true));
}

// Multiple alternating regions
unittest
{
    auto a = _tmpFileFrom([1, 0, 3, 0, 5]);
    auto b = _tmpFileFrom([1, 9, 3, 9, 5]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 5);
    assert(regions[0] == DiffRegion(0, 1, true));
    assert(regions[1] == DiffRegion(1, 1, false));
    assert(regions[2] == DiffRegion(2, 1, true));
    assert(regions[3] == DiffRegion(3, 1, false));
    assert(regions[4] == DiffRegion(4, 1, true));
}

// Source longer than target (tail region)
unittest
{
    auto a = _tmpFileFrom([1, 2, 3, 4, 5]);
    auto b = _tmpFileFrom([1, 2, 3]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 3, true));
    assert(regions[1] == DiffRegion(3, 2, false)); // tail
}

// Target longer than source (tail region)
unittest
{
    auto a = _tmpFileFrom([1, 2]);
    auto b = _tmpFileFrom([1, 2, 3, 4, 5]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 2, true));
    assert(regions[1] == DiffRegion(2, 3, false)); // tail
}

// Source empty, target non-empty
unittest
{
    auto a = _tmpFileFrom([]);
    auto b = _tmpFileFrom([1, 2, 3]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 3, false));
}

// Source non-empty, target empty
unittest
{
    auto a = _tmpFileFrom([1, 2, 3]);
    auto b = _tmpFileFrom([]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 3, false));
}

// Different files with tail: common prefix differs, then source is longer
unittest
{
    auto a = _tmpFileFrom([1, 2, 3, 4, 5, 6]);
    auto b = _tmpFileFrom([1, 2, 9]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 2, true));
    assert(regions[1] == DiffRegion(2, 1, false));
    assert(regions[2] == DiffRegion(3, 3, false)); // tail
}

// Regions span across buffer boundaries (small buffer)
unittest
{
    ubyte[] a = new ubyte[20];
    ubyte[] b = new ubyte[20];
    a[] = 0;
    b[] = 0;
    // Make bytes 8..12 differ (crosses a 4-byte buffer boundary)
    a[8] = 1; a[9] = 1; a[10] = 1; a[11] = 1;

    auto fa = _tmpFileFrom(a);
    auto fb = _tmpFileFrom(b);
    auto diff = BinDiff(fa, fb, 4); // tiny buffer
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 8, true));
    assert(regions[1] == DiffRegion(8, 4, false));
    assert(regions[2] == DiffRegion(12, 8, true));
}

// Buffer size of 1 (extreme case)
unittest
{
    auto a = _tmpFileFrom([1, 2, 3]);
    auto b = _tmpFileFrom([1, 9, 3]);
    auto diff = BinDiff(a, b, 1);
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 1, true));
    assert(regions[1] == DiffRegion(1, 1, false));
    assert(regions[2] == DiffRegion(2, 1, true));
}

// Buffer size of 1 with identical files
unittest
{
    auto a = _tmpFileFrom([5, 5, 5, 5]);
    auto b = _tmpFileFrom([5, 5, 5, 5]);
    auto diff = BinDiff(a, b, 1);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 4, true));
}

// Data larger than buffer - identical
unittest
{
    ubyte[] data = new ubyte[100];
    foreach (i, ref v; data)
        v = cast(ubyte)(i & 0xFF);

    auto a = _tmpFileFrom(data.dup);
    auto b = _tmpFileFrom(data.dup);
    auto diff = BinDiff(a, b, 16);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 100, true));
}

// Data larger than buffer - single byte difference at end
unittest
{
    ubyte[] a = new ubyte[100];
    ubyte[] b = new ubyte[100];
    a[] = 0;
    b[] = 0;
    b[99] = 1;

    auto fa = _tmpFileFrom(a);
    auto fb = _tmpFileFrom(b);
    auto diff = BinDiff(fa, fb, 16);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 99, true));
    assert(regions[1] == DiffRegion(99, 1, false));
}

// Data larger than buffer - single byte difference at start
unittest
{
    ubyte[] a = new ubyte[100];
    ubyte[] b = new ubyte[100];
    a[] = 0;
    b[] = 0;
    b[0] = 1;

    auto fa = _tmpFileFrom(a);
    auto fb = _tmpFileFrom(b);
    auto diff = BinDiff(fa, fb, 16);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 1, false));
    assert(regions[1] == DiffRegion(1, 99, true));
}

// Regions cover entire file (offsets + lengths sum correctly)
unittest
{
    auto a = _tmpFileFrom([1, 0, 1, 0, 1, 0]);
    auto b = _tmpFileFrom([1, 1, 1, 1, 1, 1]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    ulong totalLen = 0;
    foreach (r; regions)
    {
        assert(r.offset == totalLen);
        totalLen += r.length;
    }
    assert(totalLen == 6);
}

// Regions cover entire file including tail
unittest
{
    auto a = _tmpFileFrom([1, 2, 3, 4, 5, 6, 7, 8]);
    auto b = _tmpFileFrom([1, 2, 3]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    ulong totalLen = 0;
    foreach (r; regions)
    {
        assert(r.offset == totalLen);
        totalLen += r.length;
    }
    assert(totalLen == 8); // length of longer file
}

// Large identical files with small buffer
unittest
{
    ubyte[] data = new ubyte[1000];
    foreach (i, ref v; data)
        v = cast(ubyte)(i % 251); // prime modulus for variety

    auto a = _tmpFileFrom(data.dup);
    auto b = _tmpFileFrom(data.dup);
    auto diff = BinDiff(a, b, 7); // prime-sized buffer
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 1000, true));
}

// Difference exactly at buffer boundary
unittest
{
    ubyte[] a = new ubyte[8];
    ubyte[] b = new ubyte[8];
    a[] = 0;
    b[] = 0;
    b[4] = 1; // first byte of second buffer when bufSize=4

    auto fa = _tmpFileFrom(a);
    auto fb = _tmpFileFrom(b);
    auto diff = BinDiff(fa, fb, 4);
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 4, true));
    assert(regions[1] == DiffRegion(4, 1, false));
    assert(regions[2] == DiffRegion(5, 3, true));
}

// Difference at last byte of buffer
unittest
{
    ubyte[] a = new ubyte[8];
    ubyte[] b = new ubyte[8];
    a[] = 0;
    b[] = 0;
    b[3] = 1; // last byte of first buffer when bufSize=4

    auto fa = _tmpFileFrom(a);
    auto fb = _tmpFileFrom(b);
    auto diff = BinDiff(fa, fb, 4);
    auto regions = _collectRegions(diff);

    assert(regions.length == 3);
    assert(regions[0] == DiffRegion(0, 3, true));
    assert(regions[1] == DiffRegion(3, 1, false));
    assert(regions[2] == DiffRegion(4, 4, true));
}

// Files of length 1 where source is longer
unittest
{
    auto a = _tmpFileFrom([1, 2]);
    auto b = _tmpFileFrom([1]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 1, true));
    assert(regions[1] == DiffRegion(1, 1, false));
}

// Entirely different with tail
unittest
{
    auto a = _tmpFileFrom([0, 0, 0, 0, 0]);
    auto b = _tmpFileFrom([1, 1]);
    auto diff = BinDiff(a, b);
    auto regions = _collectRegions(diff);

    assert(regions.length == 2);
    assert(regions[0] == DiffRegion(0, 2, false)); // common range, all different
    assert(regions[1] == DiffRegion(2, 3, false)); // tail
}

// All 256 byte values identical
unittest
{
    ubyte[] data = new ubyte[256];
    foreach (i, ref v; data)
        v = cast(ubyte) i;

    auto a = _tmpFileFrom(data.dup);
    auto b = _tmpFileFrom(data.dup);
    auto diff = BinDiff(a, b, 32);
    auto regions = _collectRegions(diff);

    assert(regions.length == 1);
    assert(regions[0] == DiffRegion(0, 256, true));
}
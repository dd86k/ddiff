module ddiff.ddiff;

import std.algorithm : min, max;
import std.stdio : File;

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
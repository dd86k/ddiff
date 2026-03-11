module main;

// TODO: Render class to hold parameters

//
// Diff
//

import std.algorithm : min, max;

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

//
// Terminal
//

version(Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.wincon;
    import core.sys.windows.windef;
    __gshared uint oldAttr;
}

void terminalInvertColor()
{
version (Windows)
{
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    if (oldAttr==0)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        cast(void)GetConsoleScreenBufferInfo(hout, &csbi);
        oldAttr = csbi.wAttributes;
    }
    SetConsoleTextAttribute(hout, oldAttr | COMMON_LVB_REVERSE_VIDEO);
}
else
{
    write("\033[7m");
}
}

void terminalResetColor()
{
version (Windows)
{
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    SetConsoleTextAttribute(hout, oldAttr);
}
else
{
    write("\033[0m");
}
}

//
// Rendering
//

char tochar(ubyte c)
{
    return c < 32 || c >= 127 ? '.' : c;
}

enum DIFF : ubyte {
    SAME,
    ADD,
}

enum STYLE : ubyte {
    plain,
    monochrome,
    //colorful,
}

enum LAYOUT : ubyte {
    inline,
    side,
}

void modeon(STYLE style, DIFF diff)
{
    final switch (style) {
    case STYLE.plain:
        switch (diff) {
        case DIFF.ADD:  write('+'); break;
        default:        write(' ');
        }
        break;
    case STYLE.monochrome:
        write(' ');
        switch (diff) {
        case DIFF.ADD:
            terminalInvertColor();
            break;
        default:
        }
        break;
    }
}
void modeoff(STYLE style)
{
    final switch (style) {
    case STYLE.plain: break; // no-op
    case STYLE.monochrome: // reset color
        terminalResetColor();
        break;
    }
}

void renderAddress(ulong address)
{
    writef("%0*x", 8, address);
}
void renderLine(ubyte[] line, int row, DIFF[] diff, STYLE style)
{
    int l = cast(int)line.length;
    for (int i; i < row; i++)
    {
        if (i < l)
        {
            modeon(style, diff[i]);
            writef("%*x", 2, line[i]);
            modeoff(style);
        }
        else
        {
            write("   "); // +1 to account for separator or indicator
        }
    }
}
void renderChars(ubyte[] line, DIFF[] diff, STYLE style, int columns)
{
    write(" ");
    // Helps when rendering side by side
    for (int i; i < columns; i++)
    {
        if (i < line.length)
            write( tochar(line[i]) );
        else
            write( ' ' );
    }
}

void renderByLine(ulong address, ubyte[] line1, ubyte[] line2, int cols, DIFF[] diff, STYLE style)
{
    write("-");
    renderAddress(address);
    renderLine(line1, cols, diff, style);
    renderChars(line1, diff, style, cols);
    writeln;
    write("+");
    renderAddress(address);
    renderLine(line2, cols, diff, style);
    renderChars(line2, diff, style, cols);
    writeln;
}

void renderBySide(ulong address, ubyte[] line1, ubyte[] line2, int cols, DIFF[] diff, STYLE style)
{
    renderAddress(address);
    renderLine(line1, cols, diff, style);
    renderChars(line1, diff, style, cols);
    write(" |");
    renderLine(line2, cols, diff, style);
    renderChars(line2, diff, style, cols);
    writeln;
}

void render(ulong address, ubyte[] line1, ubyte[] line2, int cols, DIFF[] diff, STYLE style, LAYOUT layout)
{
    final switch (layout) {
    case LAYOUT.inline:
        renderByLine(address, line1, line2, cols, diff, style);
        break;
    case LAYOUT.side:
        renderBySide(address, line1, line2, cols, diff, style);
        break;
    }
}

//
// CLI
//

import std.stdio;
import std.getopt;
import std.conv : text;

private:

static immutable string VERSION = "0.0.1";

void printfield(string field, string line, int spacing = -12)
{
    writefln("%*s %s", spacing, field ? field : "", line);
}
void pageversion()
{
    import core.stdc.stdlib : exit;
    static immutable string BUILDINFO = "Built: "~__TIMESTAMP__;
    printfield("ddiff",     VERSION);
    printfield(null,        BUILDINFO);
    printfield("License",   "CC0-1.0");
    printfield(null,        "https://creativecommons.org/publicdomain/zero/1.0/");
    printfield("Homepage",  "https://github.com/dd86k/ddiff");
    exit(0);
}

int main(string[] args)
{
    int ocols = 8;
    STYLE ostyle;
    bool osummary;
    LAYOUT olayout; // ubyte
    GetoptResult get = void;
    try get = getopt(args, config.caseSensitive,
        "c|columns", "Columns per row (default: 8)", &ocols,
        // Alias for --layout=side
        "side",      "Render side-by-side instead of per-line", ()
        {
            olayout = LAYOUT.side;
        },
        "l|layout",  "Use layout ('inline', 'side')", (string _, string val)
        {
            switch (val) {
            case "inline":  olayout = LAYOUT.inline; break;
            case "side":    olayout = LAYOUT.side; break;
            default:
                throw new Exception(text("Unknown layout: ", val));
            }
        },
        // Alias for --style=mono
        "C|color",   "Use color if available", ()
        {
            // TODO: Auto-detection needed (xterm, xterm-256color, etc.)
            ostyle = STYLE.monochrome;
        },
        "style",     "Marker style (plain, mono)", (string _, string val)
        {
            switch (val) {
            case "plain": ostyle = STYLE.plain; break;
            case "mono":  ostyle = STYLE.monochrome; break;
            default:
                throw new Exception(text("Unknown style: ", val));
            }
        },
        "summary",   "Only print diff changes", &osummary,
        "version",   "Show version page", &pageversion
    );
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }
    
    if (get.helpWanted)
    {
    Lhelp:
        writeln("Binary diff visualizer");
        writeln("Usage: ddiff <file1> <file2>");
        writeln();
        writeln("Options:");
        foreach (opt; get.options)
        {
            writefln("%*s %*s  %s", 3, opt.optShort, 12, opt.optLong, opt.help);
        }
        return 0;
    }
    
    if (ocols <= 0)
    {
        stderr.writeln("error: Cannot have zero or negative columns");
        return 1;
    }
    
    if (args.length != 3)
    {
        stderr.writeln("error: Need two files");
        return 1;
    }
    
    File file1 = File(args[1], "rb");
    File file2 = File(args[2], "rb");
    
    if (osummary)
    {
        foreach (DiffRegion region; BinDiff(file1, file2))
        {
            writeln(region);
        }
        return 0;
    }
    
    ubyte[] line1;
    ubyte[] line2;
    DIFF[] diff;
    line1.length = line2.length = diff.length = ocols;
    diff[]  = cast(DIFF)0xff;
    
    ulong last_cumulative;
    bool linespaced;
    foreach (DiffRegion region; BinDiff(file1, file2))
    {
        // If region identical, boring, we skip that
        if (region.identical)
            continue;
        
        // TODO: Fix "..." printing inbetween two valid adjacent lines
        // TODO: Only print if we have data before/after different spots
        if (linespaced == false)
        {
            writeln("...");
            linespaced = true;
        }
        
        // If region is within last render's cumulative (pos+ROW), skip
        if (region.offset < last_cumulative)
            continue;
        
        linespaced = false;
        
        line1[] = 0;
        line2[] = 0;
        
        // align down by ROW to get starting pos
        ulong pos = region.offset-(region.offset % ocols);
        
        last_cumulative = pos + ocols;
        
        file1.seek(pos);
        file2.seek(pos);
        
        ubyte[] l1 = file1.rawRead(line1);
        ubyte[] l2 = file2.rawRead(line2);
        
        // LAZY: populates diff region
        for (int h; h < ocols; h++)
        {
            if (h < l1.length && h < l2.length)
            {
                diff[h] = l1[h] != l2[h] ? DIFF.ADD : DIFF.SAME;
            }
            else break;
        }
        
        render(pos, l1, l2, ocols, diff, ostyle, olayout);
    }
    
    return 0;
}

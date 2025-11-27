module main;

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
    this(File source, File target)
    {
        file1 = source;
        file2 = target;
        
        size1 = file1.size();
        size2 = file2.size();
        minimum = min(size1, size2);
        
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
    void _primeNext()
    {
        ubyte[1] b1 = void, b2 = void;
        if (i < minimum)
        {
            // Read bytes at current position
            file1.seek(i);
            file2.seek(i);
            file1.rawRead(b1);
            file2.rawRead(b2);
            
            bool currentMatch = (b1[0] == b2[0]);
            ulong start = i;
            
            // Extend region while status remains same
            i++;
            while (i < minimum)
            {
                file1.seek(i);
                file2.seek(i);
                file1.rawRead(b1);
                file2.rawRead(b2);
                
                if ((b1[0] == b2[0]) != currentMatch)
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

enum STYLE {
    plain,
    monochrome,
    //colorful,
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
            write("  ");
        }
    }
}
void renderChars(ubyte[] line, DIFF[] diff, STYLE style)
{
    write(" ");
    foreach (ubyte b; line)
        write( tochar(b) );
}

void renderByLine(ulong address, ubyte[] line1, ubyte[] line2, int row, DIFF[] diff, STYLE style)
{
    write("-");
    renderAddress(address);
    renderLine(line1, row, diff, style);
    renderChars(line1, diff, style);
    writeln;
    write("+");
    renderAddress(address);
    renderLine(line2, row, diff, style);
    renderChars(line2, diff, style);
    writeln;
}

void renderBySide(ulong address, ubyte[] line1, ubyte[] line2, int row, DIFF[] diff, STYLE style)
{
    renderAddress(address);
    renderLine(line1, row, diff, style);
    renderChars(line1, diff, style);
    write(" |");
    renderLine(line2, row, diff, style);
    renderChars(line2, diff, style);
    writeln;
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
    int ocols = 16;
    STYLE ostyle;
    bool osummary;
    bool oside;
    GetoptResult get = void;
    try get = getopt(args,
        "c|columns", "Columns per row (default: 16)", &ocols,
        "side",      "Render side-by-side instead of per-line", &oside,
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
    
    //ulong size1 = file1.size();
    //ulong size2 = file2.size();
    /*ulong delta;
    if (size1 < size2)
        delta = size2 - size1;
    else if (size2 < size1)
        delta = size1 - size2;
    */
    
    ubyte[] line1;
    ubyte[] line2;
    DIFF[] diff;
    line1.length = line2.length = diff.length = ocols;
    
    ulong last_cumulative;
    bool linespaced;
    foreach (DiffRegion region; BinDiff(file1, file2))
    {
        // TODO: Only print if we have data before/after different spots
        if (linespaced == false)
        {
            writeln("...");
            linespaced = true;
        }
        
        // If region identical, boring, we skip that
        if (region.identical)
            continue;
        
        // If region is within last render's cumulative (pos+ROW), skip
        if (region.offset < last_cumulative)
            continue;
        
        // TODO: Handle situation where diffregion mentions same range since last print
        
        linespaced = false;
        
        line1[] = 0;
        line2[] = 0;
        diff[]  = cast(DIFF)0xff;
        
        // align down by ROW to get starting pos
        ulong pos = region.offset-(region.offset % ocols);
        
        last_cumulative = pos + ocols;
        
        file1.seek(pos);
        file2.seek(pos);
        
        ubyte[] l1 = file1.rawRead(line1);
        ubyte[] l2 = file2.rawRead(line2);
        
        // lazy lazy lazy
        for (int h; h < ocols; h++)
        {
            if (h < l1.length && h < l2.length)
            {
                diff[h] = l1[h] != l2[h] ? DIFF.ADD : DIFF.SAME;
            }
            else break;
        }
        
        oside ?
        renderBySide(pos, l1, l2, ocols, diff, ostyle):
        renderByLine(pos, l1, l2, ocols, diff, ostyle);
    }
    
    return 0;
}

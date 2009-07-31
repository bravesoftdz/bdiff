{
  ------------------------------------------------------------------------------
  UBDiff.dpr

  Main program logic for BDiff.

  Copyright (c) 2003-2007 Peter D Johnson (www.delphidabbler.com).

  Based on bdiff.c by Stefan Reuther, copyright (c) 1999 Stefan Reuther
  <Streu@gmx.de>.

  THIS SOFTWARE IS PROVIDED "AS-IS", WITHOUT ANY EXPRESS OR IMPLIED WARRANTY. IN
  NO EVENT WILL THE AUTHORS BE HELD LIABLE FOR ANY DAMAGES ARISING FROM THE USE
  OF THIS SOFTWARE.

  For conditions of distribution and use see the BDiff / BPatch license
  available from http://www.delphidabbler.com/software/bdiff/license

  Change log
  v1.0 of 28 Nov 2003  -  Original Pascal translation of bdiff.c
  v1.1 of 18 Sep 2007  -  Fixed memory leaks by freeing various memory buffers.
                       -  Removed "side-by-side" C code.
                       -  Updated help screen copyright statement and added
                          information about -o / --output switch and various
                          format options.
                       -  Changed date format displayed by --version switch.
                       -  Fixed small bug in -h and -v options.
                       -  Fixed a buffer size in print_binary_add routine.
                       -  Updated version constant to 0.2.3.
                       -  Changed copyright and license notice.
  -----------------------------------------------------------------------------
}


unit UBDiff;

{
  PASCAL IMPLEMENTATION NOTES:

  The Pascal translation is only suitable for use on Windows targets - it
  compiles to a Win32 console application and uses the Windows API.

  When shell redirection is used in the original C version running under
  MS-DOS/Windows to create binary difference files, the shell can write CRLF
  whenever LF appears in the output. This modification does not occur in the
  Pascal version and therefore it a safe to output binary files using
  redirection meaning it is not necessary to use the --output switch. The
  --output switch is still supported.
}


interface


{ Program's main interface code: called from the project file }
procedure Main;


implementation


{
  ABOUT THIS UNIT'S IMPLEMENTATION

  v1.0 of this file was a literal translation into Object Pascal of Stefan
  Reuther's bdiff.c file from BDiff v0.2. The original C code was included as
  comments in the file.

  v1.1 of this file has been updated to fix a few issues and is no longer a
  simple translation of Stefan's code. The C code has been stripped from the
  file as a result.
}

{$IOCHECKS OFF}

uses
  // Delphi
  SysUtils, Windows,
  // Project: translation of blksort.c
  UBlkSort,
  // Project: special types & routines
  UBDiffTypes, UBDiffUtils;

const
  VERSION_        = '0.2.3';    // this program's version number
  FORMAT_VERSION  = '02';       // binary diff file format version
  BUFFER_SIZE     = 4096;       // size of buffer used to read files


{ Output format to use }
type
  TFormat = (FMT_BINARY, FMT_FILTERED, FMT_QUOTED);


{ Structure for a matching block }
type
  TMatch = record
    oofs: size_t; {pos in old file}
    nofs: size_t; {pos in new file}
    len: size_t;  {length: 0 if no match}
  end;
  PMatch = ^TMatch;

{ Global variables }
var
  progname: string;             // used in error messages, set in main()
  min_len: size_t = 24;         // default minimum match length
  format: TFormat = FMT_QUOTED; // default output format
  verbose: Integer = 0;         // verbose mode defaults to off / false

{ Record used to reference output generation routines for a format }
type
  TFormatSpec = record
    header:
      procedure(oldfn, newfn: PChar; olds, news: size_t);
    add:
      procedure(data: PShortInt; len: size_t);
    copy:
      procedure(nbase: PShortIntArray; npos: size_t; obase: PShortIntArray;
        opos: size_t; len: size_t);
  end;

procedure print_binary_header(oldfn, newfn: PChar; oldl, newl: size_t);
  forward;
procedure print_text_header(oldfn, newfn: PChar; olds, news: size_t);
  forward;
procedure print_binary_add(data: PShortInt; len: size_t);
  forward;
procedure print_filtered_add(data: PShortInt; len: size_t);
  forward;
procedure print_quoted_add(data: PShortInt; len: size_t);
  forward;
procedure print_text_copy(nbase: PShortIntArray; npos: size_t;
  obase: PShortIntArray; opos: size_t; len: size_t);
  forward;
procedure print_binary_copy(nbase: PShortIntArray; npos: size_t;
  obase: PShortIntArray; opos: size_t; len: size_t);
  forward;

var
  { References procs used to generate output for different formats }
  fmt_spec: array[TFormat] of TFormatSpec = (
    (
      header: print_binary_header;
      add: print_binary_add;
      copy: print_binary_copy;
    ),
    (
      header: print_text_header;
      add: print_filtered_add;
      copy: print_text_copy;
    ),
    (
      header: print_text_header;
      add: print_quoted_add;
      copy: print_text_copy;
    )
  );

{ Exit program with error message }
procedure error_exit(msg: PChar);
begin
  WriteStrFmt(stderr, '%s: %s'#13#10, [progname, msg]);
  Halt(1);
end;

{ Load file, returning pointer to file data, exits with error message if out of
  memory or not found }
function load_file(file_name: PChar; size_ret: Psize_t): PShortIntArray;
var
  fp: File of Char;
  data: PShortIntArray;
  buffer: array[0..BUFFER_SIZE-1] of Char;
  len: size_t;
  cur_len: size_t;
  tmp: PShortIntArray;
begin
  { open file }
  AssignFile(fp, file_name);
  Reset(fp);
  if (IOResult <> 0) then
  begin
    perror(file_name);
    Halt(1);
  end;

  { read file }
  cur_len := 0;
  data := nil;
  BlockRead(fp, buffer, BUFFER_SIZE, len);
  while (len > 0) do
  begin
    tmp := data;
    ReallocMem(tmp, cur_len + len);
    if not Assigned(tmp) then
    begin
      WriteStrFmt(stderr, '%s: Virtual memory exhausted' + #13#10, [progname]);
      Halt(1);
    end;
    data := tmp;
    Move(buffer, data[cur_len], len);
    Inc(cur_len, len);
    BlockRead(fp, buffer, BUFFER_SIZE, len);
  end;
  if not EOF(fp) then
  begin
    perror(file_name);
    CloseFile(fp);
    Halt(1);
  end;

  { exit }
  CloseFile(fp);
  if Assigned(size_ret) then
    size_ret^ := cur_len;
  Result := data;
end;

{ Pack long in little-endian format minto p }
procedure pack_long(p: PShortInt; l: Longint);
begin
  p^ := l and $FF;
  Inc(p);
  p^ := (l shr 8) and $FF;
  Inc(p);
  p^ := (l shr 16) and $FF;
  Inc(p);
  p^ := (l shr 24) and $FF;
end;

{ Compute simple checksum }
function checksum(data: PShortInt; len: size_t): Longint;
var
  l: Longint;
begin
  l := 0;
  while len <> 0 do
  begin
    Dec(len);
    l := ((l shr 30) and 3) or (l shl 2);
    l := l xor Ord(data^);
    Inc(data);
  end;
  Result := l;
end;

{ Print header for 'BINARY' format }
procedure print_binary_header(oldfn, newfn: PChar; oldl, newl: size_t);
var
  head: array[0..15] of ShortInt;
begin
  Move('bdiff' + FORMAT_VERSION + #$1A, head[0], 8); {8 bytes}
  pack_long(@head[8], oldl);
  pack_long(@head[12], newl);
  WriteBin(stdout, @head, 16);
end;

{ Print header for text formats }
procedure print_text_header(oldfn, newfn: PChar; olds, news: size_t);
begin
  WriteStrFmt(
    stdout,
    '%% --- %s (%d bytes)'#13#10'%% +++ %s (%d bytes)'#13#10,
    [oldfn, olds, newfn, news]
  );
end;

{ Print data as C-escaped string }
procedure print_quoted_data(data: PShortInt; len: size_t);
begin
  while (len <> 0) do
  begin
    if isprint(Char(data^)) and (Char(data^) <> '\') then
      WriteStr(stdout, Char(data^))
    else
      WriteStr(stdout, '\' + ByteToOct(data^ and $FF));
    Inc(data);
    Dec(len);
  end;
end;

{ Print data with non-printing characters filtered }
procedure print_filtered_data(data: PShortInt; len: size_t);
begin
  while len <> 0  do
  begin
    if isprint(Char(data^)) then
      WriteStr(stdout, Char(data^))
    else
      WriteStr(stdout, '.');
    Inc(data);
    Dec(len);
  end;
end;

{ Print information for binary diff chunk }
procedure print_binary_add(data: PShortInt; len: size_t);
var
  buf: array[0..3] of ShortInt;
begin
  WriteStr(stdout, '+');
  pack_long(@buf[0], len);
  WriteBin(stdout, @buf, 4);
  WriteBin(stdout, data, len);
end;

{ Print information for filtered diff chunk }
procedure print_filtered_add(data: PShortInt; len: size_t);
begin
  WriteStr(stdout, '+');
  print_filtered_data(data, len);
  WriteStr(stdout, #13#10);
end;

{ Print information for quoted diff chunk }
procedure print_quoted_add(data: PShortInt; len: size_t);
begin
  WriteStr(stdout, '+');
  print_quoted_data(data, len);
  WriteStr(stdout, #13#10);
end;

{ Print information for copied data in text mode }
procedure print_text_copy(nbase: PShortIntArray; npos: size_t;
  obase: PShortIntArray; opos: size_t; len: size_t);
begin
  WriteStrFmt(
    stdout,
    '@ -[%d] => +[%d] %d bytes'#13#10' ',
    [opos, npos, len]
  );
  if format = FMT_FILTERED then
    print_filtered_data(@nbase[npos], len)
  else
    print_quoted_data(@nbase[npos], len);
  WriteStr(stdout, #13#10);
end;

{ Print information for copied data in binary mode }
procedure print_binary_copy(nbase: PShortIntArray; npos: size_t;
  obase: PShortIntArray; opos: size_t; len: size_t);
var
  rec: array[0..11] of ShortInt;
begin
  WriteStr(stdout, '@');
  pack_long(@rec[0], opos);
  pack_long(@rec[4], len);
  pack_long(@rec[8], checksum(@nbase[npos], len));
  WriteBin(stdout, @rec, 12);
end;

{ Find maximum-length match }
procedure bs_find_max_match(
  m_ret: PMatch;                      { return }
  data: PShortIntArray; sort: PBlock;
  len: size_t;                        { old file }
  text: PShortInt; tlen: size_t);     { rest of new file }
var
  found_pos: size_t;
  found_len: size_t;
begin
  m_ret^.len := 0;  {no match}
  m_ret^.nofs := 0;
  while (tlen <> 0) do
  begin
    found_len := find_string(data, sort, len, text, tlen, @found_pos);
    if found_len >= min_len then
    begin
      m_ret^.oofs := found_pos;
      m_ret^.len := found_len;
      Exit;
    end;
    Inc(text);
    Inc(m_ret^.nofs);
    Dec(tlen);
  end;
end;

{ Print log message, if enabled. Log messages go to stderr because we may be
  writing patch file contents to stdout }
procedure log_status(const p: PChar);
begin
  if verbose <> 0 then
    WriteStrFmt(stderr, '%s: %s'#13#10, [progname, p]);
end;

{ Main routine: generate diff }
procedure bs_diff(fn, newfn: PChar);
var
  data: PShortIntArray;
  data2: PShortIntArray;
  len: size_t;
  len2, todo, nofs: size_t;
  sort: PBlock;
  match: TMatch;
  error_code: Integer;  // added in UBDiff v1.1
begin
  error_code := 0;
  { initialize }
  try
    log_status('loading old file');
    data := load_file(fn, @len);
    log_status('loading new file');
    data2 := load_file(newfn, @len2);
    log_status('block sorting old file');
    sort := block_sort(data, len);
    if not Assigned(sort) then
    begin
      WriteStrFmt(stderr, '%s: virtual memory exhausted'#13#10, [progname]);
      // Halt(1); -- Deleted since skips finally section below
      error_code := 1;  // replacement code causes Halt(1) after mem freed
      Exit;             // in finally section
    end;
    log_status('generating patch');
    fmt_spec[format].header(fn, newfn, len, len2);
    { main loop }
    todo := len2;
    nofs := 0;
    while (todo <> 0) do
    begin
      { invariant: nofs + todo = len2 }
      bs_find_max_match(@match, data, sort, len, @data2[nofs], todo);
      if match.len <> 0 then
      begin
        { found a match }
        if match.nofs <> 0 then
          { preceded by a "copy" block }
          fmt_spec[format].add(@data2[nofs], match.nofs);
        Inc(nofs, match.nofs);
        Dec(todo, match.nofs);
        fmt_spec[format].copy(data2, nofs, data, match.oofs, match.len);
        Inc(nofs, match.len);
        Dec(todo, match.len);
      end
      else
      begin
        fmt_spec[format].add(@data2[nofs], todo);
        Break;
      end;
    end;
    log_status('done');
  finally
    // finally section new to v1.1
    if Assigned(sort) then
      FreeMem(sort);
    if Assigned(data) then
      FreeMem(data);
    if Assigned(data2) then
      FreeMem(data2);
    if error_code = 1 then
      Halt(1);    // error_code = 1 flags that program should halt
  end;
end;

{ Display help & exit }
procedure help;
begin
  WriteStrFmt(
    stdout,
    '%s: binary ''diff'' - compare two binary files'#13#10#13#10
      + 'Usage: %s [options] old-file new-file [>patch-file]'#13#10#13#10
      + 'Difference between old-file and new-file written to standard output'
      + #13#10#13#10
      + 'Valid options:'#13#10
      + ' -q                   Use QUOTED format'#13#10
      + ' -f                   Use FILTERED format'#13#10
      + ' -b                   Use BINARY format'#13#10
      + '       --format=FMT   Use format FMT (''quoted'', ''filter[ed]'' '
      + 'or ''binary'')'#13#10
      + ' -m N  --min-equal=N  Minimum equal bytes to recognize an equal chunk'
      + #13#10
      + ' -o FN --output=FN    Set output file name (instead of stdout)'
      + 'output'#13#10
      + ' -V    --verbose      Show status messages'#13#10
      + ' -h    --help         Show this help screen'#13#10
      + ' -v    --version      Show version information'#13#10
      + #13#10
      + '(c) copyright 1999 Stefan Reuther <Streu@gmx.de>'#13#10
      + '(c) copyright 2003-2007 Peter Johnson (www.delphidabbler.com)'#13#10,
    [progname, progname]
  );
  Halt(0);
end;

{ Display version & exit }
procedure version;

  function ExeDate: string;
  var
    H: Integer;
    DOSDate: Integer;
  begin
    H := FileOpen(ParamStr(0), fmOpenRead + fmShareDenyNone);
    try
      DOSDate := FileGetDate(H);
    finally
      FileClose(H);
    end;
    Result := FormatDateTime('dd mmm yyy', FileDateToDateTime(DOSDate));
  end;
begin
  // NOTE: original code displayed compile date using C's __DATE__ macro. Since
  // there is no Pascal equivalent of __DATE__ we display update date of program
  // file instead
  WriteStrFmt(stdout, 'bdiff-%s %s '#13#10, [VERSION_, ExeDate]);
  Halt(0);
end;

{ Read argument of --min-equal }
procedure set_min_equal(p: PChar);
var
  q: PChar;
  x: LongWord;
begin
  if not Assigned(p) or (p^ = #0) then
    error_exit('Missing argument to ''--min-equal'' / ''-m''');
  x := StrToULDec(p, q);
  if q^ <> #0 then
    error_exit('Malformed number on command line');
  if (x = 0) or (x > $7FFF) then
    error_exit('Number out of range on command line');
  min_len := x;
end;

{ Read argument of --format }
procedure set_format(p: PChar);
begin
  if not Assigned(p) then
    error_exit('Missing argument to ''--format''');
  if StrComp(p, 'quoted') = 0 then
    format := FMT_QUOTED
  else if (StrComp(p, 'filter') = 0) or (StrComp(p, 'filtered') = 0) then
    format := FMT_FILTERED
  else if StrComp(p, 'binary') = 0 then
    format := FMT_BINARY
  else
    error_exit('Invalid format specification');
end;

{ Main routine: parses arguments and calls creates diff using bs_diff() }
procedure Main;
var
  oldfn: string;
  newfn: string;
  outfn: string;
  i: Integer;
  p: PChar;
  fp: Integer;
  argv: PChar;
begin
  oldfn := '';
  newfn := '';
  outfn := '';

  progname := ExtractFileName(ParamStr(0));

  { Parse command line }
  i := 1;
  while (i <= ParamCount) do
  begin
    argv := PChar(ParamStr(i) + #0#0#0);
    if argv[0] = '-' then
    begin
      if argv[1] = '-' then
      begin
        { long options }
        p := argv + 2;
        if StrComp(p, 'help') = 0 then
          help
        else if StrComp(p, 'version') = 0 then
          version
        else if StrComp(p, 'verbose') = 0 then
          verbose := 1
        else if StrComp(p, 'output') = 0 then
        begin
          Inc(i);
          argv := PChar(ParamStr(i));
          if (argv^ = #0) then
          begin
            WriteStrFmt(
              stderr, '%s: missing argument to ''--output'''#13#10, [progname]
            );
            Halt(1);
          end
          else
            outfn := argv;
        end
        else if StrLComp(p, 'output=', 7) = 0 then
          outfn := p + 7
        else if StrComp(p, 'format') = 0 then
        begin
          Inc(i);
          argv := PChar(ParamStr(i));
          set_format(argv);
        end
        else if StrLComp(p, 'format=', 7) = 0 then
          set_format(p + 7)
        else if StrComp(p, 'min-equal') = 0 then
        begin
          Inc(i);
          argv := PChar(ParamStr(i));
          set_min_equal(argv);
        end
        else if StrLComp(p, 'min-equal=', 10) = 0 then
          set_min_equal(p + 10)
        else
        begin
          WriteStrFmt(
            stderr,
            '%s: unknown option ''--%s'''#13#10
              + '%s: try ''%s --help'' for more information'#13#10,
            [progname, p, progname, progname]
          );
          Halt(1);
        end;
      end
      else
      begin
        { short options }
        p := argv + 1;
        while p^ <> #0 do
        begin
          case p^ of
            'h':
              if StrComp(p, 'h') = 0 then help; // changed v1.1
            'v':
              if StrComp(p, 'v') = 0 then version;  // changed v1.1
            'V':
              verbose := 1;
            'q':
              format := FMT_QUOTED;
            'f':
              format := FMT_FILTERED;
            'b':
              format := FMT_BINARY;
            'm':
            begin
              Inc(i);
              argv := PChar(ParamStr(i));
              set_min_equal(argv);
            end;
            'o':
            begin
              Inc(i);
              argv := PChar(ParamStr(i));
              if argv^ = #0 then
              begin
                WriteStrFmt(
                  stderr, '%s: missing argument to ''-o'''#13#10, [progname]
                  );
                Halt(1);
              end
              else
                outfn := argv;
            end;
            else
              WriteStrFmt(
                stderr,
                '%s: unknown option ''-%s'''#13#10
                  + '%s: try %s --help'' for more information'#13#10,
                [progname, p^, progname, progname]);
              Halt(1);
          end;
          Inc(p);
        end;
      end;
    end
    else
    begin
      { file names }
      if oldfn = '' then
        oldfn := ParamStr(i)
      else if newfn = '' then
        newfn := ParamStr(i)
      else
        error_exit('Too many file names on command line');
    end;
    Inc(i);
  end;
  if newfn = '' then
    error_exit('Need two filenames');
  if (outfn <> '') and (outfn <> '-') then
  begin
    { redirect stdout to patch file }
    fp := FileCreate(outfn);
    if fp <= 0 then
    begin
      perror(outfn);
      Halt(1);
    end;
    RedirectStdOut(fp);
  end;

  { create the diff }
  bs_diff(PChar(oldfn), PChar(newfn));

end;

end.

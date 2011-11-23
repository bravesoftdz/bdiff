{
 * UBlkSort.dpr
 *
 * Implements block sort / search mechanism.
 *
 * Based on parts of blksort.c by Stefan Reuther, copyright (c) 1999 Stefan
 * Reuther <Streu@gmx.de>.
 *
 * Copyright (c) 2003-2011 Peter D Johnson (www.delphidabbler.com).
 *
 * $Rev$
 * $Date$
 *
 * THIS SOFTWARE IS PROVIDED "AS-IS", WITHOUT ANY EXPRESS OR IMPLIED WARRANTY.
 * IN NO EVENT WILL THE AUTHORS BE HELD LIABLE FOR ANY DAMAGES ARISING FROM THE
 * USE OF THIS SOFTWARE.
 *
 * For conditions of distribution and use see the LICENSE file of visit
 * http://www.delphidabbler.com/software/bdiff/license
}


unit UBlkSort;


interface

uses
  // Delphi
  Windows, SysUtils,
  // Project
  UBDiffTypes;


{ Returns array of offsets into data, sorted by position.
  @param Data [in] Data to be sorted. Must not be nil.
  @param DataSize [in] Size of data to be sorted, must be > 0.
  @return Pointer to block of sorted indices into Data. Caller must free.
  @except raises EOutOfMemory if can't allocate sorted data block.
}
function BlockSort(Data: PSignedAnsiCharArray; DataSize: Cardinal): PBlock;


implementation


{
  GENERAL IMPLEMENTATION NOTE (Stefan Reuther)

    Block-sort part of bdiff:

      Taking the data area of length N, we generate N substrings:
      - first substring is data area, length N
      - 2nd is data area sans first character, length N-1
      - ith is data area sans first i-1 characters, length N-i+1
      - Nth is last character of data area, length 1

      These strings are sorted to allow fast (i.e., binary) searching in data
      area. Of course, we don't really generate these N*N/2 bytes of strings: we
      use an array of N size_t's indexing the data.

  PASCAL IMPLEMENTATION NOTE (Peter Johnson)

    The fact that C's (ansi) Char type is signed and Pascal's is unsigned is
    relevant to the string sorting and accessing code described above. Thefore
    we use a specially defined SignedAnsiChar to maintain the data buffer to
    ensure that the the Pascal performs in the same way as the C code.
}


uses
  // Project
  UBDiffUtils;


function BlockSortCompare(A: Cardinal; B: Cardinal; Data: PSignedAnsiCharArray;
  DataSize: Cardinal): Integer;
var
  PA: PSignedAnsiChar;
  PB: PSignedAnsiChar;
  Len: Cardinal;
begin
  PA := @Data[A];
  PB := @Data[B];
  Len := DataSize - A;
  if DataSize - B < Len then
    Len := DataSize - B;
  while (Len <> 0) and (PA^ = PB^) do
  begin
    Inc(PA);
    Inc(PB);
    Dec(Len);
  end;
  if Len = 0 then
  begin
    Result := A - B;
    Exit;
  end;
  Result := PA^ - PB^;
end;

{ The 'sink element' part of heapsort }
procedure BlockSortSink(Left: Cardinal; Right: Cardinal; Block: PBlock;
  Data: PSignedAnsiCharArray; DataSize: Cardinal);
var
  I, J, X: Cardinal;
begin
  I := Left;
  X := Block[I];
  while True do
  begin
    J := 2 * I + 1;
    if J >= Right then
      Break;
    if J < Right - 1 then
      if BlockSortCompare(Block[J], Block[J+1], Data, DataSize) < 0 then
        Inc(J);
    if BlockSortCompare(X, Block[J], Data, DataSize) > 0 then
      Break;
    Block[I] := Block[J];
    I := J;
  end;
  Block[I] := X;
end;

function BlockSort(Data: PSignedAnsiCharArray; DataSize: Cardinal): PBlock;
var
  I, Temp, Left, Right: Cardinal;
begin
  if DataSize = 0 then
  begin
    Result := nil;
    Exit;
  end;

  GetMem(Result, SizeOf(Cardinal) * DataSize);

  // initialize unsorted data
  for I := 0 to Pred(DataSize) do
    Result[I] := I;

  // heapsort
  Left := DataSize div 2;
  Right := DataSize;
  while Left > 0 do
  begin
    Dec(Left);
    BlockSortSink(Left, Right, Result, Data, DataSize);
  end;
  while Right > 0 do
  begin
    Temp := Result[Left];
    Result[Left] := Result[Right-1];
    Result[Right-1] := Temp;
    Dec(Right);
    BlockSortSink(Left, Right, Result, Data, DataSize);
  end;
end;

end.


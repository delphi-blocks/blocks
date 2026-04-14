{******************************************************************************}
{                                                                              }
{  DelphiBlock Installer                                                       }
{                                                                              }
{  Copyright (c) Luca Minuti <code@lucaminuti.it>                              }
{  All rights reserved.                                                        }
{                                                                              }
{  https://github.com/delphi-blocks/blocks                                     }
{                                                                              }
{  Licensed under the Apache-2.0 license                                       }
{                                                                              }
{******************************************************************************}
unit Blocks.Console;

interface

uses
  System.Classes,
  System.SysUtils;

/// <summary>Windows console text colours, expressed as <c>FOREGROUND_*</c> attribute flags.</summary>
type
  TConsoleColor = (
      clCyan = $0B, // bright cyan
      clDkCyan = $03, // dark cyan
      clGreen = $0A, // bright green
      clYellow = $0E, // bright yellow
      clRed = $0C, // bright red
      clWhite = $0F, // bright white
      clGray = $07, // gray (default)
      clDkGray = $08 // dark gray
  );

const
  clDefault = clGray;

type
  /// <summary>Base class for reading text from a console handle.</summary>
  TConsoleReader = class
  protected
    FHandle: THandle;
    FReader: TStreamReader;
    function GetReaderHandle: THandle; virtual; abstract;
  public
    /// <summary>Reads and returns one line of text from the console input stream.</summary>
    /// <returns>The line of text entered by the user, without the trailing newline.</returns>
    function ReadLine: string;

    constructor Create; virtual;
    destructor Destroy; override;
  end;

  /// <summary>Base class for writing coloured text to a console handle.</summary>
  TConsoleWriter = class
  protected
    FHandle: THandle;
    FWriter: TStreamWriter;
    FUTF8Encoding: TEncoding;
    FBarWidth: Integer; // for the progressbar
    FLastProgress: Int64; // for the progressbar
    procedure SetColor(AColor: TConsoleColor);
    function GetWriterHandle: THandle; virtual; abstract;
  public
    /// <summary>Writes an empty line to the output stream.</summary>
    procedure WriteLine; overload;
    /// <summary>Writes a line of text to the output stream using the current colour.</summary>
    /// <param name="AText">The text to write.</param>
    procedure WriteLine(const AText: string); overload;
    /// <summary>Writes a line of text to the output stream in the specified colour.</summary>
    /// <param name="AText">The text to write.</param>
    /// <param name="AColor">Console colour to apply for this line.</param>
    procedure WriteLine(const AText: string; AColor: TConsoleColor); overload;
    /// <summary>Writes text to the output stream without a trailing newline, using the current colour.</summary>
    /// <param name="AText">The text to write.</param>
    procedure Write(const AText: string); overload;
    /// <summary>Writes text to the output stream without a trailing newline in the specified colour.</summary>
    /// <param name="AText">The text to write.</param>
    /// <param name="AColor">Console colour to apply.</param>
    procedure Write(const AText: string; AColor: TConsoleColor); overload;
    /// <summary>Moves the console cursor to the specified position in the screen buffer.</summary>
    /// <param name="X">Zero-based column index.</param>
    /// <param name="Y">Zero-based row index.</param>
    procedure SetCursorPosition(X, Y: Integer);
    /// <summary>Returns the current cursor position in the screen buffer.</summary>
    /// <param name="X">Receives the zero-based column index, or <c>-1</c> on failure.</param>
    /// <param name="Y">Receives the zero-based row index, or <c>-1</c> on failure.</param>
    procedure GetCursorPosition(var X, Y: Integer);
    /// <summary>Returns the visible size of the console window in character cells.</summary>
    /// <param name="Width">Receives the number of columns.</param>
    /// <param name="Height">Receives the number of rows.</param>
    procedure GetScreenBufferSize(var Width, Height: Integer);
    /// <summary>Renders an in-place ASCII progress bar on the current line.</summary>
    /// <param name="ACount">Number of bytes (or units) transferred so far.</param>
    /// <param name="ASize">Total expected bytes (or units); used to compute the percentage.</param>
    /// <remarks>
    ///   Call with <c>ACount &lt; 1</c> to initialise the bar width from the current console
    ///   window size. Subsequent calls advance the bar; the line is rewritten in place using
    ///   a carriage-return (<c>#13</c>) so the cursor stays on the same row.
    /// </remarks>
    procedure WriteProgress(const ACount, ASize: Int64);

    constructor Create; virtual;
    destructor Destroy; override;
  end;

  /// <summary>Singleton accessor for the three standard console streams.</summary>
  /// <remarks>
  ///   Instances are created on first access and released by the class destructor.
  ///   Use <see cref="StdOut"/> and <see cref="StdErr"/> for output,
  ///   and <see cref="StdIn"/> for reading user input.
  /// </remarks>
  TConsole = class
  strict private
    class var
      FStdIn: TConsoleReader;
      FStdOut: TConsoleWriter;
      FStdErr: TConsoleWriter;
    class destructor Destroy;
    class function GetStdIn: TConsoleReader; static;
    class function GetStdOut: TConsoleWriter; static;
    class function GetStdErr: TConsoleWriter; static;
  strict protected
    FStream: TStreamWriter;
  public
    /// <summary>Standard input stream; reads from the console keyboard.</summary>
    class property StdIn: TConsoleReader read GetStdIn;
    /// <summary>Standard output stream; writes to the console window.</summary>
    class property StdOut: TConsoleWriter read GetStdOut;
    /// <summary>Standard error stream; writes to the console error handle.</summary>
    class property StdErr: TConsoleWriter read GetStdErr;

    /// <summary>Writes an empty line to the output stream.</summary>
    class procedure WriteLine; overload; static;
    /// <summary>Writes a line of text to the output stream in the specified colour.</summary>
    /// <param name="AText">The text to write.</param>
    /// <param name="AColor">Console colour to apply for this line.</param>
    class procedure WriteLine(const AText: string; AColor: TConsoleColor); overload; static;
    /// <summary>Writes a line of text to the output stream in the default colour.</summary>
    /// <param name="AText">The text to write.</param>
    class procedure WriteLine(const AText: string); overload; static;
    /// <summary>Writes text to the output stream without a trailing newline, using the current colour.</summary>
    /// <param name="AText">The text to write.</param>
    class procedure Write(const AText: string); overload; static;
    /// <summary>Writes text to the output stream without a trailing newline in the specified colour.</summary>
    /// <param name="AText">The text to write.</param>
    /// <param name="AColor">Console colour to apply.</param>
    class procedure Write(const AText: string; AColor: TConsoleColor); overload; static;
    /// <summary>Writes a line of text to the error stream.</summary>
    /// <param name="AText">The text to write.</param>
    class procedure WriteError(const AText: string); static;
    /// <summary>Writes a line of text to the output stream.</summary>
    /// <param name="AText">The text to write.</param>
    class procedure WriteWarning(const AText: string); static;
    /// <summary>Reads and returns one line of text from the console input stream.</summary>
    /// <returns>The line of text entered by the user, without the trailing newline.</returns>
    class function ReadLine: string; static;
    /// <summary>Resets stdout and stderr text colour to the default (gray).</summary>
    class procedure ResetColor; static;
  end;

  TStdOutConsole = class(TConsoleWriter)
  protected
    function GetWriterHandle: THandle; override;
  end;

  TStdErrConsole = class(TConsoleWriter)
  protected
    function GetWriterHandle: THandle; override;
  end;

  TStdInConsole = class(TConsoleReader)
  protected
    function GetReaderHandle: THandle; override;
  end;

implementation

uses
  Winapi.Windows;

{ TConsole }

class destructor TConsole.Destroy;
begin
  FStdIn.Free;
  FStdOut.Free;
  FStdErr.Free;
end;

class function TConsole.GetStdErr: TConsoleWriter;
begin
  if not Assigned(FStdErr) then
    FStdErr := TStdErrConsole.Create;
  Result := FStdErr;
end;

class function TConsole.GetStdIn: TConsoleReader;
begin
  if not Assigned(FStdIn) then
    FStdIn := TStdInConsole.Create;
  Result := FStdIn;
end;

class function TConsole.GetStdOut: TConsoleWriter;
begin
  if not Assigned(FStdOut) then
    FStdOut := TStdOutConsole.Create;
  Result := FStdOut;
end;

class function TConsole.ReadLine: string;
begin
  Result := StdIn.ReadLine;
end;

class procedure TConsole.ResetColor;
begin
  SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), Word(clDefault));
  SetConsoleTextAttribute(GetStdHandle(STD_ERROR_HANDLE), Word(clDefault));
end;

class procedure TConsole.Write(const AText: string; AColor: TConsoleColor);
begin
  StdOut.Write(AText, AColor);
end;

class procedure TConsole.Write(const AText: string);
begin
  StdOut.Write(AText);
end;

class procedure TConsole.WriteError(const AText: string);
begin
  StdErr.WriteLine(AText, clRed);
end;

class procedure TConsole.WriteLine(const AText: string);
begin
  StdOut.WriteLine(AText);
end;

class procedure TConsole.WriteLine(const AText: string; AColor: TConsoleColor);
begin
  StdOut.WriteLine(AText, AColor);
end;

class procedure TConsole.WriteWarning(const AText: string);
begin
  StdOut.WriteLine('[WARNING] ' + AText, clYellow);
end;

class procedure TConsole.WriteLine;
begin
  StdOut.WriteLine;
end;

{ TConsoleWriter }

constructor TConsoleWriter.Create;
begin
  inherited;
  FHandle := GetWriterHandle();
  // I need this to avoid the BOM
  FUTF8Encoding := TUTF8Encoding.Create(False);
  SetConsoleOutputCP(CP_UTF8);
  FWriter := TStreamWriter.Create(THandleStream.Create(FHandle), FUTF8Encoding);
  FWriter.AutoFlush := True;
  FWriter.OwnStream;
end;

destructor TConsoleWriter.Destroy;
begin
  SetColor(clDefault);
  FWriter.Free;
  FUTF8Encoding.Free;
  inherited;
end;

procedure TConsoleWriter.GetCursorPosition(var X, Y: Integer);
var
  CSBI: TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(FHandle, CSBI) then
  begin
    X := CSBI.dwCursorPosition.X;
    Y := CSBI.dwCursorPosition.Y;
  end
  else
  begin
    X := -1;
    Y := -1;
  end;
end;

procedure TConsoleWriter.GetScreenBufferSize(var Width, Height: Integer);
var
  Info: CONSOLE_SCREEN_BUFFER_INFO;
begin
  GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), Info);

  Width := Info.srWindow.Right - Info.srWindow.Left + 1;
  Height := Info.srWindow.Bottom - Info.srWindow.Top + 1;
end;

procedure TConsoleWriter.SetColor(AColor: TConsoleColor);
begin
  SetConsoleTextAttribute(FHandle, Word(AColor));
end;

procedure TConsoleWriter.SetCursorPosition(X, Y: Integer);
var
  Coo: TCoord;
begin
  Coo.X := X;
  Coo.Y := Y;
  SetConsoleCursorPosition(FHandle, Coo);
end;

procedure TConsoleWriter.WriteLine(const AText: string);
begin
  FWriter.WriteLine(AText);
end;

procedure TConsoleWriter.WriteLine;
begin
  FWriter.WriteLine;
end;

procedure TConsoleWriter.Write(const AText: string);
begin
  FWriter.Write(AText);
end;

procedure TConsoleWriter.Write(const AText: string; AColor: TConsoleColor);
begin
  SetColor(AColor);
  FWriter.Write(AText);
  SetColor(clDefault);
end;

procedure TConsoleWriter.WriteLine(const AText: string; AColor: TConsoleColor);
begin
  SetColor(AColor);
  FWriter.WriteLine(AText);
  SetColor(clDefault);
end;

procedure TConsoleWriter.WriteProgress(const ACount, ASize: Int64);
var
  Progress: Integer;
  Filled: Integer;
begin
  if ACount < 1 then
  begin
    var Height: Integer;
    GetScreenBufferSize(FBarWidth, Height);
    FBarWidth := FBarWidth - 10;
    FLastProgress := 0;
    Exit;
  end;

  if ACount > ASize then
    Exit;

  Progress := Trunc((ACount / ASize) * 100);
  if Progress <= FLastProgress then
    Exit;

  FLastProgress := Progress;

  Filled := Trunc(Progress / 100 * FBarWidth);

  Write(#13'[' +
    StringOfChar('#', Filled) +
    StringOfChar(' ', FBarWidth - Filled) +
    '] ' +
    Format('%3d%%', [Round(Progress)])
  );
end;

{ TStdOutConsole }

function TStdOutConsole.GetWriterHandle: THandle;
begin
  Result := GetStdHandle(STD_OUTPUT_HANDLE);
end;

{ TStdErrConsole }

function TStdErrConsole.GetWriterHandle: THandle;
begin
  Result := GetStdHandle(STD_ERROR_HANDLE);
end;

{ TConsoleReader }

constructor TConsoleReader.Create;
begin
  inherited;
  FHandle := GetReaderHandle();
  FReader := TStreamReader.Create(THandleStream.Create(FHandle), TEncoding.UTF8);
  FReader.OwnStream;
end;

destructor TConsoleReader.Destroy;
begin
  FReader.Free;
  inherited;
end;

function TConsoleReader.ReadLine: string;
begin
  Result := FReader.ReadLine;
end;

{ TStdInConsole }

function TStdInConsole.GetReaderHandle: THandle;
begin
  Result := GetStdHandle(STD_INPUT_HANDLE);
end;

end.

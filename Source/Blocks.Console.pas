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

procedure TConsoleWriter.SetColor(AColor: TConsoleColor);
begin
  SetConsoleTextAttribute(FHandle, Word(AColor));
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

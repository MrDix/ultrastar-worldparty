{*
    UltraStar WorldParty - Karaoke Game

	UltraStar WorldParty is the legal property of its developers,
	whose names	are too numerous to list here. Please refer to the
	COPYRIGHT file distributed with this source distribution.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. Check "LICENSE" file. If not, see
	<http://www.gnu.org/licenses/>.
 *}


unit UScreenFolderBrowser;

interface

{$MODE OBJFPC}

{$I switches.inc}

uses
  sdl2,
  UMenu,
  UPath;

type
  { Receives the folder chosen in the folder browser }
  TFolderSelectedEvent = procedure(const Folder: IPath) of object;

  { Part of a text that is replaced by an ellipsis when it is too wide }
  TTextElision = (teStart, teMiddle, teEnd);

  TFolderItemKind = (fikUseFolder, fikParent, fikFolder, fikDrive);

  TFolderItem = record
    Kind: TFolderItemKind;
    Name: UTF8String; //text of the list row
    Path: IPath;      //folder opened by the row, PATH_NONE for the drive list
  end;

  TFolderBrowserFocus = (bfExit, bfPath, bfList);

  { Lets the user choose a folder with keyboard, mouse or controller }
  TScreenFolderBrowser = class(TMenu)
    private
      Items: array of TFolderItem;
      CurrentFolder: IPath; //shown folder, PATH_NONE for the drive list
      ItemIndex: integer;   //selected list item
      FirstItem: integer;   //list item shown in the first row
      Focus: TFolderBrowserFocus;
      PathInput: UTF8String; //text typed into the path field
      ReturnScreen: PMenu;
      OnFolderSelected: TFolderSelectedEvent;
      ButtonExit, ButtonPath, TextTitle, TextScroll: integer;
      RowButtons: array of integer;
      procedure AddItem(Kind: TFolderItemKind; const Name: UTF8String; const ItemPath: IPath);
      function ShowFolder(const Folder, SelectFolder: IPath): boolean;
      procedure OpenItem(Index: integer);
      procedure OpenParent();
      procedure OpenTypedPath(const PathText: UTF8String);
      procedure SelectItem(Index: integer);
      procedure JumpToLetter(CharCode: UCS4Char);
      procedure SetFocus(NewFocus: TFolderBrowserFocus);
      procedure UpdateList();
      procedure UpdatePath();
      procedure Finish(Confirmed: boolean);
    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      { Shows the folder containing Folder with Folder selected, or the drive
        list for PATH_NONE, and passes the chosen folder to Handler before
        returning to Screen. }
      procedure Browse(const Title: UTF8String; const Folder: IPath; Screen: PMenu; Handler: TFolderSelectedEvent);
  end;

{ Returns the absolute path of Folder, with a trailing delimiter only for the
  root of a drive or network share. }
function NormalizeFolder(const Folder: IPath): IPath;

{ Shortens Text with an ellipsis until it fits into Width when drawn with the
  given font style and size. }
function FitTextToWidth(const Text: UTF8String; Width: real; Style: integer; Size: real; Elision: TTextElision): UTF8String;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  Classes,
  Math,
  SysUtils,
  TextGL,
  UCommon,
  UFilesystem,
  UGraphic,
  ULanguage,
  UMenuButton,
  UMusic,
  UThemes,
  UUnicodeUtils;

const
  ELLIPSIS = '...';

function CompareFolderNames(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := UTF8CompareText(List[Index1], List[Index2]);
end;

function IsRootFolder(const Folder: IPath): boolean;
var
  FolderText: UTF8String;
begin
  // the drive of "C:\" is "C:", the one of "\\server\share\" is "\\server\share";
  // compared as text because "C:" alone is expanded to the current directory
  FolderText := Folder.RemovePathDelim().ToUTF8();
  Result := (FolderText = '') or (CompareText(FolderText, Folder.GetDrive().ToUTF8()) = 0);
end;

function NormalizeFolder(const Folder: IPath): IPath;
begin
  Result := Folder.GetAbsolutePath().AppendPathDelim();
  if not IsRootFolder(Result) then
    Result := Result.RemovePathDelim();
end;

// returns the folder containing Folder, PATH_NONE (the drive list) for a root
function ParentFolder(const Folder: IPath): IPath;
begin
  Result := PATH_NONE;
  if Folder.IsSet() and not IsRootFolder(Folder) then
    Result := Folder.GetParent();
end;

function FitTextToWidth(const Text: UTF8String; Width: real; Style: integer; Size: real; Elision: TTextElision): UTF8String;
var
  Len, Keep, MinKeep, MaxKeep: integer;

  // Text with only Count of its characters left
  function Shortened(Count: integer): UTF8String;
  begin
    case Elision of
      teStart:
        Result := ELLIPSIS + UTF8Copy(Text, Len - Count + 1, Count);
      teMiddle:
        Result := UTF8Copy(Text, 1, (Count + 1) div 2) + ELLIPSIS + UTF8Copy(Text, Len - Count div 2 + 1, Count div 2);
      else
        Result := UTF8Copy(Text, 1, Count) + ELLIPSIS;
    end;
  end;

begin
  Result := Text;
  TextGL.SetFontStyle(Style);
  TextGL.SetFontSize(Size);
  TextGL.SetFontItalic(false);
  if (Width <= 0) or (TextGL.glTextWidth(Text) <= Width) then
    Exit;

  // binary search for the longest shortened text that still fits
  Len := LengthUTF8(Text);
  MinKeep := 0;
  MaxKeep := Len - 1;
  while (MinKeep < MaxKeep) do
  begin
    Keep := (MinKeep + MaxKeep + 1) div 2;
    if (TextGL.glTextWidth(Shortened(Keep)) <= Width) then
      MinKeep := Keep
    else
      MaxKeep := Keep - 1;
  end;
  Result := Shortened(MinKeep);
end;

// fits Text into the width of the first text of the button
procedure SetButtonText(Button: TButton; const Text: UTF8String; Elision: TTextElision);
var
  Margin: real;
begin
  Margin := Button.Text[0].X - Button.X;
  Button.Text[0].Text := FitTextToWidth(Text, Button.W - 2 * Margin, Button.Text[0].Style, Button.Text[0].Size, Elision);
end;

// returns the first line of the clipboard without enclosing quotes
function ClipboardPath(): UTF8String;
var
  Data: PAnsiChar;
  LineEnd: integer;
begin
  Result := '';
  Data := SDL_GetClipboardText();
  if (Data = nil) then
    Exit;
  Result := UTF8String(Data);
  SDL_free(Data);

  LineEnd := Pos(#10, StringReplace(Result, #13, #10, [rfReplaceAll]));
  if (LineEnd > 0) then
    Result := Copy(Result, 1, LineEnd - 1);
  Result := Trim(Result);
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Trim(Copy(Result, 2, Length(Result) - 2));
end;

constructor TScreenFolderBrowser.Create;
var
  Row: integer;
  RowTheme: TThemeButton;
begin
  inherited Create;

  Self.LoadFromTheme(UThemes.Theme.FolderBrowser);
  Self.TextTitle := Self.AddText(UThemes.Theme.FolderBrowser.TextTitle);
  Self.TextScroll := Self.AddText(UThemes.Theme.FolderBrowser.ListScrollText);

  Self.ButtonExit := Self.AddButton(UThemes.Theme.FolderBrowser.ButtonExit);
  Self.ButtonPath := Self.AddButton(UThemes.Theme.FolderBrowser.ButtonPath);
  if (Length(Self.Button[Self.ButtonPath].Text) = 0) then
    Self.AddButtonText(10, 5, '');
  Self.Button[Self.ButtonPath].Text[0].Writable := true;

  // the rows repeat the first row of the theme
  RowTheme := UThemes.Theme.FolderBrowser.ListRow;
  SetLength(Self.RowButtons, UThemes.Theme.FolderBrowser.List.Rows);
  for Row := 0 to High(Self.RowButtons) do
  begin
    Self.RowButtons[Row] := Self.AddButton(RowTheme);
    if (Length(Self.Button[Self.RowButtons[Row]].Text) = 0) then
      Self.AddButtonText(10, 5, '');
    RowTheme.Y := RowTheme.Y + UThemes.Theme.FolderBrowser.List.Spacing;
  end;

  Self.CurrentFolder := PATH_NONE;
  Self.Focus := bfList;
end;

procedure TScreenFolderBrowser.Browse(const Title: UTF8String; const Folder: IPath; Screen: PMenu; Handler: TFolderSelectedEvent);
var
  Selected, Shown: IPath;
begin
  Self.Text[Self.TextTitle].Text := Title;
  Self.ReturnScreen := Screen;
  Self.OnFolderSelected := Handler;
  Self.Focus := bfList;

  // show the closest existing parent, e.g. when a network share is offline
  Selected := PATH_NONE;
  Shown := PATH_NONE;
  if Folder.IsSet() then
  begin
    Selected := NormalizeFolder(Folder);
    Shown := ParentFolder(Selected);
    while Shown.IsSet() and not Shown.IsDirectory() do
      Shown := ParentFolder(Shown);
  end;
  if not Self.ShowFolder(Shown, Selected) then
    Self.ShowFolder(PATH_NONE, PATH_NONE);
end;

procedure TScreenFolderBrowser.AddItem(Kind: TFolderItemKind; const Name: UTF8String; const ItemPath: IPath);
begin
  SetLength(Self.Items, Length(Self.Items) + 1);
  Self.Items[High(Self.Items)].Kind := Kind;
  Self.Items[High(Self.Items)].Name := Name;
  Self.Items[High(Self.Items)].Path := ItemPath;
end;

{ Lists the subfolders of Folder (the drives for PATH_NONE) and selects
  SelectFolder or else the first subfolder. Returns false if Folder cannot be
  read, the shown folder is kept then. }
function TScreenFolderBrowser.ShowFolder(const Folder, SelectFolder: IPath): boolean;
var
  Shown, Selected: IPath;
  Names: TStringList;
  Iter: IFileIterator;
  Info: TFileInfo;
  Name: UTF8String;
  I: integer;
  {$IFDEF MSWINDOWS}
  Drives: DWORD;
  Letter: char;
  OldErrorMode: UINT;
  {$ENDIF}
begin
  Result := false;
  // own references, the arguments may be the fields replaced below
  Selected := SelectFolder;
  Shown := PATH_NONE;
  if Folder.IsSet() then
    Shown := NormalizeFolder(Folder);
  Names := TStringList.Create();
  {$IFDEF MSWINDOWS}
  // no system message box for drives without medium
  OldErrorMode := SetErrorMode(SEM_FAILCRITICALERRORS);
  {$ENDIF}
  try
    if Shown.IsSet() then
    begin
      if not Shown.IsDirectory() then
        Exit;

      Iter := FileSystem.FileFind(Shown.Append('*'), faAnyFile);
      while Iter.HasNext() do
      begin
        Info := Iter.Next();
        Name := Info.Name.ToUTF8();
        // skip files, "." and "..", hidden folders on Unix and protected system folders on Windows
        if ((Info.Attr and faDirectory) = 0) or (Name = '') or (Name[1] = '.') or
           (((Info.Attr and faHidden) <> 0) and ((Info.Attr and faSysFile) <> 0)) then
          Continue;
        Names.Add(Name);
      end;
    end;

    SetLength(Self.Items, 0);
    if Shown.IsSet() then
    begin
      Self.AddItem(fikUseFolder, ULanguage.Language.Translate('SING_FOLDER_BROWSER_USE_FOLDER'), Shown);
      Self.AddItem(fikParent, ULanguage.Language.Translate('SING_FOLDER_BROWSER_PARENT'), ParentFolder(Shown));
      Names.CustomSort(@CompareFolderNames);
      for I := 0 to Names.Count - 1 do
        Self.AddItem(fikFolder, Names[I], Shown.Append(Names[I]));
    end
    else
    begin
      {$IFDEF MSWINDOWS}
      Drives := GetLogicalDrives();
      for Letter := 'A' to 'Z' do
        if ((Drives and (1 shl (Ord(Letter) - Ord('A')))) <> 0) then
          Self.AddItem(fikDrive, Letter + ':' + PathDelim, Path(Letter + ':' + PathDelim));
      {$ELSE}
      Self.AddItem(fikDrive, PathDelim, Path(PathDelim));
      if (GetEnvironmentVariable('HOME') <> '') then
        Self.AddItem(fikDrive, GetEnvironmentVariable('HOME'), Path(GetEnvironmentVariable('HOME')));
      {$ENDIF}
    end;
    Self.CurrentFolder := Shown;

    // select the requested folder, else the first folder of the list
    Self.ItemIndex := -1;
    for I := 0 to High(Self.Items) do
      if (Self.Items[I].Kind in [fikFolder, fikDrive]) and Selected.IsSet() and Self.Items[I].Path.Equals(Selected) then
        Self.ItemIndex := I;
    if (Self.ItemIndex < 0) then
      for I := High(Self.Items) downto 0 do
        if (Self.Items[I].Kind in [fikFolder, fikDrive]) then
          Self.ItemIndex := I;
    Self.ItemIndex := Max(Self.ItemIndex, 0);
    Self.FirstItem := 0;
    Self.SetFocus(bfList);
    Result := true;
  finally
    {$IFDEF MSWINDOWS}
    SetErrorMode(OldErrorMode);
    {$ENDIF}
    Names.Free();
  end;
end;

procedure TScreenFolderBrowser.OpenItem(Index: integer);
begin
  if (Index < 0) or (Index > High(Self.Items)) then
    Exit;

  case Self.Items[Index].Kind of
    fikUseFolder:
      Self.Finish(true);
    fikParent:
      Self.OpenParent();
    else
      if not Self.ShowFolder(Self.Items[Index].Path, PATH_NONE) then
        UGraphic.ScreenPopupError.ShowPopup(ULanguage.Language.Translate('SING_FOLDER_BROWSER_NOT_FOUND'));
  end;
end;

procedure TScreenFolderBrowser.OpenParent();
begin
  // the drive list has no parent
  if Self.CurrentFolder.IsSet() then
    Self.ShowFolder(ParentFolder(Self.CurrentFolder), Self.CurrentFolder);
end;

procedure TScreenFolderBrowser.OpenTypedPath(const PathText: UTF8String);
var
  Folder: IPath;
  Typed: UTF8String;
begin
  Typed := Trim(PathText);
  if (Typed = '') then
  begin
    Self.SetFocus(bfList);
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  // "C:" would be the current directory of drive C
  if (Typed[Length(Typed)] = ':') then
    Typed := Typed + PathDelim;
  {$ENDIF}
  Folder := NormalizeFolder(Path(Typed));
  if not Self.ShowFolder(Folder, PATH_NONE) then
    UGraphic.ScreenPopupError.ShowPopup(ULanguage.Language.Translate('SING_FOLDER_BROWSER_NOT_FOUND'));
end;

procedure TScreenFolderBrowser.SelectItem(Index: integer);
begin
  if (Length(Self.Items) = 0) then
    Exit;
  Self.ItemIndex := EnsureRange(Index, 0, High(Self.Items));
  Self.SetFocus(bfList);
end;

// selects the next folder whose name starts with the typed character
procedure TScreenFolderBrowser.JumpToLetter(CharCode: UCS4Char);
var
  Letter: UTF8String;
  I, Index: integer;
begin
  Letter := UCS4ToUTF8String(CharCode);
  for I := 1 to Length(Self.Items) do
  begin
    Index := (Self.ItemIndex + I) mod Length(Self.Items);
    if (Self.Items[Index].Kind in [fikFolder, fikDrive]) and UTF8StartsText(Letter, Self.Items[Index].Name) then
    begin
      Self.SelectItem(Index);
      Exit;
    end;
  end;
end;

procedure TScreenFolderBrowser.SetFocus(NewFocus: TFolderBrowserFocus);
begin
  // editing starts with the path of the shown folder
  if (NewFocus = bfPath) and (Self.Focus <> bfPath) then
    Self.PathInput := Self.CurrentFolder.ToUTF8();
  Self.Focus := NewFocus;
  Self.UpdateList();
  Self.UpdatePath();
end;

procedure TScreenFolderBrowser.UpdateList();
var
  Row, Index, Rows: integer;
begin
  Rows := Length(Self.RowButtons);
  // keep the selected item visible
  if (Self.ItemIndex < Self.FirstItem) then
    Self.FirstItem := Self.ItemIndex
  else if (Self.ItemIndex >= Self.FirstItem + Rows) then
    Self.FirstItem := Self.ItemIndex - Rows + 1;
  Self.FirstItem := EnsureRange(Self.FirstItem, 0, Max(Length(Self.Items) - Rows, 0));

  for Row := 0 to Rows - 1 do
  begin
    Index := Self.FirstItem + Row;
    Self.Button[Self.RowButtons[Row]].Visible := (Index < Length(Self.Items));
    if (Index < Length(Self.Items)) then
      SetButtonText(Self.Button[Self.RowButtons[Row]], Self.Items[Index].Name, teEnd);
  end;

  if (Length(Self.Items) > Rows) then
    Self.Text[Self.TextScroll].Text := Format('%d-%d / %d', [Self.FirstItem + 1, Min(Self.FirstItem + Rows, Length(Self.Items)), Length(Self.Items)])
  else
    Self.Text[Self.TextScroll].Text := '';

  case Self.Focus of
    bfExit:
      Self.Interaction := Self.ButtonExit;
    bfPath:
      Self.Interaction := Self.ButtonPath;
    else
      if (Length(Self.Items) > 0) and (Rows > 0) then
        Self.Interaction := Self.RowButtons[Self.ItemIndex - Self.FirstItem];
  end;
end;

procedure TScreenFolderBrowser.UpdatePath();
begin
  if (Self.Focus = bfPath) then
    SetButtonText(Self.Button[Self.ButtonPath], Self.PathInput, teStart)
  else if Self.CurrentFolder.IsSet() then
    SetButtonText(Self.Button[Self.ButtonPath], Self.CurrentFolder.ToUTF8(), teMiddle)
  else
    SetButtonText(Self.Button[Self.ButtonPath], ULanguage.Language.Translate('SING_FOLDER_BROWSER_DRIVES'), teEnd);
end;

procedure TScreenFolderBrowser.Finish(Confirmed: boolean);
begin
  if Confirmed then
  begin
    if Assigned(Self.OnFolderSelected) then
      Self.OnFolderSelected(Self.CurrentFolder);
    Self.FadeTo(Self.ReturnScreen, UMusic.SoundLib.Start);
  end
  else
    Self.FadeTo(Self.ReturnScreen, UMusic.SoundLib.Back);
end;

function TScreenFolderBrowser.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
var
  Pasted: UTF8String;
begin
  Result := true;
  if not PressedDown then
    Exit;

  // paste a path, e.g. of a network share
  if (PressedKey = SDLK_V) and ((SDL_GetModState() and KMOD_CTRL) <> 0) then
  begin
    Pasted := ClipboardPath();
    if (Self.Focus = bfPath) then
    begin
      // a complete path replaces the typed text
      if Path(Pasted).IsAbsolute() then
        Self.PathInput := Pasted
      else
        Self.PathInput := Self.PathInput + Pasted;
      Self.UpdatePath();
    end
    else if (Pasted <> '') then
      Self.OpenTypedPath(Pasted);
    Exit;
  end;

  if IsPrintableChar(CharCode) then
  begin
    if (Self.Focus = bfPath) then
    begin
      Self.PathInput := Self.PathInput + UCS4ToUTF8String(CharCode);
      Self.UpdatePath();
    end
    else if (Self.Focus = bfList) then
      Self.JumpToLetter(CharCode);
    Exit;
  end;

  if (Self.Focus = bfPath) then
  begin
    case PressedKey of
      SDLK_BACKSPACE:
        begin
          Self.PathInput := UTF8Copy(Self.PathInput, 1, LengthUTF8(Self.PathInput) - 1);
          Self.UpdatePath();
        end;
      SDLK_DELETE:
        begin
          Self.PathInput := '';
          Self.UpdatePath();
        end;
      SDLK_RETURN:
        Self.OpenTypedPath(Self.PathInput);
      SDLK_ESCAPE, SDLK_DOWN:
        Self.SetFocus(bfList);
      SDLK_UP:
        Self.SetFocus(bfExit);
    end;
    Exit;
  end;

  if (Self.Focus = bfExit) then
  begin
    case PressedKey of
      SDLK_RETURN, SDLK_ESCAPE:
        Self.Finish(false);
      SDLK_DOWN:
        Self.SetFocus(bfPath);
    end;
    Exit;
  end;

  case PressedKey of
    SDLK_ESCAPE:
      Self.Finish(false);
    SDLK_RETURN:
      Self.OpenItem(Self.ItemIndex);
    SDLK_RIGHT:
      if (Self.ItemIndex <= High(Self.Items)) and (Self.Items[Self.ItemIndex].Kind in [fikFolder, fikDrive]) then
        Self.OpenItem(Self.ItemIndex);
    SDLK_LEFT, SDLK_BACKSPACE:
      Self.OpenParent();
    SDLK_UP:
      if (Self.ItemIndex > 0) then
        Self.SelectItem(Self.ItemIndex - 1)
      else
        Self.SetFocus(bfPath);
    SDLK_DOWN:
      Self.SelectItem(Self.ItemIndex + 1);
    SDLK_PAGEUP:
      Self.SelectItem(Self.ItemIndex - Length(Self.RowButtons));
    SDLK_PAGEDOWN:
      Self.SelectItem(Self.ItemIndex + Length(Self.RowButtons));
    SDLK_HOME:
      Self.SelectItem(0);
    SDLK_END:
      Self.SelectItem(High(Self.Items));
  end;
end;

function TScreenFolderBrowser.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  Row: integer;
begin
  Result := true;
  if BtnDown and (MouseButton = SDL_BUTTON_RIGHT) then
  begin
    Result := Self.ParseInput(SDLK_ESCAPE, 0, true);
    Exit;
  end;

  if BtnDown and ((MouseButton = SDL_BUTTON_WHEELDOWN) or (MouseButton = SDL_BUTTON_WHEELUP)) then
  begin
    if (Self.Focus = bfList) then
      Self.SelectItem(Self.ItemIndex + IfThen(MouseButton = SDL_BUTTON_WHEELDOWN, 3, -3));
    Exit;
  end;

  Self.TransferMouseCords(X, Y);
  if Self.Button[Self.ButtonExit].Visible and InRegion(X, Y, Self.Button[Self.ButtonExit].GetMouseOverArea()) then
  begin
    if BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
      Self.Finish(false)
    else if (Self.Focus = bfList) then
      Self.SetFocus(bfExit);
    Exit;
  end;

  if InRegion(X, Y, Self.Button[Self.ButtonPath].GetMouseOverArea()) then
  begin
    if BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
      Self.SetFocus(bfPath);
    Exit;
  end;

  // hovering selects a row unless the path is being edited
  for Row := 0 to High(Self.RowButtons) do
    if Self.Button[Self.RowButtons[Row]].Visible and InRegion(X, Y, Self.Button[Self.RowButtons[Row]].GetMouseOverArea()) then
    begin
      if (Self.Focus <> bfPath) or (BtnDown and (MouseButton = SDL_BUTTON_LEFT)) then
        Self.SelectItem(Self.FirstItem + Row);
      if BtnDown and (MouseButton = SDL_BUTTON_LEFT) then
        Self.OpenItem(Self.ItemIndex);
      Exit;
    end;
end;

end.

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


unit UScreenOptionsSongdirs;

interface

{$MODE OBJFPC}

{$I switches.inc}

uses
  sdl2,
  UIni,
  UMenu,
  UPath;

type
  TSongDirKind = (sdkBuiltin, sdkStatic, sdkDynamic);

  TSongDir = record
    Path:    IPath;
    Kind:    TSongDirKind;
    Missing: boolean; //the folder did not exist when it was listed
  end;

  TSongDirColumn = (scType, scPath, scDelete);

  TSongDirsFocus = (sfExit, sfList, sfAddStatic, sfAddDynamic);

  { Lists the song folders and lets the user add, change and remove them }
  TScreenOptionsSongdirs = class(TMenu)
    private
      Dirs: array of TSongDir; //built-in folders first, then the configured ones
      DirIndex: integer;       //selected folder
      FirstDir: integer;       //folder shown in the first row
      Column: TSongDirColumn;
      Focus: TSongDirsFocus;
      Changed, StaticChanged: boolean;
      Browsing: boolean;       //the folder browser was opened by this screen
      BrowseIndex: integer;    //folder changed in the browser, -1 to add one
      BrowseKind: TSongDirKind;
      ChosenFolder: IPath;     //folder chosen in the browser, PATH_NONE if cancelled
      ButtonExit, ButtonAddStatic, ButtonAddDynamic, TextScroll: integer;
      TypeButtons, PathButtons, DeleteButtons: array of integer;
      procedure AddDir(const DirPath: IPath; Kind: TSongDirKind);
      procedure LoadDirs();
      function ConfiguredDirs(): TSongDirEntries;
      function CheckFolder(const Folder: IPath; IgnoreIndex: integer; out Error: UTF8String): boolean;
      procedure MarkChanged(Kind: TSongDirKind);
      procedure OpenBrowser(Index: integer; Kind: TSongDirKind);
      procedure OnFolderChosen(const Folder: IPath);
      procedure ApplyChosenFolder();
      procedure ToggleKind(Index: integer);
      procedure ConfirmDelete(Index: integer);
      procedure DeleteDir(Index: integer);
      procedure Activate();
      procedure SelectDir(Index: integer);
      procedure SetFocus(NewFocus: TSongDirsFocus);
      procedure UpdateList();
      procedure ExitScreen();
    public
      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      procedure OnShow; override;
  end;

implementation

uses
  Math,
  SysUtils,
  TextGL,
  UCommon,
  UGraphic,
  ULanguage,
  UMenuButton,
  UMusic,
  UPathUtils,
  UScreenFolderBrowser,
  UThemes;

const
  KIND_NAMES: array[TSongDirKind] of string = (
    'SING_OPTIONS_SONGDIRS_TYPE_BUILTIN',
    'SING_OPTIONS_SONGDIRS_TYPE_STATIC',
    'SING_OPTIONS_SONGDIRS_TYPE_DYNAMIC');

// shortens a path to the width of the error popup text
function PopupPath(const PathText: UTF8String): UTF8String;
begin
  Result := FitTextToWidth(PathText, UThemes.Theme.ErrorPopup.TextError.W,
    UThemes.Theme.ErrorPopup.TextError.Font, UThemes.Theme.ErrorPopup.TextError.Size, teMiddle);
end;

procedure OnDeleteConfirmed(Value: boolean; Data: Pointer);
begin
  if Value then
    UGraphic.ScreenOptionsSongdirs.DeleteDir(PtrInt(Data));
end;

// leaves the screen without the changes that could not be saved
procedure OnDiscardConfirmed(Value: boolean; Data: Pointer);
begin
  if Value then
  begin
    UGraphic.ScreenOptionsSongdirs.Changed := false;
    UGraphic.ScreenOptionsSongdirs.ExitScreen();
  end;
end;

constructor TScreenOptionsSongdirs.Create;
var
  Row: integer;
  TypeTheme, PathTheme, DeleteTheme: TThemeButton;
begin
  inherited Create;

  Self.LoadFromTheme(UThemes.Theme.OptionsSongdirs);
  Self.TextScroll := Self.AddText(UThemes.Theme.OptionsSongdirs.ListScrollText);
  Self.ButtonExit := Self.AddButton(UThemes.Theme.OptionsSongdirs.ButtonExit);

  // the rows repeat the first row of the theme
  TypeTheme := UThemes.Theme.OptionsSongdirs.ListType;
  PathTheme := UThemes.Theme.OptionsSongdirs.ListPath;
  DeleteTheme := UThemes.Theme.OptionsSongdirs.ListDelete;
  SetLength(Self.TypeButtons, UThemes.Theme.OptionsSongdirs.List.Rows);
  SetLength(Self.PathButtons, Length(Self.TypeButtons));
  SetLength(Self.DeleteButtons, Length(Self.TypeButtons));
  for Row := 0 to High(Self.TypeButtons) do
  begin
    Self.TypeButtons[Row] := Self.AddButton(TypeTheme);
    if (Length(Self.Button[Self.TypeButtons[Row]].Text) = 0) then
      Self.AddButtonText(10, 5, '');
    Self.PathButtons[Row] := Self.AddButton(PathTheme);
    if (Length(Self.Button[Self.PathButtons[Row]].Text) = 0) then
      Self.AddButtonText(10, 5, '');
    Self.DeleteButtons[Row] := Self.AddButton(DeleteTheme);
    TypeTheme.Y := TypeTheme.Y + UThemes.Theme.OptionsSongdirs.List.Spacing;
    PathTheme.Y := PathTheme.Y + UThemes.Theme.OptionsSongdirs.List.Spacing;
    DeleteTheme.Y := DeleteTheme.Y + UThemes.Theme.OptionsSongdirs.List.Spacing;
  end;

  Self.ButtonAddStatic := Self.AddButton(UThemes.Theme.OptionsSongdirs.ButtonAddStatic);
  Self.ButtonAddDynamic := Self.AddButton(UThemes.Theme.OptionsSongdirs.ButtonAddDynamic);

  Self.ChosenFolder := PATH_NONE;
end;

procedure TScreenOptionsSongdirs.OnShow;
begin
  inherited;

  if Self.Browsing then
  begin
    // back from the folder browser, keep the unsaved changes
    Self.Browsing := false;
    Self.ApplyChosenFolder();
  end
  else
  begin
    Self.LoadDirs();
    Self.Changed := false;
    Self.StaticChanged := false;
    Self.DirIndex := 0;
    Self.FirstDir := 0;
    Self.Column := scPath;
    Self.Focus := sfList;
    if (Length(Self.Dirs) = 0) then
      Self.Focus := sfAddStatic;
  end;
  Self.UpdateList();
end;

procedure TScreenOptionsSongdirs.AddDir(const DirPath: IPath; Kind: TSongDirKind);
begin
  SetLength(Self.Dirs, Length(Self.Dirs) + 1);
  Self.Dirs[High(Self.Dirs)].Path := DirPath;
  Self.Dirs[High(Self.Dirs)].Kind := Kind;
  Self.Dirs[High(Self.Dirs)].Missing := not DirPath.IsDirectory();
end;

procedure TScreenOptionsSongdirs.LoadDirs();
var
  I: integer;
begin
  SetLength(Self.Dirs, 0);
  if Assigned(UPathUtils.BuiltinSongPaths) then
    for I := 0 to UPathUtils.BuiltinSongPaths.Count - 1 do
      Self.AddDir(NormalizeFolder(UPathUtils.BuiltinSongPaths[I] as IPath), sdkBuiltin);
  for I := 0 to High(UIni.Ini.SongDirs) do
    if UIni.Ini.SongDirs[I].Dynamic then
      Self.AddDir(UIni.Ini.SongDirs[I].Path, sdkDynamic)
    else
      Self.AddDir(UIni.Ini.SongDirs[I].Path, sdkStatic);
end;

function TScreenOptionsSongdirs.ConfiguredDirs(): TSongDirEntries;
var
  I: integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(Self.Dirs) do
    if (Self.Dirs[I].Kind <> sdkBuiltin) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Path := Self.Dirs[I].Path;
      Result[High(Result)].Dynamic := (Self.Dirs[I].Kind = sdkDynamic);
    end;
end;

{ A folder must not overlap another song folder or the trash folder, its songs
  would be loaded twice or disabled songs would come back. }
function TScreenOptionsSongdirs.CheckFolder(const Folder: IPath; IgnoreIndex: integer; out Error: UTF8String): boolean;
var
  I: integer;
begin
  Result := false;
  Error := '';
  for I := 0 to High(Self.Dirs) do
    if (I <> IgnoreIndex) and PathsOverlap(Folder, Self.Dirs[I].Path) then
    begin
      if Folder.Equals(Self.Dirs[I].Path) then
        Error := ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_ALREADY_ADDED')
      else
        Error := Format(ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_OVERLAP'), [PopupPath(Self.Dirs[I].Path.ToUTF8())]);
      Exit;
    end;

  if PathsOverlap(Folder, UPathUtils.DisabledSongPath) then
  begin
    Error := ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_OVERLAP_TRASH');
    Exit;
  end;
  Result := true;
end;

procedure TScreenOptionsSongdirs.MarkChanged(Kind: TSongDirKind);
begin
  Self.Changed := true;
  // only changes of dynamic folders can be applied by a dynamic-only rescan
  if (Kind <> sdkDynamic) then
    Self.StaticChanged := true;
end;

procedure TScreenOptionsSongdirs.OpenBrowser(Index: integer; Kind: TSongDirKind);
var
  Folder: IPath;
  Title: UTF8String;
begin
  Self.Browsing := true;
  Self.BrowseIndex := Index;
  Self.BrowseKind := Kind;
  Self.ChosenFolder := PATH_NONE;

  // show the changed folder or, for a new one, the last folder of the list
  Folder := PATH_NONE;
  if (Index >= 0) then
  begin
    Folder := Self.Dirs[Index].Path;
    Title := ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_CHANGE');
  end
  else
  begin
    if (Length(Self.Dirs) > 0) then
      Folder := Self.Dirs[High(Self.Dirs)].Path;
    if (Kind = sdkDynamic) then
      Title := ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_ADD_DYNAMIC')
    else
      Title := ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_ADD_STATIC');
  end;

  if not Assigned(UGraphic.ScreenFolderBrowser) then
    UGraphic.ScreenFolderBrowser := TScreenFolderBrowser.Create();
  UGraphic.ScreenFolderBrowser.Browse(Title, Folder, @UGraphic.ScreenOptionsSongdirs, @Self.OnFolderChosen);
  Self.FadeTo(@UGraphic.ScreenFolderBrowser, UMusic.SoundLib.Start);
end;

procedure TScreenOptionsSongdirs.OnFolderChosen(const Folder: IPath);
begin
  Self.ChosenFolder := Folder;
end;

procedure TScreenOptionsSongdirs.ApplyChosenFolder();
var
  Error: UTF8String;
begin
  // cancelled
  if Self.ChosenFolder.IsUnset() then
    Exit;

  if not Self.CheckFolder(Self.ChosenFolder, Self.BrowseIndex, Error) then
  begin
    UGraphic.ScreenPopupError.ShowPopup(Error);
    Exit;
  end;

  if (Self.BrowseIndex >= 0) then
  begin
    if Self.Dirs[Self.BrowseIndex].Path.Equals(Self.ChosenFolder) then
      Exit;
    Self.Dirs[Self.BrowseIndex].Path := Self.ChosenFolder;
    Self.Dirs[Self.BrowseIndex].Missing := false;
    Self.MarkChanged(Self.Dirs[Self.BrowseIndex].Kind);
    Self.DirIndex := Self.BrowseIndex;
  end
  else
  begin
    Self.AddDir(Self.ChosenFolder, Self.BrowseKind);
    Self.MarkChanged(Self.BrowseKind);
    Self.DirIndex := High(Self.Dirs);
  end;
  Self.Column := scPath;
  Self.Focus := sfList;
end;

procedure TScreenOptionsSongdirs.ToggleKind(Index: integer);
begin
  // switching moves the folder in or out of the static library
  if (Self.Dirs[Index].Kind = sdkStatic) then
    Self.Dirs[Index].Kind := sdkDynamic
  else
    Self.Dirs[Index].Kind := sdkStatic;
  Self.MarkChanged(sdkStatic);
  Self.UpdateList();
end;

procedure TScreenOptionsSongdirs.ConfirmDelete(Index: integer);
begin
  UGraphic.ScreenPopupCheck.ShowPopup(ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_DELETE_CONFIRM'),
    @OnDeleteConfirmed, Pointer(PtrInt(Index)), false);
end;

procedure TScreenOptionsSongdirs.DeleteDir(Index: integer);
var
  I: integer;
begin
  if (Index < 0) or (Index > High(Self.Dirs)) or (Self.Dirs[Index].Kind = sdkBuiltin) then
    Exit;

  Self.MarkChanged(Self.Dirs[Index].Kind);
  for I := Index to High(Self.Dirs) - 1 do
    Self.Dirs[I] := Self.Dirs[I + 1];
  SetLength(Self.Dirs, Length(Self.Dirs) - 1);

  if (Length(Self.Dirs) = 0) then
    Self.SetFocus(sfAddStatic)
  else
    Self.SelectDir(Min(Index, High(Self.Dirs)));
end;

// runs the action of the selected element
procedure TScreenOptionsSongdirs.Activate();
begin
  case Self.Focus of
    sfExit:
      Self.ExitScreen();
    sfAddStatic:
      Self.OpenBrowser(-1, sdkStatic);
    sfAddDynamic:
      Self.OpenBrowser(-1, sdkDynamic);
    sfList:
      if (Self.Dirs[Self.DirIndex].Kind = sdkBuiltin) then
        UGraphic.ScreenPopupInfo.ShowPopup(ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_BUILTIN_INFO'))
      else
        case Self.Column of
          scType:
            Self.ToggleKind(Self.DirIndex);
          scPath:
            Self.OpenBrowser(Self.DirIndex, Self.Dirs[Self.DirIndex].Kind);
          scDelete:
            Self.ConfirmDelete(Self.DirIndex);
        end;
  end;
end;

procedure TScreenOptionsSongdirs.SelectDir(Index: integer);
begin
  if (Length(Self.Dirs) = 0) then
    Exit;
  Self.DirIndex := EnsureRange(Index, 0, High(Self.Dirs));
  Self.SetFocus(sfList);
end;

procedure TScreenOptionsSongdirs.SetFocus(NewFocus: TSongDirsFocus);
begin
  if (NewFocus = sfList) and (Length(Self.Dirs) = 0) then
    NewFocus := sfAddStatic;
  Self.Focus := NewFocus;
  Self.UpdateList();
end;

procedure TScreenOptionsSongdirs.UpdateList();
var
  Row, Index, Rows: integer;
  PathButton: TButton;
  PathText, Suffix: UTF8String;
  Margin: real;
begin
  Rows := Length(Self.PathButtons);
  // keep the selected folder visible
  if (Self.DirIndex < Self.FirstDir) then
    Self.FirstDir := Self.DirIndex
  else if (Self.DirIndex >= Self.FirstDir + Rows) then
    Self.FirstDir := Self.DirIndex - Rows + 1;
  Self.FirstDir := EnsureRange(Self.FirstDir, 0, Max(Length(Self.Dirs) - Rows, 0));

  for Row := 0 to Rows - 1 do
  begin
    Index := Self.FirstDir + Row;
    Self.Button[Self.TypeButtons[Row]].Visible := (Index < Length(Self.Dirs));
    Self.Button[Self.PathButtons[Row]].Visible := (Index < Length(Self.Dirs));
    Self.Button[Self.DeleteButtons[Row]].Visible := (Index < Length(Self.Dirs)) and (Self.Dirs[Index].Kind <> sdkBuiltin);
    if (Index >= Length(Self.Dirs)) then
      Continue;

    Self.Button[Self.TypeButtons[Row]].Text[0].Text := ULanguage.Language.Translate(KIND_NAMES[Self.Dirs[Index].Kind]);

    // the hint for a missing folder stays visible, the path is shortened
    PathButton := Self.Button[Self.PathButtons[Row]];
    Suffix := '';
    if Self.Dirs[Index].Missing then
      Suffix := ' ' + ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_NOT_FOUND');
    TextGL.SetFontStyle(PathButton.Text[0].Style);
    TextGL.SetFontSize(PathButton.Text[0].Size);
    Margin := PathButton.Text[0].X - PathButton.X;
    PathText := FitTextToWidth(Self.Dirs[Index].Path.ToUTF8(), PathButton.W - 2 * Margin - TextGL.glTextWidth(Suffix),
      PathButton.Text[0].Style, PathButton.Text[0].Size, teMiddle);
    PathButton.Text[0].Text := PathText + Suffix;
    PathButton.Text[0].Alpha := IfThen(Self.Dirs[Index].Missing, 0.6, 1.0);
  end;

  if (Length(Self.Dirs) > Rows) then
    Self.Text[Self.TextScroll].Text := Format('%d-%d / %d', [Self.FirstDir + 1, Min(Self.FirstDir + Rows, Length(Self.Dirs)), Length(Self.Dirs)])
  else
    Self.Text[Self.TextScroll].Text := '';

  case Self.Focus of
    sfExit:
      Self.Interaction := Self.ButtonExit;
    sfAddStatic:
      Self.Interaction := Self.ButtonAddStatic;
    sfAddDynamic:
      Self.Interaction := Self.ButtonAddDynamic;
    else
    begin
      Row := Self.DirIndex - Self.FirstDir;
      // built-in folders can only be looked at
      if (Self.Dirs[Self.DirIndex].Kind = sdkBuiltin) or (Self.Column = scPath) then
        Self.Interaction := Self.PathButtons[Row]
      else if (Self.Column = scType) then
        Self.Interaction := Self.TypeButtons[Row]
      else
        Self.Interaction := Self.DeleteButtons[Row];
    end;
  end;
end;

procedure TScreenOptionsSongdirs.ExitScreen();
begin
  if Self.Changed then
  begin
    // keep the changes on the screen unless the user discards them, e.g. a
    // read-only configuration could not be saved on any later attempt
    if not UIni.Ini.SaveSongDirs(Self.ConfiguredDirs()) then
    begin
      UGraphic.ScreenPopupCheck.ShowPopup(ULanguage.Language.Translate('SING_OPTIONS_SONGDIRS_SAVE_FAILED'),
        @OnDiscardConfirmed, nil, false);
      Exit;
    end;
    UGraphic.ScreenMain.RequestReloadSongs(not Self.StaticChanged);
    Self.Changed := false;
  end;
  Self.FadeTo(@UGraphic.ScreenOptions, UMusic.SoundLib.Back);
end;

function TScreenOptionsSongdirs.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
begin
  Result := true;
  if not PressedDown then
    Exit;

  case PressedKey of
    SDLK_ESCAPE, SDLK_BACKSPACE:
      Self.ExitScreen();
    SDLK_RETURN:
      Self.Activate();
    SDLK_DELETE:
      if (Self.Focus = sfList) and (Self.Dirs[Self.DirIndex].Kind <> sdkBuiltin) then
        Self.ConfirmDelete(Self.DirIndex);
    SDLK_UP:
      case Self.Focus of
        sfList:
          if (Self.DirIndex > 0) then
            Self.SelectDir(Self.DirIndex - 1)
          else
            Self.SetFocus(sfExit);
        sfAddStatic, sfAddDynamic:
          if (Length(Self.Dirs) > 0) then
            Self.SelectDir(High(Self.Dirs))
          else
            Self.SetFocus(sfExit);
      end;
    SDLK_DOWN:
      case Self.Focus of
        sfExit:
          Self.SetFocus(sfList);
        sfList:
          if (Self.DirIndex < High(Self.Dirs)) then
            Self.SelectDir(Self.DirIndex + 1)
          else
            Self.SetFocus(sfAddStatic);
      end;
    SDLK_LEFT:
      case Self.Focus of
        sfList:
          if (Self.Column > scType) then
          begin
            Self.Column := Pred(Self.Column);
            Self.UpdateList();
          end;
        sfAddDynamic:
          Self.SetFocus(sfAddStatic);
      end;
    SDLK_RIGHT:
      case Self.Focus of
        sfList:
          if (Self.Column < scDelete) then
          begin
            Self.Column := Succ(Self.Column);
            Self.UpdateList();
          end;
        sfAddStatic:
          Self.SetFocus(sfAddDynamic);
      end;
    SDLK_PAGEUP:
      if (Self.Focus = sfList) then
        Self.SelectDir(Self.DirIndex - Length(Self.PathButtons));
    SDLK_PAGEDOWN:
      if (Self.Focus = sfList) then
        Self.SelectDir(Self.DirIndex + Length(Self.PathButtons));
    SDLK_HOME:
      Self.SelectDir(0);
    SDLK_END:
      Self.SelectDir(High(Self.Dirs));
  end;
end;

function TScreenOptionsSongdirs.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var
  Row: integer;
  Clicked: boolean;

  // selects the element under the mouse and runs its action on a click
  function Hit(ButtonIndex: integer; NewFocus: TSongDirsFocus; NewColumn: TSongDirColumn): boolean;
  begin
    Result := Self.Button[ButtonIndex].Visible and InRegion(X, Y, Self.Button[ButtonIndex].GetMouseOverArea());
    if not Result then
      Exit;
    if (NewFocus = sfList) then
    begin
      Self.DirIndex := Self.FirstDir + Row;
      Self.Column := NewColumn;
    end;
    Self.SetFocus(NewFocus);
    if Clicked then
      Self.Activate();
  end;

begin
  Result := true;
  if BtnDown and (MouseButton = SDL_BUTTON_RIGHT) then
  begin
    Result := Self.ParseInput(SDLK_ESCAPE, 0, true);
    Exit;
  end;

  if BtnDown and ((MouseButton = SDL_BUTTON_WHEELDOWN) or (MouseButton = SDL_BUTTON_WHEELUP)) then
  begin
    if (Self.Focus = sfList) then
      Self.SelectDir(Self.DirIndex + IfThen(MouseButton = SDL_BUTTON_WHEELDOWN, 1, -1));
    Exit;
  end;

  Self.TransferMouseCords(X, Y);
  Clicked := BtnDown and (MouseButton = SDL_BUTTON_LEFT);
  Row := 0;
  if Hit(Self.ButtonExit, sfExit, scPath) or Hit(Self.ButtonAddStatic, sfAddStatic, scPath) or
     Hit(Self.ButtonAddDynamic, sfAddDynamic, scPath) then
    Exit;

  for Row := 0 to High(Self.PathButtons) do
    if Hit(Self.TypeButtons[Row], sfList, scType) or Hit(Self.PathButtons[Row], sfList, scPath) or
       Hit(Self.DeleteButtons[Row], sfList, scDelete) then
      Exit;
end;

end.

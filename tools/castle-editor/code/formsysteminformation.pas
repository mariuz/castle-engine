{
  Copyright 2022-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Show system information - OpenGL, audio, other reports. }
unit FormSystemInformation;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ButtonPanel, ExtCtrls,
  StdCtrls,
  CastleControl, CastleUiControls;

type
  TSystemInformationForm = class(TForm)
    ButtonPanel1: TButtonPanel;
    CastleControl1: TCastleControl;
    ListSections: TListBox;
    MemoSysInfo: TMemo;
    Panel1: TPanel;
    Panel2: TPanel;
    SaveDialogText: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure HelpButtonClick(Sender: TObject);
    procedure ListSectionsClick(Sender: TObject);
  private
    type
      TInfoType = (itRendering, itAudio, itOther);
      TContextNotification = class(TCastleUserInterface)
        // pass the notification about context creation to form's GLContextOpen method
        procedure GLContextOpen; override;
      end;
    var
      Info: array [TInfoType] of String;
      ButtonCopyClipboard: TButton;
    procedure GLContextOpen;
    procedure SoundEngineOpenClose(Sender: TObject);
    procedure ButtonCopyClipboardClick(Sender: TObject);
    function FullReportText: String;
  public

  end;

var
  SystemInformationForm: TSystemInformationForm;

implementation

{$R *.lfm}

uses Clipbrd,
  CastleGLUtils, CastleSoundEngine, CastleUtils, CastleFilesUtils,
  CastleUriUtils,
  ToolCompilerInfo, ToolFpcVersion, ToolCommonUtils,
  EditorUtils, ProjectUtils;

procedure TSystemInformationForm.TContextNotification.GLContextOpen;
begin
  inherited;
  (Owner as TSystemInformationForm).GLContextOpen;
end;

{ TSystemInformationForm --------------------------------------------------- }

procedure TSystemInformationForm.ListSectionsClick(Sender: TObject);
var
  Selected: TInfoType;
begin
  if Between(ListSections.ItemIndex, Ord(Low(TInfoType)), Ord(High(TInfoType))) then
    Selected := TInfoType(ListSections.ItemIndex)
  else
    { on macOS (Cocoa) user can click anywhere in list to deselect it,
      setting ItemIndex = -1, tolerate it. }
    Selected := Low(TInfoType);

  MemoSysInfo.Lines.Text := Info[Selected];
end;

procedure TSystemInformationForm.SoundEngineOpenClose(Sender: TObject);
begin
  { Update Info[itAudio] when sound engine initializes / deinitializes. }
  Info[itAudio] := SoundEngine.Information;
end;

procedure TSystemInformationForm.FormShow(Sender: TObject);
const
  { Return current widgetset as a string.
    Esp. useful to detect when someone uses non-standard widgetsets that don't support
    OpenGL context sharing.
    See https://wiki.lazarus.freepascal.org/LCL_Defines#General_LCL_defines
    https://wiki.freepascal.org/Widgetset
  }
  SCurrentWidgetset =
    {$if defined(LCLCocoa)} 'Cocoa'
    {$elseif defined(LCLCarbon)} 'Carbon'
    {$elseif defined(LCLGtk2)} 'GTK 2'
    {$elseif defined(LCLGtk3)} 'GTK 3'
    {$elseif defined(LCLQt)} 'Qt 4'
    {$elseif defined(LCLQt5)} 'Qt 5'
    {$elseif defined(LCLWin32)} 'Win32'
    {$else} 'Unknown'
    {$endif};
var
  EditorApplicationData: TEditorApplicationData;
  FpcInfo, LazInfo, DelphiInfo, VSCodeInfo: String;
begin
  EditorApplicationData := TEditorApplicationData.Create;
  try
    CastleControl1.Container.DesignUrl := 'castle-data:/demo_animation/view_demo_animation.castle-user-interface';
  finally FreeAndNil(EditorApplicationData) end;

  { Info[itRendering] will be initialized in CastleControl1Open.
    We do not even reset it here, as CastleControl1 may have been already opened
    (when this form was shown previous time)
    so we just may have valid Info[itRendering] already. }

  try
    FpcInfo := FindExeFpcCompiler + ' (' + FpcVersion.ToString + ')';
  except
    FpcInfo := 'Not found';
  end;
  try
    LazInfo := FindExeLazarusIDE + ' (' + LazarusVersion.ToString + ')';
  except
    LazInfo := 'Not found';
  end;
  DelphiInfo := FindDelphiPath(false);
  if DelphiInfo = '' then
    DelphiInfo := 'Not found';
  VSCodeInfo := FindExeVSCode(false);
  if VSCodeInfo = '' then
    VSCodeInfo := 'Not found';

  Info[itAudio] := SoundEngine.Information;
  Info[itOther] :=
    'Castle Game Engine version: ' + CastleEngineVersion + '.' + NL +
    'Castle Game Engine path: ' + CastleEnginePath + NL +
    'Editor compiled with ' + SCompilerDescription + '.' + NL +
    'Editor platform: ' + SPlatformDescription + '.' + NL +
    'Editor widgetset: ' + SCurrentWidgetset + '.' + NL +
    'Detected FPC: ' + FpcInfo + NL +
    'Detected Lazarus: ' + LazInfo + NL +
    'Detected Delphi: ' + DelphiInfo + NL +
    'Detected VS Code: ' + VSCodeInfo + NL;

  SoundEngine.OnOpenClose.Add(@SoundEngineOpenClose);

  ListSections.ItemIndex := 0;
  MemoSysInfo.Lines.Text := Info[TInfoType(ListSections.ItemIndex)];
end;

procedure TSystemInformationForm.GLContextOpen;
begin
  // use GLInformationString only once rendering context initialized
  Info[itRendering] := GLInformationString;

  if ListSections.ItemIndex = Ord(itRendering) then
    MemoSysInfo.Lines.Text := Info[itRendering];
end;

procedure TSystemInformationForm.FormCreate(Sender: TObject);
begin
  CastleControl1.Container.Controls.Add(TContextNotification.Create(Self));
  ButtonCopyClipboard := TButton.Create(Self);
  ButtonCopyClipboard.Parent := ButtonPanel1;
  ButtonCopyClipboard.Caption := 'Copy All to Clipboard';
  ButtonCopyClipboard.AutoSize := true;
  ButtonCopyClipboard.Align := alLeft;
  ButtonCopyClipboard.BorderSpacing.Around := 6;
  ButtonCopyClipboard.OnClick := @ButtonCopyClipboardClick;
end;

procedure TSystemInformationForm.FormHide(Sender: TObject);
var
  EditorApplicationData: TEditorApplicationData;
begin
  { Using TEditorApplicationData, because we need to set castle-data:/
    to point to the editor data. That's because the loaded design
    possibly watched some castle-data:/ URLs,
    like castle-data:/demo_animation/demo_animation.gltf .
    They must resolve to the same thing when unwatching. }
  EditorApplicationData := TEditorApplicationData.Create;
  try
    { Unload to stop sound.
      Also, explicit unloading allows to use TEditorApplicationData
      to avoid warnings about unwatching castle-data:/demo_animation/demo_animation.gltf,
      per above comment. }
    CastleControl1.Container.DesignUrl := '';
  finally FreeAndNil(EditorApplicationData) end;

  SoundEngine.OnOpenClose.Remove(@SoundEngineOpenClose);
end;

function TSystemInformationForm.FullReportText: String;
begin
  Result :=
    'Rendering:' + NL + Info[itRendering] + NL + NL +
    'Audio:' + NL + Info[itAudio] + NL + NL +
    'Other:' + NL + Info[itOther];
end;

procedure TSystemInformationForm.ButtonCopyClipboardClick(Sender: TObject);
begin
  Clipboard.AsText := FullReportText;
end;

procedure TSystemInformationForm.HelpButtonClick(Sender: TObject);
begin
  if SaveDialogText.Execute then
    StringToFile(FilenameToUriSafe(SaveDialogText.FileName), FullReportText);
end;

end.


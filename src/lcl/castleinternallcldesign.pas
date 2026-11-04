{
  Copyright 2022-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Lazarus IDE integration with Castle Game Engine.

  It's actually compiled-in with castle_engine_lcl now always,
  though in principle we only need this when we're inside Lazarus IDE
  (at design-time for Lazarus IDE).

  This does:
  - make castle-data: work in Lazarus IDE,
  - send CGE warnings to LCL messages window.
}
unit CastleInternalLclDesign;

interface

procedure Register;

{ At design-time (when running in Lazarus IDE) make sure to adjust
  ApplicationDataOverride. }
procedure FixApplicationDataInIDE;

implementation

uses // FPC and LCL units
  SysUtils, Classes, Controls, Forms,
  // Lazarus design-time (IDE) units
  LazIDEIntf, ProjectIntf, IDEMsgIntf, IDEExternToolIntf,
  // CGE units
  CastleUtils, CastleFilesUtils, CastleLclUtils, CastleApplicationProperties;

procedure FixApplicationDataInIDE;
begin
  { Note: In addition to listening to LazarusIDE.AddHandlerOnProjectOpened and
    AddHandlerOnProjectClose in TCastleLazarusIDEIntegration, we also allow
    calling FixApplicationDataInIDE on demand (e.g. when opening the DesignUrl
    dialog or deserializing TCastleControl.DesignUrl before OnProjectOpened).

    Note: We don't check "CastleDesignMode and ..." here now.
    This was preventing FixApplicationDataInIDE from setting path
    when we open the dialog to load DesignUrl for the first time in project
    in Lazarus IDE
    (testcase: open in Lazarus examples/lazarus/multiple_views/ , open form,
    try to set DesignUrl by clicking on "..." near it).
    Our InternalCastleApplicationMode is not yet set at this point.
  }
  if (LazarusIDE <> nil) and
     (LazarusIDE.ActiveProject <> nil) then
  begin
    { Override ApplicationData interpretation, and castle-data:/xxx URL meaning. }
    ApplicationDataOverride := FilenameToUriSafeUTF8(
      InclPathDelim(LazarusIDE.ActiveProject.Directory) + 'data' + PathDelim);
  end;
end;

type
  { Provides integration between Lazarus IDE and CGE that is nice to wrap
    in a class. }
  TCastleLazarusIDEIntegration = class(TComponent)
  strict private
    procedure WarningToLazarusMessages(const Category, S: string);
    function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TCastleLazarusIDEIntegration.Create(AOwner: TComponent);
begin
  inherited;
  ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}WarningToLazarusMessages);
  if LazarusIDE <> nil then
  begin
    LazarusIDE.AddHandlerOnProjectOpened({$ifdef FPC}@{$endif}ProjectOpened);
    LazarusIDE.AddHandlerOnProjectClose({$ifdef FPC}@{$endif}ProjectClose);
    FixApplicationDataInIDE;
  end;
end;

destructor TCastleLazarusIDEIntegration.Destroy;
begin
  if ApplicationProperties <> nil then
    ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}WarningToLazarusMessages);
  if LazarusIDE <> nil then
  begin
    LazarusIDE.RemoveHandlerOnProjectOpened({$ifdef FPC}@{$endif}ProjectOpened);
    LazarusIDE.RemoveHandlerOnProjectClose({$ifdef FPC}@{$endif}ProjectClose);
  end;
  inherited;
end;

function TCastleLazarusIDEIntegration.ProjectOpened(Sender: TObject;
  AProject: TLazProject): TModalResult;
begin
  if AProject <> nil then
    ApplicationDataOverride := FilenameToUriSafeUTF8(
      InclPathDelim(AProject.Directory) + 'data' + PathDelim)
  else
    FixApplicationDataInIDE;
  Result := mrOk;
end;

function TCastleLazarusIDEIntegration.ProjectClose(Sender: TObject;
  AProject: TLazProject): TModalResult;
begin
  ApplicationDataOverride := '';
  Result := mrOk;
end;

procedure TCastleLazarusIDEIntegration.WarningToLazarusMessages(const Category, S: string);
var
  MessageContent: String;
begin
  MessageContent := 'Castle Game Engine: ';
  if Category <> '' then
    MessageContent += Category + ': ';
  MessageContent += S;
  AddIDEMessage(mluWarning, MessageContent);
end;

procedure Register;
//var
//  LazarusIDEIntegration: TCastleLazarusIDEIntegration;
begin
  { If running in Lazarus IDE, show CGE warnings on Lazarus messages list. }
  {LazarusIDEIntegration := }TCastleLazarusIDEIntegration.Create(Application);
end;

end.

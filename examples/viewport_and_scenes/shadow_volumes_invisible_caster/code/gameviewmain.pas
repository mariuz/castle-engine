{
  Copyright 2026 Popa Marius Adrian.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Shadow-only casters: invisible shapes (visible FALSE) casting shadow volumes.

  The design (data/gameviewmain.castle-user-interface) shows
  data/objects.x3dv: two flat signs.
  They are not closed, so they cannot cast shadow volumes themselves.
  Each has an invisible closed shape that casts its shadow.
  Here we only show / hide the invisible casters, to see them. }
unit GameViewMain;

interface

uses Classes,
  CastleVectors, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleViewport, CastleScene, X3DNodes;

type
  { Main view, where most of the application logic takes place. }
  TViewMain = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelInfo: TCastleLabel;
    MainViewport: TCastleViewport;
    SceneObjects: TCastleScene;
  private
    SignCaster, RoundCaster: TShapeNode;
    procedure UpdateInfo;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMain: TViewMain;

implementation

uses SysUtils,
  CastleUtils;

constructor TViewMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
end;

procedure TViewMain.Start;
begin
  inherited;
  SignCaster := SceneObjects.Node('SignCaster') as TShapeNode;
  RoundCaster := SceneObjects.Node('RoundCaster') as TShapeNode;
  UpdateInfo;
end;

procedure TViewMain.UpdateInfo;
begin
  LabelInfo.Caption :=
    'The signs are flat (not closed), invisible shapes cast their shadows.' + NL +
    Format('Shadow casters: %s (press V to change)', [Iff(SignCaster.Visible, 'visible', 'invisible')]) + NL +
    Format('Shadow volumes: %s (press S)', [Iff(MainViewport.ShadowVolumes, 'on', 'off')]) + NL +
    'Drag with mouse to rotate the view.';
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keyV) then
  begin
    SignCaster.Visible := not SignCaster.Visible;
    RoundCaster.Visible := SignCaster.Visible;
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keyS) then
  begin
    MainViewport.ShadowVolumes := not MainViewport.ShadowVolumes;
    UpdateInfo;
    Exit(true);
  end;
end;

end.

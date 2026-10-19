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

{ Depth function and polygon offset of shapes (DepthMode node),
  to render shapes on the same surface as other shapes.

  The design (data/gameviewmain.castle-user-interface) shows
  data/wall.x3dv: a wall, a layer of stripes on it (DepthMode with
  depthFunc "lequal") and a decal (DepthMode with a negative polygonOffset).
  Here we only turn these DepthMode settings off and on,
  to compare with the default depth test. }
unit GameViewMain;

interface

uses Classes,
  CastleVectors, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleScene, X3DNodes;

type
  { Main view, where most of the application logic takes place. }
  TViewMain = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelInfo: TCastleLabel;
    SceneWall: TCastleScene;
  private
    LayerDepthMode, DecalDepthMode: TDepthModeNode;
    DepthModesOn: Boolean;
    procedure UpdateDepthModes;
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
  LayerDepthMode := SceneWall.Node('LayerDepthMode') as TDepthModeNode;
  DecalDepthMode := SceneWall.Node('DecalDepthMode') as TDepthModeNode;
  DepthModesOn := true;
  UpdateDepthModes;
end;

procedure TViewMain.UpdateDepthModes;
begin
  if DepthModesOn then
  begin
    LayerDepthMode.DepthFunc := dmfLessEqual;
    DecalDepthMode.PolygonOffset := Vector2(-1, -1);
  end else
  begin
    { The default depth test: the layer is rejected ("less" fails
      at the same depth), the decal flickers with the wall (z-fighting). }
    LayerDepthMode.DepthFunc := dmfDefault;
    DecalDepthMode.PolygonOffset := Vector2(0, 0);
  end;

  LabelInfo.Caption :=
    Format('DepthMode: %s (press D to change)', [Iff(DepthModesOn, 'on', 'off')]) + NL +
    Format('Stripes layer: depthFunc "%s"', [Iff(DepthModesOn, 'lequal', 'default')]) + NL +
    Format('Decal: polygonOffset %s', [Iff(DepthModesOn, '-1 -1', '0 0')]) + NL +
    'Drag with mouse to rotate the view.';
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keyD) then
  begin
    DepthModesOn := not DepthModesOn;
    UpdateDepthModes;
    Exit(true);
  end;
end;

end.

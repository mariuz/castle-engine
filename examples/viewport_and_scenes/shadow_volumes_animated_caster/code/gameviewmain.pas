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

{ Shadow volumes cast by meshes deformed every frame.

  The design (data/gameviewmain.castle-user-interface) has a light with
  shadows and 4 scenes with data/blob.x3dv: a closed mesh whose coordinates
  are animated by a CoordinateInterpolator (like skinned animation).
  When only the coordinates change, the shadow volumes move the same
  triangles (keeping the edges), instead of triangulating the mesh again.
  Here we only show the frame rate and toggle the animation and shadows. }
unit GameViewMain;

interface

uses Classes,
  CastleVectors, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleViewport, CastleScene;

type
  { Main view, where most of the application logic takes place. }
  TViewMain = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelInfo, LabelFps: TCastleLabel;
    MainViewport: TCastleViewport;
    Blob1, Blob2, Blob3, Blob4: TCastleScene;
  private
    procedure UpdateInfo;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
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
  UpdateInfo;
end;

procedure TViewMain.UpdateInfo;
begin
  LabelInfo.Caption :=
    Format('4 animated meshes, %d triangles each', [Blob1.TrianglesCount]) + NL +
    Format('Animation: %s (press Space)', [Iff(Blob1.TimePlaying, 'on', 'off')]) + NL +
    Format('Shadow volumes: %s (press S)', [Iff(MainViewport.ShadowVolumes, 'on', 'off')]) + NL +
    'Drag with mouse to rotate the view.';
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
var
  Playing: Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keySpace) then
  begin
    Playing := not Blob1.TimePlaying;
    Blob1.TimePlaying := Playing;
    Blob2.TimePlaying := Playing;
    Blob3.TimePlaying := Playing;
    Blob4.TimePlaying := Playing;
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

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

{ Environment probes: several EnvironmentLight nodes with influence boxes,
  each shape is lit by the probe whose box contains it,
  and an irradiance volume (diffuse light varying with the position).

  The rooms and probes are in data/rooms.x3dv.
  Here we compute the irradiance volume of the right room
  (a light from its right side, fading to the left),
  save it as a KTX 3D texture and assign it to the right room's probe. }
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
    MainViewport: TCastleViewport;
    Rooms: TCastleScene;
    LabelInfo: TCastleLabel;
  private
    LeftProbe, RightProbe: TEnvironmentLightNode;
    IrradianceVolume: TImageTexture3DNode;
    ProbeBoxes, UseIrradianceVolume: Boolean;
    function CreateIrradianceVolume: TImageTexture3DNode;
    procedure UpdateProbes;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMain: TViewMain;

implementation

uses SysUtils,
  CastleUtils, CastleImages;

constructor TViewMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
end;

function TViewMain.CreateIrradianceVolume: TImageTexture3DNode;
const
  { Grid points along X, Y, Z of the probe's box (powers of 2,
    as 3D textures need). }
  NX = 8;
  NY = 2;
  NZ = 4;
var
  Image: TRGBFloatImage;
  X, Y, Z: Integer;
  T: Single;
  L0, L1X: TVector3;
  Url: String;
  Props: TTexturePropertiesNode;
begin
  { Order 1 spherical harmonics of the irradiance at each grid point:
    the texture has 4 slabs along Z (L0, L1x, L1y, L1z),
    see TEnvironmentLightNode.IrradianceVolume.
    A warm light from the right (+X) side of the room, stronger near it:
    L0 (the average) grows to the right, L1x makes surfaces facing +X
    brighter than surfaces facing -X. }
  Image := TRGBFloatImage.Create(NX, NY, NZ * 4);
  try
    for Z := 0 to NZ - 1 do
      for Y := 0 to NY - 1 do
        for X := 0 to NX - 1 do
        begin
          T := X / (NX - 1); // 0 on the left of the box, 1 on the right
          L0 := Vector3(0.05, 0.08, 0.15) + Vector3(1.2, 0.6, 0.2) * Sqr(T);
          L1X := Vector3(1.0, 0.5, 0.15) * Sqr(T);
          PVector3(Image.PixelPtr(X, Y, Z))^ := L0;
          PVector3(Image.PixelPtr(X, Y, NZ + Z))^ := L1X;
          PVector3(Image.PixelPtr(X, Y, 2 * NZ + Z))^ := TVector3.Zero;
          PVector3(Image.PixelPtr(X, Y, 3 * NZ + Z))^ := TVector3.Zero;
        end;
    { KTX can store float 3D textures. }
    Url := 'castle-config:/irradiance_volume.ktx';
    SaveImage(Image, Url);
  finally FreeAndNil(Image) end;

  { Linear filtering between the grid points, no mipmaps. }
  Props := TTexturePropertiesNode.Create;
  Props.FdMinificationFilter.Value := 'AVG_PIXEL';
  Props.FdMagnificationFilter.Value := 'AVG_PIXEL';
  Props.BoundaryModeS := bmClampToEdge;
  Props.BoundaryModeT := bmClampToEdge;
  Props.BoundaryModeR := bmClampToEdge;
  Props.GenerateMipMaps := false;

  Result := TImageTexture3DNode.Create;
  Result.SetUrl([Url]);
  Result.TextureProperties := Props;
end;

procedure TViewMain.UpdateProbes;
const
  NoBox: TVector3 = (X: -1; Y: -1; Z: -1);
  RoomSize: TVector3 = (X: 10; Y: 4; Z: 10);
begin
  { Without boxes, every probe lights everything (they add up). }
  if ProbeBoxes then
  begin
    LeftProbe.InfluenceSize := RoomSize;
    RightProbe.InfluenceSize := RoomSize;
  end else
  begin
    LeftProbe.InfluenceSize := NoBox;
    RightProbe.InfluenceSize := NoBox;
  end;

  if UseIrradianceVolume then
    RightProbe.IrradianceVolume := IrradianceVolume
  else
    RightProbe.IrradianceVolume := nil;

  LabelInfo.Caption :=
    Format('Probe boxes: %s (press B)', [Iff(ProbeBoxes, 'on: each room has its probe', 'off: all probes light everything')]) + NL +
    Format('Irradiance volume in the right room: %s (press I)', [Iff(UseIrradianceVolume, 'on', 'off')]) + NL +
    'Drag with mouse to rotate the view.';
end;

procedure TViewMain.Start;
begin
  inherited;
  LeftProbe := Rooms.Node('LeftProbe') as TEnvironmentLightNode;
  RightProbe := Rooms.Node('RightProbe') as TEnvironmentLightNode;
  IrradianceVolume := CreateIrradianceVolume;
  { keep it alive while it's not used by RightProbe }
  IrradianceVolume.KeepExistingBegin;
  ProbeBoxes := true;
  UseIrradianceVolume := true;
  UpdateProbes;
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;

  if Event.IsKey(keyB) then
  begin
    ProbeBoxes := not ProbeBoxes;
    UpdateProbes;
    Exit(true);
  end;

  if Event.IsKey(keyI) then
  begin
    UseIrradianceVolume := not UseIrradianceVolume;
    UpdateProbes;
    Exit(true);
  end;
end;

end.

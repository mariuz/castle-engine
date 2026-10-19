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

{ Shadow volumes from several lights on physical (PBR) materials,
  with TCastleViewport.HighDynamicRange.

  The design (data/gameviewmain.castle-user-interface) has three colored
  point lights with Shadows = true, a few objects with physical materials,
  and a viewport with ShadowVolumesMaxLights = 3 and HighDynamicRange = true.
  Every light casting shadows is added in its own rendering pass.
  With HighDynamicRange, the passes are added in linear color space,
  and gamma correction and tone mapping are applied once, after the world
  is rendered: where the lights overlap, the result looks as if all lights
  were rendered at once (like with ShadowVolumesMaxLights = 1 and shadows off).
  Without HighDynamicRange, the passes are added after gamma correction,
  so where the lights overlap it is too bright. }
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
    MainViewport: TCastleViewport;
    Light1, Light2, Light3: TCastlePointLight;
    LabelInfo: TCastleLabel;
  private
    Lights: array [0..2] of TCastlePointLight;
    LightsTime: Single;
    LightsMove: Boolean;
    procedure UpdateLights;
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

uses SysUtils, Math, TypInfo,
  CastleUtils, CastleRenderOptions, CastleGLUtils;

const
  LightsRadius = 5.0;
  LightsHeight = 4.0;

constructor TViewMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
end;

procedure TViewMain.UpdateLights;
var
  I: Integer;
  Angle: Single;
begin
  for I := 0 to High(Lights) do
  begin
    Angle := LightsTime * 0.5 + I * 2 * Pi / Length(Lights);
    Lights[I].Translation := Vector3(
      Cos(Angle) * LightsRadius, LightsHeight, Sin(Angle) * LightsRadius);
  end;
end;

procedure TViewMain.UpdateInfo;
var
  S: String;
  I: Integer;
begin
  S := Format('HighDynamicRange: %s (press H)', [Iff(MainViewport.HighDynamicRange, 'on', 'off')]);
  { HighDynamicRange needs rendering to float color buffers. }
  if MainViewport.HighDynamicRange and not GLFeatures.ColorBufferFloat then
    S := S + ' (not supported by this GPU)';
  S := S + NL +
    Format('Tone mapping: %s (press T to change)', [GetEnumName(TypeInfo(TToneMapping), Ord(ToneMapping))]) + NL +
    Format('ShadowVolumesMaxLights: %d (press M to change)', [MainViewport.ShadowVolumesMaxLights]) + NL;
  for I := 0 to High(Lights) do
    S := S + Format('Light %d: %s (press %d to toggle)', [I + 1,
      Iff(Lights[I].Exists, 'on', 'off'), I + 1]) + NL;
  S := S +
    Format('Shadow volumes: %s (press S)', [Iff(MainViewport.ShadowVolumes, 'on', 'off')]) + NL +
    Format('Lights move: %s (press Space)', [Iff(LightsMove, 'yes', 'no')]) + NL +
    'Drag with mouse to rotate the view.';
  LabelInfo.Caption := S;
end;

procedure TViewMain.Start;
begin
  inherited;
  Lights[0] := Light1;
  Lights[1] := Light2;
  Lights[2] := Light3;
  LightsMove := true;
  UpdateLights;
  UpdateInfo;
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  if LightsMove then
  begin
    LightsTime := LightsTime + SecondsPassed;
    UpdateLights;
  end;
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
var
  I: Integer;
begin
  Result := inherited;
  if Result then Exit;

  for I := 0 to High(Lights) do
    if Event.IsKey(TKey(Ord(key1) + I)) then
    begin
      Lights[I].Exists := not Lights[I].Exists;
      UpdateInfo;
      Exit(true);
    end;

  if Event.IsKey(keyH) then
  begin
    MainViewport.HighDynamicRange := not MainViewport.HighDynamicRange;
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keyT) then
  begin
    { ToneMapping is a global setting, for all viewports and scenes.
      With HighDynamicRange it is applied once, after the world is rendered. }
    if ToneMapping = High(TToneMapping) then
      ToneMapping := Low(TToneMapping)
    else
      ToneMapping := Succ(ToneMapping);
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keyM) then
  begin
    if MainViewport.ShadowVolumesMaxLights = 1 then
      MainViewport.ShadowVolumesMaxLights := 3
    else
      MainViewport.ShadowVolumesMaxLights := 1;
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keyS) then
  begin
    MainViewport.ShadowVolumes := not MainViewport.ShadowVolumes;
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keySpace) then
  begin
    LightsMove := not LightsMove;
    UpdateInfo;
    Exit(true);
  end;
end;

end.

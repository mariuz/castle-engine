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

{ Temporal anti-aliasing: TCastleViewport.TemporalAntiAliasing
  (set in the design, data/gameviewmain.castle-user-interface)
  toggled by a key, while the camera slowly circles around the scene. }
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
    LabelInfo: TCastleLabel;
  private
    Orbit: Boolean;
    OrbitAngle: Single;
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
  Orbit := true;
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
const
  OrbitDistance = 16;
  OrbitHeight = 4;
begin
  inherited;
  { Circle slowly around the scene, looking at its center:
    the thin poles and wires flicker without anti-aliasing then. }
  if Orbit then
  begin
    OrbitAngle := OrbitAngle + SecondsPassed * 0.1;
    MainViewport.Camera.SetWorldView(
      Vector3(Sin(OrbitAngle) * OrbitDistance, OrbitHeight, Cos(OrbitAngle) * OrbitDistance),
      Vector3(-Sin(OrbitAngle), -OrbitHeight / OrbitDistance, -Cos(OrbitAngle)),
      Vector3(0, 1, 0));
  end;

  LabelInfo.Caption :=
    'FPS: ' + Container.Fps.ToString + NL +
    Format('Temporal anti-aliasing: %s (press T)', [
      Iff(MainViewport.TemporalAntiAliasing, 'on', 'off')]) + NL +
    Format('Camera circling: %s (press O; drag with mouse to rotate the view when off)', [
      Iff(Orbit, 'on', 'off')]);
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;

  if Event.IsKey(keyT) then
  begin
    MainViewport.TemporalAntiAliasing := not MainViewport.TemporalAntiAliasing;
    Exit(true);
  end;

  if Event.IsKey(keyO) then
  begin
    Orbit := not Orbit;
    Exit(true);
  end;
end;

end.

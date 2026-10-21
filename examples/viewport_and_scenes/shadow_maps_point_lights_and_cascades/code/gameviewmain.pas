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

{ Shadow maps from a point light and from a directional light with cascades
  (the lights are in data/scene.x3dv), toggled by keys. }
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
    MainScene: TCastleScene;
    LabelInfo: TCastleLabel;
  private
    Sun: TDirectionalLightNode;
    Lamp: TPointLightNode;
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
  CastleUtils, CastleRenderOptions;

constructor TViewMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
end;

procedure TViewMain.Start;
begin
  inherited;
  Sun := MainScene.Node(TDirectionalLightNode, 'Sun') as TDirectionalLightNode;
  Lamp := MainScene.Node(TPointLightNode, 'Lamp') as TPointLightNode;
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  LabelInfo.Caption :=
    'FPS: ' + Container.Fps.ToString + NL +
    Format('Sun: %s, cascades: %d (press 1 to toggle the sun, C to change the cascades)', [
      Iff(Sun.IsOn, 'on', 'off'), Sun.ShadowCascades]) + NL +
    Format('Blending between the cascades: %s (press B to toggle)', [
      Iff(ShadowMapsCascadeBlend > 0, 'on', 'off')]) + NL +
    Format('Point light: %s (press 2 to toggle)', [Iff(Lamp.IsOn, 'on', 'off')]) + NL +
    Format('Shadow map size by the size on the screen: %s (press Z to toggle)', [
      Iff(ShadowMapsSizeByScreen, 'on', 'off')]) + NL +
    'Walk with AWSD and the mouse (drag), like in a FPS game.';
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;

  if Event.IsKey(key1) then
  begin
    Sun.IsOn := not Sun.IsOn;
    Exit(true);
  end;

  if Event.IsKey(key2) then
  begin
    Lamp.IsOn := not Lamp.IsOn;
    Exit(true);
  end;

  if Event.IsKey(keyB) then
  begin
    if ShadowMapsCascadeBlend > 0 then
      ShadowMapsCascadeBlend := 0
    else
      ShadowMapsCascadeBlend := 0.1;
    Exit(true);
  end;

  if Event.IsKey(keyZ) then
  begin
    ShadowMapsSizeByScreen := not ShadowMapsSizeByScreen;
    Exit(true);
  end;

  if Event.IsKey(keyC) then
  begin
    { 1 cascade (one shadow map over the whole world) up to 4 }
    if Sun.ShadowCascades >= 4 then
      Sun.ShadowCascades := 1
    else
      Sun.ShadowCascades := Sun.ShadowCascades + 1;
    Exit(true);
  end;
end;

end.

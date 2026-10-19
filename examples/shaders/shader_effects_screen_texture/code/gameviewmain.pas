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

{ Shader effects that show the screen behind a shape, distorted:
  glass and heat haze, using ScreenTexture.

  The design (data/gameviewmain.castle-user-interface) has a few objects
  and data/glass.x3dv: two panes with an Effect that samples a ScreenTexture
  (see data/shaders/screen_distortion.fs).
  Here we only turn the effects off and on. }
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
    SceneGlass: TCastleScene;
  private
    GlassEffect, HazeEffect: TEffectNode;
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
  GlassEffect := SceneGlass.Node('GlassEffect') as TEffectNode;
  HazeEffect := SceneGlass.Node('HazeEffect') as TEffectNode;
  UpdateInfo;
end;

procedure TViewMain.UpdateInfo;
begin
  LabelInfo.Caption :=
    'Glass (left) and heat haze (right) show the screen behind them, distorted.' + NL +
    Format('Effects: %s (press E to change)', [Iff(GlassEffect.Enabled, 'on', 'off')]) + NL +
    'Drag with mouse to rotate the view.';
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keyE) then
  begin
    { Without the effects, the panes are plain white (unlit material). }
    GlassEffect.Enabled := not GlassEffect.Enabled;
    HazeEffect.Enabled := GlassEffect.Enabled;
    UpdateInfo;
    Exit(true);
  end;
end;

end.

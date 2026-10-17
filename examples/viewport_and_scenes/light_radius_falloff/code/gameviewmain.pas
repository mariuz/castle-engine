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

{ Lights cut off at their radius, or fading smoothly to zero there (RadiusFalloff).

  The design (data/gameviewmain.castle-user-interface) has two point lights
  over a floor, with the same radius and no attenuation.
  The left one is cut off at its radius, the right one has RadiusFalloff. }
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
    LabelInfo: TCastleLabel;
    LightLeft, LightRight: TCastlePointLight;
  private
    procedure UpdateInfo;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMain: TViewMain;

implementation

uses SysUtils, Math,
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

  function FalloffStr(const Light: TCastlePointLight): String;
  begin
    Result := Iff(Light.RadiusFalloff, 'fades to zero at the radius', 'cut off at the radius');
  end;

begin
  LabelInfo.Caption :=
    'Left light: ' + FalloffStr(LightLeft) + NL +
    'Right light: ' + FalloffStr(LightRight) + NL +
    'Press F to switch them.' + NL +
    Format('Radius: %f (press + / - to change)', [LightLeft.Radius]) + NL +
    'Drag with mouse to rotate the view.';
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;

  procedure SetRadius(const Value: Single);
  begin
    LightLeft.Radius := Value;
    LightRight.Radius := Value;
    UpdateInfo;
  end;

begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keyF) then
  begin
    LightLeft.RadiusFalloff := not LightLeft.RadiusFalloff;
    LightRight.RadiusFalloff := not LightRight.RadiusFalloff;
    UpdateInfo;
    Exit(true);
  end;

  if Event.IsKey(keyPlus) or Event.IsKey(keyNumpadPlus) then
  begin
    SetRadius(Min(LightLeft.Radius + 0.5, 8));
    Exit(true);
  end;

  if Event.IsKey(keyMinus) or Event.IsKey(keyNumpadMinus) then
  begin
    SetRadius(Max(LightLeft.Radius - 0.5, 1));
    Exit(true);
  end;
end;

end.

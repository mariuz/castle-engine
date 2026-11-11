{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Real-Time 3D VFX Particle Emitter & Preset Studio (@link(TParticleStudioForm))
  for @link(TCastleParticleEmitter), featuring 1-click Niagara-style presets,
  live burst testing, color/alpha/size-over-life gradient preview, and scene
  particle budget diagnostics (Phase 289 — UE 5.9 / 6.0 Niagara VFX Parity). }
unit FormParticleStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Spin,
  Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleViewport, CastleParticles, ToolParticleStudio;

type
  TParticleStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TParticleStudioRefreshViewportCallback = procedure of object;

  TParticleStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TParticleStudioModifiedCallback;
    FOnRefreshViewport: TParticleStudioRefreshViewportCallback;

    FBudgetReport: TParticleWorldBudgetReport;
    FLoadingControls: Boolean;
    FPreviewTimer: TTimer;

    { Top bar }
    ComboEmitter: TComboBox;
    ButtonSpawnNew: TButton;
    ButtonEmitBurst: TButton;
    ButtonClearAll: TButton;
    ButtonToggleLiveSim: TButton;
    ButtonCopyBudget: TButton;

    { Left preset gallery + gradient strip }
    PanelLeft: TPanel;
    ButtonPresetFire: TButton;
    ButtonPresetSmoke: TButton;
    ButtonPresetSparks: TButton;
    ButtonPresetMagic: TButton;
    ButtonPresetSnow: TButton;
    ButtonPresetExplosion: TButton;
    PaintBoxGradient: TPaintBox;
    LabelBudgetSummary: TLabel;
    ListBudgetEmitters: TListBox;

    { Right parameter editor }
    PanelParams: TPanel;
    ComboShape: TComboBox;
    ComboBlendMode: TComboBox;
    CheckEmitting: TCheckBox;
    CheckPreviewInEditor: TCheckBox;
    SpinMaxParticles: TSpinEdit;
    SpinSpawnRate: TFloatSpinEdit;
    SpinShapeRadius: TFloatSpinEdit;
    SpinConeAngle: TFloatSpinEdit;
    SpinLifeMin: TFloatSpinEdit;
    SpinLifeMax: TFloatSpinEdit;
    SpinSpeedMin: TFloatSpinEdit;
    SpinSpeedMax: TFloatSpinEdit;
    SpinSizeStart: TFloatSpinEdit;
    SpinSizeEnd: TFloatSpinEdit;
    SpinGravity: TFloatSpinEdit;
    SpinDrag: TFloatSpinEdit;
    SpinTurbulence: TFloatSpinEdit;
    ColorBtnStart: TColorButton;
    SpinAlphaStart: TFloatSpinEdit;
    ColorBtnEnd: TColorButton;
    SpinAlphaEnd: TFloatSpinEdit;
    ButtonApplyParams: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveEmitter: TCastleParticleEmitter;
    function ComputeDefaultSpawnPos: TVector3;
    procedure RefreshEmitterList(const SelectEmitter: TCastleParticleEmitter = nil);
    procedure LoadControlsFromEmitter;
    procedure UpdateBudgetSummaryUi;
    procedure ApplySelectedPreset(const APreset: TVfxParticlePreset);
    procedure NotifyModified(const Comment: String);
    procedure NotifyViewportRefresh;

    procedure ComboEmitterChange(Sender: TObject);
    procedure ButtonSpawnNewClick(Sender: TObject);
    procedure ButtonEmitBurstClick(Sender: TObject);
    procedure ButtonClearAllClick(Sender: TObject);
    procedure ButtonToggleLiveSimClick(Sender: TObject);
    procedure ButtonCopyBudgetClick(Sender: TObject);
    procedure PreviewTimerTick(Sender: TObject);

    procedure ButtonPresetFireClick(Sender: TObject);
    procedure ButtonPresetSmokeClick(Sender: TObject);
    procedure ButtonPresetSparksClick(Sender: TObject);
    procedure ButtonPresetMagicClick(Sender: TObject);
    procedure ButtonPresetSnowClick(Sender: TObject);
    procedure ButtonPresetExplosionClick(Sender: TObject);
    procedure PaintBoxGradientPaint(Sender: TObject);
    procedure ButtonApplyParamsClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TParticleStudioModifiedCallback;
      const AOnRefreshViewport: TParticleStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

uses
  CastleUIControls;

function CastleColorToTColor(const C: TCastleColor): TColor;
begin
  Result := RGBToColor(
    Clamped(Round(C.X * 255), 0, 255),
    Clamped(Round(C.Y * 255), 0, 255),
    Clamped(Round(C.Z * 255), 0, 255));
end;

function TColorAndAlphaToCastleColor(const Col: TColor; const Alpha: Single): TCastleColor;
var
  R, G, B: Byte;
begin
  RedGreenBlue(ColorToRGB(Col), R, G, B);
  Result := Vector4(R / 255.0, G / 255.0, B / 255.0, Clamped(Alpha, 0.0, 1.0));
end;

constructor TParticleStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TParticleStudioModifiedCallback;
  const AOnRefreshViewport: TParticleStudioRefreshViewportCallback);
var
  InitEmitter: TCastleParticleEmitter;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FLoadingControls := false;

  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Interval := 33;
  FPreviewTimer.Enabled := true;
  FPreviewTimer.OnTimer := @PreviewTimerTick;

  BuildUi;

  if AInitialSelected is TCastleParticleEmitter then
    InitEmitter := TCastleParticleEmitter(AInitialSelected)
  else
    InitEmitter := nil;

  RefreshEmitterList(InitEmitter);
end;

destructor TParticleStudioForm.Destroy;
begin
  if FPreviewTimer <> nil then
    FPreviewTimer.Enabled := false;
  inherited Destroy;
end;

procedure TParticleStudioForm.BuildUi;

  function AddParamLabel(const AParent: TWinControl; const ACaption: String;
    const L, T: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Left := L;
    Result.Top := T;
  end;

  function AddFloatSpin(const AParent: TWinControl;
    const L, T: Integer; const AMin, AMax, AInc: Double): TFloatSpinEdit;
  begin
    Result := TFloatSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.Left := L;
    Result.Top := T;
    Result.Width := 96;
    Result.DecimalPlaces := 2;
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Increment := AInc;
  end;

var
  PanelTop, PanelBottom: TPanel;
  Lbl: TLabel;
begin
  Caption := 'Real-Time 3D VFX Particle Emitter & Preset Studio (Niagara Parity)';
  Position := poScreenCenter;
  Width := 1040;
  Height := 660;
  Constraints.MinWidth := 920;
  Constraints.MinHeight := 580;

  { Top bar }
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelTop;
  Lbl.Caption := 'Emitter:';
  Lbl.Left := 10;
  Lbl.Top := 13;

  ComboEmitter := TComboBox.Create(Self);
  ComboEmitter.Parent := PanelTop;
  ComboEmitter.Style := csDropDownList;
  ComboEmitter.Left := 68;
  ComboEmitter.Top := 9;
  ComboEmitter.Width := 230;
  ComboEmitter.OnChange := @ComboEmitterChange;

  ButtonSpawnNew := TButton.Create(Self);
  ButtonSpawnNew.Parent := PanelTop;
  ButtonSpawnNew.Caption := '+ Spawn VFX Emitter';
  ButtonSpawnNew.Left := 306;
  ButtonSpawnNew.Top := 8;
  ButtonSpawnNew.Width := 148;
  ButtonSpawnNew.Height := 28;
  ButtonSpawnNew.OnClick := @ButtonSpawnNewClick;

  ButtonEmitBurst := TButton.Create(Self);
  ButtonEmitBurst.Parent := PanelTop;
  ButtonEmitBurst.Caption := 'Emit Burst (+40)';
  ButtonEmitBurst.Left := 462;
  ButtonEmitBurst.Top := 8;
  ButtonEmitBurst.Width := 126;
  ButtonEmitBurst.Height := 28;
  ButtonEmitBurst.OnClick := @ButtonEmitBurstClick;

  ButtonClearAll := TButton.Create(Self);
  ButtonClearAll.Parent := PanelTop;
  ButtonClearAll.Caption := 'Clear Particles';
  ButtonClearAll.Left := 594;
  ButtonClearAll.Top := 8;
  ButtonClearAll.Width := 112;
  ButtonClearAll.Height := 28;
  ButtonClearAll.OnClick := @ButtonClearAllClick;

  ButtonToggleLiveSim := TButton.Create(Self);
  ButtonToggleLiveSim.Parent := PanelTop;
  ButtonToggleLiveSim.Caption := 'Pause Live Sim';
  ButtonToggleLiveSim.Left := 712;
  ButtonToggleLiveSim.Top := 8;
  ButtonToggleLiveSim.Width := 122;
  ButtonToggleLiveSim.Height := 28;
  ButtonToggleLiveSim.OnClick := @ButtonToggleLiveSimClick;

  ButtonCopyBudget := TButton.Create(Self);
  ButtonCopyBudget.Parent := PanelTop;
  ButtonCopyBudget.Caption := 'Copy Budget MD';
  ButtonCopyBudget.Left := 840;
  ButtonCopyBudget.Top := 8;
  ButtonCopyBudget.Width := 132;
  ButtonCopyBudget.Height := 28;
  ButtonCopyBudget.OnClick := @ButtonCopyBudgetClick;

  { Bottom bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Caption := 'Close';
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.Left := Width - 102;
  ButtonClose.Top := 6;
  ButtonClose.Width := 88;
  ButtonClose.Height := 28;
  ButtonClose.OnClick := @ButtonCloseClick;

  { Left preset gallery + gradient curve + scene budget }
  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := AddParamLabel(PanelLeft, '1-Click Niagara VFX Presets:', 10, 8);
  Lbl.Font.Style := [Graphics.fsBold];

  ButtonPresetFire := TButton.Create(Self);
  ButtonPresetFire.Parent := PanelLeft;
  ButtonPresetFire.Caption := 'Fire / Torch';
  ButtonPresetFire.SetBounds(10, 30, 128, 30);
  ButtonPresetFire.OnClick := @ButtonPresetFireClick;

  ButtonPresetSmoke := TButton.Create(Self);
  ButtonPresetSmoke.Parent := PanelLeft;
  ButtonPresetSmoke.Caption := 'Billowing Smoke';
  ButtonPresetSmoke.SetBounds(144, 30, 128, 30);
  ButtonPresetSmoke.OnClick := @ButtonPresetSmokeClick;

  ButtonPresetSparks := TButton.Create(Self);
  ButtonPresetSparks.Parent := PanelLeft;
  ButtonPresetSparks.Caption := 'Welding Sparks';
  ButtonPresetSparks.SetBounds(278, 30, 128, 30);
  ButtonPresetSparks.OnClick := @ButtonPresetSparksClick;

  ButtonPresetMagic := TButton.Create(Self);
  ButtonPresetMagic.Parent := PanelLeft;
  ButtonPresetMagic.Caption := 'Magic Portal Ring';
  ButtonPresetMagic.SetBounds(10, 66, 128, 30);
  ButtonPresetMagic.OnClick := @ButtonPresetMagicClick;

  ButtonPresetSnow := TButton.Create(Self);
  ButtonPresetSnow.Parent := PanelLeft;
  ButtonPresetSnow.Caption := 'Snow / Rain Box';
  ButtonPresetSnow.SetBounds(144, 66, 128, 30);
  ButtonPresetSnow.OnClick := @ButtonPresetSnowClick;

  ButtonPresetExplosion := TButton.Create(Self);
  ButtonPresetExplosion.Parent := PanelLeft;
  ButtonPresetExplosion.Caption := 'Explosion Burst';
  ButtonPresetExplosion.SetBounds(278, 66, 128, 30);
  ButtonPresetExplosion.OnClick := @ButtonPresetExplosionClick;

  Lbl := AddParamLabel(PanelLeft, 'Color, Alpha & Size Envelope Over Lifetime (t = 0 -> 1):', 10, 108);
  Lbl.Font.Style := [Graphics.fsBold];

  PaintBoxGradient := TPaintBox.Create(Self);
  PaintBoxGradient.Parent := PanelLeft;
  PaintBoxGradient.SetBounds(10, 130, 396, 86);
  PaintBoxGradient.OnPaint := @PaintBoxGradientPaint;

  Lbl := AddParamLabel(PanelLeft, 'Scene VFX Particle Budget Diagnostics:', 10, 228);
  Lbl.Font.Style := [Graphics.fsBold];

  LabelBudgetSummary := TLabel.Create(Self);
  LabelBudgetSummary.Parent := PanelLeft;
  LabelBudgetSummary.SetBounds(10, 250, 396, 36);
  LabelBudgetSummary.AutoSize := false;
  LabelBudgetSummary.WordWrap := true;

  ListBudgetEmitters := TListBox.Create(Self);
  ListBudgetEmitters.Parent := PanelLeft;
  ListBudgetEmitters.SetBounds(10, 290, 396, 265);
  ListBudgetEmitters.Anchors := [akTop, akLeft, akBottom];

  { Right parameters editor }
  PanelParams := TPanel.Create(Self);
  PanelParams.Parent := Self;
  PanelParams.Align := alClient;
  PanelParams.BevelOuter := bvLowered;
  PanelParams.BorderSpacing.Around := 6;

  Lbl := AddParamLabel(PanelParams, 'Emitter Shape, Physics & Lifetime Curves:', 14, 10);
  Lbl.Font.Style := [Graphics.fsBold];

  AddParamLabel(PanelParams, 'Shape:', 14, 42);
  ComboShape := TComboBox.Create(Self);
  ComboShape.Parent := PanelParams;
  ComboShape.Style := csDropDownList;
  ComboShape.Items.Add('Point');
  ComboShape.Items.Add('Sphere');
  ComboShape.Items.Add('Cone');
  ComboShape.Items.Add('Box');
  ComboShape.Items.Add('Circle Ring');
  ComboShape.SetBounds(110, 38, 136, 26);

  AddParamLabel(PanelParams, 'Blend Mode:', 268, 42);
  ComboBlendMode := TComboBox.Create(Self);
  ComboBlendMode.Parent := PanelParams;
  ComboBlendMode.Style := csDropDownList;
  ComboBlendMode.Items.Add('Alpha Blend');
  ComboBlendMode.Items.Add('Additive Glow');
  ComboBlendMode.SetBounds(360, 38, 150, 26);

  CheckEmitting := TCheckBox.Create(Self);
  CheckEmitting.Parent := PanelParams;
  CheckEmitting.Caption := 'Continuous Emitting';
  CheckEmitting.Left := 14;
  CheckEmitting.Top := 74;

  CheckPreviewInEditor := TCheckBox.Create(Self);
  CheckPreviewInEditor.Parent := PanelParams;
  CheckPreviewInEditor.Caption := 'Live Preview in 3D Viewport';
  CheckPreviewInEditor.Left := 210;
  CheckPreviewInEditor.Top := 74;

  AddParamLabel(PanelParams, 'Max Particles:', 14, 112);
  SpinMaxParticles := TSpinEdit.Create(Self);
  SpinMaxParticles.Parent := PanelParams;
  SpinMaxParticles.MinValue := 1;
  SpinMaxParticles.MaxValue := 8192;
  SpinMaxParticles.SetBounds(126, 108, 96, 26);

  AddParamLabel(PanelParams, 'Spawn Rate (/s):', 258, 112);
  SpinSpawnRate := AddFloatSpin(PanelParams, 384, 108, 0.0, 2000.0, 4.0);

  AddParamLabel(PanelParams, 'Shape Radius:', 14, 148);
  SpinShapeRadius := AddFloatSpin(PanelParams, 126, 144, 0.0, 100.0, 0.1);

  AddParamLabel(PanelParams, 'Cone Angle (deg):', 258, 148);
  SpinConeAngle := AddFloatSpin(PanelParams, 384, 144, 0.0, 89.0, 2.0);

  AddParamLabel(PanelParams, 'Lifetime Min (s):', 14, 184);
  SpinLifeMin := AddFloatSpin(PanelParams, 126, 180, 0.05, 60.0, 0.1);

  AddParamLabel(PanelParams, 'Lifetime Max (s):', 258, 184);
  SpinLifeMax := AddFloatSpin(PanelParams, 384, 180, 0.05, 60.0, 0.1);

  AddParamLabel(PanelParams, 'Speed Min (m/s):', 14, 220);
  SpinSpeedMin := AddFloatSpin(PanelParams, 126, 216, 0.0, 200.0, 0.25);

  AddParamLabel(PanelParams, 'Speed Max (m/s):', 258, 220);
  SpinSpeedMax := AddFloatSpin(PanelParams, 384, 216, 0.0, 200.0, 0.25);

  AddParamLabel(PanelParams, 'Size Start (m):', 14, 256);
  SpinSizeStart := AddFloatSpin(PanelParams, 126, 252, 0.01, 25.0, 0.05);

  AddParamLabel(PanelParams, 'Size End (m):', 258, 256);
  SpinSizeEnd := AddFloatSpin(PanelParams, 384, 252, 0.0, 25.0, 0.05);

  AddParamLabel(PanelParams, 'Gravity Factor:', 14, 292);
  SpinGravity := AddFloatSpin(PanelParams, 126, 288, -10.0, 10.0, 0.1);

  AddParamLabel(PanelParams, 'Linear Drag:', 258, 292);
  SpinDrag := AddFloatSpin(PanelParams, 384, 288, 0.0, 20.0, 0.1);

  AddParamLabel(PanelParams, '3D Turbulence:', 14, 328);
  SpinTurbulence := AddFloatSpin(PanelParams, 126, 324, 0.0, 25.0, 0.15);

  AddParamLabel(PanelParams, 'Start Color / Alpha:', 14, 370);
  ColorBtnStart := TColorButton.Create(Self);
  ColorBtnStart.Parent := PanelParams;
  ColorBtnStart.SetBounds(146, 365, 86, 28);
  SpinAlphaStart := AddFloatSpin(PanelParams, 240, 366, 0.0, 1.0, 0.05);

  AddParamLabel(PanelParams, 'End Color / Alpha:', 14, 408);
  ColorBtnEnd := TColorButton.Create(Self);
  ColorBtnEnd.Parent := PanelParams;
  ColorBtnEnd.SetBounds(146, 403, 86, 28);
  SpinAlphaEnd := AddFloatSpin(PanelParams, 240, 404, 0.0, 1.0, 0.05);

  ButtonApplyParams := TButton.Create(Self);
  ButtonApplyParams.Parent := PanelParams;
  ButtonApplyParams.Caption := 'Apply Parameter Changes to Emitter';
  ButtonApplyParams.SetBounds(14, 452, 260, 34);
  ButtonApplyParams.OnClick := @ButtonApplyParamsClick;
end;

function TParticleStudioForm.ActiveEmitter: TCastleParticleEmitter;
var
  Idx: Integer;
begin
  Idx := ComboEmitter.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FBudgetReport.Emitters)) then
    Result := FBudgetReport.Emitters[Idx].Emitter
  else
    Result := nil;
end;

function TParticleStudioForm.ComputeDefaultSpawnPos: TVector3;
var
  I: Integer;
  VP: TCastleViewport;
  UI: TCastleUserInterface;
  Pos, Dir, Up: TVector3;
begin
  Result := Vector3(0, 1.5, 0);
  VP := nil;
  if FRootComponent is TCastleViewport then
    VP := TCastleViewport(FRootComponent)
  else if FRootComponent is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(FRootComponent);
    for I := 0 to UI.ControlsCount - 1 do
      if UI.Controls[I] is TCastleViewport then
      begin
        VP := TCastleViewport(UI.Controls[I]);
        Break;
      end;
  end;
  if (VP <> nil) and (VP.Camera <> nil) then
  begin
    VP.Camera.GetWorldView(Pos, Dir, Up);
    Result := Pos + Dir * 5.0;
  end;
end;

procedure TParticleStudioForm.RefreshEmitterList(
  const SelectEmitter: TCastleParticleEmitter);
var
  I, SelIdx: Integer;
begin
  FBudgetReport := TParticleStudioHelper.ScanEmittersAndBudget(FRootComponent);
  ComboEmitter.Items.BeginUpdate;
  try
    ComboEmitter.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FBudgetReport.Emitters) do
    begin
      ComboEmitter.Items.Add(Format('%s [%s - %s]',
        [FBudgetReport.Emitters[I].EmitterName,
         FBudgetReport.Emitters[I].PresetName,
         FBudgetReport.Emitters[I].ShapeName]));
      if FBudgetReport.Emitters[I].Emitter = SelectEmitter then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FBudgetReport.Emitters) > 0) then
      SelIdx := 0;
    ComboEmitter.ItemIndex := SelIdx;
  finally
    ComboEmitter.Items.EndUpdate;
  end;

  LoadControlsFromEmitter;
  UpdateBudgetSummaryUi;
end;

procedure TParticleStudioForm.LoadControlsFromEmitter;
var
  E: TCastleParticleEmitter;
begin
  E := ActiveEmitter;
  PanelParams.Enabled := E <> nil;
  if E = nil then
  begin
    PaintBoxGradient.Invalidate;
    Exit;
  end;

  FLoadingControls := true;
  try
    ComboShape.ItemIndex := Ord(E.Shape);
    ComboBlendMode.ItemIndex := Ord(E.BlendMode);
    CheckEmitting.Checked := E.Emitting;
    CheckPreviewInEditor.Checked := E.PreviewInEditor;
    SpinMaxParticles.Value := E.MaxParticles;
    SpinSpawnRate.Value := E.SpawnRate;
    SpinShapeRadius.Value := E.ShapeRadius;
    SpinConeAngle.Value := E.ConeAngleDeg;
    SpinLifeMin.Value := E.LifetimeMin;
    SpinLifeMax.Value := E.LifetimeMax;
    SpinSpeedMin.Value := E.SpeedMin;
    SpinSpeedMax.Value := E.SpeedMax;
    SpinSizeStart.Value := E.SizeStart;
    SpinSizeEnd.Value := E.SizeEnd;
    SpinGravity.Value := E.GravityFactor;
    SpinDrag.Value := E.Drag;
    SpinTurbulence.Value := E.Turbulence;
    ColorBtnStart.ButtonColor := CastleColorToTColor(E.ColorStart);
    SpinAlphaStart.Value := E.ColorStart.W;
    ColorBtnEnd.ButtonColor := CastleColorToTColor(E.ColorEnd);
    SpinAlphaEnd.Value := E.ColorEnd.W;
  finally
    FLoadingControls := false;
  end;
  PaintBoxGradient.Invalidate;
end;

procedure TParticleStudioForm.UpdateBudgetSummaryUi;
var
  I: Integer;
  Info: TParticleEmitterBudgetInfo;
begin
  FBudgetReport := TParticleStudioHelper.ScanEmittersAndBudget(FRootComponent);
  LabelBudgetSummary.Caption := Format(
    'Emitters: %d | Live Particles: %d / %d Peak | Live Tris: %d / %d Peak',
    [FBudgetReport.EmitterCount, FBudgetReport.TotalActiveParticles,
     FBudgetReport.TotalMaxParticles, FBudgetReport.TotalActiveTriangles,
     FBudgetReport.TotalPeakTriangles]);
  if FBudgetReport.OverBudgetWarning then
    LabelBudgetSummary.Font.Color := $4858F8
  else
    LabelBudgetSummary.Font.Color := clDefault;

  ListBudgetEmitters.Items.BeginUpdate;
  try
    ListBudgetEmitters.Items.Clear;
    for I := 0 to High(FBudgetReport.Emitters) do
    begin
      Info := FBudgetReport.Emitters[I];
      ListBudgetEmitters.Items.Add(Format('%s [%s]  %d / %d particles  (%.0f/s, %d peak tris)',
        [Info.EmitterName, Info.PresetName, Info.ActiveParticles,
         Info.MaxParticles, Info.SpawnRate, Info.PeakTriangles]));
    end;
  finally
    ListBudgetEmitters.Items.EndUpdate;
  end;
end;

procedure TParticleStudioForm.PaintBoxGradientPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, X, Y, Checker: Integer;
  E: TCastleParticleEmitter;
  CStart, CEnd, Sample: TCastleColor;
  MaxSz, SzT, HalfBand: Single;
  BgLum: Byte;
  R, G, B: Byte;
begin
  C := PaintBoxGradient.Canvas;
  W := PaintBoxGradient.Width;
  H := PaintBoxGradient.Height;

  E := ActiveEmitter;
  if E <> nil then
  begin
    CStart := E.ColorStart;
    CEnd := E.ColorEnd;
    MaxSz := Max(0.01, Max(E.SizeStart, E.SizeEnd));
  end else
  begin
    CStart := Vector4(1.0, 0.72, 0.18, 0.95);
    CEnd := Vector4(0.85, 0.12, 0.02, 0.0);
    MaxSz := 1.0;
  end;

  { Checkerboard + blended color-over-life gradient }
  for X := 0 to W - 1 do
  begin
    Sample := Lerp(X / Max(1, W - 1), CStart, CEnd);
    for Y := 0 to H - 1 do
    begin
      Checker := ((X div 10) + (Y div 10)) and 1;
      BgLum := IfThen(Checker = 0, 38, 58);
      R := Clamped(Round(BgLum * (1.0 - Sample.W) + Sample.X * 255.0 * Sample.W), 0, 255);
      G := Clamped(Round(BgLum * (1.0 - Sample.W) + Sample.Y * 255.0 * Sample.W), 0, 255);
      B := Clamped(Round(BgLum * (1.0 - Sample.W) + Sample.Z * 255.0 * Sample.W), 0, 255);
      C.Pixels[X, Y] := RGBToColor(R, G, B);
    end;
  end;

  { Size-over-life white envelope curves }
  if E <> nil then
  begin
    C.Pen.Color := clWhite;
    C.Pen.Width := 2;
    for X := 0 to W - 2 do
    begin
      SzT := Lerp(X / Max(1, W - 1), E.SizeStart, E.SizeEnd) / MaxSz;
      HalfBand := SzT * (H * 0.42);
      C.Pixels[X, Round(H * 0.5 - HalfBand)] := clWhite;
      C.Pixels[X, Round(H * 0.5 + HalfBand)] := clWhite;
    end;
    C.Pen.Width := 1;
  end;
end;

procedure TParticleStudioForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  NotifyViewportRefresh;
end;

procedure TParticleStudioForm.NotifyViewportRefresh;
begin
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TParticleStudioForm.ComboEmitterChange(Sender: TObject);
begin
  LoadControlsFromEmitter;
end;

procedure TParticleStudioForm.ButtonSpawnNewClick(Sender: TObject);
var
  NewE: TCastleParticleEmitter;
begin
  NewE := TParticleStudioHelper.CreateEmitterInDesign(
    FRootComponent, FDesignOwner, vfxFire, ComputeDefaultSpawnPos);
  if NewE = nil then
  begin
    MessageDlg('Spawn VFX Emitter',
      'Open a 3D TCastleTransform or TCastleViewport design first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  NewE.EmitBurst(24);
  NotifyModified('Spawn TCastleParticleEmitter ' + NewE.Name);
  RefreshEmitterList(NewE);
end;

procedure TParticleStudioForm.ButtonEmitBurstClick(Sender: TObject);
var
  E: TCastleParticleEmitter;
begin
  E := ActiveEmitter;
  if E <> nil then
    E.EmitBurst(40)
  else
    TParticleStudioHelper.TriggerAllBursts(FRootComponent, 40);
  UpdateBudgetSummaryUi;
  NotifyViewportRefresh;
end;

procedure TParticleStudioForm.ButtonClearAllClick(Sender: TObject);
begin
  TParticleStudioHelper.ClearAllEmitters(FRootComponent);
  UpdateBudgetSummaryUi;
  NotifyViewportRefresh;
end;

procedure TParticleStudioForm.ButtonToggleLiveSimClick(Sender: TObject);
begin
  FPreviewTimer.Enabled := not FPreviewTimer.Enabled;
  if FPreviewTimer.Enabled then
    ButtonToggleLiveSim.Caption := 'Pause Live Sim'
  else
    ButtonToggleLiveSim.Caption := 'Start Live Sim';
end;

procedure TParticleStudioForm.ButtonCopyBudgetClick(Sender: TObject);
begin
  UpdateBudgetSummaryUi;
  Clipboard.AsText := TParticleStudioHelper.FormatBudgetMarkdown(FBudgetReport);
  MessageDlg('Copied VFX Budget Report',
    'Markdown particle budget report copied to clipboard.',
    mtInformation, [mbOK], 0);
end;

procedure TParticleStudioForm.PreviewTimerTick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FBudgetReport.Emitters) do
    if FBudgetReport.Emitters[I].Emitter.PreviewInEditor then
      FBudgetReport.Emitters[I].Emitter.SimulateStep(0.033);
  UpdateBudgetSummaryUi;
  NotifyViewportRefresh;
end;

procedure TParticleStudioForm.ApplySelectedPreset(const APreset: TVfxParticlePreset);
var
  E: TCastleParticleEmitter;
begin
  E := ActiveEmitter;
  if E = nil then
  begin
    E := TParticleStudioHelper.CreateEmitterInDesign(
      FRootComponent, FDesignOwner, APreset, ComputeDefaultSpawnPos);
    if E = nil then
      Exit;
    E.EmitBurst(24);
    NotifyModified('Spawn ' + VfxPresetToString(APreset) + ' VFX emitter');
    RefreshEmitterList(E);
    Exit;
  end;
  E.ApplyPreset(APreset);
  E.ClearParticles;
  E.EmitBurst(24);
  NotifyModified('Apply ' + VfxPresetToString(APreset) + ' VFX preset to ' + E.Name);
  RefreshEmitterList(E);
end;

procedure TParticleStudioForm.ButtonPresetFireClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxFire);
end;

procedure TParticleStudioForm.ButtonPresetSmokeClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxSmoke);
end;

procedure TParticleStudioForm.ButtonPresetSparksClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxSparks);
end;

procedure TParticleStudioForm.ButtonPresetMagicClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxMagicPortal);
end;

procedure TParticleStudioForm.ButtonPresetSnowClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxSnowRain);
end;

procedure TParticleStudioForm.ButtonPresetExplosionClick(Sender: TObject);
begin
  ApplySelectedPreset(vfxExplosionBurst);
end;

procedure TParticleStudioForm.ButtonApplyParamsClick(Sender: TObject);
var
  E: TCastleParticleEmitter;
begin
  E := ActiveEmitter;
  if (E = nil) or FLoadingControls then
    Exit;
  E.Preset := vfxCustom;
  E.Shape := TParticleEmitterShape(Clamped(ComboShape.ItemIndex, 0, Ord(High(TParticleEmitterShape))));
  E.BlendMode := TParticleBlendMode(Clamped(ComboBlendMode.ItemIndex, 0, Ord(High(TParticleBlendMode))));
  E.Emitting := CheckEmitting.Checked;
  E.PreviewInEditor := CheckPreviewInEditor.Checked;
  E.MaxParticles := SpinMaxParticles.Value;
  E.SpawnRate := SpinSpawnRate.Value;
  E.ShapeRadius := SpinShapeRadius.Value;
  E.ConeAngleDeg := SpinConeAngle.Value;
  E.LifetimeMin := SpinLifeMin.Value;
  E.LifetimeMax := SpinLifeMax.Value;
  E.SpeedMin := SpinSpeedMin.Value;
  E.SpeedMax := SpinSpeedMax.Value;
  E.SizeStart := SpinSizeStart.Value;
  E.SizeEnd := SpinSizeEnd.Value;
  E.GravityFactor := SpinGravity.Value;
  E.Drag := SpinDrag.Value;
  E.Turbulence := SpinTurbulence.Value;
  E.ColorStart := TColorAndAlphaToCastleColor(ColorBtnStart.ButtonColor, SpinAlphaStart.Value);
  E.ColorEnd := TColorAndAlphaToCastleColor(ColorBtnEnd.ButtonColor, SpinAlphaEnd.Value);

  PaintBoxGradient.Invalidate;
  UpdateBudgetSummaryUi;
  NotifyModified('Modify VFX particle emitter ' + E.Name);
end;

procedure TParticleStudioForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.

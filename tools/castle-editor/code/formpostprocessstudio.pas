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

{ Interactive Priority-Blended Post-Processing Volumes & Cinematic Look-Dev
  Studio (@link(TPostProcessStudioForm))
  (Phase 293 — UE 5.9 / 6.0 APostProcessVolume Parity). }
unit FormPostProcessStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleUtils, CastleViewport,
  CastlePostProcessVolume, ToolPostProcessStudio;

type
  TPostProcessStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TPostProcessStudioRefreshViewportCallback = procedure of object;

  TPostProcessStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TPostProcessStudioModifiedCallback;
    FOnRefreshViewport: TPostProcessStudioRefreshViewportCallback;

    FSummary: TPostProcessStudioSummary;
    FUpdatingUi: Boolean;

    { Top toolbar }
    ButtonAddGlobal: TButton;
    ButtonAddLocal: TButton;
    ButtonApplyLiveViewport: TButton;
    ButtonCopyMarkdown: TButton;

    { 6 Cinematic Preset Buttons }
    PresetButtons: array [TCastlePostProcessPreset] of TButton;

    { Center split-screen Before / After Look-Dev Canvas }
    PaintBoxPreview: TPaintBox;

    { Right Volume & Grading Inspector }
    ComboVolume: TComboBox;
    CheckUnbound: TCheckBox;
    SpinPriority: TSpinEdit;
    SpinCoreRadius: TFloatSpinEdit;
    SpinBlendRadius: TFloatSpinEdit;
    SpinBlendWeight: TFloatSpinEdit;

    SpinExposure: TFloatSpinEdit;
    SpinAces: TFloatSpinEdit;
    SpinContrast: TFloatSpinEdit;
    SpinSaturation: TFloatSpinEdit;
    SpinVignette: TFloatSpinEdit;
    SpinChromatic: TFloatSpinEdit;
    SpinTintR: TFloatSpinEdit;
    SpinTintG: TFloatSpinEdit;
    SpinTintB: TFloatSpinEdit;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function CurrentObserverPos: TVector3;
    function ActiveVolume: TCastlePostProcessVolume;
    procedure RefreshAll;
    procedure LoadVolumeToControls;
    procedure PushControlsToVolume;
    procedure ApplyStackLive;
    procedure NotifyModified(const Comment: String);

    procedure ButtonAddGlobalClick(Sender: TObject);
    procedure ButtonAddLocalClick(Sender: TObject);
    procedure ButtonApplyLiveViewportClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure PresetButtonClick(Sender: TObject);
    procedure ComboVolumeChange(Sender: TObject);
    procedure AnyVolumeFieldChange(Sender: TObject);
    procedure PaintBoxPreviewPaint(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TPostProcessStudioModifiedCallback;
      const AOnRefreshViewport: TPostProcessStudioRefreshViewportCallback);
  end;

implementation

constructor TPostProcessStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TPostProcessStudioModifiedCallback;
  const AOnRefreshViewport: TPostProcessStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  BuildUi;
  RefreshAll;
end;

procedure TPostProcessStudioForm.BuildUi;
var
  PanelTop, PanelPresets, PanelBottom, PanelRight, PanelCenter: TPanel;
  Lbl: TLabel;
  Pr: TCastlePostProcessPreset;
  Y: Integer;

  function AddFloatRow(const AParent: TWinControl; const ACaption: String;
    var ATop: Integer; const AMin, AMax, AInc: Double): TFloatSpinEdit;
  var
    L: TLabel;
  begin
    L := TLabel.Create(Self);
    L.Parent := AParent;
    L.SetBounds(10, ATop + 4, 152, 18);
    L.Caption := ACaption;

    Result := TFloatSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(168, ATop, 156, 24);
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Increment := AInc;
    Result.DecimalPlaces := 2;
    Result.OnChange := @AnyVolumeFieldChange;
    Inc(ATop, 28);
  end;

begin
  Caption := 'Priority-Blended Post-Processing Volumes & Cinematic Look-Dev Studio (UE 5.9 / 6.0 Parity)';
  Width := 1040;
  Height := 670;
  Position := poMainFormCenter;
  Constraints.MinWidth := 880;
  Constraints.MinHeight := 560;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonAddGlobal := TButton.Create(Self);
  ButtonAddGlobal.Parent := PanelTop;
  ButtonAddGlobal.SetBounds(10, 7, 195, 30);
  ButtonAddGlobal.Caption := '+ Add Global Unbound Volume';
  ButtonAddGlobal.OnClick := @ButtonAddGlobalClick;

  ButtonAddLocal := TButton.Create(Self);
  ButtonAddLocal.Parent := PanelTop;
  ButtonAddLocal.SetBounds(212, 7, 210, 30);
  ButtonAddLocal.Caption := '+ Add Bounded Volume @ Camera';
  ButtonAddLocal.OnClick := @ButtonAddLocalClick;

  ButtonApplyLiveViewport := TButton.Create(Self);
  ButtonApplyLiveViewport.Parent := PanelTop;
  ButtonApplyLiveViewport.SetBounds(430, 7, 195, 30);
  ButtonApplyLiveViewport.Caption := 'Apply ScreenEffect to Viewport';
  ButtonApplyLiveViewport.OnClick := @ButtonApplyLiveViewportClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(633, 7, 180, 30);
  ButtonCopyMarkdown.Caption := 'Copy Markdown + GLSL';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelPresets := TPanel.Create(Self);
  PanelPresets.Parent := Self;
  PanelPresets.Align := alTop;
  PanelPresets.Height := 40;
  PanelPresets.BevelOuter := bvLowered;

  for Pr := Low(TCastlePostProcessPreset) to High(TCastlePostProcessPreset) do
  begin
    PresetButtons[Pr] := TButton.Create(Self);
    PresetButtons[Pr].Parent := PanelPresets;
    PresetButtons[Pr].SetBounds(10 + Ord(Pr) * 164, 6, 156, 28);
    PresetButtons[Pr].Caption := PostProcessPresetToDisplayName(Pr);
    PresetButtons[Pr].Tag := Ord(Pr);
    PresetButtons[Pr].OnClick := @PresetButtonClick;
  end;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 38;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 10, 820, 18);
  LabelStatus.Caption := 'Ready.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.BorderSpacing.Around := 5;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alRight;
  PanelRight.Width := 342;
  PanelRight.BorderSpacing.Around := 6;
  PanelRight.BevelOuter := bvLowered;

  ComboVolume := TComboBox.Create(Self);
  ComboVolume.Parent := PanelRight;
  ComboVolume.SetBounds(10, 10, 314, 26);
  ComboVolume.Style := csDropDownList;
  ComboVolume.OnChange := @ComboVolumeChange;

  CheckUnbound := TCheckBox.Create(Self);
  CheckUnbound.Parent := PanelRight;
  CheckUnbound.SetBounds(10, 42, 165, 22);
  CheckUnbound.Caption := 'Global Unbound';
  CheckUnbound.OnChange := @AnyVolumeFieldChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.SetBounds(182, 44, 55, 18);
  Lbl.Caption := 'Priority:';

  SpinPriority := TSpinEdit.Create(Self);
  SpinPriority.Parent := PanelRight;
  SpinPriority.SetBounds(240, 40, 84, 24);
  SpinPriority.MinValue := -1000;
  SpinPriority.MaxValue := 1000;
  SpinPriority.OnChange := @AnyVolumeFieldChange;

  Y := 72;
  SpinCoreRadius := AddFloatRow(PanelRight, 'Core Radius (m):', Y, 0.0, 5000.0, 1.0);
  SpinBlendRadius := AddFloatRow(PanelRight, 'Blend Radius (m):', Y, 0.0, 5000.0, 1.0);
  SpinBlendWeight := AddFloatRow(PanelRight, 'Blend Weight (0..1):', Y, 0.0, 1.0, 0.05);
  Inc(Y, 6);
  SpinExposure := AddFloatRow(PanelRight, 'Exposure (EV):', Y, -4.0, 4.0, 0.1);
  SpinAces := AddFloatRow(PanelRight, 'ACES Tonemap Mix:', Y, 0.0, 1.0, 0.05);
  SpinContrast := AddFloatRow(PanelRight, 'Contrast:', Y, 0.2, 3.0, 0.05);
  SpinSaturation := AddFloatRow(PanelRight, 'Saturation:', Y, 0.0, 3.0, 0.05);
  SpinVignette := AddFloatRow(PanelRight, 'Vignette Intensity:', Y, 0.0, 1.5, 0.05);
  SpinChromatic := AddFloatRow(PanelRight, 'Chromatic Aberr (px):', Y, 0.0, 16.0, 0.2);
  SpinTintR := AddFloatRow(PanelRight, 'Color Tint Red:', Y, 0.0, 2.0, 0.05);
  SpinTintG := AddFloatRow(PanelRight, 'Color Tint Green:', Y, 0.0, 2.0, 0.05);
  SpinTintB := AddFloatRow(PanelRight, 'Color Tint Blue:', Y, 0.0, 2.0, 0.05);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := Self;
  PanelCenter.Align := alClient;
  PanelCenter.BorderSpacing.Around := 6;
  PanelCenter.BevelOuter := bvLowered;

  PaintBoxPreview := TPaintBox.Create(Self);
  PaintBoxPreview.Parent := PanelCenter;
  PaintBoxPreview.Align := alClient;
  PaintBoxPreview.OnPaint := @PaintBoxPreviewPaint;
end;

function TPostProcessStudioForm.CurrentObserverPos: TVector3;
var
  VP: TCastleViewport;
  CamP, CamD, CamU: TVector3;
begin
  Result := TVector3.Zero;
  VP := TPostProcessStudioHelper.FindFirstViewport(FRootComponent);
  if (VP <> nil) and (VP.Camera <> nil) then
  begin
    VP.Camera.GetWorldView(CamP, CamD, CamU);
    Result := CamP;
  end;
end;

function TPostProcessStudioForm.ActiveVolume: TCastlePostProcessVolume;
var
  Idx: Integer;
begin
  Idx := ComboVolume.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FSummary.Volumes)) then
    Result := FSummary.Volumes[Idx]
  else
    Result := nil;
end;

procedure TPostProcessStudioForm.RefreshAll;
var
  I, PrevIdx: Integer;
begin
  PrevIdx := ComboVolume.ItemIndex;
  FSummary := TPostProcessStudioHelper.ScanVolumesAndBlend(
    FRootComponent, CurrentObserverPos);

  ComboVolume.Items.BeginUpdate;
  try
    ComboVolume.Items.Clear;
    for I := 0 to High(FSummary.Volumes) do
      ComboVolume.Items.Add(Format('%s %s',
        [FSummary.Volumes[I].Name, FSummary.Volumes[I].VolumeSummaryBadge]));
    if ComboVolume.Items.Count > 0 then
    begin
      if (FInitialSelected is TCastlePostProcessVolume) and (PrevIdx < 0) then
        for I := 0 to High(FSummary.Volumes) do
          if FSummary.Volumes[I] = FInitialSelected then
            PrevIdx := I;
      ComboVolume.ItemIndex := Clamped(Max(0, PrevIdx), 0, ComboVolume.Items.Count - 1);
    end;
  finally
    ComboVolume.Items.EndUpdate;
  end;

  LoadVolumeToControls;
  LabelStatus.Caption := Format(
    'Volumes: %d (Active @ Camera: %d) | Blended EV: %+.2f | ACES: %.0f%% | Contrast: %.2f | Sat: %.2f',
    [Length(FSummary.Volumes), FSummary.ActiveVolumeCount,
     FSummary.Blended.ExposureEV, FSummary.Blended.AcesTonemapMix * 100.0,
     FSummary.Blended.Contrast, FSummary.Blended.Saturation]);
  PaintBoxPreview.Invalidate;
end;

procedure TPostProcessStudioForm.LoadVolumeToControls;
var
  V: TCastlePostProcessVolume;
  HasV: Boolean;
begin
  FUpdatingUi := true;
  try
    V := ActiveVolume;
    HasV := V <> nil;
    CheckUnbound.Enabled := HasV;
    SpinPriority.Enabled := HasV;
    SpinCoreRadius.Enabled := HasV;
    SpinBlendRadius.Enabled := HasV;
    SpinBlendWeight.Enabled := HasV;
    SpinExposure.Enabled := HasV;
    SpinAces.Enabled := HasV;
    SpinContrast.Enabled := HasV;
    SpinSaturation.Enabled := HasV;
    SpinVignette.Enabled := HasV;
    SpinChromatic.Enabled := HasV;
    SpinTintR.Enabled := HasV;
    SpinTintG.Enabled := HasV;
    SpinTintB.Enabled := HasV;

    if HasV then
    begin
      CheckUnbound.Checked := V.IsUnbound;
      SpinPriority.Value := V.Priority;
      SpinCoreRadius.Value := V.CoreRadius;
      SpinBlendRadius.Value := V.BlendRadius;
      SpinBlendWeight.Value := V.BlendWeight;
      SpinExposure.Value := V.ExposureEV;
      SpinAces.Value := V.AcesTonemapMix;
      SpinContrast.Value := V.Contrast;
      SpinSaturation.Value := V.Saturation;
      SpinVignette.Value := V.VignetteIntensity;
      SpinChromatic.Value := V.ChromaticAberrationPx;
      SpinTintR.Value := V.TintRed;
      SpinTintG.Value := V.TintGreen;
      SpinTintB.Value := V.TintBlue;
    end;
  finally
    FUpdatingUi := false;
  end;
end;

procedure TPostProcessStudioForm.PushControlsToVolume;
var
  V: TCastlePostProcessVolume;
begin
  V := ActiveVolume;
  if V = nil then
    Exit;
  V.IsUnbound := CheckUnbound.Checked;
  V.Priority := SpinPriority.Value;
  V.CoreRadius := SpinCoreRadius.Value;
  V.BlendRadius := SpinBlendRadius.Value;
  V.BlendWeight := SpinBlendWeight.Value;
  V.ExposureEV := SpinExposure.Value;
  V.AcesTonemapMix := SpinAces.Value;
  V.Contrast := SpinContrast.Value;
  V.Saturation := SpinSaturation.Value;
  V.VignetteIntensity := SpinVignette.Value;
  V.ChromaticAberrationPx := SpinChromatic.Value;
  V.TintRed := SpinTintR.Value;
  V.TintGreen := SpinTintG.Value;
  V.TintBlue := SpinTintB.Value;
end;

procedure TPostProcessStudioForm.ApplyStackLive;
var
  Stack: TCastlePostProcessStack;
  VP: TCastleViewport;
begin
  Stack := TPostProcessStudioHelper.EnsureStackInDesign(FRootComponent, FDesignOwner);
  VP := TPostProcessStudioHelper.FindFirstViewport(FRootComponent);
  if (Stack <> nil) and (VP <> nil) then
    Stack.ApplyToViewport(FRootComponent, VP, CurrentObserverPos);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TPostProcessStudioForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TPostProcessStudioForm.ButtonAddGlobalClick(Sender: TObject);
begin
  TPostProcessStudioHelper.EnsureStackInDesign(FRootComponent, FDesignOwner);
  if TPostProcessStudioHelper.CreateVolumeInDesign(
       FRootComponent, FDesignOwner, pppWarmSunset, true, TVector3.Zero) <> nil then
  begin
    RefreshAll;
    ComboVolume.ItemIndex := ComboVolume.Items.Count - 1;
    LoadVolumeToControls;
    ApplyStackLive;
    NotifyModified('Add Global Post-Process Volume');
  end;
end;

procedure TPostProcessStudioForm.ButtonAddLocalClick(Sender: TObject);
begin
  TPostProcessStudioHelper.EnsureStackInDesign(FRootComponent, FDesignOwner);
  if TPostProcessStudioHelper.CreateVolumeInDesign(
       FRootComponent, FDesignOwner, pppHorrorVignette, false, CurrentObserverPos) <> nil then
  begin
    RefreshAll;
    ComboVolume.ItemIndex := ComboVolume.Items.Count - 1;
    LoadVolumeToControls;
    ApplyStackLive;
    NotifyModified('Add Bounded Post-Process Volume');
  end;
end;

procedure TPostProcessStudioForm.ButtonApplyLiveViewportClick(Sender: TObject);
begin
  ApplyStackLive;
  RefreshAll;
  NotifyModified('Apply Post-Process Stack to Viewport');
end;

procedure TPostProcessStudioForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TPostProcessStudioHelper.FormatPostProcessMarkdown(
    FRootComponent, CurrentObserverPos);
  LabelStatus.Caption := 'Copied Post-Processing Stack Markdown + GLSL shader to clipboard.';
end;

procedure TPostProcessStudioForm.PresetButtonClick(Sender: TObject);
var
  V: TCastlePostProcessVolume;
  Pr: TCastlePostProcessPreset;
begin
  if not (Sender is TButton) then
    Exit;
  Pr := TCastlePostProcessPreset(TButton(Sender).Tag);
  V := ActiveVolume;
  if V = nil then
  begin
    TPostProcessStudioHelper.EnsureStackInDesign(FRootComponent, FDesignOwner);
    V := TPostProcessStudioHelper.CreateVolumeInDesign(
      FRootComponent, FDesignOwner, Pr, true, TVector3.Zero);
  end else
    V.ApplyLookPreset(Pr);

  if V <> nil then
  begin
    RefreshAll;
    ApplyStackLive;
    NotifyModified('Apply Post-Process Look Preset');
  end;
end;

procedure TPostProcessStudioForm.ComboVolumeChange(Sender: TObject);
begin
  LoadVolumeToControls;
end;

procedure TPostProcessStudioForm.AnyVolumeFieldChange(Sender: TObject);
begin
  if FUpdatingUi then
    Exit;
  PushControlsToVolume;
  FSummary.Blended := TCastlePostProcessStack.EvaluateBlendedWorldSettings(
    FRootComponent, CurrentObserverPos, FSummary.ActiveVolumeCount);
  ApplyStackLive;
  PaintBoxPreview.Invalidate;
  NotifyModified('Adjust Post-Process Volume Parameters');
end;

procedure TPostProcessStudioForm.PaintBoxPreviewPaint(Sender: TObject);
const
  Cols = 48;
  Rows = 32;
var
  C: TCanvas;
  R, CellR: TRect;
  GX, GY, SplitX: Integer;
  U, V: Single;
  BaseCol, OutCol: TVector3;
begin
  C := PaintBoxPreview.Canvas;
  R := PaintBoxPreview.ClientRect;
  if (R.Right <= 4) or (R.Bottom <= 4) then
    Exit;

  SplitX := R.Right div 2;
  for GY := 0 to Rows - 1 do
    for GX := 0 to Cols - 1 do
    begin
      U := (GX + 0.5) / Cols;
      V := 1.0 - ((GY + 0.5) / Rows);
      { Procedural HDR sky/sun/landscape color chart }
      if V > 0.42 then
        BaseCol := Vector3(
          Lerp((V - 0.42) / 0.58, 0.88, 0.22),
          Lerp((V - 0.42) / 0.58, 0.62, 0.44),
          Lerp((V - 0.42) / 0.58, 0.44, 0.86))
      else
        BaseCol := Vector3(
          Lerp(V / 0.42, 0.14, 0.36),
          Lerp(V / 0.42, 0.28, 0.52),
          Lerp(V / 0.42, 0.12, 0.24));
      { Bright sun disc highlight }
      if Sqr(U - 0.68) + Sqr(V - 0.64) < 0.018 then
        BaseCol := Vector3(1.45, 1.28, 0.92);

      CellR := Rect(
        (GX * R.Right) div Cols,
        (GY * R.Bottom) div Rows,
        ((GX + 1) * R.Right) div Cols + 1,
        ((GY + 1) * R.Bottom) div Rows + 1);

      if CellR.Left < SplitX then
        OutCol := Vector3(Clamped(BaseCol.X, 0.0, 1.0),
          Clamped(BaseCol.Y, 0.0, 1.0), Clamped(BaseCol.Z, 0.0, 1.0))
      else
        OutCol := TPostProcessStudioHelper.EvaluateColorGradeCpuPreview(
          FSummary.Blended, BaseCol, Vector2(U, V));

      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(
        Round(OutCol.X * 255.0),
        Round(OutCol.Y * 255.0),
        Round(OutCol.Z * 255.0));
      C.FillRect(CellR);
    end;

  C.Pen.Color := RGBToColor(255, 255, 255);
  C.Pen.Width := 2;
  C.Line(SplitX, 0, SplitX, R.Bottom);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(18, 22, 30);
  C.Font.Color := RGBToColor(235, 240, 250);
  C.Font.Style := [Graphics.fsBold];
  C.TextOut(12, 10, ' BEFORE (Unprocessed Linear/sRGB) ');
  C.TextOut(SplitX + 12, 10, ' AFTER (Blended Post-Process Stack @ Camera) ');
end;

procedure TPostProcessStudioForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.

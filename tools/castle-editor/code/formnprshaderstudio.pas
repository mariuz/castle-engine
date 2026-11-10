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

{ Stylized / NPR Shader Effect Studio & Light/Shadow Budget Complexity
  Audit dialog (Phase 282 — UE 5.8 Substrate NPR & MegaLights Parity). }
unit FormNprShaderStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics, Clipbrd,
  CastleVectors, CastleColors, CastleTransform, CastleScene, CastleNprShader,
  ToolNprShaderStudio;

type
  TNprStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TNprStudioSelectComponentCallback = procedure (const C: TComponent) of object;
  TNprStudioToggleOverlayCallback = procedure (const AEnabled: Boolean) of object;

  TNprShaderStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSelectedTransforms: TList;
    FPreviewBehavior: TCastleStylizedShaderBehavior;
    FCurrentReport: TLightShadowBudgetReport;
    FUpdatingUi: Boolean;

    FOnModified: TNprStudioModifiedCallback;
    FOnSelectComponent: TNprStudioSelectComponentCallback;
    FOnToggleOverlay: TNprStudioToggleOverlayCallback;

    PageMain: TPageControl;
    TabShader: TTabSheet;
    TabLightAudit: TTabSheet;

    { Tab 1: Stylized / NPR Shader Studio }
    PanelShaderTop: TPanel;
    ComboPreset: TComboBox;
    SpinCelBands: TSpinEdit;
    SpinShadowFloor: TFloatSpinEdit;
    SpinRimPower: TFloatSpinEdit;
    SpinIntensity: TFloatSpinEdit;
    SpinDissolveProgress: TFloatSpinEdit;
    SpinDissolveScale: TFloatSpinEdit;
    SpinEdgeWidth: TFloatSpinEdit;
    SpinOutlineThickness: TFloatSpinEdit;
    BtnPickAccentColor: TButton;
    BtnPickSecondaryColor: TButton;
    ColorDlg: TColorDialog;
    GroupGlslPreview: TGroupBox;
    MemoGlslPreview: TMemo;
    PanelShaderButtons: TPanel;
    BtnApplyToSelected: TButton;
    BtnRemoveFromSelected: TButton;
    BtnExportGlsl: TButton;
    BtnCopyGlsl: TButton;

    { Tab 2: Light & Shadow Budget Audit }
    PanelAuditTop: TPanel;
    CheckViewportOverlay: TCheckBox;
    BtnRefreshAudit: TButton;
    BtnFixMultiShadow: TButton;
    SpinClampRadius: TFloatSpinEdit;
    BtnClampRadii: TButton;
    GroupHotspots: TGroupBox;
    ListHotspots: TListBox;
    SplitterAudit: TSplitter;
    MemoAuditReport: TMemo;

    PanelBottom: TPanel;
    BtnClose: TButton;

    procedure LoadInitialBehaviorFromSelection;
    procedure SyncPreviewBehaviorFromControls;
    procedure RefreshGlslPreview;
    procedure RefreshLightAudit;
    procedure UpdateColorButtonCaptions;

    procedure AnyShaderParamChange(Sender: TObject);
    procedure BtnPickAccentColorClick(Sender: TObject);
    procedure BtnPickSecondaryColorClick(Sender: TObject);
    procedure BtnApplyToSelectedClick(Sender: TObject);
    procedure BtnRemoveFromSelectedClick(Sender: TObject);
    procedure BtnExportGlslClick(Sender: TObject);
    procedure BtnCopyGlslClick(Sender: TObject);

    procedure CheckViewportOverlayChange(Sender: TObject);
    procedure BtnRefreshAuditClick(Sender: TObject);
    procedure BtnFixMultiShadowClick(Sender: TObject);
    procedure BtnClampRadiiClick(Sender: TObject);
    procedure ListHotspotsDblClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const ASelectedComponents: TComponentList;
      const InitialOverlayActive: Boolean;
      const OpenLightAuditTab: Boolean;
      const AOnModified: TNprStudioModifiedCallback;
      const AOnSelectComponent: TNprStudioSelectComponentCallback;
      const AOnToggleOverlay: TNprStudioToggleOverlayCallback);
    destructor Destroy; override;
  end;

implementation

uses
  Math, CastleUtils, CastleUriUtils, CastleFilesUtils, EditorUtils;

function CastleRgbToTColor(const C: TCastleColorRGB): TColor;
begin
  Result := RGBToColor(
    Round(Clamped(C.X, 0.0, 1.0) * 255.0),
    Round(Clamped(C.Y, 0.0, 1.0) * 255.0),
    Round(Clamped(C.Z, 0.0, 1.0) * 255.0));
end;

function TColorToCastleRgb(const C: TColor): TCastleColorRGB;
var
  R, G, B: Byte;
begin
  RedGreenBlue(ColorToRGB(C), R, G, B);
  Result := Vector3(R / 255.0, G / 255.0, B / 255.0);
end;

{ TNprShaderStudioForm ------------------------------------------------------- }

constructor TNprShaderStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const ASelectedComponents: TComponentList;
  const InitialOverlayActive: Boolean;
  const OpenLightAuditTab: Boolean;
  const AOnModified: TNprStudioModifiedCallback;
  const AOnSelectComponent: TNprStudioSelectComponentCallback;
  const AOnToggleOverlay: TNprStudioToggleOverlayCallback);

  procedure AddLabeledControl(const AParent: TWinControl; const ACaption: String;
    const AControl: TControl);
  var
    Cell: TPanel;
    Lbl: TLabel;
  begin
    Cell := TPanel.Create(Self);
    Cell.AutoSize := true;
    Cell.BevelOuter := bvNone;
    Cell.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
    Cell.ChildSizing.ControlsPerLine := 2;
    Cell.ChildSizing.HorizontalSpacing := 4;
    Cell.Parent := AParent;

    Lbl := TLabel.Create(Self);
    Lbl.Caption := ACaption;
    Lbl.Layout := tlCenter;
    Lbl.Parent := Cell;

    AControl.Parent := Cell;
  end;

var
  P: TCastleStylizedShaderPreset;
  I: Integer;
  LblRadius: TLabel;
begin
  inherited CreateNew(AOwner);

  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnSelectComponent := AOnSelectComponent;
  FOnToggleOverlay := AOnToggleOverlay;

  FSelectedTransforms := TList.Create;
  if ASelectedComponents <> nil then
    for I := 0 to ASelectedComponents.Count - 1 do
      if ASelectedComponents[I] is TCastleTransform then
        FSelectedTransforms.Add(ASelectedComponents[I]);

  FPreviewBehavior := TCastleStylizedShaderBehavior.Create(Self);
  ColorDlg := TColorDialog.Create(Self);

  Caption := 'Stylized / NPR Shader Effect Studio & Light/Shadow Budget Audit';
  Width := 920;
  Height := 660;
  Position := poMainFormCenter;
  Constraints.MinWidth := 720;
  Constraints.MinHeight := 500;

  PageMain := TPageControl.Create(Self);
  PageMain.Align := alClient;
  PageMain.BorderSpacing.Around := 8;
  PageMain.Parent := Self;

  TabShader := TTabSheet.Create(PageMain);
  TabShader.Caption := 'Stylized / NPR Shader Studio';
  TabShader.PageControl := PageMain;

  TabLightAudit := TTabSheet.Create(PageMain);
  TabLightAudit.Caption := 'Light & Shadow Budget Audit (MegaLights View)';
  TabLightAudit.PageControl := PageMain;

  { --- Tab 1: Stylized / NPR Shader Studio --- }
  PanelShaderTop := TPanel.Create(Self);
  PanelShaderTop.Align := alTop;
  PanelShaderTop.AutoSize := true;
  PanelShaderTop.BevelOuter := bvNone;
  PanelShaderTop.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  PanelShaderTop.ChildSizing.ControlsPerLine := 4;
  PanelShaderTop.ChildSizing.HorizontalSpacing := 12;
  PanelShaderTop.ChildSizing.VerticalSpacing := 6;
  PanelShaderTop.ChildSizing.LeftRightSpacing := 8;
  PanelShaderTop.ChildSizing.TopBottomSpacing := 8;
  PanelShaderTop.Parent := TabShader;

  ComboPreset := TComboBox.Create(Self);
  ComboPreset.Style := csDropDownList;
  ComboPreset.Width := 250;
  for P := Low(TCastleStylizedShaderPreset) to High(TCastleStylizedShaderPreset) do
    ComboPreset.Items.Add(TLightShadowBudgetAuditor.PresetDisplayName(P));
  ComboPreset.ItemIndex := 0;
  ComboPreset.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Preset:', ComboPreset);

  SpinCelBands := TSpinEdit.Create(Self);
  SpinCelBands.MinValue := 2;
  SpinCelBands.MaxValue := 16;
  SpinCelBands.Value := FPreviewBehavior.CelBands;
  SpinCelBands.Width := 64;
  SpinCelBands.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Cel Bands:', SpinCelBands);

  SpinShadowFloor := TFloatSpinEdit.Create(Self);
  SpinShadowFloor.DecimalPlaces := 2;
  SpinShadowFloor.MinValue := 0.0;
  SpinShadowFloor.MaxValue := 1.0;
  SpinShadowFloor.Increment := 0.05;
  SpinShadowFloor.Value := FPreviewBehavior.ShadowFloor;
  SpinShadowFloor.Width := 68;
  SpinShadowFloor.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Shadow Floor:', SpinShadowFloor);

  SpinIntensity := TFloatSpinEdit.Create(Self);
  SpinIntensity.DecimalPlaces := 2;
  SpinIntensity.MinValue := 0.0;
  SpinIntensity.MaxValue := 10.0;
  SpinIntensity.Increment := 0.10;
  SpinIntensity.Value := FPreviewBehavior.Intensity;
  SpinIntensity.Width := 68;
  SpinIntensity.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Intensity / Blend:', SpinIntensity);

  SpinRimPower := TFloatSpinEdit.Create(Self);
  SpinRimPower.DecimalPlaces := 1;
  SpinRimPower.MinValue := 0.2;
  SpinRimPower.MaxValue := 16.0;
  SpinRimPower.Increment := 0.5;
  SpinRimPower.Value := FPreviewBehavior.RimPower;
  SpinRimPower.Width := 68;
  SpinRimPower.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Rim Power:', SpinRimPower);

  SpinDissolveProgress := TFloatSpinEdit.Create(Self);
  SpinDissolveProgress.DecimalPlaces := 2;
  SpinDissolveProgress.MinValue := 0.0;
  SpinDissolveProgress.MaxValue := 1.0;
  SpinDissolveProgress.Increment := 0.05;
  SpinDissolveProgress.Value := FPreviewBehavior.DissolveProgress;
  SpinDissolveProgress.Width := 68;
  SpinDissolveProgress.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Dissolve (0..1):', SpinDissolveProgress);

  SpinDissolveScale := TFloatSpinEdit.Create(Self);
  SpinDissolveScale.DecimalPlaces := 1;
  SpinDissolveScale.MinValue := 0.2;
  SpinDissolveScale.MaxValue := 200.0;
  SpinDissolveScale.Increment := 1.0;
  SpinDissolveScale.Value := FPreviewBehavior.DissolveScale;
  SpinDissolveScale.Width := 68;
  SpinDissolveScale.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Noise Scale:', SpinDissolveScale);

  SpinEdgeWidth := TFloatSpinEdit.Create(Self);
  SpinEdgeWidth.DecimalPlaces := 2;
  SpinEdgeWidth.MinValue := 0.01;
  SpinEdgeWidth.MaxValue := 0.50;
  SpinEdgeWidth.Increment := 0.02;
  SpinEdgeWidth.Value := FPreviewBehavior.EdgeWidth;
  SpinEdgeWidth.Width := 68;
  SpinEdgeWidth.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Edge Width:', SpinEdgeWidth);

  SpinOutlineThickness := TFloatSpinEdit.Create(Self);
  SpinOutlineThickness.DecimalPlaces := 2;
  SpinOutlineThickness.MinValue := 0.02;
  SpinOutlineThickness.MaxValue := 0.95;
  SpinOutlineThickness.Increment := 0.04;
  SpinOutlineThickness.Value := FPreviewBehavior.OutlineThickness;
  SpinOutlineThickness.Width := 68;
  SpinOutlineThickness.OnChange := @AnyShaderParamChange;
  AddLabeledControl(PanelShaderTop, 'Outline Width:', SpinOutlineThickness);

  BtnPickAccentColor := TButton.Create(Self);
  BtnPickAccentColor.AutoSize := true;
  BtnPickAccentColor.OnClick := @BtnPickAccentColorClick;
  BtnPickAccentColor.Parent := PanelShaderTop;

  BtnPickSecondaryColor := TButton.Create(Self);
  BtnPickSecondaryColor.AutoSize := true;
  BtnPickSecondaryColor.OnClick := @BtnPickSecondaryColorClick;
  BtnPickSecondaryColor.Parent := PanelShaderTop;

  PanelShaderButtons := TPanel.Create(Self);
  PanelShaderButtons.Align := alBottom;
  PanelShaderButtons.AutoSize := true;
  PanelShaderButtons.BevelOuter := bvNone;
  PanelShaderButtons.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  PanelShaderButtons.ChildSizing.ControlsPerLine := 6;
  PanelShaderButtons.ChildSizing.HorizontalSpacing := 8;
  PanelShaderButtons.ChildSizing.LeftRightSpacing := 8;
  PanelShaderButtons.ChildSizing.TopBottomSpacing := 8;
  PanelShaderButtons.Parent := TabShader;

  BtnApplyToSelected := TButton.Create(Self);
  BtnApplyToSelected.AutoSize := true;
  BtnApplyToSelected.Caption := Format('Apply NPR Shader to Selected (%d)', [FSelectedTransforms.Count]);
  BtnApplyToSelected.Enabled := FSelectedTransforms.Count > 0;
  BtnApplyToSelected.OnClick := @BtnApplyToSelectedClick;
  BtnApplyToSelected.Parent := PanelShaderButtons;

  BtnRemoveFromSelected := TButton.Create(Self);
  BtnRemoveFromSelected.AutoSize := true;
  BtnRemoveFromSelected.Caption := 'Remove NPR Shader from Selected';
  BtnRemoveFromSelected.Enabled := FSelectedTransforms.Count > 0;
  BtnRemoveFromSelected.OnClick := @BtnRemoveFromSelectedClick;
  BtnRemoveFromSelected.Parent := PanelShaderButtons;

  BtnExportGlsl := TButton.Create(Self);
  BtnExportGlsl.AutoSize := true;
  BtnExportGlsl.Caption := 'Export .fs GLSL to castle-data:/shaders/';
  BtnExportGlsl.OnClick := @BtnExportGlslClick;
  BtnExportGlsl.Parent := PanelShaderButtons;

  BtnCopyGlsl := TButton.Create(Self);
  BtnCopyGlsl.AutoSize := true;
  BtnCopyGlsl.Caption := 'Copy GLSL to Clipboard';
  BtnCopyGlsl.OnClick := @BtnCopyGlslClick;
  BtnCopyGlsl.Parent := PanelShaderButtons;

  GroupGlslPreview := TGroupBox.Create(Self);
  GroupGlslPreview.Align := alClient;
  GroupGlslPreview.BorderSpacing.Around := 8;
  GroupGlslPreview.Caption := 'Generated CGE X3D TEffectNode / PLUG_lighting_apply Fragment Shader (Live Preview)';
  GroupGlslPreview.Parent := TabShader;

  MemoGlslPreview := TMemo.Create(Self);
  MemoGlslPreview.Align := alClient;
  MemoGlslPreview.BorderSpacing.Around := 6;
  MemoGlslPreview.ReadOnly := true;
  MemoGlslPreview.ScrollBars := ssAutoBoth;
  MemoGlslPreview.Font.Name := 'Monospace';
  MemoGlslPreview.Parent := GroupGlslPreview;

  { --- Tab 2: Light & Shadow Budget Audit --- }
  PanelAuditTop := TPanel.Create(Self);
  PanelAuditTop.Align := alTop;
  PanelAuditTop.AutoSize := true;
  PanelAuditTop.BevelOuter := bvNone;
  PanelAuditTop.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  PanelAuditTop.ChildSizing.ControlsPerLine := 8;
  PanelAuditTop.ChildSizing.HorizontalSpacing := 8;
  PanelAuditTop.ChildSizing.VerticalSpacing := 6;
  PanelAuditTop.ChildSizing.LeftRightSpacing := 8;
  PanelAuditTop.ChildSizing.TopBottomSpacing := 8;
  PanelAuditTop.Parent := TabLightAudit;

  CheckViewportOverlay := TCheckBox.Create(Self);
  CheckViewportOverlay.Caption := 'Show Live 3D Viewport Light Spheres & Overlap Heat Badges';
  CheckViewportOverlay.Checked := InitialOverlayActive;
  CheckViewportOverlay.OnChange := @CheckViewportOverlayChange;
  CheckViewportOverlay.Parent := PanelAuditTop;

  BtnRefreshAudit := TButton.Create(Self);
  BtnRefreshAudit.AutoSize := true;
  BtnRefreshAudit.Caption := 'Refresh Audit';
  BtnRefreshAudit.OnClick := @BtnRefreshAuditClick;
  BtnRefreshAudit.Parent := PanelAuditTop;

  BtnFixMultiShadow := TButton.Create(Self);
  BtnFixMultiShadow.AutoSize := true;
  BtnFixMultiShadow.Caption := 'Resolve Multi-Shadow Conflict';
  BtnFixMultiShadow.Hint := 'Keep Shadows = true only on the primary light so CGE shadow volumes render cleanly';
  BtnFixMultiShadow.ShowHint := true;
  BtnFixMultiShadow.OnClick := @BtnFixMultiShadowClick;
  BtnFixMultiShadow.Parent := PanelAuditTop;

  LblRadius := TLabel.Create(Self);
  LblRadius.Caption := 'Max Punctual Radius:';
  LblRadius.Layout := tlCenter;
  LblRadius.Parent := PanelAuditTop;

  SpinClampRadius := TFloatSpinEdit.Create(Self);
  SpinClampRadius.DecimalPlaces := 1;
  SpinClampRadius.MinValue := 2.0;
  SpinClampRadius.MaxValue := 500.0;
  SpinClampRadius.Increment := 5.0;
  SpinClampRadius.Value := 35.0;
  SpinClampRadius.Width := 68;
  SpinClampRadius.Parent := PanelAuditTop;

  BtnClampRadii := TButton.Create(Self);
  BtnClampRadii.AutoSize := true;
  BtnClampRadii.Caption := 'Clamp Unbounded Radii';
  BtnClampRadii.OnClick := @BtnClampRadiiClick;
  BtnClampRadii.Parent := PanelAuditTop;

  GroupHotspots := TGroupBox.Create(Self);
  GroupHotspots.Align := alTop;
  GroupHotspots.Height := 220;
  GroupHotspots.BorderSpacing.Around := 8;
  GroupHotspots.Caption := 'Lit Receiver Overlap Hotspots (Double-Click Row to Select in Hierarchy)';
  GroupHotspots.Parent := TabLightAudit;

  ListHotspots := TListBox.Create(Self);
  ListHotspots.Align := alClient;
  ListHotspots.BorderSpacing.Around := 6;
  ListHotspots.OnDblClick := @ListHotspotsDblClick;
  ListHotspots.Parent := GroupHotspots;

  SplitterAudit := TSplitter.Create(Self);
  SplitterAudit.Align := alTop;
  SplitterAudit.Top := GroupHotspots.Top + GroupHotspots.Height + 1;
  SplitterAudit.Parent := TabLightAudit;

  MemoAuditReport := TMemo.Create(Self);
  MemoAuditReport.Align := alClient;
  MemoAuditReport.BorderSpacing.Around := 8;
  MemoAuditReport.ReadOnly := true;
  MemoAuditReport.ScrollBars := ssAutoBoth;
  MemoAuditReport.Font.Name := 'Monospace';
  MemoAuditReport.Parent := TabLightAudit;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Align := alBottom;
  PanelBottom.AutoSize := true;
  PanelBottom.BevelOuter := bvNone;
  PanelBottom.ChildSizing.LeftRightSpacing := 8;
  PanelBottom.ChildSizing.TopBottomSpacing := 6;
  PanelBottom.Parent := Self;

  BtnClose := TButton.Create(Self);
  BtnClose.AutoSize := true;
  BtnClose.Align := alRight;
  BtnClose.Caption := 'Close';
  BtnClose.Cancel := true;
  BtnClose.OnClick := @BtnCloseClick;
  BtnClose.Parent := PanelBottom;

  LoadInitialBehaviorFromSelection;
  UpdateColorButtonCaptions;
  RefreshGlslPreview;
  RefreshLightAudit;

  if OpenLightAuditTab then
    PageMain.ActivePage := TabLightAudit
  else
    PageMain.ActivePage := TabShader;
end;

destructor TNprShaderStudioForm.Destroy;
begin
  FreeAndNil(FCurrentReport);
  FreeAndNil(FSelectedTransforms);
  inherited;
end;

procedure TNprShaderStudioForm.LoadInitialBehaviorFromSelection;
var
  I: Integer;
  T: TCastleTransform;
  Existing: TCastleStylizedShaderBehavior;
begin
  Existing := nil;
  for I := 0 to FSelectedTransforms.Count - 1 do
  begin
    T := TCastleTransform(FSelectedTransforms[I]);
    Existing := T.FindBehavior(TCastleStylizedShaderBehavior) as TCastleStylizedShaderBehavior;
    if Existing <> nil then
      Break;
  end;
  if Existing = nil then
    Exit;

  FUpdatingUi := true;
  try
    ComboPreset.ItemIndex := Ord(Existing.Preset);
    SpinCelBands.Value := Existing.CelBands;
    SpinShadowFloor.Value := Existing.ShadowFloor;
    SpinRimPower.Value := Existing.RimPower;
    SpinIntensity.Value := Existing.Intensity;
    SpinDissolveProgress.Value := Existing.DissolveProgress;
    SpinDissolveScale.Value := Existing.DissolveScale;
    SpinEdgeWidth.Value := Existing.EdgeWidth;
    SpinOutlineThickness.Value := Existing.OutlineThickness;
    FPreviewBehavior.AccentColor := Existing.AccentColor;
    FPreviewBehavior.SecondaryColor := Existing.SecondaryColor;
  finally
    FUpdatingUi := false;
  end;
  SyncPreviewBehaviorFromControls;
end;

procedure TNprShaderStudioForm.SyncPreviewBehaviorFromControls;
begin
  if FUpdatingUi then
    Exit;
  FPreviewBehavior.Preset := TCastleStylizedShaderPreset(
    Clamped(ComboPreset.ItemIndex, 0, Ord(High(TCastleStylizedShaderPreset))));
  FPreviewBehavior.CelBands := SpinCelBands.Value;
  FPreviewBehavior.ShadowFloor := SpinShadowFloor.Value;
  FPreviewBehavior.RimPower := SpinRimPower.Value;
  FPreviewBehavior.Intensity := SpinIntensity.Value;
  FPreviewBehavior.DissolveProgress := SpinDissolveProgress.Value;
  FPreviewBehavior.DissolveScale := SpinDissolveScale.Value;
  FPreviewBehavior.EdgeWidth := SpinEdgeWidth.Value;
  FPreviewBehavior.OutlineThickness := SpinOutlineThickness.Value;
end;

procedure TNprShaderStudioForm.UpdateColorButtonCaptions;
begin
  if BtnPickAccentColor <> nil then
    BtnPickAccentColor.Caption := FormatDot('Accent RGB (%.2f, %.2f, %.2f)...',
      [FPreviewBehavior.AccentColor.X, FPreviewBehavior.AccentColor.Y, FPreviewBehavior.AccentColor.Z]);
  if BtnPickSecondaryColor <> nil then
    BtnPickSecondaryColor.Caption := FormatDot('Secondary RGB (%.2f, %.2f, %.2f)...',
      [FPreviewBehavior.SecondaryColor.X, FPreviewBehavior.SecondaryColor.Y, FPreviewBehavior.SecondaryColor.Z]);
end;

procedure TNprShaderStudioForm.RefreshGlslPreview;
begin
  SyncPreviewBehaviorFromControls;
  if MemoGlslPreview <> nil then
    MemoGlslPreview.Lines.Text := FPreviewBehavior.BuildFragmentShaderSource;
end;

procedure TNprShaderStudioForm.RefreshLightAudit;
var
  I: Integer;
begin
  FreeAndNil(FCurrentReport);
  FCurrentReport := TLightShadowBudgetAuditor.AnalyzeRoot(FDesignRoot);

  ListHotspots.Items.BeginUpdate;
  try
    ListHotspots.Items.Clear;
    for I := 0 to High(FCurrentReport.Hotspots) do
      ListHotspots.Items.AddObject(
        Format('[%s] %s (%s) — %d lights (%d shadow), Cost=%.1f',
          [TLightShadowBudgetAuditor.HeatTierDisplayName(FCurrentReport.Hotspots[I].HeatTier),
           FCurrentReport.Hotspots[I].ReceiverName,
           FCurrentReport.Hotspots[I].ReceiverClass,
           FCurrentReport.Hotspots[I].OverlappingLightCount,
           FCurrentReport.Hotspots[I].ShadowLightCount,
           FCurrentReport.Hotspots[I].ComplexityScore]),
        FCurrentReport.Hotspots[I].ReceiverComponent);
  finally
    ListHotspots.Items.EndUpdate;
  end;

  MemoAuditReport.Lines.Text := FCurrentReport.FormatSummaryReport;
  BtnFixMultiShadow.Enabled := FCurrentReport.HasMultipleShadowVolumeConflict;
  BtnClampRadii.Enabled := FCurrentReport.UnboundedPunctualLights > 0;
end;

procedure TNprShaderStudioForm.AnyShaderParamChange(Sender: TObject);
begin
  RefreshGlslPreview;
end;

procedure TNprShaderStudioForm.BtnPickAccentColorClick(Sender: TObject);
begin
  ColorDlg.Color := CastleRgbToTColor(FPreviewBehavior.AccentColor);
  if ColorDlg.Execute then
  begin
    FPreviewBehavior.AccentColor := TColorToCastleRgb(ColorDlg.Color);
    UpdateColorButtonCaptions;
    RefreshGlslPreview;
  end;
end;

procedure TNprShaderStudioForm.BtnPickSecondaryColorClick(Sender: TObject);
begin
  ColorDlg.Color := CastleRgbToTColor(FPreviewBehavior.SecondaryColor);
  if ColorDlg.Execute then
  begin
    FPreviewBehavior.SecondaryColor := TColorToCastleRgb(ColorDlg.Color);
    UpdateColorButtonCaptions;
    RefreshGlslPreview;
  end;
end;

procedure TNprShaderStudioForm.BtnApplyToSelectedClick(Sender: TObject);
var
  I: Integer;
  T: TCastleTransform;
  Beh: TCastleStylizedShaderBehavior;
begin
  SyncPreviewBehaviorFromControls;
  for I := 0 to FSelectedTransforms.Count - 1 do
  begin
    T := TCastleTransform(FSelectedTransforms[I]);
    Beh := TLightShadowBudgetAuditor.AttachOrUpdateStylizedShader(
      T, FDesignOwner, FPreviewBehavior.Preset);
    if Beh <> nil then
    begin
      Beh.CelBands := FPreviewBehavior.CelBands;
      Beh.ShadowFloor := FPreviewBehavior.ShadowFloor;
      Beh.RimPower := FPreviewBehavior.RimPower;
      Beh.Intensity := FPreviewBehavior.Intensity;
      Beh.DissolveProgress := FPreviewBehavior.DissolveProgress;
      Beh.DissolveScale := FPreviewBehavior.DissolveScale;
      Beh.EdgeWidth := FPreviewBehavior.EdgeWidth;
      Beh.OutlineThickness := FPreviewBehavior.OutlineThickness;
      Beh.AccentColor := FPreviewBehavior.AccentColor;
      Beh.SecondaryColor := FPreviewBehavior.SecondaryColor;
      Beh.RebuildAndApplyEffect;
    end;
  end;
  if Assigned(FOnModified) then
    FOnModified('Apply Stylized / NPR Shader (' +
      TLightShadowBudgetAuditor.PresetDisplayName(FPreviewBehavior.Preset) + ')');
end;

procedure TNprShaderStudioForm.BtnRemoveFromSelectedClick(Sender: TObject);
var
  I, RemovedCount: Integer;
begin
  RemovedCount := 0;
  for I := 0 to FSelectedTransforms.Count - 1 do
    if TLightShadowBudgetAuditor.RemoveStylizedShader(TCastleTransform(FSelectedTransforms[I])) then
      Inc(RemovedCount);
  if (RemovedCount > 0) and Assigned(FOnModified) then
    FOnModified('Remove Stylized / NPR Shader Behavior');
end;

procedure TNprShaderStudioForm.BtnExportGlslClick(Sender: TObject);
const
  PresetFileNames: array [TCastleStylizedShaderPreset] of String = (
    'npr_cel_toon.fs',
    'npr_fresnel_rim.fs',
    'npr_dissolve.fs',
    'npr_gooch_technical.fs',
    'npr_silhouette_outline.fs'
  );
var
  DataDirPath, ShadersDirPath, OutFile, OutUrl: String;
  SL: TStringList;
begin
  SyncPreviewBehaviorFromControls;
  if ApplicationDataOverride = '' then
  begin
    InfoBox('Open a Castle Game Engine project first to export into castle-data:/shaders/, or click "Copy GLSL to Clipboard".');
    Exit;
  end;

  DataDirPath := ExcludeTrailingPathDelimiter(UriToFilenameSafe(ApplicationDataOverride));
  ShadersDirPath := IncludeTrailingPathDelimiter(DataDirPath) + 'shaders';
  ForceDirectories(ShadersDirPath);
  OutFile := IncludeTrailingPathDelimiter(ShadersDirPath) + PresetFileNames[FPreviewBehavior.Preset];
  OutUrl := 'castle-data:/shaders/' + PresetFileNames[FPreviewBehavior.Preset];

  SL := TStringList.Create;
  try
    SL.Text := FPreviewBehavior.BuildFragmentShaderSource;
    SL.SaveToFile(OutFile);
  finally
    FreeAndNil(SL);
  end;
  InfoBox('Exported stylized GLSL shader to:' + NL + OutUrl);
end;

procedure TNprShaderStudioForm.BtnCopyGlslClick(Sender: TObject);
begin
  SyncPreviewBehaviorFromControls;
  Clipboard.AsText := FPreviewBehavior.BuildFragmentShaderSource;
end;

procedure TNprShaderStudioForm.CheckViewportOverlayChange(Sender: TObject);
begin
  if Assigned(FOnToggleOverlay) then
    FOnToggleOverlay(CheckViewportOverlay.Checked);
end;

procedure TNprShaderStudioForm.BtnRefreshAuditClick(Sender: TObject);
begin
  RefreshLightAudit;
end;

procedure TNprShaderStudioForm.BtnFixMultiShadowClick(Sender: TObject);
var
  FixedCount: Integer;
begin
  FixedCount := TLightShadowBudgetAuditor.EnsureSingleShadowVolumeLight(FDesignRoot);
  if (FixedCount > 0) and Assigned(FOnModified) then
    FOnModified('Resolve Multi-Shadow-Volume Conflict');
  RefreshLightAudit;
end;

procedure TNprShaderStudioForm.BtnClampRadiiClick(Sender: TObject);
var
  ClampedCount: Integer;
begin
  ClampedCount := TLightShadowBudgetAuditor.ClampUnboundedLightRadii(
    FDesignRoot, SpinClampRadius.Value);
  if (ClampedCount > 0) and Assigned(FOnModified) then
    FOnModified(Format('Clamp %d Unbounded Light Radii', [ClampedCount]));
  RefreshLightAudit;
end;

procedure TNprShaderStudioForm.ListHotspotsDblClick(Sender: TObject);
var
  Idx: Integer;
  Obj: TObject;
begin
  Idx := ListHotspots.ItemIndex;
  if (Idx >= 0) and (Idx < ListHotspots.Items.Count) then
  begin
    Obj := ListHotspots.Items.Objects[Idx];
    if (Obj is TComponent) and Assigned(FOnSelectComponent) then
      FOnSelectComponent(TComponent(Obj));
  end;
end;

procedure TNprShaderStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrClose;
  Close;
end;

end.

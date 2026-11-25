{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Material Instance Editor & Material Parameter
  Collections (MPC) Studio featuring a live ray-shaded PBR Preview Sphere,
  Parent -> Child Inheritance Chain Inspector, Global MPC Weathering Broadcast
  Controls, and Interactive bOverride_* Parameter Table
  (Phase 391 — 111 UE Studios / 34 MCP). }
unit FormMaterialInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleMaterialInstance, ToolMaterialInstance;

type
  TMatInstModifiedCallback = procedure(const UndoComment: String) of object;
  TMatInstRefreshCallback = procedure of object;

  TMaterialInstanceForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMatInstModifiedCallback;
    FOnRefresh: TMatInstRefreshCallback;

    FActiveMi: TCastleMaterialInstance;
    FActiveMpc: TCastleMaterialParameterCollection;

    FLblStatus: TLabel;
    FPaintViewport: TPaintBox;
    FPaintDetails: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintShaderSphereAndChain(Sender: TObject);
    procedure PaintParameterDetailsTable(Sender: TObject);
    procedure DetailsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnShowcaseClick(Sender: TObject);
    procedure BtnSelectParentClick(Sender: TObject);
    procedure BtnSelectChildClick(Sender: TObject);
    procedure BtnMpcDryClick(Sender: TObject);
    procedure BtnMpcRainClick(Sender: TObject);
    procedure BtnMpcSnowClick(Sender: TObject);
    procedure BtnMpcNeonClick(Sender: TObject);
    procedure BtnResetChildClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMatInstModifiedCallback;
      const AOnRefresh: TMatInstRefreshCallback);
  end;

implementation

function RGBToTColorClamped(const R, G, B: Single): TColor;
begin
  Result := RGBToColor(
     Byte(Round(EnsureRange(R, 0.0, 1.0) * 255)),
    Byte(Round(EnsureRange(G, 0.0, 1.0) * 255)),
    Byte(Round(EnsureRange(B, 0.0, 1.0) * 255))
  );
end;

constructor TMaterialInstanceForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMatInstModifiedCallback;
  const AOnRefresh: TMatInstRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Material Instance Editor & Material Parameter Collections (MPC) Studio (111 UE Studios / 34 MCP)';
  Position := poScreenCenter;
  Width := 1320;
  Height := 760;

  BuildUi;
  FActiveMpc := TMaterialInstanceHelper.FindFirstMpc(FDesignRoot);
  FActiveMi := TMaterialInstanceHelper.FindFirstMaterialInstance(FDesignRoot);
  RefreshFromScene;
end;

procedure TMaterialInstanceForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnSpawn, BtnSelParent, BtnSelChild, BtnDry, BtnRain, BtnSnow, BtnNeon,
    BtnReset, BtnCopy, BtnClose: TButton;
  XPos: Integer;

  function MakeToolbarBtn(const ACaption: String; const AWidth: Integer;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PnlToolbar;
    Result.Left := XPos;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    Inc(XPos, AWidth + 6);
  end;

begin
  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;
  PnlToolbar.Color := RGBToColor(34, 37, 45);

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Top := 0;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := RGBToColor(26, 28, 34);
  PnlToolbar.Top := 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 12;
  FLblStatus.Top := 8;
  FLblStatus.Font.Color := RGBToColor(225, 232, 245);
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := 'Material Instance Editor & Global MPC Studio Ready.';

  XPos := 10;
  BtnSpawn := MakeToolbarBtn('+ Spawn Showcase', 146, @BtnSpawnShowcaseClick);
  BtnSelParent := MakeToolbarBtn('Inspect Parent MI', 132, @BtnSelectParentClick);
  BtnSelChild := MakeToolbarBtn('Inspect Child MI', 128, @BtnSelectChildClick);
  BtnDry := MakeToolbarBtn('MPC: Dry Noon', 120, @BtnMpcDryClick);
  BtnRain := MakeToolbarBtn('MPC: Monsoon Rain', 146, @BtnMpcRainClick);
  BtnSnow := MakeToolbarBtn('MPC: Blizzard Snow', 148, @BtnMpcSnowClick);
  BtnNeon := MakeToolbarBtn('MPC: Neon Night', 132, @BtnMpcNeonClick);
  BtnReset := MakeToolbarBtn('Reset Overrides', 132, @BtnResetChildClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 104, @BtnCopyMarkdownClick);
  BtnClose := MakeToolbarBtn('Close', 72, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnSpawn <> nil) and (BtnSelParent <> nil) and (BtnSelChild <> nil) and
     (BtnDry <> nil) and (BtnRain <> nil) and (BtnSnow <> nil) and
     (BtnNeon <> nil) and (BtnReset <> nil) and (BtnCopy <> nil) then ;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 128;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.Font.Name := 'Consolas';
  FMemoReport.Font.Size := 9;
  FMemoReport.Color := RGBToColor(18, 20, 26);
  FMemoReport.Font.Color := RGBToColor(208, 218, 232);

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 540;
  PnlRight.BevelOuter := bvNone;

  FPaintDetails := TPaintBox.Create(Self);
  FPaintDetails.Parent := PnlRight;
  FPaintDetails.Align := alClient;
  FPaintDetails.OnPaint := @PaintParameterDetailsTable;
  FPaintDetails.OnMouseDown := @DetailsMouseDown;

  FPaintViewport := TPaintBox.Create(Self);
  FPaintViewport.Parent := Self;
  FPaintViewport.Align := alClient;
  FPaintViewport.OnPaint := @PaintShaderSphereAndChain;
end;

procedure TMaterialInstanceForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TMaterialInstanceForm.RefreshFromScene;
var
  Surf: TResolvedPbrSurface;
begin
  if FActiveMpc = nil then
    FActiveMpc := TMaterialInstanceHelper.FindFirstMpc(FDesignRoot);
  if FActiveMi = nil then
    FActiveMi := TMaterialInstanceHelper.FindFirstMaterialInstance(FDesignRoot);

  if FActiveMi <> nil then
  begin
    Surf := FActiveMi.EvaluateEffectiveSurface(FActiveMpc);
    FLblStatus.Caption := Format(
      'Active: %s  |  Chain: %s  |  Overrides: %d/%d  |  Roughness=%.2f  Metallic=%.2f  |  StaticPerm=%s (%d Shader Compiles)',
      [FActiveMi.Name, FActiveMi.HierarchyChainString,
       Surf.OverriddenCount, Length(FActiveMi.Slots),
       Surf.FinalRoughness, Surf.FinalMetallic,
       Surf.StaticSwitchMaskHex, Surf.ShaderPermutationsCompiled]);
  end else
    FLblStatus.Caption := 'No TCastleMaterialInstance in scene — click "+ Spawn Parent->Child + MPC" to create a 3-Sphere Showcase.';

  FMemoReport.Lines.Text := TMaterialInstanceHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveMi, FActiveMpc);

  FPaintViewport.Invalidate;
  FPaintDetails.Invalidate;
end;

procedure TMaterialInstanceForm.PaintShaderSphereAndChain(Sender: TObject);
var
  C: TCanvas;
  W, H, SphCX, SphCY, SphR, PX, PY, StepPix, NodeX, NodeW, NodeY, I: Integer;
  Surf: TResolvedPbrSurface;
  DX, DY, DistSq, NZ, NdotL, NdotH, Rim, SpecPow, SpecStr, Diff, RCol, GCol, BCol,
    LX, LY, LZ, HX, HY, HZ, InvLen, WetVal, SnowVal, WindVal, PulseVal: Single;
  CheckerDark: Boolean;
  ChainLabels: array[0..2] of String;
  ChainBadges: array[0..2] of String;
  ChainCount: Integer;
  MpcNames: array[0..3] of String;
  MpcVals: array[0..3] of Single;
  MpcCols: array[0..3] of TColor;
  BarX, BarW, BarY, FillW: Integer;
begin
  C := FPaintViewport.Canvas;
  W := Max(320, FPaintViewport.Width);
  H := Max(280, FPaintViewport.Height);

  C.Brush.Color := RGBToColor(20, 22, 28);
  C.FillRect(0, 0, W, H);

  { Header bar }
  C.Brush.Color := RGBToColor(30, 34, 44);
  C.FillRect(0, 0, W, 30);
  C.Font.Color := RGBToColor(135, 195, 255);
  C.Font.Style := [fsBold];
  C.TextOut(12, 7, 'UE 5.5 PBR Material Preview Sphere + Hierarchy Chain + Global MPC Broadcast');
  C.Font.Style := [];

  if FActiveMi <> nil then
    Surf := FActiveMi.EvaluateEffectiveSurface(FActiveMpc)
  else
  begin
    Surf := Default(TResolvedPbrSurface);
    Surf.FinalBaseColor := Vector4(0.32, 0.48, 0.34, 1.0);
    Surf.FinalRoughness := 0.35;
    Surf.FinalMetallic := 0.10;
    Surf.FinalClearCoat := 0.40;
    Surf.StaticSwitchMaskHex := '0x03';
    Surf.ShaderPermutationsCompiled := 1;
  end;

  { Left Viewport Box: Checkerboard studio backdrop + Ray-shaded PBR Sphere }
  SphCX := Min(176, W div 4 + 10);
  SphCY := 44 + (H - 64) div 2;
  SphR := Min(132, Min(SphCX - 22, (H - 96) div 2));

  for PY := 42 to H - 18 do
    if (PY - 42) mod 18 = 0 then
      for PX := 14 to SphCX * 2 - 14 do
        if (PX - 14) mod 18 = 0 then
        begin
          CheckerDark := (((PX - 14) div 18) + ((PY - 42) div 18)) mod 2 = 0;
          if CheckerDark then
            C.Brush.Color := RGBToColor(27, 30, 38)
          else
            C.Brush.Color := RGBToColor(35, 39, 49);
          C.FillRect(PX, PY, Min(PX + 18, SphCX * 2 - 14), Min(PY + 18, H - 18));
        end;

  { Outer emissive bloom halo if emissive > 0 }
  if Surf.FinalEmissiveRGB.Length > 0.05 then
  begin
    C.Pen.Color := RGBToTColorClamped(
      Surf.FinalEmissiveRGB.X * 0.35,
      Surf.FinalEmissiveRGB.Y * 0.35,
      Surf.FinalEmissiveRGB.Z * 0.35);
    C.Pen.Width := 4;
    C.Brush.Style := bsClear;
    C.Ellipse(SphCX - SphR - 6, SphCY - SphR - 6, SphCX + SphR + 6, SphCY + SphR + 6);
    C.Brush.Style := bsSolid;
    C.Pen.Width := 1;
  end;

  { Analytical per-block ray-shaded PBR sphere (3x3 pixel blocks for crisp interactive speed) }
  LX := -0.48; LY := -0.58; LZ := 0.66;
  HX := LX; HY := LY; HZ := LZ + 1.0;
  InvLen := 1.0 / Sqrt(HX * HX + HY * HY + HZ * HZ);
  HX := HX * InvLen; HY := HY * InvLen; HZ := HZ * InvLen;

  SpecPow := Lerp(190.0, 8.0, Surf.FinalRoughness);
  SpecStr := Lerp(0.95, 0.12, Surf.FinalRoughness) * Lerp(0.35, 1.25, Surf.FinalMetallic)
    + Surf.FinalClearCoat * 0.55;

  StepPix := 3;
  PY := SphCY - SphR;
  while PY <= SphCY + SphR do
  begin
    PX := SphCX - SphR;
    while PX <= SphCX + SphR do
    begin
      DX := (PX - SphCX) / Max(1, SphR);
      DY := (PY - SphCY) / Max(1, SphR);
      DistSq := DX * DX + DY * DY;
      if DistSq <= 1.0 then
      begin
        NZ := Sqrt(Max(0.0, 1.0 - DistSq));
        NdotL := Max(0.0, DX * LX + DY * LY + NZ * LZ);
        NdotH := Max(0.0, DX * HX + DY * HY + NZ * HZ);
        Rim := Power(1.0 - NZ, 3.0) * (0.20 + 0.45 * Surf.FinalClearCoat);
        Diff := (0.18 + 0.82 * NdotL) * (1.0 - 0.65 * Surf.FinalMetallic);

        RCol := Surf.FinalBaseColor.X * Diff
          + Power(NdotH, SpecPow) * SpecStr * Lerp(1.0, Surf.FinalBaseColor.X, Surf.FinalMetallic)
          + Rim * 0.55 + Surf.FinalEmissiveRGB.X * 0.18;
        GCol := Surf.FinalBaseColor.Y * Diff
          + Power(NdotH, SpecPow) * SpecStr * Lerp(1.0, Surf.FinalBaseColor.Y, Surf.FinalMetallic)
          + Rim * 0.68 + Surf.FinalEmissiveRGB.Y * 0.18;
        BCol := Surf.FinalBaseColor.Z * Diff
          + Power(NdotH, SpecPow) * SpecStr * Lerp(1.0, Surf.FinalBaseColor.Z, Surf.FinalMetallic)
          + Rim * 0.88 + Surf.FinalEmissiveRGB.Z * 0.18;

        C.Brush.Color := RGBToTColorClamped(RCol, GCol, BCol);
        C.FillRect(PX, PY, PX + StepPix, PY + StepPix);
      end;
      Inc(PX, StepPix);
    end;
    Inc(PY, StepPix);
  end;

  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(92, 108, 136);
  C.Ellipse(SphCX - SphR, SphCY - SphR, SphCX + SphR, SphCY + SphR);
  C.Font.Color := RGBToColor(195, 210, 232);
  C.TextOut(20, H - 38, Format('UV Tiling: %.1fx   Normal: %.2f   ClearCoat: %.2f',
    [Surf.FinalUVTiling, Surf.FinalNormalStrength, Surf.FinalClearCoat]));

  { Right Column Top: Parent -> Child Inheritance Graph }
  NodeX := SphCX * 2 + 8;
  NodeW := Max(220, W - NodeX - 16);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(27, 31, 40);
  C.Pen.Color := RGBToColor(62, 72, 92);
  C.Rectangle(NodeX, 42, NodeX + NodeW, 292);

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 208, 112);
  C.TextOut(NodeX + 12, 50, 'UMaterialInstanceConstant Inheritance Chain');
  C.Font.Style := [];

  ChainCount := 2;
  if FActiveMi <> nil then
  begin
    ChainLabels[0] := 'Master: ' + FActiveMi.MasterMaterialKey;
    ChainBadges[0] := 'Compiled Root Shader Graph (Perm ' + Surf.StaticSwitchMaskHex + ')';
    if FActiveMi.ParentInstance <> nil then
    begin
      ChainCount := 3;
      ChainLabels[1] := 'Parent MI: ' + FActiveMi.ParentInstance.Name;
      ChainBadges[1] := Format('%d Overrides  |  0 Extra Shader Compiles',
        [FActiveMi.ParentInstance.OverriddenParameterCount]);
      ChainLabels[2] := 'Active Child MI: ' + FActiveMi.Name;
      ChainBadges[2] := Format('%d Local Overrides  |  Inherits Unchecked Slots',
        [FActiveMi.OverriddenParameterCount]);
    end else
    begin
      ChainLabels[1] := 'Active MI: ' + FActiveMi.Name;
      ChainBadges[1] := Format('%d Direct Overrides  |  0 Shader Recompiles on Scalar/Vec',
        [FActiveMi.OverriddenParameterCount]);
    end;
  end else
  begin
    ChainLabels[0] := 'Master: M_MasterPBR_Weathering';
    ChainBadges[0] := 'Root PBR + MPC Weathering Node Graph';
    ChainLabels[1] := 'Click "+ Spawn Parent->Child + MPC"';
    ChainBadges[1] := 'Creates Stone Parent + Mossy Child + Sci-Fi Trim';
  end;

  for I := 0 to ChainCount - 1 do
  begin
    NodeY := 80 + I * 68;
    if I = ChainCount - 1 then
    begin
      C.Brush.Color := RGBToColor(38, 66, 98);
      C.Pen.Color := RGBToColor(96, 178, 255);
    end else
    begin
      C.Brush.Color := RGBToColor(36, 41, 54);
      C.Pen.Color := RGBToColor(84, 96, 122);
    end;
    C.RoundRect(NodeX + 16, NodeY, NodeX + NodeW - 16, NodeY + 48, 8, 8);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(235, 242, 255);
    C.TextOut(NodeX + 28, NodeY + 7, ChainLabels[I]);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(168, 198, 228);
    C.TextOut(NodeX + 28, NodeY + 26, ChainBadges[I]);
    C.Brush.Style := bsSolid;

    if I < ChainCount - 1 then
    begin
      C.Pen.Color := RGBToColor(110, 185, 255);
      C.Pen.Width := 2;
      C.MoveTo(NodeX + NodeW div 2, NodeY + 48);
      C.LineTo(NodeX + NodeW div 2, NodeY + 68);
      C.Pen.Width := 1;
    end;
  end;

  { Right Column Bottom: Global MPC Uniform Broadcast Monitor }
  C.Brush.Color := RGBToColor(27, 31, 40);
  C.Pen.Color := RGBToColor(62, 72, 92);
  C.Rectangle(NodeX, 306, NodeX + NodeW, H - 18);

  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(124, 232, 178);
  if FActiveMpc <> nil then
    C.TextOut(NodeX + 12, 314, 'Global MPC: ' + FActiveMpc.CollectionKey +
      Format(' (Rev %d)', [FActiveMpc.Revision]))
  else
    C.TextOut(NodeX + 12, 314, 'Global MPC: MPC_GlobalEnvironment (Default Preview)');
  C.Font.Style := [];

  WetVal := 0.0; SnowVal := 0.0; WindVal := 0.25; PulseVal := 0.50;
  if FActiveMpc <> nil then
  begin
    WetVal := FActiveMpc.GlobalWetness;
    SnowVal := FActiveMpc.SnowCoverage;
    WindVal := FActiveMpc.WindStrength;
    PulseVal := FActiveMpc.EmissivePulsePhase;
  end;

  MpcNames[0] := 'GlobalWetness (Rain Darken + Smooth)';
  MpcNames[1] := 'SnowCoverage (Frost Albedo Blanket)';
  MpcNames[2] := 'WindStrength (Foliage Sway)';
  MpcNames[3] := 'EmissivePulsePhase (Neon Trim)';
  MpcVals[0] := WetVal;
  MpcVals[1] := SnowVal;
  MpcVals[2] := WindVal;
  MpcVals[3] := PulseVal;
  MpcCols[0] := RGBToColor(72, 168, 255);
  MpcCols[1] := RGBToColor(220, 238, 255);
  MpcCols[2] := RGBToColor(102, 224, 162);
  MpcCols[3] := RGBToColor(218, 122, 255);

  BarX := NodeX + 16;
  BarW := Max(120, NodeW - 32);
  for I := 0 to 3 do
  begin
    BarY := 346 + I * 48;
    if BarY + 34 > H - 22 then Break;

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(212, 220, 235);
    C.TextOut(BarX, BarY, Format('%s: %.2f', [MpcNames[I], MpcVals[I]]));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(18, 20, 26);
    C.Pen.Color := RGBToColor(58, 68, 86);
    C.Rectangle(BarX, BarY + 19, BarX + BarW, BarY + 34);

    FillW := Round(EnsureRange(MpcVals[I], 0.0, 1.0) * (BarW - 2));
    if FillW > 0 then
    begin
      C.Brush.Color := MpcCols[I];
      C.Pen.Style := psClear;
      C.Rectangle(BarX + 1, BarY + 20, BarX + 1 + FillW, BarY + 34);
      C.Pen.Style := psSolid;
    end;
  end;
end;

procedure TMaterialInstanceForm.PaintParameterDetailsTable(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY, RowH, BarX, BarW, FillW: Integer;
  EffSlot: TMaterialParameterSlot;
  SrcName, ValStr: String;
  IsOv: Boolean;
  NormT: Single;
begin
  C := FPaintDetails.Canvas;
  W := Max(340, FPaintDetails.Width);
  H := Max(280, FPaintDetails.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(235, 240, 250);
  C.TextOut(10, 7, 'Parameter Groups  (Click Row to Toggle bOverride / Cycle Value)');
  C.Font.Style := [];

  if FActiveMi = nil then
  begin
    C.Font.Color := RGBToColor(168, 178, 198);
    C.TextOut(16, 52, 'Click "+ Spawn Parent->Child + MPC" to inspect live parameter overrides.');
    Exit;
  end;

  RowH := 31;
  for I := 0 to High(FActiveMi.Slots) do
  begin
    RowY := 34 + I * RowH;
    if RowY + RowH > H then Break;

    IsOv := FActiveMi.Slots[I].IsOverridden;
    FActiveMi.GetEffectiveSlot(FActiveMi.Slots[I].ParamName, EffSlot, SrcName);

    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(28, 31, 40)
    else
      C.Brush.Color := RGBToColor(24, 27, 35);
    C.FillRect(0, RowY, W, RowY + RowH - 1);

    { bOverride Checkbox }
    if IsOv then
    begin
      C.Brush.Color := RGBToColor(52, 138, 235);
      C.Pen.Color := RGBToColor(135, 198, 255);
    end else
    begin
      C.Brush.Color := RGBToColor(36, 40, 50);
      C.Pen.Color := RGBToColor(88, 96, 114);
    end;
    C.Rectangle(10, RowY + 7, 26, RowY + 23);
    if IsOv then
    begin
      C.Brush.Style := bsClear;
      C.Font.Style := [fsBold];
      C.Font.Color := clWhite;
      C.TextOut(14, RowY + 7, 'x');
      C.Font.Style := [];
    end;

    { Parameter Name }
    C.Brush.Style := bsClear;
    if IsOv then
    begin
      C.Font.Style := [fsBold];
      C.Font.Color := RGBToColor(242, 246, 255);
    end else
    begin
      C.Font.Style := [];
      C.Font.Color := RGBToColor(156, 168, 188);
    end;
    C.TextOut(34, RowY + 7, EffSlot.ParamName);
    C.Font.Style := [];

    { Value Control / Swatch / Slider }
    BarX := 222;
    BarW := 140;
    C.Brush.Style := bsSolid;
    case EffSlot.Kind of
      mpkScalar:
        begin
          C.Brush.Color := RGBToColor(16, 18, 24);
          C.Pen.Color := RGBToColor(62, 70, 88);
          C.Rectangle(BarX, RowY + 7, BarX + BarW, RowY + 23);
          NormT := (EffSlot.ScalarValue - EffSlot.MinScalar) /
            Max(0.001, EffSlot.MaxScalar - EffSlot.MinScalar);
          FillW := Round(EnsureRange(NormT, 0.0, 1.0) * (BarW - 2));
          if FillW > 0 then
          begin
            if IsOv then
              C.Brush.Color := RGBToColor(68, 152, 238)
            else
              C.Brush.Color := RGBToColor(72, 84, 106);
            C.Pen.Style := psClear;
            C.Rectangle(BarX + 1, RowY + 8, BarX + 1 + FillW, RowY + 23);
            C.Pen.Style := psSolid;
          end;
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(232, 238, 248);
          C.TextOut(BarX + 6, RowY + 7, Format('%.2f', [EffSlot.ScalarValue]));
        end;
      mpkVector:
        begin
          C.Brush.Color := RGBToTColorClamped(
            EffSlot.VectorValue.X, EffSlot.VectorValue.Y, EffSlot.VectorValue.Z);
          C.Pen.Color := RGBToColor(140, 150, 170);
          C.Rectangle(BarX, RowY + 6, BarX + 34, RowY + 24);
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(208, 218, 234);
          C.TextOut(BarX + 40, RowY + 7, Format('(%.2f, %.2f, %.2f)',
            [EffSlot.VectorValue.X, EffSlot.VectorValue.Y, EffSlot.VectorValue.Z]));
        end;
      mpkTexture:
        begin
          C.Brush.Color := RGBToColor(34, 42, 56);
          C.Pen.Color := RGBToColor(74, 92, 120);
          C.Rectangle(BarX, RowY + 6, BarX + BarW, RowY + 24);
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(172, 214, 255);
          ValStr := EffSlot.TextureSlot;
          if Length(ValStr) > 21 then
            ValStr := Copy(ValStr, 1, 19) + '..';
          C.TextOut(BarX + 5, RowY + 7, ValStr);
        end;
      mpkStaticSwitch:
        begin
          if EffSlot.SwitchValue then
          begin
            C.Brush.Color := RGBToColor(38, 112, 74);
            C.Pen.Color := RGBToColor(96, 212, 148);
            ValStr := 'TRUE (Static)';
          end else
          begin
            C.Brush.Color := RGBToColor(54, 44, 48);
            C.Pen.Color := RGBToColor(118, 86, 94);
            ValStr := 'FALSE';
          end;
          C.RoundRect(BarX, RowY + 6, BarX + 108, RowY + 24, 6, 6);
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(232, 242, 236);
          C.TextOut(BarX + 10, RowY + 7, ValStr);
        end;
    end;

    { Provenance Badge (Self / Parent / Master) }
    C.Brush.Style := bsClear;
    if Pos('Self', SrcName) = 1 then
      C.Font.Color := RGBToColor(112, 196, 255)
    else if Pos('Parent', SrcName) = 1 then
      C.Font.Color := RGBToColor(255, 206, 112)
    else
      C.Font.Color := RGBToColor(138, 148, 168);
    if Length(SrcName) > 20 then
      SrcName := Copy(SrcName, 1, 18) + '..';
    C.TextOut(386, RowY + 7, SrcName);
    C.Brush.Style := bsSolid;
  end;
end;

procedure TMaterialInstanceForm.DetailsMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  EffSlot: TMaterialParameterSlot;
  Src: String;
  NormT: Single;
begin
  if (FActiveMi = nil) or (Y < 34) then Exit;
  Idx := (Y - 34) div 31;
  if (Idx < 0) or (Idx > High(FActiveMi.Slots)) then Exit;

  if X < 32 then
  begin
    { Toggle bOverride_* checkbox }
    if FActiveMi.Slots[Idx].IsOverridden then
      FActiveMi.ResetParameterToParent(FActiveMi.Slots[Idx].ParamName)
    else
    begin
      FActiveMi.GetEffectiveSlot(FActiveMi.Slots[Idx].ParamName, EffSlot, Src);
      case EffSlot.Kind of
        mpkScalar: FActiveMi.SetScalarParameterValue(EffSlot.ParamName, EffSlot.ScalarValue);
        mpkVector: FActiveMi.SetVectorParameterValue(EffSlot.ParamName, EffSlot.VectorValue);
        mpkTexture: FActiveMi.SetTextureParameterValue(EffSlot.ParamName, EffSlot.TextureSlot);
        mpkStaticSwitch: FActiveMi.SetStaticSwitchParameterValue(EffSlot.ParamName, not EffSlot.SwitchValue);
      end;
    end;
    NotifyChanged('Toggle Material Instance Override ' + FActiveMi.Slots[Idx].ParamName);
    Exit;
  end;

  { Click inside Scalar bar sets scalar directly; click on StaticSwitch toggles it }
  FActiveMi.GetEffectiveSlot(FActiveMi.Slots[Idx].ParamName, EffSlot, Src);
  if (EffSlot.Kind = mpkScalar) and (X >= 222) and (X <= 362) then
  begin
    NormT := EnsureRange((X - 222) / 140.0, 0.0, 1.0);
    FActiveMi.SetScalarParameterValue(EffSlot.ParamName,
      EffSlot.MinScalar + NormT * (EffSlot.MaxScalar - EffSlot.MinScalar));
    NotifyChanged('Adjust Material Scalar ' + EffSlot.ParamName);
  end else
  if (EffSlot.Kind = mpkStaticSwitch) and (X >= 222) and (X <= 332) then
  begin
    FActiveMi.SetStaticSwitchParameterValue(EffSlot.ParamName, not EffSlot.SwitchValue);
    NotifyChanged('Toggle Material Static Switch ' + EffSlot.ParamName);
  end;
end;

procedure TMaterialInstanceForm.BtnSpawnShowcaseClick(Sender: TObject);
var
  ParentMi, ChildMi: TCastleMaterialInstance;
begin
  TMaterialInstanceHelper.SpawnParentChildMpcShowcaseInDesign(
    FDesignRoot, FDesignOwner, FActiveMpc, ParentMi, ChildMi);
  if ChildMi <> nil then
    FActiveMi := ChildMi
  else
    FActiveMi := ParentMi;
  NotifyChanged('Spawn Parent->Child Material Instance + MPC Showcase');
end;

procedure TMaterialInstanceForm.BtnSelectParentClick(Sender: TObject);
begin
  if (FActiveMi <> nil) and (FActiveMi.ParentInstance <> nil) then
  begin
    FActiveMi := FActiveMi.ParentInstance;
    RefreshFromScene;
  end;
end;

procedure TMaterialInstanceForm.BtnSelectChildClick(Sender: TObject);
var
  L: TList;
  I: Integer;
begin
  L := TList.Create;
  try
    TMaterialInstanceHelper.CollectMaterialInstances(FDesignRoot, L);
    for I := 0 to L.Count - 1 do
      if TCastleMaterialInstance(L[I]).ParentInstance <> nil then
      begin
        FActiveMi := TCastleMaterialInstance(L[I]);
        Break;
      end;
  finally
    FreeAndNil(L);
  end;
  RefreshFromScene;
end;

procedure TMaterialInstanceForm.BtnMpcDryClick(Sender: TObject);
begin
  TMaterialInstanceHelper.BroadcastMpcPresetInDesign(FDesignRoot, mpcpClearNoonDry);
  NotifyChanged('Broadcast MPC Clear Noon Dry');
end;

procedure TMaterialInstanceForm.BtnMpcRainClick(Sender: TObject);
begin
  TMaterialInstanceHelper.BroadcastMpcPresetInDesign(FDesignRoot, mpcpMonsoonRainStorm);
  NotifyChanged('Broadcast MPC Monsoon Rain Storm');
end;

procedure TMaterialInstanceForm.BtnMpcSnowClick(Sender: TObject);
begin
  TMaterialInstanceHelper.BroadcastMpcPresetInDesign(FDesignRoot, mpcpBlizzardSnowline);
  NotifyChanged('Broadcast MPC Blizzard Snowline');
end;

procedure TMaterialInstanceForm.BtnMpcNeonClick(Sender: TObject);
begin
  TMaterialInstanceHelper.BroadcastMpcPresetInDesign(FDesignRoot, mpcpCyberpunkNeonNight);
  NotifyChanged('Broadcast MPC Cyberpunk Neon Night');
end;

procedure TMaterialInstanceForm.BtnResetChildClick(Sender: TObject);
begin
  if FActiveMi <> nil then
  begin
    FActiveMi.ResetAllOverrides;
    NotifyChanged('Reset Material Instance Overrides to Parent');
  end;
end;

procedure TMaterialInstanceForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Material Instance & MPC Markdown Report to Clipboard.';
end;

end.

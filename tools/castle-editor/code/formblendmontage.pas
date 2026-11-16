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

{ Interactive 1D/2D Gradient-Band Locomotion Blend Space, Motion-Warped Root
  Motion & Frame-Exact Anim Montage Studio (@link(TBlendMontageForm)) featuring
  an interactive clickable 2D (DirectionDeg x Speed) Blend Space weight canvas,
  Montage section/notify timeline visualization, 1-click Combo / Dodge Roll
  triggers, and Markdown export (Phase 318). }
unit FormBlendMontage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleBlendMontage, ToolBlendMontage;

type
  TBlendMontageModifiedCallback = procedure(const AComment: String) of object;
  TBlendMontageRefreshViewportCallback = procedure of object;

  TBlendMontageForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBlendMontageModifiedCallback;
    FOnRefreshViewport: TBlendMontageRefreshViewportCallback;

    FBlends: TBlendSpaceArray;
    FMontages: TAnimMontageArray;
    FReport: TBlendMontageAuditReport;

    LblHeader: TLabel;
    ListItems: TListBox;
    PaintStudio: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveBlend: TCastleBlendSpace2DBehavior;
    function ActiveMontage: TCastleAnimMontageBehavior;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnHeroDemoClick(Sender: TObject);
    procedure BtnPlaySlash1Click(Sender: TObject);
    procedure BtnQueueComboClick(Sender: TObject);
    procedure BtnPlayDodgeIframeClick(Sender: TObject);
    procedure BtnStepPointOneClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure ListItemsClick(Sender: TObject);
    procedure PaintStudioPaint(Sender: TObject);
    procedure PaintStudioMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBlendMontageModifiedCallback;
      const AOnRefreshViewport: TBlendMontageRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TBlendMontageForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBlendMontageModifiedCallback;
  const AOnRefreshViewport: TBlendMontageRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := '2D Locomotion Blend Space, Motion Warping & Anim Montage Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TBlendMontageForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TBlendMontageForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := '2D Blend Spaces & Anim Montages: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn 8-Way Hero + Combo Target', 4, 2, 238, @BtnSpawnHeroDemoClick);
  MakeBtn(RowTop, 'Play Slash1 (Lunge Warp)', 248, 2, 178, @BtnPlaySlash1Click);
  MakeBtn(RowTop, 'Queue Next Combo!', 432, 2, 150, @BtnQueueComboClick);
  MakeBtn(RowTop, 'Play Dodge Roll (i-Frame)', 588, 2, 180, @BtnPlayDodgeIframeClick);
  MakeBtn(RowTop, 'Step (+0.10s)', 774, 2, 125, @BtnStepPointOneClick);
  MakeBtn(RowTop, 'Copy Markdown Report', 905, 2, 175, @BtnCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'BlendSpace2D & AnimMontage Behaviors:';

  ListItems := TListBox.Create(Self);
  ListItems.Parent := PanelLeft;
  ListItems.SetBounds(10, 26, 320, 240);
  ListItems.OnClick := @ListItemsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 274, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Sample Weights, Active Tags & QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 296, 320, 275);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintStudio := TPaintBox.Create(Self);
  PaintStudio.Parent := PanelCenter;
  PaintStudio.Align := alClient;
  PaintStudio.OnPaint := @PaintStudioPaint;
  PaintStudio.OnMouseDown := @PaintStudioMouseDown;
end;

function TBlendMontageForm.ActiveBlend: TCastleBlendSpace2DBehavior;
begin
  if Length(FBlends) > 0 then
    Result := FBlends[0]
  else
    Result := nil;
end;

function TBlendMontageForm.ActiveMontage: TCastleAnimMontageBehavior;
begin
  if Length(FMontages) > 0 then
    Result := FMontages[0]
  else
    Result := nil;
end;

procedure TBlendMontageForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TBlendMontageForm.RefreshAll;
var
  I: Integer;
  B: TCastleBlendSpace2DBehavior;
  M: TCastleAnimMontageBehavior;
  S: TBlendSampleDef;
begin
  TBlendMontageHelper.ScanBlendAndMontages(FDesignRoot, FDesignOwner, FBlends, FMontages);
  FreeAndNil(FReport);
  FReport := TBlendMontageHelper.AuditBlendAndMontages(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    '2D Blend Spaces: %d (%d samples)  |  Anim Montages: %d (%d notifies)  |  QA Warnings: %d',
    [FReport.BlendSpaceCount, FReport.TotalSamples, FReport.MontageCount,
     FReport.TotalNotifies, FReport.Warnings.Count]);

  ListItems.Items.BeginUpdate;
  try
    ListItems.Items.Clear;
    for I := 0 to High(FBlends) do
      ListItems.Items.Add(Format('%s  %s', [FBlends[I].Name, FBlends[I].BlendSummaryBadge]));
    for I := 0 to High(FMontages) do
      ListItems.Items.Add(Format('%s  %s', [FMontages[I].Name, FMontages[I].MontageSummaryBadge]));
  finally
    ListItems.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    B := ActiveBlend;
    if B <> nil then
    begin
      MemoDiag.Lines.Add(Format('BlendSpace: %s  (%.1f, %.2f) -> %s (%.2fx)',
        [B.Name, B.CurrentParamX, B.CurrentParamY, B.DominantAnimationName, B.EffectivePlaySpeed]));
      for I := 0 to B.SampleCount - 1 do
      begin
        S := B.GetSample(I);
        if S.ComputedWeight > 0.01 then
          MemoDiag.Lines.Add(Format('  - %s [%s]: %.0f%%', [S.SampleName, S.AnimationClipName, S.ComputedWeight * 100.0]));
      end;
      MemoDiag.Lines.Add('');
    end;
    M := ActiveMontage;
    if M <> nil then
    begin
      MemoDiag.Lines.Add(Format('Montage: %s  Section=%s  t=%.2f / %.2fs  ComboQueued=%s',
        [M.Name, M.CurrentSectionName, M.CurrentTimeSec, M.TotalDurationSec,
         BoolToStr(M.ComboQueued, 'YES', 'no')]));
      if M.ActiveTags.Count > 0 then
        MemoDiag.Lines.Add('  Active Tags: ' + M.ActiveTags.CommaText);
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All BlendSpace2D & AnimMontage links verified.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintStudio.Invalidate;
end;

procedure TBlendMontageForm.BtnSpawnHeroDemoClick(Sender: TObject);
var
  H, T: TCastleTransform;
  B: TCastleBlendSpace2DBehavior;
  M: TCastleAnimMontageBehavior;
begin
  TBlendMontageHelper.SpawnHeroLocomotionAndMontageDemo(FDesignRoot, FDesignOwner, H, T, B, M);
  NotifyChanged('Spawn 8-Way Hero Locomotion & Combo Montage Demo');
end;

procedure TBlendMontageForm.BtnPlaySlash1Click(Sender: TObject);
var
  M: TCastleAnimMontageBehavior;
begin
  M := ActiveMontage;
  if M = nil then Exit;
  M.ApplyPreset(mpThreeHitSwordCombo);
  M.PlayMontageSection('Slash1');
  NotifyChanged('Play Montage Section Slash1');
end;

procedure TBlendMontageForm.BtnQueueComboClick(Sender: TObject);
var
  M: TCastleAnimMontageBehavior;
begin
  M := ActiveMontage;
  if M = nil then Exit;
  M.QueueComboInput;
  NotifyChanged('Queue Anim Montage Combo Input');
end;

procedure TBlendMontageForm.BtnPlayDodgeIframeClick(Sender: TObject);
var
  M: TCastleAnimMontageBehavior;
begin
  M := ActiveMontage;
  if M = nil then Exit;
  M.ApplyPreset(mpDodgeRollInvuln);
  M.PlayMontageSection('DodgeRoll');
  NotifyChanged('Play Dodge Roll Montage (i-Frame Window)');
end;

procedure TBlendMontageForm.BtnStepPointOneClick(Sender: TObject);
begin
  TBlendMontageHelper.StepAllBlendAndMontages(FDesignRoot, FDesignOwner, 0.10);
  NotifyChanged('Step BlendSpace & AnimMontage (+0.10s)');
end;

procedure TBlendMontageForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TBlendMontageHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TBlendMontageForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TBlendMontageForm.ListItemsClick(Sender: TObject);
begin
  RefreshAll;
end;

procedure TBlendMontageForm.PaintStudioMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  B: TCastleBlendSpace2DBehavior;
  PadL, PadR, PadT, PadB: Integer;
  NewX, NewY: Single;
begin
  B := ActiveBlend;
  if B = nil then Exit;
  PadL := 28;
  PadR := PaintStudio.Width - 28;
  PadT := 42;
  PadB := (PaintStudio.Height * 60) div 100;
  if (X >= PadL) and (X <= PadR) and (Y >= PadT) and (Y <= PadB) then
  begin
    NewX := Lerp((X - PadL) / Max(1, PadR - PadL), -B.RangeX, B.RangeX);
    NewY := Lerp(1.0 - (Y - PadT) / Max(1, PadB - PadT), 0.0, B.RangeY);
    B.EvaluateImmediate(NewX, NewY);
    NotifyChanged('Evaluate 2D Blend Space Crosshair');
  end;
end;

procedure TBlendMontageForm.PaintStudioPaint(Sender: TObject);
var
  C: TCanvas;
  B: TCastleBlendSpace2DBehavior;
  M: TCastleAnimMontageBehavior;
  W, H, PadL, PadR, PadT, PadB, Sx, Sy, Rad, I: Integer;
  S: TBlendSampleDef;
  TlL, TlR, TlT, TlB, X1, X2: Integer;
  TotDur: Single;
  Sec: TMontageSectionDef;
  Notif: TAnimNotifyDef;
begin
  C := PaintStudio.Canvas;
  W := Max(200, PaintStudio.Width);
  H := Max(200, PaintStudio.Height);

  C.Brush.Color := RGBToColor(22, 26, 33);
  C.FillRect(0, 0, W, H);

  B := ActiveBlend;
  M := ActiveMontage;
  if (B = nil) and (M = nil) then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn 8-Way Hero + Combo Target" to preview interactive 2D BlendSpace & Montage tracks.');
    Exit;
  end;

  { Top region: Interactive 2D Gradient-Band Blend Space Pad }
  PadL := 28;
  PadR := W - 28;
  PadT := 42;
  PadB := (H * 60) div 100;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(PadL, 14, '2D Gradient-Band Locomotion Pad (Click anywhere to blend DirectionDeg x Speed)');
  C.Font.Style := [];

  C.Pen.Color := RGBToColor(70, 82, 102);
  C.Brush.Color := RGBToColor(30, 36, 46);
  C.Rectangle(PadL, PadT, PadR, PadB);

  if B <> nil then
  begin
    for I := 0 to B.SampleCount - 1 do
    begin
      S := B.GetSample(I);
      Sx := PadL + Round(((S.ParamX + B.RangeX) / Max(1.0, 2.0 * B.RangeX)) * (PadR - PadL));
      Sy := PadB - Round(Clamped(S.ParamY / Max(0.1, B.RangeY), 0.0, 1.0) * (PadB - PadT));
      Rad := 5 + Round(S.ComputedWeight * 18.0);
      C.Brush.Color := RGBToColor(58, 178, 246);
      C.Pen.Color := RGBToColor(180, 230, 255);
      C.Ellipse(Sx - Rad, Sy - Rad, Sx + Rad, Sy + Rad);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(210, 224, 240);
      C.TextOut(Sx + Rad + 4, Sy - 8, Format('%s (%.0f%%)', [S.SampleName, S.ComputedWeight * 100.0]));
    end;

    { Active query crosshair }
    Sx := PadL + Round(((B.CurrentParamX + B.RangeX) / Max(1.0, 2.0 * B.RangeX)) * (PadR - PadL));
    Sy := PadB - Round(Clamped(B.CurrentParamY / Max(0.1, B.RangeY), 0.0, 1.0) * (PadB - PadT));
    C.Pen.Color := RGBToColor(250, 200, 64);
    C.Line(Sx - 12, Sy, Sx + 12, Sy);
    C.Line(Sx, Sy - 12, Sx, Sy + 12);
  end;

  { Bottom region: Anim Montage Sections, Notify Windows & Playhead }
  TlL := 28;
  TlR := W - 28;
  TlT := PadB + 46;
  TlB := H - 24;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(TlL, PadB + 18, 'Anim Montage Section & Notify Timeline');
  C.Font.Style := [];
  C.Pen.Color := RGBToColor(70, 82, 102);
  C.Brush.Color := RGBToColor(30, 36, 46);
  C.Rectangle(TlL, TlT, TlR, TlB);

  if M <> nil then
  begin
    TotDur := Max(0.2, M.TotalDurationSec);
    for I := 0 to M.SectionCount - 1 do
    begin
      Sec := M.GetSection(I);
      X1 := TlL + Round((Sec.StartTimeSec / TotDur) * (TlR - TlL));
      X2 := TlL + Round((Sec.EndTimeSec / TotDur) * (TlR - TlL));
      C.Brush.Color := RGBToColor(46, 62, 86);
      C.Rectangle(X1, TlT + 8, X2, TlT + 38);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(230, 238, 250);
      C.TextOut(X1 + 6, TlT + 14, Sec.SectionName);
    end;

    for I := 0 to M.NotifyCount - 1 do
    begin
      Notif := M.GetNotify(I);
      X1 := TlL + Round((Notif.TriggerTimeSec / TotDur) * (TlR - TlL));
      X2 := TlL + Round(((Notif.TriggerTimeSec + Max(0.02, Notif.DurationSec)) / TotDur) * (TlR - TlL));
      if Notif.IsMotionWarpWindow then
        C.Brush.Color := RGBToColor(186, 108, 248)
      else if Pos('ComboWindow', Notif.GrantedTag) > 0 then
        C.Brush.Color := RGBToColor(68, 216, 142)
      else
        C.Brush.Color := RGBToColor(246, 146, 62);
      C.FillRect(X1, TlT + 48, Max(X1 + 4, X2), TlT + 68);
    end;

    { Playhead }
    X1 := TlL + Round(Clamped(M.CurrentTimeSec / TotDur, 0.0, 1.0) * (TlR - TlL));
    C.Pen.Color := RGBToColor(255, 86, 86);
    C.Pen.Width := 2;
    C.Line(X1, TlT, X1, TlB);
    C.Pen.Width := 1;
  end;
end;

end.

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

{ Interactive Multi-Resolution Responsive UI Safe-Area, Notch & Touch-Target
  Simulator (@link(TResponsiveSimForm))
  (Phase 295 — UE 5.9 / 6.0 CommonUI Responsive Parity). }
unit FormResponsiveSim;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Graphics, Clipbrd, Types,
  CastleRectangles, ToolResponsiveSim;

type
  TResponsiveToggleGuidesCallback = procedure (const AEnabled: Boolean;
    const AProfile: TResponsiveDeviceProfileKind) of object;

  TResponsiveSimForm = class(TForm)
  private
    FRootComponent: TComponent;
    FOnToggleGuides: TResponsiveToggleGuidesCallback;
    FActiveProfile: TResponsiveDeviceProfileKind;
    FGuidesEnabled: Boolean;
    FAudit: TResponsiveAuditSummary;

    ProfileButtons: array [TResponsiveDeviceProfileKind] of TButton;
    CheckViewportGuides: TCheckBox;
    ButtonCopyMarkdown: TButton;

    PaintBoxDevice: TPaintBox;
    ListViewIssues: TListView;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure RefreshSimulation;
    procedure ProfileButtonClick(Sender: TObject);
    procedure CheckViewportGuidesChange(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure PaintBoxDevicePaint(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent: TComponent;
      const AInitialGuidesEnabled: Boolean;
      const AInitialProfile: TResponsiveDeviceProfileKind;
      const AOnToggleGuides: TResponsiveToggleGuidesCallback);
  end;

implementation

constructor TResponsiveSimForm.CreateStudio(AOwner: TComponent;
  const ARootComponent: TComponent;
  const AInitialGuidesEnabled: Boolean;
  const AInitialProfile: TResponsiveDeviceProfileKind;
  const AOnToggleGuides: TResponsiveToggleGuidesCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FGuidesEnabled := AInitialGuidesEnabled;
  FActiveProfile := AInitialProfile;
  FOnToggleGuides := AOnToggleGuides;
  BuildUi;
  RefreshSimulation;
end;

procedure TResponsiveSimForm.BuildUi;
var
  PanelTop, PanelBottom: TPanel;
  P: TResponsiveDeviceProfileKind;
  Spec: TResponsiveDeviceSpec;
  Col: TListColumn;
  X: Integer;
begin
  Caption := 'Multi-Resolution Responsive UI Safe-Area, Notch & Touch-Target Simulator (UE 5.9 / 6.0 CommonUI Parity)';
  Width := 1080;
  Height := 700;
  Position := poMainFormCenter;
  Constraints.MinWidth := 920;
  Constraints.MinHeight := 580;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  X := 8;
  for P := Low(TResponsiveDeviceProfileKind) to High(TResponsiveDeviceProfileKind) do
  begin
    Spec := TResponsiveUiSimulator.GetProfileSpec(P);
    ProfileButtons[P] := TButton.Create(Self);
    ProfileButtons[P].Parent := PanelTop;
    ProfileButtons[P].SetBounds(X, 7, 138, 30);
    ProfileButtons[P].Caption := Format('%s (%s)', [Spec.AspectLabel, IntToStr(Spec.WidthPx) + 'p']);
    ProfileButtons[P].Hint := Spec.DisplayName;
    ProfileButtons[P].ShowHint := true;
    ProfileButtons[P].Tag := Ord(P);
    ProfileButtons[P].OnClick := @ProfileButtonClick;
    Inc(X, 144);
  end;

  CheckViewportGuides := TCheckBox.Create(Self);
  CheckViewportGuides.Parent := PanelTop;
  CheckViewportGuides.SetBounds(X + 6, 11, 185, 22);
  CheckViewportGuides.Caption := 'Show Safe-Area in Viewport';
  CheckViewportGuides.Checked := FGuidesEnabled;
  CheckViewportGuides.OnChange := @CheckViewportGuidesChange;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(X + 198, 7, 152, 30);
  ButtonCopyMarkdown.Caption := 'Copy Audit Markdown';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 38;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 10, 860, 18);
  LabelStatus.Caption := 'Ready.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.BorderSpacing.Around := 5;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  ListViewIssues := TListView.Create(Self);
  ListViewIssues.Parent := Self;
  ListViewIssues.Align := alBottom;
  ListViewIssues.Height := 185;
  ListViewIssues.BorderSpacing.Around := 6;
  ListViewIssues.ViewStyle := vsReport;
  ListViewIssues.RowSelect := true;
  ListViewIssues.ReadOnly := true;

  Col := ListViewIssues.Columns.Add;
  Col.Caption := 'Device Profile';
  Col.Width := 180;

  Col := ListViewIssues.Columns.Add;
  Col.Caption := 'Violation Type';
  Col.Width := 140;

  Col := ListViewIssues.Columns.Add;
  Col.Caption := 'Control(s)';
  Col.Width := 200;

  Col := ListViewIssues.Columns.Add;
  Col.Caption := 'Diagnostic';
  Col.Width := 510;

  PaintBoxDevice := TPaintBox.Create(Self);
  PaintBoxDevice.Parent := Self;
  PaintBoxDevice.Align := alClient;
  PaintBoxDevice.BorderSpacing.Around := 6;
  PaintBoxDevice.OnPaint := @PaintBoxDevicePaint;
end;

procedure TResponsiveSimForm.RefreshSimulation;
var
  P: TResponsiveDeviceProfileKind;
  I: Integer;
  It: TListItem;
  Iss: TResponsiveIssue;
  CurRes: TResponsiveProfileSimResult;
begin
  FAudit := TResponsiveUiSimulator.AuditAllProfiles(FRootComponent);

  ListViewIssues.Items.BeginUpdate;
  try
    ListViewIssues.Items.Clear;
    for P := Low(TResponsiveDeviceProfileKind) to High(TResponsiveDeviceProfileKind) do
      for I := 0 to High(FAudit.Results[P].Issues) do
      begin
        Iss := FAudit.Results[P].Issues[I];
        It := ListViewIssues.Items.Add;
        It.Caption := FAudit.Results[P].Spec.DisplayName + ' (' + FAudit.Results[P].Spec.AspectLabel + ')';
        It.SubItems.Add(ResponsiveIssueKindToLabel(Iss.Kind));
        if Iss.SecondaryComponentName <> '' then
          It.SubItems.Add(Iss.ComponentName + ' <-> ' + Iss.SecondaryComponentName)
        else
          It.SubItems.Add(Iss.ComponentName);
        It.SubItems.Add(Iss.Message);
      end;
  finally
    ListViewIssues.Items.EndUpdate;
  end;

  CurRes := FAudit.Results[FActiveProfile];
  LabelStatus.Caption := Format(
    'Active: %s (%s, %dx%d, UI Scale %.2fx) — %d profile issues | Total across all 5 profiles: %d',
    [CurRes.Spec.DisplayName, CurRes.Spec.AspectLabel,
     CurRes.Spec.WidthPx, CurRes.Spec.HeightPx, CurRes.UiScale,
     Length(CurRes.Issues), FAudit.TotalIssueCount]);
  PaintBoxDevice.Invalidate;
end;

procedure TResponsiveSimForm.ProfileButtonClick(Sender: TObject);
begin
  if not (Sender is TButton) then
    Exit;
  FActiveProfile := TResponsiveDeviceProfileKind(TButton(Sender).Tag);
  if FGuidesEnabled and Assigned(FOnToggleGuides) then
    FOnToggleGuides(true, FActiveProfile);
  RefreshSimulation;
end;

procedure TResponsiveSimForm.CheckViewportGuidesChange(Sender: TObject);
begin
  FGuidesEnabled := CheckViewportGuides.Checked;
  if Assigned(FOnToggleGuides) then
    FOnToggleGuides(FGuidesEnabled, FActiveProfile);
end;

procedure TResponsiveSimForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TResponsiveUiSimulator.FormatResponsiveAuditMarkdown(FRootComponent);
  LabelStatus.Caption := 'Copied 5-Profile Responsive UI & Safe-Area Markdown audit to clipboard.';
end;

procedure TResponsiveSimForm.PaintBoxDevicePaint(Sender: TObject);
var
  C: TCanvas;
  R, ScreenR, SafeR, BoxR, NotchR: TRect;
  Cur: TResponsiveProfileSimResult;
  ScaleFit: Single;
  DrawW, DrawH, OffX, OffY, I: Integer;

  function MapDeviceRect(const DR: TFloatRectangle): TRect;
  var
    L, T, W, H: Integer;
  begin
    L := OffX + Round(DR.Left * ScaleFit);
    W := Max(2, Round(DR.Width * ScaleFit));
    H := Max(2, Round(DR.Height * ScaleFit));
    { Convert bottom-up CGE coordinates into top-down LCL canvas coordinates }
    T := OffY + DrawH - Round((DR.Bottom + DR.Height) * ScaleFit);
    Result := Rect(L, T, L + W, T + H);
  end;

begin
  C := PaintBoxDevice.Canvas;
  R := PaintBoxDevice.ClientRect;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(20, 24, 32);
  C.FillRect(R);

  Cur := FAudit.Results[FActiveProfile];
  if (Cur.Spec.WidthPx <= 0) or (Cur.Spec.HeightPx <= 0) or
     (R.Right < 40) or (R.Bottom < 40) then
    Exit;

  ScaleFit := Min((R.Right - 48) / Cur.Spec.WidthPx, (R.Bottom - 48) / Cur.Spec.HeightPx);
  DrawW := Max(10, Round(Cur.Spec.WidthPx * ScaleFit));
  DrawH := Max(10, Round(Cur.Spec.HeightPx * ScaleFit));
  OffX := (R.Right - DrawW) div 2;
  OffY := (R.Bottom - DrawH) div 2;

  ScreenR := Rect(OffX, OffY, OffX + DrawW, OffY + DrawH);
  C.Brush.Color := RGBToColor(34, 42, 56);
  C.Pen.Color := RGBToColor(120, 140, 175);
  C.Pen.Style := psSolid;
  C.Pen.Width := 2;
  C.Rectangle(ScreenR);

  { Draw Notch / Home-bar exclusion bands if insets > 0 }
  if Cur.Spec.InsetLeftPx > 0 then
  begin
    NotchR := MapDeviceRect(FloatRectangle(0, Cur.Spec.HeightPx * 0.28,
      Cur.Spec.InsetLeftPx * 0.72, Cur.Spec.HeightPx * 0.44));
    C.Brush.Color := RGBToColor(12, 14, 18);
    C.Pen.Color := RGBToColor(235, 95, 95);
    C.Pen.Width := 1;
    C.RoundRect(NotchR.Left, NotchR.Top, NotchR.Right, NotchR.Bottom, 12, 12);
  end;
  if Cur.Spec.InsetBottomPx > 0 then
  begin
    NotchR := MapDeviceRect(FloatRectangle(Cur.Spec.WidthPx * 0.34, 10,
      Cur.Spec.WidthPx * 0.32, Max(8.0, Cur.Spec.InsetBottomPx * 0.24)));
    C.Brush.Color := RGBToColor(195, 205, 220);
    C.Pen.Style := psClear;
    C.RoundRect(NotchR.Left, NotchR.Top, NotchR.Right, NotchR.Bottom, 8, 8);
  end;

  { Draw Safe-Area emerald dashed frame }
  SafeR := MapDeviceRect(Cur.SafeRectPx);
  C.Brush.Style := bsClear;
  C.Pen.Style := psDash;
  C.Pen.Color := RGBToColor(64, 224, 150);
  C.Pen.Width := 1;
  C.Rectangle(SafeR);

  { Draw UI control boxes }
  C.Pen.Style := psSolid;
  for I := 0 to High(Cur.Boxes) do
  begin
    if Cur.Boxes[I].IsBackgroundContainer then
      Continue;
    BoxR := MapDeviceRect(Cur.Boxes[I].DeviceRect);
    if Cur.Boxes[I].HasViolation then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(96, 34, 42);
      C.Pen.Color := RGBToColor(255, 88, 88);
      C.Pen.Width := 2;
    end else
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(46, 72, 108);
      C.Pen.Color := RGBToColor(110, 185, 255);
      C.Pen.Width := 1;
    end;
    C.Rectangle(BoxR);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(235, 240, 250);
    if (BoxR.Right - BoxR.Left > 36) and (BoxR.Bottom - BoxR.Top > 14) then
      C.TextOut(BoxR.Left + 4, BoxR.Top + 2, Cur.Boxes[I].ComponentName);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(180, 225, 255);
  C.Font.Style := [fsBold];
  C.TextOut(12, 8, Format('%s (%s — %dx%d px, Safe Area %.0fx%.0f px)',
    [Cur.Spec.DisplayName, Cur.Spec.AspectLabel,
     Cur.Spec.WidthPx, Cur.Spec.HeightPx,
     Cur.SafeRectPx.Width, Cur.SafeRectPx.Height]));
end;

procedure TResponsiveSimForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.

{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for GameplayDebugger Live 3D HUD & Numpad 0..5 Channels (Phase 363). }
unit FormGameplayDebugger;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleTransform, CastleViewport, CastleGameplayDebugger, ToolGameplayDebugger;

type
  TGameplayDebuggerModifiedCallback = procedure(const UndoComment: String) of object;
  TGameplayDebuggerRefreshCallback = procedure of object;

  TGameplayDebuggerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGameplayDebuggerModifiedCallback;
    FOnRefresh: TGameplayDebuggerRefreshCallback;
    FPaintHud: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveDebugger: TCastleGameplayDebugger;
    procedure ReCollectAndNotify(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnToggleChClick(Sender: TObject);
    procedure BtnAllOnClick(Sender: TObject);
    procedure BtnCopyJsonClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintHudOverlay(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGameplayDebuggerModifiedCallback;
      const AOnRefresh: TGameplayDebuggerRefreshCallback);
  end;

implementation

constructor TGameplayDebuggerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGameplayDebuggerModifiedCallback;
  const AOnRefresh: TGameplayDebuggerRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'GameplayDebugger Live 3D HUD & Numpad 0..5 Channels Studio (Phase 363)';
  Width := 1020;
  Height := 650;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TGameplayDebuggerForm.BuildUi;
var
  Lbl: TLabel;
  Row1, Row2, BodyPanel: TPanel;
  Ch: TGameplayDebugChannel;
  B: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String; const AOnClick: TNotifyEvent;
    const ATag: Integer = 0): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := alLeft;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 4;
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AOnClick;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ AGameplayDebugger — Per-Category Numpad 0..5 Channels (AI / Targeting / GAS / Mover2 / Traffic / GI)';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn 6-Subsystem Debug Sandbox', @BtnSpawnClick);
  MakeBtn(Row1, 'Enable All 0..5 Channels', @BtnAllOnClick);
  MakeBtn(Row1, 'Copy JSON Snapshot', @BtnCopyJsonClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  for Ch := Low(TGameplayDebugChannel) to High(TGameplayDebugChannel) do
  begin
    B := MakeBtn(Row2, 'Toggle ' + GameplayDebugChannelName(Ch), @BtnToggleChClick, Ord(Ch));
    B.ShowHint := True;
  end;

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintHud := TPaintBox.Create(Self);
  FPaintHud.Parent := BodyPanel;
  FPaintHud.Align := alLeft;
  FPaintHud.Width := 540;
  FPaintHud.OnPaint := @PaintHudOverlay;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TGameplayDebuggerForm.ActiveDebugger: TCastleGameplayDebugger;
begin
  Result := TGameplayDebuggerHelper.FindDebuggerInHierarchy(FDesignRoot);
end;

procedure TGameplayDebuggerForm.ReCollectAndNotify(const AComment: String);
var
  D: TCastleGameplayDebugger;
  Vp: TCastleViewport;
begin
  D := ActiveDebugger;
  Vp := TGameplayDebuggerHelper.FindViewport(FDesignRoot);
  if (D <> nil) and (Vp <> nil) then
    D.CollectSnapshotFromWorld(Vp.Items);
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TGameplayDebuggerForm.RefreshView;
begin
  FMemoReport.Lines.Text := TGameplayDebuggerHelper.GenerateDebuggerReport(ActiveDebugger);
  FPaintHud.Invalidate;
end;

procedure TGameplayDebuggerForm.BtnSpawnClick(Sender: TObject);
var
  D: TCastleGameplayDebugger;
  Hero: TCastleTransform;
begin
  if TGameplayDebuggerHelper.SpawnMultiSubsystemDebugSandbox(FDesignRoot, FDesignOwner, D, Hero) then
    ReCollectAndNotify('Spawn 6-Subsystem GameplayDebugger Sandbox');
end;

procedure TGameplayDebuggerForm.BtnToggleChClick(Sender: TObject);
var
  D: TCastleGameplayDebugger;
  Digit: Integer;
begin
  D := ActiveDebugger;
  if (D = nil) or (not (Sender is TComponent)) then Exit;
  Digit := TComponent(Sender).Tag;
  D.ToggleChannelByNumpadKey(Digit);
  ReCollectAndNotify(Format('Toggle GameplayDebugger Numpad %d Channel', [Digit]));
end;

procedure TGameplayDebuggerForm.BtnAllOnClick(Sender: TObject);
var
  D: TCastleGameplayDebugger;
begin
  D := ActiveDebugger;
  if D = nil then Exit;
  D.EnableAllChannels;
  ReCollectAndNotify('Enable All GameplayDebugger Channels');
end;

procedure TGameplayDebuggerForm.BtnCopyJsonClick(Sender: TObject);
var
  D: TCastleGameplayDebugger;
begin
  D := ActiveDebugger;
  if D <> nil then
    Clipboard.AsText := D.ExportDiagnosticSnapshotJson;
end;

procedure TGameplayDebuggerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TGameplayDebuggerHelper.GenerateDebuggerReport(ActiveDebugger);
end;

procedure TGameplayDebuggerForm.PaintHudOverlay(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y: Integer;
  D: TCastleGameplayDebugger;
  Ch: TGameplayDebugChannel;
begin
  Cv := FPaintHud.Canvas;
  W := FPaintHud.Width;
  H := FPaintHud.Height;
  Cv.Brush.Color := RGBToColor(14, 18, 24);
  Cv.FillRect(0, 0, W, H);

  D := ActiveDebugger;
  if D = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn 6-Subsystem Debug Sandbox" to inspect live AGameplayDebugger HUD.');
    Exit;
  end;

  Cv.Font.Color := RGBToColor(110, 230, 145);
  Cv.TextOut(14, 12, Format('AGameplayDebugger HUD | Actor: %s | Mask: %d', [
    D.ResolvedActorName, D.ChannelMask]));

  Y := 38;
  for Ch := Low(TGameplayDebugChannel) to High(TGameplayDebugChannel) do
  begin
    if D.IsChannelEnabled(Ch) then
      Cv.Font.Color := RGBToColor(255, 225, 95)
    else
      Cv.Font.Color := RGBToColor(95, 105, 118);
    Cv.TextOut(14, Y, Format('%s : %s', [
      GameplayDebugChannelName(Ch),
      BoolToStr(D.IsChannelEnabled(Ch), '[ACTIVE]', '[OFF]')]));
    Inc(Y, 20);
  end;

  Inc(Y, 12);
  Cv.Font.Color := clWhite;
  for I := 0 to D.HudLineCount - 1 do
  begin
    Cv.TextOut(14, Y, Copy(D.GetHudLine(I), 1, 74));
    Inc(Y, 22);
  end;
end;

end.

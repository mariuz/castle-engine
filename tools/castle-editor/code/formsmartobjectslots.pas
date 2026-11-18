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

{ Visual Studio dialog for Multi-Slot SmartObject Claiming, Queues & Cooldowns (Phase 368). }
unit FormSmartObjectSlots;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleSmartObjectSlots, ToolSmartObjectSlots;

type
  TSmartObjectSlotsModifiedCallback = procedure(const UndoComment: String) of object;
  TSmartObjectSlotsRefreshCallback = procedure of object;

  TSmartObjectSlotsForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSmartObjectSlotsModifiedCallback;
    FOnRefresh: TSmartObjectSlotsRefreshCallback;
    FNextPatronSeq: Integer;
    FPaintSlots: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveStation: TCastleMultiSlotSmartObject;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnTavernClick(Sender: TObject);
    procedure BtnForgeClick(Sender: TObject);
    procedure BtnBallistaClick(Sender: TObject);
    procedure BtnSendPatronClick(Sender: TObject);
    procedure BtnReleaseFirstClick(Sender: TObject);
    procedure BtnStepCooldownClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintSlotDiagram(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSmartObjectSlotsModifiedCallback;
      const AOnRefresh: TSmartObjectSlotsRefreshCallback);
  end;

implementation

constructor TSmartObjectSlotsForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSmartObjectSlotsModifiedCallback;
  const AOnRefresh: TSmartObjectSlotsRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FNextPatronSeq := 1;
  Caption := 'Multi-Slot SmartObject Claiming, FIFO Wait-Queue & Cooldown Studio (Phase 368)';
  Width := 1000;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TSmartObjectSlotsForm.BuildUi;
var
  Lbl: TLabel;
  Row1, Row2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String; const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := alLeft;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 4;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ USmartObjectDefinition — Multi-Slot Claim/Use/Release, Per-Slot Cooldowns, Role Tags & FIFO Wait-Queues';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn 4-Seat Tavern Smart Table', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Tavern 4-Seat', @BtnTavernClick);
  MakeBtn(Row1, 'Preset: Blacksmith Forge', @BtnForgeClick);
  MakeBtn(Row1, 'Preset: Siege Ballista', @BtnBallistaClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, '+ Send Next Agent (Claim or FIFO Queue!)', @BtnSendPatronClick);
  MakeBtn(Row2, 'Finish & Release 1st Occupied Slot (-> Cooldown)', @BtnReleaseFirstClick);
  MakeBtn(Row2, 'Step Cooldowns +2.5s (Auto-Promote FIFO!)', @BtnStepCooldownClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintSlots := TPaintBox.Create(Self);
  FPaintSlots.Parent := BodyPanel;
  FPaintSlots.Align := alLeft;
  FPaintSlots.Width := 480;
  FPaintSlots.OnPaint := @PaintSlotDiagram;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TSmartObjectSlotsForm.ActiveStation: TCastleMultiSlotSmartObject;
begin
  Result := TSmartObjectSlotsHelper.FindSmartObjectInHierarchy(FDesignRoot);
end;

procedure TSmartObjectSlotsForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSmartObjectSlotsForm.RefreshView;
begin
  FMemoReport.Lines.Text := TSmartObjectSlotsHelper.GenerateSmartSlotsReport(ActiveStation);
  FPaintSlots.Invalidate;
end;

procedure TSmartObjectSlotsForm.BtnSpawnClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
begin
  if TSmartObjectSlotsHelper.SpawnTavernSmartTableDemo(FDesignRoot, FDesignOwner, St) then
  begin
    FNextPatronSeq := 1;
    NotifyChange('Spawn 4-Seat Tavern SmartObject Table');
  end;
end;

procedure TSmartObjectSlotsForm.BtnTavernClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
begin
  St := ActiveStation;
  if St = nil then Exit;
  St.Preset := smspTavernFourSeatTable;
  FNextPatronSeq := 1;
  NotifyChange('Apply Tavern 4-Seat SmartObject Preset');
end;

procedure TSmartObjectSlotsForm.BtnForgeClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
begin
  St := ActiveStation;
  if St = nil then Exit;
  St.Preset := smspBlacksmithDualForgeAnvil;
  FNextPatronSeq := 1;
  NotifyChange('Apply Blacksmith Dual Forge SmartObject Preset');
end;

procedure TSmartObjectSlotsForm.BtnBallistaClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
begin
  St := ActiveStation;
  if St = nil then Exit;
  St.Preset := smspSiegeBallistaCrewPair;
  FNextPatronSeq := 1;
  NotifyChange('Apply Siege Ballista Crew SmartObject Preset');
end;

procedure TSmartObjectSlotsForm.BtnSendPatronClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
  SlotIdx: Integer;
  Reason, UserId: String;
begin
  St := ActiveStation;
  if St = nil then Exit;
  UserId := Format('Agent_%d', [FNextPatronSeq]);
  Inc(FNextPatronSeq);
  if St.RequestClaimOrEnqueue(UserId, 'Role.Blacksmith.Master,Role.Apprentice,Role.Artillery', SlotIdx, Reason) then
    St.BeginUsingClaimedSlot(UserId);
  NotifyChange('Dispatch ' + UserId + ' to Multi-Slot SmartObject');
end;

procedure TSmartObjectSlotsForm.BtnReleaseFirstClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
  I: Integer;
  S: TSmartObjectSlotEntry;
begin
  St := ActiveStation;
  if St = nil then Exit;
  for I := 0 to St.SlotCount - 1 do
  begin
    S := St.GetSlot(I);
    if S.ActiveUserId <> '' then
    begin
      St.ReleaseSlotAndStartCooldown(S.ActiveUserId);
      NotifyChange('Release Slot ' + S.SlotId + ' into Cooldown');
      Exit;
    end;
  end;
end;

procedure TSmartObjectSlotsForm.BtnStepCooldownClick(Sender: TObject);
var
  St: TCastleMultiSlotSmartObject;
begin
  St := ActiveStation;
  if St = nil then Exit;
  St.StepSlotsAndPromoteQueue(2.5);
  NotifyChange('Step SmartObject Cooldowns +2.5s');
end;

procedure TSmartObjectSlotsForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TSmartObjectSlotsHelper.GenerateSmartSlotsReport(ActiveStation);
end;

procedure TSmartObjectSlotsForm.PaintSlotDiagram(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, I, SX, SY: Integer;
  St: TCastleMultiSlotSmartObject;
  S: TSmartObjectSlotEntry;
begin
  Cv := FPaintSlots.Canvas;
  W := FPaintSlots.Width;
  H := FPaintSlots.Height;
  Cv.Brush.Color := RGBToColor(20, 22, 28);
  Cv.FillRect(0, 0, W, H);

  St := ActiveStation;
  if St = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn 4-Seat Tavern Smart Table" to inspect Multi-Slot States.');
    Exit;
  end;

  CX := W div 2;
  CY := H div 2;
  Cv.Brush.Color := RGBToColor(95, 68, 42);
  Cv.Rectangle(CX - 56, CY - 56, CX + 56, CY + 56);

  for I := 0 to St.SlotCount - 1 do
  begin
    S := St.GetSlot(I);
    SX := CX + Round(S.LocalOffset.X * 92);
    SY := CY + Round(S.LocalOffset.Z * 92);
    case S.State of
      sssFreeAvailable:   Cv.Brush.Color := RGBToColor(55, 215, 105);
      sssClaimedApproach: Cv.Brush.Color := RGBToColor(65, 195, 250);
      sssInUseActive:     Cv.Brush.Color := RGBToColor(250, 205, 55);
      sssCoolingDown:     Cv.Brush.Color := RGBToColor(245, 110, 45);
      sssDisabledLocked:  Cv.Brush.Color := RGBToColor(110, 110, 120);
    end;
    Cv.Ellipse(SX - 28, SY - 28, SX + 28, SY + 28);
    Cv.Brush.Style := bsClear;
    Cv.Font.Color := clWhite;
    Cv.TextOut(SX - 34, SY + 32, Format('%s (%s)', [S.SlotId, SmartSlotStateToString(S.State)]));
    Cv.Brush.Style := bsSolid;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(14, 12, Format('Slots: %d/%d Free | FIFO Wait-Queue: %d | Promotions: %d', [
    St.FreeSlotCount, St.SlotCount, St.WaitQueueCount, St.TotalPromotions]));
end;

end.

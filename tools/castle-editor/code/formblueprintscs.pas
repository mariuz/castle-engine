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

{ Unreal Engine 5.5-style Blueprint Components Viewport & Inherited Subobject
  Tree Studio featuring a Blueprint 3D Assembly Viewport (CapsuleCollider,
  Skeletal/Static Meshes, Red USpringArmComponent Boom, Camera Frustum &
  SpotLight Cone) and a Hierarchical USCS_Node + UInheritableComponentHandler
  Tree Inspector (Phase 395 — 115 UE Studios / 38 MCP). }
unit FormBlueprintScs;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleBlueprintScs, ToolBlueprintScs;

type
  TBpScsModifiedCallback = procedure(const UndoComment: String) of object;
  TBpScsRefreshCallback = procedure of object;

  TBlueprintScsForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBpScsModifiedCallback;
    FOnRefresh: TBpScsRefreshCallback;

    FActiveBp: TCastleBlueprintScsActor;

    FLblStatus: TLabel;
    FPaintViewport: TPaintBox;
    FPaintTree: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintBlueprintComponentsViewport(Sender: TObject);
    procedure PaintScsComponentTree(Sender: TObject);

    procedure BtnSpawnShowcaseClick(Sender: TObject);
    procedure BtnSpawnChestClick(Sender: TObject);
    procedure BtnInspectParentClick(Sender: TObject);
    procedure BtnInspectChildClick(Sender: TObject);
    procedure BtnExtendBoomClick(Sender: TObject);
    procedure BtnRevertOverridesClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBpScsModifiedCallback;
      const AOnRefresh: TBpScsRefreshCallback);
  end;

implementation

constructor TBlueprintScsForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBpScsModifiedCallback;
  const AOnRefresh: TBpScsRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Blueprint Components Viewport & Inherited Subobject Tree (USimpleConstructionScript — 115 UE Studios / 38 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveBp := TBlueprintScsHelper.FindFirstBlueprintScs(FDesignRoot);
  RefreshFromScene;
end;

procedure TBlueprintScsForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnSpawn, BtnChest, BtnParent, BtnChild, BtnBoom, BtnRevert, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'Blueprint Components Viewport & USimpleConstructionScript Ready.';

  XPos := 8;
  BtnSpawn := MakeToolbarBtn('+ Parent+Child BP', 156, @BtnSpawnShowcaseClick);
  BtnChest := MakeToolbarBtn('+ Chest BP', 112, @BtnSpawnChestClick);
  BtnParent := MakeToolbarBtn('Inspect Base Class', 152, @BtnInspectParentClick);
  BtnChild := MakeToolbarBtn('Inspect Child Paladin', 168, @BtnInspectChildClick);
  BtnBoom := MakeToolbarBtn('Override Boom 6.2m', 166, @BtnExtendBoomClick);
  BtnRevert := MakeToolbarBtn('Revert Overrides', 150, @BtnRevertOverridesClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 106, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 72, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnSpawn <> nil) and (BtnChest <> nil) and (BtnParent <> nil) and
     (BtnChild <> nil) and (BtnBoom <> nil) and (BtnRevert <> nil) and
     (BtnCopy <> nil) then ;

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
  PnlRight.Width := 612;
  PnlRight.BevelOuter := bvNone;

  FPaintTree := TPaintBox.Create(Self);
  FPaintTree.Parent := PnlRight;
  FPaintTree.Align := alClient;
  FPaintTree.OnPaint := @PaintScsComponentTree;

  FPaintViewport := TPaintBox.Create(Self);
  FPaintViewport.Parent := Self;
  FPaintViewport.Align := alClient;
  FPaintViewport.OnPaint := @PaintBlueprintComponentsViewport;
end;

procedure TBlueprintScsForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TBlueprintScsForm.RefreshFromScene;
var
  ParentName: String;
begin
  if FActiveBp = nil then
    FActiveBp := TBlueprintScsHelper.FindFirstBlueprintScs(FDesignRoot);

  if FActiveBp <> nil then
  begin
    if FActiveBp.ParentBlueprintScs <> nil then
      ParentName := FActiveBp.ParentBlueprintScs.BlueprintClassKey
    else
      ParentName := 'AActor (Native Root)';

    FLblStatus.Caption := Format(
      'Active Class: %s  |  Parent Class: %s  |  Assembled Subobjects: %d  |  Inherited: %d  |  Delta Overrides: %d',
      [FActiveBp.BlueprintClassKey, ParentName,
       Length(FActiveBp.Assembled),
       FActiveBp.InheritedComponentCount,
       FActiveBp.OverriddenInheritedCount]);
  end else
    FLblStatus.Caption := 'No TCastleBlueprintScsActor in scene — click "+ Parent+Child Characters" to inspect USCS_Node assembly.';

  FMemoReport.Lines.Text := TBlueprintScsHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveBp);

  FPaintViewport.Invalidate;
  FPaintTree.Invalidate;
end;

procedure TBlueprintScsForm.PaintBlueprintComponentsViewport(Sender: TObject);
var
  C: TCanvas;
  W, H, OriginX, GroundY, I, PX, PY, QX, QY, RX, RY: Integer;
  ScalePx: Single;
  Comp: TScsAssembledComponent;

  function MapX(const AX, AZ: Single): Integer;
  begin
    { Subtle 2.5D side-oblique projection so Z offsets (Sword_R vs Shield_L) separate cleanly! }
    Result := OriginX + Round((AX + AZ * 0.42) * ScalePx);
  end;

  function MapY(const AY, AZ: Single): Integer;
  begin
    Result := GroundY - Round((AY - AZ * 0.16) * ScalePx);
  end;

begin
  C := FPaintViewport.Canvas;
  W := Max(360, FPaintViewport.Width);
  H := Max(320, FPaintViewport.Height);

  C.Brush.Color := RGBToColor(19, 22, 29);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 206, 255);
  C.TextOut(12, 7, 'Blueprint 3D Components Viewport  (Capsule | Red SpringArm | Camera/Spot)');
  C.Font.Style := [];

  if FActiveBp = nil then Exit;

  ScalePx := Min((W - 140) / 8.8, (H - 120) / 4.6);
  OriginX := Round(W * 0.48);
  GroundY := H - 72;

  { Perspective floor grid }
  C.Pen.Color := RGBToColor(32, 37, 48);
  for I := -8 to 4 do
  begin
    PX := MapX(I * 0.75, -2.5);
    PY := MapY(0.0, -2.5);
    QX := MapX(I * 0.75, 2.5);
    QY := MapY(0.0, 2.5);
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
  end;
  for I := -3 to 3 do
  begin
    PX := MapX(-6.0, I * 0.8);
    PY := MapY(0.0, I * 0.8);
    QX := MapX(3.0, I * 0.8);
    QY := MapY(0.0, I * 0.8);
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
  end;

  { Actor Origin X/Y/Z Triad }
  PX := MapX(0, 0);
  PY := MapY(0, 0);
  C.Pen.Width := 2;
  C.Pen.Color := RGBToColor(238, 86, 86);
  C.MoveTo(PX, PY); C.LineTo(PX + 34, PY);
  C.Pen.Color := RGBToColor(86, 232, 128);
  C.MoveTo(PX, PY); C.LineTo(PX, PY - 34);
  C.Pen.Width := 1;

  { Render each assembled component in Actor Space }
  for I := 0 to High(FActiveBp.Assembled) do
  begin
    Comp := FActiveBp.Assembled[I];
    PX := MapX(Comp.ActorSpacePos.X, Comp.ActorSpacePos.Z);
    PY := MapY(Comp.ActorSpacePos.Y, Comp.ActorSpacePos.Z);

    case Comp.Kind of
      sckCapsuleCollider:
        begin
          RX := Max(16, Round(Comp.SecondaryParam * ScalePx));
          RY := Max(28, Round(Comp.PrimaryParam * 0.5 * ScalePx));
          C.Brush.Style := bsClear;
          C.Pen.Color := RGBToColor(255, 158, 64);
          C.Pen.Width := 2;
          C.RoundRect(PX - RX, PY - RY, PX + RX, PY + RY, RX * 2, RX * 2);
          C.Pen.Width := 1;
          C.Font.Color := RGBToColor(255, 192, 118);
          C.TextOut(PX + RX + 8, PY - RY + 4, Format('%s (H=%.2fm R=%.2fm)',
            [Comp.NodeName, Comp.PrimaryParam, Comp.SecondaryParam]));
        end;

      sckSkeletalMesh, sckStaticMesh:
        begin
          RX := Max(8, Round(Comp.LocalScale.X * 0.5 * ScalePx));
          RY := Max(12, Round(Comp.LocalScale.Y * 0.5 * ScalePx));
          C.Brush.Style := bsSolid;
          if Comp.Kind = sckSkeletalMesh then
          begin
            C.Brush.Color := RGBToColor(46, 88, 148);
            C.Pen.Color := RGBToColor(116, 182, 255);
          end else
          begin
            C.Brush.Color := RGBToColor(118, 94, 42);
            C.Pen.Color := RGBToColor(255, 214, 96);
          end;
          C.RoundRect(PX - RX, PY - RY, PX + RX, PY + RY, 6, 6);
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(226, 238, 255);
          if Comp.LocalPos.X < -0.1 then
            C.TextOut(PX - RX - C.TextWidth(Comp.NodeName) - 8, PY - 7, Comp.NodeName)
          else if Comp.Kind = sckSkeletalMesh then
            C.TextOut(PX + RX + 8, PY + 14, Comp.NodeName)
          else
            C.TextOut(PX + RX + 8, PY - 12, Comp.NodeName);
        end;

      sckSpringArm:
        begin
          QX := MapX(Comp.ActorSpaceTipPos.X, Comp.ActorSpaceTipPos.Z);
          QY := MapY(Comp.ActorSpaceTipPos.Y, Comp.ActorSpaceTipPos.Z);
          { Iconic UE Red USpringArmComponent line! }
          C.Pen.Color := RGBToColor(255, 76, 84);
          C.Pen.Width := 3;
          C.MoveTo(PX, PY);
          C.LineTo(QX, QY);
          C.Pen.Width := 1;
          C.Brush.Style := bsSolid;
          C.Brush.Color := RGBToColor(255, 96, 102);
          C.Ellipse(PX - 5, PY - 5, PX + 5, PY + 5);
          C.Brush.Style := bsClear;
          C.Font.Style := [fsBold];
          C.Font.Color := RGBToColor(255, 146, 152);
          C.TextOut((PX + QX) div 2 - 48, (PY + QY) div 2 - 20,
            Format('%s (Arm=%.1fm)', [Comp.NodeName, Comp.PrimaryParam]));
          C.Font.Style := [];
        end;

      sckFollowCamera:
        begin
          { Camera body + FOV frustum cone looking toward character }
          C.Brush.Style := bsSolid;
          C.Brush.Color := RGBToColor(238, 192, 54);
          C.Pen.Color := RGBToColor(255, 238, 158);
          C.RoundRect(PX - 12, PY - 9, PX + 12, PY + 9, 4, 4);
          C.Pen.Color := RGBToColor(112, 212, 255);
          C.MoveTo(PX + 12, PY);
          C.LineTo(PX + 68, PY - 26);
          C.MoveTo(PX + 12, PY);
          C.LineTo(PX + 68, PY + 26);
          C.LineTo(PX + 68, PY - 26);
          C.Brush.Style := bsClear;
          C.Font.Style := [fsBold];
          C.Font.Color := RGBToColor(255, 228, 118);
          C.TextOut(Max(8, PX - 10), PY - 26, Format('%s (FOV %.0f)',
            [Comp.NodeName, Comp.PrimaryParam]));
          C.Font.Style := [];
        end;

      sckSpotLight:
        begin
          QX := MapX(Comp.ActorSpaceTipPos.X, Comp.ActorSpaceTipPos.Z);
          QY := MapY(Comp.ActorSpaceTipPos.Y, Comp.ActorSpaceTipPos.Z);
          C.Pen.Color := RGBToColor(255, 234, 106);
          C.MoveTo(PX, PY);
          C.LineTo(QX - 26, QY);
          C.MoveTo(PX, PY);
          C.LineTo(QX + 26, QY);
          C.LineTo(QX - 26, QY);
          C.Brush.Style := bsSolid;
          C.Brush.Color := RGBToColor(255, 242, 132);
          C.Ellipse(PX - 6, PY - 6, PX + 6, PY + 6);
          C.Brush.Style := bsClear;
          C.Font.Color := RGBToColor(255, 238, 146);
          C.TextOut(PX + 10, PY - 10, Comp.NodeName);
        end;

      sckBoxTrigger:
        begin
          RX := Max(20, Round(Comp.LocalScale.X * 0.5 * ScalePx));
          RY := Max(16, Round(Comp.LocalScale.Y * 0.5 * ScalePx));
          C.Brush.Style := bsClear;
          C.Pen.Color := RGBToColor(92, 242, 152);
          C.Rectangle(PX - RX, PY - RY, PX + RX, PY + RY);
          C.Font.Color := RGBToColor(124, 246, 172);
          C.TextOut(PX - RX + 6, PY - RY - 16, Comp.NodeName);
        end;
    else
      ;
    end;
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(188, 206, 232);
  C.TextOut(14, H - 26,
    'Inherited USCS_Nodes: locked from deletion in Child BPs; support Child Attachments & Overrides.');
  C.Brush.Style := bsSolid;
end;

procedure TBlueprintScsForm.PaintScsComponentTree(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY, IndentPx: Integer;
  Comp: TScsAssembledComponent;
  Prefix, BadgeStr: String;
begin
  C := FPaintTree.Canvas;
  W := Max(360, FPaintTree.Width);
  H := Max(320, FPaintTree.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'USimpleConstructionScript Tree  ([Inherited] vs Local Child SCS)');
  C.Font.Style := [];

  if FActiveBp = nil then Exit;

  { Column Header }
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(0, 32, W, 56);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(14, 37, 'Subobject Hierarchy');
  C.TextOut(236, 37, 'Component Class');
  C.TextOut(432, 37, 'Provenance');
  C.Font.Style := [];

  for I := 0 to High(FActiveBp.Assembled) do
  begin
    Comp := FActiveBp.Assembled[I];
    RowY := 58 + I * 48;
    if RowY + 46 > H - 8 then Break;

    C.Brush.Style := bsSolid;
    if Comp.IsOverriddenInChild then
      C.Brush.Color := RGBToColor(34, 48, 68)
    else if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(8, RowY, W - 8, RowY + 45);

    IndentPx := 16 + Comp.TreeDepth * 20;
    if Comp.TreeDepth > 0 then
      Prefix := '+-- '
    else
      Prefix := '';

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    if Comp.IsInherited then
      C.Font.Color := RGBToColor(178, 216, 255)
    else
      C.Font.Color := RGBToColor(122, 246, 174);
    C.TextOut(IndentPx, RowY + 6, Prefix + Comp.NodeName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(196, 208, 228);
    C.TextOut(236, RowY + 6, ScsKindDisplayName(Comp.Kind));

    if Comp.IsInherited then
    begin
      if Comp.IsOverriddenInChild then
      begin
        BadgeStr := '[Inherited | Overridden]';
        C.Font.Color := RGBToColor(255, 208, 98);
      end else
      begin
        BadgeStr := '[Inherited]';
        C.Font.Color := RGBToColor(148, 178, 218);
      end;
    end else
    begin
      BadgeStr := '[Child SCS Node]';
      C.Font.Color := RGBToColor(112, 238, 164);
    end;
    C.TextOut(432, RowY + 6, BadgeStr);

    { Second detail line: ActorSpacePos + Primary/Secondary Archetype Parameters }
    C.Font.Color := RGBToColor(148, 162, 186);
    C.TextOut(IndentPx + 12, RowY + 25, Format(
      'Pos=(%.2f, %.2f, %.2f)  |  P1=%.2f  P2=%.2f  |  %s',
      [Comp.ActorSpacePos.X, Comp.ActorSpacePos.Y, Comp.ActorSpacePos.Z,
       Comp.PrimaryParam, Comp.SecondaryParam, Comp.SourceBlueprintName]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TBlueprintScsForm.BtnSpawnShowcaseClick(Sender: TObject);
var
  BaseBp, ChildBp: TCastleBlueprintScsActor;
begin
  TBlueprintScsHelper.SpawnParentAndChildBlueprintShowcaseInDesign(
    FDesignRoot, FDesignOwner, BaseBp, ChildBp);
  if ChildBp <> nil then
    FActiveBp := ChildBp
  else
    FActiveBp := BaseBp;
  NotifyChanged('Spawn Parent+Child Blueprint SCS Character Hierarchy');
end;

procedure TBlueprintScsForm.BtnSpawnChestClick(Sender: TObject);
begin
  FActiveBp := TBlueprintScsHelper.SpawnBlueprintScsPresetInDesign(
    FDesignRoot, FDesignOwner, bspModularInteractableChestBp, Vector3(0, 0, -4));
  NotifyChanged('Spawn Modular Treasure Chest Blueprint SCS');
end;

procedure TBlueprintScsForm.BtnInspectParentClick(Sender: TObject);
begin
  if (FActiveBp <> nil) and (FActiveBp.ParentBlueprintScs <> nil) then
  begin
    FActiveBp := FActiveBp.ParentBlueprintScs;
    RefreshFromScene;
  end;
end;

procedure TBlueprintScsForm.BtnInspectChildClick(Sender: TObject);
var
  L: TList;
  I: Integer;
begin
  L := TList.Create;
  try
    TBlueprintScsHelper.CollectBlueprintScsActors(FDesignRoot, L);
    for I := 0 to L.Count - 1 do
      if TCastleBlueprintScsActor(L[I]).ParentBlueprintScs <> nil then
      begin
        FActiveBp := TCastleBlueprintScsActor(L[I]);
        Break;
      end;
  finally
    FreeAndNil(L);
  end;
  RefreshFromScene;
end;

procedure TBlueprintScsForm.BtnExtendBoomClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  if FActiveBp.OverrideInheritedParams('CameraBoom', 6.20, 24.0) then
    NotifyChanged('Override Inherited CameraBoom TargetArmLength = 6.20m');
end;

procedure TBlueprintScsForm.BtnRevertOverridesClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.RevertAllInheritedOverrides;
  NotifyChanged('Revert All Inherited Subobject Overrides to Parent Blueprint');
end;

procedure TBlueprintScsForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Blueprint Components & SCS Report to Clipboard.';
end;

end.

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

{ Interactive Gameplay Ability, Cooldown, Status Buff/Debuff & Attribute System
  (GAS) Studio (@link(TAbilityStudioForm)) featuring 1-click RPG combat actor
  spawners, live attribute Base->Current bar gauges, ability casting against
  targets, stacking DoT/HoT & Tag Immunity simulation, and Markdown export
  (Phase 310). }
unit FormAbilityStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleUtils,
  CastleGameplayAbility, ToolAbilityStudio;

type
  TAbilityStudioModifiedCallback = procedure(const AComment: String) of object;
  TAbilityStudioRefreshViewportCallback = procedure of object;

  TAbilityStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSelectedTransform: TCastleTransform;
    FSpawnPos: TVector3;
    FOnModified: TAbilityStudioModifiedCallback;
    FOnRefreshViewport: TAbilityStudioRefreshViewportCallback;

    FReport: TAbilityStudioAuditReport;
    FLastCombatStatus: String;

    LblHeader: TLabel;
    ListSystems: TListBox;
    ComboTarget: TComboBox;
    ListAbilities: TListBox;
    ListEffects: TListBox;
    PaintHud: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentSystem: TCastleAbilitySystemBehavior;
    function TargetSystem: TCastleAbilitySystemBehavior;
    procedure RefreshAll;
    procedure RefreshSubLists;
    procedure NotifyChanged(const AComment: String);

    procedure ListSystemsClick(Sender: TObject);
    procedure BtnSpawnMageClick(Sender: TObject);
    procedure BtnSpawnPaladinClick(Sender: TObject);
    procedure BtnSpawnRangerClick(Sender: TObject);
    procedure BtnAttachSelectedClick(Sender: TObject);
    procedure BtnCastAbilityClick(Sender: TObject);
    procedure BtnApplyEffectClick(Sender: TObject);
    procedure BtnStepSimClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintHudPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const ASelectedTransform: TCastleTransform;
      const ASpawnPos: TVector3;
      const AOnModified: TAbilityStudioModifiedCallback;
      const AOnRefreshViewport: TAbilityStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TAbilityStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const ASelectedTransform: TCastleTransform;
  const ASpawnPos: TVector3;
  const AOnModified: TAbilityStudioModifiedCallback;
  const AOnRefreshViewport: TAbilityStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSelectedTransform := ASelectedTransform;
  FSpawnPos := ASpawnPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FLastCombatStatus := 'Ready.';

  Caption := 'Gameplay Ability, Cooldown, Status Buff/Debuff & Attribute System (GAS) Studio';
  Width := 1100;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TAbilityStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TAbilityStudioForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

var
  BtnClose: TButton;
begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Gameplay Ability System (GAS) Studio';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1080, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Spawn Arcane Mage', 4, 4, 168, @BtnSpawnMageClick);
  MakeBtn(RowTop, '+ Spawn Vanguard Paladin', 178, 4, 184, @BtnSpawnPaladinClick);
  MakeBtn(RowTop, '+ Spawn Shadow Ranger', 368, 4, 174, @BtnSpawnRangerClick);
  MakeBtn(RowTop, 'Attach GAS to Selected', 548, 4, 174, @BtnAttachSelectedClick);
  MakeBtn(RowTop, 'Step Combat (+0.5s)', 728, 4, 162, @BtnStepSimClick);
  MakeBtn(RowTop, 'Reset CDs & Effects', 896, 4, 162, @BtnResetClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 970, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 320;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 280, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Caster GAS Actors:';

  ListSystems := TListBox.Create(Self);
  ListSystems.Parent := PanelLeft;
  ListSystems.SetBounds(10, 26, 300, 128);
  ListSystems.OnClick := @ListSystemsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 160, 280, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Target GAS Actor (for Cast):';

  ComboTarget := TComboBox.Create(Self);
  ComboTarget.Parent := PanelLeft;
  ComboTarget.Style := csDropDownList;
  ComboTarget.SetBounds(10, 180, 300, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 212, 280, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Declared Abilities:';

  ListAbilities := TListBox.Create(Self);
  ListAbilities.Parent := PanelLeft;
  ListAbilities.SetBounds(10, 232, 300, 126);

  MakeBtn(PanelLeft, 'Cast Selected Ability -> Target', 10, 364, 300, @BtnCastAbilityClick);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 400, 280, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Declared Status Effects (Buff / Debuff):';

  ListEffects := TListBox.Create(Self);
  ListEffects.Parent := PanelLeft;
  ListEffects.SetBounds(10, 420, 300, 118);

  MakeBtn(PanelLeft, 'Apply Selected Effect on Caster', 10, 544, 300, @BtnApplyEffectClick);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintHud := TPaintBox.Create(Self);
  PaintHud.Parent := PanelCenter;
  PaintHud.Align := alTop;
  PaintHud.Height := 360;
  PaintHud.OnPaint := @PaintHudPaint;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TAbilityStudioForm.CurrentSystem: TCastleAbilitySystemBehavior;
var
  Idx: Integer;
begin
  Result := nil;
  if (FReport = nil) or (Length(FReport.Systems) = 0) then
    Exit;
  Idx := ListSystems.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Systems)) then
    Result := FReport.Systems[Idx];
end;

function TAbilityStudioForm.TargetSystem: TCastleAbilitySystemBehavior;
var
  Idx: Integer;
begin
  Result := CurrentSystem;
  if (FReport = nil) or (Length(FReport.Systems) = 0) then
    Exit;
  Idx := ComboTarget.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Systems)) then
    Result := FReport.Systems[Idx];
end;

procedure TAbilityStudioForm.RefreshAll;
var
  PrevCaster, PrevTarget, Sys: TCastleAbilitySystemBehavior;
  I, CasterIdx, TargetIdx: Integer;
  ActorTitle: String;
begin
  PrevCaster := CurrentSystem;
  PrevTarget := TargetSystem;
  if (PrevCaster = nil) and (FSelectedTransform <> nil) then
    PrevCaster := FSelectedTransform.FindBehavior(TCastleAbilitySystemBehavior) as TCastleAbilitySystemBehavior;

  FreeAndNil(FReport);
  FReport := TAbilityStudioHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListSystems.Items.BeginUpdate;
  ComboTarget.Items.BeginUpdate;
  try
    ListSystems.Items.Clear;
    ComboTarget.Items.Clear;
    CasterIdx := 0;
    TargetIdx := 0;
    for I := 0 to High(FReport.Systems) do
    begin
      Sys := FReport.Systems[I];
      if Sys.Parent <> nil then
        ActorTitle := Sys.Parent.Name
      else
        ActorTitle := Sys.Name;
      ListSystems.Items.Add(Format('%s %s', [ActorTitle, Sys.GasSummaryBadge]));
      ComboTarget.Items.Add(ActorTitle);
      if Sys = PrevCaster then
        CasterIdx := I;
      if Sys = PrevTarget then
        TargetIdx := I;
    end;
    if ListSystems.Items.Count > 0 then
    begin
      ListSystems.ItemIndex := CasterIdx;
      if (PrevTarget = nil) and (ComboTarget.Items.Count > 1) then
        ComboTarget.ItemIndex := 1
      else
        ComboTarget.ItemIndex := TargetIdx;
    end;
  finally
    ComboTarget.Items.EndUpdate;
    ListSystems.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'GAS Studio — %d Actor(s) | %d Attributes | %d Abilities | %d Active Buffs/Debuffs | %s',
    [Length(FReport.Systems), FReport.TotalAttributes, FReport.TotalAbilities,
     FReport.TotalActiveEffects, FLastCombatStatus]);

  RefreshSubLists;
  MemoDiag.Lines.Text := TAbilityStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintHud.Invalidate;
end;

procedure TAbilityStudioForm.RefreshSubLists;
var
  Sys: TCastleAbilitySystemBehavior;
  I, PrevAb, PrevEf: Integer;
  Ab: TGasAbilityDef;
  Ef: TGasEffectDef;
  Reason: String;
begin
  PrevAb := ListAbilities.ItemIndex;
  PrevEf := ListEffects.ItemIndex;
  ListAbilities.Items.BeginUpdate;
  ListEffects.Items.BeginUpdate;
  try
    ListAbilities.Items.Clear;
    ListEffects.Items.Clear;
    Sys := CurrentSystem;
    if Sys <> nil then
    begin
      for I := 0 to Sys.Abilities.Count - 1 do
      begin
        Ab := Sys.Abilities[I];
        Sys.CanActivateAbility(Ab.AbilityId, Reason);
        ListAbilities.Items.Add(Format('%s (%.0f %s, CD %.1f/%.1fs) [%s]',
          [Ab.AbilityId, Ab.CostAmount, Ab.CostAttrName,
           Ab.RemainingCooldownSec, Ab.CooldownSec, Reason]));
      end;
      if ListAbilities.Items.Count > 0 then
        ListAbilities.ItemIndex := Clamped(Max(0, PrevAb), 0, ListAbilities.Items.Count - 1);

      for I := 0 to Sys.EffectDefs.Count - 1 do
      begin
        Ef := Sys.EffectDefs[I];
        ListEffects.Items.Add(Format('%s [%s] (%.1fs, max %dx)',
          [Ef.EffectId, Ef.EffectTag, Ef.DurationSec, Ef.MaxStacks]));
      end;
      if ListEffects.Items.Count > 0 then
        ListEffects.ItemIndex := Clamped(Max(0, PrevEf), 0, ListEffects.Items.Count - 1);
    end;
  finally
    ListEffects.Items.EndUpdate;
    ListAbilities.Items.EndUpdate;
  end;
end;

procedure TAbilityStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TAbilityStudioForm.ListSystemsClick(Sender: TObject);
begin
  RefreshSubLists;
  PaintHud.Invalidate;
end;

procedure TAbilityStudioForm.BtnSpawnMageClick(Sender: TObject);
var
  Sys: TCastleAbilitySystemBehavior;
begin
  Sys := TAbilityStudioHelper.SpawnCombatActorWithGas(
    FDesignRoot, FDesignOwner, 'ArcaneMage', gapArcaneMage, FSpawnPos);
  if (Sys <> nil) and (Sys.Parent <> nil) then
    FSelectedTransform := Sys.Parent;
  FLastCombatStatus := 'Spawned Arcane Mage.';
  NotifyChanged('Spawn GAS Arcane Mage Actor');
end;

procedure TAbilityStudioForm.BtnSpawnPaladinClick(Sender: TObject);
var
  Sys: TCastleAbilitySystemBehavior;
begin
  Sys := TAbilityStudioHelper.SpawnCombatActorWithGas(
    FDesignRoot, FDesignOwner, 'VanguardPaladin', gapVanguardPaladin,
    FSpawnPos + Vector3(2.4, 0.0, 0.0));
  if (Sys <> nil) and (Sys.Parent <> nil) then
    FSelectedTransform := Sys.Parent;
  FLastCombatStatus := 'Spawned Vanguard Paladin.';
  NotifyChanged('Spawn GAS Vanguard Paladin Actor');
end;

procedure TAbilityStudioForm.BtnSpawnRangerClick(Sender: TObject);
var
  Sys: TCastleAbilitySystemBehavior;
begin
  Sys := TAbilityStudioHelper.SpawnCombatActorWithGas(
    FDesignRoot, FDesignOwner, 'ShadowRanger', gapShadowRanger,
    FSpawnPos + Vector3(-2.4, 0.0, 0.0));
  if (Sys <> nil) and (Sys.Parent <> nil) then
    FSelectedTransform := Sys.Parent;
  FLastCombatStatus := 'Spawned Shadow Ranger.';
  NotifyChanged('Spawn GAS Shadow Ranger Actor');
end;

procedure TAbilityStudioForm.BtnAttachSelectedClick(Sender: TObject);
begin
  if FSelectedTransform = nil then
    Exit;
  TAbilityStudioHelper.AttachGasToTransform(FSelectedTransform, FDesignOwner, gapArcaneMage);
  FLastCombatStatus := 'Attached GAS to ' + FSelectedTransform.Name;
  NotifyChanged('Attach Gameplay Ability System Behavior');
end;

procedure TAbilityStudioForm.BtnCastAbilityClick(Sender: TObject);
var
  Sys, Tgt: TCastleAbilitySystemBehavior;
  Idx: Integer;
  AbId, Reason: String;
begin
  Sys := CurrentSystem;
  Tgt := TargetSystem;
  Idx := ListAbilities.ItemIndex;
  if (Sys = nil) or (Idx < 0) or (Idx >= Sys.Abilities.Count) then
    Exit;
  AbId := Sys.Abilities[Idx].AbilityId;
  Sys.TryActivateAbility(AbId, Tgt, Reason);
  FLastCombatStatus := Format('Cast %s -> %s', [AbId, Reason]);
  NotifyChanged('Cast GAS Ability ' + AbId);
end;

procedure TAbilityStudioForm.BtnApplyEffectClick(Sender: TObject);
var
  Sys: TCastleAbilitySystemBehavior;
  Idx: Integer;
  EfId, Reason: String;
begin
  Sys := CurrentSystem;
  Idx := ListEffects.ItemIndex;
  if (Sys = nil) or (Idx < 0) or (Idx >= Sys.EffectDefs.Count) then
    Exit;
  EfId := Sys.EffectDefs[Idx].EffectId;
  Sys.ApplyEffectById(EfId, Reason);
  FLastCombatStatus := Format('Effect %s -> %s', [EfId, Reason]);
  NotifyChanged('Apply GAS Effect ' + EfId);
end;

procedure TAbilityStudioForm.BtnStepSimClick(Sender: TObject);
begin
  TAbilityStudioHelper.StepAllGasSystems(FDesignRoot, FDesignOwner, 0.5);
  FLastCombatStatus := 'Stepped all GAS actors +0.5s.';
  NotifyChanged('Step GAS Simulation +0.5s');
end;

procedure TAbilityStudioForm.BtnResetClick(Sender: TObject);
var
  I: Integer;
begin
  if FReport <> nil then
    for I := 0 to High(FReport.Systems) do
    begin
      FReport.Systems[I].ResetAllCooldowns;
      FReport.Systems[I].ClearActiveEffects;
    end;
  FLastCombatStatus := 'Cleared cooldowns & active status effects.';
  NotifyChanged('Reset GAS Cooldowns & Effects');
end;

procedure TAbilityStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TAbilityStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TAbilityStudioForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAbilityStudioForm.PaintHudPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, I, BarW, FillW, Y: Integer;
  Sys: TCastleAbilitySystemBehavior;
  At: TGasAttributeDef;
  Act: TGasActiveEffect;
  CurV, CapV, Ratio: Single;
begin
  C := PaintHud.Canvas;
  W := PaintHud.Width;
  H := PaintHud.Height;

  C.Brush.Color := RGBToColor(22, 26, 34);
  C.FillRect(0, 0, W, H);

  Sys := CurrentSystem;
  C.Font.Color := RGBToColor(222, 232, 245);
  C.Brush.Style := bsClear;
  if Sys = nil then
  begin
    C.TextOut(16, H div 2 - 10, 'Click "+ Spawn Arcane Mage" above to inspect live GAS Attributes & Status Effects.');
    Exit;
  end;

  C.TextOut(14, 10, Format('Live GAS Attribute Gauges & Active Status Stack (%s)', [Sys.GasSummaryBadge]));
  Y := 38;
  BarW := Max(120, W - 260);
  for I := 0 to Min(7, Sys.Attributes.Count - 1) do
  begin
    At := Sys.Attributes[I];
    CurV := Sys.GetCurrentValue(At.AttrName);
    if (At.MaxAttrName <> '') and Sys.HasAttribute(At.MaxAttrName) then
      CapV := Max(1.0, Sys.GetCurrentValue(At.MaxAttrName))
    else
      CapV := Max(1.0, Max(At.BaseValue * 1.5, CurV));
    Ratio := Clamped(CurV / CapV, 0.0, 1.0);
    FillW := Round(BarW * Ratio);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(42, 48, 58);
    C.FillRect(160, Y, 160 + BarW, Y + 20);

    if SameText(At.AttrName, 'Health') then
      C.Brush.Color := RGBToColor(68, 206, 128)
    else if SameText(At.AttrName, 'Mana') then
      C.Brush.Color := RGBToColor(72, 152, 246)
    else
      C.Brush.Color := RGBToColor(232, 178, 72);
    C.FillRect(160, Y, 160 + FillW, Y + 20);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(228, 236, 246);
    C.TextOut(14, Y + 2, At.AttrName);
    C.TextOut(168, Y + 2, Format('Curr: %.1f  (Base: %.1f)', [CurV, At.BaseValue]));
    Inc(Y, 28);
  end;

  Inc(Y, 8);
  C.Font.Color := RGBToColor(168, 214, 250);
  C.TextOut(14, Y, Format('Active Buffs / Debuffs (%d):', [Sys.ActiveEffects.Count]));
  Inc(Y, 22);
  for I := 0 to Min(4, Sys.ActiveEffects.Count - 1) do
  begin
    Act := Sys.ActiveEffects[I];
    if Pos('Debuff', Act.Def.EffectTag) > 0 then
      C.Brush.Color := RGBToColor(138, 48, 52)
    else
      C.Brush.Color := RGBToColor(38, 98, 78);
    C.Brush.Style := bsSolid;
    C.FillRect(14, Y, W - 20, Y + 22);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(242, 246, 250);
    C.TextOut(22, Y + 3, Format('[%dx] %s  (%s)  —  %.1fs remaining',
      [Act.CurrentStacks, Act.Def.EffectId, Act.Def.EffectTag, Act.RemainingSec]));
    Inc(Y, 26);
  end;
end;

end.

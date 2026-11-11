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

{ Interactive 5-Bus Spatial Audio Soundscape Mixer, Sidechain Voice Ducking &
  Reverb/Attenuation Zone Studio (@link(TAudioMixerForm))
  (Phase 291 — UE 5.9 / 6.0 MetaSounds & Submix Bus Parity). }
unit FormAudioMixer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleViewport, CastleAudioMixer, ToolAudioMixer;

type
  TAudioStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TAudioStudioRefreshViewportCallback = procedure of object;

  TAudioMixerForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TAudioStudioModifiedCallback;
    FOnRefreshViewport: TAudioStudioRefreshViewportCallback;

    FSummary: TAudioMixerSummary;
    FLiveTimer: TTimer;
    FUpdatingUi: Boolean;

    { Top toolbar }
    ButtonEnsureMixer: TButton;
    ButtonSpawnZone: TButton;
    ButtonRouteSelected: TButton;
    ComboRouteBus: TComboBox;
    ButtonLiveEval: TButton;
    ButtonCopyMarkdown: TButton;

    { 5-Bus Fader Console }
    TrackFaders: array [TCastleAudioBusKind] of TTrackBar;
    LabelDb: array [TCastleAudioBusKind] of TLabel;
    CheckMute: array [TCastleAudioBusKind] of TCheckBox;
    CheckSolo: array [TCastleAudioBusKind] of TCheckBox;
    PaintBoxMeters: TPaintBox;

    { Right Sidechain & Spatial Zone Inspector }
    CheckDuckVoice: TCheckBox;
    CheckVoiceActiveTest: TCheckBox;
    SpinDuckFactor: TFloatSpinEdit;
    ButtonPresetBalanced: TButton;
    ButtonPresetDialogue: TButton;
    ButtonPresetCombat: TButton;
    ButtonPresetExplore: TButton;

    ComboZone: TComboBox;
    ComboZonePreset: TComboBox;
    SpinInnerRadius: TFloatSpinEdit;
    SpinOuterRadius: TFloatSpinEdit;
    SpinZoneAmbientMult: TFloatSpinEdit;
    SpinZoneMusicMult: TFloatSpinEdit;
    ButtonApplyZone: TButton;
    ListRouters: TListBox;
    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function CurrentListenerPos: TVector3;
    function ActiveMixer: TCastleAudioBusMixer;
    function ActiveZone: TCastleAudioZone;
    procedure RefreshAll;
    procedure LoadMixerControls;
    procedure LoadZoneControls;
    procedure NotifyModified(const Comment: String);
    procedure NotifyViewportRefresh;

    procedure ButtonEnsureMixerClick(Sender: TObject);
    procedure ButtonSpawnZoneClick(Sender: TObject);
    procedure ButtonRouteSelectedClick(Sender: TObject);
    procedure ButtonLiveEvalClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure FaderChange(Sender: TObject);
    procedure MuteOrSoloChange(Sender: TObject);
    procedure DuckSettingsChange(Sender: TObject);
    procedure MixPresetButtonClick(Sender: TObject);
    procedure ComboZoneChange(Sender: TObject);
    procedure ButtonApplyZoneClick(Sender: TObject);
    procedure PaintBoxMetersPaint(Sender: TObject);
    procedure LiveTimerTick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TAudioStudioModifiedCallback;
      const AOnRefreshViewport: TAudioStudioRefreshViewportCallback);
  end;

implementation

function FindViewportCameraWorldPos(const ARoot: TComponent): TVector3;
var
  I: Integer;
  VP: TCastleViewport;
  CamP, CamD, CamU: TVector3;
begin
  Result := TVector3.Zero;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
  begin
    VP := TCastleViewport(ARoot);
    if VP.Camera <> nil then
    begin
      VP.Camera.GetWorldView(CamP, CamD, CamU);
      Exit(CamP);
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
    begin
      VP := TCastleViewport(ARoot.Components[I]);
      if VP.Camera <> nil then
      begin
        VP.Camera.GetWorldView(CamP, CamD, CamU);
        Exit(CamP);
      end;
    end;
end;

constructor TAudioMixerForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TAudioStudioModifiedCallback;
  const AOnRefreshViewport: TAudioStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  FLiveTimer := TTimer.Create(Self);
  FLiveTimer.Enabled := false;
  FLiveTimer.Interval := 33;
  FLiveTimer.OnTimer := @LiveTimerTick;

  BuildUi;
  RefreshAll;
end;

procedure TAudioMixerForm.BuildUi;
var
  PanelTop, PanelBottom, PanelCenter, PanelFaders, PanelStrip, PanelRight: TPanel;
  GrpDuck, GrpPresets, GrpZones: TGroupBox;
  Lbl: TLabel;
  Bus: TCastleAudioBusKind;
  Pr: TCastleAudioAcousticPreset;
begin
  Caption := 'Spatial Audio Soundscape Mixer, Buses & Reverb Zones (UE 5.9 / 6.0 MetaSounds Parity)';
  Width := 1040;
  Height := 660;
  Position := poMainFormCenter;
  Constraints.MinWidth := 880;
  Constraints.MinHeight := 540;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 46;
  PanelTop.BevelOuter := bvNone;

  ButtonEnsureMixer := TButton.Create(Self);
  ButtonEnsureMixer.Parent := PanelTop;
  ButtonEnsureMixer.Left := 10;
  ButtonEnsureMixer.Top := 8;
  ButtonEnsureMixer.Width := 142;
  ButtonEnsureMixer.Height := 30;
  ButtonEnsureMixer.Caption := '+ Ensure Bus Mixer';
  ButtonEnsureMixer.OnClick := @ButtonEnsureMixerClick;

  ButtonSpawnZone := TButton.Create(Self);
  ButtonSpawnZone.Parent := PanelTop;
  ButtonSpawnZone.Left := 158;
  ButtonSpawnZone.Top := 8;
  ButtonSpawnZone.Width := 142;
  ButtonSpawnZone.Height := 30;
  ButtonSpawnZone.Caption := '+ Spawn Audio Zone';
  ButtonSpawnZone.OnClick := @ButtonSpawnZoneClick;

  ComboRouteBus := TComboBox.Create(Self);
  ComboRouteBus.Parent := PanelTop;
  ComboRouteBus.Left := 308;
  ComboRouteBus.Top := 10;
  ComboRouteBus.Width := 96;
  ComboRouteBus.Style := csDropDownList;
  for Bus := abkMusic to abkAmbient do
    ComboRouteBus.Items.Add(AudioBusKindToDisplayName(Bus));
  ComboRouteBus.ItemIndex := 1; { SFX }

  ButtonRouteSelected := TButton.Create(Self);
  ButtonRouteSelected.Parent := PanelTop;
  ButtonRouteSelected.Left := 408;
  ButtonRouteSelected.Top := 8;
  ButtonRouteSelected.Width := 162;
  ButtonRouteSelected.Height := 30;
  ButtonRouteSelected.Caption := '+ Route Transform to Bus';
  ButtonRouteSelected.OnClick := @ButtonRouteSelectedClick;

  ButtonLiveEval := TButton.Create(Self);
  ButtonLiveEval.Parent := PanelTop;
  ButtonLiveEval.Left := 578;
  ButtonLiveEval.Top := 8;
  ButtonLiveEval.Width := 162;
  ButtonLiveEval.Height := 30;
  ButtonLiveEval.Caption := 'Start Live Camera Eval';
  ButtonLiveEval.OnClick := @ButtonLiveEvalClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.Left := 748;
  ButtonCopyMarkdown.Top := 8;
  ButtonCopyMarkdown.Width := 158;
  ButtonCopyMarkdown.Height := 30;
  ButtonCopyMarkdown.Caption := 'Copy Markdown Report';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  { Bottom status & close }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.Left := 12;
  LabelStatus.Top := 12;
  LabelStatus.Caption := 'Ready.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.BorderSpacing.Around := 6;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  { Right Inspector }
  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alRight;
  PanelRight.Width := 350;
  PanelRight.BorderSpacing.Around := 6;
  PanelRight.BevelOuter := bvLowered;

  GrpPresets := TGroupBox.Create(Self);
  GrpPresets.Parent := PanelRight;
  GrpPresets.Align := alTop;
  GrpPresets.Height := 84;
  GrpPresets.Caption := '1-Click Soundscape Mix Presets';

  ButtonPresetBalanced := TButton.Create(Self);
  ButtonPresetBalanced.Parent := GrpPresets;
  ButtonPresetBalanced.SetBounds(8, 6, 156, 26);
  ButtonPresetBalanced.Caption := 'Balanced Gameplay';
  ButtonPresetBalanced.Tag := 0;
  ButtonPresetBalanced.OnClick := @MixPresetButtonClick;

  ButtonPresetDialogue := TButton.Create(Self);
  ButtonPresetDialogue.Parent := GrpPresets;
  ButtonPresetDialogue.SetBounds(172, 6, 156, 26);
  ButtonPresetDialogue.Caption := 'Dialogue Cutscene';
  ButtonPresetDialogue.Tag := 1;
  ButtonPresetDialogue.OnClick := @MixPresetButtonClick;

  ButtonPresetCombat := TButton.Create(Self);
  ButtonPresetCombat.Parent := GrpPresets;
  ButtonPresetCombat.SetBounds(8, 36, 156, 26);
  ButtonPresetCombat.Caption := 'Combat Action';
  ButtonPresetCombat.Tag := 2;
  ButtonPresetCombat.OnClick := @MixPresetButtonClick;

  ButtonPresetExplore := TButton.Create(Self);
  ButtonPresetExplore.Parent := GrpPresets;
  ButtonPresetExplore.SetBounds(172, 36, 156, 26);
  ButtonPresetExplore.Caption := 'Exploration Ambient';
  ButtonPresetExplore.Tag := 3;
  ButtonPresetExplore.OnClick := @MixPresetButtonClick;

  GrpDuck := TGroupBox.Create(Self);
  GrpDuck.Parent := PanelRight;
  GrpDuck.Align := alTop;
  GrpDuck.Height := 102;
  GrpDuck.Caption := 'Sidechain Voice -> Music Ducking';

  CheckDuckVoice := TCheckBox.Create(Self);
  CheckDuckVoice.Parent := GrpDuck;
  CheckDuckVoice.SetBounds(10, 6, 220, 22);
  CheckDuckVoice.Caption := 'Auto-Duck Music on Voice';
  CheckDuckVoice.OnChange := @DuckSettingsChange;

  CheckVoiceActiveTest := TCheckBox.Create(Self);
  CheckVoiceActiveTest.Parent := GrpDuck;
  CheckVoiceActiveTest.SetBounds(10, 30, 240, 22);
  CheckVoiceActiveTest.Caption := 'Simulate Voice Line Active';
  CheckVoiceActiveTest.OnChange := @DuckSettingsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GrpDuck;
  Lbl.SetBounds(10, 58, 120, 18);
  Lbl.Caption := 'Duck Gain Factor:';

  SpinDuckFactor := TFloatSpinEdit.Create(Self);
  SpinDuckFactor.Parent := GrpDuck;
  SpinDuckFactor.SetBounds(140, 54, 96, 24);
  SpinDuckFactor.MinValue := 0.0;
  SpinDuckFactor.MaxValue := 1.0;
  SpinDuckFactor.Increment := 0.05;
  SpinDuckFactor.DecimalPlaces := 2;
  SpinDuckFactor.OnChange := @DuckSettingsChange;

  GrpZones := TGroupBox.Create(Self);
  GrpZones.Parent := PanelRight;
  GrpZones.Align := alClient;
  GrpZones.Caption := 'Spatial Reverb / Attenuation Zones & Routers';

  ComboZone := TComboBox.Create(Self);
  ComboZone.Parent := GrpZones;
  ComboZone.SetBounds(10, 8, 318, 26);
  ComboZone.Style := csDropDownList;
  ComboZone.OnChange := @ComboZoneChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GrpZones;
  Lbl.SetBounds(10, 42, 95, 18);
  Lbl.Caption := 'Acoustic Preset:';

  ComboZonePreset := TComboBox.Create(Self);
  ComboZonePreset.Parent := GrpZones;
  ComboZonePreset.SetBounds(112, 38, 216, 26);
  ComboZonePreset.Style := csDropDownList;
  for Pr := Low(TCastleAudioAcousticPreset) to High(TCastleAudioAcousticPreset) do
    ComboZonePreset.Items.Add(AudioAcousticPresetToDisplayName(Pr));

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GrpZones;
  Lbl.SetBounds(10, 72, 110, 18);
  Lbl.Caption := 'Inner / Outer (m):';

  SpinInnerRadius := TFloatSpinEdit.Create(Self);
  SpinInnerRadius.Parent := GrpZones;
  SpinInnerRadius.SetBounds(128, 68, 92, 24);
  SpinInnerRadius.MinValue := 0.0;
  SpinInnerRadius.MaxValue := 5000.0;
  SpinInnerRadius.Increment := 1.0;
  SpinInnerRadius.DecimalPlaces := 1;

  SpinOuterRadius := TFloatSpinEdit.Create(Self);
  SpinOuterRadius.Parent := GrpZones;
  SpinOuterRadius.SetBounds(230, 68, 98, 24);
  SpinOuterRadius.MinValue := 0.1;
  SpinOuterRadius.MaxValue := 5000.0;
  SpinOuterRadius.Increment := 1.0;
  SpinOuterRadius.DecimalPlaces := 1;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GrpZones;
  Lbl.SetBounds(10, 102, 115, 18);
  Lbl.Caption := 'Amb / Music Mult:';

  SpinZoneAmbientMult := TFloatSpinEdit.Create(Self);
  SpinZoneAmbientMult.Parent := GrpZones;
  SpinZoneAmbientMult.SetBounds(128, 98, 92, 24);
  SpinZoneAmbientMult.MinValue := 0.0;
  SpinZoneAmbientMult.MaxValue := 4.0;
  SpinZoneAmbientMult.Increment := 0.1;
  SpinZoneAmbientMult.DecimalPlaces := 2;

  SpinZoneMusicMult := TFloatSpinEdit.Create(Self);
  SpinZoneMusicMult.Parent := GrpZones;
  SpinZoneMusicMult.SetBounds(230, 98, 98, 24);
  SpinZoneMusicMult.MinValue := 0.0;
  SpinZoneMusicMult.MaxValue := 4.0;
  SpinZoneMusicMult.Increment := 0.1;
  SpinZoneMusicMult.DecimalPlaces := 2;

  ButtonApplyZone := TButton.Create(Self);
  ButtonApplyZone.Parent := GrpZones;
  ButtonApplyZone.SetBounds(10, 130, 318, 28);
  ButtonApplyZone.Caption := 'Apply Selected Zone Parameters';
  ButtonApplyZone.OnClick := @ButtonApplyZoneClick;

  ListRouters := TListBox.Create(Self);
  ListRouters.Parent := GrpZones;
  ListRouters.SetBounds(10, 166, 318, 175);
  ListRouters.Anchors := [akLeft, akTop, akRight, akBottom];

  { Center 5-Bus Fader Strips + Meter Canvas }
  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := Self;
  PanelCenter.Align := alClient;
  PanelCenter.BorderSpacing.Around := 6;
  PanelCenter.BevelOuter := bvNone;

  PanelFaders := TPanel.Create(Self);
  PanelFaders.Parent := PanelCenter;
  PanelFaders.Align := alTop;
  PanelFaders.Height := 310;
  PanelFaders.BevelOuter := bvLowered;

  for Bus := Low(TCastleAudioBusKind) to High(TCastleAudioBusKind) do
  begin
    PanelStrip := TPanel.Create(Self);
    PanelStrip.Parent := PanelFaders;
    PanelStrip.SetBounds(10 + Ord(Bus) * 130, 8, 122, 292);
    PanelStrip.BevelOuter := bvRaised;

    Lbl := TLabel.Create(Self);
    Lbl.Parent := PanelStrip;
    Lbl.SetBounds(8, 6, 106, 20);
    Lbl.Alignment := taCenter;
    Lbl.AutoSize := false;
    Lbl.Font.Style := [Graphics.fsBold];
    Lbl.Caption := AudioBusKindToDisplayName(Bus);

    TrackFaders[Bus] := TTrackBar.Create(Self);
    TrackFaders[Bus].Parent := PanelStrip;
    TrackFaders[Bus].Orientation := trVertical;
    TrackFaders[Bus].Reversed := true;
    TrackFaders[Bus].Min := 0;
    TrackFaders[Bus].Max := 200;
    TrackFaders[Bus].Position := 100;
    TrackFaders[Bus].Frequency := 25;
    TrackFaders[Bus].SetBounds(36, 28, 48, 176);
    TrackFaders[Bus].Tag := Ord(Bus);
    TrackFaders[Bus].OnChange := @FaderChange;

    LabelDb[Bus] := TLabel.Create(Self);
    LabelDb[Bus].Parent := PanelStrip;
    LabelDb[Bus].SetBounds(4, 208, 114, 18);
    LabelDb[Bus].Alignment := taCenter;
    LabelDb[Bus].AutoSize := false;
    LabelDb[Bus].Caption := '100% (+0.0 dB)';

    CheckMute[Bus] := TCheckBox.Create(Self);
    CheckMute[Bus].Parent := PanelStrip;
    CheckMute[Bus].SetBounds(12, 232, 96, 22);
    CheckMute[Bus].Caption := 'Mute';
    CheckMute[Bus].Tag := Ord(Bus);
    CheckMute[Bus].OnChange := @MuteOrSoloChange;

    if Bus <> abkMaster then
    begin
      CheckSolo[Bus] := TCheckBox.Create(Self);
      CheckSolo[Bus].Parent := PanelStrip;
      CheckSolo[Bus].SetBounds(12, 256, 96, 22);
      CheckSolo[Bus].Caption := 'Solo';
      CheckSolo[Bus].Tag := Ord(Bus);
      CheckSolo[Bus].OnChange := @MuteOrSoloChange;
    end else
      CheckSolo[Bus] := nil;
  end;

  PaintBoxMeters := TPaintBox.Create(Self);
  PaintBoxMeters.Parent := PanelCenter;
  PaintBoxMeters.Align := alClient;
  PaintBoxMeters.BorderSpacing.Top := 6;
  PaintBoxMeters.OnPaint := @PaintBoxMetersPaint;
end;

function TAudioMixerForm.CurrentListenerPos: TVector3;
begin
  Result := FindViewportCameraWorldPos(FRootComponent);
end;

function TAudioMixerForm.ActiveMixer: TCastleAudioBusMixer;
begin
  if Length(FSummary.Mixers) > 0 then
    Result := FSummary.Mixers[0]
  else
    Result := nil;
end;

function TAudioMixerForm.ActiveZone: TCastleAudioZone;
var
  Idx: Integer;
begin
  Idx := ComboZone.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FSummary.Zones)) then
    Result := FSummary.Zones[Idx]
  else
    Result := nil;
end;

procedure TAudioMixerForm.RefreshAll;
var
  I, PrevZoneIdx: Integer;
  Mix: TCastleAudioBusMixer;
  DomPr: TCastleAudioAcousticPreset;
  DomW: Single;
  ParentName: String;
begin
  PrevZoneIdx := ComboZone.ItemIndex;
  FSummary := TAudioMixerHelper.ScanAudioSoundscape(FRootComponent, CurrentListenerPos);

  Mix := ActiveMixer;
  if Mix <> nil then
    Mix.EvaluateWorldSoundscape(FRootComponent, CurrentListenerPos, 0.0, DomPr, DomW);

  ComboZone.Items.BeginUpdate;
  try
    ComboZone.Items.Clear;
    for I := 0 to High(FSummary.Zones) do
      ComboZone.Items.Add(Format('%s [%s %.0f..%.0fm]',
        [FSummary.Zones[I].Name,
         AudioAcousticPresetToDisplayName(FSummary.Zones[I].AcousticPreset),
         FSummary.Zones[I].InnerRadius,
         FSummary.Zones[I].OuterRadius]));
    if ComboZone.Items.Count > 0 then
      ComboZone.ItemIndex := Clamped(PrevZoneIdx, 0, ComboZone.Items.Count - 1);
  finally
    ComboZone.Items.EndUpdate;
  end;

  ListRouters.Items.BeginUpdate;
  try
    ListRouters.Items.Clear;
    for I := 0 to High(FSummary.Routers) do
    begin
      if FSummary.Routers[I].Parent <> nil then
        ParentName := FSummary.Routers[I].Parent.Name
      else
        ParentName := '(detached)';
      ListRouters.Items.Add(Format('%s -> %s (Vol=%.2f Pitch=%.2f)',
        [ParentName,
         AudioBusKindToDisplayName(FSummary.Routers[I].Bus),
         FSummary.Routers[I].LastAppliedVolume,
         FSummary.Routers[I].LastAppliedPitch]));
    end;
  finally
    ListRouters.Items.EndUpdate;
  end;

  LoadMixerControls;
  LoadZoneControls;

  LabelStatus.Caption := Format(
    'Mixers: %d | Zones: %d | Routed Transforms: %d | Camera Zone: %s (%.0f%%)',
    [Length(FSummary.Mixers), Length(FSummary.Zones), Length(FSummary.Routers),
     AudioAcousticPresetToDisplayName(FSummary.DominantPreset),
     FSummary.DominantWeight * 100.0]);
  PaintBoxMeters.Invalidate;
end;

procedure TAudioMixerForm.LoadMixerControls;
var
  Mix: TCastleAudioBusMixer;
  Bus: TCastleAudioBusKind;
  G: Single;
begin
  FUpdatingUi := true;
  try
    Mix := ActiveMixer;
    for Bus := Low(TCastleAudioBusKind) to High(TCastleAudioBusKind) do
    begin
      TrackFaders[Bus].Enabled := Mix <> nil;
      CheckMute[Bus].Enabled := Mix <> nil;
      if CheckSolo[Bus] <> nil then
        CheckSolo[Bus].Enabled := Mix <> nil;

      if Mix <> nil then
      begin
        G := Mix.GetBusGain(Bus);
        TrackFaders[Bus].Position := Round(G * 100.0);
        LabelDb[Bus].Caption := Format('%d%% (%s)',
          [Round(G * 100.0), LinearGainToDecibelsStr(G)]);
        CheckMute[Bus].Checked := Mix.GetBusMuted(Bus);
        if CheckSolo[Bus] <> nil then
          CheckSolo[Bus].Checked := Mix.GetBusSolo(Bus);
      end else
        LabelDb[Bus].Caption := '(no mixer)';
    end;

    CheckDuckVoice.Enabled := Mix <> nil;
    CheckVoiceActiveTest.Enabled := Mix <> nil;
    SpinDuckFactor.Enabled := Mix <> nil;
    if Mix <> nil then
    begin
      CheckDuckVoice.Checked := Mix.DuckMusicOnVoice;
      CheckVoiceActiveTest.Checked := Mix.VoiceActive;
      SpinDuckFactor.Value := Mix.VoiceDuckFactor;
    end;
  finally
    FUpdatingUi := false;
  end;
end;

procedure TAudioMixerForm.LoadZoneControls;
var
  Z: TCastleAudioZone;
begin
  FUpdatingUi := true;
  try
    Z := ActiveZone;
    ComboZonePreset.Enabled := Z <> nil;
    SpinInnerRadius.Enabled := Z <> nil;
    SpinOuterRadius.Enabled := Z <> nil;
    SpinZoneAmbientMult.Enabled := Z <> nil;
    SpinZoneMusicMult.Enabled := Z <> nil;
    ButtonApplyZone.Enabled := Z <> nil;
    if Z <> nil then
    begin
      ComboZonePreset.ItemIndex := Ord(Z.AcousticPreset);
      SpinInnerRadius.Value := Z.InnerRadius;
      SpinOuterRadius.Value := Z.OuterRadius;
      SpinZoneAmbientMult.Value := Z.AmbientGainMultiplier;
      SpinZoneMusicMult.Value := Z.MusicGainMultiplier;
    end;
  finally
    FUpdatingUi := false;
  end;
end;

procedure TAudioMixerForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  NotifyViewportRefresh;
end;

procedure TAudioMixerForm.NotifyViewportRefresh;
begin
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TAudioMixerForm.ButtonEnsureMixerClick(Sender: TObject);
begin
  if TAudioMixerHelper.EnsureMixerInDesign(FRootComponent, FDesignOwner) <> nil then
  begin
    RefreshAll;
    NotifyModified('Ensure Audio Bus Mixer');
  end;
end;

procedure TAudioMixerForm.ButtonSpawnZoneClick(Sender: TObject);
begin
  TAudioMixerHelper.EnsureMixerInDesign(FRootComponent, FDesignOwner);
  if TAudioMixerHelper.CreateAudioZoneInDesign(
       FRootComponent, FDesignOwner, CurrentListenerPos, aapCaveReverb) <> nil then
  begin
    RefreshAll;
    ComboZone.ItemIndex := ComboZone.Items.Count - 1;
    LoadZoneControls;
    NotifyModified('Spawn Spatial Audio Zone');
  end;
end;

procedure TAudioMixerForm.ButtonRouteSelectedClick(Sender: TObject);
var
  TargetT: TCastleTransform;
  Mix: TCastleAudioBusMixer;
  ChosenBus: TCastleAudioBusKind;
begin
  Mix := TAudioMixerHelper.EnsureMixerInDesign(FRootComponent, FDesignOwner);
  if FInitialSelected is TCastleTransform then
    TargetT := TCastleTransform(FInitialSelected)
  else
    TargetT := TAudioMixerHelper.FindFirstRoutableTransform(FRootComponent);

  if TargetT = nil then
  begin
    MessageDlg('No 3D TCastleTransform found to route onto an Audio Bus.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  ChosenBus := TCastleAudioBusKind(Clamped(ComboRouteBus.ItemIndex + 1,
    Ord(abkMusic), Ord(abkAmbient)));
  if Mix <> nil then
    TAudioMixerHelper.AttachBusRouter(TargetT, FDesignOwner, ChosenBus, Mix.Name)
  else
    TAudioMixerHelper.AttachBusRouter(TargetT, FDesignOwner, ChosenBus, '');

  RefreshAll;
  NotifyModified('Route Transform to Audio Bus');
end;

procedure TAudioMixerForm.ButtonLiveEvalClick(Sender: TObject);
begin
  FLiveTimer.Enabled := not FLiveTimer.Enabled;
  if FLiveTimer.Enabled then
    ButtonLiveEval.Caption := 'Stop Live Camera Eval'
  else
    ButtonLiveEval.Caption := 'Start Live Camera Eval';
end;

procedure TAudioMixerForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TAudioMixerHelper.FormatAudioSoundscapeMarkdown(
    FRootComponent, CurrentListenerPos);
  LabelStatus.Caption := 'Copied Spatial Audio Soundscape Markdown report to clipboard.';
end;

procedure TAudioMixerForm.FaderChange(Sender: TObject);
var
  Mix: TCastleAudioBusMixer;
  Bus: TCastleAudioBusKind;
  DomPr: TCastleAudioAcousticPreset;
  DomW: Single;
begin
  if FUpdatingUi then
    Exit;
  Mix := ActiveMixer;
  if (Mix = nil) or not (Sender is TTrackBar) then
    Exit;
  Bus := TCastleAudioBusKind(TTrackBar(Sender).Tag);
  Mix.SetBusGain(Bus, TTrackBar(Sender).Position / 100.0);
  LabelDb[Bus].Caption := Format('%d%% (%s)',
    [TTrackBar(Sender).Position, LinearGainToDecibelsStr(Mix.GetBusGain(Bus))]);
  Mix.EvaluateWorldSoundscape(FRootComponent, CurrentListenerPos, 0.0, DomPr, DomW);
  PaintBoxMeters.Invalidate;
  NotifyModified('Adjust Audio Bus Fader');
end;

procedure TAudioMixerForm.MuteOrSoloChange(Sender: TObject);
var
  Mix: TCastleAudioBusMixer;
  Bus: TCastleAudioBusKind;
  DomPr: TCastleAudioAcousticPreset;
  DomW: Single;
begin
  if FUpdatingUi then
    Exit;
  Mix := ActiveMixer;
  if (Mix = nil) or not (Sender is TCheckBox) then
    Exit;
  Bus := TCastleAudioBusKind(TCheckBox(Sender).Tag);
  if Sender = CheckMute[Bus] then
    Mix.SetBusMuted(Bus, TCheckBox(Sender).Checked)
  else
    Mix.SetBusSolo(Bus, TCheckBox(Sender).Checked);
  Mix.EvaluateWorldSoundscape(FRootComponent, CurrentListenerPos, 0.0, DomPr, DomW);
  PaintBoxMeters.Invalidate;
  NotifyModified('Toggle Audio Bus Mute / Solo');
end;

procedure TAudioMixerForm.DuckSettingsChange(Sender: TObject);
var
  Mix: TCastleAudioBusMixer;
  DomPr: TCastleAudioAcousticPreset;
  DomW: Single;
begin
  if FUpdatingUi then
    Exit;
  Mix := ActiveMixer;
  if Mix = nil then
    Exit;
  Mix.DuckMusicOnVoice := CheckDuckVoice.Checked;
  Mix.VoiceActive := CheckVoiceActiveTest.Checked;
  Mix.VoiceDuckFactor := SpinDuckFactor.Value;
  Mix.EvaluateWorldSoundscape(FRootComponent, CurrentListenerPos, 0.0, DomPr, DomW);
  PaintBoxMeters.Invalidate;
  NotifyModified('Update Voice Ducking Settings');
end;

procedure TAudioMixerForm.MixPresetButtonClick(Sender: TObject);
var
  Mix: TCastleAudioBusMixer;
begin
  if not (Sender is TButton) then
    Exit;
  Mix := TAudioMixerHelper.EnsureMixerInDesign(FRootComponent, FDesignOwner);
  TAudioMixerHelper.ApplySoundscapeMixPreset(Mix, TButton(Sender).Tag);
  RefreshAll;
  NotifyModified('Apply Audio Mix Preset');
end;

procedure TAudioMixerForm.ComboZoneChange(Sender: TObject);
begin
  LoadZoneControls;
end;

procedure TAudioMixerForm.ButtonApplyZoneClick(Sender: TObject);
var
  Z: TCastleAudioZone;
begin
  Z := ActiveZone;
  if Z = nil then
    Exit;
  Z.AcousticPreset := TCastleAudioAcousticPreset(
    Clamped(ComboZonePreset.ItemIndex, 0, Ord(High(TCastleAudioAcousticPreset))));
  Z.ZoneLabel := AudioAcousticPresetToDisplayName(Z.AcousticPreset);
  Z.InnerRadius := SpinInnerRadius.Value;
  Z.OuterRadius := Max(SpinInnerRadius.Value, SpinOuterRadius.Value);
  Z.AmbientGainMultiplier := SpinZoneAmbientMult.Value;
  Z.MusicGainMultiplier := SpinZoneMusicMult.Value;
  RefreshAll;
  NotifyModified('Update Spatial Audio Zone');
end;

procedure TAudioMixerForm.PaintBoxMetersPaint(Sender: TObject);
var
  C: TCanvas;
  R: TRect;
  Mix: TCastleAudioBusMixer;
  Bus: TCastleAudioBusKind;
  BarW, X, FillW, MaxW: Integer;
  EffG: Single;
begin
  C := PaintBoxMeters.Canvas;
  R := PaintBoxMeters.ClientRect;
  C.Brush.Color := RGBToColor(22, 26, 34);
  C.FillRect(R);

  C.Font.Color := RGBToColor(215, 224, 238);
  C.Brush.Style := bsClear;
  C.TextOut(12, 8, 'Effective Bus Output Levels & Spatial Zone Blend');

  Mix := ActiveMixer;
  if Mix = nil then
  begin
    C.Font.Color := RGBToColor(150, 162, 180);
    C.TextOut(12, 36, 'Click "+ Ensure Bus Mixer" above to create TCastleAudioBusMixer.');
    Exit;
  end;

  MaxW := Max(120, R.Right - 150);
  for Bus := Low(TCastleAudioBusKind) to High(TCastleAudioBusKind) do
  begin
    EffG := Mix.EffectiveBusGain(Bus);
    X := 110;
    BarW := Round(Clamped(EffG / 2.0, 0.0, 1.0) * MaxW);
    C.Font.Color := RGBToColor(200, 212, 228);
    C.Brush.Style := bsClear;
    C.TextOut(14, 34 + Ord(Bus) * 26, AudioBusKindToDisplayName(Bus));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(38, 44, 56);
    C.FillRect(Rect(X, 34 + Ord(Bus) * 26, X + MaxW, 52 + Ord(Bus) * 26));

    FillW := BarW;
    if EffG <= 0.001 then
      C.Brush.Color := RGBToColor(90, 96, 110)
    else if EffG > 1.25 then
      C.Brush.Color := RGBToColor(242, 174, 58)
    else
      C.Brush.Color := RGBToColor(56, 206, 134);
    C.FillRect(Rect(X, 34 + Ord(Bus) * 26, X + FillW, 52 + Ord(Bus) * 26));

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(235, 240, 248);
    C.TextOut(X + 8, 35 + Ord(Bus) * 26,
      Format('%.0f%% (%s)', [EffG * 100.0, LinearGainToDecibelsStr(EffG)]));
  end;
end;

procedure TAudioMixerForm.LiveTimerTick(Sender: TObject);
var
  Mix: TCastleAudioBusMixer;
  DomPr: TCastleAudioAcousticPreset;
  DomW: Single;
begin
  Mix := ActiveMixer;
  if Mix = nil then
    Exit;
  Mix.EvaluateWorldSoundscape(FRootComponent, CurrentListenerPos, 0.033, DomPr, DomW);
  FSummary.DominantPreset := DomPr;
  FSummary.DominantWeight := DomW;
  LabelStatus.Caption := Format(
    'Live Camera Eval | Zone: %s (%.0f%%) | Voice Duck Envelope: %.0f%%',
    [AudioAcousticPresetToDisplayName(DomPr), DomW * 100.0, Mix.DuckAmount * 100.0]);
  PaintBoxMeters.Invalidate;
  NotifyViewportRefresh;
end;

procedure TAudioMixerForm.ButtonCloseClick(Sender: TObject);
begin
  FLiveTimer.Enabled := false;
  Close;
end;

end.

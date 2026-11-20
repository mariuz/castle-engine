{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 397: Procedural Icicle, Stalactite & Cave Drip
  Overhang Studio. }
unit TestToolIcicleOverhang;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolIcicleOverhang = class(TCastleTestCase)
  published
    procedure TestOverhangUndersideDetectionOpenSkyRejectionAndPairedStalagmites;
    procedure TestStefanTaperedProfileFloorClearanceClampAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleIcicleOverhang, ToolIcicleOverhang;

procedure TTestToolIcicleOverhang.TestOverhangUndersideDetectionOpenSkyRejectionAndPairedStalagmites;
var
  Root: TComponent;
  VP: TCastleViewport;
  Overhang: TCastleIcicleOverhang;
  I: Integer;
  S: TIcicleSpikeSample;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TIcicleOverhangHelper.SpawnCavernOverhangDemo(Root, Root, Overhang));

    { CavernCeilingLedgeWest covers X in [-6.0 .. +1.0], while X > +1.0 is open sky! }
    AssertTrue('Spikes spawn under West ceiling ledge', Overhang.SpikeCount >= 8);
    AssertTrue('Paired floor stalagmites spawn beneath cave drips',
      Overhang.PairedStalagmiteCount >= 6);

    for I := 0 to Overhang.SpikeCount - 1 do
    begin
      S := Overhang.GetSpike(I);
      AssertTrue('Zero floating sky icicles outside X <= 1.05m ceiling ledge',
        S.CeilingAttachWorld.X <= 1.05);
      AssertTrue('Tip stays strictly above CavernFloorShelf (Y = 0)',
        S.TipWorld.Y > 0.20);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolIcicleOverhang.TestStefanTaperedProfileFloorClearanceClampAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  LowFloor, LowCeiling: TCastleBox;
  Overhang, Restored: TCastleIcicleOverhang;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleIcicleOverhang.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { Cramped crawlspace with only 0.30m gap (< MinClearDropMeters = 0.55m) -> 0 spikes! }
    LowFloor := TCastleBox.Create(Root);
    LowFloor.Size := Vector3(8.0, 0.2, 8.0);
    LowFloor.Translation := Vector3(0.0, 0.90, 0.0);
    VP.Items.Add(LowFloor);

    LowCeiling := TCastleBox.Create(Root);
    LowCeiling.Size := Vector3(8.0, 0.2, 8.0);
    LowCeiling.Translation := Vector3(0.0, 1.40, 0.0);
    VP.Items.Add(LowCeiling);

    Overhang := TCastleIcicleOverhang.Create(Root);
    Overhang.Translation := Vector3(0.0, 1.10, 0.0);
    Overhang.ApplyPreset(iopRoofEaveWinterIcicles);
    VP.Items.Add(Overhang);
    AssertEquals(0, Overhang.GrowOverhangSpikes(VP.Items));

    { Stefan tapered profile: BaseRadius at u=0, sharp 0.0 at u=1 }
    AssertSameValue(Overhang.BaseRadiusMeters,
      Overhang.EvaluateProfileRadiusAtNormalizedU(0.0), 0.0001);
    AssertSameValue(0.0,
      Overhang.EvaluateProfileRadiusAtNormalizedU(1.0), 0.0001);
    AssertTrue(Overhang.EvaluateProfileRadiusAtNormalizedU(0.5) <
      Overhang.BaseRadiusMeters);

    { Raise ceiling to Y = 4.5m -> winter icicles grow cleanly with 0 stalagmites }
    LowCeiling.Translation := Vector3(0.0, 4.50, 0.0);
    AssertTrue(Overhang.GrowOverhangSpikes(VP.Items) >= 12);
    AssertEquals(0, Overhang.PairedStalagmiteCount);

    SerializedScene := ComponentToString(Overhang);
    AssertTrue(Pos('IcicleOverhangPreview', SerializedScene) = 0);

    Overhang.ApplyPreset(iopGlacialIceCavern);
    JsonCfg := TIcicleOverhangHelper.ExportOverhangJson(Overhang);
    AssertTrue(TIcicleOverhangHelper.ImportOverhangJson(Restored, JsonCfg));
    AssertEquals(Ord(iopGlacialIceCavern), Ord(Restored.Preset));
    Md := TIcicleOverhangHelper.GenerateMarkdownReport(Overhang);
    AssertTrue(Pos('GlacialIceCavern', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolIcicleOverhang);

end.

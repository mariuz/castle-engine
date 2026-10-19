{
  Copyright 2025-2025 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test CastleTransformManipulate unit. }
unit TestCastleTransformManipulate;

interface

uses Classes, SysUtils,
  CastleTester;

type
  TTestCastleTransformManipulate = class(TCastleTestCase)
  strict private
    FModifiedCount: Integer;
    FModifyEndCount: Integer;
    procedure HandleTransformModified(Sender: TObject);
    procedure HandleTransformModifyEnd(Sender: TObject);
  published
    procedure TestSelectedCountAndFree;
    procedure TestTranslateSnapAndCoordSpace;
    procedure TestRotateSnapAndCoordSpace;
    procedure TestScaleSnap;
    procedure TestMultiSelectionManipulateAndHierarchy;
    procedure TestSnapToFloor;
    procedure TestAlignAndDistributeSelected;
    procedure TestSnapSelectedToGridAndPivotCenter;
    procedure TestSnapToFloorAlignToNormal;
    procedure TestMirrorRotate90AndRandomizeSelected;
    procedure TestStackSelected;
    procedure TestSnapSelectedToRaySurfaceAndVertex;
    procedure TestMeasureSelectedAndRayDistance;
    procedure TestProjectAlongDirectionDistributeGapsAndSnapRotScale;
    procedure TestSwapPositionsAndMatchSelectedSize;
  end;

implementation

uses Math,
  CastleTransformManipulate, CastleTransform, CastleControls, CastleVectors,
  CastleViewport, CastleScene;

procedure TTestCastleTransformManipulate.HandleTransformModified(Sender: TObject);
begin
  Inc(FModifiedCount);
end;

procedure TTestCastleTransformManipulate.HandleTransformModifyEnd(Sender: TObject);
begin
  Inc(FModifyEndCount);
end;

procedure TTestCastleTransformManipulate.TestSelectedCountAndFree;
var
  B: TCastleButton;
  T1, T2, T3: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  // initialize all variables to nil, to allow easy finally clause later
  Manipulate := nil;
  T1 := nil;
  T2 := nil;
  T3 := nil;
  B := nil;

  try
    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.Mode := mmTranslate;
    T1 := TCastleTransform.Create(nil);
    T2 := TCastleTransform.Create(nil);
    T3 := TCastleTransform.Create(nil);
    B := TCastleButton.Create(nil);

    AssertEquals(0, Manipulate.SelectedCount);

    Manipulate.SetSelected(nil); // allowed

    AssertEquals(0, Manipulate.SelectedCount);

    Manipulate.SetSelected([T1, nil, B]);

    AssertEquals(1, Manipulate.SelectedCount);
    AssertTrue(Manipulate.Selected[0] = T1);

    Manipulate.SetSelected([T1, nil, B, T3]);

    AssertEquals(2, Manipulate.SelectedCount);
    AssertTrue(Manipulate.Selected[0] = T1);
    AssertTrue(Manipulate.Selected[1] = T3);

    FreeAndNil(T1);

    AssertEquals(1, Manipulate.SelectedCount);
    AssertTrue(Manipulate.Selected[0] = T3);

    // Manipulating after T1 was freed should now manipulate T3 cleanly
    Manipulate.TranslateSelected(Vector3(5, 0, 0));
    AssertVectorEquals(Vector3(5, 0, 0), T3.Translation);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(T1);
    FreeAndNil(T2);
    FreeAndNil(T3);
    FreeAndNil(B);
  end;
end;

procedure TTestCastleTransformManipulate.TestTranslateSnapAndCoordSpace;
var
  T1: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Manipulate := TCastleTransformManipulate.Create(nil);
  T1 := TCastleTransform.Create(nil);
  try
    FModifiedCount := 0;
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.Mode := mmTranslate;
    Manipulate.SetSelected([T1]);

    // Test TranslateSnap = 2.0
    Manipulate.TranslateSnap := 2.0;

    // Sub-threshold delta (< 1.0) should snap to 0 and not move T1
    Manipulate.TranslateSelected(Vector3(0.4, -0.8, 0.9));
    AssertVectorEquals(TVector3.Zero, T1.Translation);
    AssertEquals(0, FModifiedCount);

    // Delta (2.9, -3.2, 1.1) should snap to (2.0, -4.0, 2.0)
    Manipulate.TranslateSelected(Vector3(2.9, -3.2, 1.1));
    AssertVectorEquals(Vector3(2.0, -4.0, 2.0), T1.Translation);
    AssertEquals(1, FModifiedCount);

    // Test Local vs World coordinate space on a 90-degree Y-rotated transform
    T1.Translation := TVector3.Zero;
    T1.Rotation := Vector4(0, 1, 0, Pi / 2); // local +X points along world -Z
    Manipulate.TranslateSnap := 0;

    Manipulate.CoordSpace := csLocal;
    Manipulate.TranslateSelected(Vector3(3, 0, 0));
    AssertVectorEquals(Vector3(0, 0, -3), T1.Translation, 1e-4);

    Manipulate.CoordSpace := csWorld;
    Manipulate.TranslateSelected(Vector3(3, 0, 0));
    AssertVectorEquals(Vector3(3, 0, -3), T1.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(T1);
  end;
end;

procedure TTestCastleTransformManipulate.TestRotateSnapAndCoordSpace;
var
  T1: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Manipulate := TCastleTransformManipulate.Create(nil);
  T1 := TCastleTransform.Create(nil);
  try
    FModifiedCount := 0;
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.Mode := mmRotate;
    Manipulate.SetSelected([T1]);

    // 15 degree snap
    Manipulate.RotateSnap := DegToRad(15);

    // 5 degrees (< 7.5 deg) snaps to 0
    Manipulate.RotateSelected(1, DegToRad(5));
    AssertEquals(0, FModifiedCount);
    AssertSameValue(0, T1.Rotation.W, 1e-4);

    // 22 degrees snaps to 15 degrees
    Manipulate.RotateSelected(1, DegToRad(22));
    AssertEquals(1, FModifiedCount);
    AssertVectorEquals(Vector3(0, 1, 0), T1.Rotation.XYZ, 1e-4);
    AssertSameValue(DegToRad(15), T1.Rotation.W, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(T1);
  end;
end;

procedure TTestCastleTransformManipulate.TestScaleSnap;
var
  T1: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Manipulate := TCastleTransformManipulate.Create(nil);
  T1 := TCastleTransform.Create(nil);
  try
    FModifiedCount := 0;
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.Mode := mmScale;
    Manipulate.SetSelected([T1]);
    Manipulate.ScaleSnap := 0.25;

    // Sub-threshold delta snaps to 0
    Manipulate.ScaleSelected(Vector3(0.1, 0, 0));
    AssertVectorEquals(Vector3(1, 1, 1), T1.Scale);
    AssertEquals(0, FModifiedCount);

    // 0.24 snaps to 0.25, 0.52 snaps to 0.50
    Manipulate.ScaleSelected(Vector3(0.24, 0.52, -0.26));
    AssertVectorEquals(Vector3(1.25, 1.50, 0.75), T1.Scale, 1e-4);
    AssertEquals(1, FModifiedCount);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(T1);
  end;
end;

procedure TTestCastleTransformManipulate.TestMultiSelectionManipulateAndHierarchy;
var
  Viewport: TCastleViewport;
  Parent1, Child1, Sibling2: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Parent1 := TCastleTransform.Create(Viewport);
    Parent1.Translation := Vector3(1, 2, 3);
    Viewport.Items.Add(Parent1);

    Child1 := TCastleTransform.Create(Viewport);
    Child1.Translation := Vector3(0, 5, 0);
    Parent1.Add(Child1);

    Sibling2 := TCastleTransform.Create(Viewport);
    Sibling2.Translation := Vector3(10, 20, 30);
    Viewport.Items.Add(Sibling2);

    // Select Parent1, Child1 (descendant of Parent1), and Sibling2
    Manipulate.Mode := mmTranslate;
    Manipulate.CoordSpace := csWorld;
    Manipulate.SetSelected([Parent1, Child1, Sibling2]);
    AssertEquals(3, Manipulate.SelectedCount);

    // Translating selection by (4, 0, -2) must move Parent1 and Sibling2,
    // and must NOT double-move Child1 (whose local Translation remains (0, 5, 0)).
    Manipulate.TranslateSelected(Vector3(4, 0, -2));
    AssertVectorEquals(Vector3(5, 2, 1), Parent1.Translation);
    AssertVectorEquals(Vector3(14, 20, 28), Sibling2.Translation);
    AssertVectorEquals(Vector3(0, 5, 0), Child1.Translation);

    // Scaling selection by (+1, +1, +1) scales Parent1 and Sibling2, not Child1 twice
    Manipulate.ScaleSelected(Vector3(1, 1, 1));
    AssertVectorEquals(Vector3(2, 2, 2), Parent1.Scale);
    AssertVectorEquals(Vector3(2, 2, 2), Sibling2.Scale);
    AssertVectorEquals(Vector3(1, 1, 1), Child1.Scale);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSnapToFloor;
var
  Viewport: TCastleViewport;
  FloorBox, FloatingBox1, FloatingBox2: TCastleBox;
  EmptyTransform: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    FModifiedCount := 0;
    FModifyEndCount := 0;
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    // Floor with top surface at Y = 0 (center at Y = -1, height = 2)
    FloorBox := TCastleBox.Create(Viewport);
    FloorBox.Size := Vector3(100, 2, 100);
    FloorBox.Translation := Vector3(0, -1, 0);
    Viewport.Items.Add(FloorBox);

    // Box of height 4 (HalfHeight = 2) floating at Y = 10 -> should snap to Y = 2
    FloatingBox1 := TCastleBox.Create(Viewport);
    FloatingBox1.Size := Vector3(2, 4, 2);
    FloatingBox1.Translation := Vector3(-5, 10, 0);
    Viewport.Items.Add(FloatingBox1);

    // Box of height 6 (HalfHeight = 3) floating at Y = 25 -> should snap to Y = 3
    FloatingBox2 := TCastleBox.Create(Viewport);
    FloatingBox2.Size := Vector3(2, 6, 2);
    FloatingBox2.Translation := Vector3(5, 25, 0);
    Viewport.Items.Add(FloatingBox2);

    // Empty transform (no geometry) at Y = 12 -> origin should snap to Y = 0
    EmptyTransform := TCastleTransform.Create(Viewport);
    EmptyTransform.Translation := Vector3(0, 12, 0);
    Viewport.Items.Add(EmptyTransform);

    Manipulate.SetSelected([FloatingBox1, FloatingBox2, EmptyTransform]);
    AssertTrue(Manipulate.SnapToFloor);

    AssertVectorEquals(Vector3(-5, 2, 0), FloatingBox1.Translation, 1e-3);
    AssertVectorEquals(Vector3(5, 3, 0), FloatingBox2.Translation, 1e-3);
    AssertVectorEquals(Vector3(0, 0, 0), EmptyTransform.Translation, 1e-3);
    AssertEquals(1, FModifiedCount);
    AssertEquals(1, FModifyEndCount);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestAlignAndDistributeSelected;
var
  Viewport: TCastleViewport;
  T1, T2, T3, T4: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    FModifiedCount := 0;
    FModifyEndCount := 0;
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    T1.Translation := Vector3(4, 10, -2);
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(16, 2, 8);
    Viewport.Items.Add(T2);

    T3 := TCastleTransform.Create(Viewport);
    T3.Translation := Vector3(7, 20, 30);
    Viewport.Items.Add(T3);

    T4 := TCastleTransform.Create(Viewport);
    T4.Translation := Vector3(1, -6, 14);
    Viewport.Items.Add(T4);

    Manipulate.SetSelected([T1, T2, T3, T4]);

    // Align along Y (Axis = 1) to Primary (T1.Y = 10)
    Manipulate.AlignSelected(1, atPrimary);
    AssertSameValue(10, T1.Translation.Y, 1e-4);
    AssertSameValue(10, T2.Translation.Y, 1e-4);
    AssertSameValue(10, T3.Translation.Y, 1e-4);
    AssertSameValue(10, T4.Translation.Y, 1e-4);
    AssertEquals(1, FModifiedCount);
    AssertEquals(1, FModifyEndCount);

    // Align along Z (Axis = 2) to Center of (-2..30) -> 14
    Manipulate.AlignSelected(2, atCenter);
    AssertSameValue(14, T1.Translation.Z, 1e-4);
    AssertSameValue(14, T2.Translation.Z, 1e-4);
    AssertSameValue(14, T3.Translation.Z, 1e-4);
    AssertSameValue(14, T4.Translation.Z, 1e-4);

    // Distribute along X (Axis = 0): X values are (4, 16, 7, 1) -> sorted (1, 4, 7, 16)
    // Min = 1, Max = 16, Count = 4 -> Step = 15 / 3 = 5 -> (1, 6, 11, 16)
    Manipulate.DistributeSelected(0);
    AssertSameValue(1, T4.Translation.X, 1e-4);
    AssertSameValue(6, T1.Translation.X, 1e-4);
    AssertSameValue(11, T3.Translation.X, 1e-4);
    AssertSameValue(16, T2.Translation.X, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSnapSelectedToGridAndPivotCenter;
var
  Viewport: TCastleViewport;
  T1, T2: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    T1 := TCastleTransform.Create(Viewport);
    T1.Translation := Vector3(-4.3, 1.8, 0.2);
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(5.9, 2.1, -0.4);
    Viewport.Items.Add(T2);

    Manipulate.SetSelected([T1, T2]);
    Manipulate.TranslateSnap := 2.0;

    // SnapSelectedToGrid snaps T1 to (-4, 2, 0) and T2 to (6, 2, 0)
    AssertTrue(Manipulate.SnapSelectedToGrid);
    AssertVectorEquals(Vector3(-4, 2, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(6, 2, 0), T2.Translation, 1e-4);

    // Calling SnapSelectedToGrid again when already aligned returns false
    AssertFalse(Manipulate.SnapSelectedToGrid);

    // SelectionWorkingCenter of (-4, 2, 0) and (6, 2, 0) is (1, 2, 0)
    AssertVectorEquals(Vector3(1, 2, 0), Manipulate.SelectionWorkingCenter, 1e-4);

    // Rotate 90 degrees (+Pi/2) around Y (Axis = 1) with PivotMode = pmSelectionCenter
    // Center = (1, 2, 0).
    // T1 RelPos = (-5, 0, 0) -> rotated +90 deg around +Y -> (0, 0, 5) -> World (1, 2, 5)
    // T2 RelPos = ( 5, 0, 0) -> rotated +90 deg around +Y -> (0, 0, -5) -> World (1, 2, -5)
    Manipulate.CoordSpace := csWorld;
    Manipulate.PivotMode := pmSelectionCenter;
    Manipulate.RotateSelected(1, Pi / 2);
    AssertVectorEquals(Vector3(1, 2, 5), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(1, 2, -5), T2.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSnapToFloorAlignToNormal;
var
  Viewport: TCastleViewport;
  Floor: TCastleBox;
  Prop: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
  ExpectedNormal, ActualUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Floor := TCastleBox.Create(Viewport);
    Floor.Size := Vector3(50, 2, 50);
    Floor.Translation := Vector3(0, 0, 0);
    // Tilt floor 30 degrees (Pi/6) around Z axis
    Floor.Rotation := Vector4(0, 0, 1, Pi / 6);
    Viewport.Items.Add(Floor);

    Prop := TCastleTransform.Create(Viewport);
    Prop.Translation := Vector3(0, 10, 0);
    Viewport.Items.Add(Prop);

    Manipulate.SetSelected([Prop]);
    AssertTrue(Manipulate.SnapToFloor(true));

    ExpectedNormal := Floor.LocalToWorldDirection(Vector3(0, 1, 0)).Normalize;
    ActualUp := Prop.LocalToWorldDirection(Vector3(0, 1, 0)).Normalize;
    AssertVectorEquals(ExpectedNormal, ActualUp, 1e-4);
    AssertTrue(Prop.Translation.Y < 5.0);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestMirrorRotate90AndRandomizeSelected;
var
  Viewport: TCastleViewport;
  T1, T2: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    T1 := TCastleTransform.Create(Viewport);
    T1.Translation := Vector3(-2, 0, 0);
    T1.Rotation := Vector4(0, 1, 0, Pi / 6); // +30 deg around Y
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(6, 0, 0);
    T2.Rotation := Vector4(0, 1, 0, -Pi / 6); // -30 deg around Y
    Viewport.Items.Add(T2);

    Manipulate.SetSelected([T1, T2]);
    Manipulate.PivotMode := pmSelectionCenter; // Center X = 2

    // Mirror across X (Axis = 0):
    // T1.X = 2*2 - (-2) = 6, T2.X = 2*2 - 6 = -2
    // T1.Rotation Y axis negated -> (0, -1, 0, Pi/6)
    AssertTrue(Manipulate.MirrorSelected(0));
    AssertSameValue(6, T1.Translation.X, 1e-4);
    AssertSameValue(-2, T2.Translation.X, 1e-4);
    AssertSameValue(-1, T1.Rotation.Y, 1e-4);
    AssertVectorEquals(Vector3(1, 1, 1), T1.Scale, 1e-4); // Scale stays positive

    // Test RotateSelected90 around Y even when RotateSnap is set to 40 degrees
    T1.Translation := Vector3(4, 0, 0);
    T1.Rotation := TVector4.Zero;
    Manipulate.SetSelected([T1]);
    Manipulate.CoordSpace := csWorld;
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.RotateSnap := DegToRad(40.0);
    AssertTrue(Manipulate.RotateSelected90(1, false)); // +90 deg (+Pi/2)
    AssertSameValue(Pi / 2, T1.Rotation.W, 1e-4);

    // Test RandomizeSelected: Scale within [0.8, 1.2], PositionJitter within [-0.5, 0.5]
    T1.Translation := Vector3(10, 5, 10);
    T1.Scale := Vector3(1, 1, 1);
    AssertTrue(Manipulate.RandomizeSelected(Pi, 0.8, 1.2, 0.5));
    AssertTrue((T1.Scale.X >= 0.8 - 1e-4) and (T1.Scale.X <= 1.2 + 1e-4));
    AssertSameValue(T1.Scale.X, T1.Scale.Y, 1e-4);
    AssertSameValue(T1.Scale.X, T1.Scale.Z, 1e-4);
    AssertSameValue(5, T1.Translation.Y, 1e-4);
    AssertTrue(Abs(T1.Translation.X - 10) <= 0.5 + 1e-4);
    AssertTrue(Abs(T1.Translation.Z - 10) <= 0.5 + 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestStackSelected;
var
  Viewport: TCastleViewport;
  Box1, Box2, Box3: TCastleBox;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    // Box1: width 4 (X in [-2..2] at X=0)
    Box1 := TCastleBox.Create(Viewport);
    Box1.Size := Vector3(4, 2, 2);
    Box1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(Box1);

    // Box2: width 2 (half-width 1), placed at X=20
    Box2 := TCastleBox.Create(Viewport);
    Box2.Size := Vector3(2, 2, 2);
    Box2.Translation := Vector3(20, 0, 0);
    Viewport.Items.Add(Box2);

    // Box3: width 6 (half-width 3), placed at X=50
    Box3 := TCastleBox.Create(Viewport);
    Box3.Size := Vector3(6, 2, 2);
    Box3.Translation := Vector3(50, 0, 0);
    Viewport.Items.Add(Box3);

    Manipulate.SetSelected([Box1, Box2, Box3]);

    // Stack flush along X (Axis = 0, Spacing = 0):
    // Box1 stays at [-2..2] (center 0)
    // Box2 moves to [2..4] (center 3)
    // Box3 moves to [4..10] (center 7)
    AssertTrue(Manipulate.StackSelected(0, 0));
    AssertSameValue(0, Box1.Translation.X, 1e-4);
    AssertSameValue(3, Box2.Translation.X, 1e-4);
    AssertSameValue(7, Box3.Translation.X, 1e-4);

    // Stack with Spacing = 1.5 along X:
    // Box1 stays at [-2..2] (center 0)
    // Box2 moves to [3.5..5.5] (center 4.5)
    // Box3 moves to [7.0..13.0] (center 10.0)
    AssertTrue(Manipulate.StackSelected(0, 1.5));
    AssertSameValue(0, Box1.Translation.X, 1e-4);
    AssertSameValue(4.5, Box2.Translation.X, 1e-4);
    AssertSameValue(10.0, Box3.Translation.X, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSnapSelectedToRaySurfaceAndVertex;
var
  Viewport: TCastleViewport;
  TargetBox: TCastleBox;
  Prop1, Prop2: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    // TargetBox: Size (4, 2, 4) centered at (10, 0, 0) -> top face at Y = +1, corners at X in {8, 12}, Z in {-2, +2}
    TargetBox := TCastleBox.Create(Viewport);
    TargetBox.Size := Vector3(4, 2, 4);
    TargetBox.Translation := Vector3(10, 0, 0);
    Viewport.Items.Add(TargetBox);

    Prop1 := TCastleTransform.Create(Viewport);
    Prop1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(Prop1);

    Prop2 := TCastleTransform.Create(Viewport);
    Prop2.Translation := Vector3(1, 0, 0);
    Viewport.Items.Add(Prop2);

    Manipulate.SetSelected([Prop1, Prop2]);
    Manipulate.PivotMode := pmPrimarySelected;

    // 1. Surface snap (SnapToNearestVertex = false):
    // Ray from (10.5, 10, 0.5) pointing down (0, -1, 0) hits top face at (10.5, 1.0, 0.5).
    // Prop1 moves to (10.5, 1.0, 0.5), Prop2 preserves (+1, 0, 0) offset -> (11.5, 1.0, 0.5).
    AssertTrue(Manipulate.SnapSelectedToRay(
      Vector3(10.5, 10, 0.5), Vector3(0, -1, 0), false, false));
    AssertVectorEquals(Vector3(10.5, 1.0, 0.5), Prop1.Translation, 1e-4);
    AssertVectorEquals(Vector3(11.5, 1.0, 0.5), Prop2.Translation, 1e-4);

    // 2. Vertex snap (SnapToNearestVertex = true):
    // Ray from (11.8, 10, 1.8) pointing down (0, -1, 0) hits near corner (12, 1, 2).
    // Closest triangle vertex on top face is (12, 1, 2).
    AssertTrue(Manipulate.SnapSelectedToRay(
      Vector3(11.8, 10, 1.8), Vector3(0, -1, 0), true, false));
    AssertVectorEquals(Vector3(12.0, 1.0, 2.0), Prop1.Translation, 1e-4);
    AssertVectorEquals(Vector3(13.0, 1.0, 2.0), Prop2.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestMeasureSelectedAndRayDistance;
var
  Viewport: TCastleViewport;
  TargetBox: TCastleBox;
  T1, T2: TCastleTransform;
  Manipulate: TCastleTransformManipulate;
  Dist: Single;
  HitPoint, WorldDelta: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    T1 := TCastleTransform.Create(Viewport);
    T1.Translation := Vector3(1, 2, 3);
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(4, 6, 3); // delta (3, 4, 0) -> distance 5.0
    Viewport.Items.Add(T2);

    // With only 1 selected object, MeasureSelectedDistance returns -1
    Manipulate.SetSelected([T1]);
    AssertSameValue(-1.0, Manipulate.MeasureSelectedDistance(WorldDelta), 1e-4);

    // With 2 selected objects, MeasureSelectedDistance returns 5.0 and delta (3, 4, 0)
    Manipulate.SetSelected([T1, T2]);
    Dist := Manipulate.MeasureSelectedDistance(WorldDelta);
    AssertSameValue(5.0, Dist, 1e-4);
    AssertVectorEquals(Vector3(3, 4, 0), WorldDelta, 1e-4);

    // TargetBox centered at (1, 10, 3) with Size (4, 2, 4) -> bottom face at Y = 9, top face at Y = 11
    TargetBox := TCastleBox.Create(Viewport);
    TargetBox.Size := Vector3(4, 2, 4);
    TargetBox.Translation := Vector3(1, 10, 3);
    Viewport.Items.Add(TargetBox);

    // MeasureRayDistanceFromSelected from T1 at (1, 2, 3) to ray hitting TargetBox top face at (1, 11, 3):
    // Delta = (0, 9, 0), Distance = 9.0
    Manipulate.SetSelected([T1]);
    Manipulate.PivotMode := pmPrimarySelected;
    Dist := Manipulate.MeasureRayDistanceFromSelected(
      Vector3(1, 20, 3), Vector3(0, -1, 0), HitPoint, WorldDelta);
    AssertSameValue(9.0, Dist, 1e-4);
    AssertVectorEquals(Vector3(1, 11, 3), HitPoint, 1e-4);
    AssertVectorEquals(Vector3(0, 9, 0), WorldDelta, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestProjectAlongDirectionDistributeGapsAndSnapRotScale;
var
  Viewport: TCastleViewport;
  WallBox, PropBox, B1, B2, B3: TCastleBox;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    // 1. Test ProjectSelectedAlongDirection along +X onto a vertical wall at X = 20 (Size 2, 20, 20 -> MinX = 19)
    WallBox := TCastleBox.Create(Viewport);
    WallBox.Size := Vector3(2, 20, 20);
    WallBox.Translation := Vector3(20, 0, 0);
    Viewport.Items.Add(WallBox);

    // PropBox has Size (4, 2, 2) -> HalfExtent along +X is 2.0.
    // Starting at (0, 0, 0) and projecting along +X (1, 0, 0) should place PropBox flush against X = 19 -> Center X = 17.0.
    PropBox := TCastleBox.Create(Viewport);
    PropBox.Size := Vector3(4, 2, 2);
    PropBox.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(PropBox);

    Manipulate.SetSelected([PropBox]);
    AssertTrue(Manipulate.ProjectSelectedAlongDirection(Vector3(1, 0, 0), false));
    AssertVectorEquals(Vector3(17.0, 0, 0), PropBox.Translation, 1e-3);

    // 2. Test DistributeSelectedGaps along X (Axis = 0) with different-sized boxes:
    // B1: width 2 (at X=0 -> [-1..1])
    // B2: width 6 (at X=5 -> [2..8])
    // B3: width 4 (at X=20 -> [18..22])
    // Total span: [-1..22] = 23.0. Total box widths: 2 + 6 + 4 = 12.0.
    // Remaining gap space = 23.0 - 12.0 = 11.0 -> Equal gap between 3 boxes = 11.0 / 2 = 5.5.
    // B1 stays at [-1..1] (center 0).
    // B2 moves so MinX = 1.0 + 5.5 = 6.5 -> [6.5..12.5] -> center = 9.5.
    // B3 stays at [18..22] (center 20, gap from 12.5 to 18.0 is 5.5).
    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(6, 2, 2);
    B2.Translation := Vector3(5, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(4, 2, 2);
    B3.Translation := Vector3(20, 0, 0);
    Viewport.Items.Add(B3);

    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.DistributeSelectedGaps(0));
    AssertSameValue(0.0, B1.Translation.X, 1e-4);
    AssertSameValue(9.5, B2.Translation.X, 1e-4);
    AssertSameValue(20.0, B3.Translation.X, 1e-4);

    // 3. Test SnapSelectedRotationAndScaleToGrid:
    // RotateSnap = 15 deg, ScaleSnap = 0.25.
    // B1 has Rotation.W = 22 deg -> snaps to 15 deg, Scale = (1.14, 1.88, 0.49) -> snaps to (1.25, 2.00, 0.50).
    B1.Rotation := Vector4(0, 1, 0, DegToRad(22.0));
    B1.Scale := Vector3(1.14, 1.88, 0.49);
    Manipulate.SetSelected([B1]);
    Manipulate.RotateSnap := DegToRad(15.0);
    Manipulate.ScaleSnap := 0.25;
    AssertTrue(Manipulate.SnapSelectedRotationAndScaleToGrid);
    AssertSameValue(DegToRad(15.0), B1.Rotation.W, 1e-4);
    AssertVectorEquals(Vector3(1.25, 2.00, 0.50), B1.Scale, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSwapPositionsAndMatchSelectedSize;
var
  Viewport: TCastleViewport;
  B1, B2, B3: TCastleBox;
  Manipulate: TCastleTransformManipulate;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(4, 10, 6);
    B1.Translation := Vector3(1, 2, 3);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 5, 3);
    B2.Translation := Vector3(10, 20, 30);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(8, 20, 12);
    B3.Translation := Vector3(-5, -10, -15);
    Viewport.Items.Add(B3);

    // 1. Swap 2 selected objects: B1 <-> B2
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.SwapSelectedPositions);
    AssertVectorEquals(Vector3(10, 20, 30), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(1, 2, 3), B2.Translation, 1e-4);

    // 2. Cycle 3 selected objects: B1 -> B2's pos, B2 -> B3's pos, B3 -> B1's old pos
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.SwapSelectedPositions);
    AssertVectorEquals(Vector3(1, 2, 3), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-5, -10, -15), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 20, 30), B3.Translation, 1e-4);

    // 3. MatchSelectedSize along Y only (Axis = 1):
    // Primary B1 has world Y size = 10.
    // B2 has Size.Y = 5 (Scale.Y = 1) -> Scale.Y becomes 2.0 (X and Z remain 1.0).
    // B3 has Size.Y = 20 (Scale.Y = 1) -> Scale.Y becomes 0.5 (X and Z remain 1.0).
    AssertTrue(Manipulate.MatchSelectedSize(1));
    AssertVectorEquals(Vector3(1.0, 2.0, 1.0), B2.Scale, 1e-4);
    AssertVectorEquals(Vector3(1.0, 0.5, 1.0), B3.Scale, 1e-4);

    // 4. MatchSelectedSize on all axes (Axis = -1):
    // Primary B1 has world size (4, 10, 6).
    // B2 base Size is (2, 5, 3) -> Scale becomes (2, 2, 2).
    // B3 base Size is (8, 20, 12) -> Scale becomes (0.5, 0.5, 0.5).
    AssertTrue(Manipulate.MatchSelectedSize(-1));
    AssertVectorEquals(Vector3(2.0, 2.0, 2.0), B2.Scale, 1e-4);
    AssertVectorEquals(Vector3(0.5, 0.5, 0.5), B3.Scale, 1e-4);
    AssertVectorEquals(B1.WorldBoundingBox.Size, B2.WorldBoundingBox.Size, 1e-4);
    AssertVectorEquals(B1.WorldBoundingBox.Size, B3.WorldBoundingBox.Size, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

initialization
  RegisterTest(TTestCastleTransformManipulate);
end.

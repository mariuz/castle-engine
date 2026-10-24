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
    procedure TestLookAtAimAndAlignSelectedBounds;
    procedure TestMatchRotationTransformAndArrangeInCircle;
    procedure TestArrangeInGridScalePositionsAndResetTransform;
    procedure TestArrangeLineSeparateOverlappingAndProgressiveTransform;
    procedure TestArrangeWaypointsHelixAndCenterOriginOnChildren;
    procedure TestArrangeBezierArchSphereAndScaleGroupAroundPivot;
    procedure TestArrangeSineWaveEllipseAndReversePositions;
    procedure TestArrangePhyllotaxisDiskStaircaseAndRadialScale;
    procedure TestArrangeTorusZigzagAndNormalizeSizes;
    procedure TestArrangeLissajousCatenaryAndProjectOntoLine;
    procedure TestArrangePolygonSpiralVortexAndProjectOntoPlane;
    procedure TestArrangeTorusKnotConcentricRingsAndProjectSphereCylinder;
    procedure TestArrangeCylinderPyramidAndClampToBox;
    procedure TestArrangeConeHexGridAndPushOutsideBox;
    procedure TestArrangeCubeFrameParaboloidBowlAndSnapToBoxSurface;
    procedure TestArrangeRoseCurveEllipsoidAndShearSelected;
    procedure TestTwistTaperSphericalSpiralAndSuperellipse;
    procedure TestBendVivianiCurveAndSpirograph;
    procedure TestSpherifyMobiusStripAndCardioidHeart;
    procedure TestRippleLemniscateAndTorusHelix;
    procedure TestSquashStretchButterflyAndClelie;
    procedure TestSwirlKnotCurveAndGeodesicDome;
    procedure TestRadialFalloffCycloidAndHyperboloid;
    procedure TestCylindrifyCassiniOvalAndCatenoid;
    procedure TestBarrelHippopedeAndHelicoid;
    procedure TestWaveDeformEnneperAndGearWheel;
    procedure TestSaddleDomeKleinBottleAndFermatSpiral;
    procedure TestOctahedralDeformDiniAndCornuSpiral;
    procedure TestGyroidDeformRomanSurfaceAndCochleoid;
    procedure TestScherkDeformBoysSurfaceAndBicorn;
    procedure TestStereographicCatalanAndCylindricalHarmonic;
    procedure TestDupinCyclideBourSurfaceAndLimacon;
    procedure TestHennebergSphericalEpicycloidAndTalbotCurve;
    procedure TestKuenRichmondAndDevilsCurve;
    procedure TestPluckerSuperellipsoidAndGeronoLemniscate;
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

procedure TTestCastleTransformManipulate.TestLookAtAimAndAlignSelectedBounds;
var
  Viewport: TCastleViewport;
  TargetBox, Observer1, Observer2: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    // TargetBox: Size (4, 10, 6) centered at (0, 5, 0) -> Min = (-2, 0, -3), Max = (2, 10, 3)
    TargetBox := TCastleBox.Create(Viewport);
    TargetBox.Size := Vector3(4, 10, 6);
    TargetBox.Translation := Vector3(0, 5, 0);
    Viewport.Items.Add(TargetBox);

    // Observer1: Size (2, 4, 2) centered at (10, 5, 0) -> MinY = 3, MaxY = 7
    Observer1 := TCastleBox.Create(Viewport);
    Observer1.Size := Vector3(2, 4, 2);
    Observer1.Translation := Vector3(10, 5, 0);
    Viewport.Items.Add(Observer1);

    // Observer2: Size (6, 2, 6) centered at (0, 5, 20) -> MinY = 4, MaxY = 6
    Observer2 := TCastleBox.Create(Viewport);
    Observer2.Size := Vector3(6, 2, 6);
    Observer2.Translation := Vector3(0, 5, 20);
    Viewport.Items.Add(Observer2);

    // 1. Test LookAtWorldPoint: Observer1 at (10, 5, 0) looks at (0, 5, 0) -> Direction (-1, 0, 0)
    Manipulate.SetSelected([Observer1]);
    AssertTrue(Manipulate.LookAtWorldPoint(Vector3(0, 5, 0)));
    Observer1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test AimSelectedAtPrimary: Primary = TargetBox at (0, 5, 0).
    // Observer1 at (10, 5, 0) aims (-1, 0, 0), Observer2 at (0, 5, 20) aims (0, 0, -1).
    Observer1.Rotation := TVector4.Zero;
    Observer2.Rotation := TVector4.Zero;
    Manipulate.SetSelected([TargetBox, Observer1, Observer2]);
    AssertTrue(Manipulate.AimSelectedAtPrimary);
    Observer1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);
    Observer2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-4);

    // 3. Test AlignSelectedBounds along Y (Axis = 1) with UseMaxFace = false (Min face / bottom alignment):
    // TargetBox MinY = 0.0.
    // Observer1 has height 4 (half-height 2) -> Translation.Y becomes 2.0 (MinY = 0.0).
    // Observer2 has height 2 (half-height 1) -> Translation.Y becomes 1.0 (MinY = 0.0).
    Observer1.Rotation := TVector4.Zero;
    Observer2.Rotation := TVector4.Zero;
    AssertTrue(Manipulate.AlignSelectedBounds(1, false));
    AssertSameValue(0.0, Observer1.WorldBoundingBox.Data[0].Y, 1e-4);
    AssertSameValue(0.0, Observer2.WorldBoundingBox.Data[0].Y, 1e-4);
    AssertSameValue(2.0, Observer1.Translation.Y, 1e-4);
    AssertSameValue(1.0, Observer2.Translation.Y, 1e-4);

    // 4. Test AlignSelectedBounds along Y (Axis = 1) with UseMaxFace = true (Max face / top alignment):
    // TargetBox MaxY = 10.0.
    // Observer1 has height 4 (half-height 2) -> Translation.Y becomes 8.0 (MaxY = 10.0).
    // Observer2 has height 2 (half-height 1) -> Translation.Y becomes 9.0 (MaxY = 10.0).
    AssertTrue(Manipulate.AlignSelectedBounds(1, true));
    AssertSameValue(10.0, Observer1.WorldBoundingBox.Data[1].Y, 1e-4);
    AssertSameValue(10.0, Observer2.WorldBoundingBox.Data[1].Y, 1e-4);
    AssertSameValue(8.0, Observer1.Translation.Y, 1e-4);
    AssertSameValue(9.0, Observer2.Translation.Y, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestMatchRotationTransformAndArrangeInCircle;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4: TCastleTransform;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);
    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.CoordSpace := csWorld;

    T1 := TCastleTransform.Create(Viewport);
    T1.SetWorldView(Vector3(1, 2, 3), Vector3(1, 0, 0), Vector3(0, 1, 0));
    T1.Scale := Vector3(2, 3, 4);
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(10, 5, 0);
    Viewport.Items.Add(T2);

    T3 := TCastleTransform.Create(Viewport);
    T3.Translation := Vector3(20, 8, -5);
    Viewport.Items.Add(T3);

    T4 := TCastleTransform.Create(Viewport);
    T4.Translation := Vector3(-30, 0, 5);
    Viewport.Items.Add(T4);

    // 1. Test MatchSelectedRotation: T2 and T3 match T1's world direction (1, 0, 0) while preserving position and scale
    Manipulate.SetSelected([T1, T2, T3]);
    AssertTrue(Manipulate.MatchSelectedRotation);
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(10, 5, 0), WorldPos, 1e-4);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    AssertVectorEquals(Vector3(1, 1, 1), T2.Scale, 1e-4);
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(20, 8, -5), WorldPos, 1e-4);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test MatchSelectedTransform(true, true, true): T2 matches T1's position, rotation, and scale
    Manipulate.SetSelected([T1, T2]);
    AssertTrue(Manipulate.MatchSelectedTransform(true, true, true));
    AssertVectorEquals(Vector3(1, 2, 3), T2.WorldTranslation, 1e-4);
    AssertVectorEquals(Vector3(2, 3, 4), T2.Scale, 1e-4);

    // 3. Test ArrangeSelectedInCircle: arrange 4 transforms around center (0, Y, 0) with Radius = 10, OrientToCenter = true
    T1.Translation := Vector3(-5, 1, 0);
    T2.Translation := Vector3(5, 2, 0);
    T3.Translation := Vector3(0, 3, -5);
    T4.Translation := Vector3(0, 4, 5);
    Manipulate.PivotMode := pmSelectionCenter;
    Manipulate.SetSelected([T1, T2, T3, T4]);
    AssertTrue(Manipulate.ArrangeSelectedInCircle(10.0, 360.0, true));

    // I=0 (0 deg): (0, 1, 10), facing (0, 0, -1)
    T1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 10), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-3);

    // I=1 (90 deg): (10, 2, 0), facing (-1, 0, 0)
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(10, 2, 0), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-3);

    // I=2 (180 deg): (0, 3, -10), facing (0, 0, 1)
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 3, -10), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-3);

    // I=3 (270 deg): (-10, 4, 0), facing (1, 0, 0)
    T4.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-10, 4, 0), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeInGridScalePositionsAndResetTransform;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4: TCastleTransform;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    T1.Translation := Vector3(-10, 5, -10);
    T1.Rotation := Vector4(0, 1, 0, Pi / 4);
    T1.Scale := Vector3(2, 3, 4);
    Viewport.Items.Add(T1);

    T2 := TCastleTransform.Create(Viewport);
    T2.Translation := Vector3(10, -5, -10);
    T2.Rotation := Vector4(1, 0, 0, Pi / 3);
    T2.Scale := Vector3(1.5, 1.5, 1.5);
    Viewport.Items.Add(T2);

    T3 := TCastleTransform.Create(Viewport);
    T3.Translation := Vector3(-10, 0, 10);
    Viewport.Items.Add(T3);

    T4 := TCastleTransform.Create(Viewport);
    T4.Translation := Vector3(10, 0, 10);
    Viewport.Items.Add(T4);

    // 1. Test ArrangeSelectedInGrid (2x2 grid centered at (0, 0, 0), spacing (4, 2, 6))
    Manipulate.SetSelected([T1, T2, T3, T4]);
    AssertTrue(Manipulate.ArrangeSelectedInGrid(2, 2, Vector3(4, 2, 6), true));
    // GridSpan = (4, 0, 6), Center = (0, 0, 0) -> OriginPos = (-2, 0, -3)
    AssertVectorEquals(Vector3(-2, 0, -3), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0, -3), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 0, 3), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0, 3), T4.Translation, 1e-4);

    // 2. Test ScaleSelectedPositionsFromPivot around SelectionCenter (0, 0, 0) by (2, 1, 3)
    Manipulate.PivotMode := pmSelectionCenter;
    AssertTrue(Manipulate.ScaleSelectedPositionsFromPivot(Vector3(2, 1, 3)));
    AssertVectorEquals(Vector3(-4, 0, -9), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 0, -9), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4, 0, 9), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 0, 9), T4.Translation, 1e-4);
    // Individual Scale and Rotation must remain untouched
    AssertVectorEquals(Vector3(2, 3, 4), T1.Scale, 1e-4);
    AssertSameValue(Pi / 4, T1.Rotation.W, 1e-4);

    // 3. Test ResetSelectedTransform (Rotation & Scale only first, then Translation)
    AssertTrue(Manipulate.ResetSelectedTransform(false, true, true));
    AssertVectorEquals(Vector3(-4, 0, -9), T1.Translation, 1e-4);
    AssertSameValue(0.0, T1.Rotation.W, 1e-4);
    AssertVectorEquals(Vector3(1, 1, 1), T1.Scale, 1e-4);
    AssertSameValue(0.0, T2.Rotation.W, 1e-4);
    AssertVectorEquals(Vector3(1, 1, 1), T2.Scale, 1e-4);

    AssertTrue(Manipulate.ResetSelectedTransform(true, false, false));
    AssertVectorEquals(TVector3.Zero, T1.Translation, 1e-4);
    AssertVectorEquals(TVector3.Zero, T2.Translation, 1e-4);
    AssertVectorEquals(TVector3.Zero, T3.Translation, 1e-4);
    AssertVectorEquals(TVector3.Zero, T4.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeLineSeparateOverlappingAndProgressiveTransform;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(0, 1, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(50, 99, -20);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(-40, -10, 15);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(30, 7, 60);
    Viewport.Items.Add(B4);

    // 1. Test ArrangeSelectedBetweenEndpoints: places B2 and B3 at 1/3 and 2/3 along B1 -> B4 and orients along line
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedBetweenEndpoints(true));
    AssertVectorEquals(Vector3(0, 1, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 3, 20), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(20, 5, 40), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(30, 7, 60), B4.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(30, 6, 60).Normalize, WorldDir.Normalize, 1e-3);

    // 2. Test ApplyProgressiveTransformSelected: linear scale gradient (1,1,1) -> (4,4,4) + 30 deg step around Y
    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B4.Rotation := Vector4(0, 1, 0, 0);
    AssertTrue(Manipulate.ApplyProgressiveTransformSelected(
      Vector3(1, 1, 1), Vector3(4, 4, 4), true, 1, Pi / 6));
    AssertVectorEquals(Vector3(1, 1, 1), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(2, 2, 2), B2.Scale, 1e-4);
    AssertVectorEquals(Vector3(3, 3, 3), B3.Scale, 1e-4);
    AssertVectorEquals(Vector3(4, 4, 4), B4.Scale, 1e-4);
    AssertSameValue(0.0, B1.Rotation.W, 1e-4);
    AssertSameValue(Pi / 6, B2.Rotation.W, 1e-4);
    AssertSameValue(2 * Pi / 6, B3.Rotation.W, 1e-4);
    AssertSameValue(3 * Pi / 6, B4.Rotation.W, 1e-4);

    // 3. Test SeparateOverlappingSelected: two 2x2x2 boxes overlapping at X=0 and X=0.5 pushed apart with 1.0 padding
    B1.Scale := Vector3(1, 1, 1);
    B2.Scale := Vector3(1, 1, 1);
    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(0, 5, 0);
    B2.Translation := Vector3(0.5, 5, 0);
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.SeparateOverlappingSelected(1.0, true, 8));
    // Box width is 2, plus 1.0 padding => required center-to-center distance along X is >= 3.0, Y stays 5
    AssertSameValue(5.0, B1.Translation.Y, 1e-4);
    AssertSameValue(5.0, B2.Translation.Y, 1e-4);
    AssertTrue(Abs(B2.Translation.X - B1.Translation.X) >= 3.0 - 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeWaypointsHelixAndCenterOriginOnChildren;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4, T5, ParentGroup: TCastleTransform;
  ChildBox1, ChildBox2: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T1);
    T2 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T2);
    T3 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T3);
    T4 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T4);
    T5 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T5);

    // 1. Test ArrangeSelectedAlongWaypoints along an L-shaped 3-waypoint path:
    // Waypoints: (0,0,0) -> (10,0,0) [len 10] -> (10,0,10) [len 10], total length = 20.
    // 5 items placed at arc distances 0, 5, 10, 15, 20:
    // T1=(0,0,0), T2=(5,0,0), T3=(10,0,0), T4=(10,0,5), T5=(10,0,10)
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedAlongWaypoints(
      [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)], true));
    AssertVectorEquals(Vector3(0, 0, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 0, 0), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 5), T4.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 10), T5.Translation, 1e-4);
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    T4.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInHelix:
    // 5 items around primary selected T1 at (0, 0, 0), StartRadius=10, EndRadius=20, HeightSpan=40, Turns=1.0, OrientToCenter=true
    // Factor = 0, 0.25, 0.5, 0.75, 1.0 -> Angles = 0, 90, 180, 270, 360 deg
    // Radii  = 10, 12.5, 15, 17.5, 20
    // Heights= 0, 10, 20, 30, 40
    T1.Translation := Vector3(0, 0, 0);
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedInHelix(10.0, 20.0, 40.0, 1.0, true));
    AssertVectorEquals(Vector3(0, 0, 10), T1.Translation, 1e-3);
    AssertVectorEquals(Vector3(12.5, 10, 0), T2.Translation, 1e-3);
    AssertVectorEquals(Vector3(0, 20, -15), T3.Translation, 1e-3);
    AssertVectorEquals(Vector3(-17.5, 30, 0), T4.Translation, 1e-3);
    AssertVectorEquals(Vector3(0, 40, 20), T5.Translation, 1e-3);
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-3);

    // 3. Test CenterSelectedOriginOnChildren:
    // ParentGroup at (0, 0, 0) with two 2x4x2 boxes at local/world (10, 2, 4) and (20, 2, 8).
    // Combined world bounding box of children:
    // X in [9..21] (center 15), Y in [0..4] (center 2, min 0), Z in [3..9] (center 6).
    ParentGroup := TCastleTransform.Create(Viewport);
    ParentGroup.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(ParentGroup);

    ChildBox1 := TCastleBox.Create(Viewport);
    ChildBox1.Size := Vector3(2, 4, 2);
    ChildBox1.Translation := Vector3(10, 2, 4);
    ParentGroup.Add(ChildBox1);

    ChildBox2 := TCastleBox.Create(Viewport);
    ChildBox2.Size := Vector3(2, 4, 2);
    ChildBox2.Translation := Vector3(20, 2, 8);
    ParentGroup.Add(ChildBox2);

    Manipulate.SetSelected([ParentGroup]);
    // 3a. Center on children bounding box center (UseBottomCenter = false) -> Parent moves to (15, 2, 6), children stay at world (10, 2, 4) & (20, 2, 8)
    AssertTrue(Manipulate.CenterSelectedOriginOnChildren(false));
    AssertVectorEquals(Vector3(15, 2, 6), ParentGroup.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 2, 4), ChildBox1.WorldTranslation, 1e-4);
    AssertVectorEquals(Vector3(20, 2, 8), ChildBox2.WorldTranslation, 1e-4);
    AssertVectorEquals(Vector3(-5, 0, -2), ChildBox1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 0, 2), ChildBox2.Translation, 1e-4);

    // 3b. Center on children bottom-center (UseBottomCenter = true) -> Parent moves to (15, 0, 6), children stay at world (10, 2, 4) & (20, 2, 8)
    AssertTrue(Manipulate.CenterSelectedOriginOnChildren(true));
    AssertVectorEquals(Vector3(15, 0, 6), ParentGroup.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 2, 4), ChildBox1.WorldTranslation, 1e-4);
    AssertVectorEquals(Vector3(20, 2, 8), ChildBox2.WorldTranslation, 1e-4);
    AssertVectorEquals(Vector3(-5, 2, -2), ChildBox1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 2, 2), ChildBox2.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeBezierArchSphereAndScaleGroupAroundPivot;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4, T5: TCastleTransform;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T1);
    T2 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T2);
    T3 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T3);
    T4 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T4);
    T5 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T5);

    // 1. Test ArrangeSelectedInParabolicArchBetweenEndpoints:
    // Start T1 at (0, 0, 0), End T5 at (20, 0, 0), ApexHeight = 10 -> ControlPoint = (10, 20, 0).
    // At t = 0.5 (T3), B(0.5) = 0.25*(0,0,0) + 0.5*(10,20,0) + 0.25*(20,0,0) = (10, 10, 0),
    // and tangent is horizontal (1, 0, 0).
    // At t = 0.25 (T2), B(0.25) = (5, 7.5, 0).
    // At t = 0.75 (T4), B(0.75) = (15, 7.5, 0).
    T1.Translation := Vector3(0, 0, 0);
    T5.Translation := Vector3(20, 0, 0);
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedInParabolicArchBetweenEndpoints(10.0, true));
    AssertVectorEquals(Vector3(0, 0, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 7.5, 0), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 10, 0), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(15, 7.5, 0), T4.Translation, 1e-4);
    AssertVectorEquals(Vector3(20, 0, 0), T5.Translation, 1e-4);
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedOnSphere:
    // Primary selected T1 at (0, 0, 0), Radius = 10, MinElevation = 0 (hemisphere dome), MaxElevation = 90, OrientOutward = true.
    // All 5 items must lie at distance 10 from (0,0,0), have Y >= 0, and look outward along their radial direction.
    T1.Translation := Vector3(0, 0, 0);
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedOnSphere(10.0, 0.0, 90.0, true));
    AssertSameValue(10.0, T1.Translation.Length, 1e-3);
    AssertSameValue(10.0, T2.Translation.Length, 1e-3);
    AssertSameValue(10.0, T3.Translation.Length, 1e-3);
    AssertSameValue(10.0, T4.Translation.Length, 1e-3);
    AssertSameValue(10.0, T5.Translation.Length, 1e-3);
    AssertTrue(T1.Translation.Y >= -1e-4);
    AssertTrue(T5.Translation.Y >= -1e-4);
    // First item (I=0, Factor=0) is at MinElevation 0 deg -> equator (10, 0, 0)
    AssertVectorEquals(Vector3(10, 0, 0), T1.Translation, 1e-3);
    // Last item (I=4, Factor=1) is at MaxElevation 90 deg -> top pole (0, 10, 0)
    AssertVectorEquals(Vector3(0, 10, 0), T5.Translation, 1e-3);
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(T3.Translation.Normalize, WorldDir.Normalize, 1e-3);

    // 3. Test ScaleSelectedGroupAroundPivot:
    // Primary selected T1 at (10, 5, 0) with Scale (1, 1, 1), T2 at (14, 9, -2) with Scale (2, 3, 4).
    // Scaling around primary selected T1 by Factor (2, 0.5, 3):
    // T1 stays at (10, 5, 0), Scale becomes (2, 0.5, 3).
    // T2 offset from T1 was (4, 4, -2) -> new offset (8, 2, -6) -> T2 moves to (18, 7, -6), Scale becomes (4, 1.5, 12).
    T1.Translation := Vector3(10, 5, 0);
    T1.Scale := Vector3(1, 1, 1);
    T2.Translation := Vector3(14, 9, -2);
    T2.Scale := Vector3(2, 3, 4);
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.SetSelected([T1, T2]);
    AssertTrue(Manipulate.ScaleSelectedGroupAroundPivot(Vector3(2.0, 0.5, 3.0)));
    AssertVectorEquals(Vector3(10, 5, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0.5, 3), T1.Scale, 1e-4);
    AssertVectorEquals(Vector3(18, 7, -6), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 1.5, 12), T2.Scale, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeSineWaveEllipseAndReversePositions;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4, T5: TCastleTransform;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T1);
    T2 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T2);
    T3 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T3);
    T4 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T4);
    T5 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T5);

    // 1. Test ArrangeSelectedInSineWaveBetweenEndpoints:
    // Start T1 at (0, 0, 0), End T5 at (20, 0, 0), Amplitude = 6, Cycles = 1.0, WaveAxis = 1 (Y), OrientAlongWave = true.
    // Factors for 5 items: 0.0, 0.25, 0.5, 0.75, 1.0
    // Sin(2*Pi*t): 0, +1, 0, -1, 0 -> Y values: 0, +6, 0, -6, 0.
    // At t = 0.25 (T2, wave crest), Cos(Pi/2) = 0 -> tangent is purely horizontal (1, 0, 0).
    T1.Translation := Vector3(0, 0, 0);
    T5.Translation := Vector3(20, 0, 0);
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedInSineWaveBetweenEndpoints(6.0, 1.0, 1, true));
    AssertVectorEquals(Vector3(0, 0, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 6, 0), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(15, -6, 0), T4.Translation, 1e-4);
    AssertVectorEquals(Vector3(20, 0, 0), T5.Translation, 1e-4);
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInEllipse:
    // 4 transforms centered at (0, Y, 0) with RadiusX = 12, RadiusZ = 6, OrientMode = 2 (tangent).
    // I=0 (Angle=0): (12, 1, 0), tangent (0, 0, 1)
    // I=1 (Angle=Pi/2): (0, 2, 6), tangent (-1, 0, 0)
    // I=2 (Angle=Pi): (-12, 3, 0), tangent (0, 0, -1)
    // I=3 (Angle=3*Pi/2): (0, 4, -6), tangent (1, 0, 0)
    T1.Translation := Vector3(-2, 1, 0);
    T2.Translation := Vector3(2, 2, 0);
    T3.Translation := Vector3(0, 3, -2);
    T4.Translation := Vector3(0, 4, 2);
    Manipulate.PivotMode := pmSelectionCenter;
    Manipulate.SetSelected([T1, T2, T3, T4]);
    AssertTrue(Manipulate.ArrangeSelectedInEllipse(12.0, 6.0, 2));
    T1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(12, 1, 0), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-3);
    T2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 2, 6), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-3);
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-12, 3, 0), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-3);
    T4.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 4, -6), WorldPos, 1e-3);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-3);

    // 3. Test ReverseSelectedPositions(true, true):
    // Reverses positions, rotations, and scales of [T1, T2, T3, T4].
    T1.Scale := Vector3(1, 1, 1);
    T2.Scale := Vector3(2, 2, 2);
    T3.Scale := Vector3(3, 3, 3);
    T4.Scale := Vector3(4, 4, 4);
    Manipulate.SetSelected([T1, T2, T3, T4]);
    AssertTrue(Manipulate.ReverseSelectedPositions(true, true));
    AssertVectorEquals(Vector3(0, 4, -6), T1.Translation, 1e-3);
    AssertVectorEquals(Vector3(4, 4, 4), T1.Scale, 1e-3);
    T1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-3);

    AssertVectorEquals(Vector3(-12, 3, 0), T2.Translation, 1e-3);
    AssertVectorEquals(Vector3(3, 3, 3), T2.Scale, 1e-3);

    AssertVectorEquals(Vector3(0, 2, 6), T3.Translation, 1e-3);
    AssertVectorEquals(Vector3(2, 2, 2), T3.Scale, 1e-3);

    AssertVectorEquals(Vector3(12, 1, 0), T4.Translation, 1e-3);
    AssertVectorEquals(Vector3(1, 1, 1), T4.Scale, 1e-3);
    T4.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangePhyllotaxisDiskStaircaseAndRadialScale;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  T1, T2, T3, T4, T5: TCastleTransform;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif} HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif} HandleTransformModifyEnd;

    T1 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T1);
    T2 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T2);
    T3 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T3);
    T4 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T4);
    T5 := TCastleTransform.Create(Viewport);
    Viewport.Items.Add(T5);

    // 1. Test ArrangeSelectedInPhyllotaxisDisk:
    // Primary selected T1 at (0, 2, 0), OuterRadius = 10, OrientMode = 2 (outward).
    // For 5 items (I = 0..4), distances from (0, *, 0) in XZ are 10 * Sqrt(I / 4):
    // I=0 -> 0.0, I=1 -> 5.0, I=2 -> 10*Sqrt(0.5), I=3 -> 10*Sqrt(0.75), I=4 -> 10.0.
    // Y elevations must remain unchanged.
    T1.Translation := Vector3(0, 2, 0);
    T2.Translation := Vector3(1, 3, 1);
    T3.Translation := Vector3(2, 4, 2);
    T4.Translation := Vector3(3, 5, 3);
    T5.Translation := Vector3(4, 6, 4);
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedInPhyllotaxisDisk(10.0, 2));
    AssertSameValue(0.0, Hypot(T1.Translation.X, T1.Translation.Z), 1e-3);
    AssertSameValue(5.0, Hypot(T2.Translation.X, T2.Translation.Z), 1e-3);
    AssertSameValue(10.0 * Sqrt(0.5), Hypot(T3.Translation.X, T3.Translation.Z), 1e-3);
    AssertSameValue(10.0 * Sqrt(0.75), Hypot(T4.Translation.X, T4.Translation.Z), 1e-3);
    AssertSameValue(10.0, Hypot(T5.Translation.X, T5.Translation.Z), 1e-3);
    AssertSameValue(2.0, T1.Translation.Y, 1e-4);
    AssertSameValue(6.0, T5.Translation.Y, 1e-4);
    // Outward orientation on T5 matches its XZ radial vector
    T5.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(T5.Translation.X, 0, T5.Translation.Z).Normalize, WorldDir.Normalize, 1e-3);

    // 2. Test ScaleSelectedRadialDistanceXZ:
    // Scaling XZ radial distance from primary T1 (0, 2, 0) by 2.0 doubles all XZ radii while preserving Y:
    AssertTrue(Manipulate.ScaleSelectedRadialDistanceXZ(2.0));
    AssertSameValue(0.0, Hypot(T1.Translation.X, T1.Translation.Z), 1e-3);
    AssertSameValue(10.0, Hypot(T2.Translation.X, T2.Translation.Z), 1e-3);
    AssertSameValue(20.0, Hypot(T5.Translation.X, T5.Translation.Z), 1e-3);
    AssertSameValue(3.0, T2.Translation.Y, 1e-4);
    AssertSameValue(6.0, T5.Translation.Y, 1e-4);

    // 3. Test ArrangeSelectedInStaircaseBetweenEndpoints:
    // Start T1 at (0, 0, 0), End T5 at (0, 16, 20), CurveExponent = 2.0 (quadratic concave grand stairs), OrientHorizontallyAlongRun = true.
    // Factors for 5 items: 0.0, 0.25, 0.5, 0.75, 1.0
    // Z values (linear): 0, 5, 10, 15, 20
    // Y values (16 * t^2): 0, 1, 4, 9, 16
    // Orientation: horizontal along +Z (0, 0, 1) with Up = (0, 1, 0).
    T1.Translation := Vector3(0, 0, 0);
    T5.Translation := Vector3(0, 16, 20);
    Manipulate.SetSelected([T1, T2, T3, T4, T5]);
    AssertTrue(Manipulate.ArrangeSelectedInStaircaseBetweenEndpoints(2.0, true));
    AssertVectorEquals(Vector3(0, 0, 0), T1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 1, 5), T2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 4, 10), T3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 9, 15), T4.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 16, 20), T5.Translation, 1e-4);
    T3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-4);
    AssertVectorEquals(Vector3(0, 1, 0), WorldUp.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeTorusZigzagAndNormalizeSizes;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
  AvgDiag: Single;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := @HandleTransformModified;
    Manipulate.OnTransformModifyEnd := @HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);

    Viewport.Items.Add(B1);
    Viewport.Items.Add(B2);
    Viewport.Items.Add(B3);
    Viewport.Items.Add(B4);

    // 1. Test ArrangeSelectedOnTorus:
    // MajorRadius = 10, MinorRadius = 2, MinorTurns = 1.0, OrientMode = 1 (tube outward normal), Center = (0,0,0).
    // For 4 items (I = 0..3), Theta = Phi = 0, Pi/2, Pi, 3*Pi/2:
    // I=0 (Theta=0, Phi=0): RingR = 12 -> Pos = (12, 0, 0), TubeCenter = (10, 0, 0) -> Normal = (1, 0, 0)
    // I=1 (Theta=Pi/2, Phi=Pi/2): RingR = 10 -> Pos = (0, 2, 10), TubeCenter = (0, 0, 10) -> Normal = (0, 1, 0)
    // I=2 (Theta=Pi, Phi=Pi): RingR = 8 -> Pos = (-8, 0, 0), TubeCenter = (-10, 0, 0) -> Normal = (1, 0, 0)
    // I=3 (Theta=3*Pi/2, Phi=3*Pi/2): RingR = 10 -> Pos = (0, -2, -10), TubeCenter = (0, 0, -10) -> Normal = (0, -1, 0)
    B1.Translation := Vector3(0, 0, 0);
    Manipulate.PivotMode := pmPrimarySelected;
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedOnTorus(10.0, 2.0, 1.0, 1));
    AssertVectorEquals(Vector3(12, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 2, 10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -2, -10), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInZigzag:
    // Start = (0, 0, 0), End = (0, 0, 30), LateralOffset = 4.0, OrientMode = 2 (orient inward toward corridor).
    // LineDir = (0, 0, 1), GravityUp = (0, 1, 0) -> SideVec = Cross((0,0,1), (0,1,0)) = (-1, 0, 0).
    // I=0 (Sign=+1): Pos = (0,0,0) + (-4,0,0) = (-4, 0, 0), Inward Dir = +1 * (1, 0, 0) = (1, 0, 0)
    // I=1 (Sign=-1): Pos = (0,0,10) + (4,0,0) = (4, 0, 10), Inward Dir = (-1, 0, 0)
    // I=2 (Sign=+1): Pos = (-4, 0, 20), Inward Dir = (1, 0, 0)
    // I=3 (Sign=-1): Pos = (4, 0, 30), Inward Dir = (-1, 0, 0)
    AssertTrue(Manipulate.ArrangeSelectedInZigzag(Vector3(0, 0, 0), Vector3(0, 0, 30), 4.0, 2));
    AssertVectorEquals(Vector3(-4, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 0, 10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4, 0, 20), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 0, 30), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test NormalizeSelectedSizes:
    // Reset rotations and give B1..B4 non-uniform sizes via Scale: 1x, 2x, 3x, 6x (mean = 3.0x).
    Manipulate.ResetSelectedTransform(false, true, false);
    B1.Scale := Vector3(1, 1, 1);
    B2.Scale := Vector3(2, 2, 2);
    B3.Scale := Vector3(3, 3, 3);
    B4.Scale := Vector3(6, 6, 6);
    AssertTrue(Manipulate.NormalizeSelectedSizes(true));
    AssertVectorEquals(Vector3(3, 3, 3), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(3, 3, 3), B2.Scale, 1e-4);
    AssertVectorEquals(Vector3(3, 3, 3), B3.Scale, 1e-4);
    AssertVectorEquals(Vector3(3, 3, 3), B4.Scale, 1e-4);
    AvgDiag := B1.WorldBoundingBox.Size.Length;
    AssertSameValue(AvgDiag, B4.WorldBoundingBox.Size.Length, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeLissajousCatenaryAndProjectOntoLine;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(-6, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(6, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedInLissajous:
    // Center = (0, 0, 0), RadiusX = 8, RadiusZ = 4, FreqX = 1, FreqZ = 2, VerticalAmplitude = 2, OrientMode = 2 (tangent).
    AssertTrue(Manipulate.ArrangeSelectedInLissajous(8.0, 4.0, 1.0, 2.0, 2.0, 2));
    AssertVectorEquals(Vector3(0, 2, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(8, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -2, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8, 0, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1 / Sqrt(2), 0, 1 / Sqrt(2)), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInCatenary on 3 items:
    // Start = (0, 10, 0), End = (20, 10, 0), SagDepth = 5.0, OrientAlongCurve = true.
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedInCatenary(Vector3(0, 10, 0), Vector3(20, 10, 0), 5.0, true));
    AssertVectorEquals(Vector3(0, 10, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 5, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(20, 10, 0), B3.Translation, 1e-4);
    // At midpoint (u = 0), catenary tangent is horizontal along chord (1, 0, 0):
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test ProjectSelectedOntoLineBetweenEndpoints:
    // Place B1 at (0,0,0), B2 at (4, 7, -3), B3 at (-5, 3, 2), B4 at (20,0,0).
    // With ClampToSegment = true and OrientAlongLine = true:
    // B2 projects to (4, 0, 0); B3 has t = -0.25 -> clamped to 0 -> (0, 0, 0).
    B1.Translation := Vector3(0, 0, 0);
    B2.Translation := Vector3(4, 7, -3);
    B3.Translation := Vector3(-5, 3, 2);
    B4.Translation := Vector3(20, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ProjectSelectedOntoLineBetweenEndpoints(true, true));
    AssertVectorEquals(Vector3(0, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(20, 0, 0), B4.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangePolygonSpiralVortexAndProjectOntoPlane;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(-6, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(6, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedInPolygon:
    // Sides = 4, OuterRadius = 10, InnerRadius = 0, OrientMode = 2 (along edge V1 - V0).
    AssertTrue(Manipulate.ArrangeSelectedInPolygon(4, 10.0, 0.0, 2));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -10), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1 / Sqrt(2), 0, 1 / Sqrt(2)), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInSpiralVortex:
    // Center = (0, 0, 0), StartRadius = 2, EndRadius = 16, Turns = 1.0, HeightSpan = 6.0, Logarithmic = true, OrientMode = 1 (inward).
    // t = 0, 1/3, 2/3, 1 -> r = 2 * 8^t = 2, 4, 8, 16; Theta = 0, 120 deg, 240 deg, 360 deg.
    Manipulate.ResetSelectedTransform(true, true, false);
    AssertTrue(Manipulate.ArrangeSelectedInSpiralVortex(2.0, 16.0, 1.0, 6.0, true, 1));
    AssertVectorEquals(Vector3(2, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 2, 2 * Sqrt(3)), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4, 4, -4 * Sqrt(3)), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(16, 6, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test ProjectSelectedOntoPlaneThreePoints and ProjectSelectedOntoPlane:
    // B1=(0,0,0), B2=(3, 9, 4), B3=(10,0,0), B4=(0,0,10).
    // Three-point plane uses B1(0), B3(2), B4(3) -> plane Y = 0, so B2 projects to (3, 0, 4).
    B1.Translation := Vector3(0, 0, 0);
    B2.Translation := Vector3(3, 9, 4);
    B3.Translation := Vector3(10, 0, 0);
    B4.Translation := Vector3(0, 0, 10);
    AssertTrue(Manipulate.ProjectSelectedOntoPlaneThreePoints(false));
    AssertVectorEquals(Vector3(0, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(3, 0, 4), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 10), B4.Translation, 1e-4);

    // Project onto plane Y = 5 with normal (0, 1, 0) and AlignUpToNormal = true:
    AssertTrue(Manipulate.ProjectSelectedOntoPlane(Vector3(0, 5, 0), Vector3(0, 1, 0), true));
    AssertVectorEquals(Vector3(3, 5, 4), B2.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 0), WorldUp.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeTorusKnotConcentricRingsAndProjectSphereCylinder;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(-6, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(6, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedInTorusKnot:
    // Center = (0,0,0), MajorRadius = 10, TubeRadius = 2, KnotP = 2, KnotQ = 3, OrientMode = 1 (tube normal).
    // Theta = 0, pi/2, pi, 3pi/2:
    // i=0 (Theta=0): p*Theta=0, q*Theta=0 -> r=12, Pos=(12, 0, 0), Core=(10, 0, 0) -> Dir=(1, 0, 0)
    // i=1 (Theta=pi/2): p*Theta=pi, q*Theta=3pi/2 -> cosQ=0, sinQ=-1 -> r=10, Pos=(-10, -2, 0)
    // i=2 (Theta=pi): p*Theta=2pi, q*Theta=3pi -> cosQ=-1, sinQ=0 -> r=8, Pos=(8, 0, 0), Core=(10, 0, 0) -> Dir=(-1, 0, 0)
    // i=3 (Theta=3pi/2): p*Theta=3pi, q*Theta=9pi/2 -> cosQ=0, sinQ=1 -> r=10, Pos=(-10, 2, 0)
    AssertTrue(Manipulate.ArrangeSelectedInTorusKnot(10.0, 2.0, 2, 3, 1));
    AssertVectorEquals(Vector3(12, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, -2, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(8, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 2, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInConcentricRings:
    // Center returns to (0,0,0) after reset; FirstRingRadius = 4, RingSpacing = 6, RingRiseY = 3, BaseRingCount = 2, OrientMode = 1 (inward).
    // Ring 0 has capacity 2 (B1 at Theta=0 -> (4, 0, 0), B2 at Theta=pi -> (-4, 0, 0)).
    // Ring 1 has 2 remaining items (B3 at Theta=0 -> (10, 3, 0), B4 at Theta=pi -> (-10, 3, 0)).
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInConcentricRings(4.0, 6.0, 3.0, 2, 1));
    AssertVectorEquals(Vector3(4, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 3, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 3, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test ProjectSelectedOntoSphere and ProjectSelectedOntoCylinder:
    // Place B1=(2, 0, 0), B2=(-6, 0, 0), B3=(0, 3, 0), B4=(4, -3, 0) -> Center = (0, 0, 0).
    B1.Translation := Vector3(2, 0, 0);
    B2.Translation := Vector3(-6, 0, 0);
    B3.Translation := Vector3(0, 3, 0);
    B4.Translation := Vector3(4, -3, 0);
    AssertTrue(Manipulate.ProjectSelectedOntoSphere(10.0, true));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 10, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(8, -6, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // ProjectSelectedOntoCylinder(5.0, true) preserves Y while snapping XZ distance to 5.0:
    B1.Translation := Vector3(3, 7, 4);
    B2.Translation := Vector3(-3, -7, -4);
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.ProjectSelectedOntoCylinder(10.0, true));
    AssertVectorEquals(Vector3(6, 7, 8), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-6, -7, -8), B2.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.6, 0, 0.8), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeCylinderPyramidAndClampToBox;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  RoomBox, B1, B2, B3, B4, B5: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(-4, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B4);

    B5 := TCastleBox.Create(Viewport);
    B5.Size := Vector3(2, 2, 2);
    B5.Translation := Vector3(4, 0, 0);
    Viewport.Items.Add(B5);

    Manipulate.SetSelected([B1, B2, B3, B4, B5]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedOnCylinder(10.0, 20.0, 2):
    // Center = (0, 0, 0). Every item has XZ radius = 10.0, Y from -10 to +10 in steps of 5,
    // and outward horizontal orientation:
    AssertTrue(Manipulate.ArrangeSelectedOnCylinder(10.0, 20.0, 2));
    AssertVectorEquals(Vector3(10, -10, 0), B1.Translation, 1e-4);
    AssertSameValue(10.0, Hypot(B2.Translation.X, B2.Translation.Z), 1e-4);
    AssertSameValue(-5.0, B2.Translation.Y, 1e-4);
    AssertSameValue(10.0, Hypot(B3.Translation.X, B3.Translation.Z), 1e-4);
    AssertSameValue(0.0, B3.Translation.Y, 1e-4);
    AssertSameValue(10.0, Hypot(B5.Translation.X, B5.Translation.Z), 1e-4);
    AssertSameValue(10.0, B5.Translation.Y, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInPyramid(4.0, 3.0, 1):
    // Reset positions so Center = (0, 0, 0).
    // With 5 items: TotalLayers = 2 (Layer 0 has 1x1=1 item at Y = 3.0; Layer 1 has 2x2=4 items at Y = 0.0).
    // Layer 0: B1 at (0, 3, 0).
    // Layer 1 (2x2 with spacing 4.0):
    //   B2 (row=0, col=0): (-2, 0, -2)
    //   B3 (row=0, col=1): ( 2, 0, -2)
    //   B4 (row=1, col=0): (-2, 0,  2)
    //   B5 (row=1, col=1): ( 2, 0,  2)
    B1.Translation := Vector3(-4, 0, 0);
    B2.Translation := Vector3(-2, 0, 0);
    B3.Translation := Vector3(0, 0, 0);
    B4.Translation := Vector3(2, 0, 0);
    B5.Translation := Vector3(4, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInPyramid(4.0, 3.0, 1));
    AssertVectorEquals(Vector3(0, 3, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 0, -2), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0, -2), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 0, 2), B4.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0, 2), B5.Translation, 1e-4);

    // 3. Test ClampSelectedToBox and ClampSelectedToPrimaryBounds:
    // RoomBox has Size (20, 10, 20) at (0, 5, 0) -> WorldBoundingBox is [-10..10] x [0..10] x [-10..10].
    // B1..B3 have Size (2, 2, 2) (half-extent 1.0 on each axis).
    // When UseObjectBounds = true, their centers must be clamped to [-9..9] x [1..9] x [-9..9]!
    RoomBox := TCastleBox.Create(Viewport);
    RoomBox.Size := Vector3(20, 10, 20);
    RoomBox.Translation := Vector3(0, 5, 0);
    Viewport.Items.Add(RoomBox);

    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(-25, -5, 30);
    B2.Translation := Vector3(15, 20, -12);
    B3.Translation := Vector3(3, 4, -2); // already inside
    Manipulate.SetSelected([RoomBox, B1, B2, B3]);
    AssertTrue(Manipulate.ClampSelectedToPrimaryBounds(true));
    AssertVectorEquals(Vector3(-9, 1, 9), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(9, 9, -9), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(3, 4, -2), B3.Translation, 1e-4);

    // Also test ClampSelectedToBox with UseObjectBounds = false (clamps origins to [-5..5]):
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.ClampSelectedToBox(Vector3(-5, 2, -5), Vector3(5, 8, 5), false));
    AssertVectorEquals(Vector3(-5, 2, 5), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 8, -5), B2.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeConeHexGridAndPushOutsideBox;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  RoomBox, B1, B2, B3, B4, B5: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
  ExpectedStep: Single;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(-4, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B4);

    B5 := TCastleBox.Create(Viewport);
    B5.Size := Vector3(2, 2, 2);
    B5.Translation := Vector3(4, 0, 0);
    Viewport.Items.Add(B5);

    Manipulate.SetSelected([B1, B2, B3, B4, B5]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedOnCone(10.0, 2.0, 16.0, 2):
    // Center = (0, 0, 0). BaseRadius = 10.0, TopRadius = 2.0, HeightSpan = 16.0.
    // B1 (t=0): radius 10.0, theta=0, Y = -8.0 -> (10, -8, 0)
    // B3 (t=0.5): radius 6.0, Y = 0.0
    // B5 (t=1.0): radius 2.0, Y = 8.0
    AssertTrue(Manipulate.ArrangeSelectedOnCone(10.0, 2.0, 16.0, 2));
    AssertVectorEquals(Vector3(10, -8, 0), B1.Translation, 1e-4);
    AssertSameValue(6.0, Hypot(B3.Translation.X, B3.Translation.Z), 1e-4);
    AssertSameValue(0.0, B3.Translation.Y, 1e-4);
    AssertSameValue(2.0, Hypot(B5.Translation.X, B5.Translation.Z), 1e-4);
    AssertSameValue(8.0, B5.Translation.Y, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(16.0, 8.0, 0.0).Normalize, WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInHexGrid(2, 4.0, 1):
    // Reset positions of B1..B4 so Center = (0, 0, 0).
    // With CellRadius = 4.0, every hexagonal neighbor (same-row B1-B2 and diagonal B1-B3, B2-B3, B2-B4)
    // is equidistant at 4 * Sqrt(3) = 6.92820323!
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInHexGrid(2, 4.0, 1));
    ExpectedStep := 4.0 * Sqrt(3.0);
    AssertSameValue(ExpectedStep, PointsDistance(B1.Translation, B2.Translation), 1e-4);
    AssertSameValue(ExpectedStep, PointsDistance(B1.Translation, B3.Translation), 1e-4);
    AssertSameValue(ExpectedStep, PointsDistance(B2.Translation, B3.Translation), 1e-4);
    AssertSameValue(ExpectedStep, PointsDistance(B2.Translation, B4.Translation), 1e-4);
    AssertSameValue(ExpectedStep, PointsDistance(B3.Translation, B4.Translation), 1e-4);

    // 3. Test PushSelectedOutsidePrimaryBounds and PushSelectedOutsideBox:
    // RoomBox has Size (20, 10, 20) at (0, 5, 0) -> WorldBoundingBox is [-10..10] x [0..10] x [-10..10].
    RoomBox := TCastleBox.Create(Viewport);
    RoomBox.Size := Vector3(20, 10, 20);
    RoomBox.Translation := Vector3(0, 5, 0);
    Viewport.Items.Add(RoomBox);

    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(8.5, 5, 0);  // closest exit is +X face (10.0) -> center at 11.0
    B2.Translation := Vector3(0, 8.8, 0);  // closest exit is +Y face (10.0) -> center at 11.0
    B3.Translation := Vector3(25, 5, 0);   // already outside -> unchanged
    Manipulate.SetSelected([RoomBox, B1, B2, B3]);
    AssertTrue(Manipulate.PushSelectedOutsidePrimaryBounds(true));
    AssertVectorEquals(Vector3(11, 5, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 11, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(25, 5, 0), B3.Translation, 1e-4);

    // Also test PushSelectedOutsideBox with UseObjectBounds = false (origin push):
    B1.Translation := Vector3(-4.2, 5, 0);
    Manipulate.SetSelected([B1]);
    AssertTrue(Manipulate.PushSelectedOutsideBox(Vector3(-5, 0, -5), Vector3(5, 10, 5), false));
    AssertVectorEquals(Vector3(-5, 5, 0), B1.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeCubeFrameParaboloidBowlAndSnapToBoxSurface;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  RoomBox, B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(-3, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(-1, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(1, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(3, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedOnCubeFrame(Vector3(5, 5, 5), false, 1):
    // Center = (0, 0, 0). Total perimeter across 12 edges of length 10 = 120.
    // B1 (i=0, dist=0) -> (-5, -5, -5)
    // B2 (i=1, dist=30) -> edge 3 start (-5, -5, 5)
    // B3 (i=2, dist=60) -> edge 6 start (5, 5, 5)
    // B4 (i=3, dist=90) -> edge 9 start (5, -5, -5)
    AssertTrue(Manipulate.ArrangeSelectedOnCubeFrame(Vector3(5, 5, 5), false, 1));
    AssertVectorEquals(Vector3(-5, -5, -5), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-5, -5, 5), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 5, 5), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, -5, -5), B4.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 1, 1).Normalize, WorldDir.Normalize, 1e-4);

    // Also test ShellMode = true (K=2 -> 8 corners of [-4..4]^3):
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedOnCubeFrame(Vector3(4, 4, 4), true, 2));
    AssertVectorEquals(Vector3(-4, -4, -4), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, -4, -4), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4, -4, 4), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(4, -4, 4), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 1, 1).Normalize, WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInParaboloidBowl(8.0, 10.0, 1):
    // Reset positions so Center = (0, 0, 0). N = 4:
    // u_i = (i + 0.5) / 4 -> u_0 = 0.125, u_1 = 0.375, u_2 = 0.625, u_3 = 0.875.
    // Every point must satisfy the paraboloid equation:
    // Y = DepthY * ((X^2 + Z^2) / RimRadius^2 - 0.5)!
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInParaboloidBowl(8.0, 10.0, 1));
    AssertSameValue(8.0 * Sqrt(0.125), Hypot(B1.Translation.X, B1.Translation.Z), 1e-4);
    AssertSameValue(10.0 * (0.125 - 0.5), B1.Translation.Y, 1e-4);
    AssertSameValue(8.0 * Sqrt(0.875), Hypot(B4.Translation.X, B4.Translation.Z), 1e-4);
    AssertSameValue(10.0 * (0.875 - 0.5), B4.Translation.Y, 1e-4);

    // 3. Test SnapSelectedToPrimaryBoundsSurface and SnapSelectedToBoxSurface:
    // RoomBox has Size (20, 10, 20) at (0, 5, 0) -> WorldBoundingBox is [-10..10] x [0..10] x [-10..10].
    // B1..B3 have Size (2, 2, 2) (half-extent 1.0).
    RoomBox := TCastleBox.Create(Viewport);
    RoomBox.Size := Vector3(20, 10, 20);
    RoomBox.Translation := Vector3(0, 5, 0);
    Viewport.Items.Add(RoomBox);

    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(14, 5, 25);  // closest face is +X (dist 4 vs Z dist 15), Z clamped to 10, X snapped to 10 + 1 = 11
    B2.Translation := Vector3(0, 9.2, -3); // closest face is +Y (dist 0.8), Y snapped to 10 + 1 = 11
    B3.Translation := Vector3(-2, 4, -9.5); // closest face is -Z (dist 0.5), Z snapped to -10 - 1 = -11
    Manipulate.SetSelected([RoomBox, B1, B2, B3]);
    AssertTrue(Manipulate.SnapSelectedToPrimaryBoundsSurface(true, true));
    AssertVectorEquals(Vector3(11, 5, 10), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 11, -3), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 4, -11), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-4);

    // Also test SnapSelectedToBoxSurface with FlushOutside = false (origin snapped to face):
    B1.Translation := Vector3(-4.6, 5, 0);
    Manipulate.SetSelected([B1]);
    AssertTrue(Manipulate.SnapSelectedToBoxSurface(Vector3(-5, 0, -5), Vector3(5, 10, 5), false, false));
    AssertVectorEquals(Vector3(-5, 5, 0), B1.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestArrangeRoseCurveEllipsoidAndShearSelected;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp, ExpectedNormal: TVector3;
  EllipsoidEq: Single;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(-3, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(-1, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(1, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(3, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test ArrangeSelectedInRoseCurve(10.0, 2.0, 4.0, 2):
    // Center = (0, 0, 0). N = 4 -> theta_i = 0, pi/2, pi, 3pi/2.
    // For k = 2:
    // i=0 (theta=0): cos(0)=1, sin(0)=0 -> r=10, pos=(10, 0, 0), tangent=(0, 8, 10)
    // i=1 (theta=pi/2): cos(pi)=-1, sin(pi)=0 -> r=-10, pos=(0, 0, -10)
    // i=2 (theta=pi): cos(2pi)=1, sin(2pi)=0 -> r=10, pos=(-10, 0, 0)
    // i=3 (theta=3pi/2): cos(3pi)=-1, sin(3pi)=0 -> r=-10, pos=(0, 0, 10)
    AssertTrue(Manipulate.ArrangeSelectedInRoseCurve(10.0, 2.0, 4.0, 2));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 10), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 8, 10).Normalize, WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedOnEllipsoid(Vector3(10, 5, 8), true, 1):
    // Reset positions so Center = (0, 0, 0). UpperHemisphereOnly = true (Y > 0).
    // Every placed transform must lie on the ellipsoid (X/10)^2 + (Y/5)^2 + (Z/8)^2 = 1
    // and have Y > 0, with WorldDir aligned to the outward ellipsoid normal!
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedOnEllipsoid(Vector3(10, 5, 8), true, 1));
    EllipsoidEq := Sqr(B1.Translation.X / 10.0) + Sqr(B1.Translation.Y / 5.0) + Sqr(B1.Translation.Z / 8.0);
    AssertSameValue(1.0, EllipsoidEq, 1e-4);
    AssertTrue(B1.Translation.Y > 0);
    EllipsoidEq := Sqr(B4.Translation.X / 10.0) + Sqr(B4.Translation.Y / 5.0) + Sqr(B4.Translation.Z / 8.0);
    AssertSameValue(1.0, EllipsoidEq, 1e-4);
    AssertTrue(B4.Translation.Y > 0);
    ExpectedNormal := Vector3(
      B1.Translation.X / Sqr(10.0),
      B1.Translation.Y / Sqr(5.0),
      B1.Translation.Z / Sqr(8.0)
    ).Normalize;
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(ExpectedNormal, WorldDir.Normalize, 1e-4);

    // 3. Test ShearSelected(0, 1, 0.5, true):
    // Stack B1..B4 vertically along Y at Y = 0, 2, 4, 6 (Center.Y = 3.0) with X = 0.
    // Shearing X by Y with factor 0.5 around Center.Y = 3.0:
    // B1 (Y=0, dY=-3) -> X = -1.5
    // B2 (Y=2, dY=-1) -> X = -0.5
    // B3 (Y=4, dY=+1) -> X = +0.5
    // B4 (Y=6, dY=+3) -> X = +1.5
    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B4.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(0, 0, 0);
    B2.Translation := Vector3(0, 2, 0);
    B3.Translation := Vector3(0, 4, 0);
    B4.Translation := Vector3(0, 6, 0);
    AssertTrue(Manipulate.ShearSelected(0, 1, 0.5, true));
    AssertVectorEquals(Vector3(-1.5, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-0.5, 2, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.5, 4, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(1.5, 6, 0), B4.Translation, 1e-4);
    // With TiltOrientation = true, RefUnit=(0,1,0), ShearUnit=(1,0,0), RotAxis=(0,0,-1), TiltAngle=ArcTan(0.5),
    // so local +Y tilts toward +X: WorldUp = (sin(ArcTan(0.5)), cos(ArcTan(0.5)), 0) = Vector3(0.5, 1.0, 0).Normalize!
    B4.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.5, 1.0, 0).Normalize, WorldUp.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestTwistTaperSphericalSpiralAndSuperellipse;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4, B5: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(10, -4, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(10, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(10, 4, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(-30, 0, 0);
    Viewport.Items.Add(B4);

    B5 := TCastleBox.Create(Viewport);
    B5.Size := Vector3(2, 2, 2);
    B5.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B5);

    // 1. Test TwistSelected(1, Pi, true) around Y axis with Center = (0, 0, 0):
    // Select B1(10, -4, 0), B2(10, 0, 0), B3(10, 4, 0), B4(-30, 0, 0) -> Center = (0, 0, 0).
    // MinY = -4, MaxY = +4, Span = 8.
    // B1 (Y=-4, NormT=-0.5, Angle=-Pi/2 around +Y): (10, -4, 0) -> (0, -4, 10)
    // B2 (Y=0, NormT=0.0, Angle=0): (10, 0, 0) -> (10, 0, 0)
    // B3 (Y=+4, NormT=+0.5, Angle=+Pi/2 around +Y): (10, 4, 0) -> (0, 4, -10)
    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;
    AssertTrue(Manipulate.TwistSelected(1, Pi, true));
    AssertVectorEquals(Vector3(0, -4, 10), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 4, -10), B3.Translation, 1e-4);

    // 2. Test TaperSelected(1, 0.5, true) along Y axis:
    // Reset B1..B4 so Center = (0, 0, 0), MinY = -4 (B1), Mid Y = 0 (B2, B4), MaxY = +4 (B3).
    // NormT(B1) = 0 -> ScaleF = 1.0 -> B1 stays at (10, -4, 0), Scale = (1, 1, 1)
    // NormT(B2) = 0.5 -> ScaleF = 0.75 -> B2 moves to (7.5, 0, 0), Scale = (0.75, 1, 0.75)
    // NormT(B3) = 1.0 -> ScaleF = 0.5 -> B3 moves to (5.0, 4, 0), Scale = (0.5, 1, 0.5)
    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B4.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(10, -4, 0);
    B2.Translation := Vector3(10, 0, 0);
    B3.Translation := Vector3(10, 4, 0);
    B4.Translation := Vector3(-30, 0, 0);
    AssertTrue(Manipulate.TaperSelected(1, 0.5, true));
    AssertVectorEquals(Vector3(10, -4, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(1, 1, 1), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(7.5, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.75, 1, 0.75), B2.Scale, 1e-4);
    AssertVectorEquals(Vector3(5.0, 4, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.5, 1, 0.5), B3.Scale, 1e-4);

    // 3. Test ArrangeSelectedInSphericalSpiral(10.0, 1.0, 1) on 5 transforms:
    // Reset B1..B5 around Center = (0, 0, 0).
    // i=0 (t=0): U=-1, Rho=0 -> bottom pole (0, -10, 0)
    // i=2 (t=0.5): U=0, Rho=1, Theta=Pi -> equator (-10, 0, 0), outward normal (-1, 0, 0)
    // i=4 (t=1): U=+1, Rho=0 -> top pole (0, 10, 0)
    B1.Scale := Vector3(1, 1, 1);
    B2.Scale := Vector3(1, 1, 1);
    B3.Scale := Vector3(1, 1, 1);
    B4.Scale := Vector3(1, 1, 1);
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(0, 0, 0);
    B4.Translation := Vector3(1, 0, 0);
    B5.Translation := Vector3(2, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4, B5]);
    AssertTrue(Manipulate.ArrangeSelectedInSphericalSpiral(10.0, 1.0, 1));
    AssertVectorEquals(Vector3(0, -10, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 10, 0), B5.Translation, 1e-4);
    AssertSameValue(10.0, B2.Translation.Length, 1e-4);
    AssertSameValue(10.0, B4.Translation.Length, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 4. Test ArrangeSelectedInSuperellipse(10.0, 8.0, 4.0, 1) on 4 transforms:
    // Reset B1..B4 around Center = (0, 0, 0). N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // i=0: (10, 0, 0) oriented inward (-1, 0, 0)
    // i=1: (0, 0, 8) oriented inward (0, 0, -1)
    // i=2: (-10, 0, 0) oriented inward (1, 0, 0)
    // i=3: (0, 0, -8) oriented inward (0, 0, 1)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInSuperellipse(10.0, 8.0, 4.0, 1));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 8), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -8), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestBendVivianiCurveAndSpirograph;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
  RadiusR: Single;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.OnTransformModified := {$ifdef FPC}@{$endif}HandleTransformModified;
    Manipulate.OnTransformModifyEnd := {$ifdef FPC}@{$endif}HandleTransformModifyEnd;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(2, 2, 2);
    B1.Translation := Vector3(0, -5, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(2, 2, 2);
    B2.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(2, 2, 2);
    B3.Translation := Vector3(0, 5, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(2, 2, 2);
    B4.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B4);

    // 1. Test BendSelected(1, 0, Pi, true):
    // SpineAxis = 1 (Y), BendDirAxis = 0 (X), TotalAngleRad = Pi.
    // B1(0, -5, 0), B2(0, 0, 0), B3(0, +5, 0) -> Center = (0, 0, 0), Span = 10, RadiusR = 10 / Pi.
    // B1 (theta = -Pi/2): X = R, Y = -R
    // B2 (theta = 0): X = 0, Y = 0
    // B3 (theta = +Pi/2): X = R, Y = +R, WorldUp rotated +90 deg from +Y to +X -> (1, 0, 0)
    Manipulate.SetSelected([B1, B2, B3]);
    Manipulate.PivotMode := pmSelectionCenter;
    RadiusR := 10.0 / Pi;
    AssertTrue(Manipulate.BendSelected(1, 0, Pi, true));
    AssertVectorEquals(Vector3(RadiusR, -RadiusR, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(RadiusR, RadiusR, 0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldUp.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInVivianiCurve(10.0, 2) on 4 transforms:
    // Reset B1..B4 around Center = (0, 0, 0), N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // i=0 (theta=0): (10, 0, 0), tangent (-sin(0), cos(0), cos(0)) = (0, 1, 1)
    // i=1 (theta=pi/2): (0, 10, 0)
    // i=2 (theta=pi): (10, 0, 0)
    // i=3 (theta=3pi/2): (0, -10, 0)
    B1.Rotation := Vector4(0, 1, 0, 0);
    B2.Rotation := Vector4(0, 1, 0, 0);
    B3.Rotation := Vector4(0, 1, 0, 0);
    B4.Rotation := Vector4(0, 1, 0, 0);
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInVivianiCurve(10.0, 2));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 10, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -10, 0), B4.Translation, 1e-4);
    AssertSameValue(10.0, B1.Translation.Length, 1e-4);
    AssertSameValue(10.0, B2.Translation.Length, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 1).Normalize, WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedInSpirograph(8.0, 2.0, 1.5, false, 2) on 4 transforms:
    // Reset B1..B4 around Center = (0, 0, 0).
    // Hypotrochoid: R = 8, r = 2, d = 1.5 -> BaseR = R - r = 6, k = (R - r)/r = 3.
    // N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // i=0: (7.5, 0, 0), tangent = (0, 0, 6 - 4.5) = (0, 0, 1.5) -> (0, 0, 1)
    // i=1: (0, 0, 7.5)
    // i=2: (-7.5, 0, 0)
    // i=3: (0, 0, -7.5)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInSpirograph(8.0, 2.0, 1.5, false, 2));
    AssertVectorEquals(Vector3(7.5, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 7.5), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-7.5, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -7.5), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSpherifyMobiusStripAndCardioidHeart;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(4, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(-4, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0, 8, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(0, -8, 0);
    Viewport.Items.Add(B4);

    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test SpherifySelected(10.0, 0.5, true):
    // Center = (0, 0, 0); B1/B2 at dist 4 -> Lerp(0.5, 4, 10) = 7
    // B3/B4 at dist 8 -> Lerp(0.5, 8, 10) = 9
    AssertTrue(Manipulate.SpherifySelected(10.0, 0.5, true));
    AssertVectorEquals(Vector3(7, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-7, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 9, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -9, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInMobiusStrip(10.0, 2.0, 2, 1):
    // Reset B1..B4 around Center = (0, 0, 0), N = 4 -> u = 0, pi/2, pi, 3pi/2:
    // HalfTwists = 2 -> alpha = u, v_i = (-1)^i * 2.0:
    // i=0 (u=0, alpha=0, v=+2): (12, 0, 0), LookDir = (0, 0, 1), Up = (0, 1, 0)
    // i=1 (u=pi/2, alpha=pi/2, v=-2): (0, -2, 10), LookDir = (-1, 0, 0), Up = (0, 0, -1)
    // i=2 (u=pi, alpha=pi, v=+2): (-8, 0, 0)
    // i=3 (u=3pi/2, alpha=3pi/2, v=-2): (0, 2, -10)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInMobiusStrip(10.0, 2.0, 2, 1));
    AssertVectorEquals(Vector3(12, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -2, 10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 2, -10), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, 1), WorldDir.Normalize, 1e-4);
    AssertVectorEquals(Vector3(0, 1, 0), WorldUp.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -1), WorldUp.Normalize, 1e-4);

    // 3. Test ArrangeSelectedInCardioidOrHeart(16.0, true, 0.0, 1) (Heart curve) &
    //    ArrangeSelectedInCardioidOrHeart(10.0, false, 0.0, 2) (Cardioid curve):
    // Reset B1..B4 around Center = (0, 0, 0), N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // Heart (S = 16):
    // i=0 (theta=0): x = 0, z = -16 * (13 - 5 - 2 - 1)/16 = -5
    // i=1 (theta=pi/2): x = 16, z = -16 * (0 - (-5) - 0 - 1)/16 = -4
    // i=2 (theta=pi): x = 0, z = -16 * (-13 - 5 + 2 - 1)/16 = 17
    // i=3 (theta=3pi/2): x = -16, z = -4
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInCardioidOrHeart(16.0, true, 0.0, 1));
    AssertVectorEquals(Vector3(0, 0, -5), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(16, 0, -4), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 17), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-16, 0, -4), B4.Translation, 1e-4);

    // Cardioid (S = 10, HeartShape = false):
    // i=0 (theta=0): r = 10*(1-0) = 10 -> (10, 0, 0)
    // i=1 (theta=pi/2): r = 10*(1-1) = 0 -> (0, 0, 0)
    // i=2 (theta=pi): r = 10*(1-0) = 10 -> (-10, 0, 0)
    // i=3 (theta=3pi/2): r = 10*(1+1) = 20 -> (0, 0, -20)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInCardioidOrHeart(10.0, false, 0.0, 2));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -20), B4.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestRippleLemniscateAndTorusHelix;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(2, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(-2, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test RippleSelected(4.0, 8.0, 0.0, 0.0, true):
    // Center = (0, 0, 0), k = 2*pi/8 = pi/4:
    // B1 (r=0): dy = 4 * cos(0) = 4 -> (0, 4, 0)
    // B2 (x=+2, r=2): k*r = pi/2 -> dy = 4 * cos(pi/2) = 0 -> (2, 0, 0),
    //   dy/dr = -4 * (pi/4) * sin(pi/2) = -pi -> SurfNormal = Normalize(pi, 1, 0)
    // B3 (x=-2, r=2): dy = 0 -> (-2, 0, 0)
    AssertTrue(Manipulate.RippleSelected(4.0, 8.0, 0.0, 0.0, true));
    AssertVectorEquals(Vector3(0, 4, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 0, 0), B3.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(Pi, 1.0, 0.0).Normalize, WorldUp.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInLemniscate(10.0, 3.0, 1):
    // Reset B1..B4 around Center = (0, 0, 0), N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // i=0 (t=0): sin=0, cos=1, denom=1 -> (10, 0, 0), dx/dt=0, dz/dt=10, dy/dt=3 -> LookDir=Normalize(0, 3, 10)
    // i=1 (t=pi/2): sin=1, cos=0, denom=2 -> (0, 3, 0), dx/dt=-10*2/4=-5, dz/dt=10*(-2)/4=-5, dy/dt=0
    // i=2 (t=pi): sin=0, cos=-1, denom=1 -> (-10, 0, 0)
    // i=3 (t=3pi/2): sin=-1, cos=0, denom=2 -> (0, -3, 0)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInLemniscate(10.0, 3.0, 1));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 3, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -3, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 3, 10).Normalize, WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedInTorusHelix(10.0, 2.0, 1.0, 2):
    // Reset B1..B4 around Center = (0, 0, 0), N = 4 -> u = 0, pi/2, pi, 3pi/2, v = u:
    // i=0 (u=0, v=0): R_rad = 10+2=12, y=0 -> (12, 0, 0), TubeNormal = (1, 0, 0)
    // i=1 (u=pi/2, v=pi/2): R_rad = 10, y=2 -> (0, 2, 10), TubeNormal = (0, 1, 0)
    // i=2 (u=pi, v=pi): R_rad = 8, y=0 -> (-8, 0, 0), TubeNormal = (1, 0, 0)
    // i=3 (u=3pi/2, v=3pi/2): R_rad = 10, y=-2 -> (0, -2, -10), TubeNormal = (0, -1, 0)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInTorusHelix(10.0, 2.0, 1.0, 2));
    AssertVectorEquals(Vector3(12, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 2, 10), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -2, -10), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 0), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSquashStretchButterflyAndClelie;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
  ExpectedZ2: Single;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(4, 0, -2);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(-4, 2, 2);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.SetSelected([B1, B2]);
    Manipulate.PivotMode := pmSelectionCenter;

    // 1. Test VolumeSquashStretchSelected(1 (Y axis), 4.0, true (AnchorAtBase), true (ScaleObjects)):
    // B1=(4, 0, -2), B2=(-4, 2, 2) -> Center=(0, 1, 0), MinY=0 -> AnchorPos=(0, 0, 0)
    // StretchFactor=4.0, InvSqrtStretch=0.5:
    // B1 -> (4*0.5, 0*4.0, -2*0.5) = (2, 0, -1), Scale = (0.5, 4.0, 0.5)
    // B2 -> (-4*0.5, 2*4.0, 2*0.5) = (-2, 8, 1), Scale = (0.5, 4.0, 0.5)
    AssertTrue(Manipulate.VolumeSquashStretchSelected(1, 4.0, true, true));
    AssertVectorEquals(Vector3(2, 0, -1), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2, 8, 1), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.5, 4.0, 0.5), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(0.5, 4.0, 0.5), B2.Scale, 1e-4);

    // 2. Test ArrangeSelectedInButterflyCurve(2.0, 5.0, 1):
    // Select B1..B4 around Center = (0, 0, 0), N = 4 -> theta = 0, pi/2, pi, 3pi/2:
    // i=0 (theta=0): |cos(0)|=1 -> Y=5.0, Z=0
    // i=1 (theta=pi/2): sin=1, cos=0, (2*theta-pi)/24 = 0 -> R = Exp(1) - 2*Cos(2*pi) + 0 = e - 2
    //   -> Pos = (0, 0, 2*(e - 2)), OrientMode=1 (inward XZ) -> LookDir = (0, 0, -1)
    // i=2 (theta=pi): |cos(pi)|=1 -> Y=5.0, Z=0
    B1.Scale := Vector3(1, 1, 1);
    B2.Scale := Vector3(1, 1, 1);
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInButterflyCurve(2.0, 5.0, 1));
    AssertSameValue(5.0, B1.Translation.Y, 1e-4);
    AssertSameValue(0.0, B1.Translation.Z, 1e-4);
    ExpectedZ2 := 2.0 * (Exp(1.0) - 2.0);
    AssertVectorEquals(Vector3(0, 0, ExpectedZ2), B2.Translation, 1e-4);
    AssertSameValue(5.0, B3.Translation.Y, 1e-4);
    AssertSameValue(0.0, B3.Translation.Z, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedInClelieCurve(10.0, 1.0, 1):
    // Reset B1..B4 around Center = (0, 0, 0), R = 10, m = 1, N = 4 -> theta = phi = 0, pi/2, pi, 3pi/2:
    // i=0 (0): SphereNormal = (1, 0, 0) -> (10, 0, 0), LookDir = (1, 0, 0), Up = Normalize(0, 1, 1)
    // i=1 (pi/2): SphereNormal = (0, 1, 0) -> (0, 10, 0) (North Pole)
    // i=2 (pi): SphereNormal = ((-1)*(-1), 0, 0) = (1, 0, 0) -> (10, 0, 0)
    // i=3 (3pi/2): SphereNormal = (0, -1, 0) -> (0, -10, 0) (South Pole)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInClelieCurve(10.0, 1.0, 1));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 10, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -10, 0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);
    AssertVectorEquals(Vector3(0, 1, 1).Normalize, WorldUp.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSwirlKnotCurveAndGeodesicDome;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4, B5: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(5, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(10, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B4);

    B5 := TCastleBox.Create(Viewport);
    B5.Size := Vector3(1, 1, 1);
    B5.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B5);

    Manipulate := TCastleTransformManipulate.Create(nil);

    // 1. Test SwirlSelected(1 (Y axis), Pi (180 deg at center), 10.0, true):
    // PivotMode = pmPrimarySelected -> PivotPos = B1 = (0, 0, 0):
    // B1 (r=0): Angle = Pi -> Pos stays (0, 0, 0), LookDir rotated Pi around +Y -> (0, 0, 1)
    // B2 (r=5): t = 0.5, Angle = Pi/2 -> (5, 0, 0) rotated +Pi/2 around +Y -> (0, 0, -5), LookDir -> (-1, 0, 0)
    // B3 (r=10): t = 1.0, Angle = 0 -> stays (10, 0, 0)
    Manipulate.SetSelected([B1, B2, B3]);
    Manipulate.PivotMode := pmPrimarySelected;
    AssertTrue(Manipulate.SwirlSelected(1, Pi, 10.0, true));
    AssertVectorEquals(Vector3(0, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -5), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10, 0, 0), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0, -1), WorldDir.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInKnotCurve:
    // Case A: Trefoil Knot (FigureEightKnot = false), Radius = 3.0 (S = 1.0), OrientMode = 1 (tangent)
    // Center = (0, 0, 0), N = 4 -> t = 0, pi/2, pi, 3pi/2:
    // i=0 (t=0): K = (0, 0, -1), dK = (5, -3, 0)
    // i=2 (t=pi): K = (0, 0, -3)
    Manipulate.PivotMode := pmSelectionCenter;
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInKnotCurve(3.0, false, 1));
    AssertVectorEquals(Vector3(0, 0, -1), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -3), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(5, -3, 0).Normalize, WorldDir.Normalize, 1e-4);

    // Case B: Figure-Eight Knot (FigureEightKnot = true), Radius = 3.0 (S = 1.0), OrientMode = 2 (outward)
    // i=0 (t=0): K = (3, 0, 0), LookDir = (1, 0, 0)
    // i=2 (t=pi): K = (-3, 0, 0), LookDir = (-1, 0, 0)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInKnotCurve(3.0, true, 2));
    AssertVectorEquals(Vector3(3, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-3, 0, 0), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedInGeodesicDome(10.0, 2, 1):
    // Select B1..B5 around Center = (0, 0, 0), Radius = 10, RingsCount = 2, OrientMode = 1 (outward normal):
    // B1 (apex, RIdx=0): (0, 10, 0), WorldUp = (0, 1, 0), WorldDir = (0, 0, -1)
    // B2..B5 on equator ring (RIdx=1, phi = pi/2, staggered theta = pi/4, 3pi/4, 5pi/4, 7pi/4):
    B1.Translation := Vector3(-4, 0, 0);
    B2.Translation := Vector3(-2, 0, 0);
    B3.Translation := Vector3(0, 0, 0);
    B4.Translation := Vector3(2, 0, 0);
    B5.Translation := Vector3(4, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4, B5]);
    AssertTrue(Manipulate.ArrangeSelectedInGeodesicDome(10.0, 2, 1));
    AssertVectorEquals(Vector3(0, 10, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10.0 / Sqrt(2.0), 0, 10.0 / Sqrt(2.0)), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0 / Sqrt(2.0), 0, 10.0 / Sqrt(2.0)), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0 / Sqrt(2.0), 0, -10.0 / Sqrt(2.0)), B4.Translation, 1e-4);
    AssertVectorEquals(Vector3(10.0 / Sqrt(2.0), 0, -10.0 / Sqrt(2.0)), B5.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 0), WorldUp.Normalize, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 1).Normalize, WorldUp.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestRadialFalloffCycloidAndHyperboloid;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
  W1: Single;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(5, 0, 0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(0, 0, 0);
    Viewport.Items.Add(B4);

    Manipulate := TCastleTransformManipulate.Create(nil);

    // 1. Test RadialFalloffSelected(10.0, 5.0, true):
    // PivotMode = pmPrimarySelected -> CenterPos = B1 = (0, 0, 0)
    // B1 (d=0): Weight = 1.0 -> Pos stays (0, 0, 0), ScaleFactor = 1 + 0.5*(10/5)*1 = 2.0
    // B2 (d=5): Weight = Exp(-1) -> Pos = (5 + 10*Exp(-1), 0, 0), ScaleFactor = 1 + Exp(-1)
    Manipulate.SetSelected([B1, B2]);
    Manipulate.PivotMode := pmPrimarySelected;
    W1 := Exp(-1.0);
    AssertTrue(Manipulate.RadialFalloffSelected(10.0, 5.0, true));
    AssertVectorEquals(Vector3(0, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 2, 2), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(5.0 + 10.0 * W1, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(1.0 + W1, 1.0 + W1, 1.0 + W1), B2.Scale, 1e-4);

    // 2. Test ArrangeSelectedInCycloid:
    // Case A: 4-cusped Astroid Hypocycloid (Radius = 8.0, Cusps = 4, Epicycloid = false, OrientMode = 2)
    Manipulate.PivotMode := pmSelectionCenter;
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInCycloid(8.0, 4, false, 2));
    AssertVectorEquals(Vector3(8, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 8), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, -8), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1, 0, 0), WorldDir.Normalize, 1e-4);

    // Case B: 2-cusped Nephroid Epicycloid (Radius = 8.0, Cusps = 2, Epicycloid = true, OrientMode = 1)
    B1.Translation := Vector3(-3, 0, 0);
    B2.Translation := Vector3(-1, 0, 0);
    B3.Translation := Vector3(1, 0, 0);
    B4.Translation := Vector3(3, 0, 0);
    AssertTrue(Manipulate.ArrangeSelectedInCycloid(8.0, 2, true, 1));
    AssertVectorEquals(Vector3(4, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 0, 8), B2.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedOnHyperboloid(3.0, 8.0, Sqrt(3.0), 1):
    // Select B1, B2, B3 around Center = (0, 0, 0):
    // B1 (u=-1, Theta=0): R = 6, Y = -4 -> (6, -4, 0), outward normal = Normalize(2.0, 2.25, 0)
    // B2 (u=0): R = 3, Y = 0
    // B3 (u=+1): R = 6, Y = 4
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(0, 0, 0);
    B3.Translation := Vector3(2, 0, 0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnHyperboloid(3.0, 8.0, Sqrt(3.0), 1));
    AssertVectorEquals(Vector3(6, -4, 0), B1.Translation, 1e-4);
    AssertSameValue(0.0, B2.Translation.Y, 1e-4);
    AssertSameValue(3.0, Hypot(B2.Translation.X, B2.Translation.Z), 1e-4);
    AssertSameValue(4.0, B3.Translation.Y, 1e-4);
    AssertSameValue(6.0, Hypot(B3.Translation.X, B3.Translation.Z), 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(2.0, 2.25, 0.0).Normalize, WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestCylindrifyCassiniOvalAndCatenoid;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    B1 := TCastleBox.Create(Viewport);
    B2 := TCastleBox.Create(Viewport);
    B3 := TCastleBox.Create(Viewport);
    B4 := TCastleBox.Create(Viewport);
    Viewport.Items.Add(B1);
    Viewport.Items.Add(B2);
    Viewport.Items.Add(B3);
    Viewport.Items.Add(B4);

    // 1. Test CylindrifySelected in Cylinder mode (50% blend) and Capsule mode (100% + radial normal):
    B1.Translation := Vector3(4, 0, 0);
    B2.Translation := Vector3(-4, 0, 0);
    B3.Translation := Vector3(0, 6, 0);
    B4.Translation := Vector3(0, -6, 0);
    Manipulate.PivotMode := pmSelectionCenter; // Center = (0, 0, 0)
    Manipulate.SetSelected([B1, B2, B3, B4]);

    AssertTrue(Manipulate.CylindrifySelected(10.0, 0.5, false, false));
    AssertVectorEquals(Vector3(7, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-7, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(5, 6, 0), B3.Translation, 1e-4);

    // Reset and test CapsuleHemispheres = true (HalfSpineY = 3.0 -> top/bottom caps at Y = +/-3):
    B1.Translation := Vector3(4, 0, 0);
    B2.Translation := Vector3(-4, 0, 0);
    B3.Translation := Vector3(0, 6, 0);
    B4.Translation := Vector3(0, -6, 0);
    AssertTrue(Manipulate.CylindrifySelected(10.0, 1.0, true, true));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 13, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -13, 0), B4.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 1, 0), WorldDir.Normalize, 1e-4);

    // 2. Test ArrangeSelectedInCassiniOval(4.0, Sqrt(2.0), 2.0, 1):
    // c = Sqrt(2) -> c^4 = 4:
    // B1 (Theta = 0): r = 4 * Sqrt(1 + 2) = 4*Sqrt(3), Y = +2
    // B2 (Theta = Pi/2): r = 4 * Sqrt(-1 + 2) = 4, Y = -2, tangent = (-1, 0, 0)
    // B3 (Theta = Pi): (-4*Sqrt(3), 2, 0)
    // B4 (Theta = 3*Pi/2): (0, -2, -4)
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(2, 0, 0);
    B3.Translation := Vector3(0, 0, -2);
    B4.Translation := Vector3(0, 0, 2);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInCassiniOval(4.0, Sqrt(2.0), 2.0, 1));
    AssertVectorEquals(Vector3(4.0 * Sqrt(3.0), 2.0, 0.0), B1.Translation, 1e-3);
    AssertVectorEquals(Vector3(0.0, -2.0, 4.0), B2.Translation, 1e-3);
    AssertVectorEquals(Vector3(-4.0 * Sqrt(3.0), 2.0, 0.0), B3.Translation, 1e-3);
    AssertVectorEquals(Vector3(0.0, -2.0, -4.0), B4.Translation, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1, 0, 0), WorldDir.Normalize, 1e-3);

    // 3. Test ArrangeSelectedOnCatenoid(4.0, 8.0, 1.0, 1):
    // Select B1, B2, B3 around Center = (0, 0, 0):
    // B1 (u=-1, Theta=0): R = 4*Cosh(1), Y = -4 -> (4*Cosh(1), -4, 0), outward normal = Normalize(1, Sinh(1), 0)
    // B2 (u=0): R = 4, Y = 0
    // B3 (u=+1): R = 4*Cosh(1), Y = 4
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(0, 0, 0);
    B3.Translation := Vector3(2, 0, 0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnCatenoid(4.0, 8.0, 1.0, 1));
    AssertVectorEquals(Vector3(4.0 * Cosh(1.0), -4.0, 0.0), B1.Translation, 1e-4);
    AssertSameValue(0.0, B2.Translation.Y, 1e-4);
    AssertSameValue(4.0, Hypot(B2.Translation.X, B2.Translation.Z), 1e-4);
    AssertSameValue(4.0, B3.Translation.Y, 1e-4);
    AssertSameValue(4.0 * Cosh(1.0), Hypot(B3.Translation.X, B3.Translation.Z), 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, Sinh(1.0), 0.0).Normalize, WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestBarrelHippopedeAndHelicoid;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    B1 := TCastleBox.Create(Viewport);
    B2 := TCastleBox.Create(Viewport);
    B3 := TCastleBox.Create(Viewport);
    B4 := TCastleBox.Create(Viewport);
    Viewport.Items.Add(B1);
    Viewport.Items.Add(B2);
    Viewport.Items.Add(B3);
    Viewport.Items.Add(B4);

    // 1. Test BarrelPincushionSelected(1, 0.5, true):
    // Symmetric positions around Center = (0, 0, 0) with MaxAbsAlong = 6.0:
    // B1(4, 0, 0) at u = 0 -> ScaleFactor = 1.5 -> Pos = (6, 0, 0), Scale = (1.5, 1.0, 1.5)
    // B2(-4, 0, 0) at u = 0 -> ScaleFactor = 1.5 -> Pos = (-6, 0, 0)
    // B3(2, 6, 0) at u = +1 -> ScaleFactor = 1.0 -> Pos = (2, 6, 0), Scale = (1, 1, 1)
    // B4(-2, -6, 0) at u = -1 -> ScaleFactor = 1.0 -> Pos = (-2, -6, 0)
    B1.Translation := Vector3(4, 0, 0);
    B2.Translation := Vector3(-4, 0, 0);
    B3.Translation := Vector3(2, 6, 0);
    B4.Translation := Vector3(-2, -6, 0);
    Manipulate.PivotMode := pmSelectionCenter;
    Manipulate.SetSelected([B1, B2, B3, B4]);

    AssertTrue(Manipulate.BarrelPincushionSelected(1, 0.5, true));
    AssertVectorEquals(Vector3(6, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(1.5, 1.0, 1.5), B1.Scale, 1e-4);
    AssertVectorEquals(Vector3(-6, 0, 0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(2, 6, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(1.0, 1.0, 1.0), B3.Scale, 1e-4);
    AssertVectorEquals(Vector3(-2, -6, 0), B4.Translation, 1e-4);

    // Reset scales and test ArrangeSelectedInHippopede(10.0, 0.64, 1):
    // SqrtLambda = 0.8, SqrtOneMinus = 0.6:
    // B1 (t = 0): (10, 0, 0)
    // B2 (t = Pi/2): (0, 8, 6), outward sphere normal = (0, 0.8, 0.6)
    // B3 (t = Pi): (-10, 0, 0)
    // B4 (t = 3*Pi/2): (0, -8, -6)
    B1.Scale := Vector3(1, 1, 1);
    B2.Scale := Vector3(1, 1, 1);
    B3.Scale := Vector3(1, 1, 1);
    B4.Scale := Vector3(1, 1, 1);
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(2, 0, 0);
    B3.Translation := Vector3(0, 0, -2);
    B4.Translation := Vector3(0, 0, 2);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInHippopede(10.0, 0.64, 1));
    AssertVectorEquals(Vector3(10, 0, 0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, 8, 6), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10, 0, 0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0, -8, -6), B4.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0, 0.8, 0.6), WorldDir.Normalize, 1e-4);

    // 3. Test ArrangeSelectedOnHelicoid(4.0, 6.0 * Pi, 1.0, 1):
    // Select B1, B2, B3 around Center = (0, 0, 0):
    // PitchC = (6*Pi) / (2*Pi) = 3.0, R = 4.0:
    // B1 (i=0, u=-1, Theta=-Pi, s=+4): (-4, -3*Pi, 0)
    // B2 (i=1, u=0, Theta=0, s=-4): (-4, 0, 0), helicoid surface normal = Normalize(0, 4, -3) = (0, 0.8, -0.6)
    // B3 (i=2, u=+1, Theta=+Pi, s=+4): (-4, +3*Pi, 0)
    B1.Translation := Vector3(-2, 0, 0);
    B2.Translation := Vector3(0, 0, 0);
    B3.Translation := Vector3(2, 0, 0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnHelicoid(4.0, 6.0 * Pi, 1.0, 1));
    AssertVectorEquals(Vector3(-4.0, -3.0 * Pi, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4.0, 3.0 * Pi, 0.0), B3.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.8, -0.6), WorldDir.Normalize, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestWaveDeformEnneperAndGearWheel;
var
  Viewport: TCastleViewport;
  B1, B2, B3, B4: TCastleBox;
  Manipulate: TCastleTransformManipulate;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := nil;
  Manipulate := nil;
  try
    Viewport := TCastleViewport.Create(nil);
    B1 := TCastleBox.Create(Viewport);
    B2 := TCastleBox.Create(Viewport);
    B3 := TCastleBox.Create(Viewport);
    B4 := TCastleBox.Create(Viewport);
    Viewport.Items.Add(B1);
    Viewport.Items.Add(B2);
    Viewport.Items.Add(B3);
    Viewport.Items.Add(B4);

    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.PivotMode := pmPrimarySelected;

    { 1. Test WaveDeformSelected along X -> Y with Amplitude=3, Wavelength=8 }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    B2.Translation := Vector3(2.0, 0.0, 0.0);
    B3.Translation := Vector3(4.0, 0.0, 0.0);
    B4.Translation := Vector3(-2.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);

    AssertTrue(Manipulate.WaveDeformSelected(0, 1, 3.0, 8.0, 0.0, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2.0, 3.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(4.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-2.0, -3.0, 0.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 3.0 * Pi / 4.0, 0.0).Normalize, WorldDir.Normalize, 1e-3);
    AssertVectorEquals(Vector3(-3.0 * Pi / 4.0, 1.0, 0.0).Normalize, WorldUp.Normalize, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldUp.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnEnneperSurface (ScaleRadius=3, MaxR=1, OrderK=1, OrientMode=1) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnEnneperSurface(3.0, 1.0, 1, 1));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2.0, 3.0, 0.0), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInGearWheel (PitchRadius=10, ToothDepth=2, TeethCount=2, Smooth, OrientMode=1) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInGearWheel(10.0, 2.0, 2, false, 1));
    AssertVectorEquals(Vector3(12.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 8.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-12.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, -8.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestSaddleDomeKleinBottleAndFermatSpiral;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4, B5: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(4.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 4.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-4.0, 0.0, -4.0);
    Viewport.Items.Add(B4);

    B5 := TCastleBox.Create(Viewport);
    B5.Size := Vector3(1, 1, 1);
    Viewport.Items.Add(B5);

    { 1. Test SaddleDomeDeformSelected (DisplaceAxis=1 (Y), CurvatureU=3.0, CurvatureV=-2.0, OrientNormals=true)
      Around B1=(0,0,0), MaxExtU = 4.0, MaxExtV = 4.0:
      - B1 (u=0, v=0): DeltaD = 0 -> (0, 0, 0), Normal=(0, 1, 0), Tangent=(1, 0, 0)
      - B2 (u=1, v=0): DeltaD = 3.0 -> (4, 3, 0), SlopeU = 2*3/4 = 1.5 -> Tangent=(1, 1.5, 0).Normalize, Normal=(-1.5, 1, 0).Normalize
      - B3 (u=0, v=1): DeltaD = -2.0 -> (0, -2, 4)
      - B4 (u=-1, v=-1): DeltaD = 3.0 - 2.0 = 1.0 -> (-4, 1, -4) }
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.SaddleDomeDeformSelected(1, 3.0, -2.0, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4.0, 3.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -2.0, 4.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-4.0, 1.0, -4.0), B4.Translation, 1e-4);

    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldUp.Normalize, 1e-3);

    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 1.5, 0.0).Normalize, WorldDir.Normalize, 1e-3);
    AssertVectorEquals(Vector3(-1.5, 1.0, 0.0).Normalize, WorldUp.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnKleinBottle (MajorRadius=10, TubeScale=2, Twists=1, OrientMode=2) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedOnKleinBottle(10.0, 2.0, 1.0, 2));
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, Sqrt(2.0), 10.0 + Sqrt(2.0)), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -Sqrt(2.0), -(10.0 + Sqrt(2.0))), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInFermatSpiral (MaxRadius=10, Turns=1, HeightSpan=6, DualArm=false, OrientMode=2) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4, B5]);
    AssertTrue(Manipulate.ArrangeSelectedInFermatSpiral(10.0, 1.0, 6.0, false, 2));
    AssertVectorEquals(Vector3(0.0, -3.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -1.5, 5.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(10.0, 3.0, 0.0), B5.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);
    B5.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestOctahedralDeformDiniAndCornuSpiral;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(3.0, 1.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 5.0);
    Viewport.Items.Add(B3);

    { 1. Test OctahedralDeformSelected (Radius=8.0, ExponentP=1.0, Strength=1.0, OrientNormals=true)
      Around B1=(0,0,0):
      - B2=(3,1,0) has l_1 norm = 4 -> projects to (8/4)*(3,1,0) = (6, 2, 0), normal = (1, 1, 0).Normalize
      - B3=(0,0,5) has l_1 norm = 5 -> projects to (0, 0, 8), normal = (0, 0, 1) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.OctahedralDeformSelected(8.0, 1.0, 1.0, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(6.0, 2.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 8.0), B3.Translation, 1e-4);

    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 1.0, 0.0).Normalize, WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnDiniSurface (RadiusA=6.0, PitchB=0.5, Turns=1.0, OrientMode=2)
      Around B1=(0,0,0):
      - B1 (t=0, u=0, v=Pi/6): x = 6*0.5 = 3.0, z = 0.0
      - B3 (t=1, u=2*Pi, v=Pi/2): x = 6.0, z = 0.0, y = 0.5 * 2 * Pi = Pi, outward radial = (1, 0, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnDiniSurface(6.0, 0.5, 1.0, 2));
    AssertSameValue(3.0, B1.Translation.X, 1e-4);
    AssertSameValue(0.0, B1.Translation.Z, 1e-4);
    AssertVectorEquals(Vector3(6.0, Pi, 0.0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInCornuSpiral (ScaleLength=10.0, MaxParamT=1.0, HeightSpan=0.0, OrientMode=1)
      Around B1=(0,0,0):
      - B2 (s=0): C(0)=S(0)=0 -> (0, 0, 0), analytical tangent = (1, 0, 0)
      - B1 (s=-1) and B3 (s=+1): odd symmetry B1 = -B3, C(1)~0.7798934, S(1)~0.4382591,
        and at s=1 angle is Pi/2 -> analytical tangent = (0, 0, 1) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedInCornuSpiral(10.0, 1.0, 0.0, 1));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(7.798934, 0.0, 4.382591), B3.Translation, 1e-3);
    AssertVectorEquals(-B3.Translation, B1.Translation, 1e-4);

    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestGyroidDeformRomanSurfaceAndCochleoid;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(2.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 2.0, 0.0);
    Viewport.Items.Add(B3);

    { 1. Test GyroidDeformSelected (Wavelength=8.0, Amplitude=3.0, SchwarzPMode=false, OrientNormals=true)
      Around B1=(0,0,0) with k = 2*Pi/8 = Pi/4:
      - B1 (0,0,0): F = 0, grad = k*(1, 1, 1) -> stays at (0, 0, 0), LookDir = (1, 1, 1).Normalize
      - B2 (2,0,0) (kx=Pi/2, ky=kz=0): F = sin(Pi/2)*cos(0) = 1.0, grad = k*(0, 1, 0) ->
        displaced by 3.0 * 1.0 * (0, 1, 0) to (2, 3, 0), LookDir = (0, 1, 0)
      - B3 (0,2,0) (ky=Pi/2, kx=kz=0): F = 1.0, grad = k*(0, 0, 1) ->
        displaced by 3.0 * 1.0 * (0, 0, 1) to (0, 2, 3), LookDir = (0, 0, 1) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.GyroidDeformSelected(8.0, 3.0, false, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2.0, 3.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 2.0, 3.0), B3.Translation, 1e-4);

    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 1.0, 1.0).Normalize, WorldDir.Normalize, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnRomanSurface (Radius=10.0, Turns=0.5, OrientMode=2)
      Around B1=(0,0,0) for N=3:
      - B1 (t=0, u=0, v=-Pi/4): x=0, y=0, z=-5.0, LookDir=(0, 0, -1)
      - B2 (t=0.5, u=Pi/4, v=0): x=5.0, y=0, z=0, LookDir=(1, 0, 0)
      - B3 (t=1, u=Pi/2, v=+Pi/4): x=0, y=5.0, z=0, LookDir=(0, 1, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnRomanSurface(10.0, 0.5, 2));
    AssertVectorEquals(Vector3(0.0, 0.0, -5.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(5.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 5.0, 0.0), B3.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInCochleoid (ScaleRadius=10.0, MaxAngleTurns=1.0, HeightSpan=0.0, SymmetricDualLobe=false, OrientMode=1)
      Around B1=(0,0,0) for N=3 (ThetaMax=Pi):
      - B1 (t=0, theta=0): r=10 -> (10, 0, 0), analytical tangent = (0, 0, 1)
      - B2 (t=0.5, theta=Pi/2): r=10/(Pi/2)=20/Pi -> (0, 0, 20/Pi)
      - B3 (t=1, theta=Pi): r=0 -> (0, 0, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedInCochleoid(10.0, 1.0, 0.0, false, 1));
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 20.0 / Pi), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestScherkDeformBoysSurfaceAndBicorn;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(4.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 4.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(2.0, 0.0, 2.0);
    Viewport.Items.Add(B4);

    { 1a. Test ScherkDeformSelected (Wavelength=8.0, Amplitude=3.0, SaddleTowerMode=false, OrientNormals=true)
      Around B1=(0,0,0) with k = 2*Pi/8 = Pi/4:
      - B1 (0,0,0): u=0, v=0 -> C_u=1, C_v=1 -> dy = 0, normal = (0, 1, 0)
      - B2 (4,0,0): u=Pi, v=0 -> C_u=-1 (clamped +0.18), C_v=1 -> dy = +3.0, S_u=0, S_v=0 -> normal = (0, 1, 0)
      - B3 (0,0,4): u=0, v=Pi -> C_u=1, C_v=-1 (clamped -0.18) -> dy = -3.0, normal = (0, 1, 0) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ScherkDeformSelected(8.0, 3.0, false, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(4.0, 3.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -3.0, 4.0), B3.Translation, 1e-4);

    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);

    { 1b. Test ScherkDeformSelected in SaddleTowerMode=true (Wavelength=8.0, Amplitude=3.0):
      - B1 (0,0,0) and B4 (2,0,2) where u=Pi/2, v=Pi/2 -> S_u=1, S_v=1 -> dy = +3.0 }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    B4.Translation := Vector3(2.0, 0.0, 2.0);
    Manipulate.SetSelected([B1, B4]);
    AssertTrue(Manipulate.ScherkDeformSelected(8.0, 3.0, true, true));
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(2.0, 3.0, 2.0), B4.Translation, 1e-4);

    { 2. Test ArrangeSelectedOnBoysSurface (Radius=10.0, Turns=2.0, OrientMode=1)
      Around B1=(0,0,0) for N=2:
      - B1 (t=0, r=0, theta=0): g1=0, g2=-1, g3=-Sqrt(2)/2 -> Pos = (10*Sqrt(2)/2, 7.5, 0) = (7.0710678, 7.5, 0)
      - B2 (t=1, r=1, theta=4*Pi): g1=0, g2=0, g3=+Sqrt(2)/2 -> Pos = (0, -7.5, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.ArrangeSelectedOnBoysSurface(10.0, 2.0, 1));
    AssertVectorEquals(Vector3(10.0 * Sqrt(2.0) * 0.5, 7.5, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -7.5, 0.0), B2.Translation, 1e-4);

    { 3a. Test ArrangeSelectedInBicornCurve (ScaleRadius=9.0, CrestHeight=2.0, PiriformTeardrop=false, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): x=0, z=9*(2+1)/3=9, y=2*cos(0)=2 -> (0, 2, 9), tangent=(+1, 0, 0)
      - B2 (theta=Pi/2): x=9*1=9, z=0, y=2*cos(Pi)=-2 -> (9, -2, 0)
      - B3 (theta=Pi): x=0, z=9*(2-1)/3=3, y=2*cos(2*Pi)=2 -> (0, 2, 3), tangent=(-1, 0, 0)
      - B4 (theta=3*Pi/2): x=-9, z=0, y=-2 -> (-9, -2, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInBicornCurve(9.0, 2.0, false, 1));
    AssertVectorEquals(Vector3(0.0, 2.0, 9.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(9.0, -2.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 2.0, 3.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(-9.0, -2.0, 0.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3b. Test ArrangeSelectedInBicornCurve in PiriformTeardrop=true (ScaleRadius=8.0, CrestHeight=2.0, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): x=8*(1+1)/2=8, z=0, y=0 -> (8, 0, 0)
      - B2 (theta=Pi/2): x=0, z=8*0.5=4, y=2 -> (0, 2, 4)
      - B3 (theta=Pi): x=-8, z=0, y=0 -> (-8, 0, 0)
      - B4 (theta=3*Pi/2): x=0, z=-4, y=-2 -> (0, -2, -4) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInBicornCurve(8.0, 2.0, true, 1));
    AssertVectorEquals(Vector3(8.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 2.0, 4.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-8.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -2.0, -4.0), B4.Translation, 1e-4);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestStereographicCatalanAndCylindricalHarmonic;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 10.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-10.0, 0.0, 0.0);
    Viewport.Items.Add(B4);

    { 1a. Test StereographicDeformSelected (Radius=10.0, Strength=1.0, NorthPoleProjection=false, OrientNormals=true)
      Around B1=(0,0,0):
      - B1 (0,0,0) -> u=0, w=0, r^2=0 -> (0, -10, 0), normal=(0, -1, 0)
      - B2 (10,0,0) -> u=1, w=0, r^2=1 -> (10, 0, 0), normal=(1, 0, 0)
      - B3 (0,0,10) -> u=0, w=1, r^2=1 -> (0, 0, 10), normal=(0, 0, 1) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.StereographicDeformSelected(10.0, 1.0, false, true));
    AssertVectorEquals(Vector3(0.0, -10.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 10.0), B3.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, -1.0, 0.0), WorldDir.Normalize, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 1b. Test StereographicDeformSelected with NorthPoleProjection=true (Radius=10.0, Strength=1.0):
      - B1 (0,0,0) -> (0, +10, 0), normal=(0, +1, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2]);
    AssertTrue(Manipulate.StereographicDeformSelected(10.0, 1.0, true, true));
    AssertVectorEquals(Vector3(0.0, 10.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B2.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnCatalanSurface (ScaleRadius=5.0, TurnsU=1.0, WidthV=1.0, OrientMode=2)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0):
      - B1 (t=0, u=-Pi, v=0): (-5*Pi, 0, 10)
      - B2 (t=0.5, u=0, v=0): (0, 0, 0)
      - B3 (t=1.0, u=+Pi, v=0): (+5*Pi, 0, 10), normal=(0, 0, 1) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnCatalanSurface(5.0, 1.0, 1.0, 2));
    AssertVectorEquals(Vector3(-5.0 * Pi, 0.0, 10.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(5.0 * Pi, 0.0, 10.0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInCylindricalHarmonic (BaseRadius=10.0, RadialAmp=2.0, VerticalAmp=4.0, RadialFreqM=2, VerticalFreqN=1, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): r=12 -> (12, 0, 0), tangent = Normalize(0, 4, 12)
      - B2 (theta=Pi/2): r=8 -> (0, 4, 8)
      - B3 (theta=Pi): r=12 -> (-12, 0, 0)
      - B4 (theta=3*Pi/2): r=8 -> (0, -4, -8) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInCylindricalHarmonic(10.0, 2.0, 4.0, 2, 1, 1));
    AssertVectorEquals(Vector3(12.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 4.0, 8.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-12.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -4.0, -8.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 4.0, 12.0).Normalize, WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestDupinCyclideBourSurfaceAndLimacon;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 10.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-10.0, 0.0, 0.0);
    Viewport.Items.Add(B4);

    { 1. Test ArrangeSelectedOnDupinCyclide (MajorRadiusA=10.0, MinorRadiusB=8.0, TubeRadiusD=3.0, Turns=1.0, OrientMode=1)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0), c = Sqrt(100 - 64) = 6:
      - B1 (t=0, u=0, v=0): Denom = 10 - 6 = 4, x = (3*(6-10) + 64)/4 = 52/4 = 13 -> (13, 0, 0)
      - B2 (t=0.5, u=Pi, v=Pi): Denom = 10 - 6 = 4, x = (3*(6-10) - 64)/4 = -76/4 = -19 -> (-19, 0, 0)
      - B3 (t=1.0, u=2*Pi, v=2*Pi): (13, 0, 0) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnDupinCyclide(10.0, 8.0, 3.0, 1.0, 1));
    AssertVectorEquals(Vector3(13.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-19.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(13.0, 0.0, 0.0), B3.Translation, 1e-4);

    { 2. Test ArrangeSelectedOnBourSurface (ScaleRadius=6.0, Turns=1.0, OrientMode=2)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0):
      - B1 (t=0, r=0.25, theta=0): x = 6*(0.25 - 0.5*0.0625) = 1.3125, y = 6*(4/3)*0.125 = 1.0, z = 0
      - B3 (t=1.0, r=1.0, theta=2*Pi): x = 6*(1 - 0.5) = 3.0, y = 6*(4/3)*1*cos(3*Pi) = -8.0, z = 0,
        Weierstrass-Enneper Gauss-map normal = (-1, 0, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnBourSurface(6.0, 1.0, 2));
    AssertVectorEquals(Vector3(1.3125, 1.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(3.0, -8.0, 0.0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInLimaconCurve (LoopRadiusA=8.0, OffsetB=4.0, CrestHeight=3.0, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): r=12 -> (12, 0, 0), tangent = Normalize(0, 6, 12)
      - B2 (theta=Pi/2): r=4 -> (0, 0, 4)
      - B3 (theta=Pi): r=-4, cos(Pi)=-1 -> (4, 0, 0) (inner loop apex)
      - B4 (theta=3*Pi/2): r=4 -> (0, 0, -4) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInLimaconCurve(8.0, 4.0, 3.0, 1));
    AssertVectorEquals(Vector3(12.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 4.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(4.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, -4.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 6.0, 12.0).Normalize, WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestHennebergSphericalEpicycloidAndTalbotCurve;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 10.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-10.0, 0.0, 0.0);
    Viewport.Items.Add(B4);

    { 1. Test ArrangeSelectedOnHennebergSurface (ScaleRadius=3.0, Turns=1.0, OrientMode=1)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0):
      - B1 (t=0, u=0, v=0): x=0, y=3*2*cosh(0)*cos(0)=6, z=0 -> (0, 6, 0)
      - B2 (t=0.5, u=0.4, v=Pi): x=3*(-2*Sinh(0.4)+(2/3)*Sinh(1.2)), y=6*Cosh(0.8), z=0
      - B3 (t=1.0, u=0.8, v=2*Pi): x=3*(2*Sinh(0.8)-(2/3)*Sinh(2.4)), y=6*Cosh(1.6), z=0 }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnHennebergSurface(3.0, 1.0, 1));
    AssertVectorEquals(Vector3(0.0, 6.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(
      Vector3(3.0 * (-2.0 * Sinh(0.4) + (2.0 / 3.0) * Sinh(1.2)), 6.0 * Cosh(0.8), 0.0),
      B2.Translation, 1e-4);
    AssertVectorEquals(
      Vector3(3.0 * (2.0 * Sinh(0.8) - (2.0 / 3.0) * Sinh(2.4)), 6.0 * Cosh(1.6), 0.0),
      B3.Translation, 1e-4);

    { 2. Test ArrangeSelectedOnSphericalEpicycloid (Radius=10.0, CuspsK=2, ConeAngleDeg=60.0, OrientMode=2)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2), omega = Pi/3:
      - B1 (theta=0, phi=+Pi/3): (5, 5*Sqrt(3), 0), outward sphere normal = (0.5, Sqrt(3)/2, 0)
      - B2 (theta=Pi/2, phi=-Pi/3): (0, -5*Sqrt(3), 5)
      - B3 (theta=Pi, phi=+Pi/3): (-5, 5*Sqrt(3), 0)
      - B4 (theta=3*Pi/2, phi=-Pi/3): (0, -5*Sqrt(3), -5) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedOnSphericalEpicycloid(10.0, 2, 60.0, 2));
    AssertVectorEquals(Vector3(5.0, 5.0 * Sqrt(3.0), 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -5.0 * Sqrt(3.0), 5.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-5.0, 5.0 * Sqrt(3.0), 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -5.0 * Sqrt(3.0), -5.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.5, 0.5 * Sqrt(3.0), 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInTalbotCurve (MajorRadiusA=10.0, EccentricityF=0.5, CrestHeight=3.0, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): (10, 0, 0), analytical tangent = Normalize(0, 6, 5)
      - B2 (theta=Pi/2): (0, 0, 10)
      - B3 (theta=Pi): (-10, 0, 0)
      - B4 (theta=3*Pi/2): (0, 0, -10) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInTalbotCurve(10.0, 0.5, 3.0, 1));
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 10.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, -10.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 6.0, 5.0).Normalize, WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestKuenRichmondAndDevilsCurve;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 10.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-10.0, 0.0, 0.0);
    Viewport.Items.Add(B4);

    { 1. Test ArrangeSelectedOnKuenSurface (ScaleRadius=5.0, Turns=1.0, OrientMode=1)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0):
      - B2 (t=0.5, u=0, v=0): Denom = 1, x = 2*5*1*1/1 = 10, y = 0, z = 0 -> (10, 0, 0) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnKuenSurface(5.0, 1.0, 1));
    AssertVectorEquals(Vector3(10.0, 0.0, 0.0), B2.Translation, 1e-4);

    { 2. Test ArrangeSelectedOnRichmondSurface (ScaleRadius=10.0, OrderM=2, Turns=1.0, OrientMode=2)
      Around B1=(0,0,0) for N=3 (ParamT = 0, 0.5, 1.0):
      - B3 (t=1.0, r=1.0, theta=2*Pi): x = 10*(-0.5 - 0.1) = -6, y = 10*(0.5) = 5, z = 0,
        Weierstrass-Enneper Gauss-map normal = (1, 0, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnRichmondSurface(10.0, 2, 1.0, 2));
    AssertVectorEquals(Vector3(-6.0, 5.0, 0.0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInDevilsCurve (ScaleRadius=10.0, LobeRatioK=0.44, CrestHeight=3.0, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2), Sqrt(1 + 0.44) = 1.2 -> r = 12:
      - B1 (theta=0): (12, 0, 0), analytical tangent = Normalize(0, 6, 12)
      - B2 (theta=Pi/2): (0, 0, 12)
      - B3 (theta=Pi): (-12, 0, 0)
      - B4 (theta=3*Pi/2): (0, 0, -12) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInDevilsCurve(10.0, 0.44, 3.0, 1));
    AssertVectorEquals(Vector3(12.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, 12.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-12.0, 0.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 0.0, -12.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 6.0, 12.0).Normalize, WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleTransformManipulate.TestPluckerSuperellipsoidAndGeronoLemniscate;
var
  Viewport: TCastleViewport;
  Manipulate: TCastleTransformManipulate;
  B1, B2, B3, B4: TCastleBox;
  WorldPos, WorldDir, WorldUp: TVector3;
begin
  Viewport := TCastleViewport.Create(nil);
  Manipulate := TCastleTransformManipulate.Create(nil);
  try
    Manipulate.PivotMode := pmPrimarySelected;

    B1 := TCastleBox.Create(Viewport);
    B1.Size := Vector3(1, 1, 1);
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Viewport.Items.Add(B1);

    B2 := TCastleBox.Create(Viewport);
    B2.Size := Vector3(1, 1, 1);
    B2.Translation := Vector3(10.0, 0.0, 0.0);
    Viewport.Items.Add(B2);

    B3 := TCastleBox.Create(Viewport);
    B3.Size := Vector3(1, 1, 1);
    B3.Translation := Vector3(0.0, 0.0, 10.0);
    Viewport.Items.Add(B3);

    B4 := TCastleBox.Create(Viewport);
    B4.Size := Vector3(1, 1, 1);
    B4.Translation := Vector3(-10.0, 0.0, 0.0);
    Viewport.Items.Add(B4);

    { 1. Test ArrangeSelectedOnPluckerConoid (ScaleRadius=8.0, FoldsN=2, FoldHeight=3.0, Turns=1.0, OrientMode=2)
      Around B1=(0,0,0) for N=3 (Frac = 0, 0.5, 1.0):
      - B1 (Frac=0, RadR=2.0, Theta=0): (2, 0, 0)
      - B2 (Frac=0.5, RadR=5.0, Theta=Pi): (-5, 0, 0)
      - B3 (Frac=1.0, RadR=8.0, Theta=2*Pi): (8, 0, 0), surface normal Pth x Pr = Normalize(0, 8, -6) = (0, 0.8, -0.6) }
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnPluckerConoid(8.0, 2, 3.0, 1.0, 2));
    AssertVectorEquals(Vector3(2.0, 0.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-5.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(8.0, 0.0, 0.0), B3.Translation, 1e-4);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.8, -0.6), WorldDir.Normalize, 1e-3);

    { 2. Test ArrangeSelectedOnSuperellipsoid (Radii=(10, 6, 8), EastWestExp=0.5, NorthSouthExp=0.5, Turns=1.0, OrientMode=1)
      Around B1=(0,0,0) for N=3 (Frac = 0, 0.5, 1.0):
      - B1 (Frac=0, Phi=-Pi/2, Theta=0): (0, -6, 0), normal = (0, -1, 0)
      - B2 (Frac=0.5, Phi=0, Theta=Pi): (-10, 0, 0), normal = (-1, 0, 0)
      - B3 (Frac=1.0, Phi=+Pi/2, Theta=2*Pi): (0, 6, 0), normal = (0, 1, 0) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3]);
    AssertTrue(Manipulate.ArrangeSelectedOnSuperellipsoid(Vector3(10.0, 6.0, 8.0), 0.5, 0.5, 1.0, 1));
    AssertVectorEquals(Vector3(0.0, -6.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0, 0.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, 6.0, 0.0), B3.Translation, 1e-4);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-1.0, 0.0, 0.0), WorldDir.Normalize, 1e-3);
    B3.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), WorldDir.Normalize, 1e-3);

    { 3. Test ArrangeSelectedInGeronoLemniscate (LobeRadiusA=10.0, LobeWidthB=8.0, SaddleHeight=3.0, OrientMode=1)
      Around B1=(0,0,0) for N=4 (theta = 0, Pi/2, Pi, 3*Pi/2):
      - B1 (theta=0): (10, 3, 0), analytical tangent = (0, 0, 1)
      - B2 (theta=Pi/2): (0, -3, 0), analytical tangent = Normalize(-10, 0, -8)
      - B3 (theta=Pi): (-10, 3, 0), analytical tangent = (0, 0, 1)
      - B4 (theta=3*Pi/2): (0, -3, 0), analytical tangent = Normalize(10, 0, -8) }
    B1.Translation := Vector3(0.0, 0.0, 0.0);
    Manipulate.SetSelected([B1, B2, B3, B4]);
    AssertTrue(Manipulate.ArrangeSelectedInGeronoLemniscate(10.0, 8.0, 3.0, 1));
    AssertVectorEquals(Vector3(10.0, 3.0, 0.0), B1.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -3.0, 0.0), B2.Translation, 1e-4);
    AssertVectorEquals(Vector3(-10.0, 3.0, 0.0), B3.Translation, 1e-4);
    AssertVectorEquals(Vector3(0.0, -3.0, 0.0), B4.Translation, 1e-4);
    B1.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.0), WorldDir.Normalize, 1e-3);
    B2.GetWorldView(WorldPos, WorldDir, WorldUp);
    AssertVectorEquals(Vector3(-10.0, 0.0, -8.0).Normalize, WorldDir.Normalize, 1e-3);
  finally
    FreeAndNil(Manipulate);
    FreeAndNil(Viewport);
  end;
end;

initialization
  RegisterTest(TTestCastleTransformManipulate);
end.

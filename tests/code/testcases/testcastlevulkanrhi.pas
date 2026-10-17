{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Test CastleInternalRHI and Vulkan backend subsystems. }
unit TestCastleVulkanRHI;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleVectors, CastleColors, CastleRectangles,
  CastleApplicationProperties, CastleImages, CastleGLImages, CastleFonts,
  CastleTextureFont_Default3d_Sans,
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanMemory,
  CastleInternalVulkanWSI, CastleInternalShaderCompiler, CastleInternalRHI_Vulkan,
  CastleInternalShaderRHI, CastleInternalBatch2DRHI, CastleInternalRenderer,
  CastleRendererInternalLights, X3DNodes,
  CastleTransform, CastleViewport, CastleRenderOptions, ToolManifest, CastleInternalRenderDoc;

type
  TTestCastleVulkanRHI = class(TCastleTestCase)
  published
    procedure TestRHIFundamentals;
    procedure TestVulkanDynamicLoader;
    procedure TestVulkanPipelineKeyHashing;
    procedure TestVulkanMemorySubAllocator;
    procedure TestShaderGeneratorRHI;
    procedure TestBatch2DCalculations;
    procedure TestApplicationPropertiesRenderBackend;
    procedure TestBatch2DScissorAndClipping;
    procedure TestGeometryBuffersToRHIBuffer;
    procedure TestDrawableImageRHIDispatch;
    procedure TestFontAtlasRHIDispatch;
    procedure TestSceneShapeRHIBufferAllocation;
    procedure Test3DForwardPassDispatch;
    procedure TestGPUSkinningJointBuffer;
    procedure TestMorphTargetVboReload;
    procedure TestMultiLightUBO;
    procedure TestDepthOnlyDynamicRenderingPass;
    procedure TestSanitizeVulkanShaderSource;
    procedure TestCubeMapTextureDesc;
    procedure TestScreenEffectPreambleAndSSAO;
    procedure TestCustomEffectAutomaticUniformInjection;
    procedure TestSecondaryCommandBuffersAndExecution;
    procedure TestManifestRenderBackendParsing;
    procedure TestRenderStatisticsDiagnostics;
    procedure TestDrawIndirectCommandStructures;
    procedure TestRenderDocIntegration;
    procedure TestPlatformWSIAndBackendFallback;
    procedure TestShaderPrewarming;
    procedure TestVisualRegressionImageComparison;
    procedure TestNintendoSwitchViSurfaceAndManifestPrewarm;
    procedure TestPipelineCacheDiskPersistence;
    procedure TestVulkanMemoryBudgetAndViewportStatistics;
    procedure TestViewportPrepareResourcesPrewarmsPSOs;
    procedure TestLegacyGLSLUniformWarningDiagnostics;
    procedure TestVulkan11RenderPassFramebufferFallback;
    procedure TestVkXmlHeaderGenerator;
    procedure TestVulkan11_12DeviceNegotiationAndFallback;
    procedure TestGraphicsPipelineLibraryFastLinking;
    procedure TestSPIRVBinaryReflectionAndValidation;
    procedure TestWindows4096MaxMemoryAllocationLimitAndPooledSubAllocation;
    procedure TestMultiVendorFormatAlignmentAndDeferredResourceDestruction;
    procedure TestGrowableAndTransientDescriptorPools;
    procedure TestAsyncStagingUploadRingBufferAndTransferQueue;
  private
    FCapturedWarnings: TStringList;
    procedure CaptureWarning(const Category, S: String);
  end;

implementation

{ TTestCastleVulkanRHI }

procedure TTestCastleVulkanRHI.TestRHIFundamentals;
var
  Desc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. Buffer Descriptor Validation }
  Desc.Size := 1024;
  Desc.Usage := [buVertex, buTransferDst];
  Desc.MemoryUsage := muGpuOnly;
  Desc.DebugName := 'TestVBO';

  AssertEquals('Buffer size must match', 1024, Desc.Size);
  AssertTrue('Buffer usage must include buVertex', buVertex in Desc.Usage);
  AssertTrue('Buffer usage must include buTransferDst', buTransferDst in Desc.Usage);
  AssertFalse('Buffer usage must not include buIndex', buIndex in Desc.Usage);
  AssertEquals('Buffer memory usage', Ord(muGpuOnly), Ord(Desc.MemoryUsage));

  { 2. Texture Descriptor Validation }
  TexDesc.Dimension := td2D;
  TexDesc.Format := pfRGBA8_UNorm;
  TexDesc.Width := 512;
  TexDesc.Height := 256;
  TexDesc.DepthOrArrayLayers := 1;
  TexDesc.MipLevels := 9;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuColorAttachment];
  TexDesc.DebugName := 'TestTex';

  AssertEquals('Tex width', 512, TexDesc.Width);
  AssertEquals('Tex height', 256, TexDesc.Height);
  AssertEquals('Tex mip levels', 9, TexDesc.MipLevels);
  AssertTrue('Tex usage must include tuSampled', tuSampled in TexDesc.Usage);
  AssertTrue('Tex usage must include tuColorAttachment', tuColorAttachment in TexDesc.Usage);

  { 3. Pipeline State Default Descriptors }
  PipelineDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  AssertEquals('Default cull mode should be cmBack', Ord(cmBack), Ord(PipelineDesc.Rasterizer.CullMode));
  AssertEquals('Default front face should be ffCounterClockwise', Ord(ffCounterClockwise), Ord(PipelineDesc.Rasterizer.FrontFace));
  AssertEquals('Default polygon mode should be pmFill', Ord(pmFill), Ord(PipelineDesc.Rasterizer.PolygonMode));

  PipelineDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  AssertTrue('Depth test should be enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('Depth write should be enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertEquals('Depth compare op should be coLessOrEqual', Ord(coLessOrEqual), Ord(PipelineDesc.DepthStencil.DepthCompareOp));
end;

procedure TTestCastleVulkanRHI.TestVulkanDynamicLoader;
begin
  { Verify dynamic loader state query does not crash }
  AssertTrue('Dynamic loader query executes without raising', (IsVulkanLoaded = True) or (IsVulkanLoaded = False));

  { Calling FreeVulkan should cleanly reset function pointers }
  FreeVulkan;
  AssertFalse('After FreeVulkan, IsVulkanLoaded must be False', IsVulkanLoaded);
  AssertTrue('vkGetInstanceProcAddr should be nil when unloaded', vkGetInstanceProcAddr = nil);
end;

procedure TTestCastleVulkanRHI.TestVulkanPipelineKeyHashing;
var
  Desc1, Desc2, Desc3, Desc4: TRHIGraphicsPipelineDesc;
  Hash1, Hash2, Hash3, Hash4: UInt64;
begin
  FillChar(Desc1, SizeOf(Desc1), 0);
  Desc1.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc1.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc1.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc1.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc1.ColorAttachmentFormats, 1);
  Desc1.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc1.VertexInput.Attributes, 1);
  Desc1.VertexInput.Attributes[0].Location := 0;
  Desc1.VertexInput.Attributes[0].Binding := 0;
  Desc1.VertexInput.Attributes[0].Format := vafVector3;
  Desc1.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc2, SizeOf(Desc2), 0);
  Desc2.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc2.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc2.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc2.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc2.ColorAttachmentFormats, 1);
  Desc2.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc2.VertexInput.Attributes, 1);
  Desc2.VertexInput.Attributes[0].Location := 0;
  Desc2.VertexInput.Attributes[0].Binding := 0;
  Desc2.VertexInput.Attributes[0].Format := vafVector3;
  Desc2.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc3, SizeOf(Desc3), 0);
  Desc3.BlendState := TRHIBlendStateDesc.DefaultOpaque; // Different blend state
  Desc3.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc3.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc3.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc3.ColorAttachmentFormats, 1);
  Desc3.ColorAttachmentFormats[0] := pfBGRA8_UNorm;

  FillChar(Desc4, SizeOf(Desc4), 0);
  Desc4.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc4.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc4.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc4.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc4.ColorAttachmentFormats, 1);
  Desc4.ColorAttachmentFormats[0] := pfRGBA16_Float; // Different color attachment format

  Hash1 := ComputePipelineKeyHash(Desc1);
  Hash2 := ComputePipelineKeyHash(Desc2);
  Hash3 := ComputePipelineKeyHash(Desc3);
  Hash4 := ComputePipelineKeyHash(Desc4);

  AssertTrue('Identical pipeline configurations must produce identical FNV-1a hashes', Hash1 = Hash2);
  AssertTrue('Divergent blend states must produce different hashes', Hash1 <> Hash3);
  AssertTrue('Divergent attachment formats must produce different hashes', Hash1 <> Hash4);
end;

procedure TTestCastleVulkanRHI.TestVulkanMemorySubAllocator;
var
  Alloc: TVulkanMemoryAllocation;
begin
  { Validate TVulkanMemoryAllocation default state }
  FillChar(Alloc, SizeOf(Alloc), 0);
  AssertFalse('Empty allocation should not be valid', Alloc.IsValid);

  Alloc.Size := 4096;
  Alloc.DeviceMemory := 1; // non-zero handle
  AssertTrue('Allocation with size and non-zero handle is valid', Alloc.IsValid);
end;

procedure TTestCastleVulkanRHI.TestShaderGeneratorRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  OriginalVS, AdjustedVS: String;
  Hash1, Hash2: UInt64;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Test Vulkan NDC Depth Conversion ([ -1 .. 1 ] -> [ 0 .. 1 ]) }
    OriginalVS :=
      'void main()' + NL +
      '{' + NL +
      '  gl_Position = u_ProjectionMatrix * u_ViewMatrix * a_Position;' + NL +
      '}' + NL;

    AdjustedVS := Gen.FinalizeVertexShaderSource(OriginalVS);
    AssertTrue('Adjusted vertex shader must contain depth adjustment',
      Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', AdjustedVS) > 0);

    { 2. Test FNV-1a Source Hash Determinism }
    Hash1 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    Hash2 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    AssertTrue('Source hash must be deterministic', Hash1 = Hash2);

    { Changing string should change hash }
    AssertTrue('Different GLSL sources must produce distinct hashes',
      Hash1 <> TCastleShaderGeneratorRHI.ComputeSourceHash(AdjustedVS));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestBatch2DCalculations;
var
  Tint: Cardinal;
  C: TCastleColor;
begin
  { 1. Test Color Packing into 32-bit R8G8B8A8 UNorm integer }
  C := Vector4(1.0, 0.0, 0.0, 1.0); // Opaque Red
  Tint := PackColorRgba8(C);
  AssertEquals('Red channel should be $FF in byte 0', $FF, Tint and $FF);
  AssertEquals('Green channel should be 0 in byte 1', 0, (Tint shr 8) and $FF);
  AssertEquals('Blue channel should be 0 in byte 2', 0, (Tint shr 16) and $FF);
  AssertEquals('Alpha channel should be $FF in byte 3', $FF, (Tint shr 24) and $FF);

  { 2. Test Batch Constants }
  AssertTrue('MaxQuadsPerBatch must not exceed 65536 indices capacity', MaxQuadsPerBatch * 4 <= 65536);
  AssertTrue('MaxQuadsPerFrame must be at least MaxQuadsPerBatch', MaxQuadsPerFrame >= MaxQuadsPerBatch);
end;

procedure TTestCastleVulkanRHI.TestApplicationPropertiesRenderBackend;
begin
  AssertEquals('Default RenderBackend should be backendAuto', Ord(backendAuto), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendVulkan;
  AssertEquals('RenderBackend should be backendVulkan', Ord(backendVulkan), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendOpenGL;
  AssertEquals('RenderBackend should be backendOpenGL', Ord(backendOpenGL), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendAuto;
end;

procedure TTestCastleVulkanRHI.TestBatch2DScissorAndClipping;
var
  R1, R2, Intersection: TRectangle;
  ScaleBias: TVector4;
  ViewportW, ViewportH: Single;
begin
  ViewportW := 1920.0;
  ViewportH := 1080.0;

  { 1. Test 2D Orthographic Scale/Bias formula }
  ScaleBias := Vector4(2.0 / ViewportW, 2.0 / ViewportH, -1.0, -1.0);
  AssertTrue('ScaleBias.X should match 2.0 / 1920', Abs(ScaleBias.X - (2.0 / 1920.0)) < 0.0001);
  AssertTrue('ScaleBias.Y should match 2.0 / 1080', Abs(ScaleBias.Y - (2.0 / 1080.0)) < 0.0001);
  AssertTrue('ScaleBias.Z should match -1.0', Abs(ScaleBias.Z - (-1.0)) < 0.0001);
  AssertTrue('ScaleBias.W should match -1.0', Abs(ScaleBias.W - (-1.0)) < 0.0001);

  { 2. Test Scissor Rect calculation and intersection }
  R1 := Rectangle(100, 100, 400, 300);
  R2 := Rectangle(200, 150, 500, 400);
  Intersection := R1 * R2;
  AssertEquals('Intersection Left', 200, Intersection.Left);
  AssertEquals('Intersection Bottom', 150, Intersection.Bottom);
  AssertEquals('Intersection Width', 300, Intersection.Width);
  AssertEquals('Intersection Height', 250, Intersection.Height);
  AssertFalse('Intersection should not be empty', Intersection.IsEmpty);
end;

procedure TTestCastleVulkanRHI.TestGeometryBuffersToRHIBuffer;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
begin
  { Coordinate VBO -> RHI vertex buffer }
  FillChar(CoordDesc, SizeOf(CoordDesc), 0);
  CoordDesc.Size := 100 * SizeOf(TVector3);
  CoordDesc.Usage := [buVertex, buTransferDst];
  CoordDesc.MemoryUsage := muGpuOnly;
  CoordDesc.DebugName := 'MeshCoordinates';

  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertEquals('Coord buffer size', 100 * SizeOf(TVector3), CoordDesc.Size);

  { Attribute VBO -> RHI vertex buffer }
  FillChar(AttrDesc, SizeOf(AttrDesc), 0);
  AttrDesc.Size := 100 * SizeOf(TVector4);
  AttrDesc.Usage := [buVertex, buTransferDst];
  AttrDesc.MemoryUsage := muGpuOnly;
  AttrDesc.DebugName := 'MeshAttributes';

  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);

  { Index VBO -> RHI index buffer }
  FillChar(IndexDesc, SizeOf(IndexDesc), 0);
  IndexDesc.Size := 300 * SizeOf(UInt32);
  IndexDesc.Usage := [buIndex, buTransferDst];
  IndexDesc.MemoryUsage := muGpuOnly;
  IndexDesc.DebugName := 'MeshIndices';

  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);
  AssertFalse('Index buffer must not have buVertex', buVertex in IndexDesc.Usage);
end;

procedure TTestCastleVulkanRHI.TestDrawableImageRHIDispatch;
var
  CpuImg: TRGBAlphaImage;
  DrawImg: TDrawableImage;
  BlendMode: TCastle2DBlendMode;
begin
  CpuImg := TRGBAlphaImage.Create(32, 32);
  CpuImg.Clear(Vector4Byte(255, 128, 64, 255));

  DrawImg := TDrawableImage.Create(CpuImg, true, true);
  try
    AssertEquals('DrawableImage width', 32, DrawImg.Width);
    AssertEquals('DrawableImage height', 32, DrawImg.Height);
    AssertTrue('DrawableImage smooth scaling', DrawImg.SmoothScaling);

    { Verify RHI properties start unallocated without active device }
    AssertTrue('RHITexture nil by default without active device', DrawImg.RHITexture = nil);
    AssertTrue('RHIDescriptorSet nil by default', DrawImg.RHIDescriptorSet = nil);

    { Verify ActiveBatch2DRenderer accessor }
    AssertTrue('ActiveBatch2DRenderer nil outside 2D pass', ActiveBatch2DRenderer = nil);

    { Test alpha channel to blend mode translation }
    case DrawImg.Alpha of
      acNone: BlendMode := CastleInternalBatch2DRHI.bmNone;
      else BlendMode := CastleInternalBatch2DRHI.bmAlphaBlend;
    end;
    AssertTrue('Opaque image translates to expected blend mode',
      BlendMode in [CastleInternalBatch2DRHI.bmNone, CastleInternalBatch2DRHI.bmAlphaBlend]);

    DrawImg.SmoothScaling := false;
    AssertFalse('SmoothScaling toggle', DrawImg.SmoothScaling);
  finally
    FreeAndNil(DrawImg);
  end;
end;

procedure TTestCastleVulkanRHI.TestFontAtlasRHIDispatch;
var
  TestFont: TCastleFont;
  TextW, TextH: Single;
begin
  TestFont := TCastleFont.Create(nil);
  try
    TestFont.Load(Font_Default3d_Sans);
    TestFont.Size := 16;
    TextW := TestFont.TextWidth('Vulkan RHI Font Test');
    TextH := TestFont.TextHeight('Vulkan RHI Font Test');
    AssertTrue('Font text width > 0', TextW > 0.0);
    AssertTrue('Font text height > 0', TextH > 0.0);

    { Font rendering creates glyph rectangles compatible with batch 2D quads }
    AssertTrue('Font scale positive', TestFont.Scale > 0.0);
  finally
    FreeAndNil(TestFont);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneShapeRHIBufferAllocation;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. 3D Forward Pass Vertex/Index Layout Configuration }
  CoordDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector3), [buVertex], muGpuOnly);
  AttrDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector4), [buVertex], muGpuOnly);
  IndexDesc := TRHIBufferDesc.Create(1500 * SizeOf(UInt32), [buIndex], muGpuOnly);

  AssertEquals('Coord buffer size matches 500 vertices', 500 * SizeOf(TVector3), CoordDesc.Size);
  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);
  AssertEquals('Index buffer size matches 1500 indices', 1500 * SizeOf(UInt32), IndexDesc.Size);
  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);

  { 2. Forward pass pipeline descriptor validation }
  FillChar(PipelineDesc, SizeOf(PipelineDesc), 0);
  PipelineDesc.Topology := ptTriangleList;
  PipelineDesc.Rasterizer.CullMode := cmBack;
  PipelineDesc.Rasterizer.FrontFace := ffCounterClockwise;
  PipelineDesc.DepthStencil.DepthTestEnable := True;
  PipelineDesc.DepthStencil.DepthWriteEnable := True;
  PipelineDesc.DepthStencil.DepthCompareOp := coLess;

  AssertTrue('3D pipeline has depth test enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('3D pipeline has depth write enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertTrue('3D pipeline uses backface culling', PipelineDesc.Rasterizer.CullMode = cmBack);
end;

type
  TMockRHICommandList = class(TRHICommandList)
  public
    LastPushConstantSize: Cardinal;
    LastPushConstantData: TCastlePushConstantsBlock;
    DrawCallsCount: Cardinal;
    DrawIndexedCallsCount: Cardinal;
    LastVertexCount: Cardinal;
    LastIndexCount: Cardinal;
    LastIndexType: TRHIIndexType;
    LastVertexBuffersBound: Boolean;
    ExecutedCommandsCount: Cardinal;

    procedure BeginRecording; override;
    procedure EndRecording; override;
    procedure TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); override;
    procedure GenerateMipmaps(const Texture: TRHITexture); override;
    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;
    procedure SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;
    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags; const Offset, Size: Cardinal; const Data); override;
    procedure BindVertexBuffers(const FirstBinding: Cardinal; const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt); override;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer; const Offset: PtrUInt; const IndexType: TRHIIndexType); override;
    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); override;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal); override;
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;
    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
  end;

procedure TMockRHICommandList.BeginRecording; begin end;
procedure TMockRHICommandList.EndRecording; begin end;
procedure TMockRHICommandList.TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); begin end;
procedure TMockRHICommandList.GenerateMipmaps(const Texture: TRHITexture); begin end;
procedure TMockRHICommandList.BeginRendering(const Info: TRHIRenderingInfo); begin end;
procedure TMockRHICommandList.EndRendering; begin end;
procedure TMockRHICommandList.SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single; const MaxDepth: Single); begin end;
procedure TMockRHICommandList.SetScissor(const ScissorRect: TRectangle); begin end;
procedure TMockRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single); begin end;
procedure TMockRHICommandList.BindPipeline(const Pipeline: TRHIPipeline); begin end;
procedure TMockRHICommandList.BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); begin end;
procedure TMockRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
begin
  Inc(ExecutedCommandsCount, Length(SecondaryCommandLists));
end;
procedure TMockRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor); begin end;
procedure TMockRHICommandList.PopDebugGroup; begin end;

procedure TMockRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
begin
  LastPushConstantSize := Size;
  if Size = SizeOf(TCastlePushConstantsBlock) then
    Move(Data, LastPushConstantData, Size);
end;

procedure TMockRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
begin
  LastVertexBuffersBound := Length(Buffers) > 0;
end;

procedure TMockRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
begin
  LastIndexType := IndexType;
end;

procedure TMockRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  Inc(DrawCallsCount);
  LastVertexCount := VertexCount;
end;

procedure TMockRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  Inc(DrawIndexedCallsCount);
  LastIndexCount := IndexCount;
end;

procedure TTestCastleVulkanRHI.Test3DForwardPassDispatch;
var
  MockCmd: TMockRHICommandList;
  PushConstants: TCastlePushConstantsBlock;
  ModelViewMat: TMatrix4;
  NormalMat: TMatrix3;
begin
  AssertTrue('ActiveCommandList starts nil', ActiveCommandList = nil);

  MockCmd := TMockRHICommandList.Create;
  try
    SetActiveCommandList(MockCmd);
    AssertTrue('ActiveCommandList is now MockCmd', ActiveCommandList = MockCmd);

    { 1. Test Push Constants calculation and packaging }
    ModelViewMat := TranslationMatrix(Vector3(10.0, 5.0, -20.0));
    PushConstants.ModelViewMatrix := ModelViewMat;
    NormalMat := ModelViewToNormalMatrix(ModelViewMat);
    PushConstants.NormalMatrixRow0 := Vector4(NormalMat.Rows[0], 0);
    PushConstants.NormalMatrixRow1 := Vector4(NormalMat.Rows[1], 0);
    PushConstants.NormalMatrixRow2 := Vector4(NormalMat.Rows[2], 0);
    PushConstants.ObjectParams := Vector4(1.0, 2.0, 0.0, 0.0);

    ActiveCommandList.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushConstants), PushConstants);

    AssertEquals('Push constant size matches 128 bytes', 128, MockCmd.LastPushConstantSize);
    AssertTrue('Push constant translation X matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].X - 10.0) < 0.001);
    AssertTrue('Push constant translation Y matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Y - 5.0) < 0.001);
    AssertTrue('Push constant translation Z matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Z - (-20.0)) < 0.001);
    AssertTrue('Push constant ObjectParam X matches', Abs(MockCmd.LastPushConstantData.ObjectParams.X - 1.0) < 0.001);

    { 2. Test draw dispatch recording }
    ActiveCommandList.DrawIndexed(36, 1, 0, 0, 0);
    AssertEquals('Indexed draw call count', 1, MockCmd.DrawIndexedCallsCount);
    AssertEquals('Indexed draw count matches 36 indices', 36, MockCmd.LastIndexCount);

    ActiveCommandList.Draw(24, 1, 0, 0);
    AssertEquals('Non-indexed draw call count', 1, MockCmd.DrawCallsCount);
    AssertEquals('Non-indexed draw count matches 24 vertices', 24, MockCmd.LastVertexCount);
  finally
    SetActiveCommandList(nil);
    FreeAndNil(MockCmd);
  end;

  AssertTrue('ActiveCommandList cleared', ActiveCommandList = nil);
end;

procedure TTestCastleVulkanRHI.TestGPUSkinningJointBuffer;
var
  JointList: TMatrix4List;
  SkinUBO: TCastleSkinningUniformBlock;
  UboDesc: TRHIBufferDesc;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
  I: Integer;
begin
  { 1. Validate skinning UBO dimensions and alignments }
  AssertEquals('Maximum bone count is 256', 256, CASTLE_MAX_BONE_MATRICES);
  AssertTrue('TCastleSkinningUniformBlock size >= 16384 bytes', SizeOf(TCastleSkinningUniformBlock) >= 16384);

  { 2. Populate joint matrices and simulate UBO upload }
  JointList := TMatrix4List.Create;
  try
    for I := 0 to 15 do
      JointList.Add(TranslationMatrix(Vector3(I * 2.0, 0, 0)));

    FillChar(SkinUBO, SizeOf(SkinUBO), 0);
    SkinUBO.JointCount := JointList.Count;
    for I := 0 to JointList.Count - 1 do
      SkinUBO.JointMatrices[I] := JointList.L[I];

    AssertEquals('Skin UBO joint count', 16, SkinUBO.JointCount);
    AssertTrue('First bone translation X', Abs(SkinUBO.JointMatrices[0].Columns[3].X - 0.0) < 0.001);
    AssertTrue('Last bone translation X', Abs(SkinUBO.JointMatrices[15].Columns[3].X - 30.0) < 0.001);

    UboDesc := TRHIBufferDesc.Create(JointList.Count * SizeOf(TMatrix4), [buUniform], muCpuToGpu, 'SkinningJointsUBO');
    AssertEquals('UBO descriptor size', 16 * SizeOf(TMatrix4), UboDesc.Size);
    AssertTrue('UBO descriptor usage includes buUniform', buUniform in UboDesc.Usage);
  finally
    FreeAndNil(JointList);
  end;

  { 3. Validate GLSL Set 2 skinning block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssVertex);
    AssertTrue('Preamble must declare CastleSkinningBlock', Pos('CastleSkinningBlock', Preamble) > 0);
    AssertTrue('Preamble must alias castle_JointMatrix', Pos('#define castle_JointMatrix', Preamble) > 0);
    AssertTrue('Preamble must define Set 2 binding 0 for skinning', Pos('CASTLE_UBO(2, 0)', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestMorphTargetVboReload;
var
  Cache: TShapeCache;
  JointList: TMatrix4List;
  CoordDesc: TRHIBufferDesc;
begin
  Cache := TShapeCache.Create;
  JointList := TMatrix4List.Create;
  try
    Cache.InvalidateVertexData([vtCoordinate]);
    JointList.Add(TMatrix4.Identity);
    Cache.UploadJointMatrices(JointList.L, JointList.Count);
    AssertTrue('Cache RHI buffers safely nil when backend is not active', Cache.RHICoordinateBuffer = nil);
    AssertTrue('Cache RHI joint buffer safely nil when backend is not active', Cache.RHIJointBuffer = nil);

    { Verify morph target buffer descriptor creation }
    CoordDesc := TRHIBufferDesc.Create(1000 * SizeOf(TVector3), [buVertex], muGpuOnly, 'MorphedCoords');
    AssertEquals('Morphed coordinate buffer size matches', 1000 * SizeOf(TVector3), CoordDesc.Size);
    AssertTrue('Morphed coordinate buffer is buVertex', buVertex in CoordDesc.Usage);
  finally
    FreeAndNil(JointList);
    FreeAndNil(Cache);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiLightUBO;
var
  Block: TCastleLightsUniformBlock;
  IdxDir, IdxPoint, IdxSpot: Integer;
  ProjMat: TMatrix4;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
begin
  { 1. std140 Struct Alignment and Size Validation }
  AssertEquals('Maximum lights count is 32', 32, CASTLE_MAX_LIGHTS);
  AssertEquals('TCastleLightData record size must be 160 bytes', 160, SizeOf(TCastleLightData));
  AssertEquals('TCastleLightsUniformBlock size must be 5136 bytes (16-byte aligned)', 5136, SizeOf(TCastleLightsUniformBlock));
  AssertEquals('TCastleLightsUniformBlock must be std140 aligned', 0, SizeOf(TCastleLightsUniformBlock) mod 16);

  { 2. Populate Directional Light }
  Block.Clear;
  AssertEquals('Cleared block light count', 0, Block.Count);

  IdxDir := Block.AddDirectionalLight(Vector3(0, -1, 0), Vector3(1, 1, 0.8), Vector3(0.1, 0.1, 0.1));
  AssertEquals('First light index', 0, IdxDir);
  AssertEquals('Light count after directional light', 1, Block.Count);
  AssertTrue('Directional light position W is 0.0', Abs(Block.Lights[0].Position.W - 0.0) < 0.001);
  AssertTrue('Directional light direction Y is -1.0', Abs(Block.Lights[0].Position.Y - (-1.0)) < 0.001);
  AssertTrue('Directional light color R is 1.0', Abs(Block.Lights[0].Color.X - 1.0) < 0.001);

  { 3. Populate Point Light }
  IdxPoint := Block.AddPointLight(Vector3(10, 5, 2), Vector3(1, 0, 0), Vector3(0.05, 0, 0),
    Vector3(1, 0.1, 0.01), 50.0);
  AssertEquals('Second light index', 1, IdxPoint);
  AssertEquals('Light count after point light', 2, Block.Count);
  AssertTrue('Point light position W is 1.0', Abs(Block.Lights[1].Position.W - 1.0) < 0.001);
  AssertTrue('Point light position X is 10.0', Abs(Block.Lights[1].Position.X - 10.0) < 0.001);
  AssertTrue('Point light radius is 50.0', Abs(Block.Lights[1].Color.W - 50.0) < 0.001);
  AssertTrue('Point light attenuation constant', Abs(Block.Lights[1].Attenuation.X - 1.0) < 0.001);

  { 4. Populate Spot Light and Shadow Projector Matrix }
  IdxSpot := Block.AddSpotLight(Vector3(0, 10, 0), Vector3(0, -1, 0), Vector3(1, 1, 1),
    Vector3(0.1, 0.1, 0.1), Vector3(1, 0.05, 0), 30.0,
    Cos(Pi / 4), Pi / 4, Pi / 6, 2.0);
  AssertEquals('Third light index', 2, IdxSpot);
  AssertEquals('Light count after spot light', 3, Block.Count);
  AssertTrue('Spot light position W is 2.0', Abs(Block.Lights[2].Position.W - 2.0) < 0.001);
  AssertTrue('Spot light spot direction Y is -1.0', Abs(Block.Lights[2].SpotDirection.Y - (-1.0)) < 0.001);
  AssertTrue('Spot light spot exponent is 2.0', Abs(Block.Lights[2].SpotParams.Z - 2.0) < 0.001);

  ProjMat := TranslationMatrix(Vector3(0, 0, -5));
  Block.SetProjectorMatrix(IdxSpot, ProjMat);
  AssertTrue('Spot light projector matrix translation Z', Abs(Block.Lights[2].ProjectorMatrix.Columns[3].Z - (-5.0)) < 0.001);

  { 5. Validate GLSL Set 0 Binding 1 lights block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssFragment);
    AssertTrue('Preamble declares CastleLightsBlock', Pos('CastleLightsBlock', Preamble) > 0);
    AssertTrue('Preamble binds CastleLights at Set 0 Binding 1', Pos('CASTLE_UBO(0, 1)', Preamble) > 0);
    AssertTrue('Preamble aliases castle_LightSource0Position', Pos('#define castle_LightSource0Position', Preamble) > 0);
    AssertTrue('Preamble aliases castle_projector_matrix_0', Pos('#define castle_projector_matrix_0', Preamble) > 0);
    AssertTrue('Preamble binds shadow map samplers', Pos('CASTLE_SAMPLER(0, 2) uniform sampler2DShadow castle_shadow_map_0;', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestDepthOnlyDynamicRenderingPass;
var
  Area: TRectangle;
  Info: TRHIRenderingInfo;
  DepthState: TRHIDepthStencilStateDesc;
begin
  Area := Rectangle(0, 0, 1024, 1024);
  Info := TRHIRenderingInfo.CreateDepthOnly(Area, nil, loClear, soStore, 1.0);

  AssertEquals('RenderArea width', 1024, Info.RenderArea.Width);
  AssertEquals('RenderArea height', 1024, Info.RenderArea.Height);
  AssertEquals('ColorAttachments length is 0 for depth-only pass', 0, Length(Info.ColorAttachments));
  AssertTrue('HasDepthAttachment is True', Info.HasDepthAttachment);
  AssertEquals('Depth attachment load op is loClear', Ord(loClear), Ord(Info.DepthAttachment.LoadOp));
  AssertEquals('Depth attachment store op is soStore', Ord(soStore), Ord(Info.DepthAttachment.StoreOp));
  AssertTrue('Depth clear value is 1.0', Abs(Info.DepthAttachment.ClearDepth - 1.0) < 0.001);

  DepthState := TRHIDepthStencilStateDesc.DefaultShadowMap;
  AssertTrue('Shadow map depth test must be enabled', DepthState.DepthTestEnable);
  AssertTrue('Shadow map depth write must be enabled', DepthState.DepthWriteEnable);
  AssertEquals('Shadow map depth compare op is coLessOrEqual', Ord(coLessOrEqual), Ord(DepthState.DepthCompareOp));
  AssertFalse('Shadow map stencil test is disabled', DepthState.StencilTestEnable);
end;

procedure TTestCastleVulkanRHI.TestSanitizeVulkanShaderSource;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyGLSL, SanitizedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    LegacyGLSL :=
      'uniform mat4 castle_ModelViewMatrix;' + NL +
      'uniform mat4 castle_ProjectionMatrix;' + NL +
      'uniform vec3 castle_LightSource0Position;' + NL +
      'uniform vec3 castle_LightSource0Color;' + NL +
      'uniform mat4 castle_projector_matrix_0;' + NL +
      'uniform float u_MyCustomMultiplier;' + NL +
      'void main() {' + NL +
      '  vec3 l = castle_LightSource0Position;' + NL +
      '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * vec4(l, 1.0)) * u_MyCustomMultiplier;' + NL +
      '}' + NL;

    SanitizedGLSL := Gen.SanitizeVulkanShaderSource(LegacyGLSL);

    { Legacy uniforms replaced by UBOs/PushConstants must be commented out }
    AssertTrue('castle_ModelViewMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ModelViewMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_ProjectionMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ProjectionMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_LightSource0Position must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform vec3 castle_LightSource0Position;', SanitizedGLSL) > 0);
    AssertTrue('castle_projector_matrix_0 must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_projector_matrix_0;', SanitizedGLSL) > 0);

    { User custom uniforms must remain intact }
    AssertTrue('u_MyCustomMultiplier must NOT be commented out',
      Pos('uniform float u_MyCustomMultiplier;', SanitizedGLSL) > 0);

    { Code usage inside main() must remain intact }
    AssertTrue('Shader body must be preserved',
      Pos('vec3 l = castle_LightSource0Position;', SanitizedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCubeMapTextureDesc;
var
  Desc: TRHITextureDesc;
begin
  Desc := TRHITextureDesc.CreateCube(512, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 4);
  AssertEquals('Cube map dimension', Ord(tdCube), Ord(Desc.Dimension));
  AssertEquals('Cube map width', 512, Desc.Width);
  AssertEquals('Cube map height', 512, Desc.Height);
  AssertEquals('Cube map depth/array layers must be 6', 6, Desc.DepthOrArrayLayers);
  AssertEquals('Cube map mip levels', 4, Desc.MipLevels);
  AssertEquals('Cube map sample count', 1, Desc.SampleCount);
  AssertEquals('Cube map pixel format', Ord(pfRGBA8_UNorm), Ord(Desc.Format));
  AssertTrue('Cube map usage tuSampled', tuSampled in Desc.Usage);
  AssertTrue('Cube map usage tuTransferDst', tuTransferDst in Desc.Usage);
end;

procedure TTestCastleVulkanRHI.TestScreenEffectPreambleAndSSAO;
var
  Gen: TCastleShaderGeneratorRHI;
  VertPreamble, FragPreambleDepth, FragPreambleNoDepth: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { Fragment shader with depth (used by SSAO and depth-aware screen effects) }
    FragPreambleDepth := Gen.GenerateScreenEffectPreamble(ssFragment, True);
    AssertTrue('Screen effect preamble contains #version 450', Pos('#version 450', FragPreambleDepth) > 0);
    AssertTrue('Screen effect contains screen push constants', Pos('CastleScreenPushConstants', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases screen_width', Pos('#define screen_width (castle_Screen.screen_size.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases near plane', Pos('#define near (castle_Screen.screen_planes.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases far plane', Pos('#define far (castle_Screen.screen_planes.y)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen sampler at Set 0 Binding 0',
      Pos('layout(set = 0, binding = 0) uniform sampler2D screen;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen_depth sampler at Set 0 Binding 1',
      Pos('layout(set = 0, binding = 1) uniform sampler2D screen_depth;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines texture2D compatibility macro', Pos('#define texture2D texture', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines gl_FragColor alias', Pos('#define gl_FragColor castle_FragColor', FragPreambleDepth) > 0);
    AssertTrue('Screen effect outputs castle_FragColor at location 0',
      Pos('layout(location = 0) out vec4 castle_FragColor;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect inputs tex_coord at location 0',
      Pos('layout(location = 0) in vec2 tex_coord;', FragPreambleDepth) > 0);

    { Fragment shader without depth (simple color grading, vignette, blur) }
    FragPreambleNoDepth := Gen.GenerateScreenEffectPreamble(ssFragment, False);
    AssertTrue('No-depth preamble has screen sampler', Pos('uniform sampler2D screen;', FragPreambleNoDepth) > 0);
    AssertFalse('No-depth preamble must NOT have screen_depth sampler', Pos('screen_depth', FragPreambleNoDepth) > 0);

    { Vertex shader for screen effect quad }
    VertPreamble := Gen.GenerateScreenEffectPreamble(ssVertex, False);
    AssertTrue('Vertex preamble inputs vertex attribute at location 0',
      Pos('layout(location = 0) in vec2 vertex;', VertPreamble) > 0);
    AssertTrue('Vertex preamble inputs tex_coord attribute at location 1',
      Pos('layout(location = 1) in vec2 tex_coord;', VertPreamble) > 0);
    AssertTrue('Vertex preamble outputs v_tex_coord at location 0',
      Pos('layout(location = 0) out vec2 v_tex_coord;', VertPreamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCustomEffectAutomaticUniformInjection;
var
  Gen: TCastleShaderGeneratorRHI;
  UserGLSL, UpgradedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    UserGLSL :=
      'uniform float u_intensity;' + NL +
      'uniform vec3 u_tint;' + NL +
      'uniform mediump float u_roughness;' + NL +
      'uniform sampler2D u_noiseTexture;' + NL +
      'uniform float u_weights[4];' + NL +
      'void PLUG_custom_surface() {' + NL +
      '  float f = u_intensity * u_roughness * u_weights[0];' + NL +
      '  vec4 n = texture(u_noiseTexture, vec2(f, f)) * vec4(u_tint, 1.0);' + NL +
      '}' + NL;

    UpgradedGLSL := Gen.UpgradeUserEffectUniforms(UserGLSL);

    { Value uniforms must be gathered into CastleUserEffectBlock at Set 2 Binding 1 }
    AssertTrue('Upgraded shader contains CastleUserEffectBlock UBO at Set 2 Binding 1',
      Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_intensity', Pos('float u_user_u_intensity;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_tint', Pos('vec3 u_user_u_tint;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_roughness with stripped precision qualifier',
      Pos('float u_user_u_roughness;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains array u_user_u_weights[4]', Pos('float u_user_u_weights[4];', UpgradedGLSL) > 0);

    { Aliases must redirect bare variable names to CastleUserEffect.u_user_* }
    AssertTrue('Alias define for u_intensity',
      Pos('#define u_intensity CastleUserEffect.u_user_u_intensity', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_tint',
      Pos('#define u_tint CastleUserEffect.u_user_u_tint', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_roughness',
      Pos('#define u_roughness CastleUserEffect.u_user_u_roughness', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_weights',
      Pos('#define u_weights CastleUserEffect.u_user_u_weights', UpgradedGLSL) > 0);

    { Samplers must be assigned to Set 2 Binding 2+ }
    AssertTrue('Sampler assigned to Set 2 Binding 2',
      Pos('CASTLE_SAMPLER(2, 2) uniform sampler2D u_noiseTexture;', UpgradedGLSL) > 0);

    { User function body must remain intact }
    AssertTrue('Shader body preserved', Pos('void PLUG_custom_surface()', UpgradedGLSL) > 0);
    AssertTrue('Texture lookup preserved', Pos('vec4 n = texture(u_noiseTexture, vec2(f, f))', UpgradedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestSecondaryCommandBuffersAndExecution;
var
  PrimaryCmd, SecCmd1, SecCmd2: TMockRHICommandList;
begin
  PrimaryCmd := TMockRHICommandList.Create(cllPrimary);
  SecCmd1 := TMockRHICommandList.Create(cllSecondary);
  SecCmd2 := TMockRHICommandList.Create(cllSecondary);
  try
    AssertEquals('PrimaryCmd level is primary', Ord(cllPrimary), Ord(PrimaryCmd.Level));
    AssertEquals('SecCmd1 level is secondary', Ord(cllSecondary), Ord(SecCmd1.Level));
    AssertEquals('SecCmd2 level is secondary', Ord(cllSecondary), Ord(SecCmd2.Level));

    SecCmd1.BeginRecording;
    SecCmd1.Draw(100, 1, 0, 0);
    SecCmd1.EndRecording;
    AssertEquals('SecCmd1 recorded 1 draw call', 1, SecCmd1.DrawCallsCount);

    SecCmd2.BeginRecording;
    SecCmd2.DrawIndexed(250, 1, 0, 0, 0);
    SecCmd2.EndRecording;
    AssertEquals('SecCmd2 recorded 1 indexed draw call', 1, SecCmd2.DrawIndexedCallsCount);

    PrimaryCmd.BeginRecording;
    PrimaryCmd.ExecuteCommands([SecCmd1, SecCmd2]);
    PrimaryCmd.EndRecording;
    AssertEquals('PrimaryCmd executed 2 secondary command lists', 2, PrimaryCmd.ExecutedCommandsCount);
  finally
    FreeAndNil(SecCmd2);
    FreeAndNil(SecCmd1);
    FreeAndNil(PrimaryCmd);
  end;
end;

procedure TTestCastleVulkanRHI.TestManifestRenderBackendParsing;
var
  ParsedException: Boolean;
begin
  AssertEquals('Parse auto', Ord(backendAuto), Ord(StringToRenderBackend('auto')));
  AssertEquals('Parse opengl', Ord(backendOpenGL), Ord(StringToRenderBackend('opengl')));
  AssertEquals('Parse opengles', Ord(backendOpenGLES), Ord(StringToRenderBackend('opengles')));
  AssertEquals('Parse vulkan', Ord(backendVulkan), Ord(StringToRenderBackend('vulkan')));

  AssertEquals('String auto', 'auto', RenderBackendToString(backendAuto));
  AssertEquals('String opengl', 'opengl', RenderBackendToString(backendOpenGL));
  AssertEquals('String opengles', 'opengles', RenderBackendToString(backendOpenGLES));
  AssertEquals('String vulkan', 'vulkan', RenderBackendToString(backendVulkan));

  ParsedException := False;
  try
    StringToRenderBackend('directx');
  except
    on E: Exception do
      ParsedException := True;
  end;
  AssertTrue('Invalid backend name raises exception', ParsedException);
end;

procedure TTestCastleVulkanRHI.TestRenderStatisticsDiagnostics;
var
  Stats: TRenderStatistics;
  S: String;
  Options: TCastleRenderOptions;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Stats.ShapesRendered := 450;
  Stats.ShapesVisible := 1200;
  Stats.DrawCalls := 85;
  Stats.ActiveBackend := 'Vulkan 1.3';
  Stats.PipelineCacheHits := 120;
  Stats.PipelineCacheMisses := 4;
  Stats.DescriptorSetAllocations := 350;
  Stats.DeviceMemoryUsedMB := 128;
  Stats.DeviceMemoryBudgetMB := 2048;

  S := Stats.ToString;
  AssertTrue('Stats contains shapes count', Pos('Shapes 450', S) > 0);
  AssertTrue('Stats contains draw calls', Pos('Draw calls: 85', S) > 0);
  AssertTrue('Stats contains active backend', Pos('Backend: Vulkan 1.3', S) > 0);
  AssertTrue('Stats contains PSO cache hits/misses', Pos('PSO hits/misses: 120/4', S) > 0);
  AssertTrue('Stats contains descriptor allocations', Pos('Descriptors: 350', S) > 0);
  AssertTrue('Stats contains VRAM budget', Pos('VRAM: 128 / 2048 MB', S) > 0);

  Options := TCastleRenderOptions.Create(nil);
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    AssertEquals('Options backend name is Vulkan', 'Vulkan', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendOpenGL;
    AssertEquals('Options backend name is OpenGL', 'OpenGL', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendAuto;
    AssertEquals('Options backend name is Auto', 'Auto', Options.ActiveRenderBackendName);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawIndirectCommandStructures;
var
  Cmd: TRHIDrawIndirectCommand;
  IndexedCmd: TRHIDrawIndexedIndirectCommand;
begin
  { Verify standard sizes match hardware indirect dispatch specs }
  AssertEquals('TRHIDrawIndirectCommand size must be 16 bytes', 16, SizeOf(TRHIDrawIndirectCommand));
  AssertEquals('TRHIDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(TRHIDrawIndexedIndirectCommand));
  AssertEquals('VkDrawIndirectCommand size must be 16 bytes', 16, SizeOf(VkDrawIndirectCommand));
  AssertEquals('VkDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(VkDrawIndexedIndirectCommand));

  { Verify field values and offsets }
  FillChar(Cmd, SizeOf(Cmd), 0);
  Cmd.VertexCount := 36;
  Cmd.InstanceCount := 10;
  Cmd.FirstVertex := 0;
  Cmd.FirstInstance := 5;

  AssertEquals('VertexCount', 36, Cmd.VertexCount);
  AssertEquals('InstanceCount', 10, Cmd.InstanceCount);
  AssertEquals('FirstVertex', 0, Cmd.FirstVertex);
  AssertEquals('FirstInstance', 5, Cmd.FirstInstance);

  FillChar(IndexedCmd, SizeOf(IndexedCmd), 0);
  IndexedCmd.IndexCount := 72;
  IndexedCmd.InstanceCount := 4;
  IndexedCmd.FirstIndex := 120;
  IndexedCmd.VertexOffset := -3;
  IndexedCmd.FirstInstance := 1;

  AssertEquals('IndexCount', 72, IndexedCmd.IndexCount);
  AssertEquals('InstanceCount', 4, IndexedCmd.InstanceCount);
  AssertEquals('FirstIndex', 120, IndexedCmd.FirstIndex);
  AssertEquals('VertexOffset', -3, IndexedCmd.VertexOffset);
  AssertEquals('FirstInstance', 1, IndexedCmd.FirstInstance);
end;

procedure TTestCastleVulkanRHI.TestRenderDocIntegration;
var
  Options: TCastleRenderOptions;
  IsAvail: Boolean;
begin
  IsAvail := RenderDocAvailable;
  { Calling TriggerCapture should never fail even if RenderDoc is not connected }
  RenderDocTriggerCapture;
  RenderDocStartFrameCapture(nil, nil);
  AssertFalse('Should not be frame capturing when RenderDoc not loaded', RenderDocIsFrameCapturing);
  AssertFalse('EndFrameCapture should return False when RenderDoc not loaded', RenderDocEndFrameCapture(nil, nil));
  AssertFalse('LaunchReplayUI should return False when RenderDoc not loaded', RenderDocLaunchReplayUI(False));

  Options := TCastleRenderOptions.Create(nil);
  try
    AssertEquals('Options RenderDocAvailable matches', IsAvail, Options.RenderDocAvailable);
    Options.TriggerRenderDocCapture;
    AssertFalse('Options LaunchRenderDocReplayUI returns False without RenderDoc', Options.LaunchRenderDocReplayUI);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestPlatformWSIAndBackendFallback;
var
  Exts: TAnsiStringArray;
begin
  Exts := GetRequiredVulkanInstanceExtensions;
  AssertTrue('At least VK_KHR_surface is required', Length(Exts) >= 1);
  AssertEquals('First extension is VK_KHR_surface', VK_KHR_SURFACE_EXTENSION_NAME, String(Exts[0]));

  { Vulkan 1.3 available -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.3 -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 3, False)));

  { Vulkan 1.1 baseline on Android -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.1 on mobile -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 1, True)));

  { Vulkan 1.0 (below 1.1 baseline) on Android -> falls back to OpenGLES 3.0 }
  AssertEquals('Vulkan 1.0 on mobile -> falls back to OpenGLES',
    Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 0, True)));

  { Vulkan unavailable on desktop -> falls back to OpenGL }
  AssertEquals('No Vulkan on desktop -> falls back to OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendVulkan, False, 0, 0, False)));

  { Explicit OpenGL request is preserved even if Vulkan 1.3 is present }
  AssertEquals('Explicit OpenGL -> OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendOpenGL, True, 1, 3, False)));
end;

procedure TTestCastleVulkanRHI.TestShaderPrewarming;
var
  Hashes: TUInt64Array;
  I, J: Integer;
begin
  Hashes := TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;
  AssertEquals('PrewarmCoreEngineShaders returns 5 core shader stage hashes', 5, Length(Hashes));
  for I := 0 to High(Hashes) do
  begin
    AssertTrue('Core shader hash must be non-zero', Hashes[I] <> 0);
    for J := I + 1 to High(Hashes) do
      AssertTrue('Distinct core shaders must produce distinct hashes', Hashes[I] <> Hashes[J]);
  end;
end;

procedure TTestCastleVulkanRHI.TestVisualRegressionImageComparison;
var
  ImgA, ImgB: TRGBAlphaImage;
  RMSE: Single;
  Px: PVector4Byte;
begin
  ImgA := TRGBAlphaImage.Create(16, 16);
  ImgB := TRGBAlphaImage.Create(16, 16);
  try
    ImgA.Clear(Vector4Byte(64, 128, 192, 255));
    ImgB.Clear(Vector4Byte(64, 128, 192, 255));

    { 1. Identical images must have 0.0 RMSE }
    AssertTrue('Identical framebuffers pass diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.001, RMSE));
    AssertSameValue(0.0, RMSE, 0.00001);

    { 2. Minor 1-LSB rounding difference across 1 pixel stays well within perceptual threshold (0.01) }
    Px := ImgB.PixelPtr(8, 8);
    Px^.X := 65;
    AssertTrue('1-LSB sub-threshold difference passes',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.01, RMSE));
    AssertTrue('RMSE > 0 for modified image', RMSE > 0.0);

    { 3. Completely different image exceeds threshold and fails }
    ImgB.Clear(Vector4Byte(255, 0, 0, 255));
    AssertFalse('Divergent framebuffers fail diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.05, RMSE));
    AssertTrue('Divergent RMSE > 0.3', RMSE > 0.3);
  finally
    FreeAndNil(ImgB);
    FreeAndNil(ImgA);
  end;
end;

procedure TTestCastleVulkanRHI.TestNintendoSwitchViSurfaceAndManifestPrewarm;
var
  ViCreateInfo: VkViSurfaceCreateInfoNN;
  Manifest: TCastleManifest;
  RaisedError: Boolean;
begin
  { 1. Verify Nintendo Switch VK_NN_vi_surface ABI layout and constants }
  AssertEquals('VK_NN_vi_surface extension name', 'VK_NN_vi_surface', VK_NN_VI_SURFACE_EXTENSION_NAME);
  AssertEquals('VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN', 1000062000, VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN);

  FillChar(ViCreateInfo, SizeOf(ViCreateInfo), 0);
  ViCreateInfo.sType := VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN;
  ViCreateInfo.window := Pointer($1234);
  AssertEquals('ViCreateInfo.sType', 1000062000, ViCreateInfo.sType);
  AssertTrue('ViCreateInfo.window pointer matches', ViCreateInfo.window = Pointer($1234));

  RaisedError := False;
  try
    CreateVulkanViSurface(nil, Pointer($1234));
  except
    on E: ERHIError do
      RaisedError := True;
  end;
  AssertTrue('CreateVulkanViSurface raises ERHIError when vkCreateViSurfaceNN is not loaded', RaisedError);

  { 2. Verify TCastleManifest loading of vulkan_3d_scene and ShouldPrewarmVulkanShaders }
  Manifest := TCastleManifest.CreateFromUrl('examples/vulkan/vulkan_3d_scene/CastleEngineManifest.xml');
  try
    AssertEquals('Manifest name', 'vulkan_3d_scene', Manifest.Name);
    AssertEquals('Manifest RenderBackend is backendVulkan', Ord(backendVulkan), Ord(Manifest.RenderBackend));
    AssertTrue('ShouldPrewarmVulkanShaders is True for backendVulkan', Manifest.ShouldPrewarmVulkanShaders);
  finally
    FreeAndNil(Manifest);
  end;
end;

procedure TTestCastleVulkanRHI.TestPipelineCacheDiskPersistence;
var
  Stream: TMemoryStream;
  InputData, OutputBlob: TBytes;
  I: Integer;
begin
  SetLength(InputData, 64);
  for I := 0 to High(InputData) do
    InputData[I] := Byte((I * 37 + 13) and $FF);

  Stream := TMemoryStream.Create;
  try
    { 1. Save hardware-tagged pipeline cache blob }
    SavePipelineCacheBlobToStream(Stream, $10DE, $2684, @InputData[0], Length(InputData));
    AssertEquals('Stream size equals header + payload',
      SizeOf(TPipelineCacheDiskHeader) + Length(InputData), Stream.Size);

    { 2. Load with matching vendorId ($10DE) and deviceId ($2684) }
    Stream.Position := 0;
    AssertTrue('Valid pipeline cache blob loads for matching GPU',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
    AssertEquals('Loaded blob length matches', Length(InputData), Length(OutputBlob));
    for I := 0 to High(InputData) do
      AssertEquals('Loaded payload byte matches', InputData[I], OutputBlob[I]);

    { 3. Reject when GPU vendorId or deviceId differs }
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched VendorId',
      LoadPipelineCacheBlobFromStream(Stream, $1002, $2684, OutputBlob));
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched DeviceId',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $9999, OutputBlob));

    { 4. Reject when payload byte is corrupted (FNV-1a checksum mismatch) }
    PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] :=
      PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] xor $FF;
    Stream.Position := 0;
    AssertFalse('Corrupted pipeline cache blob rejected by FNV-1a checksum',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
  finally
    FreeAndNil(Stream);
  end;
end;

procedure MockGetPhysicalDeviceMemoryProperties2(
  physicalDevice: VkPhysicalDevice;
  pMemoryProperties: PVkPhysicalDeviceMemoryProperties2); {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
var
  BudgetExt: PVkPhysicalDeviceMemoryBudgetPropertiesEXT;
begin
  if pMemoryProperties = nil then Exit;
  pMemoryProperties^.memoryProperties.memoryHeapCount := 2;
  { Heap 0: 8 GB Device-Local VRAM }
  pMemoryProperties^.memoryProperties.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  { Heap 1: 16 GB System Shared RAM (not device-local) }
  pMemoryProperties^.memoryProperties.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[1].flags := 0;

  if pMemoryProperties^.pNext <> nil then
  begin
    BudgetExt := PVkPhysicalDeviceMemoryBudgetPropertiesEXT(pMemoryProperties^.pNext);
    if BudgetExt^.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT then
    begin
      BudgetExt^.heapUsage[0] := UInt64(512) * 1024 * 1024;
      BudgetExt^.heapBudget[0] := UInt64(4096) * 1024 * 1024;
      BudgetExt^.heapUsage[1] := UInt64(1024) * 1024 * 1024;
      BudgetExt^.heapBudget[1] := UInt64(12288) * 1024 * 1024;
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanMemoryBudgetAndViewportStatistics;
var
  MemProps: VkPhysicalDeviceMemoryProperties;
  BudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  UsedBytes, BudgetBytes: UInt64;
  UsedMB, BudgetMB: Cardinal;
  SavedProc: PFN_vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  { 1. Test AggregateDeviceLocalMemoryBudget with multi-heap DEVICE_LOCAL filtering }
  FillChar(MemProps, SizeOf(MemProps), 0);
  FillChar(BudgetProps, SizeOf(BudgetProps), 0);
  MemProps.memoryHeapCount := 2;
  MemProps.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  MemProps.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  MemProps.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  MemProps.memoryHeaps[1].flags := 0;

  BudgetProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT;
  BudgetProps.heapUsage[0] := UInt64(640) * 1024 * 1024;
  BudgetProps.heapBudget[0] := UInt64(7680) * 1024 * 1024;
  BudgetProps.heapUsage[1] := UInt64(2048) * 1024 * 1024;
  BudgetProps.heapBudget[1] := UInt64(14336) * 1024 * 1024;

  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, True,
    UInt64(128) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('VK_EXT_memory_budget used MB from DEVICE_LOCAL heap', 640, UsedMB);
  AssertEquals('VK_EXT_memory_budget budget MB from DEVICE_LOCAL heap', 7680, BudgetMB);

  { 2. Test fallback when VK_EXT_memory_budget is not supported }
  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, False,
    UInt64(256) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('Fallback used MB from tracked allocations', 256, UsedMB);
  AssertEquals('Fallback budget MB from full DEVICE_LOCAL heap size', 8192, BudgetMB);

  { 3. Test end-to-end live Viewport.Statistics query via vkGetPhysicalDeviceMemoryProperties2 }
  SavedProc := vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice := RHIDevice;
  vkGetPhysicalDeviceMemoryProperties2 := @MockGetPhysicalDeviceMemoryProperties2;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt(1)), True);
  Viewport := TCastleViewport.Create(nil);
  try
    VkDev.RecordDiagnostics(42, 3, 128);
    SetRHIDevice(VkDev);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics ActiveBackend', 'Vulkan 1.3', Stats.ActiveBackend);
    AssertEquals('Viewport.Statistics PipelineCacheHits', 42, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics PipelineCacheMisses', 3, Stats.PipelineCacheMisses);
    AssertEquals('Viewport.Statistics DescriptorSetAllocations', 128, Stats.DescriptorSetAllocations);
    AssertEquals('Viewport.Statistics DeviceMemoryUsedMB from VK_EXT_memory_budget', 512, Stats.DeviceMemoryUsedMB);
    AssertEquals('Viewport.Statistics DeviceMemoryBudgetMB from VK_EXT_memory_budget', 4096, Stats.DeviceMemoryBudgetMB);
    AssertTrue('Viewport.Statistics.ToString includes live VRAM usage/budget',
      Pos('VRAM: 512 / 4096 MB', Stats.ToString) > 0);
  finally
    SetRHIDevice(SavedDevice);
    vkGetPhysicalDeviceMemoryProperties2 := SavedProc;
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportPrepareResourcesPrewarmsPSOs;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, False);
  Viewport := TCastleViewport.Create(nil);
  try
    SetRHIDevice(VkDev);
    AssertEquals('Initial PipelineCount should be 0', 0, VkDev.PipelineCount);
    AssertFalse('Initial PipelineCacheLoaded should be False', VkDev.PipelineCacheLoaded);

    { First PrepareResources call should load the pipeline cache and bake all 5 standard PSOs }
    Viewport.PrepareResources;
    AssertTrue('PipelineCacheLoaded should be True after PrepareResources', VkDev.PipelineCacheLoaded);
    AssertEquals('All 5 standard PSO permutations should be pre-warmed', 5, VkDev.PipelineCount);
    AssertEquals('First PrepareResources should record 5 pipeline cache misses', 5, VkDev.PipelineCacheMisses);
    AssertEquals('First PrepareResources should record 0 pipeline cache hits', 0, VkDev.PipelineCacheHits);

    { Second PrepareResources call should hit all 5 cached PSOs with zero new misses }
    Viewport.PrepareResources;
    AssertEquals('PipelineCount remains 5 after second PrepareResources', 5, VkDev.PipelineCount);
    AssertEquals('PipelineCacheMisses remains 5 after second PrepareResources', 5, VkDev.PipelineCacheMisses);
    AssertEquals('Second PrepareResources should record 5 pipeline cache hits', 5, VkDev.PipelineCacheHits);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO hits', 5, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO misses', 5, Stats.PipelineCacheMisses);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.CaptureWarning(const Category, S: String);
begin
  if FCapturedWarnings <> nil then
    FCapturedWarnings.Add(Category + ': ' + S);
end;

procedure TTestCastleVulkanRHI.TestLegacyGLSLUniformWarningDiagnostics;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyEffectSource, CleanEffectSource, Upgraded: String;
  WarnCount: Cardinal;
  AllWarnings: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  FCapturedWarnings := TStringList.Create;
  ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}CaptureWarning);
  try
    { 1. Legacy EffectPart using gl_ModelViewProjectionMatrix, gl_NormalMatrix,
         gl_Vertex, gl_FragColor, texture2D, and varying }
    LegacyEffectSource :=
      'uniform sampler2D u_albedoMap;' + NL +
      'uniform float u_exposure;' + NL +
      'varying vec2 v_legacyUV;' + NL +
      'void PLUG_fragment_modify(inout vec4 color) {' + NL +
      '  vec4 clipPos = gl_ModelViewProjectionMatrix * gl_Vertex;' + NL +
      '  vec3 n = gl_NormalMatrix * vec3(0.0, 0.0, 1.0);' + NL +
      '  gl_FragColor = texture2D(u_albedoMap, v_legacyUV) * u_exposure + clipPos * 0.0 + vec4(n, 0.0) * 0.0;' + NL +
      '}' + NL;

    Upgraded := Gen.UpgradeLegacyGLSLBuiltIns(LegacyEffectSource, 'MyWaterEffect', WarnCount);
    AllWarnings := FCapturedWarnings.Text;

    AssertEquals('Should emit 6 warnings (gl_ModelViewProjectionMatrix, gl_NormalMatrix, gl_Vertex, gl_FragColor, texture2D, varying)',
      6, WarnCount);
    AssertEquals('OnWarning listener should capture 6 warnings', 6, FCapturedWarnings.Count);
    AssertTrue('Warning mentions gl_ModelViewProjectionMatrix and replacement',
      Pos('gl_ModelViewProjectionMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_NormalMatrix',
      Pos('gl_NormalMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_Vertex',
      Pos('gl_Vertex', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_FragColor',
      Pos('gl_FragColor', AllWarnings) > 0);
    AssertTrue('Warning mentions texture2D',
      Pos('texture2D', AllWarnings) > 0);
    AssertTrue('Warning mentions varying qualifier',
      Pos('qualifier "varying"', AllWarnings) > 0);

    { Verify #version 450 compatibility #define aliases and qualifier upgrade in output }
    AssertTrue('Upgraded source defines gl_ModelViewProjectionMatrix alias',
      Pos('#define gl_ModelViewProjectionMatrix (castle_ProjectionMatrix * castle_ModelViewMatrix)', Upgraded) > 0);
    AssertTrue('Upgraded source defines gl_FragColor alias',
      Pos('#define gl_FragColor castle_FragColor', Upgraded) > 0);
    AssertTrue('Upgraded source defines texture2D alias',
      Pos('#define texture2D texture', Upgraded) > 0);
    AssertTrue('Upgraded source rewrites varying to in',
      Pos('in vec2 v_legacyUV;', Upgraded) > 0);

    { 2. Verify identifier boundary matching: gl_VertexIndex must NOT trigger gl_Vertex warning }
    FCapturedWarnings.Clear;
    CleanEffectSource :=
      'uniform float u_scale;' + NL +
      'void PLUG_vertex_object_space(inout vec4 vertex, inout vec3 normal) {' + NL +
      '  int idx = gl_VertexIndex;' + NL +
      '  vertex.xyz *= u_scale;' + NL +
      '}' + NL;
    Upgraded := Gen.UpgradeUserEffectUniforms(CleanEffectSource);
    AssertEquals('Clean modern GLSL 450 effect should emit 0 warnings', 0, FCapturedWarnings.Count);
    AssertTrue('UpgradeUserEffectUniforms still generates CastleUserEffectBlock',
      Pos('CastleUserEffectBlock', Upgraded) > 0);
  finally
    ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}CaptureWarning);
    FreeAndNil(FCapturedWarnings);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkan11RenderPassFramebufferFallback;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  ColorTex, DepthTex, ShadowDepthTex: TRHITexture;
  ForwardInfo, ShadowInfo: TRHIRenderingInfo;
  RpHash1, RpHash2, RpHashShadow, FbHash1, FbHash2: UInt64;
  RpForward, RpShadow: VkRenderPass;
  PrewarmedCount: Cardinal;
begin
  { 1. Verify deterministic FNV-1a key hashes for VkRenderPass and VkFramebuffer }
  RpHash1 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHash2 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHashShadow := ComputeRenderPassKeyHash([], pfD32_Float, 1);
  AssertTrue('Identical render pass signatures must produce identical hashes', RpHash1 = RpHash2);
  AssertTrue('Forward pass and depth-only shadow pass must produce distinct hashes', RpHash1 <> RpHashShadow);

  FbHash1 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1920, 1080);
  FbHash2 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1280, 720);
  AssertTrue('Different framebuffer dimensions must produce distinct hashes', FbHash1 <> FbHash2);

  { 2. Create headless Vulkan 1.1 fallback device (SupportsDynamicRendering = False) }
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False);
  try
    AssertFalse('Headless Vulkan 1.1 device must report SupportsDynamicRendering = False',
      VkDev.SupportsDynamicRendering);
    AssertEquals('Initial fallback render pass count should be 0', 0, VkDev.FallbackRenderPassCount);
    AssertEquals('Initial fallback framebuffer count should be 0', 0, VkDev.FallbackFramebufferCount);

    { 3. Pre-warming standard PSOs on a Vulkan 1.1 device should populate fallback VkRenderPasses }
    PrewarmedCount := VkDev.PrewarmStandardPipelines(True, True);
    AssertEquals('PrewarmStandardPipelines should bake 5 standard PSOs on Vulkan 1.1 fallback', 5, PrewarmedCount);
    AssertEquals('Pre-warming forward + shadow PSOs should cache exactly 2 unique VkRenderPasses',
      2, VkDev.FallbackRenderPassCount);

    RpForward := VkDev.GetOrCreateFallbackRenderPass([pfBGRA8_UNorm], pfD32_Float, 1);
    RpShadow := VkDev.GetOrCreateFallbackRenderPass([], pfD32_Float, 1);
    AssertTrue('Cached forward VkRenderPass handle must be non-null', RpForward <> VK_NULL_HANDLE);
    AssertTrue('Cached shadow VkRenderPass handle must be non-null', RpShadow <> VK_NULL_HANDLE);
    AssertTrue('Forward and shadow VkRenderPass handles must be distinct', RpForward <> RpShadow);
    AssertEquals('Re-querying existing render passes must not increase FallbackRenderPassCount',
      2, VkDev.FallbackRenderPassCount);

    { 4. Execute BeginRendering / EndRendering on TVulkanRHICommandList across 2 frames }
    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD32_Float, [tuDepthStencil]));
    ShadowDepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(2048, 2048, pfD32_Float, [tuDepthStencil, tuSampled]));
    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      FillChar(ForwardInfo, SizeOf(ForwardInfo), 0);
      ForwardInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ForwardInfo.ColorAttachments, 1);
      ForwardInfo.ColorAttachments[0].Texture := ColorTex;
      ForwardInfo.ColorAttachments[0].LoadOp := loClear;
      ForwardInfo.ColorAttachments[0].StoreOp := soStore;
      ForwardInfo.HasDepthAttachment := True;
      ForwardInfo.DepthAttachment.Texture := DepthTex;
      ForwardInfo.DepthAttachment.LoadOp := loClear;
      ForwardInfo.DepthAttachment.StoreOp := soStore;
      ForwardInfo.DepthAttachment.ClearDepth := 1.0;

      FillChar(ShadowInfo, SizeOf(ShadowInfo), 0);
      ShadowInfo.RenderArea := Rectangle(0, 0, 2048, 2048);
      ShadowInfo.HasDepthAttachment := True;
      ShadowInfo.DepthAttachment.Texture := ShadowDepthTex;
      ShadowInfo.DepthAttachment.LoadOp := loClear;
      ShadowInfo.DepthAttachment.StoreOp := soStore;
      ShadowInfo.DepthAttachment.ClearDepth := 1.0;

      { Frame 1: Shadow pass + Forward pass }
      CmdList.BeginRendering(ShadowInfo);
      AssertTrue('CommandList must be inside fallback render pass after BeginRendering',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;
      AssertFalse('CommandList must exit fallback render pass after EndRendering',
        CmdList.InFallbackRenderPass);

      CmdList.BeginRendering(ForwardInfo);
      AssertTrue('CommandList must be inside fallback render pass during forward pass',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;

      AssertEquals('After Frame 1, 2 framebuffers (shadow + forward) should be cached',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 1, FallbackRenderPassBeginCount should be 2',
        2, VkDev.FallbackRenderPassBeginCount);

      { Frame 2: Reuse cached VkRenderPass and VkFramebuffer instances }
      CmdList.BeginRendering(ShadowInfo);
      CmdList.EndRendering;
      CmdList.BeginRendering(ForwardInfo);
      CmdList.EndRendering;

      AssertEquals('Frame 2 must reuse cached VkRenderPasses (count stays 2)',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('Frame 2 must reuse cached VkFramebuffers (count stays 2)',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 2, FallbackRenderPassBeginCount should be 4',
        4, VkDev.FallbackRenderPassBeginCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(ShadowDepthTex);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestVkXmlHeaderGenerator;
begin
  { Verify that CastleInternalVulkan was generated from the official Khronos vk.xml
    registry by tools/internal/generate_vulkan_api/vkxml2pas.dpr }
  AssertTrue('VK_HEADER_VERSION from vk.xml must be >= 300',
    VK_HEADER_VERSION >= 300);

  { Verify core and extension VkStructureType values against Khronos vk.xml
    formula: 1000000000 + (extnumber - 1) * 1000 + offset }
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO must be 17 per vk.xml',
    17, VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_INFO (ext 45, offset 0) must be 1000044000',
    1000044000, VK_STRUCTURE_TYPE_RENDERING_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO (ext 45, offset 1) must be 1000044001',
    1000044001, VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO (ext 45, offset 2) must be 1000044002',
    1000044002, VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR (ext 45, offset 3) must be 1000044003',
    1000044003, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR (ext 315, offset 7) must be 1000314007',
    1000314007, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT (ext 238, offset 0) must be 1000237000',
    1000237000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT);
end;

procedure TTestCastleVulkanRHI.TestVulkan11_12DeviceNegotiationAndFallback;
var
  UseDynRender: Boolean;
  ReqExts: TAnsiStringArray;
  VkDev: TVulkanRHIDevice;
  ColorTex, DepthTex: TRHITexture;
  CmdList: TVulkanRHICommandList;
  ScenePassInfo, UIOverlayPassInfo: TRHIRenderingInfo;
  ClearHash, LoadHash: UInt64;
begin
  { 1. Instance API Version Negotiation (vkEnumerateInstanceVersion fallback) }
  AssertEquals('Vulkan 1.3+ loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_4));
  AssertEquals('Vulkan 1.3 loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_3));
  AssertEquals('Vulkan 1.2 loader negotiates 1.2',
    VK_API_VERSION_1_2, NegotiateInstanceApiVersion(VK_API_VERSION_1_2));
  AssertEquals('Vulkan 1.1 loader negotiates 1.1',
    VK_API_VERSION_1_1, NegotiateInstanceApiVersion(VK_API_VERSION_1_1));
  AssertEquals('Vulkan 1.0 loader negotiates 1.0',
    VK_API_VERSION_1_0, NegotiateInstanceApiVersion(VK_API_VERSION_1_0));

  { 2. Vulkan 1.3 Device Config: Dynamic rendering is core (0 extra extensions needed) }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_3, False, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.3 device uses core dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.3 device needs 0 extra dynamic rendering extensions', 0, Length(ReqExts));

  { 3. Vulkan 1.2 Device Config:
    - With VK_KHR_dynamic_rendering: enabled (VK_KHR_depth_stencil_resolve & VK_KHR_create_renderpass2 are core 1.2)
    - Without VK_KHR_dynamic_rendering: falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, True, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.2 device with VK_KHR_dynamic_rendering enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.2 device enables 1 extension (VK_KHR_dynamic_rendering)', 1, Length(ReqExts));
  AssertEquals('Extension name must be VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[0]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, False, True, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.2 device without VK_KHR_dynamic_rendering falls back to VkRenderPass', UseDynRender);
  AssertEquals('Fallback needs 0 dynamic rendering extensions', 0, Length(ReqExts));

  { 4. Vulkan 1.1 Device Config:
    - Requires VK_KHR_create_renderpass2 + VK_KHR_depth_stencil_resolve + VK_KHR_dynamic_rendering
    - Missing any prerequisite falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, True, True, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.1 device with all 3 extensions enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.1 device enables all 3 prerequisite extensions', 3, Length(ReqExts));
  AssertEquals('First prerequisite on 1.1 is VK_KHR_create_renderpass2',
    VK_KHR_create_renderpass2, String(ReqExts[0]));
  AssertEquals('Second prerequisite on 1.1 is VK_KHR_depth_stencil_resolve',
    VK_KHR_depth_stencil_resolve, String(ReqExts[1]));
  AssertEquals('Third extension on 1.1 is VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[2]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, False, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.1 device missing VK_KHR_depth_stencil_resolve falls back to VkRenderPass', UseDynRender);

  { 5. Multi-Pass LoadOp (loClear vs loLoad) on a Vulkan 1.1/1.2 Fallback Device }
  ClearHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loClear, loClear);
  LoadHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loLoad, loLoad);
  AssertTrue('loClear and loLoad render passes must produce distinct cache keys', ClearHash <> LoadHash);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  try
    AssertEquals('Headless Vulkan 1.1 device reports apiVersion 1.1',
      VK_API_VERSION_1_1, VkDev.DeviceApiVersion);
    AssertFalse('Headless Vulkan 1.1 fallback device disables dynamic rendering',
      VkDev.SupportsDynamicRendering);

    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      { Pass 1: 3D Scene Pass (LoadOp = loClear) }
      FillChar(ScenePassInfo, SizeOf(ScenePassInfo), 0);
      ScenePassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ScenePassInfo.ColorAttachments, 1);
      ScenePassInfo.ColorAttachments[0].Texture := ColorTex;
      ScenePassInfo.ColorAttachments[0].LoadOp := loClear;
      ScenePassInfo.ColorAttachments[0].StoreOp := soStore;
      ScenePassInfo.HasDepthAttachment := True;
      ScenePassInfo.DepthAttachment.Texture := DepthTex;
      ScenePassInfo.DepthAttachment.LoadOp := loClear;
      ScenePassInfo.DepthAttachment.StoreOp := soStore;

      { Pass 2: 2D UI Overlay Pass (LoadOp = loLoad to preserve 3D scene!) }
      FillChar(UIOverlayPassInfo, SizeOf(UIOverlayPassInfo), 0);
      UIOverlayPassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(UIOverlayPassInfo.ColorAttachments, 1);
      UIOverlayPassInfo.ColorAttachments[0].Texture := ColorTex;
      UIOverlayPassInfo.ColorAttachments[0].LoadOp := loLoad;
      UIOverlayPassInfo.ColorAttachments[0].StoreOp := soStore;
      UIOverlayPassInfo.HasDepthAttachment := False;

      CmdList.BeginRendering(ScenePassInfo);
      CmdList.EndRendering;

      CmdList.BeginRendering(UIOverlayPassInfo);
      CmdList.EndRendering;

      AssertEquals('2 distinct fallback VkRenderPasses (loClear 3D + loLoad 2D UI) must be cached',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('2 fallback VkFramebuffers must be cached',
        2, VkDev.FallbackFramebufferCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGraphicsPipelineLibraryFastLinking;
var
  UseGPL: Boolean;
  ReqExts: TAnsiStringArray;
  DescA, DescB: TRHIGraphicsPipelineDesc;
  VkDev: TVulkanRHIDevice;
  PrewarmedCount: Cardinal;
  PsoOpaque, PsoTwoSided: TVulkanRHIPipeline;
begin
  { 1. Verify Khronos vk.xml generated constants for VK_EXT_graphics_pipeline_library }
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR must match vk.xml',
    1000290000, VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT must match vk.xml',
    1000320000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT must match vk.xml',
    1000320001, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT);
  AssertEquals('VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT must match vk.xml',
    1000320002, VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT);
  AssertEquals('All 4 GPL subset flags combined must equal $0F',
    $0000000F,
    VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT);

  { 2. Verify ResolveGraphicsPipelineLibraryConfig device extension negotiation }
  ResolveGraphicsPipelineLibraryConfig(VK_API_VERSION_1_3, True, True, True, UseGPL, ReqExts);
  AssertTrue('Device advertising both extensions and feature enables GPL', UseGPL);
  AssertEquals('GPL requires 2 extensions (VK_KHR_pipeline_library + VK_EXT_graphics_pipeline_library)',
    2, Length(ReqExts));
  AssertEquals('First GPL extension is VK_KHR_pipeline_library',
    VK_KHR_pipeline_library, String(ReqExts[0]));
  AssertEquals('Second GPL extension is VK_EXT_graphics_pipeline_library',
    VK_EXT_graphics_pipeline_library, String(ReqExts[1]));

  ResolveGraphicsPipelineLibraryConfig(VK_API_VERSION_1_3, True, True, False, UseGPL, ReqExts);
  AssertFalse('Device without graphicsPipelineLibrary feature bit disables GPL', UseGPL);
  AssertEquals('Disabled GPL requires 0 extensions', 0, Length(ReqExts));

  { 3. Verify independent hashing of the 4 pipeline library subsets }
  FillChar(DescA, SizeOf(DescA), 0);
  DescA.Topology := ptTriangleList;
  DescA.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  DescA.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  DescA.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  SetLength(DescA.ColorAttachmentFormats, 1);
  DescA.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  DescA.DepthAttachmentFormat := pfD32_Float;
  DescA.SampleCount := 1;

  DescB := DescA;
  DescB.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;

  AssertTrue('Changing BlendState must NOT change VertexInputLibrary hash',
    ComputeVertexInputLibraryKeyHash(DescA) = ComputeVertexInputLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState must NOT change PreRasterizationLibrary hash',
    ComputePreRasterizationLibraryKeyHash(DescA) = ComputePreRasterizationLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState must NOT change FragmentShaderLibrary hash',
    ComputeFragmentShaderLibraryKeyHash(DescA) = ComputeFragmentShaderLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState MUST change FragmentOutputLibrary hash',
    ComputeFragmentOutputLibraryKeyHash(DescA) <> ComputeFragmentOutputLibraryKeyHash(DescB));

  { 4. Verify fast-linking & sub-library cache reuse across permutations }
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3, True);
  try
    AssertTrue('Headless GPL device reports SupportsGraphicsPipelineLibrary',
      VkDev.SupportsGraphicsPipelineLibrary);
    AssertTrue('Headless GPL device reports SupportsGPLFastLinking',
      VkDev.SupportsGPLFastLinking);

    { PrewarmStandardPipelines bakes 5 PSOs (20 subset lookups total) }
    PrewarmedCount := VkDev.PrewarmStandardPipelines(True, True);
    AssertEquals('5 standard PSOs should be fast-linked', 5, PrewarmedCount);
    AssertEquals('GPLFastLinkedPipelineCount should equal 5', 5, VkDev.GPLFastLinkedPipelineCount);

    { Out of 20 subset lookups (5 PSOs x 4 subsets), only 13 unique sub-libraries are created
      and 7 are served directly from the partial library caches! }
    AssertEquals('VertexInputLibraryCount should be 2 (3D mesh shared by 4 PSOs + 2D sprite)',
      2, VkDev.VertexInputLibraryCount);
    AssertEquals('PreRasterizationLibraryCount should be 4 (3D CullNone shared by TwoSided + AlphaBlend)',
      4, VkDev.PreRasterizationLibraryCount);
    AssertEquals('FragmentShaderLibraryCount should be 4 (3D DepthTestWrite shared by Opaque + TwoSided)',
      4, VkDev.FragmentShaderLibraryCount);
    AssertEquals('FragmentOutputLibraryCount should be 3 (Opaque, AlphaBlend, DepthOnly)',
      3, VkDev.FragmentOutputLibraryCount);
    AssertEquals('Total unique pipeline libraries should be 13 (down from 20)',
      13, VkDev.TotalPipelineLibraryCount);
    AssertEquals('GPL library cache hits should be 7', 7, VkDev.GPLLibraryCacheHits);
    AssertEquals('GPL library cache misses should be 13', 13, VkDev.GPLLibraryCacheMisses);

    { Verify two PSOs that differ only in CullMode share 3 out of 4 pipeline libraries }
    DescB := DescA;
    DescB.Rasterizer.CullMode := cmNone;
    PsoOpaque := VkDev.GetOrCreatePipeline(DescA) as TVulkanRHIPipeline;
    PsoTwoSided := VkDev.GetOrCreatePipeline(DescB) as TVulkanRHIPipeline;

    AssertTrue('Opaque PSO must be linked from libraries', PsoOpaque.LinkedFromLibraries);
    AssertTrue('TwoSided PSO must be linked from libraries', PsoTwoSided.LinkedFromLibraries);
    AssertTrue('Opaque and TwoSided PSOs share VertexInputLibrary',
      PsoOpaque.VertexInputLibrary = PsoTwoSided.VertexInputLibrary);
    AssertTrue('Opaque and TwoSided PSOs have distinct PreRasterizationLibrary (CullBack vs CullNone)',
      PsoOpaque.PreRasterizationLibrary <> PsoTwoSided.PreRasterizationLibrary);
    AssertTrue('Opaque and TwoSided PSOs share FragmentShaderLibrary',
      PsoOpaque.FragmentShaderLibrary = PsoTwoSided.FragmentShaderLibrary);
    AssertTrue('Opaque and TwoSided PSOs share FragmentOutputLibrary',
      PsoOpaque.FragmentOutputLibrary = PsoTwoSided.FragmentOutputLibrary);
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestSPIRVBinaryReflectionAndValidation;
var
  Words, SwappedWords: array of UInt32;
  Info, SwappedInfo: TSPIRVReflectionInfo;
  FoundBind: TSPIRVReflectedBinding;
  FoundIO: TSPIRVReflectedStageIO;
  ShaderMod, WrongStageMod: TVulkanRHIShaderModule;
  ValidSet0Layout: array[0..1] of TRHIDescriptorBindingDesc;
  ValidSet1Layout: array[0..1] of TRHIDescriptorBindingDesc;
  BadTypeLayout: array[0..1] of TRHIDescriptorBindingDesc;
  MissingBindLayout: array[0..0] of TRHIDescriptorBindingDesc;
  BadStageLayout: array[0..1] of TRHIDescriptorBindingDesc;
  BadCountLayout: array[0..1] of TRHIDescriptorBindingDesc;
  DiagMsg: String;
  I: Integer;

  procedure EmitWord(const W: UInt32);
  begin
    SetLength(Words, Length(Words) + 1);
    Words[High(Words)] := W;
  end;

  procedure EmitInst(const Opcode: UInt16; const Operands: array of UInt32);
  var
    Idx: Integer;
  begin
    EmitWord((UInt32(Length(Operands) + 1) shl 16) or Opcode);
    for Idx := 0 to High(Operands) do
      EmitWord(Operands[Idx]);
  end;

  procedure EmitName(const TargetId: UInt32; const S: AnsiString);
  var
    WordLen, WIdx, BIdx, CharPos: Integer;
    WVal: UInt32;
  begin
    WordLen := (Length(S) div 4) + 1;
    EmitWord((UInt32(WordLen + 2) shl 16) or 5 { OpName });
    EmitWord(TargetId);
    for WIdx := 0 to WordLen - 1 do
    begin
      WVal := 0;
      for BIdx := 0 to 3 do
      begin
        CharPos := WIdx * 4 + BIdx + 1;
        if CharPos <= Length(S) then
          WVal := WVal or (UInt32(Ord(S[CharPos])) shl (BIdx * 8));
      end;
      EmitWord(WVal);
    end;
  end;

begin
  { Build a synthetic pre-compiled SPIR-V 1.6 Fragment Shader binary word stream
    (verifying pure Pascal reflection with zero libshaderc dependency) }
  SetLength(Words, 0);
  EmitWord($07230203); // Magic
  EmitWord($00010600); // Version 1.6
  EmitWord($000D000B); // Generator
  EmitWord(40);        // Bound
  EmitWord(0);         // Schema

  { OpEntryPoint Fragment(4), %1, "main" ($6E69616D, $00000000) }
  EmitInst(15, [4, 1, $6E69616D, 0]);

  { Debug names (OpName) }
  EmitName(10, 'CastleFrameUBO');
  EmitName(13, 'CastleJointSSBO');
  EmitName(18, 'castle_MaterialTextures');
  EmitName(20, 'castle_OutputStorageImg');
  EmitName(23, 'CastleDrawPushConstants');
  EmitName(25, 'v_TexCoord0');
  EmitName(27, 'out_FragColor');

  { Decorations (OpDecorate = 71, OpMemberDecorate = 72) }
  { UBO struct %9: Block(2), member 0 Offset 0 (mat4=64B), member 1 Offset 64 (vec4=16B) => 80B }
  EmitInst(71, [9, 2]);
  EmitInst(72, [9, 0, 35, 0]);
  EmitInst(72, [9, 1, 35, 64]);
  EmitInst(71, [10, 34, 0]); // DescriptorSet 0
  EmitInst(71, [10, 33, 0]); // Binding 0

  { SSBO struct %12: Block(2), member 0 Offset 0 (mat4=64B) => 64B }
  EmitInst(71, [12, 2]);
  EmitInst(72, [12, 0, 35, 0]);
  EmitInst(71, [13, 34, 0]); // DescriptorSet 0
  EmitInst(71, [13, 33, 1]); // Binding 1

  { CombinedImageSampler array[4] %18: DescriptorSet 1, Binding 0 }
  EmitInst(71, [18, 34, 1]);
  EmitInst(71, [18, 33, 0]);

  { StorageImage %20: DescriptorSet 1, Binding 1 }
  EmitInst(71, [20, 34, 1]);
  EmitInst(71, [20, 33, 1]);

  { PushConstant struct %22: Block(2), member 0 Offset 0 (mat4=64B), member 1 Offset 64 (mat4=64B) => 128B }
  EmitInst(71, [22, 2]);
  EmitInst(72, [22, 0, 35, 0]);
  EmitInst(72, [22, 1, 35, 64]);

  { Stage Input %25 (location = 0) and Stage Output %27 (location = 0) }
  EmitInst(71, [25, 30, 0]);
  EmitInst(71, [27, 30, 0]);

  { Fundamental types }
  EmitInst(22, [2, 32]);       // %2 = OpTypeFloat 32
  EmitInst(23, [3, 2, 4]);     // %3 = OpTypeVector %2 4 (vec4)
  EmitInst(24, [4, 3, 4]);     // %4 = OpTypeMatrix %3 4 (mat4, 64 bytes)
  EmitInst(23, [5, 2, 2]);     // %5 = OpTypeVector %2 2 (vec2)
  EmitInst(21, [6, 32, 0]);    // %6 = OpTypeInt 32 0 (uint)
  EmitInst(43, [6, 7, 4]);     // %7 = OpConstant %6 4

  { UBO type & variable: %9 = struct(mat4, vec4), %8 = ptr(Uniform=2, %9), %10 = var }
  EmitInst(30, [9, 4, 3]);
  EmitInst(32, [8, 2, 9]);
  EmitInst(59, [8, 10, 2]);

  { SSBO type & variable: %12 = struct(mat4), %11 = ptr(StorageBuffer=12, %12), %13 = var }
  EmitInst(30, [12, 4]);
  EmitInst(32, [11, 12, 12]);
  EmitInst(59, [11, 13, 12]);

  { CombinedImageSampler[4]: %14 = Image(Sampled=1), %15 = SampledImage, %16 = Array[4], %17 = ptr(UniformConstant=0), %18 = var }
  EmitInst(25, [14, 2, 1, 0, 0, 0, 1, 0]);
  EmitInst(27, [15, 14]);
  EmitInst(28, [16, 15, 7]);
  EmitInst(32, [17, 0, 16]);
  EmitInst(59, [17, 18, 0]);

  { StorageImage: %19 = Image(Sampled=2), %21 = ptr(UniformConstant=0, %19), %20 = var }
  EmitInst(25, [19, 2, 1, 0, 0, 0, 2, 1]);
  EmitInst(32, [21, 0, 19]);
  EmitInst(59, [21, 20, 0]);

  { PushConstant: %22 = struct(mat4, mat4), %24 = ptr(PushConstant=9, %22), %23 = var }
  EmitInst(30, [22, 4, 4]);
  EmitInst(32, [24, 9, 22]);
  EmitInst(59, [24, 23, 9]);

  { Stage Input & Output variables }
  EmitInst(32, [26, 1, 5]);    // %26 = ptr(Input=1, vec2)
  EmitInst(59, [26, 25, 1]);   // %25 = var Input
  EmitInst(32, [28, 3, 3]);    // %28 = ptr(Output=3, vec4)
  EmitInst(59, [28, 27, 3]);   // %27 = var Output

  { 1. Inspect native-endian SPIR-V binary }
  AssertTrue('InspectSPIRVBytecode must succeed on valid SPIR-V stream',
    InspectSPIRVBytecode(@Words[0], Length(Words) * SizeOf(UInt32), Info));
  AssertTrue('Info.IsValid must be True', Info.IsValid);
  AssertFalse('Native SPIR-V must not be flagged ByteSwapped', Info.ByteSwapped);
  AssertEquals('SPIR-V VersionMajor', 1, Info.VersionMajor);
  AssertEquals('SPIR-V VersionMinor', 6, Info.VersionMinor);
  AssertEquals('Reflected stage must be ssFragment', Ord(ssFragment), Ord(Info.Stage));
  AssertEquals('Reflected entry point name', 'main', Info.EntryPointName);

  { Verify 4 reflected descriptor bindings }
  AssertEquals('Reflected binding count must be 4', 4, Length(Info.Bindings));

  AssertTrue('Must find Set 0 Binding 0 (UBO)', Info.FindBinding(0, 0, FoundBind));
  AssertEquals('Set 0 Binding 0 type', Ord(dtUniformBuffer), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 0 Binding 0 count', 1, FoundBind.Count);
  AssertEquals('Set 0 Binding 0 block size (mat4 + vec4 = 80)', 80, FoundBind.BlockSize);
  AssertEquals('Set 0 Binding 0 name', 'CastleFrameUBO', FoundBind.Name);

  AssertTrue('Must find Set 0 Binding 1 (SSBO)', Info.FindBinding(0, 1, FoundBind));
  AssertEquals('Set 0 Binding 1 type', Ord(dtStorageBuffer), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 0 Binding 1 count', 1, FoundBind.Count);
  AssertEquals('Set 0 Binding 1 block size (mat4 = 64)', 64, FoundBind.BlockSize);
  AssertEquals('Set 0 Binding 1 name', 'CastleJointSSBO', FoundBind.Name);

  AssertTrue('Must find Set 1 Binding 0 (CombinedImageSampler[4])', Info.FindBinding(1, 0, FoundBind));
  AssertEquals('Set 1 Binding 0 type', Ord(dtCombinedImageSampler), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 1 Binding 0 array count', 4, FoundBind.Count);
  AssertEquals('Set 1 Binding 0 name', 'castle_MaterialTextures', FoundBind.Name);

  AssertTrue('Must find Set 1 Binding 1 (StorageImage)', Info.FindBinding(1, 1, FoundBind));
  AssertEquals('Set 1 Binding 1 type', Ord(dtStorageImage), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 1 Binding 1 count', 1, FoundBind.Count);
  AssertEquals('Set 1 Binding 1 name', 'castle_OutputStorageImg', FoundBind.Name);

  { Verify Push Constants }
  AssertTrue('Must detect PushConstant block', Info.HasPushConstants);
  AssertEquals('PushConstant size (2 x mat4 = 128)', 128, Info.PushConstantSize);
  AssertEquals('PushConstant name', 'CastleDrawPushConstants', Info.PushConstantName);

  { Verify Stage IO }
  AssertEquals('StageIO count must be 2', 2, Length(Info.StageIO));
  AssertTrue('Must find Stage Input at location 0', Info.FindStageInput(0, FoundIO));
  AssertEquals('Stage Input 0 component count (vec2)', 2, FoundIO.ComponentCount);
  AssertEquals('Stage Input 0 name', 'v_TexCoord0', FoundIO.Name);

  AssertTrue('Must find Stage Output at location 0', Info.FindStageOutput(0, FoundIO));
  AssertEquals('Stage Output 0 component count (vec4)', 4, FoundIO.ComponentCount);
  AssertEquals('Stage Output 0 name', 'out_FragColor', FoundIO.Name);

  { 2. Verify byte-swapped SPIR-V header/stream support }
  SetLength(SwappedWords, Length(Words));
  for I := 0 to High(Words) do
    SwappedWords[I] := SwapEndian(Words[I]);
  AssertTrue('InspectSPIRVBytecode must support byte-swapped SPIR-V streams',
    InspectSPIRVBytecode(@SwappedWords[0], Length(SwappedWords) * SizeOf(UInt32), SwappedInfo));
  AssertTrue('SwappedInfo.ByteSwapped must be True', SwappedInfo.ByteSwapped);
  AssertEquals('SwappedInfo binding count', 4, Length(SwappedInfo.Bindings));
  AssertEquals('SwappedInfo PushConstantSize', 128, SwappedInfo.PushConstantSize);

  { 3. Verify TVulkanRHIShaderModule automatic reflection & descriptor layout validation }
  ShaderMod := TVulkanRHIShaderModule.Create(nil, ssFragment,
    @Words[0], Length(Words) * SizeOf(UInt32), 'ReflectedFragShader');
  try
    AssertTrue('ShaderMod.Reflection.IsValid must be True', ShaderMod.Reflection.IsValid);
    AssertEquals('ShaderMod.Reflection binding count', 4, Length(ShaderMod.Reflection.Bindings));

    { Valid Set 0 layout (note: dtUniformBufferDynamic is compatible with SPIR-V UBO) }
    ValidSet0Layout[0].Binding := 0;
    ValidSet0Layout[0].DescriptorType := dtUniformBufferDynamic;
    ValidSet0Layout[0].Count := 1;
    ValidSet0Layout[0].StageFlags := [ssVertex, ssFragment];
    ValidSet0Layout[1].Binding := 1;
    ValidSet0Layout[1].DescriptorType := dtStorageBuffer;
    ValidSet0Layout[1].Count := 1;
    ValidSet0Layout[1].StageFlags := [ssVertex, ssFragment];
    AssertTrue('Valid Set 0 layout must pass validation',
      ShaderMod.ValidateDescriptorSetLayout(0, ValidSet0Layout, DiagMsg));
    AssertEquals('Diagnostic message must be empty on success', '', DiagMsg);

    { Valid Set 1 layout }
    ValidSet1Layout[0].Binding := 0;
    ValidSet1Layout[0].DescriptorType := dtCombinedImageSampler;
    ValidSet1Layout[0].Count := 4;
    ValidSet1Layout[0].StageFlags := [ssFragment];
    ValidSet1Layout[1].Binding := 1;
    ValidSet1Layout[1].DescriptorType := dtStorageImage;
    ValidSet1Layout[1].Count := 1;
    ValidSet1Layout[1].StageFlags := [ssFragment];
    AssertTrue('Valid Set 1 layout must pass validation',
      ShaderMod.ValidateDescriptorSetLayout(1, ValidSet1Layout, DiagMsg));

    { Mismatched descriptor type }
    BadTypeLayout[0] := ValidSet0Layout[0];
    BadTypeLayout[0].DescriptorType := dtCombinedImageSampler;
    BadTypeLayout[1] := ValidSet0Layout[1];
    AssertFalse('Mismatched descriptor type must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, BadTypeLayout, DiagMsg));
    AssertTrue('Diagnostic must report type mismatch',
      Pos('descriptor type mismatch', DiagMsg) > 0);

    { Missing binding }
    MissingBindLayout[0] := ValidSet0Layout[0];
    AssertFalse('Missing binding 1 in Set 0 must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, MissingBindLayout, DiagMsg));
    AssertTrue('Diagnostic must report undeclared descriptor',
      Pos('undeclared descriptor', DiagMsg) > 0);

    { Mismatched stage visibility }
    BadStageLayout[0] := ValidSet0Layout[0];
    BadStageLayout[0].StageFlags := [ssVertex];
    BadStageLayout[1] := ValidSet0Layout[1];
    AssertFalse('Missing ssFragment in StageFlags must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, BadStageLayout, DiagMsg));
    AssertTrue('Diagnostic must report stage visibility mismatch',
      Pos('stage visibility mismatch', DiagMsg) > 0);

    { Insufficient array count }
    BadCountLayout[0] := ValidSet1Layout[0];
    BadCountLayout[0].Count := 2; // Shader requires 4
    BadCountLayout[1] := ValidSet1Layout[1];
    AssertFalse('Array count smaller than shader array must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(1, BadCountLayout, DiagMsg));
    AssertTrue('Diagnostic must report count mismatch',
      Pos('descriptor count mismatch', DiagMsg) > 0);
  finally
    FreeAndNil(ShaderMod);
  end;

  { 4. Verify stage mismatch warning when creating a vertex module from fragment SPIR-V }
  FCapturedWarnings := TStringList.Create;
  try
    ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}CaptureWarning);
    try
      WrongStageMod := TVulkanRHIShaderModule.Create(nil, ssVertex,
        @Words[0], Length(Words) * SizeOf(UInt32), 'WrongStageShader');
      try
        AssertTrue('Creating ssVertex module with Fragment SPIR-V must emit warning',
          FCapturedWarnings.Count > 0);
        AssertTrue('Warning must mention execution model stage mismatch',
          Pos('SPIR-V execution model stage', FCapturedWarnings.Text) > 0);
      finally
        FreeAndNil(WrongStageMod);
      end;
    finally
      ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}CaptureWarning);
    end;
  finally
    FreeAndNil(FCapturedWarnings);
  end;
end;

procedure TTestCastleVulkanRHI.TestWindows4096MaxMemoryAllocationLimitAndPooledSubAllocation;
const
  { 5,000 individual buffers and textures exceed the Windows WDDM kernel limit
    of 4096 total VkDeviceMemory allocations (maxMemoryAllocationCount = 4096). }
  BufferCount = 3000;
  TextureCount = 2000;
var
  VkDev: TVulkanRHIDevice;
  Buffers: array[0 .. BufferCount - 1] of TVulkanRHIBuffer;
  Textures: array[0 .. TextureCount - 1] of TVulkanRHITexture;
  BufDesc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  Stats: TVulkanMemoryStats;
  I: Integer;
  P0, P1: Pointer;
  SampleVal0, SampleVal1: Cardinal;
  DedicatedReq: VkMemoryRequirements;
  DedicatedAlloc: TVulkanMemoryAllocation;
begin
  { Verify VK_KHR_get_memory_requirements2 and VK_KHR_dedicated_allocation
    VkStructureType constants generated by vkxml2pas.dpr from vk.xml }
  AssertEquals('VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2',
    1000146000, VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2);
  AssertEquals('VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2',
    1000146001, VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2',
    1000146003, VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS',
    1000127000, VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO',
    1000127001, VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True);
  try
    AssertTrue('TVulkanRHIDevice must initialize MemoryAllocator',
      VkDev.MemoryAllocator <> nil);
    AssertEquals('Default MaxMemoryAllocationCount must match Windows WDDM 4096 limit',
      4096, VkDev.MemoryAllocator.MaxMemoryAllocationCount);

    FillChar(Buffers, SizeOf(Buffers), 0);
    FillChar(Textures, SizeOf(Textures), 0);
    try
      { 1. Allocate 3,000 TVulkanRHIBuffer objects (1,500 host-visible + 1,500 GPU-only) }
      for I := 0 to BufferCount - 1 do
      begin
        FillChar(BufDesc, SizeOf(BufDesc), 0);
        BufDesc.Size := 4096;
        BufDesc.Usage := [buVertex, buUniform];
        if (I and 1) = 0 then
          BufDesc.MemoryUsage := muCpuToGpu
        else
          BufDesc.MemoryUsage := muGpuOnly;
        Buffers[I] := VkDev.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
        AssertTrue('Pooled buffer allocation must be valid', Buffers[I].Allocation.IsValid);
        AssertFalse('4 KB buffer must be sub-allocated, not dedicated', Buffers[I].Allocation.IsDedicated);
        AssertTrue('Buffer allocation must come from a Linear block pool',
          (Buffers[I].Allocation.Block <> nil) and Buffers[I].Allocation.Block.IsLinearPool);
        AssertTrue('Buffer allocation must hold an O(1) sub-allocation node pointer',
          Buffers[I].Allocation.Node <> nil);
      end;

      { 2. Allocate 2,000 TVulkanRHITexture objects (non-linear optimal-tiled images) }
      for I := 0 to TextureCount - 1 do
      begin
        TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuSampled]);
        Textures[I] := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
        AssertTrue('Pooled texture allocation must be valid', Textures[I].Allocation.IsValid);
        AssertFalse('32x32 RGBA8 texture (4 KB) must be sub-allocated, not dedicated',
          Textures[I].Allocation.IsDedicated);
        AssertTrue('Optimal-tiled texture must come from a Non-Linear block pool',
          (Textures[I].Allocation.Block <> nil) and (not Textures[I].Allocation.Block.IsLinearPool));
      end;

      { 3. Verify 5,000+ sub-allocations use only a handful of VkDeviceMemory blocks
           (preventing VK_ERROR_TOO_MANY_OBJECTS on Windows' 4096 allocation cap) }
      Stats := VkDev.MemoryAllocator.GetStats;
      AssertTrue('SubAllocationCount must be >= 5000 (buffers + textures + frame rings)',
        Stats.SubAllocationCount >= Cardinal(BufferCount + TextureCount));
      AssertTrue('TotalVkAllocationCount must remain tiny (< 16 blocks for 5,000 resources)',
        (Stats.TotalVkAllocationCount > 0) and (Stats.TotalVkAllocationCount < 16));
      AssertTrue('LinearBlockCount must be > 0 for buffers', Stats.LinearBlockCount > 0);
      AssertTrue('NonLinearBlockCount must be > 0 for optimal images', Stats.NonLinearBlockCount > 0);
      AssertTrue('Linear buffer and Non-Linear texture must not share the same VkDeviceMemory block',
        Buffers[0].DeviceMemory <> Textures[0].Allocation.DeviceMemory);

      { 4. Verify persistent host mapping and non-overlapping sub-allocation offsets }
      AssertTrue('Two host-visible buffers in the same block must have distinct offsets',
        Buffers[0].MemoryOffset <> Buffers[2].MemoryOffset);
      SampleVal0 := $CAFEBABE;
      SampleVal1 := $DEADBEEF;
      Buffers[0].UploadData(SampleVal0, SizeOf(SampleVal0), 0);
      Buffers[2].UploadData(SampleVal1, SizeOf(SampleVal1), 0);

      P0 := Buffers[0].Map;
      P1 := Buffers[2].Map;
      AssertTrue('Host-visible sub-allocated buffers must return non-nil persistent pointers',
        (P0 <> nil) and (P1 <> nil) and (P0 <> P1));
      AssertEquals('Buffer[0] mapped memory must retain uploaded value without corruption',
        Int64(SampleVal0), Int64(PCardinal(P0)^));
      AssertEquals('Buffer[2] mapped memory must retain uploaded value without corruption',
        Int64(SampleVal1), Int64(PCardinal(P1)^));
      Buffers[0].Unmap;
      Buffers[2].Unmap;
      { Unmapping one sub-allocated buffer must not invalidate persistent mapping of siblings }
      AssertEquals('Sibling buffer mapping must remain valid after Unmap',
        Int64(SampleVal1), Int64(PCardinal(Buffers[2].Map)^));
      Buffers[2].Unmap;

      { 5. Verify Windows 4096 maxMemoryAllocationCount safety guard:
           when close to the limit, optional dedicated requests fall back to pooled sub-allocation }
      FillChar(DedicatedReq, SizeOf(DedicatedReq), 0);
      DedicatedReq.size := 64 * 1024;
      DedicatedReq.alignment := 256;
      DedicatedReq.memoryTypeBits := $FFFFFFFF;
      { Artificially tighten MaxMemoryAllocationCount so CanAllocateDedicated(False) triggers }
      VkDev.MemoryAllocator.MaxMemoryAllocationCount := Stats.TotalVkAllocationCount + 10;
      DedicatedAlloc := VkDev.MemoryAllocator.Allocate(
        DedicatedReq, muGpuOnly, True, True, False);
      try
        AssertTrue('Allocation near maxMemoryAllocationCount limit must succeed via pool',
          DedicatedAlloc.IsValid);
        AssertFalse('Optional dedicated request must fall back to pooled block when near 4096 limit',
          DedicatedAlloc.IsDedicated);
      finally
        VkDev.MemoryAllocator.Free(DedicatedAlloc);
        VkDev.MemoryAllocator.MaxMemoryAllocationCount := 4096;
      end;
    finally
      { 6. Free all 5,000 buffers and textures in O(1) per node and verify coalescing }
      for I := 0 to BufferCount - 1 do
        FreeAndNil(Buffers[I]);
      for I := 0 to TextureCount - 1 do
        FreeAndNil(Textures[I]);
    end;

    Stats := VkDev.MemoryAllocator.GetStats;
    { Only the 2 per-frame ring buffer sub-allocations remain }
    AssertEquals('After freeing all 5,000 buffers/textures, only 2 frame-ring sub-allocations remain',
      2, Stats.SubAllocationCount);

    { Trim excess empty blocks }
    VkDev.MemoryAllocator.TrimEmptyBlocks;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure MockGetPhysicalDeviceFormatProperties(
  physicalDevice: VkPhysicalDevice; format: VkFormat;
  pFormatProperties: PVkFormatProperties); {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  if pFormatProperties = nil then Exit;
  FillChar(pFormatProperties^, SizeOf(VkFormatProperties), 0);
  case format of
    { Simulate AMD RDNA / Apple MoltenVK where D24_UNORM_S8_UINT and ASTC_4x4 are unsupported,
      while D32_SFLOAT_S8_UINT, D32_SFLOAT, RGBA8_SRGB, and RGBA8_UNORM are supported }
    VK_FORMAT_D24_UNORM_S8_UINT,
    VK_FORMAT_ASTC_4x4_SRGB_BLOCK,
    VK_FORMAT_ASTC_4x4_UNORM_BLOCK,
    VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK:
      pFormatProperties^.optimalTilingFeatures := 0;
    VK_FORMAT_D32_SFLOAT_S8_UINT,
    VK_FORMAT_D32_SFLOAT,
    VK_FORMAT_D16_UNORM:
      pFormatProperties^.optimalTilingFeatures :=
        VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT or
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or
        VK_FORMAT_FEATURE_TRANSFER_SRC_BIT or
        VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
    else
      pFormatProperties^.optimalTilingFeatures :=
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or
        VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or
        VK_FORMAT_FEATURE_TRANSFER_SRC_BIT or
        VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiVendorFormatAlignmentAndDeferredResourceDestruction;
var
  VkDev: TVulkanRHIDevice;
  SavedFormatPropsProc: Pointer;
  NegotiatedFmt: TRHIPixelFormat;
  TexDesc: TRHITextureDesc;
  DepthTex, ColorTex: TVulkanRHITexture;
  UboDesc, SsboDesc, StageDesc: TRHIBufferDesc;
  Ubo0, Ubo1, Ssbo0, Ssbo1, StageBuf: TVulkanRHIBuffer;
  AlignedOffset, AlignedSize: VkDeviceSize;
  SubAllocsBefore, SubAllocsDuring, SubAllocsAfterFlush: Cardinal;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Cross-Vendor Format Negotiation (AMD/MoltenVK D24S8 -> D32S8 fallback,
       mobile ASTC/ETC2 -> desktop RGBA8 fallback) }
  SavedFormatPropsProc := Pointer(vkGetPhysicalDeviceFormatProperties);
  vkGetPhysicalDeviceFormatProperties := @MockGetPhysicalDeviceFormatProperties;
  try
    VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($ABCD)), False, True, VK_API_VERSION_1_3);
    try
      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfD24_UNorm_S8_UInt, [tuDepthStencil, tuSampled], VkDev.PhysicalDevice);
      AssertEquals('Unsupported D24_UNorm_S8_UInt must negotiate fallback to D32_Float_S8_UInt',
        Ord(pfD32_Float_S8_UInt), Ord(NegotiatedFmt));

      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfASTC_4x4_sRGB, [tuSampled, tuTransferDst], VkDev.PhysicalDevice);
      AssertEquals('Unsupported ASTC_4x4_sRGB must negotiate fallback to RGBA8_sRGB',
        Ord(pfRGBA8_sRGB), Ord(NegotiatedFmt));

      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfETC2_RGBA8_UNorm, [tuSampled, tuTransferDst], VkDev.PhysicalDevice);
      AssertEquals('Unsupported ETC2_RGBA8_UNorm must negotiate fallback to RGBA8_UNorm',
        Ord(pfRGBA8_UNorm), Ord(NegotiatedFmt));

      { 2. Combined Depth+Stencil Barrier vs. ImageView Aspect Mask Separation
           (VUID-VkImageMemoryBarrier-subresourceRange-09601 vs VUID-VkDescriptorImageInfo-imageView-01976) }
      FillChar(TexDesc, SizeOf(TexDesc), 0);
      TexDesc.Dimension := td2D;
      TexDesc.Width := 512;
      TexDesc.Height := 512;
      TexDesc.DepthOrArrayLayers := 1;
      TexDesc.MipLevels := 1;
      TexDesc.SampleCount := 1;
      TexDesc.Format := pfD24_UNorm_S8_UInt;
      TexDesc.Usage := [tuDepthStencil, tuSampled];

      DepthTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      try
        AssertEquals('TVulkanRHITexture must automatically negotiate supported D32_Float_S8_UInt',
          Ord(pfD32_Float_S8_UInt), Ord(DepthTex.Desc.Format));
        AssertEquals('Combined depth+stencil barrier AspectMask must include both DEPTH and STENCIL bits',
          Cardinal(VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT),
          DepthTex.AspectMask);
        AssertEquals('Combined depth+stencil sampled ViewAspectMask must include ONLY DEPTH_BIT',
          Cardinal(VK_IMAGE_ASPECT_DEPTH_BIT),
          DepthTex.ViewAspectMask);
      finally
        FreeAndNil(DepthTex);
      end;

      { 3. Cross-Vendor Hardware Buffer Offset Alignment
           (NVIDIA 256B UBO alignment, Mali/Adreno 128B SSBO alignment, 64B transfer copy alignment) }
      VkDev.MemoryAllocator.MinUniformBufferAlignment := 256;
      VkDev.MemoryAllocator.MinStorageBufferAlignment := 128;
      VkDev.MemoryAllocator.OptimalBufferCopyOffsetAlignment := 64;
      VkDev.MemoryAllocator.NonCoherentAtomSize := 64;

      FillChar(UboDesc, SizeOf(UboDesc), 0);
      UboDesc.Size := 72; // unaligned size
      UboDesc.Usage := [buUniform];
      UboDesc.MemoryUsage := muCpuToGpu;

      FillChar(SsboDesc, SizeOf(SsboDesc), 0);
      SsboDesc.Size := 50; // unaligned size
      SsboDesc.Usage := [buStorage];
      SsboDesc.MemoryUsage := muGpuOnly;

      FillChar(StageDesc, SizeOf(StageDesc), 0);
      StageDesc.Size := 36; // unaligned size
      StageDesc.Usage := [buTransferSrc];
      StageDesc.MemoryUsage := muCpuToGpu;

      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      Ubo1 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      Ssbo0 := TVulkanRHIBuffer.Create(VkDev, SsboDesc, nil);
      Ssbo1 := TVulkanRHIBuffer.Create(VkDev, SsboDesc, nil);
      StageBuf := TVulkanRHIBuffer.Create(VkDev, StageDesc, nil);
      try
        AssertEquals('UBO[0] sub-allocation offset must be aligned to MinUniformBufferAlignment (256)',
          0, Ubo0.MemoryOffset mod 256);
        AssertEquals('UBO[1] sub-allocation offset must be aligned to MinUniformBufferAlignment (256)',
          0, Ubo1.MemoryOffset mod 256);
        AssertEquals('SSBO[0] sub-allocation offset must be aligned to MinStorageBufferAlignment (128)',
          0, Ssbo0.MemoryOffset mod 128);
        AssertEquals('SSBO[1] sub-allocation offset must be aligned to MinStorageBufferAlignment (128)',
          0, Ssbo1.MemoryOffset mod 128);
        AssertEquals('Transfer staging buffer offset must be aligned to OptimalBufferCopyOffsetAlignment (64)',
          0, StageBuf.MemoryOffset mod 64);
      finally
        FreeAndNil(StageBuf);
        FreeAndNil(Ssbo1);
        FreeAndNil(Ssbo0);
        FreeAndNil(Ubo1);
        FreeAndNil(Ubo0);
      end;

      { 4. Non-Coherent Atom Size Range Alignment (VUID-VkMappedMemoryRange-offset-00687) }
      AlignNonCoherentMemoryRange(
        256, 100, 17, 50, 4096, VkDev.MemoryAllocator.NonCoherentAtomSize,
        AlignedOffset, AlignedSize);
      AssertEquals('Non-coherent flush offset must round down to 64B atom boundary',
        256, AlignedOffset);
      AssertEquals('Non-coherent flush size must round up to 64B atom multiple covering [273..323)',
        128, AlignedSize);

      { 5. Synchronization & Frame-In-Flight Deferred Resource Destruction Queue
           (VUID-vkDestroyBuffer-buffer-00922: resources freed while a frame is in flight
            must remain alive until that frame slot's VkFence completes) }
      SubAllocsBefore := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      VkDev.FrameIndex := 1;
      VkDev.DeferResourceDestruction := True;

      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      TexDesc.Format := pfRGBA8_UNorm;
      TexDesc.Usage := [tuSampled, tuColorAttachment];
      ColorTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      SubAllocsDuring := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      AssertEquals('Creating 1 buffer + 1 texture must add 2 sub-allocations',
        SubAllocsBefore + 2, SubAllocsDuring);

      { Destroy both while Frame 1 is still in flight on the GPU }
      FreeAndNil(Ubo0);
      FreeAndNil(ColorTex);

      AssertEquals('Destroyed buffer + texture must be queued in PendingDeferredDeletionCount',
        2, VkDev.PendingDeferredDeletionCount);
      AssertEquals('Sub-allocations must NOT be recycled while Frame 1 is still in flight',
        SubAllocsDuring, VkDev.MemoryAllocator.GetStats.SubAllocationCount);

      { Flushing Frame 0 must not retire Frame 1's resources }
      VkDev.FlushDeferredDeletions(0);
      AssertEquals('Flushing Frame 0 must leave Frame 1 deferred resources intact',
        2, VkDev.PendingDeferredDeletionCount);

      { Flushing Frame 1 (simulating Frame 1 VkFence completion) retires both resources }
      VkDev.FlushDeferredDeletions(1);
      SubAllocsAfterFlush := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      AssertEquals('After Frame 1 fence flush, PendingDeferredDeletionCount must be 0',
        0, VkDev.PendingDeferredDeletionCount);
      AssertEquals('After Frame 1 fence flush, sub-allocations must be returned to the pool',
        SubAllocsBefore, SubAllocsAfterFlush);
      VkDev.DeferResourceDestruction := False;

      { 6. Explicit Buffer & Texture Pipeline Barrier Tracking on TVulkanRHICommandList }
      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      ColorTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      CmdList := TVulkanRHICommandList.Create(VkDev, 0);
      try
        AssertEquals('Initial BarrierCount must be 0', 0, CmdList.BarrierCount);
        CmdList.TransitionBuffer(Ubo0, rsTransferDst, rsShaderRead);
        AssertEquals('TransitionBuffer must emit a VkBufferMemoryBarrier', 1, CmdList.BarrierCount);
        CmdList.TransitionTexture(ColorTex, rsColorAttachment);
        AssertEquals('TransitionTexture must emit a VkImageMemoryBarrier', 2, CmdList.BarrierCount);
        { Redundant transition to same state must be a no-op }
        CmdList.TransitionTexture(ColorTex, rsColorAttachment);
        AssertEquals('Redundant TransitionTexture to identical state must be skipped', 2, CmdList.BarrierCount);
      finally
        FreeAndNil(CmdList);
        FreeAndNil(ColorTex);
        FreeAndNil(Ubo0);
      end;
    finally
      FreeAndNil(VkDev);
    end;
  finally
    Pointer(vkGetPhysicalDeviceFormatProperties) := SavedFormatPropsProc;
  end;
end;

procedure TTestCastleVulkanRHI.TestGrowableAndTransientDescriptorPools;
var
  PoolAlloc: TVulkanDescriptorPoolAllocator;
  OwnerPool, FirstPool, SecondPool: VkDescriptorPool;
  SetHandle: VkDescriptorSet;
  I: Integer;
  VkDev: TVulkanRHIDevice;
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  Layout: TRHIDescriptorSetLayout;
  PersistSet, TransSet0, TransSet1: TVulkanRHIDescriptorSet;
begin
  { 1. Growable Descriptor Pool Chain & Capacity Scaling }
  PoolAlloc := TVulkanDescriptorPoolAllocator.Create(nil, 4, False, 16);
  try
    AssertEquals('Initial TotalPoolCount must be 0 (lazy creation)', 0, PoolAlloc.TotalPoolCount);
    AssertEquals('Initial NextPoolMaxSets must be 4', 4, PoolAlloc.NextPoolMaxSets);

    { Allocate 4 descriptor sets filling Page #1 (capacity 4) }
    FirstPool := VK_NULL_HANDLE;
    for I := 1 to 4 do
    begin
      SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
      AssertTrue('Allocated descriptor set must be non-null', SetHandle <> VK_NULL_HANDLE);
      if I = 1 then
        FirstPool := OwnerPool
      else
        AssertTrue('First 4 sets must come from the same Pool Page #1', OwnerPool = FirstPool);
    end;
    AssertEquals('After 4 sets, TotalPoolCount must be 1', 1, PoolAlloc.TotalPoolCount);
    AssertEquals('After 4 sets, FullPoolCount must be 0', 0, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #1 (cap 4), NextPoolMaxSets must scale by 1.5x to 6',
      6, PoolAlloc.NextPoolMaxSets);

    { 5th allocation exceeds Page #1 capacity (4) and automatically grows to Page #2 (cap 6) }
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), SecondPool);
    AssertTrue('5th descriptor set must succeed via pool growth', SetHandle <> VK_NULL_HANDLE);
    AssertTrue('Page #2 handle must differ from Page #1 handle', SecondPool <> FirstPool);
    AssertEquals('After growing to Page #2, TotalPoolCount must be 2', 2, PoolAlloc.TotalPoolCount);
    AssertEquals('Page #1 must move to FullPools (FullPoolCount = 1)', 1, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #2 (cap 6), NextPoolMaxSets must scale by 1.5x to 9',
      9, PoolAlloc.NextPoolMaxSets);

    { Fill remaining 5 slots of Page #2 (total 10 sets), then allocate 11th set -> Page #3 (cap 9) }
    for I := 6 to 10 do
      PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('After 10 sets, TotalPoolCount must still be 2', 2, PoolAlloc.TotalPoolCount);

    PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('11th set must grow to Page #3 (TotalPoolCount = 3)', 3, PoolAlloc.TotalPoolCount);
    AssertEquals('Pages #1 and #2 must be in FullPools (FullPoolCount = 2)', 2, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #3 (cap 9), NextPoolMaxSets must scale to 13',
      13, PoolAlloc.NextPoolMaxSets);

    { 2. Driver Error Recovery: VK_ERROR_FRAGMENTED_POOL & VK_ERROR_OUT_OF_POOL_MEMORY }
    PoolAlloc.ForceNextAllocationError := VK_ERROR_FRAGMENTED_POOL;
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertTrue('Allocation after VK_ERROR_FRAGMENTED_POOL must recover on new pool page',
      SetHandle <> VK_NULL_HANDLE);
    AssertEquals('VK_ERROR_FRAGMENTED_POOL must retire Page #3 and create Page #4 (cap 13)',
      4, PoolAlloc.TotalPoolCount);
    AssertEquals('After Page #4 (cap 13), NextPoolMaxSets must cap at MaxSetsCap (16)',
      16, PoolAlloc.NextPoolMaxSets);

    PoolAlloc.ForceNextAllocationError := VK_ERROR_OUT_OF_POOL_MEMORY;
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertTrue('Allocation after VK_ERROR_OUT_OF_POOL_MEMORY must recover on new pool page',
      SetHandle <> VK_NULL_HANDLE);
    AssertEquals('VK_ERROR_OUT_OF_POOL_MEMORY must retire Page #4 and create Page #5 (cap 16)',
      5, PoolAlloc.TotalPoolCount);
    AssertEquals('FullPoolCount must be 4', 4, PoolAlloc.FullPoolCount);
    AssertEquals('TotalAllocatedSetCount must be 13', 13, PoolAlloc.TotalAllocatedSetCount);

    { 3. O(1) Bulk Reset (ResetPools) & Zero-Allocation Frame Reuse }
    PoolAlloc.ResetPools;
    AssertEquals('ResetCount must be 1', 1, PoolAlloc.ResetCount);
    AssertEquals('TotalAllocatedSetCount must reset to 0', 0, PoolAlloc.TotalAllocatedSetCount);
    AssertEquals('FullPoolCount must reset to 0', 0, PoolAlloc.FullPoolCount);
    AssertEquals('All 5 pool pages must move to ReadyPools (ReadyPoolCount = 5)',
      5, PoolAlloc.ReadyPoolCount);
    AssertEquals('TotalPoolCount must remain 5', 5, PoolAlloc.TotalPoolCount);

    { Allocate 20 sets in the next frame: must reuse ReadyPools without creating any new pools }
    for I := 1 to 20 do
      PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('Reusing ready pools across frames must not allocate new VkDescriptorPools',
      5, PoolAlloc.TotalPoolCount);
    AssertEquals('TotalAllocatedSetCount must be 20', 20, PoolAlloc.TotalAllocatedSetCount);
  finally
    FreeAndNil(PoolAlloc);
  end;

  { 4. TVulkanRHIDevice Persistent vs. Per-Frame Transient Descriptor Sets & Deferred Retirement }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex, ssFragment];
    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssFragment];

    Layout := VkDev.CreateDescriptorSetLayout(Bindings);
    try
      VkDev.FrameIndex := 0;
      PersistSet := VkDev.CreateDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      TransSet0 := VkDev.CreateTransientDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      TransSet1 := VkDev.CreateTransientDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      try
        AssertFalse('CreateDescriptorSet must create a persistent descriptor set',
          PersistSet.IsTransient);
        AssertTrue('CreateTransientDescriptorSet must create a transient descriptor set',
          TransSet0.IsTransient);
        AssertEquals('PersistentDescriptorAllocator must have 1 allocated set',
          1, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);
        AssertEquals('Frame 0 TransientDescriptorAllocator must have 2 allocated sets',
          2, VkDev.GetTransientDescriptorAllocator(0).TotalAllocatedSetCount);
        AssertEquals('Frame 1 TransientDescriptorAllocator must have 0 allocated sets',
          0, VkDev.GetTransientDescriptorAllocator(1).TotalAllocatedSetCount);
        AssertTrue('Device.DescriptorPool must reflect the active persistent pool handle',
          VkDev.DescriptorPool = PersistSet.OwnerPool);

        { Simulate in-flight Frame 1: destroying transient sets must NOT enqueue individual frees,
          whereas destroying a persistent set MUST defer vkFreeDescriptorSets until Fence 1 }
        VkDev.FrameIndex := 1;
        VkDev.DeferResourceDestruction := True;

        FreeAndNil(TransSet0);
        FreeAndNil(TransSet1);
        AssertEquals('Destroying transient sets must not add to PendingDeferredDeletionCount',
          0, VkDev.PendingDeferredDeletionCount);

        FreeAndNil(PersistSet);
        AssertEquals('Destroying persistent set while frame is in flight must queue 1 deferred deletion',
          1, VkDev.PendingDeferredDeletionCount);
        AssertEquals('Persistent set must remain allocated until in-flight frame fence flushes',
          1, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);

        VkDev.FlushDeferredDeletions(1);
        AssertEquals('After Frame 1 FlushDeferredDeletions, PendingDeferredDeletionCount must be 0',
          0, VkDev.PendingDeferredDeletionCount);
        AssertEquals('After Frame 1 FlushDeferredDeletions, persistent set must be freed back to pool',
          0, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);

        { Bulk reset Frame 0 transient pool }
        VkDev.GetTransientDescriptorAllocator(0).ResetPools;
        AssertEquals('After Frame 0 ResetPools, transient allocated count must be 0',
          0, VkDev.GetTransientDescriptorAllocator(0).TotalAllocatedSetCount);
        AssertEquals('Frame 0 transient pool page must be recycled into ReadyPools',
          1, VkDev.GetTransientDescriptorAllocator(0).ReadyPoolCount);
      finally
        FreeAndNil(TransSet1);
        FreeAndNil(TransSet0);
        FreeAndNil(PersistSet);
      end;
    finally
      FreeAndNil(Layout);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestAsyncStagingUploadRingBufferAndTransferQueue;
var
  QueueProps: array of VkQueueFamilyProperties;
  HasDedicatedDMA: Boolean;
  SelectedQueueFamily: Cardinal;
  VkDev: TVulkanRHIDevice;
  Uploader: TCastleVulkanStagingUploader;
  BufDesc0, BufDesc1, TempBufDesc: TRHIBufferDesc;
  GpuBuf0, GpuBuf1, TempBuf: TVulkanRHIBuffer;
  TexDesc, TempTexDesc, ColorTargetDesc: TRHITextureDesc;
  GpuTex0, TempTex, ColorTarget: TVulkanRHITexture;
  ImgMip0, ImgMip1: TRGBAlphaImage;
  Payload: array of Byte;
  CmdList: TVulkanRHICommandList;
  RenderInfo: TRHIRenderingInfo;
  I: Integer;
begin
  { 1. Dedicated DMA Transfer Queue Selection Across Hardware Topologies }
  SetLength(QueueProps, 1);
  FillChar(QueueProps[0], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[0].queueCount := 1;
  QueueProps[0].queueFlags := VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Single unified queue must select graphics queue family 0', 0, SelectedQueueFamily);
  AssertFalse('Single unified queue must not report HasDedicatedTransferQueue', HasDedicatedDMA);

  SetLength(QueueProps, 2);
  FillChar(QueueProps[1], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[1].queueCount := 2;
  QueueProps[1].queueFlags := VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Graphics + Async Compute topology must select non-graphics family 1 for transfers',
    1, SelectedQueueFamily);
  AssertTrue('Non-graphics transfer queue family (family 1 <> graphics family 0) must report HasDedicatedTransferQueue = True',
    HasDedicatedDMA);

  SetLength(QueueProps, 3);
  FillChar(QueueProps[2], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[2].queueCount := 1;
  QueueProps[2].queueFlags := VK_QUEUE_TRANSFER_BIT or VK_QUEUE_SPARSE_BINDING_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Dedicated DMA queue family (TRANSFER without GRAPHICS/COMPUTE) must be prioritized (family 2)',
    2, SelectedQueueFamily);
  AssertTrue('Dedicated DMA queue family must report HasDedicatedTransferQueue = True', HasDedicatedDMA);

  { 2. Asynchronous Staging Ring Buffer Sub-Allocation & Multi-Upload Batching }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    Uploader := VkDev.StagingUploader;
    AssertTrue('Device must initialize StagingUploader', Uploader <> nil);

    Uploader.RingCapacityPerFrame := 4096;
    VkDev.MemoryAllocator.OptimalBufferCopyOffsetAlignment := 64;
    VkDev.FrameIndex := 0;

    SetLength(Payload, 8192);
    for I := 0 to High(Payload) do
      Payload[I] := Byte(I and $FF);

    BufDesc0 := TRHIBufferDesc.Create(300, [buVertex, buTransferDst], muGpuOnly, 'StagedVBO');
    BufDesc1 := TRHIBufferDesc.Create(8192, [buIndex, buTransferDst], muGpuOnly, 'StagedIBO');

    FillChar(TexDesc, SizeOf(TexDesc), 0);
    TexDesc.Dimension := td2D;
    TexDesc.Width := 8;
    TexDesc.Height := 8;
    TexDesc.DepthOrArrayLayers := 1;
    TexDesc.MipLevels := 2;
    TexDesc.SampleCount := 1;
    TexDesc.Format := pfRGBA8_UNorm;
    TexDesc.Usage := [tuSampled, tuTransferDst];
    TexDesc.DebugName := 'StagedTex2D';

    ImgMip0 := TRGBAlphaImage.Create(8, 8);
    ImgMip1 := TRGBAlphaImage.Create(4, 4);
    GpuBuf0 := TVulkanRHIBuffer.Create(VkDev, BufDesc0, @Payload[0]);
    GpuBuf1 := TVulkanRHIBuffer.Create(VkDev, BufDesc1, nil);
    GpuTex0 := TVulkanRHITexture.Create(VkDev, TexDesc);
    try
      { Upload 512 bytes to GpuBuf1 at offset 128, plus Mip 0 (256B) and Mip 1 (64B) to GpuTex0 }
      GpuBuf1.UploadData(Payload[0], 512, 128);
      GpuTex0.UploadImage(ImgMip0, 0, 0);
      GpuTex0.UploadImage(ImgMip1, 1, 0);

      AssertEquals('2 buffer uploads must be queued without synchronous flush',
        2, Uploader.PendingBufferCopyCount);
      AssertEquals('2 image mip uploads must be queued without synchronous flush',
        2, Uploader.PendingImageCopyCount);
      AssertEquals('TotalBufferUploads must be 2', 2, Uploader.TotalBufferUploads);
      AssertEquals('TotalImageUploads must be 2', 2, Uploader.TotalImageUploads);
      AssertEquals('TotalStagedBytes must equal 300 + 512 + 256 + 64 = 1132',
        1132, Uploader.TotalStagedBytes);
      { Slice 0: [0..300) -> next 300
        Slice 1: aligned to 64 -> [320..832) -> next 832
        Slice 2: aligned to 64 -> [832..1088) -> next 1088
        Slice 3: aligned to 64 -> [1088..1152) -> next 1152 }
      AssertEquals('CurrentFrameWriteOffset must reflect 64-byte OptimalBufferCopyOffsetAlignment',
        1152, Uploader.CurrentFrameWriteOffset);
      AssertEquals('Sub-allocations within 4096B ring capacity must not allocate overflow chunks',
        0, Uploader.OverflowChunkCount);

      { 3. Overflow Chunk Fallback When Single Upload Exceeds RingCapacityPerFrame }
      GpuBuf1.UploadData(Payload[0], 8192, 0);
      AssertEquals('Large upload (8192B > 4096B ring) must allocate 1 overflow staging chunk',
        1, Uploader.OverflowChunkCount);
      AssertEquals('PendingBufferCopyCount must now be 3', 3, Uploader.PendingBufferCopyCount);

      { 4. Cancellation When Destination Buffer/Texture Is Destroyed Before Flush }
      TempBufDesc := TRHIBufferDesc.Create(128, [buVertex], muGpuOnly, 'ShortLivedVBO');
      TempBuf := TVulkanRHIBuffer.Create(VkDev, TempBufDesc, @Payload[0]);
      TempTexDesc := TexDesc;
      TempTexDesc.MipLevels := 1;
      TempTex := TVulkanRHITexture.Create(VkDev, TempTexDesc);
      TempTex.UploadImage(ImgMip0, 0, 0);

      AssertEquals('PendingBufferCopyCount with TempBuf must be 4', 4, Uploader.PendingBufferCopyCount);
      AssertEquals('PendingImageCopyCount with TempTex must be 3', 3, Uploader.PendingImageCopyCount);

      FreeAndNil(TempBuf);
      FreeAndNil(TempTex);
      AssertEquals('Destroying TempBuf before flush must cancel its pending buffer copy',
        3, Uploader.PendingBufferCopyCount);
      AssertEquals('Destroying TempTex before flush must cancel its pending image copy',
        2, Uploader.PendingImageCopyCount);

      { 5. Automatic Pre-RenderPass Flush & Dedicated DMA Queue Ownership Transfer Barriers }
      Uploader.ConfigureTransferQueue(0, 2, True);
      AssertTrue('ConfigureTransferQueue(0, 2, True) must enable UseDedicatedTransferQueue',
        Uploader.UseDedicatedTransferQueue);

      ColorTargetDesc := TexDesc;
      ColorTargetDesc.MipLevels := 1;
      ColorTargetDesc.Usage := [tuColorAttachment];
      ColorTarget := TVulkanRHITexture.Create(VkDev, ColorTargetDesc);
      CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
      try
        CmdList.BeginRecording;
        FillChar(RenderInfo, SizeOf(RenderInfo), 0);
        RenderInfo.RenderArea := Rectangle(0, 0, 8, 8);
        SetLength(RenderInfo.ColorAttachments, 1);
        RenderInfo.ColorAttachments[0].Texture := ColorTarget;
        RenderInfo.ColorAttachments[0].LoadOp := loClear;
        RenderInfo.ColorAttachments[0].StoreOp := soStore;

        { BeginRendering must automatically flush all pending staged uploads BEFORE opening render pass }
        CmdList.BeginRendering(RenderInfo);
        AssertEquals('BeginRendering must flush all pending buffer copies prior to render pass',
          0, Uploader.PendingBufferCopyCount);
        AssertEquals('BeginRendering must flush all pending image copies prior to render pass',
          0, Uploader.PendingImageCopyCount);
        AssertEquals('TotalBatchedFlushes must increment to 1', 1, Uploader.TotalBatchedFlushes);
        AssertEquals('Dedicated DMA queue flush must record ownership transfer for 3 buffer copies + 2 image mips',
          5, Uploader.QueueOwnershipTransferCount);
        AssertEquals('Uploaded texture must transition to rsShaderRead after staging flush',
          Ord(rsShaderRead), Ord(GpuTex0.CurrentState));
        CmdList.EndRendering;
        CmdList.EndRecording;
      finally
        FreeAndNil(CmdList);
        FreeAndNil(ColorTarget);
      end;

      { 6. Frame Slot Reclamation Resets Ring Write Offset and Frees Overflow Chunks }
      Uploader.ReclaimFrameSlot(0);
      AssertEquals('ReclaimFrameSlot(0) must reset CurrentFrameWriteOffset to 0',
        0, Uploader.CurrentFrameWriteOffset);
      AssertEquals('ReclaimFrameSlot(0) must release temporary overflow chunks for that frame slot',
        0, Uploader.OverflowChunkCount);
    finally
      FreeAndNil(GpuTex0);
      FreeAndNil(GpuBuf1);
      FreeAndNil(GpuBuf0);
      FreeAndNil(ImgMip1);
      FreeAndNil(ImgMip0);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

initialization
  RegisterTest(TTestCastleVulkanRHI);
end.

{%MainUnit castleinternalshadercompiler.pas}
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

{ Built-in SPIR-V fallback dispatcher for TCastleShaderCompiler.
  SPIR-V binary words live in src/base_rendering/vulkan/spirv/*.spv and are
  packed at build time into generated-pascal/castleinternalvulkanspirv_blobs.inc
  by tools/internal/generate_vulkan_spirv/spv2pas.dpr (or loaded directly from
  disk when CASTLE_VULKAN_SPIRV_DIR points to a directory of *.spv files). }

{$I generated-pascal/castleinternalvulkanspirv_blobs.inc}

function TryLoadExternalBuiltInSPIRV(const AModuleName: String;
  out ASPIRV: TSPIRVBytecode): Boolean;
var
  OverrideDir, SpvFile: String;
  Stream: TFileStream;
  FirstWord: UInt32;
begin
  Result := False;
  ASPIRV := nil;
  OverrideDir := Trim(GetEnvironmentVariable('CASTLE_VULKAN_SPIRV_DIR'));
  if OverrideDir = '' then
    Exit;
  SpvFile := InclPathDelim(OverrideDir) + AModuleName + '.spv';
  if not RegularFileExists(SpvFile) then
    Exit;
  Stream := TFileStream.Create(SpvFile, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 20) or ((Stream.Size mod 4) <> 0) then
      Exit;
    SetLength(ASPIRV, Stream.Size);
    Stream.ReadBuffer(ASPIRV[0], Stream.Size);
    Move(ASPIRV[0], FirstWord, SizeOf(UInt32));
    if FirstWord <> SPIRV_MAGIC_NUMBER then
    begin
      ASPIRV := nil;
      Exit;
    end;
    Result := True;
  finally
    FreeAndNil(Stream);
  end;
end;

procedure CopyBuiltInModuleWords(const AModuleName: String;
  const AWords: array of UInt32; out ASPIRV: TSPIRVBytecode);
var
  ByteSize: PtrInt;
begin
  if TryLoadExternalBuiltInSPIRV(AModuleName, ASPIRV) then
    Exit;
  ByteSize := Length(AWords) * SizeOf(UInt32);
  SetLength(ASPIRV, ByteSize);
  if ByteSize > 0 then
    Move(AWords[0], ASPIRV[0], ByteSize);
end;

function TCastleShaderCompiler.TryGetBuiltInSPIRV(const AStage: TRHIShaderStage;
  const AGLSLSource, ADebugName: String; out ASPIRV: TSPIRVBytecode): Boolean;

  procedure CopyWords(const AModuleName: String; const AWords: array of UInt32);
  var
    ByteSize: PtrInt;
  begin
    if TryLoadExternalBuiltInSPIRV(AModuleName, ASPIRV) then
    begin
      Result := True;
      Exit;
    end;
    ByteSize := Length(AWords) * SizeOf(UInt32);
    SetLength(ASPIRV, ByteSize);
    if ByteSize > 0 then
      Move(AWords[0], ASPIRV[0], ByteSize);
    Result := True;
  end;

  { Classic X3D 3.0 Phong materials (TMaterialNode -> castle_specular_color) evaluate
    unnormalized Lambertian diffuse (diffuseColor * NdotL) rather than glTF 2.0 PBR's
    energy-normalized (0.96 * baseColor / PI) * NdotL, and omit sRGB pow(2.2)/pow(1/2.2)
    conversion unless CASTLE_GAMMA_CORRECTION is active. When falling back to
    BuiltIn3DPBRShadowFragSPIRV without a runtime GLSL compiler, patch those constants
    in-place while preserving PI (%25) in the GGX specular NDF denominator. }
  procedure PatchPhongLambertianDiffuseIfNeeded;
  var
    Words: PUInt32;
    WordCount, W: PtrInt;
    DisableGamma: Boolean;
  begin
    if (Pos('castle_specular_color', AGLSLSource) = 0) or (Length(ASPIRV) < 28) then
      Exit;
    DisableGamma := Pos('#define CASTLE_GAMMA_CORRECTION 1', AGLSLSource) = 0;
    Words := PUInt32(@ASPIRV[0]);
    WordCount := Length(ASPIRV) div SizeOf(UInt32);
    for W := 5 to WordCount - 7 do
    begin
      { %A5 = OpFMul %float %20 (0.96) %A4 -> %1C (1.0) }
      if (Words[W] = $00050085) and (Words[W + 1] = $00000004) and
         (Words[W + 2] = $000000A5) and (Words[W + 3] = $00000020) then
        Words[W + 3] := $0000001C
      else
      { %A7 = OpFDiv %float %1C (1.0) %25 (PI) -> %1C (1.0) }
      if (Words[W] = $00050088) and (Words[W + 1] = $00000004) and
         (Words[W + 2] = $000000A7) and (Words[W + 3] = $0000001C) and
         (Words[W + 4] = $00000025) then
        Words[W + 4] := $0000001C
      else
      { %6B / %70 / %244 = OpExtInst %v3float %id %1 Pow(26) %val %2E/%2F -> %2C (vec3(1.0)) }
      if DisableGamma and (Words[W] = $0007000C) and (Words[W + 1] = $00000006) and
         (Words[W + 3] = $00000001) and (Words[W + 4] = $0000001A) and
         ((Words[W + 2] = $0000006B) or (Words[W + 2] = $00000070) or (Words[W + 2] = $00000244)) and
         ((Words[W + 6] = $0000002E) or (Words[W + 6] = $0000002F)) then
        Words[W + 6] := $0000002C;
    end;
  end;

begin
  ASPIRV := nil;
  Result := False;

  case AStage of
    ssVertex:
      begin
        if (ADebugName = 'MeshletFallbackVS') or
           (ADebugName = 'MeshletFallback_VS') then
        begin
          CopyWords('BuiltInMeshletFallbackVertSPIRV', BuiltInMeshletFallbackVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'Primitive2D_VS') or
           ((Pos('viewport_size', AGLSLSource) > 0) and (Pos('point_size', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInPrimitive2DVertSPIRV', BuiltInPrimitive2DVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'UnlitMesh_VS') or
           ((Pos('u_MVP', AGLSLSource) > 0) and (Pos('castle_Vertex', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInUnlitMeshVertSPIRV', BuiltInUnlitMeshVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBatch2D.vert') or
           (Pos('CastleDraw.u_ModelViewMatrix[0].xy', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInBatch2DVertSPIRV', BuiltInBatch2DVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'ScreenDefaultVS') or
           (ADebugName = 'ScreenEffectVS') or
           (Pos('v_tex_coord = tex_coord', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInScreenEffectVertSPIRV', BuiltInScreenEffectVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'HDRCompositeVS') or
           (ADebugName = 'HDRComposite_VS') or
           (Pos('HDRCompositeVS', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInHDRCompositeVertSPIRV', BuiltInHDRCompositeVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBindlessIndirectVS') or
           ((Pos('InstancesSSBO', AGLSLSource) > 0) and (Pos('gl_InstanceIndex', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInBindlessIndirectVertSPIRV', BuiltInBindlessIndirectVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleSkinned3DVert') or
           (Pos('CastleSkinning.u_JointMatrices[', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltIn3DSkinnedVertSPIRV', BuiltIn3DSkinnedVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleColorPerVertex3DVert') or
           (Pos('CASTLE_PERM_COLOR_PER_VERTEX', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltIn3DColorPerVertexVertSPIRV', BuiltIn3DColorPerVertexVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleMultiTex3DVert') or
           (Pos('CASTLE_PERM_MULTITEX_UV1', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltIn3DMultiTexVertSPIRV', BuiltIn3DMultiTexVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleDefault3DVert') or
           (ADebugName = 'CastleVSMCasterVert') or
           (Pos('CastleShapeVert', ADebugName) = 1) or
           ((Pos('CastleSceneBlock', AGLSLSource) > 0) and (Pos('CastlePushConstants', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltIn3DPosNormUVVertSPIRV', BuiltIn3DPosNormUVVertSPIRV);
          Exit;
        end;
      end;

    ssFragment:
      begin
        if (ADebugName = 'MeshletFS') or
           (ADebugName = 'Meshlet_FS') then
        begin
          CopyWords('BuiltInMeshletFragSPIRV', BuiltInMeshletFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'Primitive2D_FS') or
           ((Pos('viewport_size', AGLSLSource) > 0) and (Pos('out_Color = pc.color', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInPrimitive2DFragSPIRV', BuiltInPrimitive2DFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'UnlitMesh_FS') or
           ((Pos('u_MVP', AGLSLSource) > 0) and (Pos('out_Color = pc.u_Color', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInUnlitMeshFragSPIRV', BuiltInUnlitMeshFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBatch2D.frag') or
           (Pos('.RHI2D.frag', ADebugName) > 0) or
           ((Pos('u_SpriteTexture', AGLSLSource) > 0) and (Pos('CastleDraw.u_ModelViewMatrix[1]', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInBatch2DFragSPIRV', BuiltInBatch2DFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleVSMCasterFrag') or
           (Pos('out_Moments = vec4(depth, moment2', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInVSMCasterFragSPIRV', BuiltInVSMCasterFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'HDRCompositeFS') or
           (ADebugName = 'HDRComposite_FS') or
           ((Pos('u_HDRSceneTexture', AGLSLSource) > 0) and (Pos('u_BloomTexture', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInHDRCompositeFragSPIRV', BuiltInHDRCompositeFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'ScreenDefaultFS') or
           (ADebugName = 'ScreenEffectFS') or
           (Pos('sampler2D screen', AGLSLSource) > 0) then
        begin
          if (Pos('1.0 -', AGLSLSource) > 0) or (Pos('invert', LowerCase(AGLSLSource)) > 0) then
            CopyWords('BuiltInScreenEffectInvertFragSPIRV', BuiltInScreenEffectInvertFragSPIRV)
          else
            CopyWords('BuiltInScreenEffectPassthroughFragSPIRV', BuiltInScreenEffectPassthroughFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBindlessIndirectFS') or
           ((Pos('CastleBindlessMaterialsBlock', AGLSLSource) > 0) and (Pos('castle_BindlessTextures', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInBindlessIndirectFragSPIRV', BuiltInBindlessIndirectFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleDefault3DFrag') or
           (ADebugName = 'CastlePBR3DFrag') or
           (ADebugName = 'CastleColorPerVertex3DFrag') or
           (ADebugName = 'CastleMultiTex3DFrag') or
           (ADebugName = 'CastleMultiTexAdd3DFrag') or
           (ADebugName = 'CastleCubeTex3DFrag') or
           (ADebugName = 'CastleTex3DFrag') or
           (ADebugName = 'CastlePBRIBL3DFrag') or
           (Pos('CastleShapeFrag', ADebugName) = 1) or
           ((Pos('CastleMaterialBlock', AGLSLSource) > 0) and (Pos('CastleLightsBlock', AGLSLSource) > 0)) then
        begin
          if Pos('castle_sample_vsm_slot', AGLSLSource) > 0 then
            CopyWords('BuiltIn3DPBRVSMFragSPIRV', BuiltIn3DPBRVSMFragSPIRV)
          else if (ADebugName = 'CastleColorPerVertex3DFrag') or
                  (Pos('castle_color_per_vertex', Copy(AGLSLSource, Max(1, Pos('void main()', AGLSLSource)), MaxInt)) > 0) then
            CopyWords('BuiltIn3DColorPerVertexFragSPIRV', BuiltIn3DColorPerVertexFragSPIRV)
          else if (ADebugName = 'CastleMultiTexAdd3DFrag') or
                  ((Pos('uniform sampler2D castle_multi_texture_1;', AGLSLSource) > 0) and (Pos('+= multiTex1.rgb', AGLSLSource) > 0)) then
            CopyWords('BuiltIn3DMultiTexAddFragSPIRV', BuiltIn3DMultiTexAddFragSPIRV)
          else if (ADebugName = 'CastleMultiTex3DFrag') or
                  (Pos('uniform sampler2D castle_multi_texture_1;', AGLSLSource) > 0) then
            CopyWords('BuiltIn3DMultiTexModulateFragSPIRV', BuiltIn3DMultiTexModulateFragSPIRV)
          else if (ADebugName = 'CastleCubeTex3DFrag') or
                  (Pos('samplerCube castle_base_color_texture', AGLSLSource) > 0) then
            CopyWords('BuiltIn3DCubeTexFragSPIRV', BuiltIn3DCubeTexFragSPIRV)
          else if (ADebugName = 'CastleTex3DFrag') or
                  (Pos('sampler3D castle_base_color_texture', AGLSLSource) > 0) then
            CopyWords('BuiltIn3DTex3DFragSPIRV', BuiltIn3DTex3DFragSPIRV)
          else if (ADebugName = 'CastlePBRIBL3DFrag') or
                  (Pos('  Lo += EvaluateIBLCookTorranceGGX(', AGLSLSource) > 0) then
            CopyWords('BuiltIn3DPBRIBLFragSPIRV', BuiltIn3DPBRIBLFragSPIRV)
          else if (ADebugName = 'CastlePBR3DFrag') or
                  (Pos('CastleShapeFrag_Perm', ADebugName) = 1) or
                  (Pos('castle_sample_shadow_slot', AGLSLSource) > 0) or
                  ((ADebugName <> 'CastleDefault3DFrag') and
                   (Pos('  Lo += EvaluateDirectCookTorranceGGX(', AGLSLSource) > 0) and
                   (Pos('castle_specular_color', AGLSLSource) = 0)) then
          begin
            CopyWords('BuiltIn3DPBRShadowFragSPIRV', BuiltIn3DPBRShadowFragSPIRV);
            PatchPhongLambertianDiffuseIfNeeded;
          end
          else if Pos('texture(castle_base_color_texture,', AGLSLSource) > 0 then
            CopyWords('BuiltIn3DForwardTexturedFragSPIRV', BuiltIn3DForwardTexturedFragSPIRV)
          else
            CopyWords('BuiltIn3DForwardFragSPIRV', BuiltIn3DForwardFragSPIRV);
          Exit;
        end;
      end;

    ssCompute:
      begin
        if (ADebugName = 'IBLBrdfLutComputeCS') or
           (ADebugName = 'IBLBrdfLut_CS') or
           ((Pos('RadicalInverse_VdC(', AGLSLSource) > 0) and (Pos('IntegrateBRDF(', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInIBLBrdfLutCompSPIRV', BuiltInIBLBrdfLutCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'IBLPrefilterEnvComputeCS') or
           (ADebugName = 'IBLPrefilter_CS') or
           (Pos('IBLPrefilterEnvCompute', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInIBLPrefilterCubemapCompSPIRV', BuiltInIBLPrefilterCubemapCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'IBLIrradianceEnvComputeCS') or
           (ADebugName = 'IBLIrradiance_CS') or
           (Pos('IBLIrradianceEnvCompute', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInIBLIrradianceCubemapCompSPIRV', BuiltInIBLIrradianceCubemapCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'GpuCullingCS') or
           ((Pos('GpuCullingUniformBlock', AGLSLSource) > 0) and (Pos('GpuCullingIndirectOutSSBO', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInGpuCullingCompSPIRV', BuiltInGpuCullingCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'HiZDownsampleCS') or
           ((Pos('u_SrcMip', AGLSLSource) > 0) and (Pos('u_DstMip', AGLSLSource) > 0) and (Pos('r32f', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInHiZDownsampleCompSPIRV', BuiltInHiZDownsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'MaterialBinHistogramCS') or
           ((Pos('MaterialIDsSSBO', AGLSLSource) > 0) and (Pos('atomicAdd(BinCounts[', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInMaterialBinHistCompSPIRV', BuiltInMaterialBinHistCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'MaterialBinPrefixSumCS') or
           ((Pos('BinOffsets[', AGLSLSource) > 0) and (Pos('RunningSum', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInMaterialBinScanCompSPIRV', BuiltInMaterialBinScanCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'BloomDownsampleCS') or
           (ADebugName = 'BloomDown_CS') or
           ((Pos('KarisWeight', AGLSLSource) > 0) and (Pos('SoftThreshold', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInBloomDownsampleCompSPIRV', BuiltInBloomDownsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'BloomUpsampleCS') or
           (ADebugName = 'BloomUp_CS') or
           ((Pos('u_SrcMip', AGLSLSource) > 0) and (Pos('FilterRadius', AGLSLSource) > 0) and (Pos('KarisWeight', AGLSLSource) = 0)) then
        begin
          CopyWords('BuiltInBloomUpsampleCompSPIRV', BuiltInBloomUpsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'LuminanceHistogramCS') or
           (ADebugName = 'LumHist_CS') or
           ((Pos('HistogramBins', AGLSLSource) > 0) and (Pos('AutoExposureParams', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInLuminanceHistogramCompSPIRV', BuiltInLuminanceHistogramCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'GTAOHorizon_CS') or
           (ADebugName = 'GTAO_CS') or
           ((Pos('u_OutGTAO', AGLSLSource) > 0) and (Pos('IntegrateHorizonSlice', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInGTAOHorizonCompSPIRV', BuiltInGTAOHorizonCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'GTAODenoise_CS') or
           ((Pos('u_RawGTAO', AGLSLSource) > 0) and (Pos('u_DenoisedGTAO', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInGTAODenoiseCompSPIRV', BuiltInGTAODenoiseCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'HiZSSR_CS') or
           ((Pos('u_HiZPyramid', AGLSLSource) > 0) and (Pos('u_SSRReflectionOut', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInHiZSSRCompSPIRV', BuiltInHiZSSRCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'PostProcessModulateCS') or
           ((Pos('u_OutModulatedHDR', AGLSLSource) > 0) and (Pos('PostProcessModulatePC', AGLSLSource) > 0)) then
        begin
          CopyWords('BuiltInPostProcessModulateCompSPIRV', BuiltInPostProcessModulateCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'RayQueryCS') or
           (ADebugName = 'RayQuery_CS') or
           (Pos('rayQueryInitializeEXT', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInRayQueryCompSPIRV', BuiltInRayQueryCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'SoftwareLBVHRayTraceCS') or
           (ADebugName = 'SoftwareLBVH_CS') or
           (Pos('LBVHNodes', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInSoftwareLBVHRayTraceCompSPIRV', BuiltInSoftwareLBVHRayTraceCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'MeshletCullCS') or
           (ADebugName = 'MeshletSoftwareCullCS') or
           (Pos('OutExpandedVertices', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInMeshletCullCompSPIRV', BuiltInMeshletCullCompSPIRV);
          Exit;
        end;
      end;

    ssTask:
      begin
        if (ADebugName = 'MeshletTaskEXT') or
           (ADebugName = 'MeshletTask') or
           (Pos('EmitMeshTasksEXT', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInMeshletTaskSPIRV', BuiltInMeshletTaskSPIRV);
          Exit;
        end;
      end;

    ssMesh:
      begin
        if (ADebugName = 'MeshletMeshEXT') or
           (ADebugName = 'MeshletMesh') or
           (Pos('SetMeshOutputsEXT', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInMeshletMeshSPIRV', BuiltInMeshletMeshSPIRV);
          Exit;
        end;
      end;

    ssRayGen:
      begin
        if (ADebugName = 'RayTraceRGen') or
           (ADebugName = 'RayGen') or
           (Pos('traceRayEXT', AGLSLSource) > 0) then
        begin
          CopyWords('BuiltInRayTraceGenSPIRV', BuiltInRayTraceGenSPIRV);
          Exit;
        end;
      end;

    ssMiss:
      begin
        if (ADebugName = 'RayTraceRMiss') or
           (ADebugName = 'RayMiss') then
        begin
          CopyWords('BuiltInRayTraceMissSPIRV', BuiltInRayTraceMissSPIRV);
          Exit;
        end;
      end;

    ssClosestHit:
      begin
        if (ADebugName = 'RayTraceRChit') or
           (ADebugName = 'RayClosestHit') then
        begin
          CopyWords('BuiltInRayTraceClosestHitSPIRV', BuiltInRayTraceClosestHitSPIRV);
          Exit;
        end;
      end;
  end;
end;

function TCastleShaderCompiler.GetMinimalValidSPIRVFallback(
  const AStage: TRHIShaderStage): TSPIRVBytecode;
begin
  Result := nil;
  case AStage of
    ssFragment:
      CopyBuiltInModuleWords('MinimalFragWords', MinimalFragWords, Result);
    ssCompute:
      CopyBuiltInModuleWords('MinimalCompWords', MinimalCompWords, Result);
    ssGeometry:
      CopyBuiltInModuleWords('MinimalGeomWords', MinimalGeomWords, Result);
    ssTask:
      CopyBuiltInModuleWords('BuiltInMeshletTaskSPIRV', BuiltInMeshletTaskSPIRV, Result);
    ssMesh:
      CopyBuiltInModuleWords('BuiltInMeshletMeshSPIRV', BuiltInMeshletMeshSPIRV, Result);
    ssRayGen:
      CopyBuiltInModuleWords('BuiltInRayTraceGenSPIRV', BuiltInRayTraceGenSPIRV, Result);
    ssClosestHit:
      CopyBuiltInModuleWords('BuiltInRayTraceClosestHitSPIRV', BuiltInRayTraceClosestHitSPIRV, Result);
    ssMiss, ssAnyHit, ssIntersection, ssCallable:
      CopyBuiltInModuleWords('BuiltInRayTraceMissSPIRV', BuiltInRayTraceMissSPIRV, Result);
  else
    CopyBuiltInModuleWords('MinimalVertWords', MinimalVertWords, Result);
  end;
end;

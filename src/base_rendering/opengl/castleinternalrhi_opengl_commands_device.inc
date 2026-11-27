{%MainUnit castleinternalrhi_opengl.pas}
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

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TOpenGLRHICommandList                                                        }
{ ---------------------------------------------------------------------------- }

constructor TOpenGLRHICommandList.Create(const ADevice: TOpenGLRHIDevice;
  const ALevel: TRHICommandListLevel);
begin
  inherited Create(ALevel);
  FDevice := ADevice;
  FCurrentPrimitiveMode := GL_TRIANGLES;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    glGenFramebuffers(1, @FScratchFBO);
    glGenFramebuffers(1, @FResolveFBO);
  end;
end;

destructor TOpenGLRHICommandList.Destroy;
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    if FScratchFBO <> 0 then
      glDeleteFramebuffers(1, @FScratchFBO);
    if FResolveFBO <> 0 then
      glDeleteFramebuffers(1, @FResolveFBO);
  end;
  inherited;
end;

procedure TOpenGLRHICommandList.BeginRecording;
begin
  FIsRecording := True;
  FIsRendering := False;
  FCurrentPipeline := nil;
  FCurrentComputePipeline := nil;
  FCurrentIndexBuffer := nil;
  FDebugGroupDepth := 0;
end;

procedure TOpenGLRHICommandList.EndRecording;
begin
  if FIsRendering then
    EndRendering;
  while FDebugGroupDepth > 0 do
    PopDebugGroup;
  FIsRecording := False;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    if FScissorEnabled then
    begin
      glDisable(GL_SCISSOR_TEST);
      FScissorEnabled := False;
    end;
    glBindVertexArray(0);
    glUseProgram(0);
  end;
end;

procedure TOpenGLRHICommandList.EmitMemoryBarrierForState(const NewState: TRHIResourceState);
{$ifndef OpenGLES}
var
  Bits: TGLbitfield;
{$endif}
begin
  Inc(FBarrierCount);
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  {$ifndef OpenGLES}
  if Assigned(glMemoryBarrier) then
  begin
    case NewState of
      rsShaderRead:
        Bits := GL_TEXTURE_FETCH_BARRIER_BIT or GL_SHADER_IMAGE_ACCESS_BARRIER_BIT or
                GL_SHADER_STORAGE_BARRIER_BIT or GL_UNIFORM_BARRIER_BIT;
      rsUnorderedAccess:
        Bits := GL_SHADER_IMAGE_ACCESS_BARRIER_BIT or GL_SHADER_STORAGE_BARRIER_BIT;
      rsIndirectRead:
        Bits := GL_COMMAND_BARRIER_BIT or GL_SHADER_STORAGE_BARRIER_BIT or
                GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT or GL_ELEMENT_ARRAY_BARRIER_BIT;
      rsColorAttachment, rsDepthStencilWrite, rsDepthStencilRead:
        Bits := GL_FRAMEBUFFER_BARRIER_BIT or GL_TEXTURE_FETCH_BARRIER_BIT;
      rsTransferSrc, rsTransferDst:
        Bits := GL_BUFFER_UPDATE_BARRIER_BIT or GL_FRAMEBUFFER_BARRIER_BIT or
                GL_SHADER_IMAGE_ACCESS_BARRIER_BIT;
    else
      Bits := 0;
    end;
    if Bits <> 0 then
      glMemoryBarrier(Bits);
  end;
  {$endif}
end;

procedure TOpenGLRHICommandList.TransitionTexture(const Texture: TRHITexture;
  const NewState: TRHIResourceState);
begin
  if Texture = nil then Exit;
  EmitMemoryBarrierForState(NewState);
  Texture.CurrentState := NewState;
end;

procedure TOpenGLRHICommandList.EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture);
begin
  Inc(FAliasingBarrierCount);
  Inc(FBarrierCount);
  if NewTexture <> nil then
    NewTexture.CurrentState := rsUndefined;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    {$ifndef OpenGLES}
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(GL_ALL_BARRIER_BITS);
    {$endif}
  end;
  if OldTexture = nil then ; { Silence unused hint }
end;

procedure TOpenGLRHICommandList.GenerateMipmaps(const Texture: TRHITexture);
var
  GLTex: TOpenGLRHITexture;
begin
  if Texture = nil then Exit;
  GLTex := Texture as TOpenGLRHITexture;
  if GLTex.IsDefaultBackbuffer then Exit;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    glBindTexture(GLTex.Target, GLTex.Handle);
    glGenerateMipmap(GLTex.Target);
    glBindTexture(GLTex.Target, 0);
  end;
end;

procedure TOpenGLRHICommandList.BeginRendering(const Info: TRHIRenderingInfo);
var
  ClearMask: TGLbitfield;
  ColorTex, DepthTex: TOpenGLRHITexture;
  DepthAttachmentPoint: TGLenum;
  DrawBufs: array[0..7] of TGLenum;
  UseDefaultFBO: Boolean;
  I, AttCount: Integer;
begin
  FIsRendering := True;
  FCurrentPassHasCommands := False;
  FActiveRenderingInfo := Info;
  FActiveRenderingInfo.ColorAttachments := Copy(Info.ColorAttachments);
  FActiveRenderingHasColor := (Length(Info.ColorAttachments) > 0) and
    (Info.ColorAttachments[0].Texture <> nil);
  if FActiveRenderingHasColor then
  begin
    FActiveRenderingColorFormat := Info.ColorAttachments[0].Texture.Desc.Format;
    FActiveRenderingSampleCount := Max(Cardinal(1),
      Info.ColorAttachments[0].Texture.Desc.SampleCount);
  end else
  begin
    FActiveRenderingColorFormat := pfUndefined;
    FActiveRenderingSampleCount := 1;
  end;
  FActiveRenderingHasDepth := Info.HasDepthAttachment and
    (Info.DepthAttachment.Texture <> nil);
  if FActiveRenderingHasDepth then
  begin
    FActiveRenderingDepthFormat := Info.DepthAttachment.Texture.Desc.Format;
    if not FActiveRenderingHasColor then
      FActiveRenderingSampleCount := Max(Cardinal(1),
        Info.DepthAttachment.Texture.Desc.SampleCount);
  end else
    FActiveRenderingDepthFormat := pfUndefined;

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  UseDefaultFBO :=
    ((Length(Info.ColorAttachments) > 0) and
     (Info.ColorAttachments[0].Texture <> nil) and
     (Info.ColorAttachments[0].Texture as TOpenGLRHITexture).IsDefaultBackbuffer) or
    ((Length(Info.ColorAttachments) = 0) and
     Info.HasDepthAttachment and
     (Info.DepthAttachment.Texture <> nil) and
     (Info.DepthAttachment.Texture as TOpenGLRHITexture).IsDefaultBackbuffer);

  if UseDefaultFBO then
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
  else
  begin
    glBindFramebuffer(GL_FRAMEBUFFER, FScratchFBO);
    AttCount := Min(8, Length(Info.ColorAttachments));
    for I := 0 to AttCount - 1 do
    begin
      ColorTex := Info.ColorAttachments[I].Texture as TOpenGLRHITexture;
      DrawBufs[I] := GL_COLOR_ATTACHMENT0 + Cardinal(I);
      if ColorTex <> nil then
      begin
        if ColorTex.Desc.Dimension = tdCube then
          glFramebufferTexture2D(GL_FRAMEBUFFER, DrawBufs[I],
            GL_TEXTURE_CUBE_MAP_POSITIVE_X + Min(Cardinal(5), Info.ColorAttachments[I].ArrayLayer),
            ColorTex.Handle, Info.ColorAttachments[I].MipLevel)
        else if ColorTex.Desc.Dimension in [td2DArray, td3D] then
          glFramebufferTextureLayer(GL_FRAMEBUFFER, DrawBufs[I],
            ColorTex.Handle, Info.ColorAttachments[I].MipLevel,
            Info.ColorAttachments[I].ArrayLayer)
        else
          glFramebufferTexture2D(GL_FRAMEBUFFER, DrawBufs[I],
            ColorTex.Target, ColorTex.Handle, Info.ColorAttachments[I].MipLevel);
      end else
        glFramebufferTexture2D(GL_FRAMEBUFFER, DrawBufs[I], GL_TEXTURE_2D, 0, 0);
    end;
    for I := AttCount to 3 do
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + Cardinal(I), GL_TEXTURE_2D, 0, 0);

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_TEXTURE_2D, 0, 0);

    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
    begin
      DepthTex := Info.DepthAttachment.Texture as TOpenGLRHITexture;
      if DepthTex.Desc.Format in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
        DepthAttachmentPoint := GL_DEPTH_STENCIL_ATTACHMENT
      else
        DepthAttachmentPoint := GL_DEPTH_ATTACHMENT;

      if DepthTex.Desc.Dimension = tdCube then
        glFramebufferTexture2D(GL_FRAMEBUFFER, DepthAttachmentPoint,
          GL_TEXTURE_CUBE_MAP_POSITIVE_X + Min(Cardinal(5), Info.DepthAttachment.ArrayLayer),
          DepthTex.Handle, Info.DepthAttachment.MipLevel)
      else if DepthTex.Desc.Dimension in [td2DArray, td3D] then
        glFramebufferTextureLayer(GL_FRAMEBUFFER, DepthAttachmentPoint,
          DepthTex.Handle, Info.DepthAttachment.MipLevel,
          Info.DepthAttachment.ArrayLayer)
      else
        glFramebufferTexture2D(GL_FRAMEBUFFER, DepthAttachmentPoint,
          DepthTex.Target, DepthTex.Handle, Info.DepthAttachment.MipLevel);
    end;

    {$ifndef OpenGLES}
    if AttCount = 0 then
    begin
      glDrawBuffer(GL_NONE);
      glReadBuffer(GL_NONE);
    end else
    begin
      if (AttCount > 1) and Assigned(glDrawBuffers) then
        glDrawBuffers(AttCount, @DrawBufs[0])
      else
        glDrawBuffer(GL_COLOR_ATTACHMENT0);
      glReadBuffer(GL_COLOR_ATTACHMENT0);
    end;
    {$endif}
  end;

  if FScissorEnabled then
    glDisable(GL_SCISSOR_TEST);

  ClearMask := 0;
  if (Length(Info.ColorAttachments) > 0) and (Info.ColorAttachments[0].LoadOp = loClear) then
  begin
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(
      Info.ColorAttachments[0].ClearColor.X,
      Info.ColorAttachments[0].ClearColor.Y,
      Info.ColorAttachments[0].ClearColor.Z,
      Info.ColorAttachments[0].ClearColor.W);
    ClearMask := ClearMask or GL_COLOR_BUFFER_BIT;
  end;

  if Info.HasDepthAttachment and (Info.DepthAttachment.LoadOp = loClear) then
  begin
    glDepthMask(GL_TRUE);
    {$ifdef OpenGLES}
    glClearDepthf(Info.DepthAttachment.ClearDepth);
    {$else}
    glClearDepth(Info.DepthAttachment.ClearDepth);
    {$endif}
    ClearMask := ClearMask or GL_DEPTH_BUFFER_BIT;
    if FActiveRenderingDepthFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
    begin
      glStencilMask($FF);
      glClearStencil(Info.DepthAttachment.ClearStencil);
      ClearMask := ClearMask or GL_STENCIL_BUFFER_BIT;
    end;
  end;

  if ClearMask <> 0 then
    glClear(ClearMask);

  if FScissorEnabled then
    glEnable(GL_SCISSOR_TEST);

  if (Info.RenderArea.Width > 0) and (Info.RenderArea.Height > 0) then
  begin
    SetViewport(FloatRectangle(Info.RenderArea), 0.0, 1.0);
    SetScissor(Info.RenderArea);
  end;
end;

procedure TOpenGLRHICommandList.EndRendering;
var
  I, W, H: Integer;
  MsaaTex, ResolveTex: TOpenGLRHITexture;
begin
  if FIsRendering and (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    { Perform single-pass MSAA color resolve via glBlitFramebuffer when ResolveTexture is bound }
    for I := 0 to High(FActiveRenderingInfo.ColorAttachments) do
      if (FActiveRenderingInfo.ColorAttachments[I].Texture <> nil) and
         (FActiveRenderingInfo.ColorAttachments[I].ResolveTexture <> nil) and
         (FActiveRenderingInfo.ColorAttachments[I].Texture.Desc.SampleCount > 1) then
      begin
        MsaaTex := FActiveRenderingInfo.ColorAttachments[I].Texture as TOpenGLRHITexture;
        ResolveTex := FActiveRenderingInfo.ColorAttachments[I].ResolveTexture as TOpenGLRHITexture;
        W := Max(1, Integer(ResolveTex.Desc.Width));
        H := Max(1, Integer(ResolveTex.Desc.Height));
        if FScissorEnabled then
          glDisable(GL_SCISSOR_TEST);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, FScratchFBO);
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
          MsaaTex.Target, MsaaTex.Handle, 0);
        if ResolveTex.IsDefaultBackbuffer then
          glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
        else
        begin
          glBindFramebuffer(GL_DRAW_FRAMEBUFFER, FResolveFBO);
          glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
            ResolveTex.Target, ResolveTex.Handle,
            FActiveRenderingInfo.ColorAttachments[I].ResolveMipLevel);
        end;
        glBlitFramebuffer(0, 0, W, H, 0, 0, W, H, GL_COLOR_BUFFER_BIT, GL_NEAREST);
        if FScissorEnabled then
          glEnable(GL_SCISSOR_TEST);
      end;

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  end;
  FIsRendering := False;
  FCurrentPassHasCommands := False;
end;

procedure TOpenGLRHICommandList.ClearAttachments(const ClearColorBuf: Boolean;
  const ClearColor: TCastleColor; const ClearDepthBuf: Boolean;
  const ClearDepth: Single; const ClearStencilBuf: Boolean;
  const ClearStencil: Byte);
var
  ClearMask: TGLbitfield;
begin
  if FIsRendering then
    FCurrentPassHasCommands := True;
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  ClearMask := 0;
  if ClearColorBuf then
  begin
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(ClearColor.X, ClearColor.Y, ClearColor.Z, ClearColor.W);
    ClearMask := ClearMask or GL_COLOR_BUFFER_BIT;
  end;
  if ClearDepthBuf then
  begin
    glDepthMask(GL_TRUE);
    {$ifdef OpenGLES}
    glClearDepthf(ClearDepth);
    {$else}
    glClearDepth(ClearDepth);
    {$endif}
    ClearMask := ClearMask or GL_DEPTH_BUFFER_BIT;
  end;
  if ClearStencilBuf then
  begin
    glStencilMask($FF);
    glClearStencil(ClearStencil);
    ClearMask := ClearMask or GL_STENCIL_BUFFER_BIT;
  end;
  if ClearMask <> 0 then
    glClear(ClearMask);
end;

procedure TOpenGLRHICommandList.SetViewport(const ViewportRect: TFloatRectangle;
  const MinDepth, MaxDepth: Single);
begin
  FDynamicViewportRect := ViewportRect;
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;
  glViewport(Round(ViewportRect.Left), Round(ViewportRect.Bottom),
    Max(0, Round(ViewportRect.Width)), Max(0, Round(ViewportRect.Height)));
  {$ifdef OpenGLES}
  glDepthRangef(MinDepth, MaxDepth);
  {$else}
  glDepthRange(MinDepth, MaxDepth);
  {$endif}
end;

procedure TOpenGLRHICommandList.SetScissor(const ScissorRect: TRectangle);
begin
  FDynamicScissorRect := ScissorRect;
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;
  if not FScissorEnabled then
  begin
    glEnable(GL_SCISSOR_TEST);
    FScissorEnabled := True;
  end;
  glScissor(ScissorRect.Left, ScissorRect.Bottom,
    Max(0, ScissorRect.Width), Max(0, ScissorRect.Height));
end;

procedure TOpenGLRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single);
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glPolygonOffset(SlopeFactor, ConstantFactor);
end;

procedure TOpenGLRHICommandList.SetLineWidth(const LineWidth: Single);
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glLineWidth(Max(1.0, LineWidth));
end;

procedure TOpenGLRHICommandList.SetBlendConstants(const ABlendConstants: TVector4);
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext and
     ((GLFeatures = nil) or GLFeatures.BlendConstant) then
    glBlendColor(ABlendConstants.X, ABlendConstants.Y, ABlendConstants.Z, ABlendConstants.W);
end;

procedure TOpenGLRHICommandList.SetCullMode(const CullMode: TRHICullMode);
begin
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;
  if CullMode = cmNone then
    glDisable(GL_CULL_FACE)
  else
  begin
    glEnable(GL_CULL_FACE);
    if CullMode = cmBack then
      glCullFace(GL_BACK)
    else
      glCullFace(GL_FRONT);
  end;
end;

procedure TOpenGLRHICommandList.SetFrontFace(const FrontFace: TRHIFrontFace);
begin
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;
  if FrontFace = ffCounterClockwise then
    glFrontFace(GL_CCW)
  else
    glFrontFace(GL_CW);
end;

procedure TOpenGLRHICommandList.SetDepthTestEnable(const Enable: Boolean);
begin
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;
  if Enable then
    glEnable(GL_DEPTH_TEST)
  else
    glDisable(GL_DEPTH_TEST);
end;

procedure TOpenGLRHICommandList.SetDepthWriteEnable(const Enable: Boolean);
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glDepthMask(TGLboolean(Enable));
end;

procedure TOpenGLRHICommandList.SetDepthCompareOp(const CompareOp: TRHICompareOp);
begin
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glDepthFunc(RHIToGLCompareOp(CompareOp));
end;

procedure TOpenGLRHICommandList.SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology);
begin
  FCurrentPrimitiveMode := RHIToGLTopology(Topology);
end;

procedure TOpenGLRHICommandList.ApplyPipelineState(const NewPipeline: TOpenGLRHIPipeline);
var
  D: TRHIGraphicsPipelineDesc;
  WriteMask: Byte;
begin
  D := NewPipeline.Desc;
  FCurrentPrimitiveMode := NewPipeline.PrimitiveMode;

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  glUseProgram(NewPipeline.ProgramHandle);
  glBindVertexArray(NewPipeline.VAOHandle);

  SetCullMode(D.Rasterizer.CullMode);
  SetFrontFace(D.Rasterizer.FrontFace);

  {$ifndef OpenGLES}
  case D.Rasterizer.PolygonMode of
    pmFill:  glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    pmLine:  glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    pmPoint: glPolygonMode(GL_FRONT_AND_BACK, GL_POINT);
  end;
  {$endif}

  if D.Rasterizer.DepthBiasEnable then
    glEnable(GL_POLYGON_OFFSET_FILL)
  else
    glDisable(GL_POLYGON_OFFSET_FILL);

  if D.DepthStencil.DepthTestEnable then
  begin
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(RHIToGLCompareOp(D.DepthStencil.DepthCompareOp));
  end else
    glDisable(GL_DEPTH_TEST);

  glDepthMask(TGLboolean(D.DepthStencil.DepthWriteEnable));

  if D.DepthStencil.StencilTestEnable then
  begin
    glEnable(GL_STENCIL_TEST);
    glStencilFuncSeparate(GL_FRONT,
      RHIToGLCompareOp(D.DepthStencil.FrontStencil.CompareOp),
      TGLint(D.DepthStencil.FrontStencil.Reference),
      D.DepthStencil.FrontStencil.CompareMask);
    glStencilOpSeparate(GL_FRONT,
      RHIToGLStencilOp(D.DepthStencil.FrontStencil.FailOp),
      RHIToGLStencilOp(D.DepthStencil.FrontStencil.DepthFailOp),
      RHIToGLStencilOp(D.DepthStencil.FrontStencil.PassOp));
    glStencilMaskSeparate(GL_FRONT, D.DepthStencil.FrontStencil.WriteMask);

    glStencilFuncSeparate(GL_BACK,
      RHIToGLCompareOp(D.DepthStencil.BackStencil.CompareOp),
      TGLint(D.DepthStencil.BackStencil.Reference),
      D.DepthStencil.BackStencil.CompareMask);
    glStencilOpSeparate(GL_BACK,
      RHIToGLStencilOp(D.DepthStencil.BackStencil.FailOp),
      RHIToGLStencilOp(D.DepthStencil.BackStencil.DepthFailOp),
      RHIToGLStencilOp(D.DepthStencil.BackStencil.PassOp));
    glStencilMaskSeparate(GL_BACK, D.DepthStencil.BackStencil.WriteMask);
  end else
    glDisable(GL_STENCIL_TEST);

  if D.BlendState.BlendEnable then
  begin
    glEnable(GL_BLEND);
    glBlendFuncSeparate(
      RHIToGLBlendFactor(D.BlendState.SrcColorBlendFactor),
      RHIToGLBlendFactor(D.BlendState.DstColorBlendFactor),
      RHIToGLBlendFactor(D.BlendState.SrcAlphaBlendFactor),
      RHIToGLBlendFactor(D.BlendState.DstAlphaBlendFactor));
    glBlendEquationSeparate(
      RHIToGLBlendOp(D.BlendState.ColorBlendOp),
      RHIToGLBlendOp(D.BlendState.AlphaBlendOp));
  end else
    glDisable(GL_BLEND);

  if D.BlendState.DisableColorWrites then
    WriteMask := 0
  else if D.BlendState.ColorWriteMask <> 0 then
    WriteMask := D.BlendState.ColorWriteMask
  else
    WriteMask := $0F;

  glColorMask(
    TGLboolean((WriteMask and 1) <> 0),
    TGLboolean((WriteMask and 2) <> 0),
    TGLboolean((WriteMask and 4) <> 0),
    TGLboolean((WriteMask and 8) <> 0));
end;

procedure TOpenGLRHICommandList.BindPipeline(const Pipeline: TRHIPipeline);
var
  GLPipe: TOpenGLRHIPipeline;
begin
  if Pipeline = nil then Exit;
  GLPipe := Pipeline as TOpenGLRHIPipeline;
  FCurrentComputePipeline := nil;
  ApplyPipelineState(GLPipe);
  FCurrentPipeline := GLPipe;
  if (FCurrentIndexBuffer <> nil) and (FDevice <> nil) and FDevice.HasLiveGLContext then
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);
end;

procedure TOpenGLRHICommandList.ApplyDescriptorSetInternal(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
var
  GLSet: TOpenGLRHIDescriptorSet;
  I, DynIdx: Integer;
  Slot, ImgSlot: Cardinal;
  ActualOffset, ActualRange: PtrUInt;
  TargetEnum: TGLenum;
  TexEntry: TOpenGLBoundTexture;
  IsLayered: TGLboolean;
begin
  if (DescriptorSet = nil) or (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  GLSet := DescriptorSet as TOpenGLRHIDescriptorSet;
  DynIdx := 0;

  { 1. Bind Uniform Buffers (GL_UNIFORM_BUFFER) & Shader Storage Buffers (GL_SHADER_STORAGE_BUFFER) }
  for I := 0 to High(GLSet.FBoundBuffers) do
    if GLSet.FBoundBuffers[I].Buffer <> nil then
    begin
      Slot := SetIndex * GL_DESCRIPTOR_SET_SLOT_STRIDE + GLSet.FBoundBuffers[I].Binding;
      ActualOffset := GLSet.FBoundBuffers[I].Offset;
      if (DynIdx <= High(DynamicOffsets)) and
         (GLSet.FBoundBuffers[I].IsDynamic or (High(DynamicOffsets) >= 0)) then
      begin
        Inc(ActualOffset, DynamicOffsets[DynIdx]);
        Inc(DynIdx);
      end;

      ActualRange := GLSet.FBoundBuffers[I].Range;
      if ActualRange = 0 then
        ActualRange := Max(PtrUInt(1), GLSet.FBoundBuffers[I].Buffer.Desc.Size);

      if GLSet.FBoundBuffers[I].IsStorage then
        TargetEnum := GL_SHADER_STORAGE_BUFFER
      else
        TargetEnum := GL_UNIFORM_BUFFER;

      if GLSet.FBoundBuffers[I].Buffer.FIsMappedForWrite and
         (not GLSet.FBoundBuffers[I].Buffer.FMappedUploadedViaSubData) then
        GLSet.FBoundBuffers[I].Buffer.SyncMappedToGL(ActualOffset, ActualRange);

      glBindBufferRange(TargetEnum, Slot,
        GLSet.FBoundBuffers[I].Buffer.Handle, ActualOffset, ActualRange);
    end;

  { 2. Bind Combined Image Samplers (glBindTexture + glBindSampler) & Storage Images (glBindImageTexture) }
  for I := 0 to High(GLSet.FBoundTextures) do
  begin
    TexEntry := GLSet.FBoundTextures[I];
    if TexEntry.Texture = nil then
      Continue;

    Slot := SetIndex * GL_DESCRIPTOR_SET_SLOT_STRIDE + TexEntry.Binding + TexEntry.ArrayElement;
    if TexEntry.IsStorageImage then
    begin
      {$ifndef OpenGLES}
      if Assigned(glBindImageTexture) then
      begin
        ImgSlot := Slot;
        if (FDevice.MaxImageUnits > 0) and (ImgSlot >= FDevice.MaxImageUnits) then
          ImgSlot := ImgSlot mod FDevice.MaxImageUnits;
        if (not TexEntry.HasSubresourceOverride) and
           (TexEntry.Texture.Desc.Dimension in [tdCube, td2DArray, td3D]) then
          IsLayered := GL_TRUE
        else
          IsLayered := GL_FALSE;
        glBindImageTexture(ImgSlot, TexEntry.Texture.Handle,
          TGLint(TexEntry.MipLevel), IsLayered, TGLint(TexEntry.ArrayLayer),
          GL_READ_WRITE, TexEntry.Texture.ImageUnitFormat);
      end;
      {$endif}
    end else
    begin
      glActiveTexture(GL_TEXTURE0 + Slot);
      glBindTexture(TexEntry.Texture.Target, TexEntry.Texture.Handle);
      if TexEntry.Sampler <> nil then
        glBindSampler(Slot, TexEntry.Sampler.Handle)
      else
        glBindSampler(Slot, 0);
    end;
  end;
end;

procedure TOpenGLRHICommandList.BindDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
begin
  ApplyDescriptorSetInternal(SetIndex, DescriptorSet, DynamicOffsets);
end;

procedure TOpenGLRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
var
  TargetUBO: TGLuint;
begin
  if (Size = 0) or (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  TargetUBO := 0;
  if (ssCompute in StageFlags) and (FCurrentComputePipeline <> nil) and
     ((FCurrentPipeline = nil) or (StageFlags = [ssCompute])) then
  begin
    FCurrentComputePipeline.EnsurePushConstantCapacity(Offset + Size);
    TargetUBO := FCurrentComputePipeline.PushConstantUBO;
  end else
  if FCurrentPipeline <> nil then
  begin
    FCurrentPipeline.EnsurePushConstantCapacity(Offset + Size);
    TargetUBO := FCurrentPipeline.PushConstantUBO;
  end else
  if FCurrentComputePipeline <> nil then
  begin
    FCurrentComputePipeline.EnsurePushConstantCapacity(Offset + Size);
    TargetUBO := FCurrentComputePipeline.PushConstantUBO;
  end;

  if TargetUBO <> 0 then
  begin
    glBindBuffer(GL_UNIFORM_BUFFER, TargetUBO);
    glBufferSubData(GL_UNIFORM_BUFFER, Offset, Size, @Data);
    glBindBufferBase(GL_UNIFORM_BUFFER, GL_PUSH_CONSTANT_UBO_BINDING, TargetUBO);
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
  end;
end;

procedure TOpenGLRHICommandList.BindComputePipeline(const Pipeline: TRHIComputePipeline);
var
  GLComp: TOpenGLRHIComputePipeline;
begin
  if Pipeline = nil then Exit;
  GLComp := Pipeline as TOpenGLRHIComputePipeline;
  FCurrentComputePipeline := GLComp;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glUseProgram(GLComp.ProgramHandle);
end;

procedure TOpenGLRHICommandList.BindComputeDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
begin
  ApplyDescriptorSetInternal(SetIndex, DescriptorSet, DynamicOffsets);
end;

procedure TOpenGLRHICommandList.Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
  Inc(FComputeDispatchCount);
  if FDevice <> nil then
    Inc(FDevice.FComputeDispatchCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  {$ifndef OpenGLES}
  if Assigned(glDispatchCompute) then
  begin
    glDispatchCompute(Max(1, GroupCountX), Max(1, GroupCountY), Max(1, GroupCountZ));
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(
        GL_SHADER_IMAGE_ACCESS_BARRIER_BIT or
        GL_SHADER_STORAGE_BARRIER_BIT or
        GL_TEXTURE_FETCH_BARRIER_BIT or
        GL_BUFFER_UPDATE_BARRIER_BIT or
        GL_COMMAND_BARRIER_BIT or
        GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT or
        GL_ELEMENT_ARRAY_BARRIER_BIT);
  end;
  {$endif}
end;

procedure TOpenGLRHICommandList.DispatchIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt);
var
  GLBuf: TOpenGLRHIBuffer;
  CmdStruct: TRHIDispatchIndirectCommand;
begin
  if IndirectBuffer = nil then Exit;
  Inc(FComputeDispatchCount);
  if FDevice <> nil then
    Inc(FDevice.FComputeDispatchCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  GLBuf := IndirectBuffer as TOpenGLRHIBuffer;
  {$ifndef OpenGLES}
  if Assigned(glDispatchComputeIndirect) then
  begin
    glBindBuffer(GL_DISPATCH_INDIRECT_BUFFER, GLBuf.Handle);
    glDispatchComputeIndirect(TGLintptr(Offset));
    glBindBuffer(GL_DISPATCH_INDIRECT_BUFFER, 0);
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(
        GL_SHADER_IMAGE_ACCESS_BARRIER_BIT or
        GL_SHADER_STORAGE_BARRIER_BIT or
        GL_TEXTURE_FETCH_BARRIER_BIT or
        GL_BUFFER_UPDATE_BARRIER_BIT or
        GL_COMMAND_BARRIER_BIT);
  end else
  if Assigned(glDispatchCompute) then
  begin
    FillChar(CmdStruct, SizeOf(CmdStruct), 0);
    GLBuf.ReadData(CmdStruct, SizeOf(CmdStruct), Offset);
    glDispatchCompute(
      Max(1, CmdStruct.GroupCountX),
      Max(1, CmdStruct.GroupCountY),
      Max(1, CmdStruct.GroupCountZ));
  end;
  {$else}
  if GLBuf = nil then ;
  if CmdStruct.GroupCountX = 0 then ;
  {$endif}
end;

procedure TOpenGLRHICommandList.ResetQueryPool(const QueryPool: TRHIQueryPool;
  const FirstQuery, QueryCount: Cardinal);
var
  GLPool: TOpenGLRHIQueryPool;
  I, EndIdx: Cardinal;
begin
  if (QueryPool = nil) or (QueryCount = 0) then Exit;
  GLPool := QueryPool as TOpenGLRHIQueryPool;
  Inc(GLPool.FResetCount);
  if FirstQuery >= Cardinal(Length(GLPool.FQueryWritten)) then
    Exit;
  EndIdx := Min(FirstQuery + QueryCount, Cardinal(Length(GLPool.FQueryWritten))) - 1;
  for I := FirstQuery to EndIdx do
  begin
    GLPool.FQueryWritten[I] := False;
    GLPool.FSimulatedResults[I] := 0;
    GLPool.FActiveTargets[I] := 0;
  end;
end;

procedure TOpenGLRHICommandList.BeginQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Precise: Boolean);
var
  GLPool: TOpenGLRHIQueryPool;
  Target: TGLenum;
begin
  if QueryPool = nil then Exit;
  GLPool := QueryPool as TOpenGLRHIQueryPool;
  if QueryIndex >= Cardinal(Length(GLPool.FQueries)) then Exit;

  if GLPool.Desc.QueryType = qtTimestamp then
  begin
    {$ifndef OpenGLES}
    Target := GL_TIME_ELAPSED;
    {$else}
    Target := GL_ANY_SAMPLES_PASSED;
    {$endif}
  end else
  begin
    {$ifndef OpenGLES}
    if Precise then
      Target := GL_SAMPLES_PASSED
    else
      Target := GL_ANY_SAMPLES_PASSED;
    {$else}
    Target := GL_ANY_SAMPLES_PASSED;
    {$endif}
  end;

  GLPool.FActiveTargets[QueryIndex] := Target;
  GLPool.FQueryWritten[QueryIndex] := True;
  if GLPool.FSimulatedResults[QueryIndex] = 0 then
    GLPool.FSimulatedResults[QueryIndex] := 64;

  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glBeginQuery(Target, GLPool.FQueries[QueryIndex]);
end;

procedure TOpenGLRHICommandList.EndQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal);
var
  GLPool: TOpenGLRHIQueryPool;
  Target: TGLenum;
begin
  if QueryPool = nil then Exit;
  GLPool := QueryPool as TOpenGLRHIQueryPool;
  if QueryIndex >= Cardinal(Length(GLPool.FQueries)) then Exit;

  Target := GLPool.FActiveTargets[QueryIndex];
  if Target = 0 then
    Target := GL_ANY_SAMPLES_PASSED;
  GLPool.FQueryWritten[QueryIndex] := True;

  if (FDevice <> nil) and FDevice.HasLiveGLContext then
    glEndQuery(Target);
end;

procedure TOpenGLRHICommandList.WriteTimestamp(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Stage: TRHIShaderStage);
var
  GLPool: TOpenGLRHIQueryPool;
begin
  if QueryPool = nil then Exit;
  GLPool := QueryPool as TOpenGLRHIQueryPool;
  if QueryIndex >= Cardinal(Length(GLPool.FQueries)) then Exit;

  GLPool.FQueryWritten[QueryIndex] := True;
  GLPool.FSimulatedResults[QueryIndex] := UInt64(QueryIndex + 1) * UInt64(1000000);

  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    {$ifndef OpenGLES}
    if Assigned(glQueryCounter) then
      glQueryCounter(GLPool.FQueries[QueryIndex], GL_TIMESTAMP);
    {$endif}
  end;
  if Stage = ssCompute then ; { Silence unused hint }
end;

procedure TOpenGLRHICommandList.ApplyVertexLayout(const Pipeline: TOpenGLRHIPipeline;
  const FirstBinding: Cardinal; const Buffers: array of TRHIBuffer;
  const Offsets: array of PtrUInt);
var
  I, J, BIdx: Integer;
  Attr: TRHIVertexAttributeDesc;
  BindDesc: TRHIVertexBindingDesc;
  FoundBind: Boolean;
  GLBuf: TOpenGLRHIBuffer;
  CompCount: TGLint;
  CompType: TGLenum;
  Normalized: TGLboolean;
  IsIntAttr: Boolean;
  BufOffset: PtrUInt;
begin
  if (FDevice = nil) or (not FDevice.HasLiveGLContext) or (Pipeline = nil) then
    Exit;

  glBindVertexArray(Pipeline.VAOHandle);

  for I := 0 to High(Pipeline.Desc.VertexInput.Attributes) do
  begin
    Attr := Pipeline.Desc.VertexInput.Attributes[I];
    BIdx := Integer(Attr.Binding) - Integer(FirstBinding);
    if (BIdx < 0) or (BIdx > High(Buffers)) or (Buffers[BIdx] = nil) then
      Continue;

    FoundBind := False;
    FillChar(BindDesc, SizeOf(BindDesc), 0);
    for J := 0 to High(Pipeline.Desc.VertexInput.Bindings) do
      if Pipeline.Desc.VertexInput.Bindings[J].Binding = Attr.Binding then
      begin
        BindDesc := Pipeline.Desc.VertexInput.Bindings[J];
        FoundBind := True;
        Break;
      end;
    if not FoundBind then
      Continue;

    GLBuf := Buffers[BIdx] as TOpenGLRHIBuffer;
    if BIdx <= High(Offsets) then
      BufOffset := Offsets[BIdx]
    else
      BufOffset := 0;

    if GLBuf.FIsMappedForWrite and (not GLBuf.FMappedUploadedViaSubData) then
      GLBuf.SyncMappedToGL(BufOffset, 0);

    glBindBuffer(GL_ARRAY_BUFFER, GLBuf.Handle);
    glEnableVertexAttribArray(Attr.Location);

    Normalized := GL_FALSE;
    IsIntAttr := False;
    case Attr.Format of
      vafFloat:
        begin CompCount := 1; CompType := GL_FLOAT; end;
      vafVector2:
        begin CompCount := 2; CompType := GL_FLOAT; end;
      vafVector3:
        begin CompCount := 3; CompType := GL_FLOAT; end;
      vafVector4:
        begin CompCount := 4; CompType := GL_FLOAT; end;
      vafByte4Normalized:
        begin CompCount := 4; CompType := GL_BYTE; Normalized := GL_TRUE; end;
      vafUByte4Normalized:
        begin CompCount := 4; CompType := GL_UNSIGNED_BYTE; Normalized := GL_TRUE; end;
      vafShort2:
        begin CompCount := 2; CompType := GL_SHORT; end;
      vafShort4:
        begin CompCount := 4; CompType := GL_SHORT; end;
      vafUInt4:
        begin CompCount := 4; CompType := GL_UNSIGNED_INT; IsIntAttr := True; end;
    else
      begin CompCount := 4; CompType := GL_FLOAT; end;
    end;

    if IsIntAttr then
      glVertexAttribIPointer(Attr.Location, CompCount, CompType,
        BindDesc.Stride, Pointer(BufOffset + Attr.Offset))
    else
      glVertexAttribPointer(Attr.Location, CompCount, CompType, Normalized,
        BindDesc.Stride, Pointer(BufOffset + Attr.Offset));

    if BindDesc.PerInstance then
      glVertexAttribDivisor(Attr.Location, 1)
    else
      glVertexAttribDivisor(Attr.Location, 0);
  end;

  if FCurrentIndexBuffer <> nil then
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);
end;

procedure TOpenGLRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
begin
  if FCurrentPipeline = nil then Exit;
  ApplyVertexLayout(FCurrentPipeline, FirstBinding, Buffers, Offsets);
end;

procedure TOpenGLRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
begin
  if Buffer = nil then Exit;
  FCurrentIndexBuffer := Buffer as TOpenGLRHIBuffer;
  FCurrentIndexOffset := Offset;
  if IndexType = itUInt16 then
  begin
    FCurrentIndexType := GL_UNSIGNED_SHORT;
    FCurrentIndexSize := 2;
  end else
  begin
    FCurrentIndexType := GL_UNSIGNED_INT;
    FCurrentIndexSize := 4;
  end;
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    if FCurrentIndexBuffer.FIsMappedForWrite and
       (not FCurrentIndexBuffer.FMappedUploadedViaSubData) then
      FCurrentIndexBuffer.SyncMappedToGL(Offset, 0);
    if FCurrentPipeline <> nil then
      glBindVertexArray(FCurrentPipeline.VAOHandle);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);
  end;
end;

procedure TOpenGLRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  if (VertexCount = 0) or (InstanceCount = 0) or (FCurrentPipeline = nil) then
    Exit;
  FCurrentPassHasCommands := True;
  Inc(FDrawCallCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  glUseProgram(FCurrentPipeline.ProgramHandle);
  glBindVertexArray(FCurrentPipeline.VAOHandle);

  {$ifndef OpenGLES}
  if (FirstInstance > 0) and Assigned(glDrawArraysInstancedBaseInstance) then
    glDrawArraysInstancedBaseInstance(FCurrentPrimitiveMode,
      FirstVertex, VertexCount, InstanceCount, FirstInstance)
  else
  {$endif}
  if InstanceCount <= 1 then
    glDrawArrays(FCurrentPrimitiveMode, FirstVertex, VertexCount)
  else
    glDrawArraysInstanced(FCurrentPrimitiveMode, FirstVertex, VertexCount, InstanceCount);
end;

procedure TOpenGLRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
var
  IndexPtr: Pointer;
begin
  if (IndexCount = 0) or (InstanceCount = 0) or (FCurrentPipeline = nil) then
    Exit;
  FCurrentPassHasCommands := True;
  Inc(FDrawCallCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  glUseProgram(FCurrentPipeline.ProgramHandle);
  glBindVertexArray(FCurrentPipeline.VAOHandle);
  if FCurrentIndexBuffer <> nil then
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);

  IndexPtr := Pointer(FCurrentIndexOffset + PtrUInt(FirstIndex) * PtrUInt(FCurrentIndexSize));
  {$ifndef OpenGLES}
  if (FirstInstance > 0) and Assigned(glDrawElementsInstancedBaseVertexBaseInstance) then
    glDrawElementsInstancedBaseVertexBaseInstance(FCurrentPrimitiveMode,
      IndexCount, FCurrentIndexType, IndexPtr, InstanceCount, VertexOffset, FirstInstance)
  else if (VertexOffset <> 0) and (InstanceCount > 1) and Assigned(glDrawElementsInstancedBaseVertex) then
    glDrawElementsInstancedBaseVertex(FCurrentPrimitiveMode,
      IndexCount, FCurrentIndexType, IndexPtr, InstanceCount, VertexOffset)
  else if (VertexOffset <> 0) and (InstanceCount = 1) and Assigned(glDrawElementsBaseVertex) then
    glDrawElementsBaseVertex(FCurrentPrimitiveMode,
      IndexCount, FCurrentIndexType, IndexPtr, VertexOffset)
  else
  {$endif}
  if InstanceCount <= 1 then
    glDrawElements(FCurrentPrimitiveMode, IndexCount, FCurrentIndexType, IndexPtr)
  else
    glDrawElementsInstanced(FCurrentPrimitiveMode, IndexCount, FCurrentIndexType, IndexPtr, InstanceCount);
end;

procedure TOpenGLRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
var
  GLBuf: TOpenGLRHIBuffer;
  EffStride, I: Cardinal;
  CmdItem: TRHIDrawIndirectCommand;
begin
  if (IndirectBuffer = nil) or (DrawCount = 0) or (FCurrentPipeline = nil) then
    Exit;
  FCurrentPassHasCommands := True;

  Inc(FDrawCallCount);
  Inc(FIndirectDrawCallCount);
  if FDevice <> nil then
    Inc(FDevice.FIndirectDrawCallCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  GLBuf := IndirectBuffer as TOpenGLRHIBuffer;
  if Stride = 0 then
    EffStride := SizeOf(TRHIDrawIndirectCommand)
  else
    EffStride := Stride;

  glUseProgram(FCurrentPipeline.ProgramHandle);
  glBindVertexArray(FCurrentPipeline.VAOHandle);

  {$ifndef OpenGLES}
  if Assigned(glMultiDrawArraysIndirect) then
  begin
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLBuf.Handle);
    glMultiDrawArraysIndirect(FCurrentPrimitiveMode, Pointer(Offset), DrawCount, EffStride);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;

  if Assigned(glDrawArraysIndirect) then
  begin
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLBuf.Handle);
    for I := 0 to DrawCount - 1 do
      glDrawArraysIndirect(FCurrentPrimitiveMode,
        Pointer(Offset + PtrUInt(I) * PtrUInt(EffStride)));
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;
  {$endif}

  for I := 0 to DrawCount - 1 do
  begin
    FillChar(CmdItem, SizeOf(CmdItem), 0);
    GLBuf.ReadData(CmdItem, SizeOf(CmdItem), Offset + PtrUInt(I) * PtrUInt(EffStride));
    if (CmdItem.VertexCount > 0) and (CmdItem.InstanceCount > 0) then
      Draw(CmdItem.VertexCount, CmdItem.InstanceCount, CmdItem.FirstVertex, CmdItem.FirstInstance);
  end;
end;

procedure TOpenGLRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
var
  GLBuf: TOpenGLRHIBuffer;
  EffStride, I: Cardinal;
  CmdItem: TRHIDrawIndexedIndirectCommand;
begin
  if (IndirectBuffer = nil) or (DrawCount = 0) or (FCurrentPipeline = nil) then
    Exit;
  FCurrentPassHasCommands := True;

  Inc(FDrawCallCount);
  Inc(FIndirectDrawCallCount);
  if FDevice <> nil then
    Inc(FDevice.FIndirectDrawCallCount);

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
    Exit;

  GLBuf := IndirectBuffer as TOpenGLRHIBuffer;
  if Stride = 0 then
    EffStride := SizeOf(TRHIDrawIndexedIndirectCommand)
  else
    EffStride := Stride;

  glUseProgram(FCurrentPipeline.ProgramHandle);
  glBindVertexArray(FCurrentPipeline.VAOHandle);
  if FCurrentIndexBuffer <> nil then
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);

  {$ifndef OpenGLES}
  if (FCurrentIndexOffset = 0) and Assigned(glMultiDrawElementsIndirect) then
  begin
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLBuf.Handle);
    glMultiDrawElementsIndirect(FCurrentPrimitiveMode, FCurrentIndexType,
      Pointer(Offset), DrawCount, EffStride);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;

  if (FCurrentIndexOffset = 0) and Assigned(glDrawElementsIndirect) then
  begin
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLBuf.Handle);
    for I := 0 to DrawCount - 1 do
      glDrawElementsIndirect(FCurrentPrimitiveMode, FCurrentIndexType,
        Pointer(Offset + PtrUInt(I) * PtrUInt(EffStride)));
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;
  {$endif}

  for I := 0 to DrawCount - 1 do
  begin
    FillChar(CmdItem, SizeOf(CmdItem), 0);
    GLBuf.ReadData(CmdItem, SizeOf(CmdItem), Offset + PtrUInt(I) * PtrUInt(EffStride));
    if (CmdItem.IndexCount > 0) and (CmdItem.InstanceCount > 0) then
      DrawIndexed(CmdItem.IndexCount, CmdItem.InstanceCount,
        CmdItem.FirstIndex, CmdItem.VertexOffset, CmdItem.FirstInstance);
  end;
end;

procedure TOpenGLRHICommandList.DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  GLIndBuf, GLCountBuf: TOpenGLRHIBuffer;
  EffStride, ActualCount: Cardinal;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) or (MaxDrawCount = 0) or
     (FCurrentPipeline = nil) then
    Exit;

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
  begin
    Inc(FDrawCallCount);
    Inc(FIndirectDrawCallCount);
    if FDevice <> nil then
      Inc(FDevice.FIndirectDrawCallCount);
    Exit;
  end;

  GLIndBuf := IndirectBuffer as TOpenGLRHIBuffer;
  GLCountBuf := CountBuffer as TOpenGLRHIBuffer;
  if Stride = 0 then
    EffStride := SizeOf(TRHIDrawIndirectCommand)
  else
    EffStride := Stride;

  {$ifndef OpenGLES}
  if Assigned(glMultiDrawArraysIndirectCount) then
  begin
    Inc(FDrawCallCount);
    Inc(FIndirectDrawCallCount);
    if FDevice <> nil then
      Inc(FDevice.FIndirectDrawCallCount);

    glUseProgram(FCurrentPipeline.ProgramHandle);
    glBindVertexArray(FCurrentPipeline.VAOHandle);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLIndBuf.Handle);
    glBindBuffer(GL_PARAMETER_BUFFER, GLCountBuf.Handle);
    glMultiDrawArraysIndirectCount(FCurrentPrimitiveMode, Pointer(Offset),
      TGLintptr(CountBufferOffset), MaxDrawCount, EffStride);
    glBindBuffer(GL_PARAMETER_BUFFER, 0);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;
  {$endif}

  ActualCount := 0;
  GLCountBuf.ReadData(ActualCount, SizeOf(ActualCount), CountBufferOffset);
  ActualCount := Min(ActualCount, MaxDrawCount);
  if ActualCount > 0 then
    DrawIndirect(IndirectBuffer, Offset, ActualCount, EffStride);
end;

procedure TOpenGLRHICommandList.DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  GLIndBuf, GLCountBuf: TOpenGLRHIBuffer;
  EffStride, ActualCount: Cardinal;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) or (MaxDrawCount = 0) or
     (FCurrentPipeline = nil) then
    Exit;

  if (FDevice = nil) or (not FDevice.HasLiveGLContext) then
  begin
    Inc(FDrawCallCount);
    Inc(FIndirectDrawCallCount);
    if FDevice <> nil then
      Inc(FDevice.FIndirectDrawCallCount);
    Exit;
  end;

  GLIndBuf := IndirectBuffer as TOpenGLRHIBuffer;
  GLCountBuf := CountBuffer as TOpenGLRHIBuffer;
  if Stride = 0 then
    EffStride := SizeOf(TRHIDrawIndexedIndirectCommand)
  else
    EffStride := Stride;

  {$ifndef OpenGLES}
  if (FCurrentIndexOffset = 0) and Assigned(glMultiDrawElementsIndirectCount) then
  begin
    Inc(FDrawCallCount);
    Inc(FIndirectDrawCallCount);
    if FDevice <> nil then
      Inc(FDevice.FIndirectDrawCallCount);

    glUseProgram(FCurrentPipeline.ProgramHandle);
    glBindVertexArray(FCurrentPipeline.VAOHandle);
    if FCurrentIndexBuffer <> nil then
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FCurrentIndexBuffer.Handle);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, GLIndBuf.Handle);
    glBindBuffer(GL_PARAMETER_BUFFER, GLCountBuf.Handle);
    glMultiDrawElementsIndirectCount(FCurrentPrimitiveMode, FCurrentIndexType,
      Pointer(Offset), TGLintptr(CountBufferOffset), MaxDrawCount, EffStride);
    glBindBuffer(GL_PARAMETER_BUFFER, 0);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    Exit;
  end;
  {$endif}

  ActualCount := 0;
  GLCountBuf.ReadData(ActualCount, SizeOf(ActualCount), CountBufferOffset);
  ActualCount := Min(ActualCount, MaxDrawCount);
  if ActualCount > 0 then
    DrawIndexedIndirect(IndirectBuffer, Offset, ActualCount, EffStride);
end;

procedure TOpenGLRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
begin
  { On OpenGL, secondary command lists execute immediately on the GL context thread }
  if Length(SecondaryCommandLists) < 0 then ;
end;

procedure TOpenGLRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor);
var
  AnsiLabel: AnsiString;
begin
  Inc(FDebugGroupDepth);
  Inc(FDebugGroupPushCount);
  if (FDevice <> nil) and FDevice.HasLiveGLContext and (LabelName <> '') then
  begin
    {$ifndef OpenGLES}
    if Assigned(glPushDebugGroup) then
    begin
      AnsiLabel := AnsiString(LabelName);
      glPushDebugGroup(GL_DEBUG_SOURCE_APPLICATION, 0, Length(AnsiLabel), PGLchar(AnsiLabel));
    end;
    {$endif}
  end;
  if Color.X < -1e30 then ;
end;

procedure TOpenGLRHICommandList.PopDebugGroup;
begin
  if FDebugGroupDepth <= 0 then
    Exit;
  Dec(FDebugGroupDepth);
  if (FDevice <> nil) and FDevice.HasLiveGLContext then
  begin
    {$ifndef OpenGLES}
    if Assigned(glPopDebugGroup) then
      glPopDebugGroup();
    {$endif}
  end;
end;

procedure TOpenGLRHICommandList.InsertDebugMarker(const LabelName: String; const Color: TCastleColor);
var
  AnsiLabel: AnsiString;
begin
  Inc(FDebugMarkerCount);
  if (FDevice <> nil) and FDevice.HasLiveGLContext and (LabelName <> '') then
  begin
    {$ifndef OpenGLES}
    if Assigned(glDebugMessageInsert) then
    begin
      AnsiLabel := AnsiString(LabelName);
      glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION, GL_DEBUG_TYPE_MARKER,
        0, GL_DEBUG_SEVERITY_NOTIFICATION, Length(AnsiLabel), PGLchar(AnsiLabel));
    end;
    {$endif}
  end;
  if Color.X < -1e30 then ;
end;

{ ---------------------------------------------------------------------------- }
{ TOpenGLRHIDevice                                                             }
{ ---------------------------------------------------------------------------- }

constructor TOpenGLRHIDevice.Create(const InitialWidth, InitialHeight: Cardinal);
begin
  inherited Create;
  FHasLiveGLContext := (ApplicationProperties <> nil) and
    ApplicationProperties.IsGLContextOpen and (GLFeatures <> nil) and
    {$ifdef OpenGLES} GLFeatures.Version_3_0 {$else} GLFeatures.Version_3_0 {$endif} and
    Assigned(glGenFramebuffers) and Assigned(glDeleteFramebuffers);
  FPipelineMap := TOpenGLPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TOpenGLComputePipelineMap.Create([doOwnsValues]);
  FMaxImageUnits := 8;
  QueryDeviceCapabilities;

  if FHasLiveGLContext then
  begin
    glGenFramebuffers(1, @FReadbackFBO);
    glGenFramebuffers(1, @FReadbackResolveFBO);
  end;

  FCommandList := TOpenGLRHICommandList.Create(Self);
  FDefaultColorTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight),
      pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
  FDefaultDepthTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight),
      pfD24_UNorm_S8_UInt, [tuDepthStencil]));
end;

constructor TOpenGLRHIDevice.CreateHeadless(const InitialWidth, InitialHeight: Cardinal;
  const ASupportsCompute, ASupportsMultiDrawIndirect, ASupportsDrawIndirectCount: Boolean);
begin
  inherited Create;
  FHasLiveGLContext := False;
  FPipelineMap := TOpenGLPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TOpenGLComputePipelineMap.Create([doOwnsValues]);
  FMaxImageUnits := 8;

  {$ifdef OpenGLES}
  FCapabilities.Backend := rbOpenGLES;
  {$else}
  FCapabilities.Backend := rbOpenGL;
  {$endif}
  FCapabilities.DeviceName := 'Headless OpenGL 4.6 RHI Device';
  FCapabilities.MaxTextureSize := 16384;
  FCapabilities.MaxAnisotropy := 16.0;
  FCapabilities.MaxUniformBufferRange := 65536;
  FCapabilities.MinUniformBufferOffsetAlignment := 256;
  FCapabilities.MaxPushConstantsSize := 256;
  FCapabilities.MaxFramebufferSampleCount := 8;
  FCapabilities.SupportsBCCompression := True;
  FCapabilities.SupportsComputeShaders := ASupportsCompute;
  FCapabilities.SupportsMultiDrawIndirect := ASupportsMultiDrawIndirect;
  FCapabilities.SupportsDrawIndirectCount := ASupportsDrawIndirectCount;
  FCapabilities.SupportsExtendedDynamicState := True;
  FCapabilities.TimestampPeriodNanoseconds := 1.0;

  FCommandList := TOpenGLRHICommandList.Create(Self);
  FDefaultColorTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight),
      pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
  FDefaultDepthTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight),
      pfD24_UNorm_S8_UInt, [tuDepthStencil]));
end;

class function TOpenGLRHIDevice.TryCreateFromCurrentGLContext(out ADevice: TOpenGLRHIDevice;
  const InitialWidth, InitialHeight: Cardinal): Boolean;
begin
  ADevice := nil;
  if (ApplicationProperties = nil) or (not ApplicationProperties.IsGLContextOpen) or
     (GLFeatures = nil) then
    Exit(False);

  try
    ADevice := TOpenGLRHIDevice.Create(InitialWidth, InitialHeight);
    Result := ADevice.HasLiveGLContext;
    if not Result then
      FreeAndNil(ADevice);
  except
    on Exception do
    begin
      FreeAndNil(ADevice);
      Result := False;
    end;
  end;
end;

destructor TOpenGLRHIDevice.Destroy;
begin
  FreeAndNil(FComputePipelineMap);
  FreeAndNil(FPipelineMap);
  FreeAndNil(FDefaultColorTarget);
  FreeAndNil(FDefaultDepthTarget);
  FreeAndNil(FCommandList);
  ReleaseRemainingDeviceResources;
  if FHasLiveGLContext then
  begin
    if (FReadbackFBO <> 0) and Assigned(glDeleteFramebuffers) then
      glDeleteFramebuffers(1, @FReadbackFBO);
    if (FReadbackResolveFBO <> 0) and Assigned(glDeleteFramebuffers) then
      glDeleteFramebuffers(1, @FReadbackResolveFBO);
  end;
  inherited;
end;

procedure TOpenGLRHIDevice.QueryDeviceCapabilities;
var
  RendererPtr: PAnsiChar;
  IntVal: TGLint;
begin
  {$ifdef OpenGLES}
  FCapabilities.Backend := rbOpenGLES;
  {$else}
  FCapabilities.Backend := rbOpenGL;
  {$endif}
  FCapabilities.TimestampPeriodNanoseconds := 1.0;
  FCapabilities.MaxPushConstantsSize := 256;
  FCapabilities.SupportsExtendedDynamicState := True;

  if not FHasLiveGLContext then
  begin
    FCapabilities.DeviceName := 'Unbound OpenGL RHI Device';
    FCapabilities.MaxTextureSize := 4096;
    FCapabilities.MaxFramebufferSampleCount := 1;
    Exit;
  end;

  RendererPtr := PAnsiChar(glGetString(GL_RENDERER));
  if RendererPtr <> nil then
    FCapabilities.DeviceName := String(RendererPtr)
  else
    FCapabilities.DeviceName := 'OpenGL Renderer';

  FCapabilities.MaxTextureSize := GLFeatures.MaxTextureSize;
  FCapabilities.MaxAnisotropy := Max(1.0, GLFeatures.MaxTextureMaxAnisotropy);
  IntVal := 1;
  if GLFeatures.FBOMultiSampling then
    glGetIntegerv(GL_MAX_SAMPLES_RHI, @IntVal);
  FCapabilities.MaxFramebufferSampleCount := Max(1, IntVal);
  FCapabilities.SupportsBCCompression :=
    [tcDxt1_RGB, tcDxt1_RGBA, tcDxt3, tcDxt5] * GLFeatures.TextureCompression <> [];
  FCapabilities.SupportsASTCCompression := tcASTC_4x4_RGBA in GLFeatures.TextureCompression;
  FCapabilities.SupportsETC2Compression := tcETC1 in GLFeatures.TextureCompression;

  IntVal := 16384;
  if {$ifdef OpenGLES} GLFeatures.Version_3_0 {$else} GLFeatures.Version_3_1 {$endif} then
    glGetIntegerv(GL_MAX_UNIFORM_BLOCK_SIZE, @IntVal);
  FCapabilities.MaxUniformBufferRange := Max(16384, IntVal);

  IntVal := 256;
  if {$ifdef OpenGLES} GLFeatures.Version_3_0 {$else} GLFeatures.Version_3_1 {$endif} then
    glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, @IntVal);
  FCapabilities.MinUniformBufferOffsetAlignment := Max(1, IntVal);

  {$ifndef OpenGLES}
  FCapabilities.SupportsComputeShaders :=
    Assigned(glDispatchCompute) and Assigned(glBindImageTexture) and Assigned(glMemoryBarrier);
  FCapabilities.SupportsMultiDrawIndirect :=
    Assigned(glMultiDrawElementsIndirect) and Assigned(glMultiDrawArraysIndirect);
  FCapabilities.SupportsDrawIndirectCount :=
    Assigned(glMultiDrawElementsIndirectCount) and Assigned(glMultiDrawArraysIndirectCount);

  if FCapabilities.SupportsComputeShaders then
  begin
    IntVal := 8;
    glGetIntegerv(GL_MAX_IMAGE_UNITS, @IntVal);
    FMaxImageUnits := Max(1, IntVal);
  end;
  {$else}
  FCapabilities.SupportsComputeShaders := False;
  FCapabilities.SupportsMultiDrawIndirect := False;
  FCapabilities.SupportsDrawIndirectCount := False;
  {$endif}
end;

function TOpenGLRHIDevice.GetPipelineCount: Integer;
begin
  if FPipelineMap <> nil then
    Result := FPipelineMap.Count
  else
    Result := 0;
end;

function TOpenGLRHIDevice.GetComputePipelineCount: Integer;
begin
  if FComputePipelineMap <> nil then
    Result := FComputePipelineMap.Count
  else
    Result := 0;
end;

function TOpenGLRHIDevice.BeginFrame: TRHICommandList;
begin
  Inc(FTotalFramesStarted);
  FCommandList.BeginRecording;
  Result := FCommandList;
  SetActiveCommandList(Result);
end;

procedure TOpenGLRHIDevice.EndFrameAndPresent;
begin
  FCommandList.EndRecording;
  SetActiveCommandList(nil);
  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
end;

function TOpenGLRHIDevice.BeginOffscreenFrame: TRHICommandList;
begin
  Inc(FTotalFramesStarted);
  FCommandList.BeginRecording;
  Result := FCommandList;
  SetActiveCommandList(Result);
end;

procedure TOpenGLRHIDevice.EndOffscreenFrame;
begin
  FCommandList.EndRecording;
  SetActiveCommandList(nil);
end;

procedure TOpenGLRHIDevice.ResizeSwapchain(const NewWidth, NewHeight: Cardinal);
begin
  FreeAndNil(FDefaultColorTarget);
  FreeAndNil(FDefaultDepthTarget);
  FDefaultColorTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), NewWidth), Max(Cardinal(1), NewHeight),
      pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
  FDefaultDepthTarget := TOpenGLRHITexture.CreateDefaultBackbufferWrapper(Self,
    TRHITextureDesc.Create2D(Max(Cardinal(1), NewWidth), Max(Cardinal(1), NewHeight),
      pfD24_UNorm_S8_UInt, [tuDepthStencil]));
end;

procedure TOpenGLRHIDevice.WaitIdle;
begin
  if FHasLiveGLContext then
    glFinish;
end;

function TOpenGLRHIDevice.CreateSecondaryCommandList: TRHICommandList;
begin
  Result := TOpenGLRHICommandList.Create(Self, cllSecondary);
end;

function TOpenGLRHIDevice.GetSwapchainColorTexture: TRHITexture;
begin
  Result := FDefaultColorTarget;
end;

function TOpenGLRHIDevice.GetSwapchainDepthTexture: TRHITexture;
begin
  Result := FDefaultDepthTarget;
end;

function TOpenGLRHIDevice.CreateBuffer(const ADesc: TRHIBufferDesc;
  const InitialData: Pointer): TRHIBuffer;
begin
  Result := TOpenGLRHIBuffer.Create(Self, ADesc, InitialData);
end;

function TOpenGLRHIDevice.CreateTexture(const ADesc: TRHITextureDesc): TRHITexture;
begin
  Result := TOpenGLRHITexture.Create(Self, ADesc);
end;

function TOpenGLRHIDevice.CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler;
begin
  Result := TOpenGLRHISampler.Create(Self, ADesc);
end;

function TOpenGLRHIDevice.CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): TRHIShaderModule;
begin
  Result := TOpenGLRHIShaderModule.Create(Self, AStage, AGLSLSource, ADebugName);
end;

function TOpenGLRHIDevice.CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
  const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
  const ADebugName: String): TRHIShaderModule;
begin
  Result := nil;
  if (ASPIRVBinary = nil) and (ASizeInBytes = 0) and (AStage = ssCompute) and (ADebugName = '') then ;
  raise ERHIError.Create('SPIR-V binary loading is only used by the Vulkan backend; pass GLSL source to OpenGL.');
end;

function TOpenGLRHIDevice.CreateDescriptorSetLayout(
  const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout;
begin
  Result := TOpenGLRHIDescriptorSetLayout.Create(Self, Bindings);
end;

function TOpenGLRHIDevice.CreateDescriptorSet(
  const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;
begin
  Result := TOpenGLRHIDescriptorSet.Create(Self, Layout as TOpenGLRHIDescriptorSetLayout);
end;

function TOpenGLRHIDevice.ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.VertexShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.FragmentShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.GeometryShader));
  HashBytesFNV1a(Result, ADesc.Topology, SizeOf(ADesc.Topology));
  HashBytesFNV1a(Result, ADesc.Rasterizer, SizeOf(ADesc.Rasterizer));
  HashBytesFNV1a(Result, ADesc.DepthStencil, SizeOf(ADesc.DepthStencil));
  HashBytesFNV1a(Result, ADesc.BlendState, SizeOf(ADesc.BlendState));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.SampleCount, SizeOf(ADesc.SampleCount));

  for I := 0 to High(ADesc.VertexInput.Bindings) do
    HashBytesFNV1a(Result, ADesc.VertexInput.Bindings[I], SizeOf(TRHIVertexBindingDesc));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Location, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Binding, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Format, SizeOf(TRHIVertexAttributeFormat));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Offset, SizeOf(Cardinal));
    HashStringFNV1a(Result, ADesc.VertexInput.Attributes[I].AttributeName);
  end;
end;

function TOpenGLRHIDevice.ComputeComputePipelineHash(const ADesc: TRHIComputePipelineDesc): UInt64;
var
  I: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.ComputeShader));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    HashUInt64FNV1a(Result, PtrUInt(ADesc.DescriptorSetLayouts[I]));
end;

function TOpenGLRHIDevice.GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline;
var
  HashKey: UInt64;
  FoundPipeline: TOpenGLRHIPipeline;
begin
  HashKey := ComputePipelineHash(ADesc);
  if FPipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FPipelineCacheHits);
    FoundPipeline.UpdateDynamicStateDesc(ADesc);
  end else
  begin
    Inc(FPipelineCacheMisses);
    FoundPipeline := TOpenGLRHIPipeline.Create(Self, ADesc);
    FPipelineMap.Add(HashKey, FoundPipeline);
  end;
  Result := FoundPipeline;
end;

function TOpenGLRHIDevice.GetOrCreateComputePipeline(
  const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
var
  HashKey: UInt64;
  FoundPipeline: TOpenGLRHIComputePipeline;
begin
  HashKey := ComputeComputePipelineHash(ADesc);
  if (FComputePipelineMap <> nil) and FComputePipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FComputePipelineCacheHits);
  end else
  begin
    Inc(FComputePipelineCacheMisses);
    FoundPipeline := TOpenGLRHIComputePipeline.Create(Self, ADesc);
    if FComputePipelineMap <> nil then
      FComputePipelineMap.Add(HashKey, FoundPipeline);
  end;
  Result := FoundPipeline;
end;

function TOpenGLRHIDevice.CreateComputePipeline(
  const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
begin
  Result := TOpenGLRHIComputePipeline.Create(Self, ADesc);
end;

function TOpenGLRHIDevice.CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool;
begin
  Result := TOpenGLRHIQueryPool.Create(Self, ADesc);
end;

function TOpenGLRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaImage;
var
  GLTex: TOpenGLRHITexture;
  PrevReadFBO, PrevDrawFBO: TGLint;
  TempResolveTex: TGLuint;
  FloatBuf: array of Single;
  PIdx, TotalPixels: PtrUInt;
  DstBytes: PByte;
  SrcW, SrcH: Integer;

  function Float01ToByte(const V: Single): Byte; inline;
  begin
    Result := Byte(Round(EnsureRange(V, 0.0, 1.0) * 255.0));
  end;

begin
  if (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  Result := TRGBAlphaImage.Create(ReadArea.Width, ReadArea.Height);

  if not FHasLiveGLContext then
  begin
    if (SourceTexture is TOpenGLRHITexture) and
       (Length(TOpenGLRHITexture(SourceTexture).FHostPixels) >=
        PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height) * 4) then
      Move(TOpenGLRHITexture(SourceTexture).FHostPixels[0], Result.RawPixels^,
        PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height) * 4);
    Exit;
  end;

  if (SourceTexture = nil) or (SourceTexture as TOpenGLRHITexture).IsDefaultBackbuffer then
  begin
    PrevReadFBO := 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, @PrevReadFBO);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    {$ifndef OpenGLES}
    glReadBuffer(GL_BACK);
    {$endif}
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
      GL_RGBA, GL_UNSIGNED_BYTE, Result.RawPixels);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, TGLuint(PrevReadFBO));
    Exit;
  end;

  GLTex := SourceTexture as TOpenGLRHITexture;
  PrevReadFBO := 0;
  PrevDrawFBO := 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, @PrevReadFBO);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, @PrevDrawFBO);
  TempResolveTex := 0;
  try
    {$ifndef OpenGLES}
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(GL_FRAMEBUFFER_BARRIER_BIT or GL_TEXTURE_UPDATE_BARRIER_BIT or
        GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
    {$endif}

    glPixelStorei(GL_PACK_ALIGNMENT, 1);

    if GLTex.Desc.Format in [pfD16_UNorm, pfD24_UNorm_S8_UInt, pfD32_Float, pfD32_Float_S8_UInt] then
    begin
      glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackFBO);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GLTex.Target, GLTex.Handle, 0);
      TotalPixels := PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height);
      SetLength(FloatBuf, TotalPixels);
      glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
        GL_DEPTH_COMPONENT, GL_FLOAT, @FloatBuf[0]);
      DstBytes := PByte(Result.RawPixels);
      for PIdx := 0 to TotalPixels - 1 do
      begin
        DstBytes[PIdx * 4 + 0] := Float01ToByte(FloatBuf[PIdx]);
        DstBytes[PIdx * 4 + 1] := DstBytes[PIdx * 4 + 0];
        DstBytes[PIdx * 4 + 2] := DstBytes[PIdx * 4 + 0];
        DstBytes[PIdx * 4 + 3] := 255;
      end;
    end else
    if GLTex.Desc.SampleCount > 1 then
    begin
      SrcW := Max(1, Integer(GLTex.Desc.Width));
      SrcH := Max(1, Integer(GLTex.Desc.Height));
      glGenTextures(1, @TempResolveTex);
      glBindTexture(GL_TEXTURE_2D, TempResolveTex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, SrcW, SrcH, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
      glBindTexture(GL_TEXTURE_2D, 0);

      glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackFBO);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GLTex.Target, GLTex.Handle, 0);

      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, FReadbackResolveFBO);
      glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, TempResolveTex, 0);

      glBlitFramebuffer(0, 0, SrcW, SrcH, 0, 0, SrcW, SrcH, GL_COLOR_BUFFER_BIT, GL_NEAREST);

      glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackResolveFBO);
      {$ifndef OpenGLES}
      glReadBuffer(GL_COLOR_ATTACHMENT0);
      {$endif}
      glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
        GL_RGBA, GL_UNSIGNED_BYTE, Result.RawPixels);
    end else
    begin
      glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackFBO);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
      if GLTex.Desc.Dimension = tdCube then
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
          GL_TEXTURE_CUBE_MAP_POSITIVE_X, GLTex.Handle, 0)
      else if GLTex.Desc.Dimension in [td2DArray, td3D] then
        glFramebufferTextureLayer(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GLTex.Handle, 0, 0)
      else
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GLTex.Target, GLTex.Handle, 0);
      {$ifndef OpenGLES}
      glReadBuffer(GL_COLOR_ATTACHMENT0);
      {$endif}
      glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
        GL_RGBA, GL_UNSIGNED_BYTE, Result.RawPixels);
    end;
  finally
    if TempResolveTex <> 0 then
      glDeleteTextures(1, @TempResolveTex);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, TGLuint(PrevReadFBO));
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, TGLuint(PrevDrawFBO));
  end;
end;

function TOpenGLRHIDevice.GrabTextureSubresourceImage(const SourceTexture: TRHITexture;
  const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage;
var
  GLTex: TOpenGLRHITexture;
  MipW, MipH: Cardinal;
  PrevReadFBO: TGLint;
begin
  if SourceTexture = nil then
    Exit(nil);

  MipW := Max(Cardinal(1), SourceTexture.Desc.Width shr AMipLevel);
  MipH := Max(Cardinal(1), SourceTexture.Desc.Height shr AMipLevel);

  if (not FHasLiveGLContext) or (SourceTexture as TOpenGLRHITexture).IsDefaultBackbuffer then
    Exit(GrabTextureImage(SourceTexture, Rectangle(0, 0, Integer(MipW), Integer(MipH))));

  GLTex := SourceTexture as TOpenGLRHITexture;
  Result := TRGBAlphaImage.Create(MipW, MipH);
  PrevReadFBO := 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, @PrevReadFBO);
  try
    {$ifndef OpenGLES}
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(GL_FRAMEBUFFER_BARRIER_BIT or GL_TEXTURE_UPDATE_BARRIER_BIT or
        GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
    {$endif}
    glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackFBO);
    glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
    if GLTex.Desc.Dimension = tdCube then
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_CUBE_MAP_POSITIVE_X + Min(Cardinal(5), AArrayLayer),
        GLTex.Handle, AMipLevel)
    else if GLTex.Desc.Dimension in [td2DArray, td3D] then
      glFramebufferTextureLayer(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GLTex.Handle, AMipLevel, AArrayLayer)
    else
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GLTex.Target, GLTex.Handle, AMipLevel);
    {$ifndef OpenGLES}
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    {$endif}
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, Integer(MipW), Integer(MipH),
      GL_RGBA, GL_UNSIGNED_BYTE, Result.RawPixels);
  finally
    glBindFramebuffer(GL_READ_FRAMEBUFFER, TGLuint(PrevReadFBO));
  end;
end;

function TOpenGLRHIDevice.GrabTextureFloatImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaFloatImage;
var
  GLTex: TOpenGLRHITexture;
  PrevReadFBO: TGLint;
  DepthBuf: array of Single;
  PIdx, TotalPixels: PtrUInt;
  DstVec4: PVector4;
begin
  if (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  if (not FHasLiveGLContext) or (SourceTexture = nil) or
     (SourceTexture as TOpenGLRHITexture).IsDefaultBackbuffer then
    Exit(inherited GrabTextureFloatImage(SourceTexture, ReadArea));

  GLTex := SourceTexture as TOpenGLRHITexture;
  Result := TRGBAlphaFloatImage.Create(ReadArea.Width, ReadArea.Height);
  PrevReadFBO := 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, @PrevReadFBO);
  try
    {$ifndef OpenGLES}
    if Assigned(glMemoryBarrier) then
      glMemoryBarrier(GL_FRAMEBUFFER_BARRIER_BIT or GL_TEXTURE_UPDATE_BARRIER_BIT or
        GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
    {$endif}
    glBindFramebuffer(GL_READ_FRAMEBUFFER, FReadbackFBO);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);

    if GLTex.Desc.Format in [pfD16_UNorm, pfD24_UNorm_S8_UInt, pfD32_Float, pfD32_Float_S8_UInt] then
    begin
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GLTex.Target, GLTex.Handle, 0);
      TotalPixels := PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height);
      SetLength(DepthBuf, TotalPixels);
      glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
        GL_DEPTH_COMPONENT, GL_FLOAT, @DepthBuf[0]);
      DstVec4 := Result.Pixels;
      for PIdx := 0 to TotalPixels - 1 do
        DstVec4[PIdx] := Vector4(DepthBuf[PIdx], DepthBuf[PIdx], DepthBuf[PIdx], 1.0);
    end else
    begin
      glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
      if GLTex.Desc.Dimension = tdCube then
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
          GL_TEXTURE_CUBE_MAP_POSITIVE_X, GLTex.Handle, 0)
      else if GLTex.Desc.Dimension in [td2DArray, td3D] then
        glFramebufferTextureLayer(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GLTex.Handle, 0, 0)
      else
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GLTex.Target, GLTex.Handle, 0);
      {$ifndef OpenGLES}
      glReadBuffer(GL_COLOR_ATTACHMENT0);
      {$endif}
      glReadPixels(ReadArea.Left, ReadArea.Bottom, ReadArea.Width, ReadArea.Height,
        GL_RGBA, GL_FLOAT, Result.RawPixels);
    end;
  finally
    glBindFramebuffer(GL_READ_FRAMEBUFFER, TGLuint(PrevReadFBO));
  end;
end;

procedure TOpenGLRHIDevice.LoadPipelineCache(const CacheFileUrl: String);
begin
  if CacheFileUrl = '' then ;
end;

procedure TOpenGLRHIDevice.SavePipelineCache(const CacheFileUrl: String);
begin
  if CacheFileUrl = '' then ;
end;

{$endif read_implementation}

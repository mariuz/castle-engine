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

{ OpenGL 3.3–4.6 and OpenGL ES 3.0–3.2 implementation of CastleInternalRHI.
  Wraps Castle Game Engine's OpenGL/OpenGLES context and translates explicit RHI
  Graphics & Compute Pipelines, UBO/SSBO/Sampler/Storage-Image Descriptor Sets,
  Indirect Multi-Draw (including Indirect-Count), Hardware Query Pools
  (Timestamps & Occlusion), and TRHIRenderGraph passes into OpenGL execution,
  alongside a deterministic headless simulation mode for context-free unit tests. }
unit CastleInternalRHI_OpenGL;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  {$ifdef OpenGLES} CastleGLES, {$else} CastleGL, {$endif}
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleLog,
  CastleGLUtils, CastleGLImages, CastleRenderOptions, CastleApplicationProperties,
  CastleTextureImages,
  CastleInternalRHI;

const
  { Stride between Descriptor Set indices in OpenGL binding slots
    (Set 0 = 0..7, Set 1 = 8..15, Set 2 = 16..23) }
  GL_DESCRIPTOR_SET_SLOT_STRIDE = 8;
  { Reserved Uniform Buffer binding slot for emulating Vulkan Push Constants in OpenGL }
  GL_PUSH_CONSTANT_UBO_BINDING  = 24;

type
  TOpenGLRHIDevice = class;
  TOpenGLRHICommandList = class;

{$define read_interface}
{$I castleinternalrhi_opengl_resources.inc}
{$undef read_interface}

implementation

uses
  StrUtils, CastleStringUtils;

{$define read_implementation}
{$I castleinternalrhi_opengl_translator.inc}
{$I castleinternalrhi_opengl_resources.inc}
{$I castleinternalrhi_opengl_commands_device.inc}
{$undef read_implementation}

end.

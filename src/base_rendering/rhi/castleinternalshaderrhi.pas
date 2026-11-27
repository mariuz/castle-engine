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

{ Upgrade extension for CastleRendererInternalShader to emit Vulkan GLSL 450
  (UBOs, Push Constants, explicit stage locations) alongside OpenGL/OpenGLES. }
unit CastleInternalShaderRHI;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, StrUtils, Math, Generics.Collections,
  CastleVectors, CastleColors, CastleStringUtils, CastleLog,
  CastleInternalRHI;

{$define read_interface}
{$I castleinternalshaderrhi_types.inc}
{$undef read_interface}

implementation

{$define read_implementation}
{$I castleinternalshaderrhi_core_upgrade.inc}
{$I castleinternalshaderrhi_lighting_post.inc}
{$I castleinternalshaderrhi_nextgen.inc}
{$undef read_implementation}

end.

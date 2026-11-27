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

{ Abstract Render Hardware Interface (RHI) for Castle Game Engine.
  Provides an explicit, low-overhead rendering abstraction capable of driving
  both modern explicit APIs (Vulkan) and state-machine APIs (OpenGL / OpenGLES). }
unit CastleInternalRHI;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleRenderOptions;

{$define read_interface}
{$I castleinternalrhi_types_classes.inc}
{$undef read_interface}

implementation

{$define read_implementation}
{$I castleinternalrhi_core_impl.inc}
{$I castleinternalrhi_rendergraph.inc}
{$undef read_implementation}

end.

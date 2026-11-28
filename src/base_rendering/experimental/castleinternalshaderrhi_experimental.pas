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

{ Opt-in experimental & research GLSL 450 shader generators and CPU reference
  evaluators (Unreal Engine 5 Lumen/Nanite/VSM/ReSTIR/TSR/Substrate, RTX SVGF/SER,
  3D Gaussian Splatting, XPBD cloth, atmospheric/ocean/material research lobes).
  Zero core Castle Game Engine units depend on this unit; add it to your uses
  clause only when experimenting with these research subsystems. }
unit CastleInternalShaderRHI_Experimental;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, StrUtils, Math, Generics.Collections,
  CastleVectors, CastleColors, CastleStringUtils, CastleLog,
  CastleInternalRHI, CastleInternalShaderRHI;

{$define read_interface}
{$I castleinternalshaderrhi_experimental_types.inc}
{$undef read_interface}

implementation

const
  NL = LineEnding;

{$define read_implementation}
{$I castleinternalshaderrhi_experimental_pbr_env.inc}
{$I castleinternalshaderrhi_experimental_nextgen.inc}
{$undef read_implementation}

end.

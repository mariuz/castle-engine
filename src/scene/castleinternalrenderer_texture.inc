{%MainUnit castleinternalrenderer.pas}
{
  Copyright 2002-2025 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_interface}

  { }
  TTextureResource = class;

  TTextureResourceClass = class of TTextureResource;

  { OpenGL resource of a texture node. }
  TTextureResource = class(TRendererResource)
  protected
    { Calculate things from TextureProperties node.
      If TextureProperties = @nil, they are taken from defaults
      (possibly in RenderOptions) and BoundaryModeS/-T are taken
      from repeatS and repeatT fields.
      @groupBegin }
    procedure HandleTextureProperties(
      const TextureProperties: TTexturePropertiesNode;
      const RenderOptions: TCastleRenderOptions;
      const RepeatS, RepeatT, RepeatR: TGLenum;
      out Filter: TTextureFilter;
      out BoundaryModeS, BoundaryModeT, BoundaryModeR: TGLenum;
      out Anisotropy: TGLfloat;
      out GUITexture: boolean); overload;

    procedure HandleTextureProperties(
      const TextureProperties: TTexturePropertiesNode;
      const RenderOptions: TCastleRenderOptions;
      const RepeatS, RepeatT: TGLenum;
      out Filter: TTextureFilter;
      out BoundaryModeS, BoundaryModeT: TGLenum;
      out Anisotropy: TGLfloat;
      out GUITexture: boolean); overload;

    procedure HandleTextureProperties(
      const TextureProperties: TTexturePropertiesNode;
      const RenderOptions: TCastleRenderOptions;
      out Filter: TTextureFilter;
      out Anisotropy: TGLfloat;
      out GUITexture: boolean); overload;
    { @groupEnd }

    { Decide if this class can handle given texture Node. }
    class function IsClassForTextureNode(
      ANode: TAbstractTextureNode): boolean; virtual; abstract;
  public
    { ANode must be TAbstractTextureNode }
    constructor Create(const ANode: TX3DNode); override;

    { Reference to handled texture node.
      Never @nil.
      It's guaranteed to satisfy IsClassForTextureNode method of this class. }
    function TextureNode: TAbstractTextureNode;

    { Find suitable TTextureResource class that can best handle given Node.
      Returns @nil if not found.

      @italic(Descedants implementors): override IsClassForTextureNode
      to be correctly recognized by this. }
    class function ClassForTextureNode(
      ANode: TAbstractTextureNode): TTextureResourceClass;
  public
    { Bind texture for OpenGL (without enabling it).

      Just like Enable, returns @false when texture node was not successfully
      prepared for OpenGL. Returns @true when it was successfully bound
      (caller can be sure then that given texture unit is currently active). }
    function Bind(const TextureUnit: Cardinal): boolean; virtual; abstract;

    { Enables texture for OpenGL. This has to bind texture identifier
      and enable proper texture state (for example:
      2D, and not 3D, and not cube).

      When returns @false, it means that texture node was not successfully
      prepared for OpenGL, which means (we assume that you called Prepare
      before Enable) that texture failed to load, required not available
      OpenGL version / extension etc. Caller will then disable
      the texture unit, and you don't have to generate tex coords for it.

      When returns @true (success) caller can be sure that the specified
      TextureUnit is currently bound (if OpenGL multitexturing
      extensions are available at all). This is useful, if you want
      to later adjust texture unit parameters, like
      glTexEnvi(GL_TEXTURE_ENV, ...).

      It's also already enabled (by glEnable(GL_TEXTURE_2D /
      GL_TEXTURE_CUBE_MAP / GL_TEXTURE_3D) ). }
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; virtual; abstract;

    { Sets texture state for many texture units, based on this node.
      On every texture unit where something is enabled,
      proper texture identifier must be bound.
      Also, has to set complete glTexEnv on every enabled texture unit.

      TextureUnitsCount says how many texture units can be enabled/disabled.

      TextureUnitsCount does *not* take into account whether multitexturing
      OpenGL extensions are available at all.
      Look at GLFeatures.UseMultiTexturing for this.
      Think of GLFeatures.UseMultiTexturing as capping TextureUnitsCount to 1
      (still, remember to honour TextureUnitsCount = 0 case in your implementation,
      even when GLFeatures.UseMultiTexturing = @true).

      You have to update TextureSlotsUsed, this is the count of texture units
      where some texture coordinates should be generated.
      It's initial value may be > 0, in case some texture slots are already taken.
      This means that all texture units above TextureSlotsUsed
      (to TextureUnitsCount - 1) should be disabled by the caller (no need to
      do this in EnableAll),
      and there's no need to generated texture coords for them.

      (
      Yes, there is some small optimization missed in the definition
      of TextureSlotsUsed: if some textures in the middle of
      multitexture children list failed to load, but some following children
      succeded, we'll generate tex coords even for the useless texture units
      in the middle. We could avoid generating texture coords for them,
      by changing TextureSlotsUsed into bool array.
      This optimization is not considered worthy implementing for now.
      )

      You have to set texture state of all texture units < TextureSlotsUsed,
      and only on them. }
    procedure EnableAll(
      const Renderer: TRenderer;
      const TextureUnitsCount: Cardinal;
      var TextureSlotsUsed: Cardinal;
      const Shader: TShader;
      const HasPreviousMainTexture: Boolean); virtual; abstract;

    { How to query this texture type from shaders.
      @false if this texture type is not supported by simple query in shaders. }
    function ShaderTextureType(out TextureType: TTextureType): Boolean; virtual;
  end;

  { Manage TTextureResource connected to X3D nodes.

    Non-instantiable class (has only class methods).

    This should be the only code accessing
    TAbstractTextureNode.InternalRendererResource field,
    everything else should go through this class. }
  TTextureResources = class abstract
  public
    { Renderer resource for given ANode.
      Allows ANode = @nil.
      Returns @nil if not found or ANode is @nil. }
    class function Get(const ANode: TAbstractTextureNode): TTextureResource;

    { Prepare renderer resources for given texture node,
      uploading texture to OpenGL if necessary.
      Accepts all texture nodes, multi texture or not-multi texture nodes.
      Accepts also (and ignores) @nil as ANode. }
    class procedure Prepare(
      const RenderOptions: TCastleRenderOptions;
      const ANode: TAbstractTextureNode);

    { Release OpenGL resources for given texture node.
      Consistently with @link(Prepare), accepts and ignores @nil as ANode. }
    class procedure Unprepare(const ANode: TAbstractTextureNode);

    { Bind texture node. Calls TTextureResource.Bind method.
      If no texture renderer is prepared for this node, returns @false. }
    class function Bind(ANode: TAbstractTextureNode;
      const TextureUnit: Cardinal): boolean;

    { Enable and bind texture node. Calls TTextureResource.Enable method.
      If no texture renderer is prepared for this node, returns @false. }
    class function Enable(ANode: TAbstractTextureNode;
      const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean;
  end;

  { Common class for all single (not multi-texture) texture nodes.

    Implements EnableAll method, by calling @link(Enable) call.
    Override only @link(Enable) in descendants. }
  TSingleTextureResource = class(TTextureResource)
  public
    procedure EnableAll(const Renderer: TRenderer;
      const TextureUnitsCount: Cardinal;
      var TextureSlotsUsed: Cardinal;
      const Shader: TShader;
      const HasPreviousMainTexture: Boolean); override;
  end;

  { Renderer resource for TMultiTextureNode.

    In EnableAll, this uses other TTextureResource (of children)
    to enable them too. You don't need to worry about it from the outside,
    just use EnableAll. }
  TMultiTextureResource = class(TTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    { ANode must be TMultiTextureNode }
    constructor Create(const ANode: TX3DNode); override;

    function TextureNode: TMultiTextureNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    procedure EnableAll(const Renderer: TRenderer;
      const TextureUnitsCount: Cardinal;
      var TextureSlotsUsed: Cardinal;
      const Shader: TShader;
      const HasPreviousMainTexture: Boolean); override;
  end;

  { Renderer resource for a 2D texture. }
  T2DTextureResource = class(TSingleTextureResource)
  public
    { OpenGL texture identifier.
      It may be 0 if the texture was initialized successfully. }
    function GLName: TGLTextureId; virtual; abstract;
  end;

  { Renderer resource for 2D texture with static image (not a video). }
  TImageTextureResource = class(T2DTextureResource)
  strict private
    FGLName: TGLTexture;
    FAllocatedWidth, FAllocatedHeight: Cardinal;
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    NormalMap, HeightMap: TGLTexture;
    HeightMapScale: Single;

    const
      MyTextureType = tt2D;

    function TextureNode: TAbstractTexture2DNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
    function GLName: TGLTextureId; override;

    procedure UpdateTextureContentsRgbaFloat(
      const Width, Height: Cardinal; const Data: Pointer); override;
  end;

  { Renderer resource for TMovieTextureNode. }
  TMovieTextureResource = class(T2DTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    GLVideo: TGLVideo3D;

    const
      MyTextureType = tt2D;

    function TextureNode: TMovieTextureNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
    function GLName: TGLTextureId; override;
  end;

  { Renderer resource for TRenderedTextureNode. }
  TRenderedTextureResource = class(T2DTextureResource)
  strict private
    FGLName: TGLTexture;
    RenderToTexture: TGLRenderToTexture;
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    { The actual decided image size and mipmap status. }
    Width, Height: Cardinal;
    NeedsMipmaps: boolean;

    const
      MyTextureType = tt2D;

    function TextureNode: TRenderedTextureNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
    function GLName: TGLTextureId; override;

    procedure Update(
      const Render: TRenderFromViewFunction;
      const ProjectionNear, ProjectionFar: Single;
      const CurrentViewpoint: TAbstractViewpointNode;
      const CameraViewKnown: boolean;
      const CameraView: TViewVectors;
      const ShapeForViewpointMirror: TX3DRendererShape);
  end;

  { Renderer resource for TScreenTextureNode.
    All ScreenTexture nodes show the same colors (the current viewport),
    so they all bind the same OpenGL texture,
    updated once by UpdateScreenTextures. }
  TScreenTextureResource = class(T2DTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    const
      MyTextureType = tt2D;

    function TextureNode: TScreenTextureNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
    function GLName: TGLTextureId; override;
  end;

  { Abstract renderer resource for TAbstractEnvironmentTextureNode. }
  TCubeMapTextureResource = class(TSingleTextureResource)
  protected
    { Releases GLName by TextureCubeMap_DecReference.
      Suitable for descendants tht initialize GLName by
      TextureCubeMap_IncReference. }
    procedure UnprepareCore; override;
  public
    GLName: TGLTexture;

    const
      MyTextureType = ttCubeMap;

    function TextureNode: TAbstractEnvironmentTextureNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
  end;

  { Renderer resource for TComposedCubeMapTextureNode. }
  TComposedCubeMapTextureResource = class(TCubeMapTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
  public
    function TextureNode: TComposedCubeMapTextureNode;
  end;

  { Renderer resource for TImageCubeMapTextureNode. }
  TImageCubeMapTextureResource = class(TCubeMapTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
  public
    function TextureNode: TImageCubeMapTextureNode;
  end;

  { Renderer resource for TGeneratedCubeMapTextureNode. }
  TGeneratedCubeMapTextureResource = class(TCubeMapTextureResource)
  private
    RenderToTexture: TGLRenderToTexture;
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    { The right size of the texture,
      that satisfies all OpenGL cube map sizes requirements
      (IsCubeMapTextureSized). }
    Size: Cardinal;

    { Does Filter need mipmaps. }
    NeedsMipmaps: boolean;

    function TextureNode: TGeneratedCubeMapTextureNode;

    procedure Update(
      const Render: TRenderFromViewFunction;
      const ProjectionNear, ProjectionFar: Single;
      const CubeMiddle: TVector3);
  end;

  { Renderer resource for TAbstractTexture3DNode. }
  T3DTextureResource = class(TSingleTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    GLName: TGLTexture;

    const
      MyTextureType = tt3D;

    function TextureNode: TAbstractTexture3DNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
  end;

  { Depth texture holding the views (tiles) of many shadow maps,
    see ShadowMapsAtlasSize. Tiles are squares with power of 2 sizes,
    allocated by splitting the texture into quarters (a quadtree). }
  TShadowMapAtlas = class
  strict private
    type
      TRectangleList = {$ifdef FPC}specialize{$endif} TStructList<TRectangle>;
    var
      { Free blocks by level: level 0 is the whole texture,
        each next level has blocks 2x smaller. }
      FreeBlocks: array of TRectangleList;
    function BlockLevel(const BlockSize: Cardinal): Integer;
    function FindFree(const Level: Integer; const R: TRectangle): Integer;
  public
    const
      MinBlockSize = 16;
    var
      Size: Cardinal;
      GLName: TGLTexture;
      RenderToTexture: TGLRenderToTexture;
      { Number of TGeneratedShadowMapResource using this. }
      UserCount: Integer;
    constructor Create(const ASize: Cardinal);
    destructor Destroy; override;
    { Allocate a square of BlockSize (power of 2, >= MinBlockSize). }
    function Allocate(const BlockSize: Cardinal; out Rect: TRectangle): Boolean;
    procedure Release(const Rect: TRectangle);
  end;

  { Renderer resource for TGeneratedShadowMapNode.

    The shadow map has one or more views (tiles), see ShadowMapKind:
    1 for a spot light or a directional light, 6 for a point light,
    the cascades of a directional light with shadowCascades > 1.
    They are squares in the shared TShadowMapAtlas,
    or (for variance shadow maps, or when ShadowMapsAtlasSize = 0)
    in a texture of this shadow map. }
  TGeneratedShadowMapResource = class(T2DTextureResource)
  strict private
    RenderToTexture: TGLRenderToTexture;
    { VarianceShadowMaps calculated at the PrepareCore time. }
    VarianceShadowMaps: boolean;
    NeedsMipmaps: boolean;
    { Own texture, when not InAtlas. }
    FGLName: TGLTexture;
    TextureWrap: TTextureWrap2D;
    Filter: TTextureFilter;
    WarninigDoneCannotEnable: Boolean;
    { Tiles are in the shared ShadowMapAtlas. }
    InAtlas: Boolean;
    { Allocated tiles: their count and size, and (InAtlas) rectangles. }
    TileCount: Integer;
    TileSize: Cardinal;
    AtlasRects: array of TRectangle;
    { Size of the texture with the tiles. }
    TextureWidth, TextureHeight: Cardinal;
    { EffectiveSize for which the tiles were allocated. }
    AllocatedSize: Cardinal;
    { Size chosen by ChooseScreenSize, 0 if none. }
    ScreenSize: Cardinal;
    { Size of the views now: Size, or smaller ScreenSize. }
    function EffectiveSize: Cardinal;
    { Make sure that ATileCount tiles are allocated. }
    procedure AllocateTiles(const ATileCount: Integer);
    procedure FreeTiles;
    { Tile in the texture pixels. }
    function TileRect(const Index: Integer): TRectangle;
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    { Size of the views, from TGeneratedShadowMapNode.Size. }
    Size: Cardinal;
    { Camera for which the cascades were last rendered by @link(Update)
      (only compared, may be already freed). }
    CascadesCamera: TCastleCamera;

    function TextureNode: TGeneratedShadowMapNode;

    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function GLName: TGLTextureId; override;

    { Render the views of the shadow map, and store them
      in TextureNode.InternalTiles (and related fields) for the shaders.
      Camera is the main camera of the world (for cascades, may be @nil),
      WorldBox the bounding box of the world (for the automatic ranges
      of point lights and cascades). }
    procedure Update(
      const Render: TRenderFromViewFunction;
      const Light: TAbstractPunctualLightNode;
      const Camera: TCastleCamera;
      const WorldBox: TBox3D);

    { Choose the size of the views by how big the light's range
      is on the screen of Camera, when ShadowMapsSizeByScreen.
      Returns @true when it changed: the shadow map should be updated
      (@link(Update) allocates the views of the new size). }
    function ChooseScreenSize(const Light: TAbstractPunctualLightNode;
      const Camera: TCastleCamera; const WorldBox: TBox3D): Boolean;

    { Size of the views (tiles) rendered by the last @link(Update). }
    property CurrentTileSize: Cardinal read TileSize;

    { Check would we use Variance Shadow Maps with current ARenderer
      attributes and OpenGL version/extensions. }
    class function ClassVarianceShadowMaps(RenderOptions: TCastleRenderOptions): boolean;
  end;

  { Renderer resource for TShaderTextureNode. }
  TShaderTextureResource = class(TSingleTextureResource)
  protected
    class function IsClassForTextureNode(ANode: TAbstractTextureNode): boolean; override;
    procedure PrepareCore(
      const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    const
      MyTextureType = ttShader;

    function TextureNode: TShaderTextureNode;
    function Bind(const TextureUnit: Cardinal): boolean; override;
    function Enable(const TextureUnit: Cardinal;
      Shader: TShader; const Env: TTextureEnv): boolean; override;
    function ShaderTextureType(out TextureType: TTextureType): Boolean; override;
  end;

{$endif read_interface}

{$ifdef read_implementation}

{$ifndef OpenGLES}
const
  CombineGL: array [TCombine] of TGLint = (
    GL_MODULATE, GL_REPLACE, GL_ADD_SIGNED_EXT, GL_ADD, GL_SUBTRACT,
    GL_INTERPOLATE_EXT, GL_DOT3_RGB_ARB, GL_DOT3_RGBA_ARB
  );
{$endif}

function TextureRepeatToGL(const IsRepeat: boolean): TGLenum;
begin
  if IsRepeat then
    Result := GL_REPEAT
  else
    Result := GLFeatures.CLAMP_TO_EDGE;
end;

{ TTextureResource ------------------------------------------------------------- }

constructor TTextureResource.Create(const ANode: TX3DNode);
begin
  Assert(ANode is TAbstractTextureNode, 'TTextureResource.Create acceps as Node only TAbstractTextureNode');
  inherited;
end;

procedure TTextureResource.HandleTextureProperties(
  const TextureProperties: TTexturePropertiesNode;
  const RenderOptions: TCastleRenderOptions;
  const RepeatS, RepeatT, RepeatR: TGLenum;
  out Filter: TTextureFilter;
  out BoundaryModeS, BoundaryModeT, BoundaryModeR: TGLenum;
  out Anisotropy: TGLfloat;
  out GUITexture: boolean);

  function BoundaryModeGL(const Value: TBoundaryMode): TGLenum;
  const
    Map: array [TBoundaryMode] of TGLenum = (
      GL_CLAMP_TO_EDGE, // bmClamp: Undefined in X3D, we prefer to make it equal to bmClampToEdge as we don't support border.
      GL_CLAMP_TO_EDGE,
      GL_CLAMP_TO_EDGE, //< bmClampToBoundaryUnsupported: Border not supported, hence behave like bmClampToEdge.
      GL_MIRRORED_REPEAT,
      GL_REPEAT
    );
  begin
    Result := Map[Value];

    { Use GLFeatures.CLAMP_TO_EDGE instead of GL_CLAMP_TO_EDGE, to support even
      ancient OpenGL versions that don't support GL_CLAMP_TO_EDGE. }
    if Result = GL_CLAMP_TO_EDGE then
      Result := GLFeatures.CLAMP_TO_EDGE;
  end;

  { Convert TAutoMinificationFilter to TMinificationFilter,
    resolving the "default"/"fastest"/"nicest" aliases to specific values. }
  function FinalMinificationFilter(const FilterAuto: TAutoMinificationFilter): TMinificationFilter;
  begin
    case FilterAuto of
      minDefault:
        case RenderOptions.MinificationFilter of
          minDefault: Result := TCastleRenderOptions.DefaultMinificationFilter;
          minFastest: Result := minNearest;
          minNicest : Result := minLinearMipmapLinear;
          else        Result := RenderOptions.MinificationFilter;
        end;
      minFastest: Result := minNearest;
      minNicest : Result := minLinearMipmapLinear;
      else        Result := FilterAuto;
    end;
  end;

  { Convert TAutoMagnificationFilter to TMagnificationFilter,
    resolving the "default"/"fastest"/"nicest" aliases to specific values. }
  function FinalMagnificationFilter(const FilterAuto: TAutoMagnificationFilter): TMagnificationFilter;
  begin
    case FilterAuto of
      magDefault:
        case RenderOptions.MagnificationFilter of
          magDefault: Result := TCastleRenderOptions.DefaultMagnificationFilter;
          magFastest: Result := magNearest;
          magNicest : Result := magLinear;
          else        Result := RenderOptions.MagnificationFilter;
        end;
      magFastest: Result := magNearest;
      magNicest : Result := magLinear;
      else        Result := FilterAuto;
    end;
  end;

  function TextureFilter(const RenderOptions: TCastleRenderOptions): TTextureFilter;
  begin
    case RenderOptions.MinificationFilter of
      minDefault: Result.Minification := TCastleRenderOptions.DefaultMinificationFilter;
      minFastest: Result.Minification := minNearest;
      minNicest : Result.Minification := minLinearMipmapLinear;
      else        Result.Minification := RenderOptions.MinificationFilter;
    end;

    case RenderOptions.MagnificationFilter of
      magDefault: Result.Magnification := TCastleRenderOptions.DefaultMagnificationFilter;
      magFastest: Result.Magnification := magNearest;
      magNicest : Result.Magnification := magLinear;
      else        Result.Magnification := RenderOptions.MagnificationFilter;
    end;
  end;

begin
  if TextureProperties <> nil then
  begin
    Filter.Minification := FinalMinificationFilter(TextureProperties.MinificationFilter);
    Filter.Magnification := FinalMagnificationFilter(TextureProperties.MagnificationFilter);
    Anisotropy := TextureProperties.AnisotropicDegree;
    GUITexture := TextureProperties.GUITexture;

    if (TextureProperties.BoundaryModeS = bmClampToBoundaryUnsupported) or
       (TextureProperties.BoundaryModeT = bmClampToBoundaryUnsupported) or
       (TextureProperties.BoundaryModeR = bmClampToBoundaryUnsupported) then
      WritelnWarning('VRML/X3D', 'Boundary mode CLAMP_TO_BOUNDARY is not supported. Behaves like CLAMP_TO_EDGE.');

    BoundaryModeS := BoundaryModeGL(TextureProperties.BoundaryModeS);
    BoundaryModeT := BoundaryModeGL(TextureProperties.BoundaryModeT);
    BoundaryModeR := BoundaryModeGL(TextureProperties.BoundaryModeR);
  end else
  begin
    Filter := TextureFilter(RenderOptions);
    Anisotropy := 1;
    GUITexture := false;

    { Use repeatS/T/R
      as no texture property node is provided. [see 18.2.3] }
    BoundaryModeS := RepeatS;
    BoundaryModeT := RepeatT;
    BoundaryModeR := RepeatR;
  end;
end;

procedure TTextureResource.HandleTextureProperties(
  const TextureProperties: TTexturePropertiesNode;
  const RenderOptions: TCastleRenderOptions;
  const RepeatS, RepeatT: TGLenum;
  out Filter: TTextureFilter;
  out BoundaryModeS, BoundaryModeT: TGLenum;
  out Anisotropy: TGLfloat;
  out GUITexture: boolean);
var
  Dummy: TGLenum;
const
  DummyRepeatMode = GL_REPEAT;
begin
  HandleTextureProperties(TextureProperties, RenderOptions,
    RepeatS, RepeatT, DummyRepeatMode,
    Filter, BoundaryModeS, BoundaryModeT, Dummy, Anisotropy, GUITexture);
end;

procedure TTextureResource.HandleTextureProperties(
  const TextureProperties: TTexturePropertiesNode;
  const RenderOptions: TCastleRenderOptions;
  out Filter: TTextureFilter;
  out Anisotropy: TGLfloat;
  out GUITexture: boolean);
var
  Dummy: array[0..2] of TGLenum;
const
  DummyRepeatMode = GL_REPEAT;
begin
  HandleTextureProperties(
    TextureProperties, RenderOptions,
    DummyRepeatMode, DummyRepeatMode, DummyRepeatMode,
    Filter, Dummy[0], Dummy[1], Dummy[2], Anisotropy, GUITexture);
end;

class function TTextureResource.ClassForTextureNode(
  ANode: TAbstractTextureNode): TTextureResourceClass;

  function TryResult(C: TTextureResourceClass): boolean;
  begin
    Result := C.IsClassForTextureNode(ANode);
    if Result then
      ClassForTextureNode := C;
  end;

begin
  { TODO: in the future, some way of registering class for this will
    be done. For now, just try known final TTextureResource descendants. }
  if not (TryResult(TMultiTextureResource) or
          TryResult(TImageTextureResource) or
          TryResult(TMovieTextureResource) or
          TryResult(TRenderedTextureResource) or
          TryResult(TComposedCubeMapTextureResource) or
          TryResult(TImageCubeMapTextureResource) or
          TryResult(TGeneratedCubeMapTextureResource) or
          TryResult(T3DTextureResource) or
          TryResult(TGeneratedShadowMapResource) or
          TryResult(TShaderTextureResource) or
          TryResult(TScreenTextureResource) ) then
    Result := nil;
end;

function TTextureResource.TextureNode: TAbstractTextureNode;
begin
  Result := TAbstractTextureNode(inherited Node);
end;

function TTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  Result := false;
end;

{ TTextureResources ------------------------------------------------------------ }

class function TTextureResources.Get(const ANode: TAbstractTextureNode): TTextureResource;
begin
  if ANode <> nil then
    Result := TTextureResource(ANode.InternalRendererResource)
  else
    Result := nil;
end;

class procedure TTextureResources.Prepare(
  const RenderOptions: TCastleRenderOptions;
  const ANode: TAbstractTextureNode);
var
  TextureRes: TTextureResource;
  TextureResClass: TTextureResourceClass;
begin
  if (ANode <> nil) and
     (ANode.InternalRendererResource = nil) then
  begin
    TextureResClass := TTextureResourceClass.ClassForTextureNode(ANode);
    if TextureResClass <> nil { Ignore if not handled node. } then
    begin
      TextureRes := TextureResClass.Create(ANode);
      TextureRes.Prepare(RenderOptions);
      ANode.InternalRendererResource := TextureRes;
    end;
  end;
end;

class procedure TTextureResources.Unprepare(const ANode: TAbstractTextureNode);
begin
  if ANode <> nil then
    ANode.InternalRendererResourceFree;
end;

class function TTextureResources.Bind(ANode: TAbstractTextureNode;
  const TextureUnit: Cardinal): boolean;
var
  TextureRes: TTextureResource;
begin
  TextureRes := Get(ANode);
  Result := TextureRes <> nil;
  if Result then
    Result := TextureRes.Bind(TextureUnit);
end;

class function TTextureResources.Enable(ANode: TAbstractTextureNode;
  const TextureUnit: Cardinal; Shader: TShader; const Env: TTextureEnv): boolean;
var
  TextureRes: TTextureResource;
begin
  TextureRes := Get(ANode);
  Result := TextureRes <> nil;
  if Result then
    Result := TextureRes.Enable(TextureUnit, Shader, Env);
end;

{ TSingleTextureResource ------------------------------------------------------- }

procedure TSingleTextureResource.EnableAll(const Renderer: TRenderer;
  const TextureUnitsCount: Cardinal;
  var TextureSlotsUsed: Cardinal;
  const Shader: TShader;
  const HasPreviousMainTexture: Boolean);
var
  Env: TTextureEnv;
begin
  { coModulate is default texture mode for single texturing (not MultiTexture).

    Note: VRML 2 and X3D < 4.0 specifications say that the texture color should
    replace material color (see "Lighting model" spec) *in case of RGB
    (not grayscale) textures*. We contradict that specs, instead modulating
    with material color because of GL_MODULATE below. See
    https://castle-engine.io/x3d_multi_texturing.php#section_default_texture_mode ,
    https://github.com/michaliskambi/x3d-tests/wiki/Make-RGB-and-grayscale-textures-treatment-consistent .

    What we do follows X3D 4.0 spec.
    As explained above, we actually changed the spec, because "always doing
    coModulate" is better.

    For alpha channel: specification says clearly that texture alpha
    should replace (never modulate) alpha channel, if only texture
    has any alpha channel. Again, we contradict it, instead multiplying alpha.

    Note that using GL_REPLACE below would not really make us conforming
    to the spec: it would mean that texture color replaces the whole resulting
    lighting calculation (not just material color, which is input to
    lighting calculation). So it would not be conforming either. }

  Env.Init(coModulate);

  { HasPreviousMainTexture is passed when enabling Appearance.texture
    on Text node (geometry with FontTextureNode set),
    IOW when we have textured Text node.

    In this case, we already called EnableAll with FontTextureNode,
    and it has determined the initial color (and alpha) of the text.
    So our Source should indicate to mix with previous texture (FontTextureNode),
    and not with the material color (as is default, and would override
    FontTextureNode alpha).

    Testcases:
      demo-models/shadow_maps/primitives.x3dv
      demo-models/text/text_textured.x3dv
    Without this "if HasPreviousMainTexture then" check,
    the textured text displays every letter as a rectangle, as alpha
    of FontTextureNode is ignored. }
  if HasPreviousMainTexture then
  begin
    Env.Source[cRGB  ] := csPreviousTexture;
    Env.Source[cAlpha] := csPreviousTexture;
  end;

  if (TextureUnitsCount > 0) and
     Enable(TextureSlotsUsed, Shader, Env) then
  begin
    if GLFeatures.EnableFixedFunction then
    begin
      {$ifndef OpenGLES}
      { Here we know that Env was initialized above.
        So we know that mode is simple, the same for rgb and alpha,
        and can be set using GL_TEXTURE_ENV_MODE
        (doesn't require using GL_COMBINE). }
      glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, CombineGL[Env.Combine[cRGB]]);
      {$endif}
    end;
    Inc(TextureSlotsUsed);
  end;
end;

{ TMultiTextureResource -------------------------------------------------------- }

constructor TMultiTextureResource.Create(const ANode: TX3DNode);
begin
  Assert(ANode is TMultiTextureNode, 'TMultiTextureResource.Create acceps as Node only TMultiTextureNode');
  inherited;
end;

class function TMultiTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TMultiTextureNode;
end;

function TMultiTextureResource.TextureNode: TMultiTextureNode;
begin
  Result := TMultiTextureNode(inherited TextureNode);
end;

procedure TMultiTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  ChildTex: TX3DNode;
  I: Integer;
begin
  for I := 0 to TextureNode.FdTexture.Count - 1 do
  begin
    ChildTex := TextureNode.FdTexture[I];
    if ChildTex is TAbstractTextureNode then // also checks ChildTex <> nil
    begin
      if ChildTex is TMultiTextureNode then
        WritelnWarning('VRML/X3D', 'Child of MultiTexture node cannot be another MultiTexture node') else
      begin
        TTextureResources.Prepare(RenderOptions, TAbstractTextureNode(ChildTex));
      end;
    end;
  end;
end;

procedure TMultiTextureResource.UnprepareCore;
var
  ChildTex: TX3DNode;
  I: Integer;
begin
  for I := 0 to TextureNode.FdTexture.Count - 1 do
  begin
    ChildTex := TextureNode.FdTexture[I];
    if (ChildTex is TAbstractTextureNode) and // also checks ChildTex <> nil
       (not (ChildTex is TMultiTextureNode)) then
      TTextureResources.Unprepare(TAbstractTextureNode(ChildTex));
  end;
end;

function TMultiTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  { TMultiTextureResource cannot set only one texture unit.
    This may be called from GLSL shader, when someone will use MultiTexture
    node for a shader uniform field. I don't know how this should be handled,
    I guess returning failure is Ok for now. }
  Result := false;
end;

function TMultiTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  { This should never be called. TMultiTextureResource cannot set only one
    texture unit. }
  Result := false;
end;

procedure TMultiTextureResource.EnableAll(const Renderer: TRenderer;
  const TextureUnitsCount: Cardinal;
  var TextureSlotsUsed: Cardinal;
  const Shader: TShader;
  const HasPreviousMainTexture: Boolean);
{$ifndef OpenGLES}
const
  ColorSourceGL: array [TColorSource] of TGLint = (
    GL_PRIMARY_COLOR, GL_TEXTURE, GL_CONSTANT, GL_PREVIOUS
  );
  Argument: array [ta0..ta1] of Integer = ( 0, 1 );
{$endif}
var
  InitialTextureSlotsUsed: Cardinal;
  ChildTex: TX3DNode;
  I: Integer;
  Success: boolean;
  Env: TTextureEnv;
  ModeStr, SourceStr, FunctionStr: string;
begin
  { calculate TextureSlotsUsed }
  InitialTextureSlotsUsed := TextureSlotsUsed;
  TextureSlotsUsed := TextureSlotsUsed + TextureNode.FdTexture.Count;
  MinVar(TextureSlotsUsed, TextureUnitsCount);
  if not GLFeatures.UseMultiTexturing then
    MinVar(TextureSlotsUsed, 1);

  { TODO: Passing it to shader this way precludes ability to later change it
    (e.g. in case some ROUTE animates MultiTexture.color/alpha, or Pascal code changes it)
    without recompiling the shader.

    Right now changes to MultiTexture.color/alpha will recompile the shader.

    To make it efficient and corrent, this should be a uniform passed to shader.
    This is low-priority due to low MultiTexture usage. }
  Shader.MultiTextureColor := Vector4(TextureNode.Color, TextureNode.Alpha);

  for I := 0 to Integer(TextureSlotsUsed) - Integer(InitialTextureSlotsUsed) - 1 do
  begin
    ChildTex := TextureNode.FdTexture[I];
    Success := false;

    if (ChildTex <> nil) and
       (ChildTex is TAbstractTextureNode) then
    begin
      if I < TextureNode.FdMode.Count then
        ModeStr := TextureNode.FdMode.Items[I] else
        ModeStr := '';
      if I < TextureNode.FdSource.Count then
        SourceStr := TextureNode.FdSource.Items[I] else
        SourceStr := '';
      if I < TextureNode.FdFunction.Count then
        FunctionStr := TextureNode.FdFunction.Items[I] else
        FunctionStr := '';
      Env.Init(ModeStr, SourceStr, FunctionStr);

      if ChildTex is TMultiTextureNode then
        WritelnWarning('VRML/X3D', 'Child of MultiTexture node cannot be another MultiTexture node')
      else
        Success := TTextureResources.Enable(
          TAbstractTextureNode(ChildTex),
          InitialTextureSlotsUsed + I, Shader, Env);

      { Apply Env for fixed-function pipeline. }
      if Success and GLFeatures.UseMultiTexturing { needed OpenGL exts available } then
      begin
        { Set all the multitexture mode-related stuff.
          Below we handle TextureNode.mode, source, color, alpha,
          function fields. }

        if Env.Disabled then
        begin
          { When mode=OFF, turn off the texture unit. }
          Renderer.DisableCurrentTexture;
        end else
        begin
          if GLFeatures.EnableFixedFunction then
          begin
            {$ifndef OpenGLES}
            glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE);

            glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB, CombineGL[Env.Combine[cRGB]]);
            glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_ALPHA, CombineGL[Env.Combine[cAlpha]]);

            glTexEnvf(GL_TEXTURE_ENV, GL_RGB_SCALE, Env.Scale[cRGB]);
            glTexEnvf(GL_TEXTURE_ENV, GL_ALPHA_SCALE, Env.Scale[cAlpha]);

            if Env.CurrentTextureArgument[cRGB] <> taNone then
            begin
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE0_RGB + Argument[Env.CurrentTextureArgument[cRGB]], GL_TEXTURE);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND0_RGB + Argument[Env.CurrentTextureArgument[cRGB]], GL_SRC_COLOR);
            end;

            if Env.CurrentTextureArgument[cAlpha] <> taNone then
            begin
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE0_ALPHA + Argument[Env.CurrentTextureArgument[cAlpha]], GL_TEXTURE);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND0_ALPHA + Argument[Env.CurrentTextureArgument[cAlpha]], GL_SRC_ALPHA);
            end;

            if Env.SourceArgument[cRGB] <> taNone then
            begin
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE0_RGB + Argument[Env.SourceArgument[cRGB]], ColorSourceGL[Env.Source[cRGB]]);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND0_RGB + Argument[Env.SourceArgument[cRGB]], GL_SRC_COLOR);
            end;

            if Env.SourceArgument[cAlpha] <> taNone then
            begin
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE0_ALPHA + Argument[Env.SourceArgument[cAlpha]], ColorSourceGL[Env.Source[cAlpha]]);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND0_ALPHA + Argument[Env.SourceArgument[cAlpha]], GL_SRC_ALPHA);
            end;

            if (Env.Combine[cRGB] = coBlend) or
               (Env.Combine[cAlpha] = coBlend) then
            begin
              { Whole source2 (both RGB and alpha) is filled by alpha from color
                specified by BlendAlphaSource. }
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE2_RGB, ColorSourceGL[Env.BlendAlphaSource]);
              glTexEnvi(GL_TEXTURE_ENV, GL_SOURCE2_ALPHA, ColorSourceGL[Env.BlendAlphaSource]);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND2_RGB, GL_SRC_ALPHA);
              glTexEnvi(GL_TEXTURE_ENV, GL_OPERAND2_ALPHA, GL_SRC_ALPHA);
            end;

            if Env.NeedsConstantColor then
            begin
              { Assign constant color now, when we know it should be used. }
              glTexEnvv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, Vector4(
                TextureNode.FdColor.Value,
                TextureNode.FdAlpha.Value));
            end;
            {$endif}
          end;
        end;
      end;
    end;

    if not Success then
      Renderer.DisableTexture(I);
  end;
end;

{ TImageTextureResource -------------------------------------------------------- }

class function TImageTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := (ANode is TAbstractTexture2DNode) and
    TAbstractTexture2DNode(ANode).IsTextureImage;
end;

function TImageTextureResource.TextureNode: TAbstractTexture2DNode;
begin
  Result := TAbstractTexture2DNode(inherited TextureNode);
end;

procedure TImageTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  BoundaryModeS: TGLenum;
  BoundaryModeT: TGLenum;
  TextureWrap: TTextureWrap2D;
  GUITexture, FlipVertically: boolean;
begin
  { HandledNode already made sure IsTextureImage = @true }

  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    TextureRepeatToGL(TextureNode.RepeatS), TextureRepeatToGL(TextureNode.RepeatT),
    Filter, BoundaryModeS, BoundaryModeT, Anisotropy, GUITexture);

  TextureWrap.Data[0] := BoundaryModeS;
  TextureWrap.Data[1] := BoundaryModeT;

  FlipVertically :=
    (TextureNode is TImageTextureNode) and
    TImageTextureNode(TextureNode).FlipVertically;

  FGLName := RendererCache.TextureImage_IncReference(
    TextureNode.TextureImage,
    TextureNode.TextureUsedFullUrl,
    Filter,
    Anisotropy,
    TextureWrap,
    TextureNode.TextureComposite,
    GUITexture,
    FlipVertically);
  FAllocatedWidth := TextureNode.TextureImage.Width;
  FAllocatedHeight := TextureNode.TextureImage.Height;
end;

procedure TImageTextureResource.UnprepareCore;
begin
  if FGLName <> GLObjectNone then
  begin
    RendererCache.TextureImage_DecReference(FGLName);
    FGLName := GLObjectNone;
  end;
end;

function TImageTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := FGLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_2D, FGLName);
end;

function TImageTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TImageTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

function TImageTextureResource.GLName: TGLTextureId;
begin
  Result := FGLName;
end;

procedure TImageTextureResource.UpdateTextureContentsRgbaFloat(
  const Width, Height: Cardinal; const Data: Pointer);
const
  // values below like UncompressedGLFormatAndInternalFormat for TRGBAlphaFloatImage
  ImageFormat = GL_RGBA;
  ImageInternalFormat = GL_RGBA32F;
  Level = 0; // always update mipmap level 0;
var
  GLData: {$ifdef CASTLE_WEBGL} IJSFloat32Array {$else} Pointer {$endif};
begin
  if not Bind(0) then Exit;

  {$ifdef CASTLE_WEBGL}
  { On web, the texture data must be copied to JS float32 array. }
  GLData := TJSFloat32Array.Create(Width * Height * 4);
  GLData.CopyFromMemory(Data, Width * Height * 4 * SizeOf(Single));
  {$else}
  GLData := Data;
  {$endif}

  { We assume we don't need to do some stuff from CastleTexImage2D:
    - no need for BeforeUnpackImage, as RGBA float textures are always
      already aligned to 4 bytes
    - no need for Mesa + fixed function hack
    - no need for texture swizzle, just map RGBA to RGBA. }

  { Using glTexSubImage2D is theoretically faster, as it doesn't have to
    change texture size on GPU?
    In practice, animate_bones_by_code_standalone with "Add Crowd"
    shows no difference between glTexImage2D and glTexSubImage2D. }
  {$define UpdateTextureContentsRgbaFloat_USE_TEXSUBIMAGE2D}

  {$ifdef UpdateTextureContentsRgbaFloat_USE_TEXSUBIMAGE2D}
  if (FAllocatedWidth <> Width) or (FAllocatedHeight <> Height) then
  {$endif}

  begin
    glTexImage2D(GL_TEXTURE_2D, Level, ImageInternalFormat,
      Width, Height, 0, ImageFormat, GL_FLOAT, GLData);
    FAllocatedWidth := Width;
    FAllocatedHeight := Height;
  end

  {$ifdef UpdateTextureContentsRgbaFloat_USE_TEXSUBIMAGE2D}
  else
  begin
    glTexSubImage2D(GL_TEXTURE_2D, Level, 0, 0, Width, Height,
      ImageFormat, GL_FLOAT, GLData);
  end
  {$endif};
end;

{ TMovieTextureResource -------------------------------------------------------- }

class function TMovieTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  { Although for most code TMovieTextureResource, it would be enought
    to have any TAbstractTexture2DNode with IsTextureVideo = @true.
    For when rendering, we'll need some TMovieTextureNode properties
    to choose video frame.

    Anyway, TMovieTextureNode is for now the only texture node possible
    that may have IsTextureVideo = @true, so it's not a real problem for now. }

  Result := (ANode is TMovieTextureNode) and
    TMovieTextureNode(ANode).IsTextureVideo;
end;

function TMovieTextureResource.TextureNode: TMovieTextureNode;
begin
  Result := TMovieTextureNode(inherited TextureNode);
end;

procedure TMovieTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  BoundaryModeS: TGLenum;
  BoundaryModeT: TGLenum;
  TextureWrap: TTextureWrap2D;
  GUITexture: boolean;
begin
  { HandledNode already made sure IsTextureVideo = @true }

  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    TextureRepeatToGL(TextureNode.RepeatS), TextureRepeatToGL(TextureNode.RepeatT),
    Filter, BoundaryModeS, BoundaryModeT, Anisotropy, GUITexture);

  TextureWrap.Data[0] := BoundaryModeS;
  TextureWrap.Data[1] := BoundaryModeT;

  GLVideo := RendererCache.TextureVideo_IncReference(
    TextureNode.TextureVideo,
    TextureNode.TextureUsedFullUrl,
    TextureNode.FlipVertically,
    Filter,
    Anisotropy,
    TextureWrap,
    GUITexture);
end;

procedure TMovieTextureResource.UnprepareCore;
begin
  if GLVideo <> nil then
    RendererCache.TextureVideo_DecReference(GLVideo);
end;

function TMovieTextureResource.GLName: TGLTextureId;
var
  VideoUnscaledTime: TFloatTime;
begin
  { Note: don't call IsTextureImage, IsTextureVideo here --- this
    would cause reloading images/videos, nullifying
    TCastleSceneCore.FreeResources([frTextureDataInNodes]) purpose.

    Actually, it would be safe to call this for non-MovieTexture nodes,
    as they should be prepared to GL resources before doing
    FreeResources. But for MovieTexture nodes it's forbidden,
    as it's called at every frame render. }

  if GLVideo <> nil then
  begin
    VideoUnscaledTime :=
      TextureNode.TimeFunctionality.ElapsedTimeInCycle *
      TextureNode.Speed;
    if TextureNode.Speed < 0 then
      VideoUnscaledTime := TextureNode.Duration + VideoUnscaledTime;
    Result := GLVideo.GLTextureFromTime(VideoUnscaledTime);
  end else
    Result := GLObjectNone;
end;

function TMovieTextureResource.Bind(const TextureUnit: Cardinal): boolean;
var
  N: TGLTextureId;
begin
  N := GLName;
  Result := N <> GLObjectNone;
  if Result then
  begin
    TRenderer.ActiveTexture(TextureUnit);
    glBindTexture(GL_TEXTURE_2D, N);
  end;
end;

function TMovieTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TMovieTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

{ TRenderedTextureResource ----------------------------------------------------- }

class function TRenderedTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TRenderedTextureNode;
end;

function TRenderedTextureResource.TextureNode: TRenderedTextureNode;
begin
  Result := TRenderedTextureNode(inherited TextureNode);
end;

procedure TRenderedTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  InitialImage: TCastleImage;
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  BoundaryModeS: TGLenum;
  BoundaryModeT: TGLenum;
  TextureWrap: TTextureWrap2D;
  NodeWidth, NodeHeight: Cardinal;
  GUITexture: boolean;
  Sizing: TTextureSizing;
begin
  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    TextureRepeatToGL(TextureNode.FdRepeatS.Value), TextureRepeatToGL(TextureNode.FdRepeatT.Value),
    Filter, BoundaryModeS, BoundaryModeT, Anisotropy, GUITexture);

  { calculate Filter, Anisotropy, NeedsMipmaps }
  NeedsMipmaps := Filter.NeedsMipmaps;
  if NeedsMipmaps and not HasGenerateMipmap then
  begin
    WritelnWarning('VRML/X3D' { This may be caused by OpenGL implementation
      limits, so it may be impossible to predict by VRML author,
      so it's "ignorable" warning. },
      'OpenGL(ES) doesn''t have glGenerateMipmap, so you cannot use mipmaps for RenderedTexture');
    Filter.Minification := minLinear;
    NeedsMipmaps := false;
  end;

  TextureWrap.Data[0] := BoundaryModeS;
  TextureWrap.Data[1] := BoundaryModeT;

  { calculate Width, Height }
  if TextureNode.FdDimensions.Items.Count - 1 >= 0 then
    NodeWidth := Max(TextureNode.FdDimensions.Items[0], 0) else
    NodeWidth := DefaultRenderedTextureWidth;
  if TextureNode.FdDimensions.Items.Count - 1 >= 1 then
    NodeHeight := Max(TextureNode.FdDimensions.Items[1], 0) else
    NodeHeight := DefaultRenderedTextureHeight;
  Width  := NodeWidth ;
  Height := NodeHeight;
  if GUITexture then
    Sizing := tsAny else
    Sizing := tsScalablePowerOf2;
  if not IsTextureSized(Width, Height, Sizing) then
  begin
    Width  := ResizeToTextureSize(Width , Sizing);
    Height := ResizeToTextureSize(Height, Sizing);
    WritelnWarning('VRML/X3D' { This may be caused by OpenGL implementation
      limits, so it may be impossible to predict by VRML author,
      so it's "ignorable" warning. },
      Format('Rendered texture size %d x %d is incorrect (texture size must be a power of two, > 0 and <= GL_MAX_TEXTURE_SIZE = %d), corrected to %d x %d',
        [ NodeWidth, NodeHeight,
          GLFeatures.MaxTextureSize,
          Width, Height]));
  end;

  if (TextureNode.FdDepthMap.Count > 0) and
     TextureNode.FdDepthMap.Items[0] then
  begin
    WritelnWarning('VRML/X3D', 'RenderedTexture with depthMap = TRUE is no longer supported. For shadow maps, use dedicated CGE nodes.');
    Exit;
  end;

  InitialImage := TRGBImage.Create(Width, Height);
  try
    InitialImage.URL := 'generated:/' + TextureNode.NiceName;

    { Fill with deliberately stupid (but constant) color,
      to recognize easily RenderedTexture which don't have textures
      updated. }
    InitialImage.Clear(Vector4Byte(255, 0, 255, 255));

    FGLName := RendererCache.TextureImage_IncReference(
      InitialImage,
      '' { generated texture contents means empty URL },
      Filter,
      Anisotropy,
      TextureWrap,
      nil,
      GUITexture,
      false);

    { RenderedTexture never has any normal / height map
      (Hm, although it would be possible to generate some in theory
      --- after all, we generate it from 3D data. Idea for the future.)
    NormalMap := GLObjectNone;
    HeightMap := GLObjectNone;
    }
  finally FreeAndNil(InitialImage) end;

  RenderToTexture := TGLRenderToTexture.Create(Width, Height);
  RenderToTexture.SetTexture(FGLName, GL_TEXTURE_2D);
  RenderToTexture.Buffer := tbColor;
  RenderToTexture.Stencil := true;
  RenderToTexture.GLContextOpen;
end;

procedure TRenderedTextureResource.UnprepareCore;
begin
  FreeAndNil(RenderToTexture);

  if FGLName <> GLObjectNone then
  begin
    RendererCache.TextureImage_DecReference(FGLName);
    FGLName := GLObjectNone;
  end;
end;

function TRenderedTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := FGLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_2D, FGLName);
end;

function TRenderedTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TRenderedTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

procedure TRenderedTextureResource.Update(
  const Render: TRenderFromViewFunction;
  const ProjectionNear, ProjectionFar: Single;
  const CurrentViewpoint: TAbstractViewpointNode;
  const CameraViewKnown: boolean;
  const CameraView: TViewVectors;
  const ShapeForViewpointMirror: TX3DRendererShape);

  function GetProjectionMatrix(const Viewpoint: TAbstractViewpointNode): TMatrix4;
  { We have to calculate projection, given Viewpoint node.
    Similar to TCastleSceneCore.InternalUpdateCamera.

    We have to calculate things a little differently, e.g. we have
    no NavigationInfo (it could be undesirable to use scene bound NavigationInfo,
    since X3D author cannot change it by any RenderedTexture field,
    and for now we have no field RenderedTexture.navigationInfo...),
    no knowledge of scene box (although we do have ProjectionNear / Far
    already).
  }

    procedure DoPerspective;
    var
      FieldOfView, AngleOfViewY: Single;
      FieldOfViewAxis: TFieldOfViewAxis;
      Angles: TVector2;
    begin
      if (Viewpoint <> nil) and
         (Viewpoint is TViewpointNode) then
      begin
        FieldOfView := TViewpointNode(Viewpoint).FieldOfView;
        if TViewpointNode(Viewpoint).FieldOfViewForceVertical then
          FieldOfViewAxis := faVertical
        else
          FieldOfViewAxis := faSmallest;
      end else
      if (Viewpoint <> nil) and
         (Viewpoint is TPerspectiveCameraNode_1) then
      begin
        FieldOfView := TPerspectiveCameraNode_1(Viewpoint).FdHeightAngle.Value;
        FieldOfViewAxis := faSmallest;
      end else
      begin
        FieldOfView := DefaultViewpointFieldOfView;
        FieldOfViewAxis := faSmallest;
      end;

      Angles := TViewpointNode.InternalFieldOfView(FieldOfView, FieldOfViewAxis, Width, Height);
      AngleOfViewY := RadToDeg(Angles[1]);

      Result := PerspectiveProjectionMatrixDeg(AngleOfViewY, Width / Height,
        ProjectionNear, ProjectionFar);
    end;

    procedure DoOrthographic;
    var
      FieldOfView: TSingleList;
      FinalFieldOfView: TFloatRectangle;
    begin
      { default VRML/X3D fov }
      FinalFieldOfView.Left   := -1;
      FinalFieldOfView.Bottom := -1;
      FinalFieldOfView.Width  :=  2;
      FinalFieldOfView.Height :=  2;

      { update left / right / bottom / top using OrthoViewpoint.fieldOfView }
      if (Viewpoint <> nil) and
         (Viewpoint is TOrthoViewpointNode) then
      begin
        FieldOfView := TOrthoViewpointNode(Viewpoint).FdFieldOfView.Items;
        if FieldOfView.Count > 0 then FinalFieldOfView.Left   := FieldOfView.Items[0];
        if FieldOfView.Count > 1 then FinalFieldOfView.Bottom := FieldOfView.Items[1];
        if FieldOfView.Count > 2 then FinalFieldOfView.Width  := FieldOfView.Items[2] - FinalFieldOfView.Left;
        if FieldOfView.Count > 3 then FinalFieldOfView.Height := FieldOfView.Items[3] - FinalFieldOfView.Bottom;
      end else
      if (Viewpoint <> nil) and
         (Viewpoint is TOrthographicCameraNode_1) then
      begin
        FinalFieldOfView.Left   := -TOrthographicCameraNode_1(Viewpoint).FdHeight.Value / 2;
        FinalFieldOfView.Bottom := -TOrthographicCameraNode_1(Viewpoint).FdHeight.Value / 2;
        FinalFieldOfView.Width  :=  TOrthographicCameraNode_1(Viewpoint).FdHeight.Value;
        FinalFieldOfView.Height :=  TOrthographicCameraNode_1(Viewpoint).FdHeight.Value;
      end;

      FinalFieldOfView := TOrthoViewpointNode.InternalFieldOfView(
        FinalFieldOfView, Width, Height);

      Result := OrthoProjectionMatrix(FinalFieldOfView, ProjectionNear, ProjectionFar);
    end;

  var
    ProjectionType: TProjectionType;
  begin
    if Viewpoint <> nil then
      ProjectionType := Viewpoint.ProjectionType
    else
      ProjectionType := ptPerspective;

    case ProjectionType of
      ptPerspective: DoPerspective;
      ptOrthographic: DoOrthographic;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('TRenderedTextureResource.Update-ProjectionType?');
      {$endif}
    end;
  end;

  procedure GetRenderedTextureCamera(const Viewpoint: TAbstractViewpointNode;
    out CameraRender: TViewVectors);

    procedure GetFromCurrent;
    begin
      if CameraViewKnown then
      begin
        CameraRender := CameraView;
      end else
      if CurrentViewpoint <> nil then
        CurrentViewpoint.GetView(CameraRender)
      else
      begin
        { If all else fails (no viewpoint node bound, not known current
          camera settings) then use defaults. }
        CameraRender := DefaultX3DCameraView;
      end;
    end;

  begin
    if Viewpoint = CurrentViewpoint then
      GetFromCurrent else
    begin
      { Viewpoint gets assigned something different than CurrentViewpoint
        only when it's non-nil. }
      Assert(Viewpoint <> nil);
      Viewpoint.GetView(CameraRender);
    end;
  end;

  { Best plane for a set of points.
    The plane direction (first 3 components) is guaranteed to be normalized. }
  function PointsPlane(const Points: TVector3List; out Plane: TVector4): Boolean;
  var
    Normal: TVector3 absolute Plane;
    Tri: TTriangle3;
    I: Integer;
    PlaneShift: Single;
    Point: TVector3;
  begin
    if Points.Count < 3 then Exit(false);

    { Calculate plane Normal, averaging normals of all valid triangles.
      Assumes polygon is convex. }

    Normal := TVector3.Zero;

    Tri[0] := Points.L[0];
    Tri[1] := Points.L[1];
    Tri[2] := Points.L[2];
    if Tri.IsValid then
      Normal := Tri.Normal;

    for I := 3 to Points.Count - 1 do
    begin
      Tri[1] := Tri[2];
      Tri[2] := Points.L[I];
      if Tri.IsValid then
        Normal := Normal + Tri.Normal;
    end;

    if Normal.IsPerfectlyZero then
      Exit(false); // no valid triangle

    { calculate Plane[3] by averaging possible shift for all Points }
    PlaneShift := 0;
    for Point in Points do
    begin
      PlaneShift := PlaneShift +
        -Normal.X * Point.X
        -Normal.Y * Point.Y
        -Normal.Z * Point.Z;
    end;
    PlaneShift := PlaneShift / Points.Count;

    Plane.W := PlaneShift;
    Result := true;
  end;

  procedure GetMatricesForViewpoint(const Viewpoint: TAbstractViewpointNode;
    out CameraRender: TViewVectors;
    out ProjectionMatrix: TMatrix4);
  begin
    ProjectionMatrix := GetProjectionMatrix(Viewpoint);
    GetRenderedTextureCamera(Viewpoint, CameraRender);
  end;

  procedure GetMatricesForViewpointMirror(const ViewpointMirror: TViewpointMirrorNode;
    out CameraRender: TViewVectors;
    out ProjectionMatrix: TMatrix4);
  var
    PosOnPlane, Side, Coord, PlaneCoord: TVector3;
    PlaneCoordProjected: TVector2;
    Plane: TVector4;
    ZNear: Single;
    FrustumDimensions: TFloatRectangle;
    ShapeBox: TBox3d;
    ShapeCorners: TBoxCorners;
    GeometryCoordsField: TMFVec3f;
    GeometryCoords: TVector3List;
  begin
    if (ShapeForViewpointMirror.ParentScene = nil) or
       (not ShapeForViewpointMirror.ParentScene.HasWorldTransform) then
    begin
      WritelnWarning('ViewpointMirror can only work in TCastleScene that is part of viewport exactly once (without TCastleTransformReference)');
      GetMatricesForViewpoint(CurrentViewpoint, CameraRender, ProjectionMatrix);
      Exit;
    end;

    { calculate camera CameraRender (in world space) }
    if not CameraViewKnown then
    begin
      WritelnWarning('ViewpointMirror will not work correctly until camera vectors are known');
      GetMatricesForViewpoint(CurrentViewpoint, CameraRender, ProjectionMatrix);
      Exit;
    end;
    GetRenderedTextureCamera(CurrentViewpoint, CameraRender);

    { calculate GeometryCoords }
    GeometryCoords := nil;
    if ShapeForViewpointMirror.Geometry.InternalCoord(ShapeForViewpointMirror.State, GeometryCoordsField) and
       (GeometryCoordsField <> nil) then
      GeometryCoords := GeometryCoordsField.Items;
    if GeometryCoords = nil then
    begin
      WritelnWarning('ViewpointMirror can only be used on node with coordinates');
      GetMatricesForViewpoint(CurrentViewpoint, CameraRender, ProjectionMatrix);
      Exit;
    end;

    { calculate Plane of the mirror from GeometryCoords (in local shape coords) }
    if not PointsPlane(GeometryCoords, Plane) then
    begin
      WritelnWarning('ViewpointMirror plane cannot be determined, the shape does not define a plane');
      GetMatricesForViewpoint(CurrentViewpoint, CameraRender, ProjectionMatrix);
      Exit;
    end;

    { convert Plane to world coords }
    Plane := PlaneTransform(Plane,
      ShapeForViewpointMirror.ParentScene.WorldTransform *
      ShapeForViewpointMirror.State.Transformation.Transform);

    { reflect Pos, Dir, Up for mirror view }
    PosOnPlane := PointOnPlaneClosestToPoint(Plane, CameraRender.Translation);
    CameraRender.Translation := 2 * PosOnPlane - CameraRender.Translation; // mirror Pos versus Plane
    CameraRender.Direction := PosOnPlane - CameraRender.Translation;
    //CameraRender.Up := no need to change

    { calculate Side, and make Dir, Up normalized and orthogonal }
    CameraRender.Direction := CameraRender.Direction.Normalize;
    //CameraRender.Up := CameraRender.Up.Normalize; // no need to
    MakeVectorsOrthoOnTheirPlane(CameraRender.Up, CameraRender.Direction);
    Side := TVector3.CrossProduct(CameraRender.Direction, CameraRender.Up);

    { At this point CameraRender is ready. }

    { calculate FrustumDimensions,
      to include ShapeForViewpointMirror bounding box projected on the Plane. }
    ShapeBox := ShapeForViewpointMirror.BoundingBox.Transform(
      ShapeForViewpointMirror.ParentScene.WorldTransform);
    ShapeBox.Corners(ShapeCorners);
    FrustumDimensions := TFloatRectangle.Empty;
    for Coord in ShapeCorners do
    begin
      PlaneCoord := PointOnPlaneClosestToPoint(Plane, Coord) - PosOnPlane;
      PlaneCoordProjected := Vector2(
        TVector3.DotProduct(PlaneCoord, Side),
        TVector3.DotProduct(PlaneCoord, CameraRender.Up)
      );
      FrustumDimensions := FrustumDimensions.Include(PlaneCoordProjected);
    end;

    ZNear := PointsDistance(CameraRender.Translation, PosOnPlane) +
      ViewpointMirror.DistanceFromShape;
    ProjectionMatrix := FrustumProjectionMatrix(FrustumDimensions,
      ZNear, ProjectionFar);

    if ShapeForViewpointMirror.MirrorPlaneUniforms = nil then
      ShapeForViewpointMirror.MirrorPlaneUniforms := TMirrorPlaneUniforms.Create;
    ShapeForViewpointMirror.MirrorPlaneUniforms.NormalizedPlane := Plane;
    ShapeForViewpointMirror.MirrorPlaneUniforms.CameraPositionOnPlane := PosOnPlane;
    ShapeForViewpointMirror.MirrorPlaneUniforms.CameraSide := Side;
    ShapeForViewpointMirror.MirrorPlaneUniforms.CameraUp := CameraRender.Up;
    ShapeForViewpointMirror.MirrorPlaneUniforms.FrustumDimensions := FrustumDimensions;
  end;

var
  CameraRender: TViewVectors;
  SavedProjectionMatrix, NewProjectionMatrix: TMatrix4;
  Camera: TRenderingCamera;
  SavedViewport: TRectangle;
begin
  if FGLName = GLObjectNone then Exit;

  { calculate matrices to use when rendering,
    using algorithm based on TextureNode.Viewpoint }
  if TextureNode.FdViewpoint.Value is TViewpointMirrorNode then
    GetMatricesForViewpointMirror(
      TViewpointMirrorNode(TextureNode.FdViewpoint.Value),
      CameraRender, NewProjectionMatrix)
  else
  if TextureNode.FdViewpoint.Value is TAbstractViewpointNode then
    GetMatricesForViewpoint(
      TAbstractViewpointNode(TextureNode.FdViewpoint.Value),
      CameraRender, NewProjectionMatrix)
  else
    GetMatricesForViewpoint(
      CurrentViewpoint,
      CameraRender, NewProjectionMatrix);

  TextureNode.EventProjection.Send(NewProjectionMatrix);
  TextureNode.EventViewing.Send(CameraRender.Matrix);
  TextureNode.EventRendering.Send(true);

  Camera := TRenderingCamera.Create;
  try
    Camera.Target := rfRenderedTexture;
    Camera.FromViewVectors(CameraRender, NewProjectionMatrix);

    RenderToTexture.RenderBegin;

      SavedViewport := RenderContext.Viewport;
      RenderContext.Viewport := Rectangle(0, 0, Width, Height);

      SavedProjectionMatrix := RenderContext.ProjectionMatrix;
      RenderContext.ProjectionMatrix := NewProjectionMatrix;

      Render(Camera);

      RenderContext.ProjectionMatrix := SavedProjectionMatrix;
      RenderContext.Viewport := SavedViewport;

    RenderToTexture.RenderEnd;
  finally FreeAndNil(Camera) end;

  if NeedsMipmaps then
    RenderToTexture.GenerateMipmap;

  TextureNode.EventRendering.Send(false);
end;

function TRenderedTextureResource.GLName: TGLTextureId;
begin
  Result := FGLName;
end;

{ TCubeMapTextureResource ------------------------------------------------------ }

function TCubeMapTextureResource.TextureNode: TAbstractEnvironmentTextureNode;
begin
  Result := TAbstractEnvironmentTextureNode(inherited TextureNode);
end;

procedure TCubeMapTextureResource.UnprepareCore;
begin
  if GLName <> GLObjectNone then
  begin
    RendererCache.TextureCubeMap_DecReference(GLName);
    GLName := GLObjectNone;
  end;
end;

function TCubeMapTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := GLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_CUBE_MAP, GLName);
end;

function TCubeMapTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TCubeMapTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

{ TComposedCubeMapTextureResource ---------------------------------------------- }

class function TComposedCubeMapTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TComposedCubeMapTextureNode;
end;

function TComposedCubeMapTextureResource.TextureNode: TComposedCubeMapTextureNode;
begin
  Result := TComposedCubeMapTextureNode(inherited TextureNode);
end;

procedure TComposedCubeMapTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  BackRot, FrontRot, LeftRot, RightRot: TCastleImage;
  GUITexture: boolean;
begin
  if not GLFeatures.TextureCubeMap then
  begin
    WritelnWarning('VRML/X3D', 'Rendering context doesn''t support cube maps, cannot use ComposedCubeMapTexture');
    Exit;
  end;

  if not TextureNode.LoadSides then
  begin
    WritelnWarning('VRML/X3D', 'Not all sides of a CubeMapTexture are correctly set and loaded, cannot use cube map');
    Exit;
  end;

  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    Filter, Anisotropy, GUITexture);

  try
    { To match expected orientation for OpenGL, we have to rotate images.
      (source images are oriented as for VRML Background.)
      We safely cast them to TCastleImage below, SideLoaded above checked
      that they are indeed of TCastleImage class. }
    BackRot  := (TAbstractTexture2DNode(TextureNode.FdBack .Value).TextureImage as TCastleImage).MakeRotated(2);
    FrontRot := (TAbstractTexture2DNode(TextureNode.FdFront.Value).TextureImage as TCastleImage).MakeRotated(2);
    LeftRot  := (TAbstractTexture2DNode(TextureNode.FdLeft .Value).TextureImage as TCastleImage).MakeRotated(2);
    RightRot := (TAbstractTexture2DNode(TextureNode.FdRight.Value).TextureImage as TCastleImage).MakeRotated(2);

    GLName := RendererCache.TextureCubeMap_IncReference(
      { TODO: we could implement TComposedCubeMapTextureNode.TextureUsedFullUrl
        by glueing 6 URLs for 6 sides, and pass it below. }
      '',
      Filter, Anisotropy,
      { positive x } RightRot,
      { negative x } LeftRot,
      { positive y } TAbstractTexture2DNode(TextureNode.FdTop   .Value).TextureImage as TCastleImage,
      { negative y } TAbstractTexture2DNode(TextureNode.FdBottom.Value).TextureImage as TCastleImage,
      { positive z } BackRot,
      { negative z } FrontRot,
      nil);
  finally
    FreeAndNil(BackRot);
    FreeAndNil(FrontRot);
    FreeAndNil(LeftRot);
    FreeAndNil(RightRot);
  end;
end;

{ TImageCubeMapTextureResource ------------------------------------------------- }

class function TImageCubeMapTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TImageCubeMapTextureNode;
end;

function TImageCubeMapTextureResource.TextureNode: TImageCubeMapTextureNode;
begin
  Result := TImageCubeMapTextureNode(inherited TextureNode);
end;

procedure TImageCubeMapTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  GUITexture: boolean;
  Composite: TCompositeImage;
begin
  if not GLFeatures.TextureCubeMap then
  begin
    WritelnWarning('VRML/X3D', 'Rendering context doesn''t support cube maps, cannot use ImageCubeMapTexture');
    Exit;
  end;

  Composite := TextureNode.LoadImage;
  { If TextureNode doesn't contain anything useful, just exit.
    TextureNode.LoadImage already did necessary WritelnWarnings. }
  if Composite = nil then Exit;

  try

    HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
      Filter, Anisotropy, GUITexture);

    { TODO: this is a quick and dirty method:
      - We call LoadImage each time, while load calls should
        be minimized (to avoid loading image many times, but also
        to avoid making repeated warnings in case image fails).
        Should be cached, like for 2D texture nodes.
      - We do not use cube map mipmaps stored inside Composite file.
    }

    GLName := RendererCache.TextureCubeMap_IncReference(
      { TODO: we could implement TImageCubeMapTextureNode.TextureUsedFullUrl and pass it below. }
      '',
      Filter, Anisotropy,
      Composite.CubeMapImage(csPositiveX),
      Composite.CubeMapImage(csNegativeX),
      Composite.CubeMapImage(csPositiveY),
      Composite.CubeMapImage(csNegativeY),
      Composite.CubeMapImage(csPositiveZ),
      Composite.CubeMapImage(csNegativeZ),
      Composite);
  finally FreeAndNil(Composite); end;
end;

{ TGeneratedCubeMapTextureResource --------------------------------------------- }

class function TGeneratedCubeMapTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TGeneratedCubeMapTextureNode;
end;

function TGeneratedCubeMapTextureResource.TextureNode: TGeneratedCubeMapTextureNode;
begin
  Result := TGeneratedCubeMapTextureNode(inherited TextureNode);
end;

procedure TGeneratedCubeMapTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  GUITexture: boolean;
  InitialImage: TCastleImage;
begin
  if not GLFeatures.TextureCubeMap then
  begin
    WritelnWarning('VRML/X3D', 'Rendering context doesn''t support cube maps, cannot use GeneratedCubeMapTexture');
    Exit;
  end;

  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    Filter, Anisotropy, GUITexture);

  { calculate Filter, Anisotropy, NeedsMipmaps }
  NeedsMipmaps := Filter.NeedsMipmaps;
  if NeedsMipmaps and not HasGenerateMipmap then
  begin
    WritelnWarning('VRML/X3D' { This may be caused by OpenGL implementation
      limits, so it may be impossible to predict by VRML author,
      so it's "ignorable" warning. },
      'OpenGL(ES) doesn''t have glGenerateMipmap, so you cannot use mipmaps for GeneratedCubeMapTexture');
    Filter.Minification := minLinear;
    NeedsMipmaps := false;
  end;

  { calculate Size }
  Size := Max(TextureNode.FdSize.Value, 0);
  if not IsCubeMapTextureSized(Size) then
  begin
    Size := ResizeToCubeMapTextureSize(Size);
    WritelnWarning('VRML/X3D' { This may be caused by OpenGL implementation
      limits, so it may be impossible to predict by VRML author,
      so it's "ignorable" warning. },
      Format('Cube map texture size %d is incorrect (cube map texture size must be a power of two, > 0 and <= GL_MAX_CUBE_MAP_TEXTURE_SIZE_ARB = %d), corrected to %d',
        [ TextureNode.FdSize.Value, GLFeatures.MaxCubeMapTextureSize, Size]));
  end;

  InitialImage := TRGBImage.Create(Size, Size);
  try
    InitialImage.URL := 'generated:/' + TextureNode.NiceName;

    { Fill with deliberately stupid (but constant) color,
      to recognize easily GeneratedCubeMapTexture which don't have textures
      updated. }
    if not GLVersion.BuggyGenerateCubeMap then
      InitialImage.Clear(Vector4Byte(255, 0, 255, 255))
    else
      InitialImage.Clear(Vector4Byte(237, 237, 237, 255)); { when buggy, use some reasonable color }

    GLName := RendererCache.TextureCubeMap_IncReference(
      '' { generated texture contents means empty URL; this also prevents sharing textures by TextureCubeMap_IncReference },
      Filter, Anisotropy,
      InitialImage, InitialImage,
      InitialImage, InitialImage,
      InitialImage, InitialImage,
      nil);
  finally FreeAndNil(InitialImage) end;

  RenderToTexture := TGLRenderToTexture.Create(Size, Size);
  RenderToTexture.SetTexture(GLName, GL_TEXTURE_CUBE_MAP_POSITIVE_X);
  RenderToTexture.GLContextOpen;

  { Workaround for NVidia GeForce FX 5200 bug:
    (Confirmed it's needed on Linux, both 32 and 64bit, Kambi's "kocury".
     Confirmed it's *not* needed on Radeon (Linux 32bit, fglrx, Kambi's chantal).)

    Although TextureCubeMap_IncReference (glTextureCubeMap inside) already
    called initial GenerateMipmap (for our InitialImage), it's not enough.
    It seems that assigning texture to FBO destroys it's mipmaps (at least
    their contents).
    So you have to call GenerateMipmap *after* RenderToTexture.GLContextInit
    before showing this texture, to recreate mipmaps.

    To see bug, comment below, and run view3scene on
    demo_models/x3d/cubemap_generated_recursive.x3dv
    Before pressing [space] (which triggers Update method), teapots
    (or any other objects, reproducible with various IndexedFaceSets)
    will have seemingly random mipmaps (base level 0 is Ok, RGB(255,0,255),
    but mipmaps are seemingly filled with random garbage).
    Line below fixes it at negligible cost (we'll generate mipmaps at loading
    one more time than necessary). Other fix that works is to move
    RenderToTexture.GLContextOpen to first Update call, but this obfuscates code. }
  if (GLVersion.VendorType = gvNvidia) and NeedsMipmaps then
  begin
    RenderToTexture.CompleteTextureTarget := GL_TEXTURE_CUBE_MAP;
    RenderToTexture.GenerateMipmap;
  end;
end;

procedure TGeneratedCubeMapTextureResource.UnprepareCore;
begin
  FreeAndNil(RenderToTexture);
  inherited;
end;

procedure TGeneratedCubeMapTextureResource.Update(
  const Render: TRenderFromViewFunction;
  const ProjectionNear, ProjectionFar: Single;
  const CubeMiddle: TVector3);
begin
  if GLName = GLObjectNone then Exit;

  if GLVersion.BuggyGenerateCubeMap then Exit;

  GLCaptureCubeMapTexture(GLName, Size,
    CubeMiddle,
    Render, ProjectionNear, ProjectionFar,
    RenderToTexture);

  if NeedsMipmaps then
    RenderToTexture.GenerateMipmap;
end;

{ T3DTextureResource ----------------------------------------------------------- }

class function T3DTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TAbstractTexture3DNode;
end;

function T3DTextureResource.TextureNode: TAbstractTexture3DNode;
begin
  Result := TAbstractTexture3DNode(inherited TextureNode);
end;

procedure T3DTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  Filter: TTextureFilter;
  Anisotropy: TGLfloat;
  BoundaryModeS: TGLenum;
  BoundaryModeT: TGLenum;
  BoundaryModeR: TGLenum;
  GUITexture: boolean;
  TextureWrap: TTextureWrap3D;
begin
  if not GLFeatures.Texture3D then
  begin
    WritelnWarning('VRML/X3D', 'Rendering context doesn''t support 3D textures, cannot use Texture3D nodes');
    Exit;
  end;

  TextureNode.TextureLoaded := true;

  { If TextureImage doesn't contain anything useful, just exit.
    Setting TextureLoaded already did necessary WritelnWarnings. }
  if TextureNode.TextureImage = nil then Exit;

  HandleTextureProperties(TextureNode.TextureProperties, RenderOptions,
    TextureRepeatToGL(TextureNode.FdRepeatS.Value), TextureRepeatToGL(TextureNode.FdRepeatT.Value),
    TextureRepeatToGL(TextureNode.FdRepeatR.Value), Filter, BoundaryModeS, BoundaryModeT, BoundaryModeR, Anisotropy, GUITexture);

  { calculate TextureWrap }
  TextureWrap.Data[0] := BoundaryModeS;
  TextureWrap.Data[1] := BoundaryModeT;
  TextureWrap.Data[2] := BoundaryModeR;

  GLName := RendererCache.Texture3D_IncReference(
    { TODO: We could implement TAbstractTexture3DNode.TextureUsedFullUrl }
    '',
    Filter, Anisotropy,
    TextureWrap, TextureNode.TextureImage, TextureNode.TextureComposite);
end;

procedure T3DTextureResource.UnprepareCore;
begin
  if GLName <> GLObjectNone then
  begin
    RendererCache.Texture3D_DecReference(GLName);
    GLName := GLObjectNone;
  end;
end;

function T3DTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := GLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_3D, GLName);
end;

function T3DTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function T3DTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

{ TShadowMapAtlas ------------------------------------------------------------ }

var
  { The shadow map atlas shared by all TGeneratedShadowMapResource
    (with InAtlas), created when needed, freed when the OpenGL context
    is closed: it is kept when unused, as lights often start and stop
    casting shadows (e.g. switching to the strongest light near the player). }
  ShadowMapAtlas: TShadowMapAtlas;

procedure ShadowMapAtlasContextClose;
begin
  FreeAndNil(ShadowMapAtlas);
end;

constructor TShadowMapAtlas.Create(const ASize: Cardinal);
var
  Levels, I: Integer;
  Wrap: TTextureWrap2D;
begin
  inherited Create;
  Size := ASize;
  Levels := Biggest2Exponent(Size div MinBlockSize) + 1;
  SetLength(FreeBlocks, Levels);
  for I := 0 to Levels - 1 do
    FreeBlocks[I] := TRectangleList.Create;
  FreeBlocks[0].Add(Rectangle(0, 0, Size, Size));

  { Clamp to the edge: outside of the texture is never sampled anyway,
    the tiles are clamped in the shaders. }
  Wrap.Data[0] := GLFeatures.CLAMP_TO_EDGE;
  Wrap.Data[1] := GLFeatures.CLAMP_TO_EDGE;
  GLName := RendererCache.TextureDepth_IncReference('', Wrap, Size, Size);

  RenderToTexture := TGLRenderToTexture.Create(Size, Size);
  RenderToTexture.SetTexture(GLName, GL_TEXTURE_2D);
  RenderToTexture.Buffer := tbDepth;
  RenderToTexture.Stencil := false;
  RenderToTexture.GLContextOpen;

  WritelnLog('Shadow Maps', 'Created shadow map atlas %d x %d', [Size, Size]);
end;

destructor TShadowMapAtlas.Destroy;
var
  I: Integer;
begin
  FreeAndNil(RenderToTexture);
  if GLName <> GLObjectNone then
  begin
    RendererCache.TextureDepth_DecReference(GLName);
    GLName := GLObjectNone;
  end;
  for I := 0 to Length(FreeBlocks) - 1 do
    FreeAndNil(FreeBlocks[I]);
  inherited;
end;

function TShadowMapAtlas.BlockLevel(const BlockSize: Cardinal): Integer;
begin
  Result := Biggest2Exponent(Size div BlockSize);
end;

function TShadowMapAtlas.FindFree(const Level: Integer; const R: TRectangle): Integer;
var
  I: Integer;
begin
  for I := 0 to FreeBlocks[Level].Count - 1 do
    if FreeBlocks[Level].L[I].Equals(R) then
      Exit(I);
  Result := -1;
end;

function TShadowMapAtlas.Allocate(const BlockSize: Cardinal; out Rect: TRectangle): Boolean;
var
  Level: Integer;
  Parent: TRectangle;
  Half: Integer;
begin
  if (BlockSize > Size) or (BlockSize < MinBlockSize) then
    Exit(false);
  Level := BlockLevel(BlockSize);
  if FreeBlocks[Level].Count <> 0 then
  begin
    Rect := FreeBlocks[Level].L[FreeBlocks[Level].Count - 1];
    FreeBlocks[Level].Delete(FreeBlocks[Level].Count - 1);
    Exit(true);
  end;
  { split a 2x larger block into 4 }
  Result := Allocate(BlockSize * 2, Parent);
  if Result then
  begin
    Half := BlockSize;
    Rect := Rectangle(Parent.Left, Parent.Bottom, Half, Half);
    FreeBlocks[Level].Add(Rectangle(Parent.Left + Half, Parent.Bottom       , Half, Half));
    FreeBlocks[Level].Add(Rectangle(Parent.Left       , Parent.Bottom + Half, Half, Half));
    FreeBlocks[Level].Add(Rectangle(Parent.Left + Half, Parent.Bottom + Half, Half, Half));
  end;
end;

procedure TShadowMapAtlas.Release(const Rect: TRectangle);
var
  Level, I, ParentSize, Found: Integer;
  Parent, Sibling: TRectangle;
  Siblings: array [0..2] of Integer;
  SiblingCount: Integer;
begin
  Level := BlockLevel(Rect.Width);
  if Level = 0 then
  begin
    FreeBlocks[0].Add(Rect);
    Exit;
  end;
  { merge with the 3 other quarters of the parent block, when they are free }
  ParentSize := Rect.Width * 2;
  Parent := Rectangle(
    (Rect.Left div ParentSize) * ParentSize,
    (Rect.Bottom div ParentSize) * ParentSize,
    ParentSize, ParentSize);
  SiblingCount := 0;
  for I := 0 to 3 do
  begin
    Sibling := Rectangle(
      Parent.Left + (I mod 2) * Rect.Width,
      Parent.Bottom + (I div 2) * Rect.Width,
      Rect.Width, Rect.Width);
    if Sibling.Equals(Rect) then
      Continue;
    Found := FindFree(Level, Sibling);
    if Found = -1 then
    begin
      FreeBlocks[Level].Add(Rect);
      Exit;
    end;
    Siblings[SiblingCount] := Found;
    Inc(SiblingCount);
  end;
  { remove the siblings from the free list, highest index first }
  for I := 0 to 2 do
  begin
    Found := MaxIntValue([Siblings[0], Siblings[1], Siblings[2]]);
    FreeBlocks[Level].Delete(Found);
    if Siblings[0] = Found then Siblings[0] := -1 else
    if Siblings[1] = Found then Siblings[1] := -1 else
      Siblings[2] := -1;
  end;
  Release(Parent);
end;

{ TGeneratedShadowMapResource ------------------------------------------------------ }

class function TGeneratedShadowMapResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TGeneratedShadowMapNode;
end;

function TGeneratedShadowMapResource.TextureNode: TGeneratedShadowMapNode;
begin
  Result := TGeneratedShadowMapNode(inherited TextureNode);
end;

class function TGeneratedShadowMapResource.ClassVarianceShadowMaps(
  RenderOptions: TCastleRenderOptions): boolean;
begin
  Result :=
    (RenderOptions.ShadowSampling = ssVarianceShadowMaps) and
    GLFeatures.Shaders and
    GLFeatures.TextureFloat;
end;

procedure TGeneratedShadowMapResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
var
  AtlasSize: Cardinal;
  ATileCount: Integer;
begin
  // in fixed-function, do not create shadow maps, do not render to shadow maps
  if GLFeatures.EnableFixedFunction then Exit;

  { Float texture extensions: there is also NV_float_buffer,
    which is the only way for a float texture on old nvidia GPUs.
    But it's only for NV_texture_rectangle, without bilinear filtering
    or mipmapping, so it's not useful for VSM at all. }

  VarianceShadowMaps := ClassVarianceShadowMaps(RenderOptions);

  WritelnLog('Shadows', Format('Variance Shadow Maps used: %s (Reasons: RenderOptions.Shadow sampling = %s, GLSL support = %s, texture_float support = %s)', [
    BoolToStr(VarianceShadowMaps, true),
    ShadowSamplingNames[RenderOptions.ShadowSampling],
    BoolToStr(GLFeatures.Shaders, true),
    BoolToStr(GLFeatures.TextureFloat, true)
  ]));

  Size := Max(TextureNode.FdSize.Value, 1);

  { At least in case of float textures for VSM, CLAMP_TO_EDGE is needed
    (instead of standard clamp to border). Didn't see any difference
    for depth textures. }
  TextureWrap.Data[0] := GLFeatures.CLAMP_TO_EDGE;
  TextureWrap.Data[1] := GLFeatures.CLAMP_TO_EDGE;

  { calculate Filter, NeedsMipmaps }
  Filter.Magnification := magLinear;
  if VarianceShadowMaps and HasGenerateMipmap then
  begin
    NeedsMipmaps := true;
    Filter.Minification := minLinearMipmapLinear;
  end else
  begin
    NeedsMipmaps := false;
    Filter.Minification := minLinear;
  end;

  if TextureNode.CompareMode <> smCompareRLEqual then
    WritelnWarning('VRML/X3D', 'Only the standard GeneratedShadowMap.compareMode value, "COMPARE_R_LEQUAL" (in Pascal: smCompareRLEqual), is supported now. This is the only value sensible for shadow maps.');

  if (not VarianceShadowMaps) and (not GLFeatures.TextureDepthCompare) then
  begin
    WritelnWarning('VRML/X3D', 'Shadow maps not supported. OpenGL(ES) doesn''t support shadow samplers with comparison (TextureDepthCompare), cannot use GeneratedShadowMap nodes.');
    Exit;
  end;

  { The shared atlas, for depth shadow maps. }
  AtlasSize := Min(ShadowMapsAtlasSize, GLFeatures.MaxTextureSize);
  AtlasSize := Min(AtlasSize, GLFeatures.MaxViewportDimensions.X);
  AtlasSize := Min(AtlasSize, GLFeatures.MaxViewportDimensions.Y);
  AtlasSize := BiggestPowerOf2(AtlasSize);
  InAtlas := (not VarianceShadowMaps) and (AtlasSize >= TShadowMapAtlas.MinBlockSize);
  if InAtlas then
  begin
    if ShadowMapAtlas = nil then
      ShadowMapAtlas := TShadowMapAtlas.Create(AtlasSize);
    Inc(ShadowMapAtlas.UserCount);
  end;

  { Allocate the tiles now (so GLName is valid), the light is already known. }
  ATileCount := 1;
  if TextureNode.FdLight.Value is TAbstractPunctualLightNode then
    TShadowMapShader.ShadowMapKind(TAbstractPunctualLightNode(TextureNode.FdLight.Value), ATileCount);
  AllocateTiles(ATileCount);
end;

procedure TGeneratedShadowMapResource.FreeTiles;
var
  I: Integer;
begin
  if InAtlas then
  begin
    for I := 0 to Length(AtlasRects) - 1 do
      ShadowMapAtlas.Release(AtlasRects[I]);
    SetLength(AtlasRects, 0);
  end else
  begin
    FreeAndNil(RenderToTexture);
    if FGLName <> GLObjectNone then
    begin
      if VarianceShadowMaps then
        RendererCache.TextureFloat_DecReference(FGLName)
      else
        RendererCache.TextureDepth_DecReference(FGLName);
      FGLName := GLObjectNone;
    end;
  end;
  TileCount := 0;
end;

procedure TGeneratedShadowMapResource.AllocateTiles(const ATileCount: Integer);

  { Allocate ATileCount tiles of TileSize in the atlas,
    halving TileSize when they don't fit. }
  function AllocateInAtlas: Boolean;
  var
    I: Integer;
  begin
    TileSize := Smallest2Power(EffectiveSize);
    while TileSize >= TShadowMapAtlas.MinBlockSize do
    begin
      SetLength(AtlasRects, 0);
      I := 0;
      while I < ATileCount do
      begin
        SetLength(AtlasRects, I + 1);
        if not ShadowMapAtlas.Allocate(TileSize, AtlasRects[I]) then
          Break;
        Inc(I);
      end;
      if I = ATileCount then
      begin
        if TileSize < Smallest2Power(EffectiveSize) then
          WritelnWarning('Shadow Maps', 'Shadow map "%s" does not fit in the shadow map atlas (ShadowMapsAtlasSize), using %d instead of %d', [
            TextureNode.NiceName, TileSize, Size]);
        Exit(true);
      end;
      { release what was allocated, try smaller }
      SetLength(AtlasRects, I);
      while I > 0 do
      begin
        Dec(I);
        ShadowMapAtlas.Release(AtlasRects[I]);
      end;
      SetLength(AtlasRects, 0);
      TileSize := TileSize div 2;
    end;
    Result := false;
  end;

var
  Columns, Rows: Integer;
begin
  if (TileCount = ATileCount) and (TileCount <> 0) and
     (AllocatedSize = EffectiveSize) then
    Exit;
  FreeTiles;
  AllocatedSize := EffectiveSize;

  if InAtlas then
  begin
    if AllocateInAtlas then
    begin
      TileCount := ATileCount;
      TextureWidth := ShadowMapAtlas.Size;
      TextureHeight := ShadowMapAtlas.Size;
      Exit;
    end;
    WritelnWarning('Shadow Maps', 'Shadow map "%s" does not fit in the shadow map atlas (ShadowMapsAtlasSize), using its own texture', [
      TextureNode.NiceName]);
    Dec(ShadowMapAtlas.UserCount);
    InAtlas := false;
  end;

  { Own texture, with the tiles in a grid. }
  TileSize := EffectiveSize;
  Columns := Ceil(Sqrt(ATileCount));
  Rows := DivRoundUp(ATileCount, Columns);
  TextureWidth := TileSize * Columns;
  TextureHeight := TileSize * Rows;
  if VarianceShadowMaps then
    FGLName := RendererCache.TextureFloat_IncReference(
      '' { generated texture contents means empty URL },
      Filter, TextureWrap, TextureWidth, TextureHeight, true)
  else
    FGLName := RendererCache.TextureDepth_IncReference(
      '' { generated texture contents means empty URL },
      TextureWrap, TextureWidth, TextureHeight);

  RenderToTexture := TGLRenderToTexture.Create(TextureWidth, TextureHeight);
  RenderToTexture.SetTexture(FGLName, GL_TEXTURE_2D);
  if VarianceShadowMaps then
    RenderToTexture.Buffer := tbColor
  else
    RenderToTexture.Buffer := tbDepth;
  RenderToTexture.Stencil := false;
  RenderToTexture.GLContextOpen;
  TileCount := ATileCount;
end;

function TGeneratedShadowMapResource.EffectiveSize: Cardinal;
begin
  if (ScreenSize <> 0) and (ScreenSize < Size) then
    Result := ScreenSize
  else
    Result := Size;
end;

function TGeneratedShadowMapResource.ChooseScreenSize(
  const Light: TAbstractPunctualLightNode;
  const Camera: TCastleCamera; const WorldBox: TBox3D): Boolean;
const
  { Go to a smaller size only when the light needs 20% less than it:
    the size doesn't switch back and forth when the camera moves a bit. }
  Hysteresis = 0.8;
var
  NewSize, Current, MaxSize, MinSize: Cardinal;
  Range, MinDistance, MaxDistance, Distance, Coverage, Ideal: Single;
  Projection: TMatrix4;
begin
  NewSize := 0;
  if ShadowMapsSizeByScreen and
     (Camera <> nil) and
     (Light is TAbstractPositionalLightNode) then
  begin
    { the range of the light: a sphere around it }
    Range := 0;
    if TAbstractPositionalLightNode(Light).HasRadius and
       (TAbstractPositionalLightNode(Light).Radius > 0) then
      Range := TAbstractPositionalLightNode(Light).Radius;
    if Light.FdProjectionFar.Value > 0 then
    begin
      if Range > 0 then
        Range := Min(Range, Light.FdProjectionFar.Value)
      else
        Range := Light.FdProjectionFar.Value;
    end;
    if (Range <= 0) and not WorldBox.IsEmpty then
    begin
      Light.Box3DDistances(WorldBox, MinDistance, MaxDistance);
      Range := MaxDistance;
    end;

    if Range > 0 then
    begin
      { How much of the screen height the sphere covers (1 = all of it). }
      Projection := Camera.ProjectionMatrix;
      Distance := PointsDistance(Camera.WorldTranslation, Light.ProjectionWorldLocation);
      if Projection.Data[3, 3] = 1 then
        Coverage := Projection.Data[1, 1] * Range // orthographic
      else
      if Distance <= Range then
        Coverage := 1 // inside the range
      else
        Coverage := Projection.Data[1, 1] * Range / Sqrt(Sqr(Distance) - Sqr(Range));

      MaxSize := Smallest2Power(Size);
      MinSize := Min(MaxSize, Max(Smallest2Power(Max(ShadowMapsMinSizeByScreen, 1)),
        TShadowMapAtlas.MinBlockSize));
      Ideal := Size * Min(Coverage, 1);
      if Ideal >= MaxSize then
        NewSize := MaxSize
      else
        NewSize := Max(MinSize, Smallest2Power(Max(Ceil(Ideal), 1)));
      NewSize := Min(NewSize, MaxSize);

      { hysteresis }
      Current := ScreenSize;
      if Current = 0 then
        Current := MaxSize;
      if (NewSize < Current) and (Ideal > Hysteresis * (Current div 2)) then
        NewSize := Current;
      if NewSize = MaxSize then
        NewSize := 0; // as without ShadowMapsSizeByScreen
    end;
  end;

  Result := NewSize <> ScreenSize;
  ScreenSize := NewSize;
end;

function TGeneratedShadowMapResource.TileRect(const Index: Integer): TRectangle;
var
  Columns: Integer;
begin
  if InAtlas then
    Result := AtlasRects[Index]
  else
  begin
    Columns := TextureWidth div TileSize;
    Result := Rectangle(
      (Index mod Columns) * TileSize,
      (Index div Columns) * TileSize,
      TileSize, TileSize);
  end;
end;

procedure TGeneratedShadowMapResource.UnprepareCore;
begin
  FreeTiles;
  if InAtlas then
  begin
    Dec(ShadowMapAtlas.UserCount);
    InAtlas := false;
  end;
end;

function TGeneratedShadowMapResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := GLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_2D, GLName);
end;

function TGeneratedShadowMapResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  if not WarninigDoneCannotEnable then
  begin
    WarninigDoneCannotEnable := true;
    WritelnWarning('Not supported anymore: GeneratedShadowMap placed directly within Appearance.textures of a shadow receiver. Use instead Appearance.receiveShadows or light.shadows to activate shadow maps.');
  end;
end;

procedure TGeneratedShadowMapResource.Update(
  const Render: TRenderFromViewFunction;
  const Light: TAbstractPunctualLightNode;
  const Camera: TCastleCamera;
  const WorldBox: TBox3D);
type
  TTileView = record
    View: TViewVectors;
    Projection: TMatrix4;
    NormalOffset: Single;
  end;
var
  Views: array of TTileView;
  Splits: TVector4;

  { The 6 cube faces around a point light. }
  procedure PointLightViews;
  const
    FaceDirections: array [0..5] of TVector3 = (
      (X:  1; Y:  0; Z:  0), (X: -1; Y:  0; Z:  0),
      (X:  0; Y:  1; Z:  0), (X:  0; Y: -1; Z:  0),
      (X:  0; Y:  0; Z:  1), (X:  0; Y:  0; Z: -1)
    );
    FaceUps: array [0..5] of TVector3 = (
      (X: 0; Y: 1; Z:  0), (X: 0; Y: 1; Z: 0),
      (X: 0; Y: 0; Z: -1), (X: 0; Y: 0; Z: 1),
      (X: 0; Y: 1; Z:  0), (X: 0; Y: 1; Z: 0)
    );
  var
    Position: TVector3;
    ProjectionNear, ProjectionFar, MinDistance, MaxDistance, TanHalf: Single;
    I: Integer;
    Projection: TMatrix4;
  begin
    Position := Light.ProjectionWorldLocation;
    TextureNode.InternalLightPosition := Position;

    { The range: projectionNear / Far when set,
      otherwise to the farthest point of the world, within the light's radius. }
    ProjectionFar := Light.FdProjectionFar.Value;
    if ProjectionFar <= 0 then
    begin
      if not WorldBox.IsEmpty then
      begin
        Light.Box3DDistances(WorldBox, MinDistance, MaxDistance);
        ProjectionFar := MaxDistance;
      end;
      if (Light is TAbstractPositionalLightNode) and
         TAbstractPositionalLightNode(Light).HasRadius and
         (TAbstractPositionalLightNode(Light).Radius > 0) then
      begin
        if ProjectionFar <= 0 then
          ProjectionFar := TAbstractPositionalLightNode(Light).Radius
        else
          ProjectionFar := Min(ProjectionFar, TAbstractPositionalLightNode(Light).Radius);
      end;
      if ProjectionFar <= 0 then
        ProjectionFar := 100;
    end;
    { A larger near gives more depth precision, without it the surfaces
      facing the light are often in their own shadow (shadow acne). }
    ProjectionNear := Light.FdProjectionNear.Value;
    if (ProjectionNear <= 0) or (ProjectionNear >= ProjectionFar) then
      ProjectionNear := ProjectionFar / 250;

    { A bit wider than 90 degrees: the filtering (PCF) near the edges
      of the faces stays inside them. }
    TanHalf := 1 + 5 / TileSize;
    Projection := PerspectiveProjectionMatrixRad(2 * ArcTan(TanHalf), 1,
      ProjectionNear, ProjectionFar);

    SetLength(Views, 6);
    for I := 0 to 5 do
    begin
      Views[I].View.Translation := Position;
      Views[I].View.Direction := FaceDirections[I];
      Views[I].View.Up := FaceUps[I];
      Views[I].Projection := Projection;
      { 1.5 texels, per unit of distance from the light }
      Views[I].NormalOffset := 1.5 * 2 * TanHalf / TileSize;
    end;
  end;

  { One view, like a spot light or a directional light
    with projectionXxx fields.
    The projection fields left 0 (not calculated by CastleInternalShadowMaps,
    for global lights) are calculated from the whole world here. }
  procedure SingleView;
  var
    ProjectionNear, ProjectionFar, MinDistance, MaxDistance: Single;
    Pos, Dir, Side, Up, MinCorner, MaxCorner, ProjectionLocation: TVector3;
    ProjectionRectangle: TFloatRectangle;
  begin
    SetLength(Views, 1);
    Light.GetView(Views[0].View);
    Views[0].Projection := Light.ProjectionMatrix;
    Views[0].NormalOffset := 0; // not used by smkSingle shaders

    if WorldBox.IsEmpty then
      Exit;

    if (Light is TAbstractDirectionalLightNode) and
       TAbstractDirectionalLightNode(Light).FdProjectionRectangle.Value.IsPerfectlyZero then
    begin
      { Like AutoCalculateProjectionForDirectionalLight in CastleInternalShadowMaps,
        for the whole world. }
      Light.GetView(Pos, Dir, Side, Up);
      MinCorner := WorldBox.MinimumCorner(Dir);
      MaxCorner := WorldBox.MaximumCorner(Dir);
      ProjectionLocation := MinCorner * 2 - MaxCorner;
      ProjectionRectangle := WorldBox.OrthoProject(ProjectionLocation, Dir, Side, Up);
      WorldBox.DirectionDistances(ProjectionLocation, Dir, MinDistance, MaxDistance);
      ProjectionFar := Max(MaxDistance, 0) * 2;
      ProjectionNear := Max(Max(MinDistance, 0) / 2, ProjectionFar * 0.001);
      if ProjectionFar <= 0 then
        Exit;
      Views[0].View.Translation := ProjectionLocation;
      Views[0].Projection := OrthoProjectionMatrix(ProjectionRectangle,
        ProjectionNear, ProjectionFar);
    end else
    if (Light is TSpotLightNode) and
       ((Light.FdProjectionNear.Value = 0) or (Light.FdProjectionFar.Value = 0)) then
    begin
      { Like AutoCalculateProjectionNearFar in CastleInternalShadowMaps,
        for the whole world. }
      Light.Box3DDistances(WorldBox, MinDistance, MaxDistance);
      ProjectionFar := Light.FdProjectionFar.Value;
      if ProjectionFar = 0 then
        ProjectionFar := Max(MaxDistance, 0) * 2;
      if ProjectionFar <= 0 then
        Exit;
      ProjectionNear := Light.FdProjectionNear.Value;
      if ProjectionNear = 0 then
        ProjectionNear := Max(Max(MinDistance, 0) / 2, ProjectionFar * 0.001);
      Views[0].Projection := PerspectiveProjectionMatrixRad(
        TSpotLightNode(Light).EffectiveProjectionAngle, 1,
        ProjectionNear, ProjectionFar);
    end;
  end;

  { Cascades of a directional light, following the camera. }
  procedure CascadeViews(const Count: Integer);
  const
    { Mix of logarithmic (1) and uniform (0) splits. }
    SplitLambda = 0.75;
  var
    CameraView: TViewVectors;
    CameraSide, Center, Corner, LightDir, LightSide, LightUp: TVector3;
    CameraProjection: TMatrix4;
    Orthographic: Boolean;
    CameraNear, CameraFar, MinDistance, MaxDistance: Single;
    SliceNear, SliceFar, CoverNear, PreviousNear, Blend: Single;
    D, Radius, Texel, CX, CY, CZ, ZMin, ZMax: Single;
    HalfX, HalfY, OffsetX, OffsetY: Single;
    Corners: array [0..7] of TVector3;
    I, J: Integer;
    BoxCorners: TBoxCorners;
  begin
    SetLength(Views, Count);
    Splits := Vector4(MaxSingle, MaxSingle, MaxSingle, MaxSingle);
    if Camera = nil then
    begin
      { no camera to follow: every cascade like a single view }
      for I := 0 to Count - 1 do
      begin
        Light.GetView(Views[I].View);
        Views[I].Projection := Light.ProjectionMatrix;
        Views[I].NormalOffset := 0;
      end;
      Exit;
    end;

    Light.GetView(Views[0].View);
    LightDir := Views[0].View.Direction.Normalize;
    LightUp := Views[0].View.Up.Normalize;
    LightSide := TVector3.CrossProduct(LightDir, LightUp).Normalize;

    CameraView := Camera.WorldView;
    CameraView.Direction := CameraView.Direction.Normalize;
    CameraView.Up := CameraView.Up.Normalize;
    CameraSide := TVector3.CrossProduct(CameraView.Direction, CameraView.Up).Normalize;
    CameraProjection := Camera.ProjectionMatrix;
    Orthographic := CameraProjection.Data[3, 3] = 1;
    HalfX := 1 / CameraProjection.Data[0, 0];
    HalfY := 1 / CameraProjection.Data[1, 1];
    if Orthographic then
    begin
      OffsetX := -CameraProjection.Data[3, 0] * HalfX;
      OffsetY := -CameraProjection.Data[3, 1] * HalfY;
    end else
    begin
      OffsetX := 0;
      OffsetY := 0;
    end;

    CameraNear := Max(Camera.EffectiveProjectionNear, 0.001);
    CameraFar := TAbstractDirectionalLightNode(Light).ShadowCascadesDistance;
    if CameraFar <= 0 then
    begin
      CameraFar := 0;
      if not WorldBox.IsEmpty then
      begin
        WorldBox.PointDistances(CameraView.Translation, MinDistance, MaxDistance);
        CameraFar := MaxDistance;
      end;
      if (Camera.EffectiveProjectionFar > 0) and
         (Camera.EffectiveProjectionFar <> ZFarInfinity) then
        CameraFar := Min(CameraFar, Camera.EffectiveProjectionFar);
    end;
    if CameraFar <= CameraNear then
      CameraFar := CameraNear * 100;

    if WorldBox.IsEmpty then
      FillChar(BoxCorners, SizeOf(BoxCorners), 0)
    else
      WorldBox.Corners(BoxCorners);

    Blend := Clamped(ShadowMapsCascadeBlend, 0.0, 1.0);
    SliceNear := CameraNear;
    PreviousNear := CameraNear;
    for I := 0 to Count - 1 do
    begin
      { The shaders blend the end of the previous cascade with this one:
        this one covers that part too. }
      CoverNear := Max(CameraNear, SliceNear - (SliceNear - PreviousNear) * Blend);
      SliceFar :=
        SplitLambda * CameraNear * Power(CameraFar / CameraNear, (I + 1) / Count) +
        (1 - SplitLambda) * (CameraNear + (CameraFar - CameraNear) * (I + 1) / Count);
      Splits.Data[I] := SliceFar;

      { the corners of this slice of the camera frustum, in world space }
      for J := 0 to 7 do
      begin
        if J < 4 then D := CoverNear else D := SliceFar;
        if Orthographic then
          Corner := Vector3(
            OffsetX + HalfX * (2 * (J mod 2) - 1),
            OffsetY + HalfY * (2 * ((J div 2) mod 2) - 1),
            D)
        else
          Corner := Vector3(
            D * HalfX * (2 * (J mod 2) - 1),
            D * HalfY * (2 * ((J div 2) mod 2) - 1),
            D);
        Corners[J] := CameraView.Translation +
          CameraSide * Corner.X + CameraView.Up * Corner.Y +
          CameraView.Direction * Corner.Z;
      end;

      { a sphere around the slice: its size doesn't change
        when the camera turns, so the shadows don't shimmer }
      Center := TVector3.Zero;
      for J := 0 to 7 do
        Center := Center + Corners[J];
      Center := Center / 8;
      Radius := 0;
      for J := 0 to 7 do
        Radius := Max(Radius, PointsDistance(Center, Corners[J]));
      Radius := Ceil(Radius * 16) / 16;

      { snap the center to the texels of the shadow map:
        the shadows don't shimmer when the camera moves }
      Texel := 2 * Radius / TileSize;
      CX := Floor(TVector3.DotProduct(Center, LightSide) / Texel) * Texel;
      CY := Floor(TVector3.DotProduct(Center, LightUp) / Texel) * Texel;
      CZ := TVector3.DotProduct(Center, LightDir);

      { the depth range: all the world (the casters) along the light }
      ZMin := CZ - Radius;
      ZMax := CZ + Radius;
      if not WorldBox.IsEmpty then
        for J := 0 to 7 do
        begin
          D := TVector3.DotProduct(BoxCorners[J], LightDir);
          ZMin := Min(ZMin, D);
          ZMax := Max(ZMax, D);
        end;

      Views[I].View.Translation :=
        LightSide * CX + LightUp * CY + LightDir * (ZMin - 1);
      Views[I].View.Direction := LightDir;
      Views[I].View.Up := LightUp;
      Views[I].Projection := OrthoProjectionMatrix(
        FloatRectangle(-Radius, -Radius, 2 * Radius, 2 * Radius),
        0.5, ZMax - ZMin + 2);
      Views[I].NormalOffset := 1.5 * Texel;

      PreviousNear := SliceNear;
      SliceNear := SliceFar;
    end;
  end;

var
  Kind: TShadowMapKind;
  ATileCount, I: Integer;
  SavedProjectionMatrix: TMatrix4;
  SavedViewport, Tile: TRectangle;
  SavedViewportDelta: TVector2Integer;
  RenderingCamera: TRenderingCamera;
  SavedPolygonOffset: TPolygonOffset;
  RTT: TGLRenderToTexture;
begin
  Kind := TShadowMapShader.ShadowMapKind(Light, ATileCount);
  AllocateTiles(ATileCount);
  if GLName = GLObjectNone then Exit;
  if Kind = smkCascades then
    CascadesCamera := Camera;

  Splits := Vector4(MaxSingle, MaxSingle, MaxSingle, MaxSingle);
  case Kind of
    smkPoint: PointLightViews;
    smkCascades: CascadeViews(ATileCount);
    else SingleView;
  end;

  if InAtlas then
    RTT := ShadowMapAtlas.RenderToTexture
  else
    RTT := RenderToTexture;

  RenderingCamera := TRenderingCamera.Create;
  try
    if VarianceShadowMaps then
      RenderingCamera.Target := rtVarianceShadowMap
    else
      RenderingCamera.Target := rtShadowMap;

    RTT.RenderBegin;

      SavedViewport := RenderContext.Viewport;
      SavedViewportDelta := RenderContext.ViewportDelta;
      SavedProjectionMatrix := RenderContext.ProjectionMatrix;
      SavedPolygonOffset := RenderContext.PolygonOffset;
      RenderContext.ViewportDelta := TVector2Integer.Zero;
      RenderContext.InternalControlRectIgnore := RenderContext.InternalControlRectIgnore + 1;

      { Enable polygon offset for everything (whole scene).

        VarianceShadowMaps notes: can offset be avoided in this case?
        Practice (on "ATI Mobility Radeon HD 4300 Series") shows that
        offset is still needed for VSM. Without offset, VSM has some noise,
        and sunny_street demos have noise on walls. With offset, VSM is perfect. }
      RenderContext.PolygonOffsetEnable(TextureNode.FdScale.Value, TextureNode.FdBias.Value);

      for I := 0 to ATileCount - 1 do
      begin
        { The scissor limits what the rendering clears to this tile. }
        Tile := TileRect(I);
        RenderContext.Viewport := Tile;
        RenderContext.ScissorEnable(Tile);
        RenderContext.ProjectionMatrix := Views[I].Projection;
        RenderingCamera.FromViewVectors(Views[I].View, Views[I].Projection);
        Render(RenderingCamera);
        RenderContext.ScissorDisable;
      end;

      RenderContext.PolygonOffset := SavedPolygonOffset;
      RenderContext.InternalControlRectIgnore := RenderContext.InternalControlRectIgnore - 1;
      RenderContext.ProjectionMatrix := SavedProjectionMatrix;
      RenderContext.ViewportDelta := SavedViewportDelta;
      RenderContext.Viewport := SavedViewport;

    RTT.RenderEnd;

  finally FreeAndNil(RenderingCamera) end;

  if NeedsMipmaps then
    RTT.GenerateMipmap;

  { remember the views for the shaders of the shadow receivers }
  if Length(TextureNode.InternalTiles) < ATileCount then
    SetLength(TextureNode.InternalTiles, ATileCount);
  for I := 0 to ATileCount - 1 do
  begin
    Tile := TileRect(I);
    TextureNode.InternalTiles[I].ViewProjection :=
      Views[I].Projection * Views[I].View.Matrix;
    TextureNode.InternalTiles[I].NormalOffset := Views[I].NormalOffset;
    TextureNode.InternalTiles[I].Rect := Vector4(
      Tile.Left / TextureWidth,
      Tile.Bottom / TextureHeight,
      (Tile.Left + Integer(Tile.Width)) / TextureWidth,
      (Tile.Bottom + Integer(Tile.Height)) / TextureHeight);
  end;
  TextureNode.InternalTileCount := ATileCount;
  TextureNode.InternalCascadeSplits := Splits;
  TextureNode.InternalTexelSize := Vector2(1 / TextureWidth, 1 / TextureHeight);
end;

function TGeneratedShadowMapResource.GLName: TGLTextureId;
begin
  if InAtlas then
  begin
    if ShadowMapAtlas <> nil then
      Result := ShadowMapAtlas.GLName
    else
      Result := GLObjectNone;
  end else
    Result := FGLName;
end;

{ TShaderTextureResource ------------------------------------------------------ }

class function TShaderTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TShaderTextureNode;
end;

procedure TShaderTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
begin
  { no need to do anything }
end;

procedure TShaderTextureResource.UnprepareCore;
begin
  { no need to do anything }
end;

function TShaderTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := true;
  { no need to actually do anything }

  { TODO: ShaderTexture should not need to increase the TextureUnit.
    It's not loaded to OpenGL, so it doesn't take the multitexture slot.
    For now we increase it, only to pass texture coords to it. }
end;

function TShaderTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TShaderTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

function TShaderTextureResource.TextureNode: TShaderTextureNode;
begin
  Result := TShaderTextureNode(inherited TextureNode);
end;

{ TScreenTextureResource ------------------------------------------------------ }

var
  { The OpenGL texture shared by all ScreenTexture nodes,
    existing while ScreenTextureUsers > 0. }
  ScreenTextureGLName: TGLTexture;
  ScreenTextureWidth, ScreenTextureHeight: Integer;
  { Framebuffer with ScreenTextureGLName as the color attachment,
    for glBlitFramebuffer. Created on demand. }
  ScreenTextureFramebuffer: TGLFramebuffer;
  { Number of prepared TScreenTextureResource. }
  ScreenTextureUsers: Integer;
  { TFramesPerSecond.RenderFrameId when ScreenTextureGLName was last bound,
    to not update it when nothing visible uses it. }
  ScreenTextureBoundFrame: TFrameId;
  WarningScreenTextureMultisampleDone: Boolean;

class function TScreenTextureResource.IsClassForTextureNode(
  ANode: TAbstractTextureNode): boolean;
begin
  Result := ANode is TScreenTextureNode;
end;

function TScreenTextureResource.TextureNode: TScreenTextureNode;
begin
  Result := TScreenTextureNode(inherited TextureNode);
end;

procedure TScreenTextureResource.PrepareCore(
  const RenderOptions: TCastleRenderOptions);
begin
  if ScreenTextureUsers = 0 then
  begin
    ScreenTextureGLName := glCreateTexture;
    ScreenTextureWidth := 0;
    ScreenTextureHeight := 0;
    glBindTexture(GL_TEXTURE_2D, ScreenTextureGLName);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    { update it in the first frame }
    ScreenTextureBoundFrame := TFramesPerSecond.RenderFrameId;
  end;
  Inc(ScreenTextureUsers);
end;

procedure TScreenTextureResource.UnprepareCore;
begin
  Dec(ScreenTextureUsers);
  if ScreenTextureUsers = 0 then
  begin
    if ScreenTextureFramebuffer <> GLObjectNone then
    begin
      glDeleteFramebuffer(ScreenTextureFramebuffer);
      ScreenTextureFramebuffer := GLObjectNone;
    end;
    glDeleteTexture(ScreenTextureGLName);
    ScreenTextureGLName := GLObjectNone;
  end;
end;

function TScreenTextureResource.Bind(const TextureUnit: Cardinal): boolean;
begin
  Result := ScreenTextureGLName <> GLObjectNone;
  if not Result then Exit;

  TRenderer.ActiveTexture(TextureUnit);
  glBindTexture(GL_TEXTURE_2D, ScreenTextureGLName);
  ScreenTextureBoundFrame := TFramesPerSecond.RenderFrameId;
end;

function TScreenTextureResource.Enable(const TextureUnit: Cardinal;
  Shader: TShader; const Env: TTextureEnv): boolean;
begin
  Result := Bind(TextureUnit);
  if not Result then Exit;

  Shader.EnableTexture(TextureUnit, MyTextureType, TextureNode, Env);
end;

function TScreenTextureResource.ShaderTextureType(out TextureType: TTextureType): Boolean;
begin
  TextureType := MyTextureType;
  Result := true;
end;

function TScreenTextureResource.GLName: TGLTextureId;
begin
  Result := ScreenTextureGLName;
end;

{ Copy the colors of the given rectangle of the current framebuffer
  (in pixels) to ScreenTextureGLName, resizing it to the rectangle size.
  UseBlit says to use glBlitFramebuffer, otherwise glCopyTexSubImage2D. }
procedure UpdateScreenTextureFromScreen(const Rect: TRectangle;
  const UseBlit: Boolean);
{$ifndef CASTLE_WEBGL}
var
  PreviousDrawFramebuffer: TGLint;
{$endif}
begin
  if (Rect.Width <= 0) or (Rect.Height <= 0) then
    Exit;

  TRenderer.ActiveTexture(0);
  glBindTexture(GL_TEXTURE_2D, ScreenTextureGLName);
  if (ScreenTextureWidth <> Rect.Width) or (ScreenTextureHeight <> Rect.Height) then
  begin
    ScreenTextureWidth := Rect.Width;
    ScreenTextureHeight := Rect.Height;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ScreenTextureWidth, ScreenTextureHeight, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil);
  end;

  if UseBlit then
  begin
    { Blit into a framebuffer with our texture.
      The current framebuffer stays bound for reading (GL_READ_FRAMEBUFFER),
      only the drawing framebuffer is changed for the blit. }
    {$ifndef CASTLE_WEBGL}
    PreviousDrawFramebuffer := glGetInteger(GL_DRAW_FRAMEBUFFER_BINDING);
    if ScreenTextureFramebuffer = GLObjectNone then
    begin
      ScreenTextureFramebuffer := glCreateFramebuffer;
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, ScreenTextureFramebuffer);
      glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D, ScreenTextureGLName, 0);
    end else
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, ScreenTextureFramebuffer);
    glBlitFramebuffer(
      Rect.Left, Rect.Bottom, Rect.Left + ScreenTextureWidth, Rect.Bottom + ScreenTextureHeight,
      0, 0, ScreenTextureWidth, ScreenTextureHeight,
      GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, PreviousDrawFramebuffer);
    {$endif}
  end else
    glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, Rect.Left, Rect.Bottom,
      ScreenTextureWidth, ScreenTextureHeight);
end;

procedure UpdateScreenTextures;
var
  Rect: TRectangle;
  Multisampled, UseBlit: Boolean;
begin
  if ScreenTextureUsers = 0 then
    Exit;
  { Nothing rendered with it in this or the previous frame: probably not
    visible, don't copy. When it becomes visible, it shows old colors
    for one frame. }
  if ScreenTextureBoundFrame + 1 < TFramesPerSecond.RenderFrameId then
    Exit;

  { Use glBlitFramebuffer when possible:
    - glCopyTexSubImage2D cannot read from a multisampled framebuffer
      (anti-aliasing), the blit resolves it.
    - glCopyTexSubImage2D needs the texture format to match the framebuffer
      format in OpenGLES: it fails (GL_INVALID_OPERATION) with ANGLE (OpenGLES 3),
      likely because its window framebuffer is BGRA. The blit converts.
    TODO: WebGL 2 has the blit too, but we don't query
    the framebuffer binding there yet. WebGL always copies:
    the browser resolves the default (antialiased) drawing buffer
    when copying from it. }
  {$ifdef CASTLE_WEBGL}
  UseBlit := false;
  Multisampled := false;
  {$else}
  UseBlit := GLFeatures.FramebufferBlit;
  Multisampled := glGetInteger(GL_SAMPLE_BUFFERS) > 0;
  {$endif}
  if Multisampled and not UseBlit then
  begin
    if not WarningScreenTextureMultisampleDone then
    begin
      WarningScreenTextureMultisampleDone := true;
      WritelnWarning('ScreenTexture cannot be updated from a multisampled framebuffer (anti-aliasing) without glBlitFramebuffer');
    end;
    Exit;
  end;

  Rect := RenderContext.Viewport.Translate(RenderContext.ViewportDelta);
  UpdateScreenTextureFromScreen(Rect, UseBlit);
end;

{$endif read_implementation}

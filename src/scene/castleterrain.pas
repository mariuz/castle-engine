{
  Copyright 2009-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Terrain (height map) components.

  TODO: Terrain API is not finalized yet,
  there may be significant incompatible changes to this unit in the future.
  Big TODOs:

  @unorderedList(
    @item(
      Edit terrain heights in the CGE editor.

      Possible approach: turn any data (including TCastleTerrainNoise) into
      TCastleTerrainImage, then add editing tools to just change this image.

      Alternatively user could edit a TCastleTerrainImage that is combined
      with TCastleTerrainNoise -- this seems a powerful but uncertain feature,
      i.e. in the end it means you cannot directly edit the output of TCastleTerrainNoise,
      so it may be less comfortable (although it would allow to later regenerate
      TCastleTerrainNoise and keep the edits -- effectively they would work
      like Blender modifier.)
    )

    @item(
      Edit textures influence using splatmap. Just a texture where RGBA
      are weights for each texture.

      Implement this, and also add a brush to edit splatmap in CGE editor.

      The existing way to determine layers influence can then be used
      as just a nice (optional) way to auto-generate initial splatmap.)

    @item(Adding vegetation to the terrain.

      Adding grass and other small things (that must be placed in large batches
      and density should be dynamic).

      Adding trees, boulders and other large things (their density should
      also be dynamic for fast rendering, but at close distance they are just
      3D models).)

    @item(
      Add non-trivial rendering algorithm.
      Right now it is really the simplest possible approach to generate a mesh
      from heights with a simplest shader mixing a few texture layers.)
  )

  Smaller TODOs:

  @unorderedList(
    @item(TCastleTerrain.Subdivisions should be TVector2Cardinal.
      Needs introducing TCastleVector2CardinalPersistent.)
    @item(Enable normalmaps for each layer.)
    @item(? TCastleTerrain configurable textures number.
      Unsure -- hardcoding current 4 layers sucks, but also it makes sense for coming RGBA splatmap.)
    @item(? TCastleTerrain Use GridCount, GridStep instead of Subdivisions, Size?
      See wyrd-forest arguments.)
    @item(? TCastleTerrain add property to define material type, like in primitives - unlit, physical, phong.
      Wait with this for our final CGE components to define materials and effects,
      TCastlePhysicalMaterial, TCastleShaderEffect -- they will determine how to nicely
      expose it here.)
  )
}
unit CastleTerrain;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleClassUtils, CastleScript, CastleImages, X3DNodes, CastleVectors,
  CastleRectangles, CastleTransform, CastleScene, X3DFields, CastleRenderOptions,
  CastleColors, CastleTriangles;

type
  { Terrain (height map) data that can be used for @link(TCastleTerrain.Data). }
  TCastleTerrainData = class(TCastleComponent)
  strict private
    FChangeNotifications: TNotifyEventList;
    procedure UpdateNodeCore(const Node: TAbstractChildNode;
      const Subdivisions: TVector2; const InputRange, OutputRange: TFloatRectangle;
      const Appearance: TAppearanceNode;
      const TriangulationIgnoreHeights: Boolean);
  private
    { Create X3D node with the given terrain shape.

      InputRange determines the range of values (minimum and maximum X and Y)
      queried from the underlying terrain, that is: queried using the @link(Height)
      method.

      OutputRange determines the span of the resulting shape in X and Z
      coordinates. Note that, when converting a heightmap to 3D,
      the 2nd dimension is Z. In 3D, we use Y for height, as this is the default
      in X3D and Castle Game Engine.

      Often you will set InputRange and OutputRange to the same values,
      but you don't have to. Often they will at least have the same aspect ratio
      (actually, often they will be square), but you don't have to.

      Subdivisions determines how dense is the mesh.
      They determine the number of rows in columns in the mesh.
      E.g. subdivision (4,4) means 16 (4 * 4) quads and 25 (5 * 5) vertexes.
      This matches the Blender's "subdivisions" parameter for grids.

      We return the node that you should insert to your scene.

      It will use the given TAppearanceNode.
      The appearance is not configured in any way by this method,
      and it can even be @nil. }
    function CreateNode(const Subdivisions: TVector2;
      const InputRange, OutputRange: TFloatRectangle;
      const Appearance: TAppearanceNode;
      const TriangulationIgnoreHeights: Boolean): TAbstractChildNode; overload;

    { Update a node created by @link(CreateNode)
      to the new terrain and it's settings.
      The appearance of the previously created node (in CreateNode) is preserved. }
    procedure UpdateNode(const Node: TAbstractChildNode;
      const Subdivisions: TVector2; const InputRange, OutputRange: TFloatRectangle;
      const TriangulationIgnoreHeights: Boolean);
  protected
    { Use this in descendants implementation to notify that data
      (affecting @link(Height) results) changed.
      In the base class, it takes care to run notifications registered
      by @link(AddChangeNotification). }
    procedure DoChange;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Return height for given terrain point.

      @param(Coord The queried terrain height.
        Coord.X is the X position in local terrain coordinate space.
        Coord.Y is the Z position in local terrain coordinate space.
        They are in the range determined by TCastleTerrain.Size.
      )
      @param(TexCoord The texture coordinate at this point,
        assuming that TCastleTerrain.Size and texture UV scale would cancel each other,
        making both TexCoord.X and TexCoord.Y always in [0..1] range.

        Note that TexCoord.Y grows in different direction than Coord.Y,
        this means that textures have natural look when viewer from above the terrain
        (otherwise they would seem flipped in one direction in CGE right-handed
        coordinate system).
      ) }
    function Height(const Coord, TexCoord: TVector2): Single; virtual; abstract;

    { Add notification when data (affecting @link(Height) results) changes. }
    procedure AddChangeNotification(const Notify: TNotifyEvent);
    { Remove notification when data (affecting @link(Height) results) changes. }
    procedure RemoveChangeNotification(const Notify: TNotifyEvent);
  end;

  { Terrain (height map) data taken from intensities in an image.

    The image spans always the entire terrain in X and Z.

    The image minimum intensity (black) maps to height MinLevel,
    maximum intensity (white) maps to height MaxLevel.
    Any relation of MinLevel and MaxLevel is OK,
    that is: both MinLevel<MaxLevel and MinLevel>MaxLevel are valid.

    When image is not loaded, it behaves like all the image intensities are 0.5. }
  { Brush operation used when interactively sculpting @link(TCastleTerrainImage)
    or @link(TCastleTerrain). }
  TTerrainSculptBrushMode = (
    tsbmRaise,
    tsbmLower,
    tsbmSmooth,
    tsbmFlatten
  );

  TCastleTerrainImage = class(TCastleTerrainData)
  strict private
    { FImage = nil and FUrl = '' when not loaded. }
    FImage: TGrayscaleFloatImage;
    FUrl: String;
    FMinLevel, FMaxLevel: Single;
    FSmoothInterpolation: Boolean;
    procedure SetUrl(const Value: String);
    procedure SetMinLevel(const Value: Single);
    procedure SetMaxLevel(const Value: Single);
    procedure SetSmoothInterpolation(const Value: Boolean);
  public
    const
      DefaultSmoothInterpolation = true;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Height(const Coord, TexCoord: TVector2): Single; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Direct access to the underlying floating-point heightmap image
      (@nil if neither loaded from @link(Url) nor created via @link(CreateBlankImage)). }
    property Image: TGrayscaleFloatImage read FImage;

    { Allocate an in-memory floating-point heightmap of size @code(AWidth x AHeight)
      initialized uniformly to @code(InitialHeight) (adjusting @link(MinLevel)
      and @link(MaxLevel) if needed so @code(InitialHeight) is representable). }
    procedure CreateBlankImage(const AWidth, AHeight: Cardinal;
      const InitialHeight: Single = 0.0);

    { Sample @code(SourceData) across @code(InputRange) into an in-memory
      @code(AWidth x AHeight) floating-point heightmap. }
    procedure BakeFromTerrainData(const SourceData: TCastleTerrainData;
      const AWidth, AHeight: Cardinal; const InputRange: TFloatRectangle);

    { Apply a circular/elliptical sculpt brush centered at @code(CenterTexCoord)
      (in @code([0..1]) terrain texture coordinates) with UV radius @code(RadiusUV).
      Automatically expands @link(MinLevel) and @link(MaxLevel) and renormalizes
      existing texels so sculpted heights never clip to @code([0..1]).
      When @code(BaseLayerData <> nil) (for example when this image acts as an
      @code(opAdd) edit layer over @link(TCastleTerrainNoise)), @code(tsbmSmooth)
      and @code(tsbmFlatten) operate on the composite surface height
      (@code(BaseLayerData + Self)) over @code(BaseInputRange). }
    procedure ApplySculptBrush(const CenterTexCoord, RadiusUV: TVector2;
      const Mode: TTerrainSculptBrushMode; const Strength: Single;
      const FlattenTargetHeight: Single = 0.0); overload;
    procedure ApplySculptBrush(const CenterTexCoord, RadiusUV: TVector2;
      const Mode: TTerrainSculptBrushMode; const Strength: Single;
      const FlattenTargetHeight: Single;
      const BaseLayerData: TCastleTerrainData;
      const BaseInputRange: TFloatRectangle); overload;

    { Save the current in-memory heightmap image to @code(SaveUrl) (8-bit grayscale
      for PNG/JPG/BMP or floating-point where supported) and update @link(Url). }
    procedure SaveImage(const SaveUrl: String);
  published
    { Image URL. Empty string means that no image is loaded. }
    property Url: String read FUrl write SetUrl;
    { Height when the image has minimum intensity (black). }
    property MinLevel: Single read FMinLevel write SetMinLevel {$ifdef FPC}default -0.5{$endif};
    { Height when the image has maximum intensity (white). }
    property MaxLevel: Single read FMaxLevel write SetMaxLevel {$ifdef FPC}default  0.5{$endif};
    { Bilinearly interpolate texels when sampling heights (smooth slopes instead of stair-steps). }
    property SmoothInterpolation: Boolean
      read FSmoothInterpolation write SetSmoothInterpolation default DefaultSmoothInterpolation;
  end;

  { Terrain (height for each X, Y) data calculated from CastleScript
    expression. At construction, pass FunctionExpression,
    that is CastleScript language expression calculating height
    based on X, Y.

    See https://castle-engine.io/castle_script.php for CastleScript syntax.
    Try e.g. function like

    - @code(sin(x) + sin(y))

    - Sum sinusoides of various frequencies and amplitudes:

      @preformatted(
        (sin(x) + sin(x*2) / 2 + sin(x*4) / 4)  *
        (sin(y) + sin(y*2) / 2 + sin(y*4) / 4)
      ) }
  TTerrainCasScript = class(TCastleTerrainData)
  strict private
    FXVariable, FYVariable: TCasScriptFloat;
    FFunction: TCasScriptExpression;
  public
    constructor Create(const FunctionExpression: String); reintroduce;
    destructor Destroy; override;
    function Height(const Coord, TexCoord: TVector2): Single; override;
  end deprecated 'using CastleScript to define terrain is deprecated due to low usage';

  TNoiseInterpolation = (niNone, niLinear, niCosine, niSpline);

  { Terrain heights are generated from a smooth noise,
    combined with some terrain-specific improvements (Heterogeneous).

    We take the noise (integer noise, i.e. hash), smooth it
    (how well, and how fast --- see @link(Interpolation) and @link(Blur)),
    and add several
    functions ("octaves") of such noise (with varying frequency and amplitude)
    together. This is the kind of noise used to synthesize textures,
    terrains and all other procedural stuff.

    For more info about math inside:

    @unorderedList(
      @item([http://en.wikipedia.org/wiki/Fractional_Brownian_motion].
        This is the idea of summing up octaves of noise.
        Ken Musgrave's dissertation has a lot of info and interesting references:
        [http://www.kenmusgrave.com/dissertation.html])

      @item(Blender's source code is informative, interesting file
        is blender/source/blender/blenlib/intern/noise.c)

      @item(The simplest practical introduction to the idea is on
        [http://freespace.virgin.net/hugo.elias/models/m_perlin.htm].
        It describes how to get nice noise very easily, and my approach follows
        theirs.)
    ) }
  TCastleTerrainNoise = class(TCastleTerrainData)
  strict private
    type
      TNoise2DMethod = function (const X, Y: Single; const Seed: Cardinal): Single;
    var
      FOctaves: Single;
      FSmoothness: Single;
      FAmplitude: Single;
      FFrequency: Single;
      FInterpolation: TNoiseInterpolation;
      NoiseMethod: TNoise2DMethod;
      FBlur: Boolean;
      FSeed: Cardinal;
      FHeterogeneous: Single;
    procedure SetOctaves(const Value: Single);
    procedure SetSmoothness(const Value: Single);
    procedure SetAmplitude(const Value: Single);
    procedure SetFrequency(const Value: Single);
    procedure SetInterpolation(const Value: TNoiseInterpolation);
    procedure SetBlur(const Value: Boolean);
    procedure SetSeed(const Value: Cardinal);
    procedure SetHeterogeneous(const Value: Single);
    procedure UpdateNoiseMethod;
  public
    const
      DefaultOctaves = 4.0;
      DefaultSmoothnes = 2.0;
      DefaultAmplitude = 8.0;
      DefaultFrequency = 0.05;
      DefaultInterpolation = niCosine;
      DefaultBlur = false;
      DefaultHeterogeneous = 0.5;

    constructor Create(AOwner: TComponent); override;
    function Height(const Coord, TexCoord: TVector2): Single; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
  published
    { Number of noise functions to sum.
      This linearly affects the time for Height call, so don't make
      it too much. Usually ~a few are Ok.

      (The fact that it's a float is just a simple trick to allow smooth
      transitions from x to x+1. In fact, it's executed like
      Trunc(Octaves) * some noises + Frac(Octaves) * some last noise.)

      Reasonable values are roughly between 0..20. }
    property Octaves: Single read FOctaves write SetOctaves {$ifdef FPC}default DefaultOctaves{$endif};

    { How noise amplitude changes, when frequency doubles.
      When we double frequency, amplitude is divided by this.
      Smaller values <=> larger frequency noise
      is more visible, so terrain is less smooth (more noisy).

      This is elsewhere called fractal increment, fractal dimension parameter,
      "H", spectral exponent (see e.g. Blender sources, Musgrave's dissertation).
      Do not confuse this with "lacunarity" (how frequency changes in each octave),
      that is simply hardcoded to 2.0 in our code currently.
      In [http://freespace.virgin.net/hugo.elias/models/m_perlin.htm],
      the inverse of this 1/Smoothness is called "Persistence".

      I decided to call it "Smoothness", since this is the practical
      intuitive meaning.

      Value equal 1.0 means that amplitude doesn't change at all,
      each noise frequency is visible the same, so in effect you will
      just see a lot of noise. And values < 1.0 are really nonsense,
      they make more frequency noise even more visible, which means that
      the terrain is dominated by noise.

      Reasonable values are roughly between 1..10. }
    property Smoothness: Single read FSmoothness write SetSmoothness {$ifdef FPC}default DefaultSmoothnes{$endif};

    { Amplitude and frequency of the first noise octave.
      Amplitude scales the height of the result, and Frequency scales
      the size of the bumps.
      @groupBegin }
    property Amplitude: Single read FAmplitude write SetAmplitude {$ifdef FPC}default DefaultAmplitude{$endif};
    property Frequency: Single read FFrequency write SetFrequency {$ifdef FPC}default DefaultFrequency{$endif};
    { @groupEnd }

    { How integer noise is interpolated to get smooth float noise.

      Setting this to niNone turns off interpolation, which means that
      your terrain is a sum of a couple of blocky noises --- ugly.

      Using niLinear (means "bilinear", since this is 2D case)
      is also usually bad. Unless you use octaves of really high frequencies,
      usually sharp edges  / flat in-betweens will be visible.

      Using niCosine in right now the best.

      Using niSpline is even better looking
      (usese Catmull-Rom splines,
      which are special case of cubic Hermite spline, see
      http://en.wikipedia.org/wiki/Cubic_Hermite_spline,
      http://en.wikipedia.org/wiki/Bicubic_interpolation).
      But it's more time consuming under current implementation. }
    property Interpolation: TNoiseInterpolation
      read FInterpolation write SetInterpolation default DefaultInterpolation;

    { Resulting noise octaves may be blurred. This helps to remove
      the inherent vertical/horizontal directionality in our 2D noise
      (it also makes it more smooth, since that's what blurring is about;
      you may want to increase Frequency * 2 to balance this).

      This is independent from @link(Interpolation). Although the need
      for Blur is most obvious in poor/none interpolation methods
      (none, linear), it also helps for the nicer interpolation methods
      (cosine, cubic).

      Note about [http://freespace.virgin.net/hugo.elias/models/m_perlin.htm]:
      this "blurring" is called "smoothing" there.
      I call it blurring, as it seems more precise to me. }
    property Blur: Boolean read FBlur write SetBlur default DefaultBlur;

    { Determines the random seeds used when generating the terrain. }
    property Seed: Cardinal read FSeed write SetSeed default 0;

    { If non-zero, then we generate terrain using heterogeneous fBm.
      Intuitively, the idea is that the terrain details (from higher octaves)
      are more noisy when ground is higher. This is realistic
      (debris gathers in lower terrain, smoothing it more).

      More precisely, this means that we accumulate multiplied previous noise,
      at each step dividing this accumulated result by Heterogeneous,
      and clamping at 1.0. So when Heterogeneous is very small,
      this always ends up 1.0, and we get normal (homogeneous) generation.
      When Heterogeneous is larger, the details (at lower ground)
      are scaled down (terrain is smoother).

      This is called "threshold" in Musgrave's dissertation (see algorithm
      in section 2.3.2.5 "A Large Scale Terrain Model").

      Reasonable values for this are between 0..2. }
    property Heterogeneous: Single
      read FHeterogeneous write SetHeterogeneous {$ifdef FPC}default DefaultHeterogeneous{$endif};
  end;

  TTerrain = TCastleTerrainData deprecated 'use TCastleTerrainData';
  TTerrainImage = TCastleTerrainImage deprecated 'use TCastleTerrainImage';
  TTerrainNoise = TCastleTerrainNoise deprecated 'use TCastleTerrainNoise';

  { Operation used by TCastleTerrainCombine to combine heights from 2 terrain data sources.
    See @link(TCastleTerrainCombine.Operation). }
  TCastleTerrainCombineOperation = (opMax, opMin, opAdd, opMultiply);

  { Combine (add, multiply, do maximum or minimum) two other terrain data sources.
    This allows to e.g. combine TCastleTerrainNoise with TCastleTerrainImage
    in a flexible way. For example you can use TCastleTerrainImage to force some
    mountains / valleys even where TCastleTerrainNoise doesn't have them. }
  TCastleTerrainCombine = class(TCastleTerrainData)
  private
    type
      TOperationFunc = function (const A, B: Single): Single;
    var
      FData1, FData2: TCastleTerrainData;
      FData1Observer, FData2Observer: TFreeNotificationObserver;
      FOperation: TCastleTerrainCombineOperation;
      FOperationFunc: TOperationFunc;
    procedure Data1FreeNotification(const Sender: TFreeNotificationObserver);
    procedure Data2FreeNotification(const Sender: TFreeNotificationObserver);
    procedure Data1Changed(Sender: TObject);
    procedure Data2Changed(Sender: TObject);
    procedure SetData1(const Value: TCastleTerrainData);
    procedure SetData2(const Value: TCastleTerrainData);
    procedure SetOperation(const Value: TCastleTerrainCombineOperation);
    procedure UpdateOperationFunc;
  public
    const
      DefaultOperation = opMax;
    constructor Create(AOwner: TComponent); override;
    function Height(const Coord, TexCoord: TVector2): Single; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
  published
    { First data for terrain heights. }
    property Data1: TCastleTerrainData read FData1 write SetData1;
    { Second data for terrain heights. }
    property Data2: TCastleTerrainData read FData2 write SetData2;
    { How to combine results of Data1 and Data2. }
    property Operation: TCastleTerrainCombineOperation read FOperation write SetOperation default opMax;
  end;

  TCastleTerrain = class;

  { Layer of a terrain properties. See @link(TCastleTerrain) for docs how terrain
    uses layers for display. }
  TCastleTerrainLayer = class(TCastleComponent)
  strict private
    Terrain: TCastleTerrain;
    Layer: Integer;
    ColorField: TSFColor;
    TextureNode: TImageTextureNode;
    function GetUvScale: Single;
    procedure SetUvScale(const Value: Single);
    function GetMetallic: Single;
    procedure SetMetallic(const Value: Single);
    function GetRoughness: Single;
    procedure SetRoughness(const Value: Single);
    function GetColor: TCastleColorRGB;
    procedure SetColor(const Value: TCastleColorRGB);
    function GetTexture: String;
    procedure SetTexture(const Value: String);
    function GetUsingPackedVector(const Vec: TSFVec4f): Single;
    procedure SetUsingPackedVector(const Vec: TSFVec4f; const Value: Single);
  {$warnings off}
  private
    constructor CreateForTerrain(const ATerrain: TCastleTerrain;
      const ALayer: Integer; const Effect: TEffectNode);
  public
  {$warnings on}
    const
      DefaultUvScale = 1.0;
      DefaultMetallic = 1.0;
      DefaultRoughness = 1.0;

    { Public constructor for this class raises exception.
      Never create instances of this class directly.
      The instances of this class should only be created by implementation of TCastleTerrain,
      access them as TCastleTerrain subcomponents like @link(TCastleTerrain.Layer1). }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Color, multiplied by @link(Texture).
      Default is white. }
    property Color: TCastleColorRGB read GetColor write SetColor;

  published
    { Scale the @link(Texture).
      Setting UV scale to be equal to 1/@link(TCastleTerrain.Size)
      reliably makes the texture image size match the whole terrain. }
    property UvScale: Single read GetUvScale write SetUvScale {$ifdef FPC}default DefaultUvScale{$endif};

    { Texture URL. Texture is multiplied by @link(Color).
      Default (none) behaves as if it was a white texture for calculation. }
    property Texture: String read GetTexture write SetTexture;

    { The metalness of the material; values range from 0.0 (non-metal) to 1.0 (metal). }
    property Metallic: Single read GetMetallic write SetMetallic {$ifdef FPC}default DefaultMetallic{$endif};

    { The roughness of the material; values range from 0.0 (smooth) to 1.0 (rough). }
    property Roughness: Single read GetRoughness write SetRoughness {$ifdef FPC}default DefaultRoughness{$endif};

  {$define read_interface_class}
  {$I auto_generated_persistent_vectors/tcastleterrainlayer_persistent_vectors.inc}
  {$undef read_interface_class}
  end;

  { Terrain.

    Assign @link(Data) to provide some non-trivial height map, you can use there:

    @unorderedList(
      @item(@link(TCastleTerrainNoise) to generate a height map using a dedicated
        algorithm for terrain generation, using smooth noise and special tricks
        to have smooth and heteregeneous terrain.)

      @item(@link(TCastleTerrainImage) to generate a height map from intensities
        of a simple 2D image.)

      @item(@link(TCastleTerrainCombine) to combine the above options in any expression
        (take minimum, maximum, sum, multiply).)
    )

    The terrain starts as a standard mesh with a @link(TPhysicalMaterialNode) material.
    We apply on it a special affect to mix 4 layers, where each layer has a separate
    color and texture.

    @unorderedList(
      @item(
        Each layer has a color (white by default), texture (none by default,
        that behaves like white) and UV scale.
        See @link(TCastleTerrainLayer).
        Each layer is a property like @link(Layer1), @link(Layer2),
        @link(Layer3), @link(Layer4).)

      @item(Only the RBG channels of textures matter, alpha is ignored.)

      @item(Layer 1 is used for flat terrain on lower heights.)

      @item(Layer 2 is used for steep terrain on lower heights.)

      @item(Layer 3 is used for flat terrain on higher heights.)

      @item(Layer 4 is used for steep terrain on higher heights.)

      @item(The meaning of "lower" and "higher" heights is determined by @link(Height1)
        and @link(Height2). Below @link(Height1) we show only layers 1+2,
        above @link(Height2) we show only layers 3+4,
        between we show a smooth interpolation between them.)

      @item(The meaning of "flat" and "steep" is determined by looking at terrain
        normals emphasized by @link(SteepEmphasize).)

      @item(The influence of this effect can be controlled by LayersInfluence.)
    )
  }
  TCastleTerrain = class(TCastleTransform)
  public
    const
      { Texture layers to render this terrain. }
      LayersCount = 4;
      HeightsCount = 2;
  strict private
    TerrainNode: TAbstractChildNode;
    Appearance: TAppearanceNode;
    Effect: TEffectNode;
    HeightsFields: array [1..HeightsCount] of TSFFloat;
    Layers: array [1..LayersCount] of TCastleTerrainLayer;
    FData: TCastleTerrainData;
    FDataObserver: TFreeNotificationObserver;
    FTriangulationIgnoreHeights: Boolean;
    FSize, FQueryOffset: TVector2;
    FLayersInfluence: Single;
    FSteepEmphasize: Single;
    FSubdivisions: TVector2;
    FPreciseCollisions: Boolean;
    FUpdateGeometryWhenLoaded: Boolean;
    SplatmapNode: TPixelTextureNode;
    SplatmapInfluenceField: TSFFloat;
    TerrainSizeField: TSFVec2f;
    FSplatmapInfluence: Single;
    FSplatmapUrl: String;
    function GetRenderOptions: TCastleRenderOptions;
    function GetLayer(const Index: Integer): TCastleTerrainLayer;
    procedure DataFreeNotification(const Sender: TFreeNotificationObserver);
    procedure DataChanged(Sender: TObject);

    { Regenerate geometry (vertexes, normals etc.) to show the current Data
      with current parameters. }
    procedure UpdateGeometry;

    procedure SetData(const Value: TCastleTerrainData);
    procedure SetTriangulationIgnoreHeights(const Value: Boolean);
    procedure SetSubdivisions(const Value: TVector2);
    procedure SetSize(const Value: TVector2);
    procedure SetQueryOffset(const Value: TVector2);
    function GetHeight(const Index: Integer): Single;
    procedure SetHeight(const Index: Integer; const Value: Single);
    procedure SetLayersInfluence(const Value: Single);
    procedure SetSteepEmphasize(const Value: Single);
    procedure SetPreciseCollisions(const Value: Boolean);
    procedure SetSplatmapInfluence(const Value: Single);
    procedure SetSplatmapUrl(const Value: String);
  private
    Scene: TCastleScene;
    UvScaleField, MetallicField, RoughnessField: TSFVec4f;
  protected
    procedure Loaded; override;
    function InternalBuildNodeInside: TObject; override;
  public
    const
      DefaultSubdivisions = 64;
      DefaultSize = 100;
      DefaultHeight1 = 4.0;
      DefaultHeight2 = 8.0;
      { Default values for @link(Height1), @link(Height2) etc.

        Note: This array duplicates information in constants
        @link(DefaultHeight1), @link(DefaultHeight2) etc.
        Unfortunately we need the simple constants too, to specify properties default values
        like "default DefaultHeight0". Using "default DefaultHeight[0]" doesn't work in FPC
        (nor in Delphi, but that's because Delphi cannot handle Single defaults at all). }
      DefaultHeight: array [1..HeightsCount] of Single = (
        DefaultHeight1,
        DefaultHeight2
      );
      DefaultLayersInfluence = 1.0;
      DefaultSteepEmphasize = 2.0;
      DefaultSplatmapInfluence = 0.0;
      DefaultTriangulationIgnoreHeights = false;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function HasColliderMesh: Boolean; override;
    procedure ColliderMesh(const TriangleEvent: TTriangleEvent); override;

    { Convert a point in local @link(TCastleTerrain) coordinates to @code([0..1])
      terrain texture coordinates matching @link(TCastleTerrainData.Height) and splatmaps. }
    function LocalPointToTexCoord(const LocalPt: TVector3): TVector2;

    { Convert a point in world coordinates to @code([0..1]) terrain texture coordinates. }
    function WorldPointToTexCoord(const WorldPt: TVector3): TVector2;

    { Query current terrain height in local @link(TCastleTerrain) space at @code((LocalX, LocalZ)). }
    function SampleHeightAtLocalXZ(const LocalX, LocalZ: Single): Single;

    { Cast a world-space ray directly against this terrain's mesh (ignoring props/gizmos)
      and return @true with @code(HitWorldPoint) when the ray hits the terrain surface. }
    function RayCastWorld(const WorldRayOrigin, WorldRayDirection: TVector3;
      out HitWorldPoint: TVector3): Boolean;

    { Ensure @link(Data) has a writable @link(TCastleTerrainImage) edit layer and return it.
      - If @link(Data) is already @link(TCastleTerrainImage), ensures its @code(Image) is allocated.
      - If @link(Data) is @link(TCastleTerrainCombine) with @code(opAdd) and an image child, returns that image child.
      - If @link(Data) is procedural (e.g. @link(TCastleTerrainNoise)), non-destructively wraps it in
        a @link(TCastleTerrainCombine) (@code(opAdd)) + zero-initialized @link(TCastleTerrainImage) delta layer.
      - If @link(Data) is @nil, creates and assigns a new @link(TCastleTerrainImage). }
    function EnsureEditableHeightLayer(const OwnerForNewComponents: TComponent = nil;
      const DefaultResolution: Cardinal = 128): TCastleTerrainImage;

    { Interactively sculpt terrain height around @code(WorldPt) with world-space brush radius
      @code(WorldRadius). Automatically creates or reuses a non-destructive edit layer via
      @link(EnsureEditableHeightLayer). }
    function SculptHeightAtWorldPoint(const WorldPt: TVector3;
      const WorldRadius: Single; const Mode: TTerrainSculptBrushMode;
      const Strength: Single; const FlattenTargetWorldY: Single = 0.0;
      const OwnerForNewComponents: TComponent = nil;
      const DefaultResolution: Cardinal = 128): TCastleTerrainImage;

    { Current in-memory RGBA splatmap image (@code(R=Layer1, G=Layer2, B=Layer3, A=Layer4)). }
    function SplatmapImage: TRGBAlphaImage;

    { Initialize a uniform RGBA splatmap of size @code(AWidth x AHeight) filled with
      100% weight on @code(DefaultLayer) (@code(1..4)) and set @link(SplatmapInfluence) to @code(1.0). }
    procedure CreateBlankSplatmap(const AWidth: Cardinal = 128;
      const AHeight: Cardinal = 128; const DefaultLayer: Integer = 1);

    { Auto-populate the 4-channel RGBA splatmap from the terrain's current heights and surface
      normals using @link(Height1), @link(Height2), and @link(SteepEmphasize), and set
      @link(SplatmapInfluence) to @code(1.0) for further manual brush painting. }
    procedure GenerateSplatmapFromProceduralLayers(const AWidth: Cardinal = 128;
      const AHeight: Cardinal = 128);

    { Paint RGBA splatmap weight for @code(LayerIndex) (@code(1..4)) around @code(CenterTexCoord)
      with UV radius @code(RadiusUV), maintaining a normalized partition of unity across R+G+B+A. }
    procedure PaintSplatmapBrush(const CenterTexCoord, RadiusUV: TVector2;
      const LayerIndex: Integer; const Strength: Single;
      const DefaultResolution: Cardinal = 128);

    { Paint RGBA splatmap weight for @code(LayerIndex) (@code(1..4)) around @code(WorldPt)
      with world-space brush radius @code(WorldRadius). }
    procedure PaintSplatmapAtWorldPoint(const WorldPt: TVector3;
      const WorldRadius: Single; const LayerIndex: Integer;
      const Strength: Single; const DefaultResolution: Cardinal = 128);

    { Save the current RGBA splatmap image to @code(SaveUrl) (e.g. PNG) and update @link(SplatmapUrl). }
    procedure SaveSplatmap(const SaveUrl: String);

    { How dense is the mesh.
      By default this is (DefaultSubdivisions,DefaultSubdivisions).

      Changing this requires rebuild of terrain geometry, so it's costly.
      Avoid doing it at runtime. }
    property Subdivisions: TVector2 read FSubdivisions write SetSubdivisions;

    { Size of the generated shape and also the underlying range to query
      the TCastleTerrainNoise data for heights.

      Note that changing this does not just scale the same geometry,
      if TCastleTerrainNoise is used for @link(Data).
      The TCastleTerrainNoise uses the size you set here to determine
      what heights to query from a smooth noise.
      This has a nice effect that increasing the size adds additional
      pieces of terrain adjacent to the previous terrain,
      and the previous terrain shape is still visible at the same place.

      Be sure to increase also @link(Subdivisions) when increasing
      this field, to keep seeing the same detail.

      By default this is (DefaultSize,DefaultSize).

      Changing this requires rebuild of terrain geometry, so it's costly.
      Avoid doing it at runtime. }
    property Size: TVector2 read FSize write SetSize;

    { Offset the range of input values used to query the @link(Data).

      By default (when this is zero) we query the @link(TCastleTerrainData.Height)
      using @code(Coord) values ranging in X from -Size/2 to Size/2,
      similarly in Z.

      This vector offsets the range of queried values.

      It can be used to display a terrain noise matching neighboring terrain
      noise. }
    property QueryOffset: TVector2 read FQueryOffset write SetQueryOffset;

    property Triangulate: Boolean read FTriangulationIgnoreHeights write SetTriangulationIgnoreHeights;
      {$ifdef FPC}deprecated 'use TriangulationIgnoreHeights';{$endif}
  published
    { Options used to render the terrain. Can be used e.g. to toggle wireframe rendering. }
    property RenderOptions: TCastleRenderOptions read GetRenderOptions;

    { 1st layer is displayed on lower heights and more flat terrain.
      See TCastleTerrain for a full description how do we mix layers. }
    property Layer1: TCastleTerrainLayer index 1 read GetLayer;

    { 2nd layer is displayed on lower heights and more steep terrain.
      See TCastleTerrain for a full description how do we mix layers. }
    property Layer2: TCastleTerrainLayer index 2 read GetLayer;

    { 3rd layer is displayed on higher heights and more flat terrain.
      See TCastleTerrain for a full description how do we mix layers. }
    property Layer3: TCastleTerrainLayer index 3 read GetLayer;

    { 4th layer is displayed on higher heights and more steep terrain.
      See TCastleTerrain for a full description how do we mix layers. }
    property Layer4: TCastleTerrainLayer index 4 read GetLayer;

    { Data for terrain heights.
      Changing this requires rebuild of terrain geometry, so it's costly.
      Avoid doing it at runtime. }
    property Data: TCastleTerrainData read FData write SetData;

    { Triangulate each terrain quad the same way.

      When @false (default) we make a triangulation that has a little better
      quality. Each quad is split into 2 triangles in a way along the shortest
      diagonal.

      When @true, all the quads are triangulated consistently, disregarding
      the heights. This looks a bit worse, but is more friendly to dynamic changes,
      since changing the heights doesn't change the topology.

      Changing this requires rebuild of terrain geometry, so it's costly.
      Avoid doing it at runtime. }
    property TriangulationIgnoreHeights: Boolean
      read FTriangulationIgnoreHeights write SetTriangulationIgnoreHeights
      default DefaultTriangulationIgnoreHeights;

    { How much should we emphasize the "steep" layers (2nd and 4th layers)
      at the expense of "flat" layers (1st and 3rd).

      SteepEmphasize = 0.0 means that only "flat" layers (1 and 3) are visible.
      SteepEmphasize = 1.0 means that flat vs steep is a linear interpolation
      based on normal Y coordinate (but, since most terrains are more flat than
      steep, in practice the "flat" layers are still more visible).
      As SteepEmphasize goes toward infinity, the "steep" layers (2 and 4) dominate. }
    property SteepEmphasize: Single read FSteepEmphasize write SetSteepEmphasize
      {$ifdef FPC}default DefaultSteepEmphasize{$endif};

    { Below Height1 we only display layers 1+2.
      See TCastleTerrain for a description when do we show show layers and how this property affects it. }
    property Height1: Single index 1 read GetHeight write SetHeight {$ifdef FPC}default DefaultHeight1{$endif};
    { Above Height2 we only display layers 3+4.
      See TCastleTerrain for a description when do we show show layers and how this property affects it. }
    property Height2: Single index 2 read GetHeight write SetHeight {$ifdef FPC}default DefaultHeight2{$endif};

    { How much do the layers affect the final color.
      0.0 means that layes are ignored, and the terrain look is a regular
      mesh look with @link(TPhysicalMaterialNode).
      1.0 means maximum influence, the layers determine the base color
      (TODO: and normals in the future). }
    property LayersInfluence: Single read FLayersInfluence write SetLayersInfluence
      {$ifdef FPC}default DefaultLayersInfluence{$endif};

    { How much the 4-channel RGBA splatmap (@link(SplatmapUrl) or painted in-editor)
      overrides procedural slope/height layer mixing.
      @code(0.0) (default) uses procedural @link(Height1)/@link(Height2)/@link(SteepEmphasize) mixing;
      @code(1.0) uses 100% RGBA splatmap weights for @link(Layer1)..@link(Layer4). }
    property SplatmapInfluence: Single read FSplatmapInfluence write SetSplatmapInfluence
      {$ifdef FPC}default DefaultSplatmapInfluence{$endif};

    { Optional URL to a 4-channel RGBA splatmap texture whose R, G, B, A channels store
      blend weights for @link(Layer1), @link(Layer2), @link(Layer3), @link(Layer4). }
    property SplatmapUrl: String read FSplatmapUrl write SetSplatmapUrl;

    { Resolve collisions precisely with the terrain geometry.
      When this is @false we will only consider the terrain bounding box for collisions,
      which prevents moving on terrain nicely, picking terrain points with mouse etc. }
    property PreciseCollisions: Boolean read FPreciseCollisions write SetPreciseCollisions default true;

  {$define read_interface_class}
  {$I auto_generated_persistent_vectors/tcastleterrain_persistent_vectors.inc}
  {$undef read_interface_class}
  end;

implementation

uses Math,
  CastleUtils, CastleScriptParser, CastleInternalNoise, CastleDownload, CastleLog,
  CastleUriUtils, CastleComponentSerialize;

{ TCastleTerrainData ------------------------------------------------------------------- }

constructor TCastleTerrainData.Create(AOwner: TComponent);
begin
  inherited;
  FChangeNotifications := TNotifyEventList.Create;
end;

destructor TCastleTerrainData.Destroy;
begin
  FreeAndNil(FChangeNotifications);
  inherited;
end;

procedure TCastleTerrainData.DoChange;
begin
  { TODO: To fully avoid useless UpdateGeometry calls,
    avoid calling FChangeNotifications when IsLoading.
    Only schedule it and call when Loaded. }

  FChangeNotifications.ExecuteAll(Self);
end;

procedure TCastleTerrainData.AddChangeNotification(const Notify: TNotifyEvent);
begin
  FChangeNotifications.Add(Notify);
end;

procedure TCastleTerrainData.RemoveChangeNotification(const Notify: TNotifyEvent);
begin
  if FChangeNotifications = nil then
  begin
    { This can happen when we free the TCastleTerrainData (like TCastleTerrainNoise)
      that is referenced in some TCastleTerrain.Data.
      Then TCastleTerrainData.Destroy does "FreeAndNil(FChangeNotifications)"
      first, then calls inherited destructor, that sends DataFreeNotification
      to TCastleTerrain which in turn in SetData does RemoveChangeNotification.
      So this all can happen in valid situation and can be just ignored.
      When FChangeNotifications = nil it means we're freeing ourselves
      and we no longer care about tracking FChangeNotifications. }
    Assert(csDestroying in ComponentState);
    Exit;
  end;
  FChangeNotifications.Remove(Notify);
end;

function TCastleTerrainData.CreateNode(const Subdivisions: TVector2;
  const InputRange, OutputRange: TFloatRectangle;
  const Appearance: TAppearanceNode;
  const TriangulationIgnoreHeights: Boolean): TAbstractChildNode;
begin
  Result := TTransformNode.Create;
  UpdateNodeCore(Result, Subdivisions, InputRange, OutputRange, Appearance,
    TriangulationIgnoreHeights);
end;

procedure TCastleTerrainData.UpdateNode(const Node: TAbstractChildNode;
  const Subdivisions: TVector2; const InputRange, OutputRange: TFloatRectangle;
  const TriangulationIgnoreHeights: Boolean);
var
  Transform: TTransformNode;
  Shape: TShapeNode;
  Appearance: TAppearanceNode;
begin
  { extract Appearance from Node, assuming Node was created by CreateNode }
  Transform := Node as TTransformNode;
  Shape := Transform.FdChildren[0] as TShapeNode;
  Appearance := Shape.Appearance;

  Appearance.KeepExistingBegin;
  UpdateNodeCore(Node, Subdivisions, InputRange, OutputRange, Appearance,
    TriangulationIgnoreHeights);
  Appearance.KeepExistingEnd;
end;

procedure TCastleTerrainData.UpdateNodeCore(const Node: TAbstractChildNode;
  const Subdivisions: TVector2; const InputRange, OutputRange: TFloatRectangle;
  const Appearance: TAppearanceNode; const TriangulationIgnoreHeights: Boolean);
var
  XDimension, ZDimension: Cardinal;

  { Calculate height for given terrain point.
    Returns also coordinate and texture coordinate of this point.

    Note: coordinate in InputCoord does *not* equal, in XZ, the local coordinates
    that will be calculated by TElevationGridNode.InternalCreateTriangles.
    This coordinate is in input range, InputRange.

    In contrast, the local coordinates calculated by TElevationGridNode.InternalCreateTriangles
    are partially in output range: they take into account OutputRange.Width/Height.
    They do not take into account OutputRange.Left, OutputRange.Bottom
    which is applied by the transfomaion node. }
  function GetHeight(const X, Z: Single; out InputCoord, TexCoord: TVector2): Single;
  begin
    TexCoord := Vector2(
      MapRangeTo01(X, 0, XDimension - 1),
      MapRangeTo01(Z, 0, ZDimension - 1)
    );
    InputCoord := Vector2(
      Lerp(TexCoord.X, InputRange.Left  , InputRange.Right),
      Lerp(TexCoord.Y, InputRange.Bottom, InputRange.Top)
    );
    // TexCoord.Y grows in different direction, see Height docs for reason
    TexCoord.Y := 1 - TexCoord.Y;
    Result := Height(InputCoord, TexCoord);
  end;

  { Calculate 3D coordinate for given terrain point.
    The XZ of this corresponds to the InputRange,
    these are *not* 3D coordinates that will be
    calculated by TElevationGridNode.InternalCreateTriangles. }
  function GetInputCoord3D(const X, Z: Single): TVector3;
  var
    InputCoord, IgnoredTexCoord: TVector2;
  begin
    Result.Y := GetHeight(X, Z, InputCoord, IgnoredTexCoord);
    Result.X := InputCoord.X;
    Result.Z := InputCoord.Y;
  end;

  { Calculate normal at given terrain point.

    Generating normals on our side, instead of letting TIndexedTriangleSetNode
    algorithm to calculate them. Reasons:

    - This is faster. TIndexedTriangleSetNode has to consider general case,
      multiple triangles sharing a vertex in a general mesh.
      We can optimize for our case, a grid of vertexes.

    - On the edges, we can calculate normals in a more predictable way.
      This makes placing one terrain next to another result in smooth lighting
      where the terrains meet. }
  function GetNormal(const X, Z: Integer): TVector3;
  var
    P, PX, PZ: TVector3;
  begin
    // P  := GetInputCoord3D(X, Z);
    // PX := GetInputCoord3D(X + 1, Z);
    // PZ := GetInputCoord3D(X, Z + 1);
    // sample around the point, this way we don't make normal reflecting only one side
    P  := GetInputCoord3D(X - 0.5, Z - 0.5);
    PX := GetInputCoord3D(X + 0.5, Z - 0.5);
    PZ := GetInputCoord3D(X - 0.5, Z + 0.5);
    Result := TVector3.CrossProduct(
      (PZ - P),
      (PX - P)).Normalize;
  end;

var
  Transform: TTransformNode;
  Normal: TNormalNode;
  Shape: TShapeNode;
  TriangleSet: TIndexedTriangleSetNode;
  X, Z: Cardinal;
  IgnoredInputCoord, IgnoredTexCoord: TVector2;
  Heights: TSingleList;
begin
  XDimension := Round(Subdivisions.X) + 1;
  ZDimension := Round(Subdivisions.Y) + 1;

  Transform := Node as TTransformNode; // created by CreateNode
  Transform.ClearChildren;
  Transform.Translation := Vector3(OutputRange.Left, 0, OutputRange.Bottom);

  Shape := TShapeNode.Create;

  Heights := TSingleList.Create;
  try
    // calculate Heights
    Heights.Count := XDimension * ZDimension;
    for X := 0 to XDimension - 1 do
      for Z := 0 to ZDimension - 1 do
      begin
        Heights.L[X + Z * XDimension] := GetHeight(X, Z, IgnoredInputCoord, IgnoredTexCoord);
      end;

    TriangleSet := TElevationGridNode.InternalCreateTriangles(
      XDimension,
      ZDimension,
      OutputRange.Width  / (XDimension - 1),
      OutputRange.Height / (ZDimension - 1),
      Heights,
      nil,
      TriangulationIgnoreHeights
    );
  finally FreeAndNil(Heights) end;

  // calculate Normal (for TriangleSet.Normal)
  Normal := TNormalNode.Create;
  Normal.FdVector.Items.Count := XDimension * ZDimension;
  for X := 0 to XDimension - 1 do
    for Z := 0 to ZDimension - 1 do
      Normal.FdVector.Items.L[X + Z * XDimension] := GetNormal(X, Z);
  TriangleSet.Normal := Normal;

  Shape.Geometry := TriangleSet;
  Shape.Appearance := Appearance;

  // at the end, as this may cause Scene.ChangedAll
  Transform.AddChildren(Shape);
end;

{ TCastleTerrainImage ------------------------------------------------------------ }

constructor TCastleTerrainImage.Create(AOwner: TComponent);
begin
  inherited;
  FMinLevel := -0.5;
  FMaxLevel := 0.5;
  FSmoothInterpolation := DefaultSmoothInterpolation;
end;

destructor TCastleTerrainImage.Destroy;
begin
  FreeAndNil(FImage);
  inherited;
end;

procedure TCastleTerrainImage.SetUrl(const Value: String);

  procedure LoadImage(const NewUrl: String);
  var
    NewImage: TGrayscaleFloatImage;
  begin
    if NewUrl = '' then
      NewImage := nil
    else
    begin
      { Read as TGrayscaleFloatImage.
        Allows to read high-precision data from image formats that support it,
        like 16-bit PNG, 16/32-bit TIFF, OpenEXR in the future.
        The 8-bit formats will be converted to TGrayscaleFloatImage by
        TGrayscaleFloatImage.Assign. }
      NewImage := CastleImages.LoadImage(NewUrl, [TGrayscaleFloatImage])
        as TGrayscaleFloatImage;
    end;

    FreeAndNil(FImage);
    FImage := NewImage;
    FUrl := NewUrl;
    DoChange;
  end;

begin
  if FUrl <> Value then
  begin
    try
      LoadImage(Value); // in case of exception when loading, LoadImage leaves state unchanged
    except
      { If loading file failed, and we're inside CGE editor, merely report a warning.
        This allows deserializing in CGE editor designs with broken URLs. }
      on E: Exception do
      begin
        if CastleDesignMode then
        begin
          WritelnWarning('TCastleTerrainImage', 'Failed to load image "%s": %s', [
            UriDisplay(Value),
            ExceptMessage(E)
          ]);
        end else
          raise;
      end;
    end;
  end;
end;

function TCastleTerrainImage.Height(const Coord, TexCoord: TVector2): Single;
var
  PX, PY, X0, Y0, X1, Y1: Integer;
  FX, FY, FracX, FracY, I00, I10, I01, I11, Intensity: Single;
begin
  if FImage <> nil then
  begin
    if FSmoothInterpolation and ((FImage.Width > 1) or (FImage.Height > 1)) then
    begin
      FX := Clamped(TexCoord.X, 0.0, 1.0) * Max(0, Integer(FImage.Width) - 1);
      FY := Clamped(TexCoord.Y, 0.0, 1.0) * Max(0, Integer(FImage.Height) - 1);
      X0 := Floor(FX);
      Y0 := Floor(FY);
      ClampVar(X0, 0, Integer(FImage.Width) - 1);
      ClampVar(Y0, 0, Integer(FImage.Height) - 1);
      X1 := Min(X0 + 1, Integer(FImage.Width) - 1);
      Y1 := Min(Y0 + 1, Integer(FImage.Height) - 1);
      FracX := FX - X0;
      FracY := FY - Y0;
      I00 := FImage.PixelPtr(X0, Y0)^;
      I10 := FImage.PixelPtr(X1, Y0)^;
      I01 := FImage.PixelPtr(X0, Y1)^;
      I11 := FImage.PixelPtr(X1, Y1)^;
      Intensity := Lerp(FracY, Lerp(FracX, I00, I10), Lerp(FracX, I01, I11));
    end else
    begin
      PX := Floor(TexCoord.X * FImage.Width );
      PY := Floor(TexCoord.Y * FImage.Height);
      ClampVar(PX, 0, FImage.Width  - 1);
      ClampVar(PY, 0, FImage.Height - 1);
      Intensity := FImage.PixelPtr(PX, PY)^;
    end;
  end else
    Intensity := 0.5;
  Result := Lerp(Intensity, MinLevel, MaxLevel);
end;

procedure TCastleTerrainImage.SetMinLevel(const Value: Single);
begin
  if FMinLevel <> Value then
  begin
    FMinLevel := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainImage.SetMaxLevel(const Value: Single);
begin
  if FMaxLevel <> Value then
  begin
    FMaxLevel := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainImage.SetSmoothInterpolation(const Value: Boolean);
begin
  if FSmoothInterpolation <> Value then
  begin
    FSmoothInterpolation := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainImage.CreateBlankImage(const AWidth, AHeight: Cardinal;
  const InitialHeight: Single);
var
  W, H, I, Count: Cardinal;
  NormVal: Single;
  P: PSingle;
begin
  W := Max(2, AWidth);
  H := Max(2, AHeight);
  if InitialHeight < FMinLevel then
    FMinLevel := InitialHeight - 1.0;
  if InitialHeight > FMaxLevel then
    FMaxLevel := InitialHeight + 1.0;
  if Abs(FMaxLevel - FMinLevel) < 1e-4 then
  begin
    FMinLevel := InitialHeight - 0.5;
    FMaxLevel := InitialHeight + 0.5;
  end;
  NormVal := Clamped((InitialHeight - FMinLevel) / (FMaxLevel - FMinLevel), 0.0, 1.0);

  FreeAndNil(FImage);
  FImage := TGrayscaleFloatImage.Create(W, H);
  Count := W * H;
  P := PSingle(FImage.RawPixels);
  for I := 0 to Count - 1 do
  begin
    P^ := NormVal;
    Inc(P);
  end;
  DoChange;
end;

procedure TCastleTerrainImage.BakeFromTerrainData(const SourceData: TCastleTerrainData;
  const AWidth, AHeight: Cardinal; const InputRange: TFloatRectangle);
var
  W, H, X, Y: Integer;
  Samples: array of Single;
  TexC, InputC: TVector2;
  SampleH, MinH, MaxH, Span: Single;
begin
  W := Max(2, Integer(AWidth));
  H := Max(2, Integer(AHeight));
  if SourceData = nil then
  begin
    CreateBlankImage(W, H, 0.0);
    Exit;
  end;

  SetLength(Samples, W * H);
  MinH := MaxSingle;
  MaxH := -MaxSingle;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      TexC := Vector2(X / (W - 1), Y / (H - 1));
      InputC := Vector2(
        Lerp(TexC.X, InputRange.Left, InputRange.Right),
        Lerp(1.0 - TexC.Y, InputRange.Bottom, InputRange.Top));
      SampleH := SourceData.Height(InputC, TexC);
      Samples[X + Y * W] := SampleH;
      if SampleH < MinH then MinH := SampleH;
      if SampleH > MaxH then MaxH := SampleH;
    end;

  if MaxH - MinH < 1.0 then
  begin
    MinH := MinH - 0.5;
    MaxH := MaxH + 0.5;
  end;
  FMinLevel := MinH;
  FMaxLevel := MaxH;
  Span := FMaxLevel - FMinLevel;

  FreeAndNil(FImage);
  FImage := TGrayscaleFloatImage.Create(W, H);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
      FImage.PixelPtr(X, Y)^ := Clamped((Samples[X + Y * W] - FMinLevel) / Span, 0.0, 1.0);
  DoChange;
end;

procedure TCastleTerrainImage.ApplySculptBrush(const CenterTexCoord, RadiusUV: TVector2;
  const Mode: TTerrainSculptBrushMode; const Strength: Single;
  const FlattenTargetHeight: Single);
begin
  ApplySculptBrush(CenterTexCoord, RadiusUV, Mode, Strength, FlattenTargetHeight,
    nil, TFloatRectangle.Empty);
end;

procedure TCastleTerrainImage.ApplySculptBrush(const CenterTexCoord, RadiusUV: TVector2;
  const Mode: TTerrainSculptBrushMode; const Strength: Single;
  const FlattenTargetHeight: Single;
  const BaseLayerData: TCastleTerrainData;
  const BaseInputRange: TFloatRectangle);
var
  W, H: Integer;
  SafeRadX, SafeRadY: Single;
  XMin, XMax, YMin, YMax, SnapXMin, SnapXMax, SnapYMin, SnapYMax: Integer;
  SnapW, SnapH, BoxW, BoxH: Integer;
  PX, PY, NX, NY, AvgCount: Integer;
  U, V, DistSq, Falloff, Alpha, OldDeltaH, BaseH, OldTotalH, NewTotalH, NewDeltaH, AvgSum: Single;
  MinModifiedDelta, MaxModifiedDelta, OldMin, OldMax, NewMin, NewMax, Span: Single;
  SnapshotTotal, SnapshotBase, NewBoxDelta: array of Single;
  BoxMask: array of Boolean;
  HasAnyModified: Boolean;
  P: PSingle;
  I, TotalPixels: Integer;

  function SampleBaseAtPixel(const IX, IY: Integer): Single;
  var
    TC, IC: TVector2;
  begin
    if BaseLayerData = nil then
      Exit(0.0);
    TC := Vector2(IX / Max(1, W - 1), IY / Max(1, H - 1));
    IC := Vector2(
      Lerp(TC.X, BaseInputRange.Left, BaseInputRange.Right),
      Lerp(1.0 - TC.Y, BaseInputRange.Bottom, BaseInputRange.Top));
    Result := BaseLayerData.Height(IC, TC);
  end;

begin
  if FImage = nil then
    CreateBlankImage(128, 128, Lerp(0.5, FMinLevel, FMaxLevel));

  W := FImage.Width;
  H := FImage.Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  SafeRadX := Max(RadiusUV.X, 1.0 / Max(1, W));
  SafeRadY := Max(RadiusUV.Y, 1.0 / Max(1, H));

  XMin := Clamped(Floor((CenterTexCoord.X - SafeRadX) * Max(1, W - 1)), 0, W - 1);
  XMax := Clamped(Ceil ((CenterTexCoord.X + SafeRadX) * Max(1, W - 1)), 0, W - 1);
  YMin := Clamped(Floor((CenterTexCoord.Y - SafeRadY) * Max(1, H - 1)), 0, H - 1);
  YMax := Clamped(Ceil ((CenterTexCoord.Y + SafeRadY) * Max(1, H - 1)), 0, H - 1);

  if (XMin > XMax) or (YMin > YMax) then
    Exit;

  SnapXMin := Max(0, XMin - 1);
  SnapXMax := Min(W - 1, XMax + 1);
  SnapYMin := Max(0, YMin - 1);
  SnapYMax := Min(H - 1, YMax + 1);
  SnapW := SnapXMax - SnapXMin + 1;
  SnapH := SnapYMax - SnapYMin + 1;

  SetLength(SnapshotTotal, SnapW * SnapH);
  SetLength(SnapshotBase, SnapW * SnapH);
  for PY := SnapYMin to SnapYMax do
    for PX := SnapXMin to SnapXMax do
    begin
      OldDeltaH := Lerp(FImage.PixelPtr(PX, PY)^, FMinLevel, FMaxLevel);
      if (BaseLayerData <> nil) and (Mode in [tsbmSmooth, tsbmFlatten]) then
        BaseH := SampleBaseAtPixel(PX, PY)
      else
        BaseH := 0.0;
      SnapshotBase[(PX - SnapXMin) + (PY - SnapYMin) * SnapW] := BaseH;
      SnapshotTotal[(PX - SnapXMin) + (PY - SnapYMin) * SnapW] := BaseH + OldDeltaH;
    end;

  BoxW := XMax - XMin + 1;
  BoxH := YMax - YMin + 1;
  SetLength(NewBoxDelta, BoxW * BoxH);
  SetLength(BoxMask, BoxW * BoxH);
  HasAnyModified := false;
  MinModifiedDelta := MaxSingle;
  MaxModifiedDelta := -MaxSingle;

  for PY := YMin to YMax do
    for PX := XMin to XMax do
    begin
      if W > 1 then U := PX / (W - 1) else U := 0.5;
      if H > 1 then V := PY / (H - 1) else V := 0.5;
      DistSq := Sqr((U - CenterTexCoord.X) / SafeRadX) +
                Sqr((V - CenterTexCoord.Y) / SafeRadY);
      if DistSq < 1.0 then
      begin
        Falloff := Sqr(1.0 - DistSq);
        BaseH := SnapshotBase[(PX - SnapXMin) + (PY - SnapYMin) * SnapW];
        OldTotalH := SnapshotTotal[(PX - SnapXMin) + (PY - SnapYMin) * SnapW];
        OldDeltaH := OldTotalH - BaseH;

        case Mode of
          tsbmRaise:
            NewDeltaH := OldDeltaH + Strength * Falloff;
          tsbmLower:
            NewDeltaH := OldDeltaH - Strength * Falloff;
          tsbmSmooth:
            begin
              AvgSum := 0.0;
              AvgCount := 0;
              for NY := Max(SnapYMin, PY - 1) to Min(SnapYMax, PY + 1) do
                for NX := Max(SnapXMin, PX - 1) to Min(SnapXMax, PX + 1) do
                begin
                  AvgSum := AvgSum + SnapshotTotal[(NX - SnapXMin) + (NY - SnapYMin) * SnapW];
                  Inc(AvgCount);
                end;
              Alpha := Clamped(Strength * Falloff, 0.0, 1.0);
              if AvgCount > 0 then
                NewTotalH := Lerp(Alpha, OldTotalH, AvgSum / AvgCount)
              else
                NewTotalH := OldTotalH;
              NewDeltaH := NewTotalH - BaseH;
            end;
          tsbmFlatten:
            begin
              Alpha := Clamped(Strength * Falloff, 0.0, 1.0);
              NewTotalH := Lerp(Alpha, OldTotalH, FlattenTargetHeight);
              NewDeltaH := NewTotalH - BaseH;
            end;
        end;

        BoxMask[(PX - XMin) + (PY - YMin) * BoxW] := true;
        NewBoxDelta[(PX - XMin) + (PY - YMin) * BoxW] := NewDeltaH;
        HasAnyModified := true;
        if NewDeltaH < MinModifiedDelta then MinModifiedDelta := NewDeltaH;
        if NewDeltaH > MaxModifiedDelta then MaxModifiedDelta := NewDeltaH;
      end else
        BoxMask[(PX - XMin) + (PY - YMin) * BoxW] := false;
    end;

  if not HasAnyModified then
    Exit;

  OldMin := FMinLevel;
  OldMax := FMaxLevel;
  NewMin := Min(OldMin, MinModifiedDelta);
  NewMax := Max(OldMax, MaxModifiedDelta);
  if NewMax - NewMin < 1e-4 then
  begin
    NewMin := NewMin - 0.5;
    NewMax := NewMax + 0.5;
  end;

  if (NewMin < OldMin) or (NewMax > OldMax) or (Abs(OldMax - OldMin) < 1e-4) then
  begin
    Span := NewMax - NewMin;
    TotalPixels := W * H;
    P := PSingle(FImage.RawPixels);
    for I := 0 to TotalPixels - 1 do
    begin
      P^ := Clamped((Lerp(P^, OldMin, OldMax) - NewMin) / Span, 0.0, 1.0);
      Inc(P);
    end;
    FMinLevel := NewMin;
    FMaxLevel := NewMax;
  end;

  Span := FMaxLevel - FMinLevel;
  for PY := YMin to YMax do
    for PX := XMin to XMax do
      if BoxMask[(PX - XMin) + (PY - YMin) * BoxW] then
        FImage.PixelPtr(PX, PY)^ := Clamped(
          (NewBoxDelta[(PX - XMin) + (PY - YMin) * BoxW] - FMinLevel) / Span, 0.0, 1.0);

  DoChange;
end;

procedure TCastleTerrainImage.SaveImage(const SaveUrl: String);
var
  GrayByteImg: TGrayscaleImage;
  X, Y: Integer;
begin
  if SaveUrl = '' then
    raise Exception.Create('TCastleTerrainImage.SaveImage requires a non-empty URL');
  if FImage = nil then
    CreateBlankImage(128, 128, Lerp(0.5, FMinLevel, FMaxLevel));

  GrayByteImg := TGrayscaleImage.Create(FImage.Width, FImage.Height);
  try
    for Y := 0 to Integer(FImage.Height) - 1 do
      for X := 0 to Integer(FImage.Width) - 1 do
        GrayByteImg.PixelPtr(X, Y)^ := Round(Clamped(FImage.PixelPtr(X, Y)^, 0.0, 1.0) * 255.0);
    CastleImages.SaveImage(GrayByteImg, SaveUrl);
  finally
    FreeAndNil(GrayByteImg);
  end;
  FUrl := SaveUrl;
end;

function TCastleTerrainImage.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Url', 'MinLevel', 'MaxLevel', 'SmoothInterpolation'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

{ TTerrainCasScript -------------------------------------------------------- }

constructor TTerrainCasScript.Create(const FunctionExpression: String);
begin
  inherited Create(nil);

  FXVariable := TCasScriptFloat.Create(false);
  FXVariable.Name := 'x';
  FXVariable.OwnedByParentExpression := false;

  FYVariable := TCasScriptFloat.Create(false);
  FYVariable.Name := 'y';
  FYVariable.OwnedByParentExpression := false;

  FFunction := ParseFloatExpression(FunctionExpression, [FXVariable, FYVariable]);
end;

destructor TTerrainCasScript.Destroy;
begin
  FFunction.FreeByParentExpression;
  FFunction := nil;

  FreeAndNil(FXVariable);
  FreeAndNil(FYVariable);

  inherited;
end;

function TTerrainCasScript.Height(const Coord, TexCoord: TVector2): Single;
begin
  FXVariable.Value := Coord.X;
  FYVariable.Value := Coord.Y;
  Result := (FFunction.Execute as TCasScriptFloat).Value;
end;

{ TCastleTerrainNoise ------------------------------------------------------------ }

constructor TCastleTerrainNoise.Create(AOwner: TComponent);
begin
  inherited;

  FOctaves := DefaultOctaves;
  FSmoothness := DefaultSmoothnes;
  FAmplitude := DefaultAmplitude;
  FFrequency := DefaultFrequency;
  FInterpolation := DefaultInterpolation;
  FBlur := DefaultBlur;
  FHeterogeneous := DefaultHeterogeneous;

  UpdateNoiseMethod;
end;

procedure TCastleTerrainNoise.UpdateNoiseMethod;
begin
  if Blur then
    case Interpolation of
      niNone: NoiseMethod := @BlurredInterpolatedNoise2D_None;
      niLinear: NoiseMethod := @BlurredInterpolatedNoise2D_Linear;
      niCosine: NoiseMethod := @BlurredInterpolatedNoise2D_Cosine;
      niSpline: NoiseMethod := @BlurredInterpolatedNoise2D_Spline;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('TCastleTerrainNoise.UpdateNoiseMethod(Interpolation?)');
      {$endif}
    end else
    case Interpolation of
      niNone: NoiseMethod := @InterpolatedNoise2D_None;
      niLinear: NoiseMethod := @InterpolatedNoise2D_Linear;
      niCosine: NoiseMethod := @InterpolatedNoise2D_Cosine;
      niSpline: NoiseMethod := @InterpolatedNoise2D_Spline;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('TCastleTerrainNoise.UpdateNoiseMethod(Interpolation?)');
      {$endif}
    end;
end;

procedure TCastleTerrainNoise.SetOctaves(const Value: Single);
begin
  if FOctaves <> Value then
  begin
    FOctaves := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetSmoothness(const Value: Single);
begin
  if FSmoothness <> Value then
  begin
    FSmoothness := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetAmplitude(const Value: Single);
begin
  if FAmplitude <> Value then
  begin
    FAmplitude := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetFrequency(const Value: Single);
begin
  if FFrequency <> Value then
  begin
    FFrequency := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetInterpolation(const Value: TNoiseInterpolation);
begin
  if FInterpolation <> Value then
  begin
    FInterpolation := Value;
    UpdateNoiseMethod;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetBlur(const Value: Boolean);
begin
  if FBlur <> Value then
  begin
    FBlur := Value;
    UpdateNoiseMethod;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetSeed(const Value: Cardinal);
begin
  if FSeed <> Value then
  begin
    FSeed := Value;
    DoChange;
  end;
end;

procedure TCastleTerrainNoise.SetHeterogeneous(const Value: Single);
begin
  if FHeterogeneous <> Value then
  begin
    FHeterogeneous := Value;
    DoChange;
  end;
end;

function TCastleTerrainNoise.Height(const Coord, TexCoord: TVector2): Single;
// const
//   { Idea, maybe useful --- apply heterogeneous only on higher octaves.
//     Note that 1st octave is anyway always without heterogeneous,
//     so this is really useful only if setting to >= 2. }
//   HomogeneousOctaves = 2;
var
  A, F, NoiseAccumulator: Single;

  function NextOctave(const OctaveNumber: Cardinal): Single;
  begin
    { An explicit check for "Heterogeneous = 0" case is needed.

      Otherwise, when Heterogeneous = 0, "NoiseAccumulator /= Heterogeneous"
      calculates "0 / 0", which will not get us what we want.
      (What we want is to have NoiseAccumulator=+infinity,
      so that it gets clamped to 1, but it seems FPC 2.2.4 doesn't do this.
      FPC 2.4.0 seems to land on +infinity more often,
      but not when using Spline interpolation... Looks like "0 / 0"
      is simply undefined, and unsafe to use.)

      Note there's no need to check for IsZero(Heterogeneous).
      When Heterogeneous is close to zero, but not exactly zero,
      the +infinity trick will make the later code behave Ok. }
    if Heterogeneous = 0 then
      Exit(NoiseMethod(
        Coord.X * F,
        Coord.Y * F, OctaveNumber + Seed) * A);

    NoiseAccumulator := NoiseAccumulator / Heterogeneous;
    { Following Musgrave's dissertation, we should now force
      NoiseAccumulator to <0, 1> range.
      We know our NoiseMethod is always positive, and we require
      Amplitude, Heterogeneous and such to also be always positive.
      So we already know NoiseAccumulator is always >= 0. }
    MinVar(NoiseAccumulator, 1);

    NoiseAccumulator := NoiseAccumulator * NoiseMethod(
      Coord.X * F,
      Coord.Y * F, OctaveNumber + Seed);

    Result := NoiseAccumulator * A;
  end;

var
  I: Cardinal;
begin
  Result := 0;

  A := Amplitude;
  F := Frequency;
  { This will accumulate multiplication of noise octaves.
    Initial value is chosen so that at first step (I = 1)
    NoiseAccumulator will become 1.0, and then NoiseMethod() * A. }
  NoiseAccumulator := Heterogeneous;
  for I := 1 to Trunc(Octaves) do
  begin
    Result := Result + NextOctave(I);
    F := F * 2;
    A := A / Smoothness;
  end;

  { Add last octave's remainder.
    Just like a normal octave, but multiply by Frac(Octaves). }
  Result := Result + Frac(Octaves) * NextOctave(Trunc(Octaves) + 1);
end;

function TCastleTerrainNoise.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Octaves', 'Smoothness', 'Amplitude', 'Frequency', 'Interpolation', 'Blur', 'Seed', 'Heterogeneous'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

{ TCastleTerrainCombine ------------------------------------------------------ }

function CombineOperationMax(const A, B: Single): Single;
begin
  Result := Max(A, B);
end;

function CombineOperationMin(const A, B: Single): Single;
begin
  Result := Min(A, B);
end;

function CombineOperationAdd(const A, B: Single): Single;
begin
  Result := A + B;
end;

function CombineOperationMultiply(const A, B: Single): Single;
begin
  Result := A * B;
end;

constructor TCastleTerrainCombine.Create(AOwner: TComponent);
begin
  inherited;
  FData1Observer := TFreeNotificationObserver.Create(Self);
  FData1Observer.OnFreeNotification := {$ifdef FPC}@{$endif} Data1FreeNotification;
  FData2Observer := TFreeNotificationObserver.Create(Self);
  FData2Observer.OnFreeNotification := {$ifdef FPC}@{$endif} Data2FreeNotification;
  FOperation := DefaultOperation;
  UpdateOperationFunc;
end;

procedure TCastleTerrainCombine.UpdateOperationFunc;
begin
  case FOperation of
    opMax: FOperationFunc := {$ifdef FPC}@{$endif} CombineOperationMax;
    opMin: FOperationFunc := {$ifdef FPC}@{$endif} CombineOperationMin;
    opAdd: FOperationFunc := {$ifdef FPC}@{$endif} CombineOperationAdd;
    opMultiply: FOperationFunc := {$ifdef FPC}@{$endif} CombineOperationMultiply;
    {$ifndef COMPILER_CASE_ANALYSIS}
    else raise EInternalError.Create('TCastleTerrainCombine.UpdateOperationFunc?');
    {$endif}
  end;
end;

procedure TCastleTerrainCombine.SetOperation(const Value: TCastleTerrainCombineOperation);
begin
  if FOperation <> Value then
  begin
    FOperation := Value;
    UpdateOperationFunc;
    DoChange;
  end;
end;

function TCastleTerrainCombine.Height(const Coord, TexCoord: TVector2): Single;
begin
  if (Data1 <> nil) and (Data2 <> nil) then
  begin
    Result := FOperationFunc(
      Data1.Height(Coord, TexCoord),
      Data2.Height(Coord, TexCoord)
    );
  end else
  if Data1 <> nil then
    Result := Data1.Height(Coord, TexCoord)
  else
  if Data2 <> nil then
    Result := Data2.Height(Coord, TexCoord)
  else
    Result := 0;
end;

function TCastleTerrainCombine.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Data1', 'Data2', 'Operation'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTerrainCombine.Data1FreeNotification(const Sender: TFreeNotificationObserver);
begin
  Data1 := nil;
end;

procedure TCastleTerrainCombine.Data2FreeNotification(const Sender: TFreeNotificationObserver);
begin
  Data2 := nil;
end;

procedure TCastleTerrainCombine.Data1Changed(Sender: TObject);
begin
  DoChange;
end;

procedure TCastleTerrainCombine.Data2Changed(Sender: TObject);
begin
  DoChange;
end;

function ContainsData(const Tree, ValueToFind: TCastleTerrainData): Boolean;
begin
  Result :=
    (Tree = ValueToFind) or
    (
      (Tree is TCastleTerrainCombine) and (
        ContainsData(TCastleTerrainCombine(Tree).Data1, ValueToFind) or
        ContainsData(TCastleTerrainCombine(Tree).Data2, ValueToFind)
      )
    );
end;

procedure TCastleTerrainCombine.SetData1(const Value: TCastleTerrainData);
begin
  if FData1 <> Value then
  begin
    { Ignore nonsense assignment done by FpRttiJson when this node references
      in JSON non-yet-known name. See TCastleTerrain.SetData comments. }
    if (Value <> nil) and
       (Value.ClassType = TCastleTerrainData) then
      Exit;

    // Protect from recursive usage hanging the process (editor or runtime)
    if (Value <> nil) and
       ContainsData(Value, Self) then
    begin
      raise Exception.CreateFmt('Setting %s as data for %s would make a recursive dependency (infinite calculation) in TCastleTerrainCombine', [
        Value.Name,
        Name
      ]);
      Exit;
    end;

    if FData1 <> nil then
      FData1.RemoveChangeNotification({$ifdef FPC}@{$endif} Data1Changed);
    FData1 := Value;
    FData1Observer.Observed := Value;
    if FData1 <> nil then
      FData1.AddChangeNotification({$ifdef FPC}@{$endif} Data1Changed);
    DoChange;
  end;
end;

procedure TCastleTerrainCombine.SetData2(const Value: TCastleTerrainData);
begin
  if FData2 <> Value then
  begin
    { Ignore nonsense assignment done by FpRttiJson when this node references
      in JSON non-yet-known name. See TCastleTerrain.SetData comments. }
    if (Value <> nil) and
       (Value.ClassType = TCastleTerrainData) then
      Exit;

    // Protect from recursive usage hanging the process (editor or runtime)
    if (Value <> nil) and
       ContainsData(Value, Self) then
    begin
      raise Exception.CreateFmt('Setting %s and data for %s would make a recursive dependency (infinite calculation) in TCastleTerrainCombine', [
        Value.Name,
        Name
      ]);
      Exit;
    end;

    if FData2 <> nil then
      FData2.RemoveChangeNotification({$ifdef FPC}@{$endif} Data2Changed);
    FData2 := Value;
    FData2Observer.Observed := Value;
    if FData2 <> nil then
      FData2.AddChangeNotification({$ifdef FPC}@{$endif} Data2Changed);
    DoChange;
  end;
end;

{ TCastleTerrainLayer -------------------------------------------------------- }

const
  { URL of a white pixel texture, embedded PPM.
    See http://netpbm.sourceforge.net/doc/ppm.html . }
  WhitePixel = 'data:image/x-portable-pixmap,P3'#10 +
    '1 1'#10 +
    '255'#10 +
    '255 255 255';

constructor TCastleTerrainLayer.Create(AOwner: TComponent);
begin
  inherited;
  raise Exception.Create('TCastleTerrainLayer can only be instantiated by TCastleTerrain as a subcomponent');
end;

constructor TCastleTerrainLayer.CreateForTerrain(const ATerrain: TCastleTerrain;
  const ALayer: Integer; const Effect: TEffectNode);
var
  TextureField: TSFNode;
begin
  inherited Create(ATerrain);
  Terrain := ATerrain;
  Layer := ALayer;

  TextureNode := TImageTextureNode.Create;
  TextureNode.SetUrl([WhitePixel]);
  TextureField := TSFNode.Create(Effect, false, 'tex_' + IntToStr(Layer), [], TextureNode);
  Effect.AddCustomField(TextureField);


  ColorField := TSFColor.Create(Effect, true, 'color_' + IntToStr(Layer), WhiteRGB);
  Effect.AddCustomField(ColorField);

  {$define read_implementation_constructor}
  {$I auto_generated_persistent_vectors/tcastleterrainlayer_persistent_vectors.inc}
  {$undef read_implementation_constructor}
end;

destructor TCastleTerrainLayer.Destroy;
begin
  {$define read_implementation_destructor}
  {$I auto_generated_persistent_vectors/tcastleterrainlayer_persistent_vectors.inc}
  {$undef read_implementation_destructor}
  inherited;
end;

function TCastleTerrainLayer.GetUsingPackedVector(const Vec: TSFVec4f): Single;
begin
  Result := Vec.Value[Layer - 1];
end;

procedure TCastleTerrainLayer.SetUsingPackedVector(const Vec: TSFVec4f; const Value: Single);
var
  V: TVector4;
begin
  V := Vec.Value;
  V.Data[Layer - 1] := Value;
  Vec.Send(V);
end;

function TCastleTerrainLayer.GetUvScale: Single;
begin
  Result := GetUsingPackedVector(Terrain.UvScaleField);
end;

procedure TCastleTerrainLayer.SetUvScale(const Value: Single);
begin
  SetUsingPackedVector(Terrain.UvScaleField, Value);
end;

function TCastleTerrainLayer.GetMetallic: Single;
begin
  Result := GetUsingPackedVector(Terrain.MetallicField);
end;

procedure TCastleTerrainLayer.SetMetallic(const Value: Single);
begin
  SetUsingPackedVector(Terrain.MetallicField, Value);
end;

function TCastleTerrainLayer.GetRoughness: Single;
begin
  Result := GetUsingPackedVector(Terrain.RoughnessField);
end;

procedure TCastleTerrainLayer.SetRoughness(const Value: Single);
begin
  SetUsingPackedVector(Terrain.RoughnessField, Value);
end;

function TCastleTerrainLayer.GetColor: TCastleColorRGB;
begin
  Result := ColorField.Value;
end;

procedure TCastleTerrainLayer.SetColor(const Value: TCastleColorRGB);
begin
  ColorField.Send(Value);
end;

function TCastleTerrainLayer.GetTexture: String;
begin
  if TextureNode.FdUrl.Count = 2 then // [image url, WhitePixel]
    Result := TextureNode.FdUrl.Items[0]
  else
    Result := '';
end;

procedure TCastleTerrainLayer.SetTexture(const Value: String);
begin
  if GetTexture() <> Value then
  begin
    if Value <> '' then
      TextureNode.SetUrl([Value, WhitePixel])
    else
      TextureNode.SetUrl([WhitePixel]);
    // TODO: Only this will properly update the shader uniform to use new texture
    Terrain.Scene.ChangedAll;
  end;
end;

function TCastleTerrainLayer.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
     'UvScale', 'ColorPersistent', 'Texture', 'Metallic', 'Roughness'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

{$define read_implementation_methods}
{$I auto_generated_persistent_vectors/tcastleterrainlayer_persistent_vectors.inc}
{$undef read_implementation_methods}

{ TCastleTerrain ------------------------------------------------------------- }

constructor TCastleTerrain.Create(AOwner: TComponent);

  procedure AdjustAppearance;
  var
    VertexPart, FragmentPart: TEffectPartNode;
    I: Integer;
  begin
    { initialize Effect node, for a shader effect }
    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    { If no light sources are present, it is normal that almost all uniforms
      in this effect do not exist -- because they affect only
      the TPhysicalMaterialNode.BaseTexture, which is meaningless when no light shines. }
    Effect.UniformMissing := umIgnore;
    Appearance.SetEffects([Effect]);

    UvScaleField := TSFVec4f.Create(Effect, true, 'uv_scale', Vector4(
      TCastleTerrainLayer.DefaultUvScale,
      TCastleTerrainLayer.DefaultUvScale,
      TCastleTerrainLayer.DefaultUvScale,
      TCastleTerrainLayer.DefaultUvScale));
    Effect.AddCustomField(UvScaleField);

    MetallicField := TSFVec4f.Create(Effect, true, 'metallic', Vector4(
      TCastleTerrainLayer.DefaultMetallic,
      TCastleTerrainLayer.DefaultMetallic,
      TCastleTerrainLayer.DefaultMetallic,
      TCastleTerrainLayer.DefaultMetallic));
    Effect.AddCustomField(MetallicField);

    RoughnessField := TSFVec4f.Create(Effect, true, 'roughness', Vector4(
      TCastleTerrainLayer.DefaultRoughness,
      TCastleTerrainLayer.DefaultRoughness,
      TCastleTerrainLayer.DefaultRoughness,
      TCastleTerrainLayer.DefaultRoughness));
    Effect.AddCustomField(RoughnessField);

    for I := 1 to HeightsCount do
    begin
      HeightsFields[I] := TSFFloat.Create(Effect, true, 'height_' + IntToStr(I), DefaultHeight[I]);
      Effect.AddCustomField(HeightsFields[I]);
    end;

    Effect.AddCustomField(TSFFloat.Create(Effect, true, 'layers_influence', FLayersInfluence));
    Effect.AddCustomField(TSFFloat.Create(Effect, true, 'steep_emphasize', FSteepEmphasize));

    SplatmapNode := TPixelTextureNode.Create;
    SplatmapNode.RepeatS := false;
    SplatmapNode.RepeatT := false;
    SplatmapNode.FdImage.Value := TRGBAlphaImage.Create(1, 1);
    TRGBAlphaImage(SplatmapNode.FdImage.Value).PixelPtr(0, 0)^ := Vector4Byte(255, 0, 0, 0);
    Effect.AddCustomField(TSFNode.Create(Effect, false, 'splatmap_tex', [], SplatmapNode));

    SplatmapInfluenceField := TSFFloat.Create(Effect, true, 'splatmap_influence', FSplatmapInfluence);
    Effect.AddCustomField(SplatmapInfluenceField);

    TerrainSizeField := TSFVec2f.Create(Effect, true, 'terrain_size', FSize);
    Effect.AddCustomField(TerrainSizeField);

    { initialize 2 EffectPart nodes (one for vertex shader, one for fragment shader) }
    FragmentPart := TEffectPartNode.Create;
    FragmentPart.ShaderType := stFragment;
    FragmentPart.Contents := {$I terrain.fs.inc};

    VertexPart := TEffectPartNode.Create;
    VertexPart.ShaderType := stVertex;
    VertexPart.Contents := {$I terrain.vs.inc};

    Effect.SetParts([FragmentPart, VertexPart]);

    { make the material lit }
    Appearance.Material := TPhysicalMaterialNode.Create;
  end;

var
  Layer: Cardinal;
begin
  inherited;

  FTriangulationIgnoreHeights := DefaultTriangulationIgnoreHeights;
  FSubdivisions := Vector2(DefaultSubdivisions, DefaultSubdivisions);
  FSize := Vector2(DefaultSize, DefaultSize);
  FLayersInfluence := DefaultLayersInfluence;
  FSteepEmphasize := DefaultSteepEmphasize;
  FSplatmapInfluence := DefaultSplatmapInfluence;
  FPreciseCollisions := true;

  Scene := TCastleScene.Create(Self);
  //Scene.ProcessEvents := true; // not necessary right now for anything
  Scene.SetTransient;
  Scene.PreciseCollisions := true;
  Add(Scene);

  Appearance := TAppearanceNode.Create;
  Appearance.WaitForRelease; // it's easiest to manage release of Appearance
  AdjustAppearance;

  for Layer := 1 to LayersCount do
  begin
    Layers[Layer] := TCastleTerrainLayer.CreateForTerrain(Self, Layer, Effect);
    Layers[Layer].SetSubComponent(true);
    Layers[Layer].Name := 'Layer' + IntToStr(Layer);
  end;

  FDataObserver := TFreeNotificationObserver.Create(Self);
  FDataObserver.OnFreeNotification := {$ifdef FPC}@{$endif} DataFreeNotification;

  UpdateGeometry;

  {$define read_implementation_constructor}
  {$I auto_generated_persistent_vectors/tcastleterrain_persistent_vectors.inc}
  {$undef read_implementation_constructor}
end;

destructor TCastleTerrain.Destroy;
begin
  {$define read_implementation_destructor}
  {$I auto_generated_persistent_vectors/tcastleterrain_persistent_vectors.inc}
  {$undef read_implementation_destructor}
  inherited;

  { Avoid Appearance having invalid reference in Appearance.Scene.
    Note that Scene was freed in "inherited" above,
    but Appearance.Scene may not have been cleared,
    because of optimization in TCastleSceneCore.FreeRootNode doing:

      if (FRootNode <> nil) and (not FOwnsRootNode) then
        FRootNode.UnregisterScene;

    See comments in TCastleSceneCore.FreeRootNode about it.

    To avoid crashes at examples/terrain exit, we have to clear
    Appearance.Scene manually, otherwise TAppearanceNode will try to access
    it in MoveShapeAssociations. }
  if Appearance <> nil then
    Appearance.UnregisterScene;

  // remove Appearance after RootNode containing this is removed too
  NodeRelease(Appearance);
end;

procedure TCastleTerrain.Loaded;
begin
  inherited;
  if FUpdateGeometryWhenLoaded then
  begin
    FUpdateGeometryWhenLoaded := false;
    Assert(not IsLoading);
    UpdateGeometry;
  end;
end;

procedure TCastleTerrain.UpdateGeometry;

  function CreateQuadShape(const Range: TFloatRectangle): TAbstractChildNode;
  var
    QuadSet: TQuadSetNode;
    Coord: TCoordinateNode;
    Shape: TShapeNode;
    Transform: TTransformNode;
  begin
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      { Order of these points matter, must be CCW when observed from top,
        just like "real" terrain data generated by TCastleTerrainNoise.
        This way backface culling works in the same way. }
      Vector3(          0, 0, Range.Height),
      Vector3(Range.Width, 0, Range.Height),
      Vector3(Range.Width, 0,            0),
      Vector3(          0, 0,            0)
    ]);

    QuadSet := TQuadSetNode.CreateWithTransform(Shape, Transform);
    QuadSet.Coord := Coord;

    Shape.Appearance := Appearance;

    { We translate the quad by TTransformNode, to keep the vertex coordinates
      in object space consistent with what is generated by CreateNode,
      and make the texture UV coordinates start the same. }
    Transform.Translation := Vector3(Range.Left, 0, Range.Bottom);

    Result := Transform;
  end;

  { Update associated collider, e.g. to update TCastleMeshCollider to reflect new terrain. }
  procedure UpdateCollider;
  begin
    if Collider <> nil then
      Collider.InternalTransformChanged(Self);
  end;

var
  Root: TX3DRootNode;
  InputRange, OutputRange: TFloatRectangle;
begin
  { During deserialization, defer the real work to the Loaded moment,
    to avoid regenerating heights multiple times. }
  if IsLoading then
  begin
    FUpdateGeometryWhenLoaded := true;
    Exit;
  end;

  OutputRange := FloatRectangle(-Size.X/2, -Size.Y/2, Size.X, Size.Y);

  InputRange := OutputRange;
  InputRange.LeftBottom := InputRange.LeftBottom + QueryOffset;

  if Data <> nil then
  begin
    if TerrainNode = nil then
    begin
      TerrainNode := Data.CreateNode(Subdivisions, InputRange, OutputRange, Appearance, TriangulationIgnoreHeights);
      Root := TX3DRootNode.Create;
      Root.AddChildren(TerrainNode);
      Scene.Load(Root, true);
    end else
    begin
      Data.UpdateNode(TerrainNode, Subdivisions, InputRange, OutputRange, TriangulationIgnoreHeights);
    end;
  end else
  begin
    { When Data is empty, show a simple quad to visualize Size of the terrain. }
    Root := TX3DRootNode.Create;
    Root.AddChildren(CreateQuadShape(OutputRange));
    Scene.Load(Root, true);
    { Do not let subsequent calls to use TerrainNode as it was destroyed
      by Scene.Load above.
      Testcase: create TCastleTerrain and TCastleTerrainImage,
      assign TCastleTerrain.Data to TCastleTerrainImage, to nil, again to TCastleTerrainImage. }
    TerrainNode := nil;
  end;

  UpdateCollider;
end;

function TCastleTerrain.GetLayer(const Index: Integer): TCastleTerrainLayer;
begin
  Result := Layers[Index];
end;

function TCastleTerrain.GetRenderOptions: TCastleRenderOptions;
begin
  Result := Scene.RenderOptions;
end;

procedure TCastleTerrain.SetData(const Value: TCastleTerrainData);
begin
  if FData <> Value then
  begin
    { Ignore nonsense assignment done by FpRttiJson when this node references
      in JSON non-yet-known name. FpRttiJson then creates an instance of
      TCastleTerrainData and assigns it here -- a useless instance,
      that would actually cause trouble as it has abstract methods. }
    if (Value <> nil) and
       (Value.ClassType = TCastleTerrainData) then
      Exit;

    if FData <> nil then
      FData.RemoveChangeNotification({$ifdef FPC}@{$endif} DataChanged);
    FData := Value;
    FDataObserver.Observed := Value;
    if FData <> nil then
      FData.AddChangeNotification({$ifdef FPC}@{$endif} DataChanged);
    UpdateGeometry;
  end;
end;

procedure TCastleTerrain.DataChanged(Sender: TObject);
begin
  UpdateGeometry;
end;

procedure TCastleTerrain.DataFreeNotification(const Sender: TFreeNotificationObserver);
begin
  Data := nil;
end;

procedure TCastleTerrain.SetTriangulationIgnoreHeights(const Value: Boolean);
begin
  if FTriangulationIgnoreHeights <> Value then
  begin
    // free the TerrainNode and RootNode, even if already created, to create new one
    if TerrainNode <> nil then
    begin
      Scene.RootNode := nil; // will free TerrainNode and RootNode
      TerrainNode := nil;
    end;
    FTriangulationIgnoreHeights := Value;
    UpdateGeometry;
  end;
end;

procedure TCastleTerrain.SetSubdivisions(const Value: TVector2);
begin
  if not TVector2.PerfectlyEquals(FSubdivisions, Value) then
  begin
    FSubdivisions := Value;
    UpdateGeometry;
  end;
end;

procedure TCastleTerrain.SetSize(const Value: TVector2);
begin
  if not TVector2.PerfectlyEquals(FSize, Value) then
  begin
    FSize := Value;
    if TerrainSizeField <> nil then
      TerrainSizeField.Send(FSize);
    UpdateGeometry;
  end;
end;

procedure TCastleTerrain.SetQueryOffset(const Value: TVector2);
begin
  if not TVector2.PerfectlyEquals(FQueryOffset, Value) then
  begin
    FQueryOffset := Value;
    UpdateGeometry;
  end;
end;

function TCastleTerrain.GetHeight(const Index: Integer): Single;
begin
  Result := HeightsFields[Index].Value;
end;

procedure TCastleTerrain.SetHeight(const Index: Integer; const Value: Single);
begin
  HeightsFields[Index].Send(Value);
end;

procedure TCastleTerrain.SetLayersInfluence(const Value: Single);
begin
  if FLayersInfluence <> Value then
  begin
    FLayersInfluence := Value;
    (Effect.Field('layers_influence') as TSFFloat).Send(Value);
  end;
end;

procedure TCastleTerrain.SetSteepEmphasize(const Value: Single);
begin
  if FSteepEmphasize <> Value then
  begin
    FSteepEmphasize := Value;
    (Effect.Field('steep_emphasize') as TSFFloat).Send(Value);
  end;
end;

procedure TCastleTerrain.SetPreciseCollisions(const Value: Boolean);
begin
  if FPreciseCollisions <> Value then
  begin
    FPreciseCollisions := Value;
    Scene.PreciseCollisions := Value;
  end;
end;

procedure TCastleTerrain.SetSplatmapInfluence(const Value: Single);
begin
  if FSplatmapInfluence <> Value then
  begin
    FSplatmapInfluence := Value;
    if SplatmapInfluenceField <> nil then
      SplatmapInfluenceField.Send(Value);
  end;
end;

procedure TCastleTerrain.SetSplatmapUrl(const Value: String);
var
  NewImg: TRGBAlphaImage;
begin
  if FSplatmapUrl <> Value then
  begin
    if Value = '' then
    begin
      FSplatmapUrl := '';
      NewImg := TRGBAlphaImage.Create(1, 1);
      NewImg.PixelPtr(0, 0)^ := Vector4Byte(255, 0, 0, 0);
      SplatmapNode.FdImage.Value := NewImg;
      SplatmapNode.FdImage.Changed;
      Scene.ChangedAll;
    end else
    begin
      try
        NewImg := CastleImages.LoadImage(Value, [TRGBAlphaImage]) as TRGBAlphaImage;
        SplatmapNode.FdImage.Value := NewImg;
        SplatmapNode.FdImage.Changed;
        FSplatmapUrl := Value;
        Scene.ChangedAll;
      except
        on E: Exception do
        begin
          if CastleDesignMode then
            WritelnWarning('TCastleTerrain', 'Failed to load SplatmapUrl "%s": %s', [
              UriDisplay(Value),
              ExceptMessage(E)
            ])
          else
            raise;
        end;
      end;
    end;
  end;
end;

function TCastleTerrain.LocalPointToTexCoord(const LocalPt: TVector3): TVector2;
var
  SafeX, SafeY: Single;
begin
  SafeX := Max(FSize.X, 0.001);
  SafeY := Max(FSize.Y, 0.001);
  Result := Vector2(
    Clamped((LocalPt.X / SafeX) + 0.5, 0.0, 1.0),
    Clamped(0.5 - (LocalPt.Z / SafeY), 0.0, 1.0));
end;

function TCastleTerrain.WorldPointToTexCoord(const WorldPt: TVector3): TVector2;
begin
  if HasWorldTransform then
    Result := LocalPointToTexCoord(WorldToLocal(WorldPt))
  else
    Result := LocalPointToTexCoord(WorldPt - Translation);
end;

function TCastleTerrain.SampleHeightAtLocalXZ(const LocalX, LocalZ: Single): Single;
var
  TexC, InputC: TVector2;
begin
  if Data = nil then
    Exit(0.0);
  TexC := LocalPointToTexCoord(Vector3(LocalX, 0, LocalZ));
  InputC := Vector2(LocalX + FQueryOffset.X, LocalZ + FQueryOffset.Y);
  Result := Data.Height(InputC, TexC);
end;

function TCastleTerrain.RayCastWorld(const WorldRayOrigin, WorldRayDirection: TVector3;
  out HitWorldPoint: TVector3): Boolean;
var
  LocalOrigin, LocalDir: TVector3;
  RayHit: TRayCollision;
  SavedPrecise, SavedPickable: Boolean;
begin
  HitWorldPoint := TVector3.Zero;
  Result := false;
  if (Scene = nil) or WorldRayDirection.IsZero then
    Exit;

  if HasWorldTransform then
  begin
    LocalOrigin := WorldToLocal(WorldRayOrigin);
    LocalDir := WorldToLocalDirection(WorldRayDirection);
  end else
  begin
    LocalOrigin := WorldRayOrigin - Translation;
    LocalDir := WorldRayDirection;
  end;
  if LocalDir.IsZero then
    Exit;
  LocalDir := LocalDir.Normalize;

  SavedPrecise := Scene.PreciseCollisions;
  SavedPickable := Scene.Pickable;
  Scene.PreciseCollisions := true;
  Scene.Pickable := true;
  try
    RayHit := LocalRayCollision(LocalOrigin, LocalDir, nil);
    if RayHit <> nil then
    try
      if RayHit.Count > 0 then
      begin
        if HasWorldTransform then
          HitWorldPoint := LocalToWorld(RayHit[RayHit.Count - 1].Point)
        else
          HitWorldPoint := RayHit[RayHit.Count - 1].Point + Translation;
        Result := true;
      end;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Scene.PreciseCollisions := SavedPrecise;
    Scene.Pickable := SavedPickable;
  end;
end;

function UniqueTerrainComponentName(const AOwner: TComponent; const BaseName: String): String;
var
  Idx: Integer;
begin
  if (AOwner = nil) or (AOwner.FindComponent(BaseName) = nil) then
    Exit(BaseName);
  Idx := 1;
  repeat
    Result := BaseName + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

function TCastleTerrain.EnsureEditableHeightLayer(const OwnerForNewComponents: TComponent;
  const DefaultResolution: Cardinal): TCastleTerrainImage;
var
  EffectiveOwner: TComponent;
  CombineData: TCastleTerrainCombine;
  OldData: TCastleTerrainData;
begin
  if OwnerForNewComponents <> nil then
    EffectiveOwner := OwnerForNewComponents
  else
    EffectiveOwner := Owner;

  if FData is TCastleTerrainImage then
  begin
    Result := TCastleTerrainImage(FData);
    if Result.Image = nil then
      Result.CreateBlankImage(DefaultResolution, DefaultResolution,
        Lerp(0.5, Result.MinLevel, Result.MaxLevel));
    Exit;
  end;

  if (FData is TCastleTerrainCombine) and
     (TCastleTerrainCombine(FData).Operation = opAdd) then
  begin
    CombineData := TCastleTerrainCombine(FData);
    if CombineData.Data2 is TCastleTerrainImage then
    begin
      Result := TCastleTerrainImage(CombineData.Data2);
      if Result.Image = nil then
        Result.CreateBlankImage(DefaultResolution, DefaultResolution, 0.0);
      Exit;
    end;
    if CombineData.Data1 is TCastleTerrainImage then
    begin
      Result := TCastleTerrainImage(CombineData.Data1);
      if Result.Image = nil then
        Result.CreateBlankImage(DefaultResolution, DefaultResolution, 0.0);
      Exit;
    end;
  end;

  if FData = nil then
  begin
    Result := TCastleTerrainImage.Create(EffectiveOwner);
    Result.Name := UniqueTerrainComponentName(EffectiveOwner, 'TerrainHeightImage');
    Result.MinLevel := -5.0;
    Result.MaxLevel := 5.0;
    Result.CreateBlankImage(DefaultResolution, DefaultResolution, 0.0);
    Data := Result;
  end else
  begin
    OldData := FData;
    Result := TCastleTerrainImage.Create(EffectiveOwner);
    Result.Name := UniqueTerrainComponentName(EffectiveOwner, 'TerrainSculptLayer');
    Result.MinLevel := -1.0;
    Result.MaxLevel := 1.0;
    Result.CreateBlankImage(DefaultResolution, DefaultResolution, 0.0);

    CombineData := TCastleTerrainCombine.Create(EffectiveOwner);
    CombineData.Name := UniqueTerrainComponentName(EffectiveOwner, 'TerrainEditCombine');
    CombineData.Operation := opAdd;
    CombineData.Data1 := OldData;
    CombineData.Data2 := Result;
    Data := CombineData;
  end;
end;

function TCastleTerrain.SculptHeightAtWorldPoint(const WorldPt: TVector3;
  const WorldRadius: Single; const Mode: TTerrainSculptBrushMode;
  const Strength: Single; const FlattenTargetWorldY: Single;
  const OwnerForNewComponents: TComponent;
  const DefaultResolution: Cardinal): TCastleTerrainImage;
var
  LocalPt, FlattenLocalPt, LocalRadVecX, LocalRadVecZ: TVector3;
  CenterUV, RadiusUV: TVector2;
  LocalRadiusX, LocalRadiusZ: Single;
  BaseLayer: TCastleTerrainData;
  InputRange: TFloatRectangle;
begin
  Result := EnsureEditableHeightLayer(OwnerForNewComponents, DefaultResolution);
  if HasWorldTransform then
  begin
    LocalPt := WorldToLocal(WorldPt);
    LocalRadVecX := WorldToLocalDirection(Vector3(Max(WorldRadius, 0.01), 0, 0));
    LocalRadVecZ := WorldToLocalDirection(Vector3(0, 0, Max(WorldRadius, 0.01)));
    FlattenLocalPt := WorldToLocal(Vector3(WorldPt.X, FlattenTargetWorldY, WorldPt.Z));
  end else
  begin
    LocalPt := WorldPt - Translation;
    LocalRadVecX := Vector3(Max(WorldRadius, 0.01), 0, 0);
    LocalRadVecZ := Vector3(0, 0, Max(WorldRadius, 0.01));
    FlattenLocalPt := Vector3(WorldPt.X, FlattenTargetWorldY, WorldPt.Z) - Translation;
  end;
  CenterUV := LocalPointToTexCoord(LocalPt);
  LocalRadiusX := Max(LocalRadVecX.Length, 0.01);
  LocalRadiusZ := Max(LocalRadVecZ.Length, 0.01);

  RadiusUV := Vector2(
    LocalRadiusX / Max(FSize.X, 0.001),
    LocalRadiusZ / Max(FSize.Y, 0.001));

  BaseLayer := nil;
  if (FData is TCastleTerrainCombine) and
     (TCastleTerrainCombine(FData).Operation = opAdd) then
  begin
    if TCastleTerrainCombine(FData).Data2 = Result then
      BaseLayer := TCastleTerrainCombine(FData).Data1
    else if TCastleTerrainCombine(FData).Data1 = Result then
      BaseLayer := TCastleTerrainCombine(FData).Data2;
  end;

  InputRange := FloatRectangle(
    -FSize.X / 2 + FQueryOffset.X,
    -FSize.Y / 2 + FQueryOffset.Y,
    FSize.X, FSize.Y);

  Result.ApplySculptBrush(CenterUV, RadiusUV, Mode, Strength, FlattenLocalPt.Y,
    BaseLayer, InputRange);
end;

function TCastleTerrain.SplatmapImage: TRGBAlphaImage;
begin
  if (SplatmapNode <> nil) and (SplatmapNode.FdImage.Value is TRGBAlphaImage) then
    Result := TRGBAlphaImage(SplatmapNode.FdImage.Value)
  else
    Result := nil;
end;

procedure TCastleTerrain.CreateBlankSplatmap(const AWidth, AHeight: Cardinal;
  const DefaultLayer: Integer);
var
  W, H, I, Total: Cardinal;
  ClampedLayer: Integer;
  FillPixel: TVector4Byte;
  NewImg: TRGBAlphaImage;
  P: PVector4Byte;
begin
  W := Max(2, AWidth);
  H := Max(2, AHeight);
  ClampedLayer := Clamped(DefaultLayer, 1, LayersCount);
  FillPixel := Vector4Byte(0, 0, 0, 0);
  FillPixel.Data[ClampedLayer - 1] := 255;

  NewImg := TRGBAlphaImage.Create(W, H);
  Total := W * H;
  P := PVector4Byte(NewImg.RawPixels);
  for I := 0 to Total - 1 do
  begin
    P^ := FillPixel;
    Inc(P);
  end;

  SplatmapNode.FdImage.Value := NewImg;
  SplatmapNode.FdImage.Changed;
  SplatmapInfluence := 1.0;
end;

function TerrainSmoothStep(const Edge0, Edge1, X: Single): Single;
var
  T: Single;
begin
  if Abs(Edge1 - Edge0) < 1e-6 then
  begin
    if X >= Edge1 then Exit(1.0) else Exit(0.0);
  end;
  T := Clamped((X - Edge0) / (Edge1 - Edge0), 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

function NormalizeWeightsToBytes(const W0, W1, W2, W3: Single): TVector4Byte;
var
  SumW: Single;
  NW: array [0..3] of Single;
  B: array [0..3] of Integer;
  C, MaxIdx, SumB: Integer;
begin
  NW[0] := Max(0.0, W0);
  NW[1] := Max(0.0, W1);
  NW[2] := Max(0.0, W2);
  NW[3] := Max(0.0, W3);
  SumW := NW[0] + NW[1] + NW[2] + NW[3];
  if SumW < 1e-5 then
    Exit(Vector4Byte(255, 0, 0, 0));

  MaxIdx := 0;
  SumB := 0;
  for C := 0 to 3 do
  begin
    NW[C] := NW[C] / SumW;
    B[C] := Clamped(Round(NW[C] * 255.0), 0, 255);
    SumB := SumB + B[C];
    if NW[C] > NW[MaxIdx] then
      MaxIdx := C;
  end;
  B[MaxIdx] := Clamped(B[MaxIdx] + (255 - SumB), 0, 255);
  Result := Vector4Byte(B[0], B[1], B[2], B[3]);
end;

procedure TCastleTerrain.GenerateSplatmapFromProceduralLayers(const AWidth, AHeight: Cardinal);
var
  W, H, X, Y: Integer;
  NewImg: TRGBAlphaImage;
  StepX, StepZ, LocalX, LocalZ, CenterH, HX0, HX1, HZ0, HZ1: Single;
  NormalVec: TVector3;
  NormalSlope, HeightMix, FlatFactor, SteepFactor: Single;
begin
  W := Max(2, Integer(AWidth));
  H := Max(2, Integer(AHeight));
  NewImg := TRGBAlphaImage.Create(W, H);
  StepX := Max(FSize.X / Max(1, W - 1), 0.01);
  StepZ := Max(FSize.Y / Max(1, H - 1), 0.01);

  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      LocalX := (X / (W - 1) - 0.5) * FSize.X;
      LocalZ := (0.5 - Y / (H - 1)) * FSize.Y;
      CenterH := SampleHeightAtLocalXZ(LocalX, LocalZ);
      HX0 := SampleHeightAtLocalXZ(LocalX - StepX * 0.5, LocalZ);
      HX1 := SampleHeightAtLocalXZ(LocalX + StepX * 0.5, LocalZ);
      HZ0 := SampleHeightAtLocalXZ(LocalX, LocalZ - StepZ * 0.5);
      HZ1 := SampleHeightAtLocalXZ(LocalX, LocalZ + StepZ * 0.5);

      NormalVec := TVector3.CrossProduct(
        Vector3(0, HZ1 - HZ0, StepZ),
        Vector3(StepX, HX1 - HX0, 0)).Normalize;
      NormalSlope := Clamped(NormalVec.Y, 0.0, 1.0);
      HeightMix := TerrainSmoothStep(Height1, Height2, CenterH);
      FlatFactor := Clamped(Power(NormalSlope, Max(0.0, FSteepEmphasize)), 0.0, 1.0);
      SteepFactor := 1.0 - FlatFactor;

      NewImg.PixelPtr(X, Y)^ := NormalizeWeightsToBytes(
        FlatFactor  * (1.0 - HeightMix),
        SteepFactor * (1.0 - HeightMix),
        FlatFactor  * HeightMix,
        SteepFactor * HeightMix);
    end;

  SplatmapNode.FdImage.Value := NewImg;
  SplatmapNode.FdImage.Changed;
  SplatmapInfluence := 1.0;
end;

procedure TCastleTerrain.PaintSplatmapBrush(const CenterTexCoord, RadiusUV: TVector2;
  const LayerIndex: Integer; const Strength: Single;
  const DefaultResolution: Cardinal);
var
  Img, UpgradedImg: TRGBAlphaImage;
  InitColor: TVector4Byte;
  W, H, PX, PY, XMin, XMax, YMin, YMax, TargetChan, C: Integer;
  SafeRadX, SafeRadY, U, V, DistSq, Falloff, Alpha: Single;
  Weights: array [0..3] of Single;
  CurPx: TVector4Byte;
  I, Total: Cardinal;
  P: PVector4Byte;
  ModifiedAny: Boolean;
begin
  TargetChan := Clamped(LayerIndex, 1, LayersCount) - 1;
  Img := SplatmapImage;
  if (Img = nil) or ((Img.Width <= 1) and (Img.Height <= 1)) then
  begin
    if (Img <> nil) and (Img.Width = 1) and (Img.Height = 1) then
      InitColor := Img.PixelPtr(0, 0)^
    else
      InitColor := Vector4Byte(255, 0, 0, 0);
    UpgradedImg := TRGBAlphaImage.Create(Max(2, DefaultResolution), Max(2, DefaultResolution));
    Total := UpgradedImg.Width * UpgradedImg.Height;
    P := PVector4Byte(UpgradedImg.RawPixels);
    for I := 0 to Total - 1 do
    begin
      P^ := InitColor;
      Inc(P);
    end;
    SplatmapNode.FdImage.Value := UpgradedImg;
    Img := UpgradedImg;
  end;

  W := Img.Width;
  H := Img.Height;
  SafeRadX := Max(RadiusUV.X, 1.0 / Max(1, W));
  SafeRadY := Max(RadiusUV.Y, 1.0 / Max(1, H));

  XMin := Clamped(Floor((CenterTexCoord.X - SafeRadX) * Max(1, W - 1)), 0, W - 1);
  XMax := Clamped(Ceil ((CenterTexCoord.X + SafeRadX) * Max(1, W - 1)), 0, W - 1);
  YMin := Clamped(Floor((CenterTexCoord.Y - SafeRadY) * Max(1, H - 1)), 0, H - 1);
  YMax := Clamped(Ceil ((CenterTexCoord.Y + SafeRadY) * Max(1, H - 1)), 0, H - 1);

  ModifiedAny := false;
  for PY := YMin to YMax do
    for PX := XMin to XMax do
    begin
      if W > 1 then U := PX / (W - 1) else U := 0.5;
      if H > 1 then V := PY / (H - 1) else V := 0.5;
      DistSq := Sqr((U - CenterTexCoord.X) / SafeRadX) +
                Sqr((V - CenterTexCoord.Y) / SafeRadY);
      if DistSq < 1.0 then
      begin
        Falloff := Sqr(1.0 - DistSq);
        Alpha := Clamped(Strength * Falloff, 0.0, 1.0);
        CurPx := Img.PixelPtr(PX, PY)^;
        for C := 0 to 3 do
        begin
          Weights[C] := CurPx.Data[C] / 255.0;
          if C = TargetChan then
            Weights[C] := Lerp(Alpha, Weights[C], 1.0)
          else
            Weights[C] := Lerp(Alpha, Weights[C], 0.0);
        end;
        Img.PixelPtr(PX, PY)^ := NormalizeWeightsToBytes(
          Weights[0], Weights[1], Weights[2], Weights[3]);
        ModifiedAny := true;
      end;
    end;

  if ModifiedAny then
  begin
    SplatmapNode.FdImage.Changed;
    if FSplatmapInfluence <= 0.0 then
      SplatmapInfluence := 1.0;
  end;
end;

procedure TCastleTerrain.PaintSplatmapAtWorldPoint(const WorldPt: TVector3;
  const WorldRadius: Single; const LayerIndex: Integer;
  const Strength: Single; const DefaultResolution: Cardinal);
var
  LocalRadVecX, LocalRadVecZ: TVector3;
  RadiusUV: TVector2;
begin
  if HasWorldTransform then
  begin
    LocalRadVecX := WorldToLocalDirection(Vector3(Max(WorldRadius, 0.01), 0, 0));
    LocalRadVecZ := WorldToLocalDirection(Vector3(0, 0, Max(WorldRadius, 0.01)));
  end else
  begin
    LocalRadVecX := Vector3(Max(WorldRadius, 0.01), 0, 0);
    LocalRadVecZ := Vector3(0, 0, Max(WorldRadius, 0.01));
  end;
  RadiusUV := Vector2(
    Max(LocalRadVecX.Length, 0.01) / Max(FSize.X, 0.001),
    Max(LocalRadVecZ.Length, 0.01) / Max(FSize.Y, 0.001));
  PaintSplatmapBrush(WorldPointToTexCoord(WorldPt), RadiusUV, LayerIndex,
    Strength, DefaultResolution);
end;

procedure TCastleTerrain.SaveSplatmap(const SaveUrl: String);
var
  Img: TRGBAlphaImage;
begin
  if SaveUrl = '' then
    raise Exception.Create('TCastleTerrain.SaveSplatmap requires a non-empty URL');
  Img := SplatmapImage;
  if (Img = nil) or ((Img.Width <= 1) and (Img.Height <= 1)) then
    CreateBlankSplatmap(128, 128, 1);
  CastleImages.SaveImage(SplatmapImage, SaveUrl);
  FSplatmapUrl := SaveUrl;
end;

function TCastleTerrain.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'RenderOptions', 'Data', 'TriangulationIgnoreHeights', 'SubdivisionsPersistent',
       'SizePersistent', 'PreciseCollisions',
       'Height1', 'Height2',
       'Layer1', 'Layer2', 'Layer3', 'Layer4',
       'LayersInfluence', 'SteepEmphasize',
       'SplatmapInfluence', 'SplatmapUrl',
       'QueryOffsetPersistent'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleTerrain.HasColliderMesh: Boolean;
begin
  Result := true;
end;

procedure TCastleTerrain.ColliderMesh(const TriangleEvent: TTriangleEvent);
begin
  Scene.ColliderMesh(TriangleEvent);
end;

function TCastleTerrain.InternalBuildNodeInside: TObject;
begin
  if Scene.RootNode <> nil then
    Result := Scene.RootNode.DeepCopy
  else
    Result := nil;
end;

{$define read_implementation_methods}
{$I auto_generated_persistent_vectors/tcastleterrain_persistent_vectors.inc}
{$undef read_implementation_methods}

initialization
  RegisterSerializableComponent(TCastleTerrainImage, ['Terrain Data (Experimental)', 'Image Data']);
  RegisterSerializableComponent(TCastleTerrainNoise, ['Terrain Data (Experimental)', 'Noise Data']);
  RegisterSerializableComponent(TCastleTerrainCombine, ['Terrain Data (Experimental)', 'Combine Data']);
  RegisterSerializableComponent(TCastleTerrain, ['Terrain (Experimental)']);
end.

/* This library is plugged into both vertex and fragment shaders,
   and on OpenGLES a uniform used by both must have the same precision in both
   (otherwise the program doesn't link).
   The default float precision differs: highp in vertex shaders,
   mediump in our fragment shaders (see TGLSLProgram.AttachShader).
   So declare the precision explicitly. */
#ifdef GL_ES
  #ifdef GL_FRAGMENT_PRECISION_HIGH
    #define CASTLE_EYE_WORLD_SPACE_PRECISION highp
  #else
    #define CASTLE_EYE_WORLD_SPACE_PRECISION mediump
  #endif
#else
  #define CASTLE_EYE_WORLD_SPACE_PRECISION
#endif

uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat4 castle_CameraMatrix;
/* On OpenGLES the shader code is glued, and the vertex shader may already
   declare castle_CameraInverseMatrix (for texture coordinate generation). */
#ifndef CASTLE_CAMERA_INVERSE_MATRIX_DECLARED
uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat4 castle_CameraInverseMatrix;
#endif
uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat3 castle_CameraRotationMatrix;
uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat3 castle_CameraRotationInverseMatrix;

vec4 position_world_to_eye_space(vec4 position_world)
{
  return castle_CameraMatrix * position_world;
}

vec4 position_eye_to_world_space(vec4 position_eye)
{
  return castle_CameraInverseMatrix * position_eye;
}

vec3 direction_world_to_eye_space(vec3 direction_world)
{
  return castle_CameraRotationMatrix * direction_world;
}

vec3 direction_eye_to_world_space(vec3 direction_eye)
{
  return castle_CameraRotationInverseMatrix * direction_eye;
}

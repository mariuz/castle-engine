{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/shader_libraries/EyeWorldSpace.glsl" }
'/* This library is plugged into both vertex and fragment shaders,' + LineEnding +
'   and on OpenGLES a uniform used by both must have the same precision in both' + LineEnding +
'   (otherwise the program doesn''t link).' + LineEnding +
'   The default float precision differs: highp in vertex shaders,' + LineEnding +
'   mediump in our fragment shaders (see TGLSLProgram.AttachShader).' + LineEnding +
'   So declare the precision explicitly. */' + LineEnding +
'#ifdef GL_ES' + LineEnding +
'  #ifdef GL_FRAGMENT_PRECISION_HIGH' + LineEnding +
'    #define CASTLE_EYE_WORLD_SPACE_PRECISION highp' + LineEnding +
'  #else' + LineEnding +
'    #define CASTLE_EYE_WORLD_SPACE_PRECISION mediump' + LineEnding +
'  #endif' + LineEnding +
'#else' + LineEnding +
'  #define CASTLE_EYE_WORLD_SPACE_PRECISION' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat4 castle_CameraMatrix;' + LineEnding +
'/* On OpenGLES the shader code is glued, and the vertex shader may already' + LineEnding +
'   declare castle_CameraInverseMatrix (for texture coordinate generation). */' + LineEnding +
'#ifndef CASTLE_CAMERA_INVERSE_MATRIX_DECLARED' + LineEnding +
'uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat4 castle_CameraInverseMatrix;' + LineEnding +
'#endif' + LineEnding +
'uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat3 castle_CameraRotationMatrix;' + LineEnding +
'uniform CASTLE_EYE_WORLD_SPACE_PRECISION mat3 castle_CameraRotationInverseMatrix;' + LineEnding +
'' + LineEnding +
'vec4 position_world_to_eye_space(vec4 position_world)' + LineEnding +
'{' + LineEnding +
'  return castle_CameraMatrix * position_world;' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'vec4 position_eye_to_world_space(vec4 position_eye)' + LineEnding +
'{' + LineEnding +
'  return castle_CameraInverseMatrix * position_eye;' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'vec3 direction_world_to_eye_space(vec3 direction_world)' + LineEnding +
'{' + LineEnding +
'  return castle_CameraRotationMatrix * direction_world;' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'vec3 direction_eye_to_world_space(vec3 direction_eye)' + LineEnding +
'{' + LineEnding +
'  return castle_CameraRotationInverseMatrix * direction_eye;' + LineEnding +
'}' + LineEnding +
''

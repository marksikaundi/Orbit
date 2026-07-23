/* Minimal OpenGL 3.3 core loader for Orbit on Windows (GLFW + glad-style). */
#ifndef ORBIT_GLAD_H
#define ORBIT_GLAD_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void GLvoid;
typedef unsigned int GLenum;
typedef float GLfloat;
typedef int GLint;
typedef int GLsizei;
typedef unsigned int GLbitfield;
typedef double GLdouble;
typedef unsigned int GLuint;
typedef unsigned char GLboolean;
typedef unsigned char GLubyte;
typedef char GLchar;
typedef ptrdiff_t GLsizeiptr;
typedef ptrdiff_t GLintptr;

#define GL_FALSE 0
#define GL_TRUE 1
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_TRIANGLES 0x0004
#define GL_BLEND 0x0BE2
#define GL_SRC_ALPHA 0x0302
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FLOAT 0x1406
#define GL_RGBA 0x1908
#define GL_NEAREST 0x2600
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_TEXTURE_2D 0x0DE1
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_TEXTURE0 0x84C0
#define GL_ARRAY_BUFFER 0x8892
#define GL_DYNAMIC_DRAW 0x88E8
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_VERTEX_SHADER 0x8B31
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84
#define GL_UNPACK_ALIGNMENT 0x0CF5

typedef void (*ORBIT_GLADloadproc)(const char *name);

int orbitGladLoadGL(ORBIT_GLADloadproc load);

extern void (*glActiveTexture)(GLenum texture);
extern void (*glAttachShader)(GLuint program, GLuint shader);
extern void (*glBindBuffer)(GLenum target, GLuint buffer);
extern void (*glBindTexture)(GLenum target, GLuint texture);
extern void (*glBindVertexArray)(GLuint array);
extern void (*glBlendFunc)(GLenum sfactor, GLenum dfactor);
extern void (*glBufferData)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
extern void (*glClear)(GLbitfield mask);
extern void (*glClearColor)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
extern void (*glCompileShader)(GLuint shader);
extern GLuint (*glCreateProgram)(void);
extern GLuint (*glCreateShader)(GLenum type);
extern void (*glDeleteBuffers)(GLsizei n, const GLuint *buffers);
extern void (*glDeleteProgram)(GLuint program);
extern void (*glDeleteShader)(GLuint shader);
extern void (*glDeleteTextures)(GLsizei n, const GLuint *textures);
extern void (*glDeleteVertexArrays)(GLsizei n, const GLuint *arrays);
extern void (*glDrawArrays)(GLenum mode, GLint first, GLsizei count);
extern void (*glEnable)(GLenum cap);
extern void (*glEnableVertexAttribArray)(GLuint index);
extern void (*glGenBuffers)(GLsizei n, GLuint *buffers);
extern void (*glGenTextures)(GLsizei n, GLuint *textures);
extern void (*glGenVertexArrays)(GLsizei n, GLuint *arrays);
extern void (*glGetProgramInfoLog)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
extern void (*glGetProgramiv)(GLuint program, GLenum pname, GLint *params);
extern void (*glGetShaderInfoLog)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
extern void (*glGetShaderiv)(GLuint shader, GLenum pname, GLint *params);
extern GLint (*glGetUniformLocation)(GLuint program, const GLchar *name);
extern void (*glLinkProgram)(GLuint program);
extern void (*glPixelStorei)(GLenum pname, GLint param);
extern void (*glShaderSource)(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length);
extern void (*glTexImage2D)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
extern void (*glTexParameteri)(GLenum target, GLenum pname, GLint param);
extern void (*glUniform1i)(GLint location, GLint v0);
extern void (*glUseProgram)(GLuint program);
extern void (*glVertexAttribPointer)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
extern void (*glViewport)(GLint x, GLint y, GLsizei width, GLsizei height);

#ifdef __cplusplus
}
#endif

#endif /* ORBIT_GLAD_H */

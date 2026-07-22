#include "glad.h"

void (*glActiveTexture)(GLenum texture);
void (*glAttachShader)(GLuint program, GLuint shader);
void (*glBindBuffer)(GLenum target, GLuint buffer);
void (*glBindTexture)(GLenum target, GLuint texture);
void (*glBindVertexArray)(GLuint array);
void (*glBlendFunc)(GLenum sfactor, GLenum dfactor);
void (*glBufferData)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
void (*glClear)(GLbitfield mask);
void (*glClearColor)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
void (*glCompileShader)(GLuint shader);
GLuint (*glCreateProgram)(void);
GLuint (*glCreateShader)(GLenum type);
void (*glDeleteBuffers)(GLsizei n, const GLuint *buffers);
void (*glDeleteProgram)(GLuint program);
void (*glDeleteShader)(GLuint shader);
void (*glDeleteTextures)(GLsizei n, const GLuint *textures);
void (*glDeleteVertexArrays)(GLsizei n, const GLuint *arrays);
void (*glDrawArrays)(GLenum mode, GLint first, GLsizei count);
void (*glEnable)(GLenum cap);
void (*glEnableVertexAttribArray)(GLuint index);
void (*glGenBuffers)(GLsizei n, GLuint *buffers);
void (*glGenTextures)(GLsizei n, GLuint *textures);
void (*glGenVertexArrays)(GLsizei n, GLuint *arrays);
void (*glGetProgramInfoLog)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void (*glGetProgramiv)(GLuint program, GLenum pname, GLint *params);
void (*glGetShaderInfoLog)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void (*glGetShaderiv)(GLuint shader, GLenum pname, GLint *params);
GLint (*glGetUniformLocation)(GLuint program, const GLchar *name);
void (*glLinkProgram)(GLuint program);
void (*glPixelStorei)(GLenum pname, GLint param);
void (*glShaderSource)(GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length);
void (*glTexImage2D)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
void (*glTexParameteri)(GLenum target, GLenum pname, GLint param);
void (*glUniform1i)(GLint location, GLint v0);
void (*glUseProgram)(GLuint program);
void (*glVertexAttribPointer)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
void (*glViewport)(GLint x, GLint y, GLsizei width, GLsizei height);

#define LOAD(fn, type) do { \
    void *ptr = (void *)load(#fn); \
    if (!ptr) return 0; \
    fn = (type)ptr; \
} while (0)

int orbitGladLoadGL(ORBIT_GLADloadproc load) {
    if (!load) return 0;
    LOAD(glActiveTexture, void (*)(GLenum));
    LOAD(glAttachShader, void (*)(GLuint, GLuint));
    LOAD(glBindBuffer, void (*)(GLenum, GLuint));
    LOAD(glBindTexture, void (*)(GLenum, GLuint));
    LOAD(glBindVertexArray, void (*)(GLuint));
    LOAD(glBlendFunc, void (*)(GLenum, GLenum));
    LOAD(glBufferData, void (*)(GLenum, GLsizeiptr, const void *, GLenum));
    LOAD(glClear, void (*)(GLbitfield));
    LOAD(glClearColor, void (*)(GLfloat, GLfloat, GLfloat, GLfloat));
    LOAD(glCompileShader, void (*)(GLuint));
    LOAD(glCreateProgram, GLuint (*)(void));
    LOAD(glCreateShader, GLuint (*)(GLenum));
    LOAD(glDeleteBuffers, void (*)(GLsizei, const GLuint *));
    LOAD(glDeleteProgram, void (*)(GLuint));
    LOAD(glDeleteShader, void (*)(GLuint));
    LOAD(glDeleteTextures, void (*)(GLsizei, const GLuint *));
    LOAD(glDeleteVertexArrays, void (*)(GLsizei, const GLuint *));
    LOAD(glDrawArrays, void (*)(GLenum, GLint, GLsizei));
    LOAD(glEnable, void (*)(GLenum));
    LOAD(glEnableVertexAttribArray, void (*)(GLuint));
    LOAD(glGenBuffers, void (*)(GLsizei, GLuint *));
    LOAD(glGenTextures, void (*)(GLsizei, GLuint *));
    LOAD(glGenVertexArrays, void (*)(GLsizei, GLuint *));
    LOAD(glGetProgramInfoLog, void (*)(GLuint, GLsizei, GLsizei *, GLchar *));
    LOAD(glGetProgramiv, void (*)(GLuint, GLenum, GLint *));
    LOAD(glGetShaderInfoLog, void (*)(GLuint, GLsizei, GLsizei *, GLchar *));
    LOAD(glGetShaderiv, void (*)(GLuint, GLenum, GLint *));
    LOAD(glGetUniformLocation, GLint (*)(GLuint, const GLchar *));
    LOAD(glLinkProgram, void (*)(GLuint));
    LOAD(glPixelStorei, void (*)(GLenum, GLint));
    LOAD(glShaderSource, void (*)(GLuint, GLsizei, const GLchar *const *, const GLint *));
    LOAD(glTexImage2D, void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *));
    LOAD(glTexParameteri, void (*)(GLenum, GLenum, GLint));
    LOAD(glUniform1i, void (*)(GLint, GLint));
    LOAD(glUseProgram, void (*)(GLuint));
    LOAD(glVertexAttribPointer, void (*)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void *));
    LOAD(glViewport, void (*)(GLint, GLint, GLsizei, GLsizei));
    return 1;
}

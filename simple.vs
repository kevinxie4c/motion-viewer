#version 330 core

layout (location = 0) in vec3 aPos;

uniform mat4 view;
uniform mat4 proj;

void main(void)
{
	gl_Position = proj * view * vec4(aPos.x, aPos.y, aPos.z, 1.0);
}

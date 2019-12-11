#version 330 core

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;

out vec3 normal;

uniform mat4 view;
uniform mat4 proj;
uniform mat4 model;

void main(void)
{
	gl_Position = proj * view * model * vec4(aPos, 1.0);
	normal = (model * vec4(aNormal, 0.0)).xyz;
}

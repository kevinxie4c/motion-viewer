#version 330 core

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;

out vec3 normal;
out vec4 fragPosLightSpace;
out vec4 wPos;

uniform mat4 view;
uniform mat4 proj;
uniform mat4 model;
uniform mat4 lightSpaceMatrix;

void main(void)
{
	gl_Position = proj * view * model * vec4(aPos, 1.0);
	normal = transpose(inverse(mat3(model))) * aNormal;
	fragPosLightSpace = lightSpaceMatrix * model * vec4(aPos, 1.0);
        wPos = model * vec4(aPos, 1.0);
}

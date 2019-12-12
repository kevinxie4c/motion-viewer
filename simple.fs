#version 330 core

in vec3 normal;
out vec4 FragColor;

uniform vec3 lightIntensity;
uniform vec3 lightDir;
uniform vec3 color;
uniform float alpha;

void main(void)
{
    vec4 color = vec4(1.0, 0.5, 0.2, 1.0);
	vec3 ambience = vec3(0.1);
	FragColor = vec4((ambience + lightIntensity * max(0, dot(-lightDir, normal))), alpha) * color;
}

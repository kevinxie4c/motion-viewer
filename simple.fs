#version 330 core

in vec3 normal;
in vec4 fragPosLightSpace;
out vec4 fragColor;

uniform sampler2D shadowMap;

uniform vec3 lightIntensity;
uniform vec3 lightDir;
uniform vec3 color;
uniform float alpha;
uniform int enableShadow;

void main(void)
{
	vec3 ambience = vec3(0.1);
	vec3 lighting = vec3(0.0);
	
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;
    float closestDepth = texture(shadowMap, projCoords.xy).r; 
    float currentDepth = projCoords.z;
	if (enableShadow == 0 || currentDepth - 1e-3 < closestDepth)
		lighting = lightIntensity * max(0, dot(-lightDir, normal));
	fragColor = vec4((ambience + lighting), alpha) * vec4(color, 1.0);
}

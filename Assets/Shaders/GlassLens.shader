Shader "Custom/GlassLens"
{
    Properties
    {
        // Glass appearance
        _GlassTint           ("Glass Tint",             Color)        = (0.90, 0.96, 1.0, 0.12)

        // Geometry
        _BulgeStrength       ("Bulge Strength",         Range(0,1))   = 1.0

        // Refraction
        _DistortionStrength  ("Distortion Strength",    Range(0,0.1)) = 0.025

        // Fresnel
        _FresnelPower        ("Fresnel Power",          Range(1,10))  = 5.0
        _FresnelStrength     ("Fresnel Strength",       Range(0,2))   = 0.8

        // Reflection
        _ReflectionStrength  ("Reflection Strength",    Range(0,2))   = 0.4

        // Material
        _Roughness           ("Roughness",              Range(0,1))   = 0.03
        _Metallic            ("Metallic",               Range(0,1))   = 0.0

        // Edge darkening
        _EdgeDarkening       ("Edge Darkening",         Range(0,1))   = 0.15
    }

    SubShader
    {
        // ------------------------------------------------
        // Queue and Tags
        // ------------------------------------------------
        // "Transparent" queue so it renders after opaques
        // (required for _CameraOpaqueTexture to be populated)
        Tags
        {
            "RenderType"            = "Transparent"
            "Queue"                 = "Transparent"
            "RenderPipeline"        = "UniversalPipeline"
            "IgnoreProjector"       = "True"
        }

        Pass
        {
            Name "GlassLensForward"
            Tags { "LightMode" = "UniversalForward" }

            // Match Godot's blend_mix + cull_back
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Back
            ZWrite Off           // transparent objects typically skip ZWrite

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            // URP includes — give us TransformObjectToHClip,
            // GetVertexPositionInputs, GetVertexNormalInputs, etc.
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ------------------------------------------------
            // IMPORTANT: tells URP to generate _CameraOpaqueTexture
            // Add this to your URP Renderer asset too:
            //   Renderer → Opaque Texture = ON
            // ------------------------------------------------
            #pragma multi_compile _ _SCREEN_SPACE_OCCLUSION

            // ------------------------------------------------
            // Uniforms / Properties
            // ------------------------------------------------
            CBUFFER_START(UnityPerMaterial)
                float4 _GlassTint;
                float  _BulgeStrength;
                float  _DistortionStrength;
                float  _FresnelPower;
                float  _FresnelStrength;
                float  _ReflectionStrength;
                float  _Roughness;
                float  _Metallic;
                float  _EdgeDarkening;
            CBUFFER_END

            // The opaque scene texture (equivalent to Godot's screen_texture)
            // Requires "Opaque Texture" enabled on the URP Renderer asset
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            // ------------------------------------------------
            // Structs
            // ------------------------------------------------
            struct Attributes
            {
                float4 positionOS : POSITION;   // object-space position
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS  : SV_POSITION;  // clip-space position
                float3 normalWS     : TEXCOORD0;     // world-space normal
                float3 viewDirWS    : TEXCOORD1;     // world-space view direction
                float2 uv           : TEXCOORD2;
                float4 screenPos    : TEXCOORD3;     // for screen UV sampling
            };

            // ------------------------------------------------
            // Vertex Shader
            // Godot: VERTEX.z += bulge * bulge_strength
            // Unity: same idea — offset along object-space Z before
            //        transforming to clip space
            // ------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // -- Bulge logic (mirrors Godot vertex shader) --
                float2 center = IN.uv - float2(0.5, 0.5);
                float  radius = length(center);

                // smoothstep(0.0, 0.7, radius): 0 at center → 1 at edge
                float bulge = 1.0 - smoothstep(0.0, 0.7, radius);

                // Push vertex outward along object-space Z
                float4 posOS = IN.positionOS;
                posOS.y += bulge * _BulgeStrength;

                // Standard URP transforms
                VertexPositionInputs posInputs    = GetVertexPositionInputs(posOS.xyz);
                VertexNormalInputs   normalInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.normalWS    = normalInputs.normalWS;
                OUT.viewDirWS   = GetWorldSpaceViewDir(posInputs.positionWS);
                OUT.uv          = IN.uv;

                // ComputeScreenPos converts clip-space → [0,1] screen UVs
                OUT.screenPos   = ComputeScreenPos(posInputs.positionCS);

                return OUT;
            }

            // ------------------------------------------------
            // Fragment Shader
            // ------------------------------------------------
            float4 frag(Varyings IN) : SV_Target
            {
                // ---- UV / radius (same as Godot) ----
                float2 center = IN.uv - float2(0.5, 0.5);
                float  radius = length(center);

                // ---- Screen UV from interpolated screen pos ----
                // Divide by .w to go from homogeneous → actual [0,1] UV
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;

                // ---- Refraction ----
                // distortion is stronger toward edges (quadratic, like Godot)
                float  distortion   = _DistortionStrength * radius * radius;
                float2 refractedUV  = screenUV + center * distortion;

                float3 screenColor  = SAMPLE_TEXTURE2D(
                    _CameraOpaqueTexture,
                    sampler_CameraOpaqueTexture,
                    refractedUV
                ).rgb;

                // ---- Base Glass Color ----
                float3 albedo = lerp(screenColor, _GlassTint.rgb, 0.08);
                float  alpha  = _GlassTint.a;

                // ---- Fresnel ----
                float3 N       = normalize(IN.normalWS);
                float3 V       = normalize(IN.viewDirWS);
                float  NdotV   = max(dot(N, V), 0.0);
                float  fresnel = pow(1.0 - NdotV, _FresnelPower);

                // ---- Fake Specular Reflection ----
                // Same hardcoded light direction as Godot
                float3 lightDir = normalize(float3(-0.4, 0.6, 1.0));
                float3 reflDir  = reflect(-lightDir, N);
                float  spec     = pow(max(dot(reflDir, V), 0.0), 100.0);

                // ---- Edge Darkening ----
                float edge = smoothstep(0.15, 0.70, radius);
                albedo    *= lerp(1.0, 1.0 - _EdgeDarkening, edge);

                // ---- Emission (fresnel rim + specular highlight) ----
                float3 emission = float3(1,1,1) * fresnel * _FresnelStrength;
                emission       += float3(1,1,1) * spec    * _ReflectionStrength;

                // ---- Final Output ----
                // albedo + emission combined into RGB; alpha for blend
                float3 finalColor = albedo + emission;
                return float4(finalColor, alpha);
            }

            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}

Shader "Custom/Hologram"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0,1,1,1)
        _FresnelColor ("Fresnel Color", Color) = (1,1,1,1)
        _FresnelPower ("Fresnel Power", Range(0.1,10)) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "Forward"

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
               float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

           CBUFFER_START(UnityPerMaterial)

            float4 _BaseColor;

            float4 _FresnelColor;

            float _FresnelPower;

            CBUFFER_END



            Varyings vert(Attributes input)
            {
                 Varyings output;

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(input.normalOS);

                output.positionCS = positionInputs.positionCS;

                output.positionWS = positionInputs.positionWS;

                output.normalWS = normalInputs.normalWS;

                

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                 float3 viewDir =
                normalize(GetCameraPositionWS() - input.positionWS);

                 float fresnel =
                    1.0 -
                    dot(normalize(input.normalWS), viewDir);

                fresnel = pow(fresnel, _FresnelPower);

                return _BaseColor + (_FresnelColor * fresnel);
            }

            ENDHLSL
        }
    }
}
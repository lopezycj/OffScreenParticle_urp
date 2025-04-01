Shader "Unlit/MergeShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
	SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off
        Pass
        {
            Name "ColorBlitPass"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // The Blit.hlsl file provides the vertex shader (Vert),
            // the input structure (Attributes) and the output structure (Varyings)
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex vert
            #pragma fragment frag
			
			float2 _LowResPixelSize;
			float2 _LowResTextureSize;
			float _DepthMult;
			float _Threshold;
            // Set the color texture from the camera as the input texture

			TEXTURE2D(_ParticleRT);
			TEXTURE2D(_CameraDepthLowRes);
			TEXTURE2D_FLOAT(_CameraDepthTexture);
			SAMPLER(sampler_ParticleRT);
			SAMPLER(sampler_CameraDepthLowRes);
			SAMPLER(sampler_CameraDepthTexture);
			SAMPLER(sampler_BlitTexture);

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 pos : SV_POSITION;
				float2 uv00 : TEXCOORD1;
				float2 uv10 : TEXCOORD2;
				float2 uv01 : TEXCOORD3;
				float2 uv11 : TEXCOORD4;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			v2f vert (Attributes input)
			{

				v2f output;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

			#if SHADER_API_GLES
				float4 pos = input.positionOS;
				float2 uv  = input.uv;
			#else
				float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
				float2 uv  = GetFullScreenTriangleTexCoord(input.vertexID);
			#endif

				output.pos = pos;
				output.uv   = uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
				// shift pixel by a half pixel, then create other uvs..
				output.uv00 = uv - 0.5 * _LowResPixelSize;
				output.uv10 = output.uv00 + float2(_LowResPixelSize.x, 0.0);
				output.uv01 = output.uv00 + float2(0.0, _LowResPixelSize.y);
				output.uv11 = output.uv00 + _LowResPixelSize;

				return output;
			}
			half4 ClosestDepthFast(v2f i)
			{
				// sample low res depth at pixel offsets
				float z00 = SAMPLE_TEXTURE2D(_CameraDepthLowRes, sampler_CameraDepthLowRes, i.uv00).r;
				float z10 = SAMPLE_TEXTURE2D(_CameraDepthLowRes, sampler_CameraDepthLowRes, i.uv10).r;
				float z01 = SAMPLE_TEXTURE2D(_CameraDepthLowRes, sampler_CameraDepthLowRes, i.uv01).r;
				float z11 = SAMPLE_TEXTURE2D(_CameraDepthLowRes, sampler_CameraDepthLowRes, i.uv11).r;

				float zfull = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).r;

				// compute distances between low and high res
				float dist00 = abs(z00-zfull);
				float dist10 = abs(z10-zfull);
				float dist01 = abs(z01-zfull);
				float dist11 = abs(z11-zfull);

				// pack uv and distance into float3 to prepare for fast selection
				// note, this could be sped up by packing into a float4 for each
				// component and doing the select that way..
				float3 uvd00 = float3(i.uv00, dist00);
				float3 uvd10 = float3(i.uv10, dist10);
				float3 uvd01 = float3(i.uv01, dist01);
				float3 uvd11 = float3(i.uv11, dist11);

				// using saturate and a muladd *should* be faster than step, since no
				// branch is required.
				float3 finalUV = lerp(uvd10, uvd00, saturate(99999*(uvd10.z-uvd00.z)));
				finalUV = lerp(uvd01, finalUV, saturate(99999*(uvd01.z -finalUV.z)));
				finalUV = lerp(uvd11, finalUV, saturate(99999*(uvd11.z-finalUV.z)));
				            
                float maxDist = max(max(max(dist00, dist10), dist01), dist11) - _Threshold;

				half4 mainColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, i.uv);

                // finally, lerp between the original UV and the edge uv based on the max distance
                half r = saturate(maxDist*99999);
                float2 uv = lerp(i.uv, finalUV.xy, r);

				half4 particleColor = SAMPLE_TEXTURE2D(_ParticleRT, sampler_ParticleRT, uv);

				half3 result= mainColor.rgb * (1.0h - particleColor.a) + particleColor.rgb * particleColor.a;
                return half4(result, 1.0h);
			}
         
			half4 frag (v2f i) : SV_Target
			{
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
				return ClosestDepthFast(i);
			}
            ENDHLSL
        }
    }
}

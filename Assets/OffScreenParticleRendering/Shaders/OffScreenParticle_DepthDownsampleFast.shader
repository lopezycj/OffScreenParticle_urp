// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

/// <summary>
/// Off Screen Particle Rendering System
/// ©2015 Disruptor Beam
/// Written by Jason Booth (slipster216@gmail.com)
/// </summary>

Shader "Hidden/OffScreenParticles/DepthDownsampleFast"
{
	
	Subshader {
	
		Pass {
			ZTest Always Cull Off ZWrite Off

			HLSLPROGRAM
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
			#pragma vertex vert
			#pragma fragment frag
			
			struct appdata
			{
				float4 vertex :POSITION;
				float2 uv : TEXCOORD0;
			};
			struct v2f {
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};
		
			TEXTURE2D_FLOAT( _CameraDepthTexture);
			SAMPLER(sampler_CameraDepthTexture);

			half _MSAA;

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

				#if UNITY_UV_STARTS_AT_TOP
				// the standard Unity if _MainTex_TexelSize doesn't work here, so we do this ourselves
				if (_MSAA > 0)
					output.uv.y = 1.0f - uv.y;
				#endif
				

				return output;
			}

			
	
			half4 frag(v2f i) : SV_Target 
			{
				float d = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).r;
				if(d>0.99999)
					return half4(1,1,1,1);
				else
					return half4(d,d,d,1); 
			}


			ENDHLSL
		}
	}

	Fallback off

} // shader
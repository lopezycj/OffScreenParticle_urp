// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

/// <summary>
/// Off Screen Particle Rendering System
/// ©2015 Disruptor Beam
/// Written by Jason Booth (slipster216@gmail.com)
///
///   Uses nearest depth upsampling to resolve a low res buffer to a high res buffer with minimal artifacts
///
/// </summary>

Shader "Hidden/OffScreenParticles/Upsample"
{
	SubShader 
	{
		Pass 
		{
			ZTest Always Cull Off ZWrite Off Fog { Mode Off }
			Blend SrcAlpha OneMinusSrcAlpha

			HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"


			
			TEXTURE2D( _ParticleRT);
			TEXTURE2D( _CameraDepthLowRes);
			TEXTURE2D_FLOAT( _CameraDepthTexture);
			float2 _LowResPixelSize;
			float2 _LowResTextureSize;
			float _DepthMult;
			float _Threshold;
			TEXTURE2D( _MainTex);
			float4 _MainTex_TexelSize;
			
			SAMPLER(sampler_ParticleRT);
			SAMPLER(sampler_CameraDepthLowRes);
			SAMPLER(sampler_CameraDepthTexture);
			SAMPLER(sampler_MainTex);

			struct appdata
			{
				float4 vertex :POSITION;
				float2 uv : TEXCOORD0;
			};
			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 pos : SV_POSITION;
				float2 uv00 : TEXCOORD1;
				float2 uv10 : TEXCOORD2;
				float2 uv01 : TEXCOORD3;
				float2 uv11 : TEXCOORD4;
			};
			
			v2f vert (appdata v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex.xyz);
				o.uv = v.uv;
				   
				// shift pixel by a half pixel, then create other uvs..
				o.uv00 = v.uv - 0.5 * _LowResPixelSize;
				o.uv10 = o.uv00 + float2(_LowResPixelSize.x, 0.0);
				o.uv01 = o.uv00 + float2(0.0, _LowResPixelSize.y);
				o.uv11 = o.uv00 + _LowResPixelSize;

			   return o;
			}
			
			// There are a number of techniques in the wild for dealing with the upsampling. I tried several,
			// and settled on this branchless variant I rolled myself. It's faster than any of the other
			// variants I looked into, and the artifacting on 1/4 or is barely noticable. It breaks down
			// a bit on 1/8; you could likely fix this by upsampling in stages, but for our game it wasn't
			// noticable enough to matter. 
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

                // finally, lerp between the original UV and the edge uv based on the max distance
                half r = saturate(maxDist*99999);
                float2 uv = lerp(i.uv, finalUV.xy, r);
                return SAMPLE_TEXTURE2D(_ParticleRT, sampler_ParticleRT, uv);
			}
         
			half4 frag (v2f i) : SV_Target
			{
				return ClosestDepthFast(i);
			}
			ENDHLSL
		}
	}
	Fallback Off
}
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

/// <summary>
/// Off Screen Particle Rendering System
/// ©2015 Disruptor Beam
/// Written by Jason Booth (slipster216@gmail.com)
/// </summary>

// example of a alpha-blend shader. Note, offscreen rendering requires premultiplied alpha and manual z-testing
// both of which can be done in the pixel shader.

Shader "OffScreenParticles/AlphaBlend" 
{
	Properties
    {
	   _TintColor ("Tint Color", Color) = (0.5,0.5,0.5,0.5)
	   _MainTex ("Particle Texture", 2D) = "white" {}
      _InvFade ("Soft Particles Factor", Range(0.01,3.0)) = 1.0
	}

    Category {
       Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" }
       Blend One OneMinusSrcAlpha // note, we use premultiplied alpha, so 1 (1-src)
       Cull Off Lighting Off ZWrite On ZTest Always
       SubShader 
       {
           Pass 
           {
                Tags {"LightMode"="OffScreenParticle"}
         	    HLSLPROGRAM
			    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
			    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
			    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
			    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #pragma vertex vert
			    #pragma fragment frag

                 SAMPLER(sampler_MainTex);
                 TEXTURE2D_FLOAT( _CameraDepthTexture);
                 TEXTURE2D(_MainTex);
                 SAMPLER(sampler_CameraDepthTexture);
                 CBUFFER_START(UnityPerMaterial)
                 half4 _TintColor;
                 float _InvFade;
                 CBUFFER_END
         
                 struct appdata_t {
                    float4 vertex : POSITION;
                    half4 color : COLOR;
                    float2 texcoord : TEXCOORD0;
                 };

                 struct v2f {
                    float4 vertex : SV_POSITION;
                    half4 color : COLOR;
                    float2 texcoord : TEXCOORD0;
                    float4 projPos : TEXCOORD1;
                 };
         
                 float4 _MainTex_ST;

                 v2f vert (appdata_t v)
                 {
                    v2f o;
                    o.vertex = TransformObjectToHClip(v.vertex.xyz);
                    o.projPos = ComputeScreenPos (o.vertex);
                    float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                    //o.projPos.xyz /= o.projPos.w;
                    //COMPUTE_EYEDEPTH(o.projPos.z);
                    o.projPos.z = -TransformWorldToView(worldPos).z;
                    o.color = v.color;
                    o.texcoord = v.texcoord;
                    return o;
                 }


                 half4 frag (v2f i) : SV_Target
                 {
                    half4 col = i.color * _TintColor * SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.texcoord);
                    // Do Z clip
                    //float2 screenUV = i.positionCS.xy / _ScreenParams.xy;
                    float2 wcoord = i.projPos.xy / i.projPos.w;
                    float depthTex = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture,wcoord).x;

                    float zbuf = LinearEyeDepth(depthTex,_ZBufferParams);
             
                    //float zbuf = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.projPos)));
			           float partZ = i.projPos.z;
			           float zalpha = saturate((zbuf - partZ + 1e-2f)*10000);//需要对当前渲染像素的深度值和场景深度做比较
                    // soft particle
                    float fade = saturate (_InvFade * (zbuf-partZ));
                    col.a *= zalpha * fade;
                    // premultiply alpha
                    col.rgb *= col.a;
        
                    return col;
                 }
                 ENDHLSL 
          }
       }  
    }
}
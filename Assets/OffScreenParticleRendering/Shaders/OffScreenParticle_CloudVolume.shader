Shader "OffScreenParticles/CloudVolume_Offscreen" 
{
    Properties 
    {
        _MainTex ("Particle Texture", 2D) = "white" {}
        _angle_bias("angle bias", Range(0.0, 0.99)) = 0.2
        _near_plane("near plane", Float) = 2
        _fade_in_distance("distance fade in", Float) = 30
        _fade_hold_distance("distance fade hold", Float) = 10000
        _fade_out_distance("distance fade out", Float) = 10000
        _color ("color", Color) = (1,1,1,1)
    }

    SubShader 
    {
        Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent"}
        Blend One OneMinusSrcAlpha // note, we use premultiplied alpha, so 1 (1-src)
        Cull Off Lighting Off ZWrite Off
        LOD 100
        Pass 
        {
            Tags {"LightMode"="OffScreenParticle"}
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture);
            SAMPLER(sampler_MainTex);
            SAMPLER(sampler_CameraDepthTexture);
            float _near_plane;
            float _fade_in_distance;
            float _fade_hold_distance;
            float _fade_out_distance;
            half  _angle_bias;
            float4 _color;

            struct appdata_t 
            {
                float4 vertex     : POSITION;
                float2 texcoord   : TEXCOORD0;
                half3  normal     : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f 
            {
                float4 positionCS    : SV_POSITION;
                float2 texcoord      : TEXCOORD0;
                float4 projPos       : TEXCOORD1;
                half  alpha         : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };



            v2f vert (appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                    
                float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.positionCS = TransformWorldToHClip(worldPos);
                o.projPos = ComputeScreenPos (o.positionCS);
                o.projPos.z = -TransformWorldToView(worldPos).z;
                //COMPUTE_EYEDEPTH(o.projPos.z);
                o.texcoord = v.texcoord;

                float3 normalDir = TransformObjectToWorldNormal(v.normal);
                float3 camVec = _WorldSpaceCameraPos - worldPos;
                o.alpha = saturate(abs(dot(normalDir, normalize(camVec))) - _angle_bias);
                o.alpha *= o.alpha;
                o.alpha *= o.alpha;

                // compute distance to camera; fade in from near plane distance -> fade in distance,
                // hold for a while, then fade out..
                float viewDist = length(camVec);
                half a1 = saturate((viewDist - _near_plane) / _fade_in_distance);
                half a2 = 1 - saturate((viewDist - _fade_in_distance - _fade_hold_distance) / _fade_out_distance); 
                o.alpha *= a1 * a2;

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.texcoord);
                // Do Z clip
                //float zbuf = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.projPos)));

                float2 wcoord = i.projPos.xy / i.projPos.w;
                float depthTex = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture,wcoord).x;

                float zbuf = LinearEyeDepth(depthTex,_ZBufferParams);

                //float zbuf = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.projPos).r;
                //zbuf = LinearEyeDepth(zbuf,_ZBufferParams);
                float partZ = i.projPos.z;
                float zalpha = saturate((zbuf - partZ + 1e-2f) * 10000);
                col.a = col.a * _color.a * i.alpha * zalpha; 
                // premultiply alpha
                col.rgb = _color.rgb * col.a;

                return col;
            }
            ENDHLSL 
        }
 
    }
}
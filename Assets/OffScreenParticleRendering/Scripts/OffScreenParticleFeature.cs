using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class OffScreenParticleFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class PassSettings
    {
        //when to inject the pass
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
        //name of the texture you can grab in shaders
        public string TextureName = "_ParticleRT";
        //only renders objects in the layers below
        public LayerMask LayerMask;
        public Downsampling downsampling;

        public Shader downSampleDepthShader;
    }

    OffScreenParticlePass particlePass;
    DownSampleDepthPass downSampleDepthPass;
    public PassSettings passSettings = new PassSettings();

    public override void Create()
    {
        particlePass = new OffScreenParticlePass(passSettings);
        downSampleDepthPass = new DownSampleDepthPass(passSettings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(particlePass);
        renderer.EnqueuePass(downSampleDepthPass);
    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        particlePass.Setup(renderingData.cameraData.cameraTargetDescriptor);
        //downSampleDepthPass.Setup(renderingData.cameraData.cameraTargetDescriptor);
    }
    protected override void Dispose(bool disposing)
    {
        particlePass?.Dispose();
        downSampleDepthPass?.Dispose();
    }
        
}

/// <summary>
/// 将场景中的Particle Layer的对象渲染到缩放分辨率后的_ParticleRT中
/// </summary>
public class OffScreenParticlePass : ScriptableRenderPass
{
    OffScreenParticleFeature.PassSettings passSettings;

    List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();
    FilteringSettings m_FilteringSettings;
    RenderStateBlock m_RenderStateBlock;
    //ProfilingSampler m_ProfilingSampler = new ProfilingSampler("OffScreenParticle");

    //Downsampling m_DownsamplingMethod;

    //RenderTargetIdentifier colorBuffer_old, temporaryBuffer_old;
    //int temporaryBufferID;
    RTHandle colorBuffer;
    RTHandle colorBuffer_Depth;

    public OffScreenParticlePass(OffScreenParticleFeature.PassSettings passSettings)
    {
        this.passSettings = passSettings;
        //temporaryBufferID = Shader.PropertyToID(passSettings.TextureName);

        renderPassEvent = passSettings.renderPassEvent;
		profilingSampler = new ProfilingSampler("OffScreenParticle");

        //m_ShaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
        //m_ShaderTagIdList.Add(new ShaderTagId("UniversalForward"));
        //m_ShaderTagIdList.Add(new ShaderTagId("LightweightForward"));
        m_ShaderTagIdList.Add(new ShaderTagId("OffScreenParticle"));//此Pass专门渲染Shader Pass中“LightMode”为“OffScreenParticle”的对象


        m_FilteringSettings = new FilteringSettings(RenderQueueRange.all, passSettings.LayerMask);
        m_RenderStateBlock = new RenderStateBlock(RenderStateMask.Nothing);
    }

    public void Setup(RenderTextureDescriptor baseDescriptor)
    {
         ConfigureInput(ScriptableRenderPassInput.Depth);
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;

        //could downscale things here if you wanted, maybe depending on performance might be okay 
        if (passSettings.downsampling == Downsampling._2xBilinear)
        {
            descriptor.width /= 2;
            descriptor.height /= 2;
        }
        else if (passSettings.downsampling == Downsampling._4xBox || passSettings.downsampling == Downsampling._4xBilinear)
        {
            descriptor.width /= 4;
            descriptor.height /= 4;
        }

        RenderingUtils.ReAllocateIfNeeded(ref colorBuffer_Depth, descriptor, name: "PrtDepth");


        RenderTextureDescriptor descColor = descriptor;
        descColor.depthBufferBits = 0; // No depth for the color texture
        RenderingUtils.ReAllocateIfNeeded(ref colorBuffer, descColor, FilterMode.Bilinear, name:passSettings.TextureName);

        cmd.SetGlobalTexture("_ParticleRT", colorBuffer);//这里的“_ParticleRT”来自MergeShader

        ConfigureTarget(colorBuffer, colorBuffer_Depth);
        ConfigureClear(ClearFlag.All, Color.clear);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();
        using (new ProfilingScope(cmd, profilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            DrawingSettings drawSettings;
            drawSettings = CreateDrawingSettings(m_ShaderTagIdList, ref renderingData, SortingCriteria.CommonTransparent);
            context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref m_FilteringSettings, ref m_RenderStateBlock);
        }
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        colorBuffer?.Release();
    }
}

/// <summary>
/// 将场景Depth进行降采样，并保存到_CameraDepthLowRes中
/// </summary>
public class  DownSampleDepthPass : ScriptableRenderPass
{
    OffScreenParticleFeature.PassSettings passSettings;
    

    private Material m_CopyDepthMaterial;

    RTHandle m_offScreenDepth;

    public DownSampleDepthPass(OffScreenParticleFeature.PassSettings passSettings)
    {
        this.passSettings = passSettings;
        renderPassEvent = passSettings.renderPassEvent;
        this.m_CopyDepthMaterial = new Material(passSettings.downSampleDepthShader);

        //m_offScreenDepth_old.Init("_CameraDepthLowRes");
        profilingSampler = new ProfilingSampler("DownSampleDepthPass");
    }


    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
        descriptor.colorFormat = RenderTextureFormat.Depth;
        //could downscale things here if you wanted, maybe depending on performance might be okay 
        if (passSettings.downsampling == Downsampling._2xBilinear)
        {
            descriptor.width /= 2;
            descriptor.height /= 2;
        }
        else if (passSettings.downsampling == Downsampling._4xBox || passSettings.downsampling == Downsampling._4xBilinear)
        {
            descriptor.width /= 4;
            descriptor.height /= 4;
        }
        ConfigureInput(ScriptableRenderPassInput.Depth);
        RenderingUtils.ReAllocateIfNeeded(ref m_offScreenDepth, descriptor, FilterMode.Bilinear, name: "_CameraDepthLowRes");
        cmd.SetGlobalTexture("_CameraDepthLowRes", m_offScreenDepth);
    }


    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();
        RenderTextureDescriptor Desc = renderingData.cameraData.cameraTargetDescriptor;

        RTHandle DepthHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

        using (new ProfilingScope(cmd, profilingSampler))
        {            
            cmd.EnableShaderKeyword(ShaderKeywordStrings.DepthNoMsaa);
            cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa2);
            cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa4);


            CoreUtils.SetRenderTarget(cmd, m_offScreenDepth);
            Blitter.BlitTexture(cmd, Vector2.one, m_CopyDepthMaterial, 0);

            context.ExecuteCommandBuffer(cmd);

            cmd.Clear();

            
        }
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        m_offScreenDepth?.Release();
    }

}
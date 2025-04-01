using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public class OffScreenMergeFeature : ScriptableRendererFeature
{
    public RenderObjectsSettings passSettings = new RenderObjectsSettings();
    OffScreenMergePass mergePass;
    public override void Create()
    {
        mergePass = new OffScreenMergePass(passSettings);

    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(mergePass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {

    }

    [System.Serializable]
    public class RenderObjectsSettings
    {
        public string passTag = "MergeFeature";
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Shader mergeShader;

        public float depthThreshold = 0.005f;
    }
}


public class OffScreenMergePass : ScriptableRenderPass
{
    private Material mergeMaterial = null;

    OffScreenMergeFeature.RenderObjectsSettings passSettings;


    RTHandle mergeRT;
    public OffScreenMergePass(OffScreenMergeFeature.RenderObjectsSettings passSettings)
    {
        this.passSettings = passSettings;
        this.mergeMaterial = new Material(passSettings.mergeShader);
        renderPassEvent = passSettings.renderPassEvent;

        profilingSampler = new ProfilingSampler("MergePass");

    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescripor)
    {
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        base.OnCameraSetup(cmd, ref renderingData);

        var desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        RenderingUtils.ReAllocateIfNeeded(ref mergeRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_mergeRT");
        cmd.SetGlobalTexture(mergeRT.name, mergeRT.nameID);


    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.isPreviewCamera) return;

        CommandBuffer cmd = CommandBufferPool.Get();
        RenderTextureDescriptor Desc = renderingData.cameraData.cameraTargetDescriptor;
        RTHandle colorHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
        //if(colorHandle.rt ==null) return;


        using (new ProfilingScope(cmd, profilingSampler))
        {
            Vector2 pixelSize = new Vector2(2.0f / Desc.width, 2.0f / Desc.height);
            mergeMaterial.SetVector("_LowResTextureSize", new Vector2(Desc.width/2, Desc.height/2));
            mergeMaterial.SetFloat("_DepthMult", 32.0f);
            mergeMaterial.SetFloat("_Threshold", passSettings.depthThreshold);

            CoreUtils.SetRenderTarget(cmd, mergeRT);

            Blitter.BlitCameraTexture(cmd, colorHandle, mergeRT, mergeMaterial, 0);
            Blitter.BlitCameraTexture(cmd, mergeRT, colorHandle);


        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        mergeRT?.Release();
    }
}

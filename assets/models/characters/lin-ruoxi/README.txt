若夕角色源文件：

  assets/models/characters/lin-ruoxi/lin-ruoxi.glb

已导入引擎资源：

  assets/Meshes/lin-ruoxi.mdl
  assets/Materials/lin-ruoxi_00_tripo_mat_8ae16fc0-7a3a-402e-9a6e-1180f6c269f7.xml
  assets/Textures/lin-ruoxi_00_D.jpg
  assets/Textures/lin-ruoxi_00_N.png
  assets/Prefabs/lin-ruoxi.prefab

如需重新导入：

  /workspace/.cli/UrhoXCLI import-gltf \
    -i /workspace/assets/models/characters/lin-ruoxi/lin-ruoxi.glb \
    -o /workspace/assets/Meshes/lin-ruoxi.mdl \
    --material-dir /workspace/assets/Materials \
    --texture-dir /workspace/assets/Textures \
    --prefab /workspace/assets/Prefabs/lin-ruoxi.prefab \
    --resource-root /workspace/assets \
    --no-lod

背景图（可选，不阻塞预览）放到：

  assets/Textures/backgrounds/la-cafe-4x3.png

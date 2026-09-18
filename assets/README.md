# 视觉样例与替换入口

2026-09-17 场景式 UI 试作。下列四张图使用 Codex 内置 imagegen 工具生成并复制到工程，未使用 CLI 或第三方 API。它们是验证界面的可替换视觉样例，不代表角色、建筑、季节或剧情美术定稿；不改变配置表与玩法数值。

| 文件 | 用途 | 当前格式与读取位置 |
|---|---|---|
| home_courtyard.png | 山居主场景 | 1672×941，不透明；main.gd 按比例铺满 |
| daughter_stages.png | 三个成长阶段立绘 | 当前 1536×1024，透明 PNG；从左到右三等宽列；家园与剧情回退共用 ui_theme.gd 的 daughter_portrait() |
| cave_valley.png | 洞天环境背景 | 1672×941，不透明；cave_ui.gd 按比例铺满 |
| cave_buildings.png | 七种建筑与入口 | 当前 1536×1024，透明 PNG；4 列×2 行；cave_board.gd 按实际纹理尺寸等分并保持单格比例 |

建筑图集按行从 0 编号：0 竹舍、1 灵田、2 林场、3 采石场、4 丹炉、5 稻草人、6 灵泉、7 入口。`cave.json` 的建筑可选填 `sprite_index`（整数 0–7），优先使用指定格；省略才按 category / work_type / 景观词条沿用同类映射，未知类型回退到 5。新增建筑无需修改 `_sprite_index()`；绘制与透明像素命中使用同一序号。

替换人物图时保持三等分列、人物底部对齐、真实 alpha 透明；替换建筑图时保持 4×2 等分网格与透明边距，入口仍使用第 7 格。整图分辨率可改变，不必保持 512×1024 或 384×512 单格尺寸。剧情中显式填写的 `portrait.region` 是绝对像素，换图后仍须同步修改；只有未填专用立绘的回退会自动三等分。改变网格布局而非分辨率仍需程序改动，建筑布局契约位于 `content_tables.gd` 的 `BUILDING_ATLAS_GRID`。运行中不读取原始生成目录，所有运行依赖都在工程内；Godot 自动生成 `.import` 文件。

`cultivation_home.png` 为已有素材，未覆盖。`icons/` 使用 Lucide，来源和许可证保留于该目录。中文界面使用系统字体，未将 macOS 字体文件打包进仓库。

## 生成记录

模式：内置 `image_gen.imagegen`，四次全新生成，无参考图片。以下保留原始提示词，供后续迭代；提示词中的目标尺寸以实际文件尺寸为准。

### 山居

原始输出：`exec-9a89a64a-5473-4418-861e-84f3ad5e0a1e.png`。

```text
Create a production-ready background illustration for a Chinese xianxia daughter-raising PC game, NOT a UI mockup. Wide 16:9 landscape, ideally 1920x1080. Refined 2D hand-painted game background, crisp illustrated details and soft painterly surfaces, expressive but not photorealistic, warm inviting sunlight. A secluded mountain village courtyard in early autumn: modest white-plaster timber house and grey-green tiled roof on the left, open wooden veranda with a small study desk, a few potted medicinal herbs, flagstone path and lush green grass in the foreground, distant blue-green mountains, a small pond and distant village roofs to the right. Camera at a comfortable human height, clear grounded perspective, foreground space for a character overlay at about 62% image width. The courtyard should be richly visible, not dark, blurred or covered with fog. Keep upper-left sky and far edges compositionally quiet for small game HUD overlays. Natural green and blue palette balanced with muted vermilion accents and sunlit white stone; not a brown/beige scene. NO PEOPLE, no animals, no text, no logos, no icons, no buttons, no cards, no borders, no UI elements, no glowing orbs. This is the actual full-screen place where the player spends the home phase, not a website hero or dashboard. Preserve readable empty standing space in the mid-right foreground.
```

### 人物

原始输出：`exec-1b6a6b83-a539-4e60-8d3b-39bfacf0f270.png`。

```text
Create a game character sprite sheet on a genuinely transparent alpha background, NOT a UI mockup. Landscape canvas 1536x1024. Exactly THREE distinct full-body character sprites, each centered inside its own equal-width vertical third (centers x=256,768,1280). Leave generous transparent gutters between characters, and all hair, sleeves and shoes wholly inside their respective third. Same Chinese xianxia girl at three visual stages: LEFT a four-year-old small child with two hair buns, CENTER a ten-year-old child with shoulder-length black hair partly tied, RIGHT a sixteen-year-old teenager with long black hair tied partly up. All wear age-appropriate modest pale white and muted jade-teal hanfu with narrow vermilion ribbons, long sleeves, closed high collars, full length skirts, flat cloth shoes. All standing naturally, front three-quarter view facing slightly left, gentle lively smile, hands relaxed or holding a small book. Left girl child proportions and round face; center older child proportions; right teenage proportions, not mature adult. Maintain consistent recognizable eyes and face across growth stages. Refined hand-painted 2D Chinese fantasy game illustration, clear delicate linework and richly painted fabric, soft daylight from top left. NOT 3D, NOT photographic, no chibi superdeformed style. Sprites must have no ground, no scenery, no floor shadow beyond a tiny foot contact shadow, no panels, no text, no borders, no labels, no weapons. Each sprite occupies most available HEIGHT inside its third, transparent margins above and below. Real transparent background, not a checkerboard pattern painted into the image.
```

### 洞天

原始输出：`exec-c4392790-9769-4fec-a938-b9454d99450c.png`。

```text
Landscape 16:9 environment background for a Chinese fantasy 2D isometric settlement building GAME. Actual playable place backdrop, no UI, no text, no people, no buildings. A secluded pocket-realm high mountain valley seen from an elevated three-quarter isometric camera. Most of the middle 70 percent and lower half is a broad flat empty lush grass plateau, gently sunlit, clean and open for the game to overlay isometric building tiles. Around the outer edges only: layered jade-green pine-covered rock cliffs at top, small natural stream on far left, a few boulders and white flowering shrubs near extreme corners, distant blue mountains beyond top rim. Refined hand-painted strategy game illustration, clear detailed but restrained painterly surfaces, natural vivid green grass and teal foliage balanced with white-grey rocks and clear pale blue sky. No fog covering terrain, no brown parchment, no checkerboard or tile grid, no glowing orbs. The center must remain fully empty grass without raised shapes, trees, pathways, terrain obstacles, or objects. No UI panels, no icons, no card borders. Wide composition designed to fill a 1280x720 game screen.
```

### 建筑

原始输出：`exec-e20da134-448a-45b6-957f-ce7e440713e4.png`。

```text
Create a TRANSPARENT ALPHA sprite atlas for a Chinese xianxia settlement building game, 1536x1024 landscape canvas. Exactly eight isolated isometric game prop sprites in a strict 4-column by 2-row grid. Each cell is 384x512 pixels. Each object must fit fully inside its own cell with at least 32 pixels transparent padding, no overlaps or crossing cell boundaries. Same isometric camera, viewed from front-left and front-right faces equally, light from upper left. Same refined hand-painted illustrated game art style, detailed readable miniatures, pale white stone, deep jade-green/blue roof tiles, rich foliage and small vermilion accents. NO text, NO labels, no borders, NO visible sheet/grid, NO scenery, no UI. Genuine transparent background, NOT a painted checkerboard. Top row left to right: 1 a small single-story Chinese cottage with white plaster walls, timber frame and jade tiled gable roof; 2 a small rectangular medicinal herb garden plot with orderly short leafy green herbs in dark soil rows; 3 a compact stand of three green pine trees with a tiny stacked timber pile; 4 a grey-white stone quarry with several chiseled boulders and a tiny wooden mining support. Bottom row left to right: 5 a large ornate teal bronze alchemy cauldron with a red fire aperture and stone pedestal, no building; 6 a simple straw scarecrow wearing a muted vermilion robe and straw conical hat on a tiny grass base; 7 a clear jade-blue spring pool ringed with pale natural rocks and two small reeds; 8 a traditional simple white stone and jade roof paifang gateway with two pillars, no writing. All objects must be complete including their bases and roof tips. Compact diamond-oriented footprints suitable for placement on isometric tiles. Large enough in their cells to read at 100 pixels screen size. Transparent empty space around each isolated sprite, no glow or atmospheric haze. No humans or animals.
```

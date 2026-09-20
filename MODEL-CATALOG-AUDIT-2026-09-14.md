# SOPShot 视觉模型预设核验

核验日期：2026-09-14

## 判定标准

SOPShot 的预设只保留“能够接收图像或视频，并返回文字”的视觉模型。图片生成、视频生成、语音转写和纯文本模型不进入这个列表。对于只接收图像的模型，SOPShot 在本地把录屏转换成带时间点的图片帧；对于确认支持视频的模型，才允许整段视频直传。

## 核验结果

| 厂商 | 当前预设 | 输入路径 | 处理结果 |
| --- | --- | --- | --- |
| Google Gemini | `gemini-3.8-flash`、`gemini-3.7-flash`、`gemini-3.6-flash`、`gemini-3.5-flash-lite`、`gemini-3.1-pro-preview` | 视频 / 图片 | 保留并补充当前稳定型号；官方模型目录列出这些 ID，视频文档说明 Gemini 模型可处理视频。[模型目录](https://ai.google.dev/gemini-api/docs/models) [视频理解](https://ai.google.dev/gemini-api/docs/video-understanding) |
| 阿里云百炼 / 通义千问 | `qwen3.8-max`、`qwen3.8-max-0902`、`qwen3.8-flash`、`qwen3.7-plus`、`qwen3.7-flash`、`qwen3.6-plus`、`qwen3.6-flash`、`qwen3.5-omni-plus` | 视频 / 图片 | 收敛到官方当前视觉目录中的型号；旧版 Qwen-VL 和 Qwen3.5 普通型号不再作为首选预设。[视觉模型目录](https://help.aliyun.com/zh/model-studio/vision-model) |
| 火山方舟 / 豆包 | `doubao-seed-2-0-lite-260428`、`doubao-seed-2-0-mini-260428`、`doubao-seed-2-0-lite-260215` | 视频 / 图片 | 加入官方更新记录中的 260428 视觉版本，同时保留官方 API 示例中的 260215 兼容快照；实际可用性仍由方舟账号和地域决定。[方舟 API 示例](https://www.volcengine.com/docs/82379/1795150) [官方更新记录](https://www.volcengine.com/docs/6492/2165228?lang=en) |
| OpenAI | `gpt-6-astra`、`gpt-5.6-sol`、`gpt-5.6-terra`、`gpt-5.6-luna` | 图片 | 替换原来的 GPT-5.1、GPT-5 mini、GPT-4.1；官方当前模型目录将 GPT-6 Astra 和 GPT-5.6 系列列为主力模型，并说明最新模型支持图像输入。[模型目录](https://developers.openai.com/api/docs/models) [图像理解](https://developers.openai.com/api/docs/guides/images-vision) |
| Anthropic / Claude | `claude-fable-5-1`、`claude-opus-5`、`claude-sonnet-5`、`claude-haiku-4-5-20251001` | 图片 | 替换旧的 Opus 4.8 和 Sonnet 4.6；官方当前模型总览列出这四个型号并明确支持图像输入。[模型总览](https://platform.claude.com/docs/en/models/overview) |
| DeepSeek | `deepseek-flash` | 图片 | 替换 `deepseek-v4-flash-vision-exp`。官方当前价格页说明应使用 `deepseek-flash`，旧名称仍可能被接受但对应模型已退休；视觉文档说明只有视觉型号接收图片。[模型与价格](https://api-docs.deepseek.com/quick_start/pricing/) [Vision](https://api-docs.deepseek.com/guides/vision/) |
| xAI / Grok | `grok-4.6` | 图片 | 保留；官方当前模型页将 Grok 4.6 作为主力模型，图像理解文档使用同一 ID。[模型目录](https://docs.x.ai/developers/models) [图像理解](https://docs.x.ai/developers/model-capabilities/images/understanding) |
| 智谱 AI / GLM | `glm-5.3-flash`、`glm-5v-turbo`、`glm-4.6v`、`glm-4.6v-flashx`、`glm-4.6v-flash` | 视频 / 图片 | 加入 2026-09-12 官方发布的 GLM-5 系列首个原生多模态模型 `GLM-5.3-Flash`，并保留 `GLM-5V-Turbo` 与 GLM-4.6V 视觉系列；官方资料明确 Flash 支持视觉输入，官方模型仓库及 ZCode 文档使用小写 API ID `glm-5.3-flash`。[官方发布说明](https://autoclaw.z.ai/blog/model/glm-5.3-flash/) [官方模型仓库](https://huggingface.co/zai-org/GLM-5.3-Flash) [ZCode 配置说明](https://zcode.z.ai/en/docs/configuration) [GLM-5V-Turbo](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5v-turbo) [GLM-4.6V](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.6v) |
| Moonshot AI / Kimi | `kimi-k3`、`kimi-k2.6` | 图片 | 保留并标记为当前多模态型号；当前模型目录已将 K3 列为最新多模态模型，并保留 K2.6。[模型列表](https://platform.kimi.ai/docs/models) [Kimi K2.6](https://platform.kimi.ai/docs/guide/kimi-k2-6-quickstart) |
| Mistral AI | `mistral-large-2512`、`mistral-medium-2508`、`mistral-small-2506`、`ministral-14b-2512` | 图片 | 替换单一的 `mistral-small-latest`，使用官方 Vision 页面当前推荐的固定型号。[Vision](https://docs.mistral.ai/studio/conversations/vision) |

## 明确排除

- 不加入 Gemini 的 Nano Banana、OpenAI 的 GPT-Image、xAI 的 Grok Imagine、火山的 Seedream / Seedance 等生成模型。它们的主要用途是生成图片或视频，不是读取办公录屏并返回步骤文字。
- 不加入 GLM-5.3、GLM-5.2、GLM-4.7、MiniMax 等官方页面标明为纯文本的型号。特别是 `GLM-5.3` 虽然是智谱当前最新旗舰之一，但官方模型卡标注输入和输出均为 Text，不能接收 SOPShot 的图片帧或视频；注意它与应加入的视觉型号 `GLM-5.3-Flash` 不是同一个模型。[GLM-5.3 模型卡](https://docs.modelstudio.console.alibabacloud.com/zh/model-studio/glm-5-3-by-zhipu)
- 不把 DeepSeek 的 `deepseek-v4-flash` 或其他纯文本型号显示为视觉模型；DeepSeek 官方限制只有视觉型号接收图片。
- 不把 Claude 已退休的旧型号、Kimi 已退休的 K2.5 / Moonshot V1 Vision 型号加入新安装的预设。

## 运行边界

预设名称和官方目录只能证明型号曾被官方公开列出，不能证明每个用户的账号、区域、套餐或余额一定拥有调用权限。SOPShot 的“测试视觉输入”会使用真实图片请求验证用户自己的 Key；这一步仍需要用户自行提供 API Key，应用不会替用户保存密钥。

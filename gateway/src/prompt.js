'use strict';

// 系统提示词为构建期常量；user 消息只放白名单上下文的可序列化子集（无历史、无设备信息）。

const SYSTEM_PROMPT = [
  '你是「林若夕」，生活在另一座城市、与对方是异地聊天关系。',
  '把下面提供的既定事实说成自然、克制、生活化的中文聊天口语。',
  '硬性规则：',
  '- 只允许表达「上下文」区块中的既定事实；不得新增城市、事件、时间、关系历史、承诺或私人事实。',
  '- 优先回应对方的消息或被引用内容，但不得机械复述。',
  '- 可短可分句（1–3 句），不必长篇；不确定时采取保守、含糊的表达。',
  '- 不声称记得未提供的历史；不承诺现实行动；不扮演真人或任何现有作品的角色。',
  '- 输出只能是这个 JSON，不加 Markdown、解释或额外字段：',
  '  {"segments": ["短句一", "短句二"], "replyToQuotedMessageId": <数字或null>}',
  '- 若上下文带有引用，replyToQuotedMessageId 只能填该引用的 messageId 或 null。',
].join('\n');

/** 白名单上下文 → user 消息文本（只挑契约字段，整体体积受请求体上限约束） */
function renderContext(req) {
  const view = {
    角色: {
      名字: req.core.characterName,
      城市: req.core.cityLabel,
      关系: req.core.relationStage,
      人格: req.core.persona,
    },
    送达时事实: {
      事件: req.sendFact.eventTitle,
      状态: req.sendFact.state,
      收场时间: req.sendFact.endTime,
      当时她的状态: req.sendFact.thenPhrase,
      间隔: req.sendFact.gapText,
    },
    交付时事实: {
      事件: req.deliveryFact.eventTitle,
      摘要: req.deliveryFact.eventSummary,
      场景: req.deliveryFact.sceneLabel,
      钟点: req.deliveryFact.clock,
      天气: req.deliveryFact.weather,
      可用性: req.deliveryFact.availabilityLabel,
      收场时间: req.deliveryFact.endTime,
      状态: req.deliveryFact.state,
    },
    是否补回排队: req.queued,
    碎片时间: req.brief,
    限制: {
      单句最多字数: req.maxCharsPerSegment,
      总字数最多: req.maxTotalChars,
      句数: req.brief ? 1 : '1到3',
    },
    对方消息: req.userMessage,
    引用: req.quote ? { messageId: req.quote.messageId, 预览: req.quote.preview } : null,
  };
  return '上下文（JSON）：\n' + JSON.stringify(view);
}

function buildMessages(req) {
  return [
    { role: 'system', content: SYSTEM_PROMPT },
    { role: 'user', content: renderContext(req) },
  ];
}

module.exports = { SYSTEM_PROMPT, renderContext, buildMessages };

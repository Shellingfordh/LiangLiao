# Data Contracts

本文件用于让程序、LLM、事件和美术对同一组数据使用相同概念。

## WorldState

```json
{
  "world_id": "ruoxi_la",
  "clock": "2026-10-04T18:47:00-07:00",
  "weather": "clear",
  "location": "bookstore",
  "activity": "event_finished",
  "character": {
    "id": "ruoxi",
    "mood": "good",
    "energy": 0.42
  }
}
```

## Event

```json
{
  "id": "evt_001",
  "type": "social",
  "time": "2026-10-04T18:40:00-07:00",
  "location": "bookstore",
  "facts": [
    "event ended late",
    "reader stayed to talk",
    "bought iced coffee"
  ],
  "importance": 0.55,
  "chat_relevance": 0.75
}
```

## Memory

```json
{
  "id": "mem_001",
  "type": "shared_experience",
  "summary": "User recommended a book that Ruoxi later bought",
  "importance": 0.82,
  "last_referenced": "2026-10-04T18:50:00-07:00"
}
```

## LLM Context

```json
{
  "persona": {},
  "world_state": {},
  "recent_events": [],
  "relevant_memories": [],
  "conversation": [],
  "user_message": "今天怎么样？"
}
```

## 原则

Event 保存事实。

Memory 保存长期关系事实。

LLM Context 负责把两者提供给模型。

LLM 输出自然语言。

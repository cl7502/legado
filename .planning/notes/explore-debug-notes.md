---
title: 书源发现调试器 — 分析笔记与已知局限
date: 2026-05-28
context: ExploreDebugView 开发过程中积累的经验，用于后续分析其他书源、强化自动修复功能时参考
---

## 调试器工作流程

1. 书源管理 → 任意行左侧 `⋯` → 调试发现规则
2. 打开后可编辑 `exploreUrl` 和所有 `ruleExplore*` 字段
3. 点"运行诊断"：五步管线依次执行，实时显示 ✅/❌/⚠️
4. Step 3 通过（HTTP 200 + 真实内容）后"修复"按钮解锁
5. 点"修复"：系统分析响应体，填入空白规则字段，显示修复建议
6. 确认样例数据正确后点"保存"持久化到数据库
7. 再次点"运行诊断"验证全五步通过

---

## 自动修复逻辑说明

### JSON 书源（现代 API，成功率高）

算法：
1. 递归遍历 JSON 树，收集所有"由对象组成的数组"（每个元素是 dict 且数量≥2）
2. 对每个候选数组打分（item 数量 + 字段命中 name/author/url 关键词）
3. 选分最高的数组作为书单容器
4. `ruleExploreList` = 数组路径 + `[*]`，例如 `$.data[*]`
5. 各字段规则优先级从高到低匹配候选字段名

字段名候选列表（代码位于 `ExploreDebugView.swift - inferFromJSON`）：

| Legado 字段 | 匹配候选（顺序即优先级） |
|---|---|
| ruleExploreName | novelName, bookName, book_name, name, title, bookTitle |
| ruleExploreAuthor | authorName, author_name, author, penName, pen_name |
| ruleExploreCoverUrl | cover, coverUrl, cover_url, img, image, thumb, pic, picurl |
| ruleExploreKind | kind, category, type, sort, genre, cat, sortName, sort_name |
| ruleExploreNoteUrl | url, link, bookUrl, book_url, detailUrl, detail_url（优先）；novelId, novel_id, bookId, book_id, id（次选，标记警告） |

### HTML 书源（启发式，成功率较低）

依赖 SwiftSoup，识别常见列表容器：
`ul > li` / `ol > li` / `.book-list > *` / `.booklist > *` / `article`

成功率低的根本原因：HTML 结构千变万化，CSS 类名无规律可循。

---

## 已知局限与处理建议

### 局限 1：ruleExploreNoteUrl 是 ID 而非完整 URL

**表现**：修复建议里显示 `ruleExploreNoteUrl = $.novelId  ⚠️ 可能需要补全 URL 前缀`

**原因**：部分 API 书单只返回书籍 ID，需要结合书源 base URL 构造完整链接。
例如：猫眼看书的规则是 `/novel/{{$.novelId}}?isSearch=1`（相对路径 + 模板变量）。

**手动修复方法**：
1. 在诊断器里看 Step 3 响应，找 ID 字段的样例值（如 `novelId: 12345`）
2. 在书源网站手动访问书籍详情页，记录 URL 格式
3. 将 `$.novelId` 改为 `书源域名/path/{{$.novelId}}` 这样的模板

**未来优化方向**：将 `bookUrlPattern` 字段纳入推断，或参考同书源的 `ruleSearchNoteUrl` 来推断格式。

---

### 局限 2：字段名完全非标准

**表现**：修复后 `ruleExploreName` 仍为空，或填入的值样例不像书名

**原因**：书源 API 使用了单字母或完全自定义的字段名（如 `n`、`a`、`cid`）。

**手动识别方法**：
1. 看 Step 3 响应预览，在调试器里展开看完整响应（当前只显示前 300 字符，未来可优化为全文展示）
2. 根据值的内容猜测字段用途（如值是中文短字符串 → 可能是书名；值是 URL → 可能是封面或链接）
3. 在调试器里手动填入字段名，点"运行诊断"验证

**未来优化方向**：
- 扩展候选列表（从社区书源库中统计高频字段名）
- 增加"值类型"启发：值像 URL 且 > 20 字符 → 可能是 noteUrl 或 coverUrl；值像中文且 < 30 字符 → 可能是书名；值是纯数字 → 可能是 ID

---

### 局限 3：书单数组深层嵌套或评分错误

**表现**：修复后 `ruleExploreList` 路径不对，或选中了错误的数组（如分类列表而非书单）

**原因**：JSON 里有多个数组时打分算法可能选错，例如：
- `$.data.books[*]` 是真正的书单
- `$.data.categories[*]` 是分类列表（被错误选中，因为字段数可能更多）

**识别方法**：看修复建议里的"样例"数据，如果样例值明显不是书名/作者，说明选错了数组。

**手动修复方法**：
- 在调试器里修改 `ruleExploreList` 为正确路径（如 `$.data.books[*]`）
- 点"运行诊断"验证 Step 4 找到条目、Step 5 样例数据正确

**未来优化方向**：
- 添加"全部候选数组"展示，让用户从列表里选择（而不是系统自动选一个）
- 打分时对包含 `categor`/`type`/`sort` 字段的数组降分

---

## 已发现的代码 Bug（通过调试器定位）

### Bug 1：java.md5Encode() 未在 JSJavaHelperProtocol 中声明（已修复 2026-05-28）

**影响书源**：数据库中 7 个使用 `{{java.md5Encode(...)}}` 的书源
**症状**：Step 3 返回 HTTP 200 但 body 是 nginx 404 HTML（token= 为空）
**修复**：`JSJavaHelper.swift` 加入 `md5Encode()` = `md5()` 别名
**commit**：`d65b79ad7`

---

## 分析其他书源时的常用 SQL 查询

```sql
-- 查看某书源的所有发现规则
SELECT bookSourceName, exploreUrl, ruleExploreList, ruleExploreName,
       ruleExploreAuthor, ruleExploreNoteUrl, ruleExploreCoverUrl
FROM book_source WHERE bookSourceName LIKE '%书源名%';

-- 找所有 ruleExploreList 为空但有 exploreUrl 的书源（待修复候选）
SELECT bookSourceName, substr(exploreUrl, 1, 60)
FROM book_source
WHERE enabled=1
  AND (exploreUrl IS NOT NULL AND exploreUrl != '')
  AND (ruleExploreList IS NULL OR ruleExploreList = '');

-- 找使用 java.md5Encode 的书源
SELECT bookSourceName FROM book_source
WHERE exploreUrl LIKE '%md5Encode%'
   OR searchUrl LIKE '%md5Encode%';
```

---

## 待加强的功能

- [ ] Step 3 响应完整展示（当前截断 300 字符，复杂 JSON 看不全）
- [ ] 候选数组多选展示，用户手动选择而非系统强制推断
- [ ] `ruleExploreNoteUrl` 的 URL 模板推断（参考 `bookUrlPattern` 和同书源 `ruleSearchNoteUrl`）
- [ ] 非标准字段名的值类型启发（URL / 中文短串 / 纯数字）
- [ ] 一键对比 Android 版书源规则（从书源社区拉取同 URL 书源）

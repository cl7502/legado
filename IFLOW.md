# Legado (开源阅读) 项目概览

## 项目简介

Legado (开源阅读) 是一个免费开源的 Android 小说阅读器应用。该应用允许用户自定义书源，通过设置规则抓取网页数据，实现阅读各种网络小说内容。项目采用 Kotlin 语言开发，基于 Android 平台，使用现代化的 Android 开发框架和工具链。

项目还包含一个基于 Vue.js 的 Web 应用程序，可与 Android 应用的 API 交互，提供浏览器端的书籍源管理和阅读体验。

## 技术架构

### 主要技术栈
- **编程语言**: Kotlin
- **开发框架**: Android SDK (API 21-36)
- **构建工具**: Gradle (使用 Version Catalogs 管理依赖)
- **架构模式**: MVVM (Model-View-ViewModel)
- **数据库**: Room (SQLite)
- **网络请求**: OkHttp + Cronet
- **HTML 解析**: JSoup + JSoupXpath
- **图像处理**: Glide
- **依赖注入**: 手动依赖注入
- **异步处理**: Kotlin Coroutines

### 模块结构
```
legado/
├── app/                    # 主应用模块
├── modules/
│   ├── book/              # 书籍相关模块
│   ├── rhino/             # JavaScript 引擎模块
│   └── web/               # Web 前端模块 (Vue.js)
└── gradle/                # Gradle 配置
```

### 应用架构
```
io.legado.app/
├── api/                   # API 接口 (Web API 和 ContentProvider)
├── base/                  # 基类
├── constant/              # 常量定义
├── data/                  # 数据层 (数据库、实体、DAO)
├── exception/             # 异常处理
├── help/                  # 帮助文档
├── lib/                   # 第三方库封装
├── model/                 # 数据模型
├── receiver/              # 广播接收器
├── service/               # 后台服务
├── ui/                    # UI 层 (Activity、Fragment、Adapter)
├── utils/                 # 工具类
└── web/                   # Web 服务相关
```

## 构建和运行

### 环境要求
- Android Studio Hedgehog | 2023.1.1 或更高版本
- JDK 17
- Android SDK (API 21-36)
- Git

### 构建步骤
1. 克隆仓库:
   ```bash
   git clone https://github.com/gedoor/legado.git
   cd legado
   ```

2. 导入项目到 Android Studio

3. 配置签名 (可选，用于发布版本):
   在项目根目录创建 `gradle.properties` 文件，添加以下内容:
   ```properties
   RELEASE_STORE_FILE=your_keystore_path
   RELEASE_STORE_PASSWORD=your_keystore_password
   RELEASE_KEY_ALIAS=your_key_alias
   RELEASE_KEY_PASSWORD=your_key_password
   ```

4. 构建应用:
   - Debug 版本: `./gradlew assembleDebug`
     - 输出位置: `/app/build/outputs/apk/debug/`
   - Release 版本: `./gradlew assembleRelease`
     - 输出位置: `/app/build/outputs/apk/release/`

### 运行测试
```bash
./gradlew test
./gradlew connectedAndroidTest
```

### Web 模块构建
Web 模块位于 `modules/web` 目录，使用 Vue.js + TypeScript + Vite 构建:

#### 环境要求
- Node.js (版本 >= 20)
- pnpm 包管理器 (版本 >= 9)

#### 构建步骤
1. 进入 Web 模块目录:
   ```bash
   cd modules/web
   ```

2. 安装依赖:
   ```bash
   pnpm install
   ```

3. 开发模式运行:
   ```bash
   pnpm run dev
   ```
   这将启动本地开发服务器，通常在 `http://localhost:5173`

4. 生产环境构建:
   ```bash
   pnpm run build
   ```
   构建输出将位于 `modules/web/dist` 目录

5. 类型检查:
   ```bash
   pnpm run type-check
   ```

6. 代码格式化:
   ```bash
   pnpm run format
   ```

7. 代码检查和修复:
   ```bash
   pnpm run lint:fix
   ```

## 开发约定

### 代码风格

#### Android 应用
- 使用 Kotlin 官方代码风格
- 遵循 Android 开发最佳实践
- 使用 ViewBinding 进行视图绑定
- 使用 Kotlin Coroutines 处理异步任务
- 使用 Room 进行数据库操作
- 遵循 MVVM 架构模式

#### Web 应用
- 使用 ESLint 和 Prettier 进行代码格式化和检查
- 推荐使用支持相应插件的开发器以保持代码质量
- 遵循 Vue.js 3 组合式 API 最佳实践
- 使用 TypeScript 进行类型安全开发
- 遵循 Vue.js 项目结构约定

### 分支管理
- `master`: 主分支，稳定版本
- 开发新功能时创建功能分支

### 提交规范
- 提交信息使用中文
- 格式: `功能描述`
- 例如: `修复搜索bug`、`添加书源导入功能`

### 版本控制
- 版本号格式: `3.yy.MMddHH`
- 版本代码: `10000 + git提交次数`

## 核心功能

### 主要特性
1. **自定义书源**: 用户可以自定义规则抓取网页数据
2. **书架管理**: 支持列表和网格两种书架显示模式
3. **搜索与发现**: 支持自定义搜索和发现规则
4. **内容订阅**: RSS订阅功能
5. **内容净化**: 支持替换净化，去除广告
6. **本地阅读**: 支持TXT、EPUB等本地文件阅读
7. **阅读界面**: 高度自定义的阅读体验
8. **翻页模式**: 多种翻页效果
9. **开源无广告**: 完全开源，无广告干扰

### API 接口
应用提供两种API接口:
1. **Web API**: HTTP RESTful API，默认端口1234
2. **ContentProvider**: Android内容提供者接口

详细API文档请参考 `api.md` 文件。

## 项目依赖

### 主要依赖库

#### Android 应用
- AndroidX 组件库 (AppCompat, Core KTX, Room 等)
- Material Design 组件
- Room 数据库
- OkHttp 网络库
- JSoup HTML解析
- Glide 图像加载
- Coroutines 协程
- NanoHTTPD (嵌入式Web服务器)
- Firebase (崩溃统计和性能统计)

#### Web 应用
- Vue.js 3 框架
- TypeScript 类型系统
- Vite 构建工具
- Element Plus UI 组件库
- Pinia 状态管理
- Vue Router 路由管理
- Axios HTTP 客户端
- ESLint 代码检查
- Prettier 代码格式化

完整依赖列表请参考 `gradle/libs.versions.toml` 和 `modules/web/package.json` 文件。

## 注意事项

1. **版本兼容性**: 
   - 最低支持 Android 5.0 (API 21)
   - 目标版本 Android 14 (API 36)

2. **特殊依赖处理**:
   - JSoup 版本锁定为 1.16.2 (避免破坏性变更)
   - Commons Text 版本锁定为 1.13.1 (兼容旧版本Android)

3. **权限要求**:
   - 网络访问权限
   - 存储访问权限
   - 前台服务权限
   - 其他系统权限

4. **构建优化**:
   - 启用代码混淆和资源压缩 (Release版本)
   - 使用 R8 进行代码优化
   - 支持增量编译

## 社区和支持

- 官方网站: https://gedoor.github.io
- 帮助文档: https://www.yuque.com/legado/wiki
- Telegram 群组: https://t.me/yueduguanfang
- Discord: https://discord.gg/VtUfRyzRXn

## 许可证

项目采用开源许可证，具体请参考 `LICENSE` 文件。
# netwtop 自建 APT 仓库实施指南

本文说明如何把 `netwtop` 发布到项目自己维护的 APT 仓库，使用户在完成一次
软件源配置后可以使用以下命令安装和升级：

```sh
sudo apt update
sudo apt install netwtop
```

这里的“项目自己的仓库”是指由 netwtop 项目控制域名、仓库元数据、签名密钥
和发布流程，而不是提交到 Debian 官方仓库。完整的 Debian 打包准备工作见
[APT 打包与发布指南](APT_PACKAGING.md)。

## 1. 先明确用户安装流程

APT 不会自动发现第三方仓库。首次安装前，用户仍然需要：

1. 下载并验证项目的仓库公钥。
2. 把公钥保存到 `/etc/apt/keyrings/`。
3. 在 `/etc/apt/sources.list.d/` 中添加项目软件源。
4. 执行 `apt update`。
5. 执行 `apt install netwtop`。

完成一次配置后，后续版本可以通过常规的 `apt upgrade` 获得。只有当
`netwtop` 被 Debian 或 Ubuntu 官方仓库收录后，新用户才可以完全跳过添加
第三方软件源这一步。

不要在安装说明中使用以下做法：

- `apt-key add`：这是旧式的全局信任方式。
- `[trusted=yes]`：它会关闭仓库身份验证。
- `--allow-unauthenticated`：它会绕过 APT 的安全检查。
- 把项目密钥写入全局的 `trusted.gpg`。

## 2. 推荐的总体方案

对 netwtop 当前规模，建议采用：

```text
Git tag
   │
   ▼
clean Debian/Ubuntu builds
   │
   ▼
lintian + autopkgtest + project smoke tests
   │
   ▼
reprepro repository working directory
   │
   ├── signed InRelease / Release.gpg
   └── Packages indexes + package pool
   │
   ▼
atomic upload to static HTTPS hosting
   │
   ▼
packages.example.com/apt
```

推荐组合如下：

| 环节 | 推荐实现 | 原因 |
| --- | --- | --- |
| Debian 仓库管理 | `reprepro` | 简单、成熟，适合静态 APT 仓库 |
| 包构建 | `sbuild` 或干净容器/虚拟机 | 避免构建机中的依赖污染 |
| 元数据签名 | 专用 OpenPGP 签名密钥 | APT 会验证签名后的 Release 元数据 |
| 仓库托管 | 对象存储/CDN、Nginx 或静态站点 | APT 仓库本质上可以是静态文件 |
| 传输 | HTTPS | 防止下载地址被劫持并保护用户隐私 |
| 自动化 | 受保护的 CI 发布任务 | 统一构建、测试、签名和发布过程 |

`aptly` 适合需要快照、晋级和回滚的较大仓库；Launchpad PPA 主要适合
Ubuntu；packagecloud 等服务可以减少运维工作，但仓库控制权和成本模型不同。
本指南以 `reprepro` 为主，不要求 netwtop 运行时依赖它。

## 3. 发布前必须补齐的项目工作

自建仓库只是分发渠道，不能替代 Debian 打包。发布仓库前至少要完成：

- 确定开源许可证、版权持有人和版权年份。
- 确定维护者姓名、邮箱、项目主页、源码仓库和 Bug Tracker。
- 确定首个稳定版本号并维护 `CHANGELOG.md`。
- 创建 `debian/`，能够稳定构建 `netwtop_*_all.deb`。
- 提供 man page，并让安装包把命令安装为 `/usr/bin/netwtop`。
- 使用 `lintian` 检查包。
- 在干净环境执行项目测试和 `autopkgtest`。
- 测试安装、升级、卸载、普通用户运行和 root 跨用户归属。
- 构建源码包，保留与二进制包对应的可审计源码。

netwtop 主要由平台无关的 shell 和 awk 文件组成，因此 Debian 二进制包通常
应使用：

```text
Architecture: all
```

这不等于一个构建可以在所有发行版上未经测试地发布。Debian 和 Ubuntu 的每个
受支持版本仍然需要单独检查运行依赖、系统命令和安装行为。

## 4. 确定仓库命名和支持范围

开始部署前先固定以下值。本指南使用占位示例：

| 项目 | 示例值 |
| --- | --- |
| 仓库 URL | `https://packages.example.com/apt` |
| Origin | `netwtop` |
| Label | `netwtop` |
| Component | `main` |
| Debian suites | `bookworm`、`trixie` |
| Ubuntu suites | `jammy`、`noble` |
| Architectures | `amd64`、`arm64`、`source` |
| 公钥 URL | `https://packages.example.com/apt/netwtop-archive-keyring.asc` |

实际配置必须把 `example.com` 和所有占位值替换成项目自己的信息。

### 使用发行版代号

第三方仓库建议使用 `bookworm`、`trixie`、`jammy`、`noble` 这样的发行版
代号，而不是只使用含义会变化的 `stable` 或 `latest`。这样可以避免 Debian
稳定版切换时让用户意外跨发行版获取包。

每个公开 suite 都是一项支持承诺。不要创建尚未实际构建和测试的 suite。
如果某个包对所有目标系统确实完全相同，可以在仓库内部复用同一个 `.deb`，
但各 suite 的索引、测试结果和发布生命周期仍应独立管理。

### 软件包版本规则

已经公开的同一版本不得被不同内容覆盖。APT 使用版本号判断升级，如果重新发布
了内容不同但版本号相同的文件，代理缓存和用户缓存可能得到不一致结果。

可以采用以下形式：

```text
0.1.0-1~netwtop1
0.1.0-1~deb13u1
0.1.0-1~ubuntu24.04.1
```

`~netwtop1` 形式会排序在不带该后缀的 `0.1.0-1` 之前。如果未来 Debian
官方发布 `0.1.0-1`，APT 可以自然迁移到官方版本。最终规则应写入项目发布
政策，并在所有 suite 中一致执行。

## 5. 创建专用仓库签名密钥

APT 主要验证签名后的仓库 `Release` 元数据，再通过其中的哈希验证索引和
`.deb`。因此仓库签名密钥是发布系统的核心凭据；并不是给每个 `.deb` 单独
签名就能替代仓库元数据签名。

建议：

1. 为 APT 仓库创建专用密钥，不复用个人日常密钥。
2. 主密钥离线保存，只让发布系统获得用途和期限受限的签名子密钥。
3. 为密钥设置到期时间并提前制定轮换计划。
4. 加密备份私钥、吊销证书和恢复说明。
5. 绝不把私钥、密码或未加密备份提交到 Git。
6. 在 README、Release 页面和项目网站公布完整指纹。

在隔离的管理环境中创建密钥的示例为：

```sh
gpg --quick-generate-key \
  "netwtop APT Repository <repo@example.com>" rsa4096 sign 2y
gpg --list-keys --fingerprint "netwtop APT Repository"
```

记录输出的完整指纹。然后只导出最小化的 ASCII armored 公钥：

```sh
gpg --export-options export-minimal --armor \
  --export FULL_KEY_FINGERPRINT > netwtop-archive-keyring.asc
```

公钥文件使用 `.asc` 后缀；如果发布二进制 OpenPGP keyring，则使用 `.gpg`
后缀。用户侧文件必须能被 `_apt` 用户读取，通常使用 `0644` 权限。

## 6. 建立 reprepro 工作仓库

以下命令在独立的仓库管理机或受保护的 CI 发布环境中执行，不在 netwtop 用户
机器上执行。

安装仓库管理工具：

```sh
sudo apt update
sudo apt install reprepro gnupg
mkdir -p repo/conf
```

创建 `repo/conf/distributions`。下面是 Debian trixie 的最小示例：

```text
Origin: netwtop
Label: netwtop
Codename: trixie
Suite: trixie
Components: main
Architectures: amd64 arm64 source
Description: netwtop packages for Debian trixie
SignWith: FULL_KEY_FINGERPRINT
```

为每个真正支持的发行版增加一个独立段落，段落之间留一个空行。例如 Ubuntu
noble 使用 `Codename: noble` 和 `Suite: noble`。`SignWith` 应使用完整指纹，
不要只写容易碰撞的短 key ID。

仓库工作目录通常会形成类似结构：

```text
repo/
├── conf/
│   └── distributions
├── db/
├── dists/
│   └── trixie/
│       ├── InRelease
│       ├── Release
│       ├── Release.gpg
│       └── main/
├── pool/
│   └── main/
│       └── n/
│           └── netwtop/
└── netwtop-archive-keyring.asc
```

`conf/`、`db/` 和私钥属于仓库的管理状态，不应由 Web 服务器公开。公共站点
只需要发布 `dists/`、`pool/` 和项目公钥。仓库数据库应有加密备份，否则在
重建或删除版本时容易丢失发布历史。

## 7. 把构建产物加入仓库

先在干净环境生成并验证包。示例产物可能包括：

```text
netwtop_0.1.0-1~deb13u1_all.deb
netwtop_0.1.0-1~deb13u1.dsc
netwtop_0.1.0.orig.tar.gz
netwtop_0.1.0-1~deb13u1.debian.tar.xz
```

将二进制包加入目标 suite：

```sh
reprepro -b repo includedeb trixie \
  ../netwtop_0.1.0-1~deb13u1_all.deb
```

将签名的源码包加入同一 suite：

```sh
reprepro -b repo includedsc trixie \
  ../netwtop_0.1.0-1~deb13u1.dsc
```

检查仓库记录并重新导出元数据：

```sh
reprepro -b repo list trixie
reprepro -b repo check trixie
reprepro -b repo export trixie
```

确认生成了以下内容：

- `Packages` 及其压缩版本。
- 如果发布源码包，则包含 `Sources` 及其压缩版本。
- `Release`。
- clear-signed 的 `InRelease`。
- detached signature `Release.gpg`。

APT 会优先使用 `InRelease`。不要发布只有 `Packages` 而没有可验证 Release
签名的仓库。

## 8. 通过 HTTPS 原子发布

仓库可以托管在 Nginx、Apache、对象存储加 CDN，或支持静态文件的站点上。
生产环境至少应满足：

- URL 使用 HTTPS，证书自动续期。
- `dists/`、`pool/` 和公钥都可以匿名读取。
- 路径和文件名大小写保持不变。
- Web 服务器不重写或动态修改签名文件。
- MIME type 不影响原始字节内容。
- 发布过程是原子的。

“原子发布”非常重要。若先上传新的 `InRelease`，但对应的新 `Packages` 或
`.deb` 尚未上传，用户会在这段时间看到哈希不匹配或 404。推荐顺序为：

1. 在新的临时目录中生成完整仓库。
2. 验证签名、索引和所有被引用文件。
3. 先上传不可变的 `pool/` 包文件。
4. 上传索引文件。
5. 最后原子切换站点目录，或最后替换顶层 Release 元数据。

对象存储部署应使用带版本的 staging 前缀或等效发布机制。CI 发布任务必须串行，
避免两个 tag 同时修改 reprepro 数据库。对 `InRelease` 设置过长的 CDN 缓存
也会延迟更新；包文件本身因为版本化且不可变，可以使用较长缓存。

GitHub Pages 可以承载小型静态仓库，但仍要解决安全签名、原子发布、历史包大小、
带宽和并发发布问题。较正式的长期仓库通常更适合独立域名加对象存储/CDN，或受
控的 Nginx 主机。

## 9. 编写用户安装说明

以下示例使用 Debian 当前推荐的 deb822 `.sources` 格式和 `Signed-By` 限定
密钥作用范围。用户应先从项目网站或 Release 页面核对公钥指纹。

### 9.1 安装仓库公钥

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.example.com/apt/netwtop-archive-keyring.asc \
  | sudo tee /etc/apt/keyrings/netwtop-archive-keyring.asc >/dev/null
sudo chmod 0644 /etc/apt/keyrings/netwtop-archive-keyring.asc
gpg --show-keys --fingerprint /etc/apt/keyrings/netwtop-archive-keyring.asc
```

文档中应同时列出预期的完整指纹，让用户比较，而不只是相信同一下载站点上的
文件。若不希望依赖 `curl`，也可以提供浏览器下载和 `wget` 的等效步骤。

### 9.2 添加 deb822 软件源

Debian trixie 用户可以创建 `/etc/apt/sources.list.d/netwtop.sources`：

```text
Types: deb
URIs: https://packages.example.com/apt
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/netwtop-archive-keyring.asc
```

Ubuntu noble 用户必须把 `Suites` 改成仓库实际发布的 `noble`，不能继续使用
`trixie`。项目安装页可以按发行版分别给出可复制的文件，减少 suite 选择错误。

### 9.3 更新索引并安装

```sh
sudo apt update
apt-cache policy netwtop
sudo apt install netwtop
netwtop --help
```

`apt-cache policy netwtop` 应显示包来自项目 URL、正确 suite，并给出预期版本。
如果输出中还存在同名的其他来源，要确认 APT 的版本优先级符合预期。不要为了
强制第三方包覆盖官方包而默认分发高优先级 pinning 配置。

### 9.4 删除软件和仓库

卸载软件不会自动删除软件源。完整移除步骤为：

```sh
sudo apt remove netwtop
sudo rm /etc/apt/sources.list.d/netwtop.sources
sudo rm /etc/apt/keyrings/netwtop-archive-keyring.asc
sudo apt update
```

上述路径都是项目专用文件。项目不应要求用户删除共享 keyring 或修改其他软件源。

## 10. 增加 archive-keyring 包

当仓库稳定后，建议额外维护 `netwtop-archive-keyring` 包。它可以把公钥安装到：

```text
/usr/share/keyrings/netwtop-archive-keyring.gpg
```

也可以由单独的仓库配置包提供 `.sources` 文件。这有两个好处：

- 已安装用户可以通过普通包升级提前获得下一把公钥。
- 密钥轮换和软件源格式升级可以纳入版本管理。

但 keyring 包无法解决首次信任问题。新用户仍需通过 HTTPS 下载初始公钥或先
安装经过独立验证的 keyring `.deb`。文档中的 `Signed-By` 路径要与实际安装
位置一致：手动管理的密钥通常放 `/etc/apt/keyrings`，由软件包管理的密钥放
`/usr/share/keyrings`。

## 11. 建立受保护的 CI/CD 发布流程

建议把普通持续集成和生产发布分开：

### 普通 CI

每个提交和合并请求可以执行：

- `./tests/smoke.sh`。
- `shellcheck`。
- 构建源码包和二进制包。
- `lintian`。
- 在支持的 Debian/Ubuntu 环境中执行 `autopkgtest`。
- 检查安装后的 `/usr/bin/netwtop`，而不只检查源码树入口。

普通 CI 不需要、也不应该接触仓库私钥。

### 生产发布任务

只有受保护的版本 tag 和经过授权的维护者可以触发：

1. 验证 tag、源码版本与 `debian/changelog` 一致。
2. 在每个目标 suite 的干净环境重新构建。
3. 运行全部质量检查。
4. 保存构建日志、源码包、二进制包和校验和。
5. 在隔离的签名任务中签名源码包和仓库元数据。
6. 把包加入 reprepro 的正确 suite。
7. 从干净客户端验证待发布仓库。
8. 备份仓库数据库。
9. 原子发布静态文件。
10. 再次从公网 URL 执行安装和升级测试。

发布任务应使用 CI 的 protected environment、人工审批、最小权限凭据和串行
锁。不要让来自 fork 或未审查合并请求的任务读取签名密钥。更高安全要求下，
CI 只生成待签名清单，由离线或硬件保护的签名机完成签名和最终发布。

## 12. 发布前的端到端验证

每个支持的 suite 至少用一个全新的虚拟机或容器执行：

```sh
sudo apt update
apt-cache policy netwtop
sudo apt install netwtop
netwtop --help
sudo netwtop --help
```

还需要验证：

- `apt update` 没有 `NO_PUBKEY`、签名、哈希或 `Valid-Until` 错误。
- 实际候选版本来自预期 URL 和 suite。
- 包安装后所有 shell/awk 模块都存在且权限正确。
- 普通用户可以启动 UI。
- root 模式可以读取预期的跨用户 socket 信息。
- 从仓库旧版本升级到新版本时配置和运行行为正确。
- 删除再安装可以成功。
- 包被撤回后，已发布 Release 元数据不引用不存在的文件。
- 篡改索引或去掉签名后，APT 会拒绝该仓库。
- 公钥临近到期时监控会提前报警。

不要只验证本地 reprepro 目录。最终公网 URL 还可能受到 CDN 缓存、Web 服务器
权限、路径重写和 TLS 配置影响。

## 13. 日常维护职责

自建仓库上线后，项目需要长期承担：

- 对受支持的 Debian/Ubuntu 版本及时发布兼容包和安全更新。
- 明确每个 suite 的停止支持日期。
- 监控域名、TLS 证书、签名密钥和存储容量。
- 备份私钥、reprepro 数据库、发布产物和发布日志。
- 保留已发布源码和许可证信息。
- 对失败发布提供回滚或修复版本。
- 记录软件包撤回原因；不要静默覆盖原版本。
- 在项目网站公布仓库状态和安全联系渠道。

删除旧包前应检查所有已发布索引和支持中的 suite。对用户已经安装的版本，通常
保留对应 `.deb` 和源码比立即删除更利于审计和恢复。

### 密钥轮换

不要等密钥到期或泄露后才设计轮换。正常轮换应有重叠窗口：

1. 创建新密钥并通过独立渠道公布新指纹。
2. 在旧密钥仍可信时，通过 keyring 包或安装说明把新公钥分发给用户。
3. 让客户端信任新旧两把仓库密钥并完成更新。
4. 切换仓库元数据签名。
5. 经过公布的迁移期后再移除旧密钥。

如果私钥疑似泄露，应停止发布、保全日志、公布事件和新指纹，并为用户提供明确
的恢复步骤。仅在被怀疑的仓库上公布“请信任新密钥”不足以重新建立信任。

## 14. 建议的落地阶段

### 阶段 A：完成 Debian 包

- 确定许可证、维护者和版本。
- 创建 `debian/`、man page 和 changelog。
- 通过干净构建、lintian、autopkgtest 和项目测试。
- 手动安装 `.deb` 验证文件布局。

验收标准：

```sh
sudo apt install ./netwtop_VERSION_all.deb
netwtop --help
```

### 阶段 B：建立非生产测试仓库

- 创建测试签名密钥。
- 配置一个 suite 的 reprepro 仓库。
- 部署到临时 HTTPS URL。
- 从全新系统完成添加源、安装和升级。

验收标准：APT 无签名警告，`apt-cache policy` 来源正确，升级成功。

### 阶段 C：建立生产仓库

- 使用项目正式域名和正式签名密钥。
- 公布密钥完整指纹和支持范围。
- 建立备份、串行发布、原子部署和公网冒烟测试。
- 发布面向用户的逐发行版安装说明。

验收标准：新用户添加一次软件源后可以执行 `apt install netwtop`。

### 阶段 D：自动化和长期运维

- 由受保护 tag 驱动多 suite 构建。
- 增加 archive-keyring 包和密钥到期监控。
- 定期做升级、灾难恢复和密钥轮换演练。
- 明确旧 suite 的停止支持流程。

## 15. 上线检查清单

### 项目和软件包

- [ ] 许可证和版权信息完整。
- [ ] 维护者邮箱、主页、源码仓库和 Bug Tracker 已确定。
- [ ] 版本规则和 changelog 已确定。
- [ ] `debian/`、man page 和 autopkgtest 已完成。
- [ ] `.deb` 安装到 `/usr/bin/netwtop` 和正确模块目录。
- [ ] 构建、lintian、shellcheck 和项目测试通过。

### 仓库

- [ ] 已确定正式 HTTPS 域名。
- [ ] 只声明实际测试和维护的 suites。
- [ ] reprepro 数据库和发布产物有备份。
- [ ] `Packages`、`Sources`、`Release`、`InRelease` 和 `Release.gpg` 正常。
- [ ] 公开目录不包含 `conf/`、`db/`、私钥或 CI 凭据。
- [ ] 发布过程不会暴露部分更新状态。

### 安全

- [ ] 使用专用仓库密钥和完整指纹。
- [ ] 私钥没有进入 Git 或普通 CI。
- [ ] 公钥通过多个渠道公布并可核对。
- [ ] 用户配置使用 `Signed-By`。
- [ ] 没有使用 `apt-key`、`trusted=yes` 或 unauthenticated 选项。
- [ ] 已记录密钥到期、轮换、吊销和泄露响应流程。

### 用户体验

- [ ] 按 Debian/Ubuntu suite 提供 deb822 `.sources` 示例。
- [ ] 文档同时包含安装、验证、升级和彻底移除步骤。
- [ ] `apt-cache policy netwtop` 显示正确来源。
- [ ] 从全新系统通过公网 URL 安装成功。
- [ ] 从上一版本升级成功。

## 16. 官方参考资料

- Debian `sources.list(5)`：deb822 `.sources`、`Signed-By` 和 keyring 路径约定：
  <https://manpages.debian.org/testing/apt/sources.list.5.en.html>
- Debian `apt-secure(8)`：仓库身份验证、Release 签名和密钥导出建议：
  <https://manpages.debian.org/testing/apt/apt-secure.8.en.html>
- Debian `apt-ftparchive(1)`：Packages、Sources 和 Release 元数据：
  <https://manpages.debian.org/testing/apt-utils/apt-ftparchive.1.en.html>
- Debian `reprepro(1)`：仓库管理和包导入：
  <https://manpages.debian.org/bookworm/reprepro/reprepro.1.en.html>

APT 和 Debian 工具会继续演进。在首次生产发布前，应以目标 Debian/Ubuntu
版本附带的 man page 和当前 Debian Policy 为准，并在各受支持 suite 的干净
系统上重新验证本文命令。

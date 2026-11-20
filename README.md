# Black Mesa SourceMod 插件集

[English](README.en.md) | 中文

Black Mesa(黑山起源)**死亡竞赛服务器**的 SourceMod 插件集:36 个模块合并编译成单个 `BMAG.smx`,
另有几个独立插件单独加载。预编译产物见
[Releases](https://github.com/MXYLR/MXYLR-Black-Mesa-Sourcemod-plugins/releases)。

## 目录结构

```
├── plugins/                      部署产物(服务器 plugins/ 目录的备份)
│   ├── BMAG.smx                  36 模块合一插件 = 主要产物
│   ├── bms_rpgReloadFix.smx      第三方:RPG 换弹修复
│   ├── bms_weapon_tauStuckFix.smx 第三方:tau 低弹药卡枪修复
│   ├── is_weaponfx.smx           第三方:武器动画预热
│   ├── is_bms_fix_timelimit.smx  第三方:回合时限修复
│   └── disabled/                 停用插件(basebans、nextmap、randomcycle、xms 等 8 个)
├── smx_analysis/                 构建流水线与源码
│   ├── merge.py                  把 36 个模块源码合并成 BMAG.sp(唯一的构建入口)
│   ├── fix_merge.py              merge.py 的补丁工具
│   ├── sig_check.py              签名抗重定位校验
│   ├── rcon.py                   RCON 调试客户端(凭据走环境变量)
│   ├── bisect_compile.py         二分定位编译失败的模块
│   ├── REVERSE_*.md              引擎逆向笔记(重生、计时器、VGUI、穿墙)
│   ├── dl/sm-win/                SourceMod 工具链(含 spcomp.exe)
│   ├── out/                      逆向与探测留下的证据 dump
│   └── src/scripting/
│       ├── plugins/              模块源码 + 未编入 BMAG 的独立插件源码
│       ├── include/              编译用 SourceMod include
│       ├── BMAG/                 merge.py 产物(.sp 与模块副本不入库,.smx 入库)
│       ├── configs/              插件配置(bms_match.cfg、bms_webpanel.html)
│       ├── cfg/                  地图池(mapcycle_*.txt)与比赛用 cfg
│       └── translations/         短语文件(运行时读取,不编进 BMAG.smx)
├── campaign/                     单人战役两个独立小项目(tau_mp / hl1tau)
├── cfg/                          服务器 cfg/ 备份(server.cfg、autoexec、listenserver 等)
├── configs/                      SourceMod configs/ 备份(admins、advertisements、maplists 等)
├── motd/                         MOTD 页面
└── README.md / README.en.md
```

`.gitignore` 只排除 `merge.py` 生成的中间产物(`src/scripting/BMAG/*.sp`)与搁置的自定义准星客户端 mod
`client_mod/`;工具链、证据 dump、旧交付包与 `campaign/` 均已入库。

## 下载

### 解压即玩(推荐)

先给 Black Mesa 装好 **SourceMod + MetaMod:Source**,再把对应项目的 zip 解压到
**Black Mesa 文件夹**(包含 `bms\` 的那一层)即可。三个项目彼此独立,按需下载:

| 项目 | 下载 | 用途 |
|---|---|---|
| **BMAG** — 死斗服插件集(35 模块合一 + 4 个第三方插件) | [`BMAG.zip`](https://github.com/MXYLR/MXYLR-Black-Mesa-Sourcemod-plugins/releases/latest/download/BMAG.zip) | 死亡竞赛服务器 |
| **tau_mp** — 单人战役 tau:高斯跳 / 副攻无冷却 / 跌落伤害封顶 | [`tau_mp.zip`](https://github.com/MXYLR/MXYLR-Black-Mesa-Sourcemod-plugins/releases/latest/download/tau_mp.zip) | 单人剧情 |
| **hl1tau** — tau 满蓄伤害、溅射半径、穿墙门槛还原成 HL1 数值 | [`hl1tau.zip`](https://github.com/MXYLR/MXYLR-Black-Mesa-Sourcemod-plugins/releases/latest/download/hl1tau.zip) | 单人或死斗 |

zip 内结构是 `bms/addons/sourcemod/…`,并各带一份双语 `README.txt`(前置条件、解压
位置、装完还必须手动做的事)。**BMAG.zip 故意不含配置**,以免覆盖你已有的
`bms_match.cfg` / 地图池 —— 这些在 Release 里作为单独附件提供,见下表。

### 单独文件

每个 Release 对应仓库的一个提交,附件就是那次构建的产物:

| 附件 | 放到服务器 |
|---|---|
| `BMAG.smx` | `bms/addons/sourcemod/plugins/` |
| `bms_rpgReloadFix.smx` / `bms_weapon_tauStuckFix.smx` / `is_weaponfx.smx` / `is_bms_fix_timelimit.smx` | 同上 |
| `bms_match.games.txt` | `bms/addons/sourcemod/gamedata/`(**必须**,文件名不能改) |
| `bms_match.cfg` | `bms/addons/sourcemod/configs/` |
| `bms_match.phrases.txt` / `fast_spawn.phrases.txt` / `spawn_marker.phrases.txt` | `bms/addons/sourcemod/translations/`(**必须**) |
| `tau_mp.smx` + `tau_mp.games.txt` / `hl1tau.smx` | 单人战役环境的 `addons/sourcemod/` |

> 产物大小不可比:`spcomp` 的输出**不是字节可复现的**,同一份源码连编两次大小也不同,
> 判断附件新不新看标签和提交号。

## 安装

```bat
set SRV=<你的 srcds 根目录>
copy /Y plugins\BMAG.smx            %SRV%\bms\addons\sourcemod\plugins\
copy /Y plugins\bms_rpgReloadFix.smx       %SRV%\bms\addons\sourcemod\plugins\
copy /Y plugins\bms_weapon_tauStuckFix.smx %SRV%\bms\addons\sourcemod\plugins\
copy /Y plugins\is_weaponfx.smx            %SRV%\bms\addons\sourcemod\plugins\
copy /Y plugins\is_bms_fix_timelimit.smx   %SRV%\bms\addons\sourcemod\plugins\
copy /Y smx_analysis\src\scripting\translations\*.txt %SRV%\bms\addons\sourcemod\translations\
copy /Y smx_analysis\src\scripting\gamedata\bms_match.games.txt %SRV%\bms\addons\sourcemod\gamedata\
copy /Y smx_analysis\src\scripting\configs\bms_match.cfg %SRV%\bms\addons\sourcemod\configs\
copy /Y smx_analysis\src\scripting\cfg\*.txt             %SRV%\bms\cfg\
copy /Y smx_analysis\src\scripting\cfg\*.cfg             %SRV%\bms\cfg\
```

启动:`srcds.exe -game bms +map dm_boom +maxplayers 16 -condebug`。

要点:

- 除 `BMAG.smx` 外的 `.smx` 都是**独立插件,不在 BMAG 里**,必须单独拷
- `translations/*.txt` 是运行时读取、不编进 `BMAG.smx` 的,漏了聊天里会显示短语键名
- `bms_match.games.txt` 提供 `CGameRules::SetState` 的签名寻址,**文件名不能改**(`LoadGameConfigFile` 只补 `.txt`)
- SourceMod 自带的 `plugins/nextmap.smx` 要停用:本服换图由 `bms_match` 的投票 + 核心的 `sm_nextmap` 决定
- `is_weaponfx.smx` 需在 `server.cfg` 里显式设 `is_weaponfix_saddr`(默认值会被当成"未配置"而自我禁用)
- 命令权限字母:`b` = 通用管理,完整表见 `configs/admin_levels.cfg`
- 配置里仍带着**原服的服务器名、群号、域名和占位 SteamID**,用在公开服之前要改
  (`cfg/server.cfg`、`configs/admins.cfg`、`configs/advertisements.txt`、`motd/index.html`,搜 `>>>` 定位)

---

## ① `bms_match` — 比赛插件(自研)

参考 hl2dm 的 xms 比赛插件、按 Black Mesa 引擎重写。是 `BMAG.smx` 的一个模块,**不支持单独加载**。

### 玩家命令

| 命令 | 说明 |
|---|---|
| `!start` | 开始比赛。人数达到 `VoteMinPlayers` 时发起投票;否则(含 bot 时至少 2 人)直接开始 |
| `!cancel` | 取消比赛并恢复公服参数。比赛中需投票通过 |
| `!help` / `!commands` | 弹出比赛指令菜单(无线电菜单形式) |
| `!maplist` / `!list [模式]` | 查看地图池,`ffa` / `tdm` / `all`,默认当前模式 |
| `!run <地图>` / `!runnow <地图>` | 发起"换当前图"投票,支持 `模式:地图` 与缩写 |
| `!runnext <地图>` | 发起"设置下一张图"投票 |
| `!runrandom` | 从当前模式地图池随机抽 4 张发起换图投票 |
| `!shuffle` | 洗牌分队(仅 TDM) |
| `!invert` | 互换两队(仅 TDM) |
| `!yes` / `!no` / `!1`–`!5` | 投票表决 |
| `!pause` / `!unpause` | 暂停 / 继续服务器 |
| `!panel` / `!webpanel` | 打开游戏内网页控制台 |

**聊天别名**:`!stop` → `!cancel`、`!join` → 加入人数较少的队伍、`!spec` → 观战、
`!next <图>` → `!runnext <图>`、`!random` → `!runrandom`。

`!run` 支持的地图缩写:`bunker`→`dm_lambdabunker`、`bounce`、`stalk`→`dm_stalkyard`、
`sub`→`dm_subtransit`、`gas`→`dm_gasworks`、`rail`、`crossfire`、`boom`。

### 管理员命令(需 `b`)

| 命令 | 说明 |
|---|---|
| `!forcespec <玩家>` | 强制某玩家转入观战 |
| `!allow <玩家>` | 放行某玩家加入比赛(解除开赛后的加入封锁) |
| `!starttest` | 启动一场 **1 分钟**的测试比赛,用于验证 SourceTV 录像链路 |

### 比赛流程

1. `!start` → 人数 < `VoteMinPlayers` 直接开始,否则发起投票
2. MatchWait:执行 `exec server_match`(重置时限/封顶/复活)→ 冻结玩家并剥离武器 → 4 秒倒计时
3. Match:计时开始、锁定队伍;参赛者掉线自动暂停;FFA 取最高击杀(平局比死亡数),TDM 比队伍分
4. 平分 → 自动加时(每分钟续时直到分出胜负)
5. 结束:广播胜利与比分 → `exec server_match_post` 恢复公服参数 → 自动发起下一张图投票

比赛自动开启 SourceTV 录像,文件在服务器本机 `demos\` 目录,赛后广播文件名;配了
`bms_match.cfg` 的 `DownloadBase` 就能从 FastDL 的 `/demos` 下载。

**单人战役地图会被自动跳过**(判据 `bm_c<数字>` 前缀,78 张战役图):跳过队伍枚举、静默 1Hz 定时器,
并关掉 `fast_spawn`、`advertisements`、`connectmessage`、`showhealth`。

### 状态页(HUD 常驻信息)

每秒重画:`血量/护甲`、比赛状态、倒计时、地图、手持武器弹药(含 MP5 榴弹);死亡观战时改画被观察者,
通道 2 还追加自己的 K/D / ping 与前五名榜。

| ConVar | 默认 | 说明 |
|---|---|---|
| `bms_status_page` | 2 | 0 = 关;1 = 只有死亡/观战的人看;2 = 所有人 |
| `bms_status_channel` | 0 | 0 = hint 面板(带框多行,每条消息重播出现动画 = 看起来在闪);1 = HudMsg(无框 6 行);2 = HudMsg 紧凑版(+ K/D / ping / 前五名) |
| `bms_status_keyhint` | 1 | 通道 0 的面板:1 = `KeyHintText`(窄框多行);0 = `HintText`(和 Show Health 同一条细长条,静音不闪但只能一行) |
| `bms_status_hintsound` | 0 | 0 = 静音 hint 面板;1 = 不动玩家自己的设置 |
| `bms_status_stats` | 1 | 通道 2 追加 K/D / ping 与前五名榜 |
| `bms_status_right` | 0.89 | HudMsg 文本块右边界(屏幕宽度比例;16:10 上限约 0.91,16:9 约 0.82) |

### 其它 ConVar

| ConVar | 默认 | 说明 |
|---|---|---|
| `sm_bms_webpanel_enabled` | 1 | 启用游戏内网页控制台(需要 socket 扩展) |
| `sm_bms_webpanel_host` | *(空)* | 面板 URL 里的 Host,留空 = `127.0.0.1` |
| `sm_bms_webpanel_port` | 28015 | 网页控制台监听端口 |

### 配置(`configs/bms_match.cfg`)

| 键 | 默认 | 说明 |
|---|---|---|
| `VoteMinPlayers` / `VoteMaxTime` / `VoteCooldown` | 3 / 25 / 30 | 投票人数门槛、时限、冷却(秒) |
| `AutoVoting` | 1 | 比赛结束自动发起下一图投票 |
| `DefaultMode` / `RetainModes` | ffa / ffa,tdm | 默认模式 / 换图后保留的模式 |
| `PreMatchCommand` / `PostMatchCommand` | `exec server_match` / `exec server_match_post` | 开赛 / 赛后执行的 cfg |
| `Gamemodes` | — | 每模式:`Command`、`Mapcycle`、`Defaultmap`、`Matchable`、`Overtime`、`MatchTimelimit` |
| `Maps` | — | `StripPrefix`、`DefaultModes`、`Abbreviations` |

---

## ② 其它自研 / 深度改造模块(10 个)

都**编译在 `BMAG.smx` 内部**,不能单独加载。`spawn_distribute`、`textmsg_fix` 为自研,其余基于
AlliedModders 社区插件改造(`fast_spawn`、`speclist` 源自 Alienmario,`SpecDetails` 源自 wribit,
`missing_viewmodel_fix` 源自 ch4os + SHUFEN,`advertisements` 源自 Tsunami)。

| 模块 | 一句话 |
|---|---|
| `fast_spawn` | 零秒重生,不等原生按键或 5 秒 `mp_forcerespawn` |
| `spawn_distribute` | 复活点均匀分配,修原生同点堆人 |
| `textmsg_fix` | CP936 下 UTF-8 中文消息导致的 `_vsnprintf` 崩溃 |
| `adv-weapon_cleaner` | 掉落武器清扫 |
| `SpecDetails` | 观察者详情(左侧面板) |
| `speclist` | 观战者列表 |
| `missing_viewmodel_fix` | 切队/切观察后重建 viewmodel |
| `advertisements` | 轮播广告 |
| `sm_noearbleed` | 去掉爆炸耳鸣/压耳声 |
| `spawn_marker` | 复活点落点标记(训练用,默认关) |

### `fast_spawn` — 零秒重生

| 命令 | 权限 | 说明 |
|---|---|---|
| `fastspawn` / `sm_fs` | b | 查询或开关零秒重生 |

| ConVar | 默认 | 说明 |
|---|---|---|
| `sm_fastspawn` | 1 | 启用:死亡 `sm_fastspawn_time` 秒后重生 |
| `sm_fastspawn_batch` | 4 | 每个游戏 tick 最多重生几人(调小更平滑) |
| `sm_fastspawn_time` | 0.0 | 重生延迟秒数(0 = 立即) |

真人被打死时**六个武器槽全部掉到地上**(bot 例外,仍只掉手持那把);单人战役地图与比赛期间自动关闭。

### `spawn_distribute` — 复活点均匀分配

BM 原生的复活点选择链已损坏(`IsSpawnPointValid` 不读标旗、用零长度 trace 判占用),所有人会被扔到同一个点。
本模块不碰原生逻辑,在 `player_spawn` 里自己挑空闲点传送。

| ConVar | 默认 | 说明 |
|---|---|---|
| `spawn_distribute_enabled` | 1 | 开启 |
| `spawn_distribute_cooldown` | 2.0 | 同一点被分配后多少秒内不重复分配 |
| `spawn_distribute_radius` | 64.0 | 真人占用判定半径(bot 不参与) |

### `textmsg_fix` — 中文崩溃修复

修复 CP936 代码页下 UTF-8 中文消息尾字节悬空前导导致的 `_vsnprintf` fail-fast 崩溃。无命令、无 ConVar。

### `adv-weapon_cleaner` — 掉落武器清扫

| ConVar | 默认 | 说明 |
|---|---|---|
| `adv_weapon_cleaner_keep_map_weapons` | 1 | 是否保留地图固有武器(0 = 清,1 = 留) |
| `adv_weapon_cleaner_much_weapons` | 100 | 触发清理的武器数阈值 |
| `adv_weapon_cleaner_remove_delay` | 20.0 | 丢下武器后等待多久移除 |
| `adv_weapon_cleaner_remove_delay2` | 0.1 | 每把武器的递减延迟 |
| `adv_weapon_cleaner_sweep_interval` | 10.0 | 全量清扫间隔秒数(0 = 关闭) |

只跟踪 `weapon_*`,不误删 `item_*`(充电器、道具)。

### `SpecDetails` — 观察者详情

`sm_specDetails_enabled`(默认 1)。比赛期间自动禁用(面板更新有 5 秒冷却)。

### `speclist` — 观战者列表

无命令、无 ConVar。定时刷新观战者名单。

### `missing_viewmodel_fix` — 缺失持枪模型修复

无命令、无 ConVar。挂 `jointeam` 与 `client_specmode`,在切换队伍/观察模式后重建 viewmodel。

### `advertisements` — 轮播广告

| 命令 | 权限 | 说明 |
|---|---|---|
| `sm_advertisements_reload` | b | 重新读取广告文件 |

| ConVar | 默认 | 说明 |
|---|---|---|
| `sm_advertisements_enabled` | 1 | 启用/关闭 |
| `sm_advertisements_file` | advertisements.txt | 广告文本文件 |
| `sm_advertisements_interval` | 30 | 广告间隔秒数(本服设的是 600) |
| `sm_advertisements_random` | 0 | 随机顺序播放 |

### `sm_noearbleed` — 去除耳鸣/压耳声

无命令,仅 `sm_noearbleed_version`。挂 `OnTakeDamage` 把 `DMG_BLAST` 改成 `DMG_GENERIC`(不改伤害数值)。

### `spawn_marker` — 复活点落点标记(默认关)

训练用:在 `player_spawn` 时标记玩家**实际落地**的那个点。

| 命令 | 权限 | 说明 |
|---|---|---|
| `sm_spawnmarker` | b | 开关复活点标记 |
| `sm_spawnmap` | b | 开关全图复活点常显 |
| `sm_sm` | b | 快捷别名 |

| ConVar | 默认 | 说明 |
|---|---|---|
| `sm_spawnmarker_enabled` | 0 | 启用复活点标记 |
| `sm_spawnmarker_life` | 5.0 | 标记存在时长(秒) |
| `sm_spawnmarker_spawnmap` | 0 | 持续显示所有死亡竞赛复活点 |

---

## ③ SourceMod 官方模块(25 个)

绝大多数是 SourceMod 自带官方插件(少数为社区插件,如 `connectmessage`、`showhealth`、`teamjoinblocker`),
同样都**编译在 `BMAG.smx` 内部**。命令与 ConVar **全是上游默认值**,这里只列作用与本服的偏离点。

| 模块 | 作用 | 本服注意 |
|---|---|---|
| `admin-flatfile` | 从 `configs/*.cfg` 读管理员 | 本服**唯一**的管理员来源(不用 SQL) |
| `admincheats` | 执行作弊命令所需权限 | |
| `adminhelp` | `sm_help` / `sm_searchcmd` | |
| `adminmenu` | `sm_admin` 管理员菜单 | |
| `antiflood` | 聊天刷屏限制 | |
| `basechat` | 管理员聊天(`sm_say` / `sm_csay` / `sm_hsay` / `sm_msay` / `sm_psay` 等) | |
| `basecomm` | 禁言/禁麦(`sm_gag` / `sm_mute` / `sm_silence`) | 本服唯一的禁言手段 |
| `basecommands` | `sm_kick` / `sm_map` / `sm_rcon` / `sm_cvar` / `sm_who` 等 | `rcon_password` 受保护,`sm_cvar` 读不到 |
| `basetriggers` | 聊天触发词(`timeleft` / `nextmap` / `motd` / `ff`) | |
| `basevotes` | 投票(`sm_vote` / `sm_voteban` / `sm_votekick` / `sm_votemap`) | `sm_voteban` 走 SourceMod 核心的本地封禁 |
| `clientprefs` | 客户端 cookie | 需数据库才持久化 |
| `connectmessage` | 玩家加入/离开提示 | 社区插件 |
| `funcommands` | 娱乐命令(`sm_beacon` / `sm_burn` / `sm_freeze` / `sm_noclip` 等) | |
| `funvotes` | 娱乐投票 | |
| `mapchooser` | 结束换图投票、`sm_setnextmap` | 本服强制 `sm_mapvote_endvote 0`,避免覆盖 `sm_nextmap` |
| `motd-fixer` | 延时打开 MOTD | 社区插件 |
| `nominations` | 地图提名 `sm_nominate` | |
| `pause` | `sm_pause` / `sm_unpause` | 聊天 `!pause` 由 `bms_match` 接管,两者别混用 |
| `playercommands` | `sm_slap` / `sm_slay` / `sm_rename` | |
| `reservedslots` | 预留通道 | 本服 `sm_reserved_slots` 为 0(未启用) |
| `rockthevote` | RTV 换图 `sm_rtv` | |
| `showhealth` | 屏幕上显示血量 | 社区插件;与状态页共用 hint 面板,战役图静默 |
| `sounds` | `sm_play` 播放声音 | |
| `sql-admin-manager` | SQL 管理员增删改 | 本服管理员走 `admin-flatfile`,这些是备用 |
| `teamjoinblocker` | 换边封锁 `sm_toggle_join` | 社区插件 |

> `BMAG.smx` **不含任何封禁命令**(`sm_ban` / `sm_addban` / `sm_unban` / `sm_banip` 都没有)。
> 禁言禁麦仍由 `basecomm` 提供;需要本地封禁命令就启用 `plugins/disabled/basebans.smx`(独立插件,无需数据库)。

---

## ④ 独立插件

### 单人战役插件(`campaign/`)

tau 炮在单人战役里是"阉割版":没有高斯跳、副攻有硬直 —— 这两条分支写死在 `server.dll` 里
(按 `IsMultiplayer()` 判),纯 ConVar 改不出来。两个插件各自独立,只服务单机剧情:

| 项目 | 做什么 |
|---|---|
| `campaign/tau_mp/` | 让单人 tau 拥有多人模式的**高斯跳**与**右键无冷却**,并把**跌落伤害封顶**在 10 HP |
| `campaign/hl1tau/` | 把 tau 的溅射半径还原成 HL1 的值 |

### 第三方插件(无源码)

| 插件 | 作用 |
|---|---|
| `bms_rpgReloadFix.smx` | RPG 换弹动画修复 |
| `bms_weapon_tauStuckFix.smx` | tau 低弹药卡枪修复:右键第一 tick 且手持 `weapon_tau` 时把备用弹药补到 3 |
| `is_weaponfx.smx` | 武器动画预热(需在 `server.cfg` 设 `is_weaponfix_saddr`) |
| `is_bms_fix_timelimit.smx` | 回合时限修复(BM 只在地图加载时读一次 `mp_timelimit`;它走 `mp_round_time` 实体的加时输入) |

---

## 从源码构建

```bash
cd smx_analysis
python merge.py          # 生成 src/scripting/BMAG/BMAG.sp(36 模块合并)
```

再用仓库自带的 spcomp 编译(`dl/sm-win/`):

```bash
./dl/sm-win/addons/sourcemod/scripting/spcomp.exe \
  -i "src/scripting/include" \
  -o "src/scripting/BMAG/BMAG.smx" \
  "src/scripting/BMAG/BMAG.sp"
```

基线:**48 个警告、0 个错误**。

注意:

- spcomp 输出**不是字节可复现的**,判断新旧以功能验证或日志为准,别比 MD5
- `include/` 必须与服务器那一版 SourceMod 一致:旧版 `sourcemod.inc` 的 `StoreToAddress` 只有 3 个参数,会编译报错
- **签名必须抗重定位**:`GameConfGetAddress` 扫的是已加载内存,含绝对地址(`imm32`)的签名会因 base relocation 在运行时失配(磁盘命中、内存不命中,静默不生效)。用 `smx_analysis/sig_check.py` 校验
- `merge.py` 只桥接**精确的** forward 名;`bms_match` 的 `Bms_` 前缀回调靠 `FORWARD_ALIASES` 映射回标准名,改 forward 命名时务必同步该表,否则回调静默失效
- 单人战役两个插件的源码在 `campaign/` 下,不在 `merge.py` 范围内,需单独编译
- `src/scripting/compile_all.sh`(逐个编译 `plugins/*.sp`)的 `SPCOMP` 路径硬编码成 `/c/tmp/smx_analysis/...`,仓库里并不存在;要用就先改成 `smx_analysis/dl/...`

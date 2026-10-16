# 自用版新增功能

本分支基于 [suversal/WrapPin](https://github.com/suversal/WrapPin) 1.0.18，仅供个人非商业使用（PolyForm Noncommercial 1.0.0），保留原项目与 Roam Control 的署名。

## 安装

每次推送到 `custom-features` 分支，GitHub Actions 会在云端 Mac 上编译未签名 IPA，并发布到本仓库的 Releases。下载 `.ipa` 后用 SideStore 安装（My Apps → +），与官方版安装方式相同。

## 1. Quantumult X 隧道

在 Quantumult X 配置的 `[general]` 中加入：

```ini
reflected_routes = 10.7.0.1/32
```

然后在 WrapPin「设置 → 隧道跳转应用」中选择 Quantumult X。Quantumult X 没有公开的“开启 VPN”URL 动作，所以设备通道不可达时 WrapPin 只会打开它，需要手动开启 VPN 后返回。若连接失败，先在 Wi-Fi 下验证，并尝试关闭 Quantumult X 隧道的 IPv6。

## 2. 快捷指令

在「快捷指令」App 中搜索 WrapPin，可使用以下操作：

| 操作 | 说明 |
| --- | --- |
| 模拟收藏地点 | 从 WrapPin 的收藏列表中选择地点 |
| 模拟地图链接中的位置 | 支持苹果地图、高德地图链接（含短链接）和“纬度,经度”文本 |
| 模拟经纬度 | 使用地图 App 显示的坐标（中国大陆为 GCJ-02） |
| 停止模拟并恢复真实位置 | 与 App 内“停止”相同 |

执行时会先打开 WrapPin，再按 App 内同样的流程开始或停止模拟。

### 控制中心按钮

控制中心 → 左上角 + → 添加控制 → 快捷指令，选择上面的操作或你自己建的快捷指令。

## 3. 从苹果地图分享开始模拟

1. 新建快捷指令，添加操作「模拟地图链接中的位置」，地图链接选择「快捷指令输入」。
2. 在快捷指令详情中打开「在共享表单中显示」，输入类型保留 URL 和文本。
3. 在苹果地图（或高德地图）中选择地点 → 分享 → 选择这个快捷指令。

坐标保持地图 App 给出的原值，与在 WrapPin 地图上手动选点一致，再按 App 的坐标模式（GCJ-02/WGS84 推荐值）换算。

也可以直接打开链接：

- `wrappin://simulate?lat=31.2304&lon=121.4737&name=人民广场`
- `wrappin://simulate?link=<URL 编码后的地图链接>`
- `wrappin://stop`

## 4. 定时恢复真实位置

「设置 → 定时恢复真实位置」可选择 15 分钟到 8 小时。开始模拟时开始计时，到时自动停止模拟并恢复真实位置；模拟进行中修改设置会从当时重新计时。

## 更新检查

App 内的更新检查指向本仓库的 Releases，不再提示官方版更新，避免误装官方版后丢失以上功能。

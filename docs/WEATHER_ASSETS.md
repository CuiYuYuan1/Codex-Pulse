# 动态天气资源清单

天气视觉采用 [Meteocons](https://meteocons.com/) 的 Fill 动态 SVG，来源包为 `@meteocons/svg@0.1.0`。项目只选取当前天气映射需要的 16 个文件，并放入：

- macOS：`CodexPulse/Resources/WeatherAnimated/`
- Windows 动态版：`windows/src/renderer/assets/weather-animated/animated/`
- Windows 减少动态效果版：`windows/src/renderer/assets/weather-animated/static/`

这些 SVG 内含 SMIL 动画；晴天会旋转日光，云层会漂浮，雨、雪与雷暴也使用素材自身的动画。素材随应用离线分发，运行时不会访问 Meteocons CDN。macOS 通过系统 WebKit 播放，不增加第三方动画运行库；开启系统“减少动态效果”时会暂停 SVG 动画。

| 应用天气 | 白天素材 | 夜间素材 |
|---|---|---|
| 晴 | `clear-day.svg` | `clear-night.svg` |
| 多云 | `partly-cloudy-day.svg` | `partly-cloudy-night.svg` |
| 阴 | `overcast-day.svg` | `overcast-night.svg` |
| 雾 | `fog-day.svg` | `fog-night.svg` |
| 毛毛雨 | `partly-cloudy-day-drizzle.svg` | `partly-cloudy-night-drizzle.svg` |
| 雨 / 阵雨 | `partly-cloudy-day-rain.svg` | `partly-cloudy-night-rain.svg` |
| 雪 | `partly-cloudy-day-snow.svg` | `partly-cloudy-night-snow.svg` |
| 雷暴 | `thunderstorms-day-rain.svg` | `thunderstorms-night-rain.svg` |

## 许可

Meteocons is licensed under the MIT License.

Copyright (c) 2020-present Bas Milius

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

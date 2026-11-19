"""Arrange actual widget captures for README; requires Pillow.

Run after QINGNIAO_RENDER_PREVIEW=1 flutter test test/preview_screens_test.dart.
Only the surrounding captions and frames are drawn here; screen content comes
unchanged from build/preview. Uses the repository's bundled fonts.
"""
from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "build/preview"
OUTPUT = ROOT / "docs/images"
FONT = ROOT / "assets/fonts/HarmonyOS_SansSC_Regular.ttf"
BOLD = ROOT / "assets/fonts/HarmonyOS_SansSC_Bold.ttf"


def compose(name, title, subtitle, screens, *, dark=False):
    width = 412
    gap, margin, top = 32, 48, 160
    captures = []
    for file, label in screens:
        with Image.open(SOURCE / f"{file}.png") as source:
            size = (width, round(source.height * width / source.width))
            captures.append((source.convert("RGB").resize(size, Image.Resampling.LANCZOS), label))
    height = max(image.height for image, _ in captures)
    background = "#101b1a" if dark else "#eaf4f0"
    foreground = "#deeee7" if dark else "#123b32"
    muted = "#9eb9b0" if dark else "#4d7066"
    canvas = Image.new("RGB", (margin * 2 + width * len(screens) + gap * (len(screens) - 1),
                               top + height + 112), background)
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 30), title, font=ImageFont.truetype(str(BOLD), 32), fill=foreground)
    subtitle_size = 18
    subtitle_font = ImageFont.truetype(str(FONT), subtitle_size)
    while draw.textlength(subtitle, font=subtitle_font) > canvas.width - margin * 2:
        subtitle_size -= 1
        subtitle_font = ImageFont.truetype(str(FONT), subtitle_size)
    draw.text((margin, 86), subtitle, font=subtitle_font, fill=muted)
    for index, (image, label) in enumerate(captures):
        x = margin + index * (width + gap)
        # Keep every screen pixel; frames stay outside the capture.
        draw.rounded_rectangle((x - 2, top - 2, x + width + 1, top + image.height + 1),
                               radius=3, fill=muted)
        canvas.paste(image, (x, top))
        draw.text((x + width / 2, top + height + 14), label,
                  font=ImageFont.truetype(str(FONT), 19), fill=foreground, anchor="mt")
    draw.text((margin, canvas.height - 35), "实际界面渲染 · 测试夹具短信 / Widget captures · Fixture messages",
              font=ImageFont.truetype(str(FONT), 15), fill=muted)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.save(OUTPUT / name, optimize=True)
    print(f"Wrote docs/images/{name}")


def main():
    version = re.search(r"^version:\s*([^+\s]+)", (ROOT / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if version is None:
        raise ValueError("pubspec.yaml has no version")
    release = version[1]
    compose("preview-light.png", f"青鸟 Qingniao {release} · 浅色 / Light",
            "消息来源清晰可见，写短信入口带文字 / SIM source labels and a labeled compose button",
            [("home_inbox_light", "收件箱 / Inbox"), ("conversation_light", "会话 / Conversation"),
             ("otp_light", "验证码 / Codes")])
    compose("preview-dark.png", f"青鸟 Qingniao {release} · 深色 / Dark",
            "统一的色调表面、消息气泡与导航高光 / Tonal surfaces, message bubbles and navigation highlights",
            [("home_inbox_dark", "收件箱 / Inbox"), ("conversation_dark", "会话 / Conversation"),
             ("settings_dark", "设置 / Settings")], dark=True)
    compose("preview-navigation.png", f"导航栏外观 / Navigation · {release}",
            "白色边缘高光可关闭；模糊与透明度可调 / Optional white rim, adjustable blur and opacity",
            [("navigation_appearance_light", "浅色 / Light"), ("navigation_appearance_dark", "深色 / Dark")])


if __name__ == "__main__":
    main()

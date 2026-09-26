"""把散落 6 处的「周几 -> 文案」映射统一到 l10n 扩展上。

背景：`_weekdayShort` / `_shortDay` 这份 switch 在课表表格、时间轴、快速排课、
作息设置、考勤日历、模板编辑页里各抄了一份（6 处）。任何一处漏改都会出现
"同一个星期几在不同页面叫法不同"。统一收到 `AppLocalizations.weekdayShort`。

用法：python .workbuddy/tools/unify_weekday_label.py
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

METHOD = """  String _weekdayShort(int weekday) {
    final l10n = context.l10n;
    return switch (weekday) {
      1 => l10n.mon,
      2 => l10n.tue,
      3 => l10n.wed,
      4 => l10n.thu,
      5 => l10n.fri,
      6 => l10n.sat,
      _ => l10n.sun,
    };
  }
"""

METHOD_SHORT_DAY = """  String _shortDay(int weekday) {
    final l10n = context.l10n;
    return switch (weekday) {
      1 => l10n.mon,
      2 => l10n.tue,
      3 => l10n.wed,
      4 => l10n.thu,
      5 => l10n.fri,
      6 => l10n.sat,
      _ => l10n.sun,
    };
  }
"""

METHOD_TIMELINE = """  String _weekdayShort(BuildContext context, int weekday) {
    final l10n = context.l10n;
    return switch (weekday) {
      1 => l10n.mon,
      2 => l10n.tue,
      3 => l10n.wed,
      4 => l10n.thu,
      5 => l10n.fri,
      6 => l10n.sat,
      _ => l10n.sun,
    };
  }
"""

SWITCH_INLINE = """    final label = switch (weekday) {
      1 => l10n.mon,
      2 => l10n.tue,
      3 => l10n.wed,
      4 => l10n.thu,
      5 => l10n.fri,
      6 => l10n.sat,
      _ => l10n.sun,
    };
"""

EDITS = {
    "lib/features/attendance/attendance_page.dart": [
        ("_weekdayShort(weekday)", "context.l10n.weekdayShort(weekday)"),
        ("_weekdayShort(day.weekday)", "context.l10n.weekdayShort(day.weekday)"),
        ("\n" + METHOD, "\n"),
    ],
    "lib/features/schedule/lesson_quick_add_sheet.dart": [
        ("_weekdayShort(weekday)", "context.l10n.weekdayShort(weekday)"),
        ("\n" + METHOD, "\n"),
    ],
    "lib/features/schedule/schedule_settings_sheet.dart": [
        ("_weekdayShort(day)", "context.l10n.weekdayShort(day)"),
        ("widget.availableWeekdays.map(_shortDay).join('、')",
         "widget.availableWeekdays.map(context.l10n.weekdayShort).join('、')"),
        ("\n" + METHOD, "\n"),
        ("\n" + METHOD_SHORT_DAY, "\n"),
    ],
    "lib/features/schedule/timeline_view.dart": [
        ("final short = _weekdayShort(context, weekday);",
         "final short = context.l10n.weekdayShort(weekday);"),
        ("\n" + METHOD_TIMELINE, "\n"),
    ],
    "lib/features/templates/template_editor_page.dart": [
        ("_weekdayShort(weekday)", "context.l10n.weekdayShort(weekday)"),
        ("\n" + METHOD, "\n"),
    ],
    "lib/features/schedule/class_grid_view.dart": [
        (SWITCH_INLINE, "    final label = l10n.weekdayShort(weekday);\n"),
    ],
}


def main():
    for rel, pairs in EDITS.items():
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        with io.open(path, encoding="utf-8") as fh:
            source = fh.read()
        for old, new in pairs:
            assert old in source, "%s 里找不到：%r" % (rel, old[:60])
            source = source.replace(old, new)
        with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(source)
        print("%s: %d 处已替换" % (rel, len(pairs)))

    # 复核：不该再有本地实现
    leftovers = []
    for root, _dirs, files in os.walk(os.path.join(ROOT, "lib")):
        for name in files:
            if not name.endswith(".dart"):
                continue
            full = os.path.join(root, name)
            with io.open(full, encoding="utf-8") as fh:
                text = fh.read()
            if "_weekdayShort" in text or "_shortDay" in text:
                leftovers.append(os.path.relpath(full, ROOT))
    assert not leftovers, "仍有本地周几映射：%s" % leftovers
    print("周几文案已收敛到 AppLocalizations.weekdayShort")


if __name__ == "__main__":
    main()

"""给 zh/en 两个 arb 补齐新增的文案键（键必须严格对齐）。**幂等**，可反复跑。

用法：python .workbuddy/tools/add_l10n_keys.py
写完立刻 json.loads 复验，并断言 zh/en 键集合一致。

历史轮次已并入本脚本：
  - 第 6 轮：日历圆环文案、pickCourseHint 口径
  - 第 7 轮：休学 / 免修长期状态 + 考勤按班分组的横带文案
"""
import json
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

NEW_KEYS = {
    # ---- 第 6 轮：日历圆环：有课但没点名 / 点过名后的出勤率 ----
    "attendanceRingNoRecord": {"zh": "已排课 · 未点名", "en": "Scheduled · not marked"},
    "attendanceRingRate": {
        "zh": "出勤 {present}/{expected}",
        "en": "Present {present}/{expected}",
    },
    # ---- 第 7 轮：休学 / 免修（课程级长期状态，180 天）----
    "statusSuspended": {"zh": "休学", "en": "Suspended"},
    "statusExempt": {"zh": "免修", "en": "Exempt"},
    "statusShortSuspended": {"zh": "休", "en": "Sus"},
    "statusShortExempt": {"zh": "免", "en": "Ex"},
    "attendanceLongTermUntil": {"zh": "{status} · 至 {date}", "en": "{status} · until {date}"},
    "attendanceLongTermSet": {
        "zh": "{name} 已标记为{status}，至 {date}",
        "en": "{name} marked {status} until {date}",
    },
    "attendanceLongTermCleared": {
        "zh": "{name} 已恢复正常点名",
        "en": "{name} is back to normal roll call",
    },
    "attendanceLongTermClearTitle": {"zh": "取消{status}？", "en": "Cancel {status}?"},
    "attendanceLongTermClearBody": {
        "zh": "{name} 将恢复正常点名，之后每节课都要单独标记。",
        "en": "{name} returns to normal roll call and must be marked lesson by lesson.",
    },
    "attendanceLongTermLocked": {
        "zh": "{name} · {status}（至 {date}），无需逐节点名",
        "en": "{name} · {status} until {date} — no per-lesson marking needed",
    },
    # ---- 第 7 轮：考勤名单按班级分组的横带 ----
    "rosterGroupCount": {"zh": "{count} 人", "en": "{count} students"},
    # ---- 第 16 轮：休学加「复学」确认、免修改为可并存的角标 ----
    # 背景：休学 / 免修以前都会锁死日常五态，导致学生一旦被标记就无法再改。
    # 实际上休学才「不来」，免修的学生仍会来上课、还可能迟到早退。所以：
    # 休学 → 再点弹「复学」确认；免修 → 只当角标，日常点名照常。
    "attendanceResumeTitle": {"zh": "是否复学？", "en": "Resume roll call?"},
    "attendanceResumeBody": {
        "zh": "{name} 当前已休学。复学后将恢复正常点名。",
        "en": "{name} is currently suspended. Resuming restores normal roll call.",
    },
    "attendanceResumeConfirm": {"zh": "复学", "en": "Resume"},
    # ---- 第 8 轮：课表分享（截图 + 底部 app 名 + 二维码位）----
    "shareSchedule": {"zh": "分享课表", "en": "Share schedule"},
    "shareSavedToGallery": {"zh": "已保存到相册", "en": "Saved to gallery"},
    "shareGalleryPermissionDenied": {
        "zh": "需要「照片和视频」权限才能保存到相册",
        "en": "Allow photos & videos access to save to the gallery",
    },
    "shareOpenSettings": {"zh": "去设置", "en": "Settings"},
    "shareCaptureFailed": {"zh": "截图失败，请重试", "en": "Couldn't capture, try again"},
    # 分享卡片右下角的二维码占位文案（二维码方案定了以后整个替换掉占位组件）
    "shareQrPlaceholder": {"zh": "二维码位", "en": "QR code"},
    # ---- 第 9 轮：考勤异常摘要 / 统计按课程 / 工具箱两页 / 日程重复周期 ----
    "copyAction": {"zh": "复制", "en": "Copy"},
    "summaryNoAbnormal": {"zh": "全员出勤，无异常", "en": "All present, nothing abnormal"},
    "courseFilterLabel": {"zh": "按课程筛选", "en": "Filter by course"},
    "eventRecurrence": {"zh": "重复周期", "en": "Repeats"},
    "eventRecurrenceOnce": {"zh": "单次", "en": "Once"},
    "eventRecurrenceWeekly": {"zh": "每周", "en": "Weekly"},
    "eventRecurrenceBiweekly": {"zh": "隔周", "en": "Biweekly"},
    "eventRecurrenceMonthly": {"zh": "每月", "en": "Monthly"},
    # ---- 第 10 轮：受益学生数 + 工具箱滑动提示 ----
    "insightBenefitedStudents": {"zh": "受益学生", "en": "Students reached"},
    "toolboxSwipeHint": {"zh": "左右滑动 · 共 2 页", "en": "Swipe · 2 pages"},
    # ---- 第 11 轮：拍照识别课表（本地 OCR，不依赖任何 LLM 服务商）----
    "ocrTitle": {"zh": "拍照识别课表", "en": "Scan schedule photo"},
    "ocrEntryTitle": {"zh": "拍照生成课表", "en": "Schedule from photo"},
    "ocrEntryDesc": {
        "zh": "拍一张课表照片，本机识别后自动排进课表",
        "en": "Snap a timetable, recognize it on-device, build the schedule",
    },
    "ocrPickPhoto": {"zh": "选择课表照片", "en": "Choose a photo"},
    "ocrPickPhotoHint": {
        "zh": "把整张课表拍平、拍正，字要清楚；表头有「周一…周五」和「第 N 节」最容易识别",
        "en": "Shoot the whole timetable flat and straight. Headers like "
            "\"Mon…Fri\" and \"period N\" help a lot",
    },
    "ocrFromCamera": {"zh": "拍照", "en": "Camera"},
    "ocrFromGallery": {"zh": "从相册选", "en": "From gallery"},
    "ocrRecognizing": {"zh": "正在识别…", "en": "Recognizing…"},
    "ocrRecognizingHint": {
        "zh": "全部在本机完成，照片不会上传到任何服务器",
        "en": "Runs entirely on this device — nothing is uploaded",
    },
    "ocrCropTitle": {"zh": "框选课表区域", "en": "Frame the timetable"},
    "ocrCropHint": {
        "zh": "只框住表格本身，去掉标题和空白，识别更准",
        "en": "Frame just the table — drop the title and margins for better accuracy",
    },
    "ocrCropReset": {"zh": "重新框选", "en": "Reset frame"},
    "ocrCropConfirm": {"zh": "识别这块区域", "en": "Recognize this area"},
    "ocrResultTitle": {"zh": "识别结果", "en": "Recognition result"},
    "ocrResultSummary": {
        "zh": "{lessons} 节课 · {courses} 门课 · 覆盖 {days} 天",
        "en": "{lessons} lessons · {courses} courses · {days} days",
    },
    "ocrConfidenceHigh": {
        "zh": "识别效果不错，确认无误后导入",
        "en": "Looks good — review and import",
    },
    "ocrConfidenceMedium": {
        "zh": "识别结果一般，请逐条核对后再导入",
        "en": "So-so result — check each row before importing",
    },
    "ocrConfidenceLow": {
        "zh": "这张照片不太清楚，建议重拍或手动修正",
        "en": "The photo is unclear — retake it or fix the rows by hand",
    },
    "ocrImport": {"zh": "导入课表", "en": "Import"},
    "ocrImportDone": {
      "zh": "已导入 {lessons} 节课，新增 {courses} 门课程",
      "en": "Imported {lessons} lessons, {courses} new courses",
    },
    "ocrRecapture": {"zh": "重拍一张", "en": "Retake"},
    "ocrEditRow": {"zh": "点击可修改课程名", "en": "Tap to edit the course name"},
    "ocrRowEditTitle": {"zh": "修改课程名", "en": "Edit course name"},
    "ocrNoPhoto": {"zh": "没有选择照片", "en": "No photo selected"},
    "ocrNoPhotoPermission": {
        "zh": "需要「照片」权限才能读取课表图片",
        "en": "Photo access is needed to read the timetable image",
    },
    "ocrEngineUnavailable": {
      "zh": "本机没有可用的文字识别引擎，请改用 Excel 导入",
      "en": "No on-device text recognition engine available — use Excel import instead",
    },
    "ocrEngineUnavailableTitle": {"zh": "无法调用识别引擎", "en": "Engine unavailable"},
    "ocrEngineUnavailableBody": {
      "zh": "文字识别完全跑在手机本机（Google ML Kit 离线模型），不需要联网、"
          "也不会上传照片。当前设备取不到这个能力，通常是系统版本过低或缺少 "
          "Google 服务。你可以先用「Excel 导入名单」那条路，或者手动在课表里排课。",
      "en": "Recognition runs fully on-device (offline ML Kit). No network, no upload. "
          "This device can't provide it — usually an old OS or missing Google services. "
          "Use Excel import or place lessons by hand for now.",
    },
    "ocrWarnNoWeekday": {
      "zh": "没认到「周几」表头，请确认照片拍全了整张表",
      "en": "No weekday header found — make sure the whole table is in frame",
    },
    "ocrWarnPartialWeekday": {
      "zh": "只认到部分星期列，可能有几天没识别出来",
      "en": "Only some weekday columns were found — a few days may be missing",
    },
    "ocrWarnNoPeriod": {
      "zh": "没认到「第几节」表头，建议重拍或手动修正",
      "en": "No period header found — retake or fix it by hand",
    },
    "ocrWarnNoLesson": {
      "zh": "没有识别出任何课程，换个角度或拍清楚一点再试",
      "en": "No lessons recognized — try another angle or a sharper shot",
    },
    "ocrManualAdd": {"zh": "手动补一节", "en": "Add a lesson by hand"},
    "ocrAllWeekdays": {"zh": "全部", "en": "All"},
    "ocrNoGoogleServices": {
        "zh": "未安装 Google 服务，识别功能不可用",
        "en": "Google services missing — recognition unavailable",
    },
    # ---- 第 12 轮：拍照识别正式集成到课表设置 + 机型适配说明 + 错峰课表日程可见性 ----
    # 课表设置里那一行的副标题（原先是"OCR 识别开发中，敬请期待"，现在功能已经可用）
    "ocrSettingsHint": {
        "zh": "拍张课表照片，本机识别后自动排进这一格",
        "en": "Snap the timetable, recognize it on-device, place it here",
    },
    # 机型适配卡片：告诉老师"我这台手机能不能用、不能用的替代路径是什么"
    "ocrDeviceTitle": {"zh": "机型适配", "en": "Device support"},
    "ocrDeviceAndroid": {
        "zh": "安卓（小米 / OPPO / vivo 等国产手机）：可直接使用。识别用系统自带的离线文字识别，"
              "有 Google 服务走 ML Kit，没有则自动回落到系统自带识别，全程不联网。",
        "en": "Android (Xiaomi / OPPO / vivo and friends): ready to use. Recognition uses the "
              "device's offline text engine — ML Kit when Google services are present, with a "
              "system fallback otherwise. No network at any point.",
    },
    "ocrDeviceHarmony": {
        "zh": "华为（鸿蒙 HarmonyOS）：本功能暂未适配，鸿蒙缺少上述两个识别接口。"
              "后续会按鸿蒙的 AI 能力单独接一版，当前请先用 Excel 导入或手动排课。",
        "en": "Huawei (HarmonyOS): not supported yet — HarmonyOS exposes none of the engines "
              "above. A dedicated version is planned; use Excel import or place lessons by hand "
              "for now.",
    },
    "ocrDeviceIos": {
        "zh": "苹果 iOS：能力已预留在 Apple Vision 上，等 iOS 版本开发时一并启用。",
        "en": "iOS: the hook is reserved on top of Apple Vision and will be enabled together "
              "with the iOS build.",
    },
    # 错峰课表：日程小方块展开后的时间 / 内容
    "timelineEventLegend": {"zh": "日程", "en": "Event"},
    "timelineEventTapHint": {"zh": "点一下看时间", "en": "tap for time"},
    "timelineEventTime": {"zh": "{start} - {end}", "en": "{start} - {end}"},
    # ---- 第 13 轮：中国节假日 / 调休（周末上班日提醒"上周几的课"）----
    "holidayKindHoliday": {"zh": "休", "en": "Off"},
    "holidayKindMakeup": {"zh": "班", "en": "On"},
    "holidayLegend": {
        "zh": "红底=放假 · 橙底=调休上班",
        "en": "Red = holiday · amber = makeup workday",
    },
    "holidayNameNewYear": {"zh": "元旦", "en": "New Year's Day"},
    "holidayNameSpringFestival": {"zh": "春节", "en": "Spring Festival"},
    "holidayNameQingming": {"zh": "清明节", "en": "Qingming Festival"},
    "holidayNameLabourDay": {"zh": "劳动节", "en": "Labour Day"},
    "holidayNameDragonBoat": {"zh": "端午节", "en": "Dragon Boat Festival"},
    "holidayNameMidAutumn": {"zh": "中秋节", "en": "Mid-Autumn Festival"},
    "holidayNameNationalDay": {"zh": "国庆节", "en": "National Day"},
    "holidayNameNationalDayMidAutumn": {
        "zh": "国庆节、中秋节",
        "en": "National Day & Mid-Autumn Festival",
    },
    "holidayMakeupTitle": {"zh": "今天调休上班", "en": "Makeup workday today"},
    "holidayMakeupAsk": {
        "zh": "补{name}的班。学校通知上星期几的课？",
        "en": "Making up for {name}. Which weekday's timetable applies today?",
    },
    "holidayMakeupResolved": {
        "zh": "按{weekday}的课表上课",
        "en": "Following the {weekday} timetable",
    },
    "holidayMakeupNotSet": {
        "zh": "还没确认上周几的课，课时结算先按当天算",
        "en": "Not confirmed yet — lesson counts will use today's weekday",
    },
    "holidayMakeupSet": {"zh": "设置", "en": "Set"},
    "holidayShiftTitle": {
        "zh": "这天上周几的课？",
        "en": "Which weekday's timetable?",
    },
    "holidayShiftBody": {
        "zh": "以学校通知为准。选完之后，这一天的课时会按它来结算。",
        "en": "Follow your school's notice. Lesson counts for this day will use your choice.",
    },
    "holidayShiftNone": {"zh": "不调整（按当天）", "en": "No change (use the weekday itself)"},
    "holidayShiftSaved": {
        "zh": "已按{weekday}的课表结算",
        "en": "Now counting the {weekday} timetable",
    },
    "holidayShiftCleared": {"zh": "已恢复为不调整", "en": "Back to no adjustment"},
    "holidayOutsideCoverage": {
        "zh": "{year} 年的放假安排尚未收录，先按周末休息处理",
        "en": "Holiday schedule for {year} isn't bundled yet — weekends only for now",
    },
    "holidayFreeCount": {"zh": "本周放假 {count} 天", "en": "{count} days off this week"},
    "holidayMakeupCount": {"zh": "本周调休上班 {count} 天", "en": "{count} makeup workdays this week"},
    # ---- 第 13 轮：教学成果「数据概览」+ 分段卡片 ----
    "toolboxOverviewTitle": {"zh": "数据概览", "en": "Overview"},
    "toolboxTodayTitle": {"zh": "今日回顾", "en": "Today"},
    "insightWeekLessons": {"zh": "本周上课", "en": "Teaching days"},
    "insightTotalLessons": {"zh": "总课节数", "en": "Total lessons"},
    "insightFocusCount": {"zh": "专注次数", "en": "Focus sessions"},
    "insightTodayLessons": {"zh": "今天课节", "en": "Today's lessons"},
    "insightTodayNoLesson": {"zh": "今天没有课", "en": "No lessons today"},
    "insightUnitDays": {"zh": "{count} 天", "en": "{count} days"},
    "insightUnitLessons": {"zh": "{count} 节课", "en": "{count} lessons"},
    "insightUnitPeriods": {"zh": "{count} 节", "en": "{count} periods"},
    "insightUnitTimes": {"zh": "{count} 次", "en": "{count} times"},
    "insightUnitCourses": {"zh": "{count} 门课程", "en": "{count} courses"},
    "insightFocusMinutes": {
        "zh": "累计专注 {minutes} 分钟",
        "en": "{minutes} minutes in total",
    },
    "insightFocusNoRecord": {"zh": "本周还没专注过", "en": "No focus session yet"},
    "insightUnitMinutes": {"zh": "{count} 分钟", "en": "{count} min"},
    "insightUnitStudents": {"zh": "{count} 位学生", "en": "{count} students"},
    "insightUnitItems": {"zh": "{count} 项", "en": "{count} items"},
    "insightFocusTotal": {"zh": "累计专注", "en": "Total focus"},
    "insightFocusAverage": {"zh": "平均一次", "en": "Avg. per session"},
    "insightTodayEventsCount": {
        "zh": "今日事务 {count} 项",
        "en": "{count} events today",
    },
    "insightSectionLessons": {"zh": "课时分布", "en": "Lesson distribution"},
    "insightSectionAttendance": {"zh": "出勤情况", "en": "Attendance"},
    "insightSectionFocus": {"zh": "专注投入", "en": "Focus time"},
    "insightSectionEvents": {"zh": "额外事务", "en": "Extra affairs"},
    "insightSectionLessonsDesc": {"zh": "每天、每门课各多少节", "en": "Per day and per course"},
    "insightSectionAttendanceDesc": {"zh": "出勤率与最需要关注的班", "en": "Rates and the class to watch"},
    "insightSectionEventsDesc": {"zh": "日程里安排的活动", "en": "Events from your calendar"},
    "insightDoneOfTotal": {
        "zh": "已上 {done} / 共 {total} 节",
        "en": "{done} of {total} done",
    },
    "insightPerDayTitle": {"zh": "每天课节", "en": "Lessons per day"},
    "insightPerCourseTitle": {"zh": "按课程", "en": "By course"},
    "insightBestClass": {"zh": "出勤最好", "en": "Best attendance"},
    "insightWorstClass": {"zh": "最需要关注", "en": "Needs attention"},
    "insightClassRate": {
        "zh": "{rate}% · {total} 人次",
        "en": "{rate}% · {total} records",
    },
    "insightNoClassData": {
        "zh": "本周还没有点名记录",
        "en": "No roll call recorded this week",
    },
    "insightSingleClass": {
        "zh": "本周只点了一个班的名，暂无可比对象",
        "en": "Only one class had roll call this week",
    },
    "insightEventsEmpty": {"zh": "本周没有额外事务", "en": "No extra affairs this week"},
    "insightEventWithLocation": {"zh": "{title} · {location}", "en": "{title} · {location}"},
    "insightNoLessonThisWeek": {"zh": "本周还没有排课", "en": "Nothing scheduled this week"},
    # ---- 第 13 轮：日历页（月份翻页 + 当天日程标题）----
    "previousMonth": {"zh": "上一月", "en": "Previous month"},
    "nextMonth": {"zh": "下一月", "en": "Next month"},
    "yearMonth": {"zh": "{year} 年 {month} 月", "en": "{month}/{year}"},
    "eventDayTitle": {"zh": "当天日程", "en": "Events on this day"},
    "holidayAwareSwitch": {"zh": "节假日与调休", "en": "Holidays & makeup days"},
    "holidayAwareDesc": {
        "zh": "放假不计课时、调休上班日照常结算，并在调休当天提醒上周几的课",
        "en": "Skip holidays in lesson counts, count makeup workdays, and remind you which weekday's timetable applies",
    },
    # ---- 第 14 轮：节假日数据联网保鲜 ----
    # 背景：内置表只抄到"已经发过通知"的年份，跨年后就过期了。
    # 这一组文案负责把"数据从哪来、覆盖到哪年、怎么手动更新"讲清楚。
    "holidayRemoteSwitch": {
        "zh": "自动获取节假日安排",
        "en": "Fetch holiday calendars automatically",
    },
    "holidayRemoteDesc": {
        "zh": "每年自动取回新一年的放假安排；关掉也能用内置数据",
        "en": "Picks up next year's holidays automatically; built-in data still works",
    },
    "holidayDataTitle": {"zh": "节假日数据", "en": "Holiday data"},
    "holidayDataUnknown": {"zh": "暂无数据", "en": "No data yet"},
    "holidayDataSummary": {"zh": "已覆盖 {years} 年", "en": "Covers {years}"},
    "holidayDataSummaryChecked": {
        "zh": "已覆盖 {years} 年 · 上次检查 {date}",
        "en": "Covers {years} · last checked {date}",
    },
    "holidaySyncNow": {"zh": "立即更新", "en": "Update now"},
    "holidaySyncUpdated": {
        "zh": "已更新 {years} 年的放假安排",
        "en": "Updated holidays for {years}",
    },
    "holidaySyncNotPublished": {
        "zh": "{years} 年的安排还没公布，发布后会自动补齐",
        "en": "{years} isn't published yet — it will be fetched automatically",
    },
    "holidaySyncFailed": {
        "zh": "获取失败，请检查网络后重试",
        "en": "Couldn't fetch — check your connection and try again",
    },
    "holidaySyncUpToDate": {"zh": "已经是最新的了", "en": "Already up to date"},
    "holidaySyncDisabled": {
        "zh": "已关闭自动获取，请先打开上面的开关",
        "en": "Automatic fetching is off — turn it on above first",
    },
    # ---- 第 15 轮：应用内更新与分差升级 ----
    # 背景：APK 挂在 GitHub Releases 上，整包二十多兆，改几行代码也要下全量。
    # 这一组文案负责把"这次到底下多少、省了多少、走到哪一步了"讲清楚——
    # 分差升级的价值全在"少下载"，说不出来用户就感知不到。
    "updateTitle": {"zh": "检查更新", "en": "Software update"},
    "updateCurrentVersionLabel": {"zh": "当前版本", "en": "Installed version"},
    "updateVersionWithBuild": {
        "zh": "{version}（build {code}）",
        "en": "{version} (build {code})",
    },
    "updateVersionUnknown": {"zh": "无法读取版本号", "en": "Version unavailable"},
    "updateInstallBlockedTitle": {
        "zh": "需要「安装未知应用」权限",
        "en": "\"Install unknown apps\" permission needed",
    },
    "updateInstallBlockedDesc": {
        "zh": "系统要求先允许本应用安装应用，否则点安装会被直接拒绝",
        "en": "Android must allow this app to install apps, otherwise the install is rejected",
    },
    "updateGrantInstall": {"zh": "去授权", "en": "Open settings"},
    "updateRecheck": {"zh": "我已授权", "en": "I've granted it"},
    "updateUnsupported": {
        "zh": "当前平台不支持应用内更新",
        "en": "In-app updates aren't available on this platform",
    },
    "updateChecking": {"zh": "正在检查更新…", "en": "Checking for updates…"},
    "updateDownloadingPercent": {
        "zh": "正在下载… {percent}%",
        "en": "Downloading… {percent}%",
    },
    "updateFellBackToFull": {
        "zh": "分差升级没成功，已自动改用完整包",
        "en": "Delta update didn't work — switched to the full package",
    },
    "updateAssembling": {
        "zh": "正在用本机旧包合成新版本…",
        "en": "Building the new version from the installed package…",
    },
    "updateAssemblingHint": {
        "zh": "不需要重新下载整包，这一步在本机完成",
        "en": "No extra download needed — this runs on your device",
    },
    "updateInstallingHint": {
        "zh": "请在系统弹窗里确认安装",
        "en": "Confirm the install in the system dialog",
    },
    "updateInstalledHint": {
        "zh": "安装完成，重启应用后生效",
        "en": "Installed — restart the app to use it",
    },
    "updateUpToDate": {"zh": "已是最新版本", "en": "You're up to date"},
    "updateCheckAgain": {"zh": "再检查一次", "en": "Check again"},
    "updateAvailableTitle": {
        "zh": "有新版 {version}",
        "en": "Version {version} is available",
    },
    "updateDeltaBadge": {"zh": "分差升级", "en": "Delta"},
    "updateFullBadge": {"zh": "完整包", "en": "Full package"},
    "updateSizeWithDelta": {
        "zh": "只需下载 {download}（完整包 {full}）",
        "en": "Download {download} (full package is {full})",
    },
    "updateSizeFull": {"zh": "需要下载 {full}", "en": "Download {full}"},
    "updateSavedHint": {
        "zh": "比整包少下 {saved}，省下约 {percent}%",
        "en": "{saved} less than the full package — about {percent}% saved",
    },
    "updateChangesTitle": {"zh": "更新内容", "en": "What's new"},
    "updateNoChanges": {
        "zh": "这一版没有额外说明",
        "en": "No release notes for this version",
    },
    "updateDownloadDelta": {"zh": "分差升级", "en": "Update with delta"},
    "updateDownloadFull": {"zh": "下载并安装", "en": "Download & install"},
    "updateSkipVersion": {"zh": "跳过这个版本", "en": "Skip this version"},
    "updateSkipConfirmBody": {
        "zh": "跳过 {version} 之后不会再提醒这一版；出了更新的版本会重新提示",
        "en": "You won't be reminded about {version} again — a newer release will prompt you",
    },
    "updateSkippedHint": {
        "zh": "已跳过，出了更新的版本会再提醒",
        "en": "Skipped — you'll be notified about newer releases",
    },
    "updateReadyTitle": {"zh": "新版本已就绪", "en": "New version is ready"},
    "updateReadyDeltaHint": {
        "zh": "已在本机合成完成，点下面的按钮交给系统安装",
        "en": "Built on this device — hand it to the system installer",
    },
    "updateReadyFullHint": {
        "zh": "完整包已下载并校验通过，点下面的按钮安装",
        "en": "Downloaded and verified — tap to install",
    },
    "updateInstallNow": {"zh": "立即安装", "en": "Install now"},
    "updateRetry": {"zh": "重试", "en": "Retry"},
    "updateFailureNetwork": {
        "zh": "没连上服务器，检查网络后重试",
        "en": "Couldn't reach the server — check your connection",
    },
    "updateFailureManifest": {
        "zh": "版本信息暂时取不到",
        "en": "Version information is unavailable right now",
    },
    "updateFailureAssetMissing": {
        "zh": "这个版本没有适配你手机架构的安装包",
        "en": "This release has no package for your device's architecture",
    },
    "updateFailureHash": {
        "zh": "下载内容校验没通过，已放弃安装",
        "en": "The download failed verification and was discarded",
    },
    "updateFailureDelta": {
        "zh": "分差合成结果校验没通过",
        "en": "The rebuilt package failed verification",
    },
    "updateFailureNoSpace": {"zh": "存储空间不足", "en": "Not enough storage"},
    "updateFailureInstallBlocked": {
        "zh": "还没允许本应用安装应用",
        "en": "This app isn't allowed to install apps yet",
    },
    "updateFailureInstallRejected": {
        "zh": "系统拒绝了这次安装",
        "en": "The system rejected the install",
    },
    "updateFailureUnknown": {"zh": "出了点问题", "en": "Something went wrong"},
    "updateMirrorTitle": {"zh": "下载加速地址", "en": "Download mirror"},
    "updateMirrorDesc": {
        "zh": "GitHub 的下载地址在部分网络下很慢。可以填代理前缀（每行一个），直连失败后会依次尝试",
        "en": "GitHub downloads can be slow on some networks. Add proxy prefixes (one per line); they're tried after the direct URL",
    },
    "updateMirrorHint": {"zh": "https://你的代理/", "en": "https://your-proxy/"},
    "updateMirrorSaved": {
        "zh": "已保存，请重新检查更新",
        "en": "Saved — check for updates again",
    },
    "updateSettingsSubtitle": {
        "zh": "当前版本 {version}",
        "en": "Installed {version}",
    },
    "updateSettingsSubtitleAvailable": {
        "zh": "有新版本 {version}",
        "en": "Version {version} available",
    },
}

# 需要改口径的旧键（用户规格变了，文案必须跟着走，否则和界面行为对不上）
UPDATE_KEYS = {
    # 第 6 轮：选课面板从"左右滑动"改成"对话框 + 上下滑动卡片"
    "pickCourseHint": {
        "zh": "上下滑动浏览，点一下选中，再放进这一格",
        "en": "Scroll to browse, tap to pick, then place it here",
    },
    # 第 7 轮：课表页的加课 FAB 已删（加课入口在设置页），
    # 所以这里要把「课表页点空格子即可排进这一格」这个真实入口写清楚
    "courseManagementDesc": {
        "zh": "新增课程、维护教室与上课班级（课表页点空格子即可排进这一格）",
        "en": "Add courses, edit rooms and classes (tap an empty slot in the schedule to place one)",
    },
    # 第 12 轮：拍照识别已经跑通，课表设置里那一行不再是"开发中"
    "importPhotoScheduleHint": {
        "zh": "拍照或从相册选一张课表，本机识别后自动排进课表",
        "en": "Take or pick a timetable photo — it is recognized on-device",
    },
}

# 本轮不需要的键（避免留下没人用的文案）。默认状态就是"出勤"，
# 所以"全部出勤"这种批量按钮没有意义 —— 未标记的学生本来就显示为出勤，
# 老师只需要点异常的那几个。
DROP_KEYS = ["attendanceMarkAllPresent", "attendanceStatusHint",
             # 第 10 轮：工具箱去掉了「工具 / 教学成果」两个文字 Tab，改用滑动 + 圆点
             "toolboxToolsTab", "toolboxAchievementsTab"]

PLACEHOLDERS = {
    "attendanceRingRate": {
        "placeholders": {
            "present": {"type": "int"},
            "expected": {"type": "int"},
        },
    },
    "attendanceLongTermUntil": {
        "placeholders": {
            "status": {"type": "String"},
            "date": {"type": "String"},
        },
    },
    "attendanceLongTermSet": {
        "placeholders": {
            "name": {"type": "String"},
            "status": {"type": "String"},
            "date": {"type": "String"},
        },
    },
    "attendanceLongTermCleared": {"placeholders": {"name": {"type": "String"}}},
    "attendanceLongTermClearTitle": {"placeholders": {"status": {"type": "String"}}},
    "attendanceLongTermClearBody": {"placeholders": {"name": {"type": "String"}}},
    "attendanceLongTermLocked": {
        "placeholders": {
            "name": {"type": "String"},
            "status": {"type": "String"},
            "date": {"type": "String"},
        },
    },
    "rosterGroupCount": {"placeholders": {"count": {"type": "int"}}},
    "attendanceResumeBody": {"placeholders": {"name": {"type": "String"}}},
    "timelineEventTime": {
        "placeholders": {
            "start": {"type": "String"},
            "end": {"type": "String"},
        },
    },
    # ---- 第 13 轮 ----
    "holidayMakeupAsk": {"placeholders": {"name": {"type": "String"}}},
    "holidayMakeupResolved": {"placeholders": {"weekday": {"type": "String"}}},
    "holidayShiftSaved": {"placeholders": {"weekday": {"type": "String"}}},
    "holidayOutsideCoverage": {"placeholders": {"year": {"type": "int"}}},
    "holidayFreeCount": {"placeholders": {"count": {"type": "int"}}},
    "holidayMakeupCount": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitDays": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitLessons": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitPeriods": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitTimes": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitCourses": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitMinutes": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitStudents": {"placeholders": {"count": {"type": "int"}}},
    "insightUnitItems": {"placeholders": {"count": {"type": "int"}}},
    "insightTodayEventsCount": {"placeholders": {"count": {"type": "int"}}},
    "yearMonth": {
        "placeholders": {
            "year": {"type": "int"},
            "month": {"type": "int"},
        }
    },
    "insightFocusMinutes": {"placeholders": {"minutes": {"type": "int"}}},
    "insightDoneOfTotal": {
        "placeholders": {
            "done": {"type": "int"},
            "total": {"type": "int"},
        }
    },
    "insightClassRate": {
        "placeholders": {
            "rate": {"type": "int"},
            "total": {"type": "int"},
        }
    },
    "insightEventWithLocation": {
        "placeholders": {
            "title": {"type": "String"},
            "location": {"type": "String"},
        }
    },
    # ---- 第 14 轮 ----
    "holidayDataSummary": {"placeholders": {"years": {"type": "String"}}},
    "holidayDataSummaryChecked": {
        "placeholders": {
            "years": {"type": "String"},
            "date": {"type": "String"},
        }
    },
    "holidaySyncUpdated": {"placeholders": {"years": {"type": "String"}}},
    "holidaySyncNotPublished": {"placeholders": {"years": {"type": "String"}}},
    # ---- 第 15 轮：应用内更新 ----
    "updateVersionWithBuild": {
        "placeholders": {
            "version": {"type": "String"},
            "code": {"type": "int"},
        },
    },
    "updateDownloadingPercent": {"placeholders": {"percent": {"type": "int"}}},
    "updateAvailableTitle": {"placeholders": {"version": {"type": "String"}}},
    "updateSizeWithDelta": {
        "placeholders": {
            "download": {"type": "String"},
            "full": {"type": "String"},
        },
    },
    "updateSizeFull": {"placeholders": {"full": {"type": "String"}}},
    "updateSavedHint": {
        "placeholders": {
            "saved": {"type": "String"},
            "percent": {"type": "int"},
        },
    },
    "updateSkipConfirmBody": {"placeholders": {"version": {"type": "String"}}},
    "updateSettingsSubtitle": {"placeholders": {"version": {"type": "String"}}},
    "updateSettingsSubtitleAvailable": {
        "placeholders": {"version": {"type": "String"}},
    },
}


def load(path):
    with io.open(path, encoding="utf-8") as fh:
        return json.load(fh)


def dump(path, data):
    with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def main():
    for locale in ("zh", "en"):
        path = os.path.join(ROOT, "lib", "l10n", "app_%s.arb" % locale)
        data = load(path)
        for key in DROP_KEYS:
            data.pop(key, None)
        for key, values in UPDATE_KEYS.items():
            assert key in data, "%s 里没有 %s，不能凭空 create" % (locale, key)
            data[key] = values[locale]
        added = []
        for key, values in NEW_KEYS.items():
            if key in data:
                assert data[key] == values[locale], (
                    "键 %s 已存在但内容不同：%r != %r" % (key, data[key], values[locale])
                )
                continue
            data[key] = values[locale]
            added.append(key)
        for key in added:
            if key in PLACEHOLDERS:
                data["@" + key] = PLACEHOLDERS[key]
        dump(path, data)
        print(
            "%s: +%d -> %d"
            % (locale, len(added), len([k for k in data if not k.startswith("@")]))
        )

    # 键对齐校验
    zh = load(os.path.join(ROOT, "lib", "l10n", "app_zh.arb"))
    en = load(os.path.join(ROOT, "lib", "l10n", "app_en.arb"))
    zh_keys = {k for k in zh if not k.startswith("@")}
    en_keys = {k for k in en if not k.startswith("@")}
    missing_en = sorted(zh_keys - en_keys)
    missing_zh = sorted(en_keys - zh_keys)
    assert not missing_en, "en 缺少：%s" % missing_en
    assert not missing_zh, "zh 缺少：%s" % missing_zh
    print("zh/en 各 %d 个键，已对齐" % len(zh_keys))


if __name__ == "__main__":
    main()

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Schedule Planner';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get back => 'Back';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get loading => 'Loading...';

  @override
  String get noData => 'No data yet';

  @override
  String get all => 'All';

  @override
  String get searchHint => 'Search';

  @override
  String get today => 'Today';

  @override
  String get mon => 'Mon';

  @override
  String get tue => 'Tue';

  @override
  String get wed => 'Wed';

  @override
  String get thu => 'Thu';

  @override
  String get fri => 'Fri';

  @override
  String get sat => 'Sat';

  @override
  String get sun => 'Sun';

  @override
  String get tabSchedule => 'Schedule';

  @override
  String get tabAttendance => 'Attendance';

  @override
  String get tabStatistics => 'Stats';

  @override
  String get tabTodo => 'To-do';

  @override
  String get tabToolbox => 'Toolbox';

  @override
  String get scheduleTitle => 'My Schedule';

  @override
  String get scheduleAggregateView => 'Timeline';

  @override
  String get scheduleClassView => 'Class grid';

  @override
  String get selectClass => 'Select class';

  @override
  String get emptyScheduleHint => 'No lessons this week. Tap + to add one.';

  @override
  String get addLesson => 'Add lesson';

  @override
  String get editLesson => 'Edit lesson';

  @override
  String get deleteLesson => 'Delete lesson';

  @override
  String get deleteLessonConfirmBody =>
      'This lesson and all attendance records tied to it will be removed. This cannot be undone.';

  @override
  String get lessonSaved => 'Lesson saved';

  @override
  String get lessonDeleted => 'Lesson deleted';

  @override
  String get conflictMessage => 'Time conflict with another lesson';

  @override
  String get slotOccupied => 'This slot is already taken';

  @override
  String get noTemplatePeriod =>
      'The bound schedule template has no matching period';

  @override
  String get quickAddLessonHint =>
      'Pick class, then course, then weekday and period to schedule it';

  @override
  String get swapModeHint => 'Swap mode: drag a block onto another to swap';

  @override
  String get swapForbidden => 'Cannot swap across classes or templates';

  @override
  String get swapDone => 'Lessons swapped';

  @override
  String get editLessonTime => 'Adjust time';

  @override
  String get cascadeTitle => 'Apply to';

  @override
  String get cascadeOnlyThis => 'Only this period';

  @override
  String get cascadeAllFollowing => 'This and all following periods';

  @override
  String periodIndexLabel(int index) {
    return 'Period $index';
  }

  @override
  String get templateTitle => 'Schedule templates';

  @override
  String get templateNew => 'New template';

  @override
  String get templateName => 'Template name';

  @override
  String get templateNameRequired => 'Template name cannot be empty';

  @override
  String get templateSetDefault => 'Set as default';

  @override
  String get templateSetDefaultConfirm =>
      'New classes will use this template by default. Classes already bound to other templates are not affected.';

  @override
  String get templateIsDefault => 'Default';

  @override
  String templateBoundClasses(int count) {
    return '$count classes';
  }

  @override
  String get templateDelete => 'Delete template';

  @override
  String get templateDeleteBlocked => 'Cannot delete this template';

  @override
  String templateDeleteBlockedBody(String names) {
    return 'These classes are still bound to it, please migrate them first: $names';
  }

  @override
  String templateEditAffectClasses(int count) {
    return 'This change affects the displayed time of $count classes. Lesson content will not be modified.';
  }

  @override
  String get copyFromOtherDay => 'Copy from another day';

  @override
  String get copyToTargets => 'Copy to';

  @override
  String get copyDone => 'Copied';

  @override
  String get addPeriod => 'Add period';

  @override
  String get removePeriod => 'Remove period';

  @override
  String get periodType => 'Type';

  @override
  String get periodStart => 'Start';

  @override
  String get periodEnd => 'End';

  @override
  String get periodLabel => 'Label';

  @override
  String get periodTypeNormal => 'Class';

  @override
  String get periodTypeLunch => 'Lunch break';

  @override
  String get periodTypeRecess => 'Recess';

  @override
  String get periodTypeSelfStudy => 'Self study';

  @override
  String get periodTypeOther => 'Other';

  @override
  String get periodErrorInvalidFormat => 'Time must use HH:mm';

  @override
  String get periodErrorEndBeforeStart =>
      'End time must be later than start time';

  @override
  String get periodErrorOverlap => 'Overlaps another period';

  @override
  String get periodErrorNotAscending =>
      'Start time must increase with period index';

  @override
  String get templateSaved => 'Template saved';

  @override
  String get attendanceTitle => 'Attendance';

  @override
  String get calendarMonth => 'Month';

  @override
  String get calendarWeek => 'Week';

  @override
  String get courseChipToday => 'Today\'s classes';

  @override
  String get courseChipOther => 'Other classes';

  @override
  String get studentList => 'Students';

  @override
  String get sortByName => 'By name (pinyin)';

  @override
  String get sortByNo => 'By student No.';

  @override
  String get sortByStatus => 'By status';

  @override
  String get statusPresent => 'Present';

  @override
  String get statusLate => 'Late';

  @override
  String get statusEarlyLeave => 'Left early';

  @override
  String get statusAbsent => 'Absent';

  @override
  String get statusLeave => 'On leave';

  @override
  String get statusUnmarked => 'Unmarked';

  @override
  String get rollCall => 'Random picker';

  @override
  String get rollCallTitle => 'Rolling...';

  @override
  String get copySummary => 'Copy summary';

  @override
  String get copiedToClipboard => 'Summary copied to clipboard';

  @override
  String get highRisk => 'High risk';

  @override
  String riskScoreLabel(int score) {
    return 'Risk score $score';
  }

  @override
  String get tagTitle => 'Performance tags';

  @override
  String get starRating => 'Stars';

  @override
  String get remark => 'Remark';

  @override
  String get noStudentsHint => 'No students in this class yet';

  @override
  String get attendanceSaved => 'Attendance saved';

  @override
  String get tagActiveSpeaking => 'Active in class';

  @override
  String get tagHomeworkOnTime => 'Homework on time';

  @override
  String get tagFocusedListening => 'Focused listening';

  @override
  String get tagHelpingOthers => 'Helps others';

  @override
  String get tagGoodQuestion => 'Good questions';

  @override
  String get tagNeatHandwriting => 'Neat handwriting';

  @override
  String get tagTeamLeader => 'Team leader';

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get granularityDay => 'By day';

  @override
  String get granularityWeek => 'By week';

  @override
  String get granularityMonth => 'By month';

  @override
  String get attendanceRateChart => 'Attendance rate';

  @override
  String get courseRateChart => 'Rate by course';

  @override
  String get abnormalList => 'Abnormal records';

  @override
  String get riskRanking => 'High-risk ranking';

  @override
  String get emotionCard => 'Encouragement';

  @override
  String get exportExcel => 'Export Excel';

  @override
  String get exportSuccess => 'Workbook generated';

  @override
  String get filterByStatus => 'Filter by status';

  @override
  String get attendanceRateLabel => 'Attendance rate';

  @override
  String get emotionExcellent => 'This class is doing amazingly well!';

  @override
  String get emotionGood => 'Solid attendance, keep it up!';

  @override
  String get emotionNormal => 'Every step forward counts.';

  @override
  String get emotionEncourage => 'New week, new chances to shine.';

  @override
  String get todoTitle => 'To-do';

  @override
  String get todoSmart => 'Smart';

  @override
  String get todoGeneral => 'Personal';

  @override
  String get todoAdd => 'Add to-do';

  @override
  String get todoTitleRequired => 'Title cannot be empty';

  @override
  String get todoDescription => 'Description (optional)';

  @override
  String get todoPriority => 'Priority';

  @override
  String get priorityHigh => 'High';

  @override
  String get priorityMedium => 'Medium';

  @override
  String get priorityLow => 'Low';

  @override
  String get todoDueDate => 'Due date (optional)';

  @override
  String get todoAutoCompleted => 'Completed automatically';

  @override
  String get todoDeleteConfirmBody => 'This to-do will be deleted permanently.';

  @override
  String get emptyTodo => 'Nothing to do right now';

  @override
  String todoCompletedSection(int count) {
    return 'Completed ($count)';
  }

  @override
  String get toolboxTitle => 'Toolbox';

  @override
  String get focusTimer => 'Focus timer';

  @override
  String get focusStart => 'Start';

  @override
  String get focusPause => 'Pause';

  @override
  String get focusResume => 'Resume';

  @override
  String get focusReset => 'Reset';

  @override
  String get focusBreak => 'Break';

  @override
  String get focusDone => 'Focus session complete';

  @override
  String get noteTitle => 'Quick notes';

  @override
  String get noteEditor => 'Note';

  @override
  String get noteEmpty => 'Start writing...';

  @override
  String get aiExpand => 'Expand';

  @override
  String get aiPolish => 'Polish';

  @override
  String get aiSummarize => 'Summarize';

  @override
  String get aiApply => 'Apply result';

  @override
  String get aiDiscard => 'Discard';

  @override
  String get aiDiffTitle => 'Review AI result';

  @override
  String get aiOriginal => 'Original';

  @override
  String get aiResult => 'Result';

  @override
  String get aiNoProvider => 'No LLM provider configured';

  @override
  String get aiSelectTextFirst => 'Select a piece of text first';

  @override
  String get scheduleCalendar => 'Calendar';

  @override
  String get eventAdd => 'Add event';

  @override
  String get eventTitle => 'Title';

  @override
  String get eventLocation => 'Location (optional)';

  @override
  String get eventReminder => 'Reminder';

  @override
  String get eventReminderBefore => 'Minutes before';

  @override
  String get generalTodoTitle => 'Personal to-do list';

  @override
  String get llmProviders => 'LLM providers';

  @override
  String get llmProviderName => 'Name';

  @override
  String get llmBaseUrl => 'API base URL';

  @override
  String get llmApiKey => 'API key';

  @override
  String get llmModelName => 'Model name';

  @override
  String get llmSetDefault => 'Use by default';

  @override
  String get manageTitle => 'Management';

  @override
  String get manageClasses => 'Classes';

  @override
  String get manageCourses => 'Courses';

  @override
  String get manageStudents => 'Students';

  @override
  String get className => 'Class name';

  @override
  String get gradeName => 'Grade';

  @override
  String get headTeacher => 'Head teacher';

  @override
  String studentCountLabel(int count) {
    return '$count students';
  }

  @override
  String get classColor => 'Color';

  @override
  String get templateBinding => 'Schedule template';

  @override
  String get studentName => 'Name';

  @override
  String get studentNo => 'Student No.';

  @override
  String get importExcel => 'Import from Excel';

  @override
  String get importPreview => 'Import preview';

  @override
  String importResult(int success, int fail, int skip) {
    return 'Success $success, failed $fail, skipped $skip';
  }

  @override
  String get importReasonMissingName => 'Name is empty';

  @override
  String get importReasonClassNotFound => 'No matching class';

  @override
  String get importReasonDuplicate => 'Already exists';

  @override
  String get importDone => 'Import finished';

  @override
  String get dragToReorderHint => 'Long-press and drag to reorder';

  @override
  String get batchUpdateTemplate => 'Batch update template';

  @override
  String batchUpdateTemplateConfirm(String names) {
    return 'The following classes will be updated: $names';
  }

  @override
  String get classDeleteConfirmBody =>
      'Deleting this class also removes its courses, lessons, students and attendance records.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get theme => 'Theme';

  @override
  String get themeMint => 'Fresh mint';

  @override
  String get themeMinimalGray => 'Minimal gray';

  @override
  String get themeNightCare => 'Night care';

  @override
  String get riskThreshold => 'High-risk absence threshold';

  @override
  String get attendanceWarnThreshold => 'Attendance warning threshold (%)';

  @override
  String get retentionDays => 'Keep attendance for (days)';

  @override
  String get retentionImportLogDays => 'Keep import logs for (days)';

  @override
  String get cascadeSwitch => 'Cascade time updates';

  @override
  String get defaultAttendanceStatus => 'Default status for unrecorded days';

  @override
  String get notificationPermission => 'Notification permission';

  @override
  String get notificationCheck => 'Check permission';

  @override
  String get notificationOpenSettings => 'Open system settings';

  @override
  String get notificationGranted => 'Notifications are enabled';

  @override
  String get notificationDenied => 'Notifications are disabled';

  @override
  String get lessonReminder => 'Pre-class reminder';

  @override
  String get reminderMinutesBefore => 'Remind minutes before';

  @override
  String get reminderRegenerate => 'Rebuild reminders now';

  @override
  String reminderRegenerated(int count) {
    return '$count reminders rebuilt from current templates';
  }

  @override
  String get cleanupNow => 'Clean up expired data';

  @override
  String cleanupResult(int attendance, int logs) {
    return 'Cleaned attendance $attendance, import logs $logs';
  }

  @override
  String get cleanupAborted => 'Backup failed, cleanup cancelled';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get clearAllData => 'Clear all data';

  @override
  String get clearAllDataConfirm =>
      'All classes, courses, lessons, students, attendance and to-dos will be erased permanently.';

  @override
  String get aboutTitle => 'About';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String autoTodoTitle(String className) {
    return 'Check absences for $className this week';
  }

  @override
  String get colRow => 'Row';

  @override
  String get colName => 'Name';

  @override
  String get colNo => 'No.';

  @override
  String get colClass => 'Class';

  @override
  String get colStatus => 'Status';

  @override
  String get classFormTitle => 'Class';

  @override
  String get courseFormTitle => 'Course';

  @override
  String get studentFormTitle => 'Student';

  @override
  String get eventFormTitle => 'Event';

  @override
  String get addClass => 'Add class';

  @override
  String get addCourse => 'Add course';

  @override
  String get addStudent => 'Add student';

  @override
  String get addEvent => 'Add event';

  @override
  String get addNote => 'Add note';

  @override
  String get deleteNote => 'Delete note';

  @override
  String get deleteEvent => 'Delete event';

  @override
  String get deleteStudent => 'Delete student';

  @override
  String get deleteCourse => 'Delete course';

  @override
  String get deleteClass => 'Delete class';

  @override
  String get pickColor => 'Pick color';

  @override
  String get importChooseFile => 'Choose Excel file';

  @override
  String get noteSaved => 'Note saved';

  @override
  String get classSaved => 'Class saved';

  @override
  String get courseSaved => 'Course saved';

  @override
  String get studentSaved => 'Student saved';

  @override
  String get eventSaved => 'Event saved';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get timePickerTitle => 'Pick time';

  @override
  String get hour => 'Hour';

  @override
  String get minute => 'Minute';

  @override
  String get requiredField => 'This field is required';

  @override
  String operationFailed(String message) {
    return 'Operation failed: $message';
  }

  @override
  String get unexpectedError => 'Unexpected error, please retry';

  @override
  String get tabSettings => 'Settings';

  @override
  String get scheduleModeTraditional => 'Class grid';

  @override
  String get scheduleModeStaggered => 'Teacher timeline';

  @override
  String get scheduleModeSwitch => 'Switch schedule view';

  @override
  String get scheduleSettings => 'Schedule settings';

  @override
  String get gridPeriodHeader => 'Period';

  @override
  String get gridTimeHeader => 'Time';

  @override
  String get todayLabel => 'Today';

  @override
  String get quickGenerateTitle => 'Generate periods';

  @override
  String get quickGenerateDesc =>
      'Batch-generate periods from start time, lesson length, break and count';

  @override
  String get generateStartTime => 'Start time';

  @override
  String get generateLessonMinutes => 'Lesson length (min)';

  @override
  String get generateBreakMinutes => 'Break length (min)';

  @override
  String get generatePeriodCount => 'Periods per day';

  @override
  String get generateWeekdays => 'Apply to';

  @override
  String get generatePreview => 'Preview';

  @override
  String generateDone(int count) {
    return 'Generated $count periods';
  }

  @override
  String generatePreviewRow(int index, String start, String end) {
    return 'Period $index　$start-$end';
  }

  @override
  String get generateInvalidRange =>
      'Range exceeds one day. Reduce periods or length.';

  @override
  String get generateEmptyWeekdays => 'Pick at least one weekday';

  @override
  String get editPeriodTime => 'Edit period time';

  @override
  String get editPeriodTimeDesc =>
      'Edit this period, with optional shift of the following ones';

  @override
  String get cascadeFollowing => 'Shift following periods';

  @override
  String get periodTimeUpdated => 'Period time updated';

  @override
  String cascadeApplied(int count) {
    return 'Shifted $count periods';
  }

  @override
  String get defaultTemplateEdit => 'Edit default periods';

  @override
  String get defaultTemplateHint => 'Used by default for new classes';

  @override
  String get clearSchedule => 'Clear schedule';

  @override
  String get clearScheduleConfirm =>
      'Clears the lessons of every class on this template. Period times are kept. This cannot be undone.';

  @override
  String get clearScheduleDone => 'Schedule cleared';

  @override
  String get importPhotoSchedule => 'Import from photo';

  @override
  String get importPhotoScheduleHint =>
      'Take or pick a timetable photo — it is recognized on-device';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get toolboxAllTools => 'All tools';

  @override
  String get toolStatistics => 'Statistics';

  @override
  String get toolTodo => 'Smart todos';

  @override
  String get toolFocus => 'Focus';

  @override
  String get toolNote => 'Notes';

  @override
  String get toolCalendar => 'Calendar';

  @override
  String get toolPrivateTodo => 'Checklist';

  @override
  String get toolboxInsight => 'This week';

  @override
  String get insightDoneLessons => 'Lessons done';

  @override
  String get insightLeftLessons => 'Remaining';

  @override
  String get insightAttention => 'Needs attention';

  @override
  String get insightNoAttention => 'All good, keep it up';

  @override
  String get insightAttendanceRate => 'Attendance rate';

  @override
  String insightCheer(int done) {
    return '$done lessons done this week. Nice work.';
  }

  @override
  String insightStudentRisk(String name, int count) {
    return '$name was absent $count times this week';
  }

  @override
  String pageIndicator(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String weekRange(String start, String end) {
    return '$start ~ $end';
  }

  @override
  String get groupScheduleData => 'Schedule & roster';

  @override
  String get groupPermission => 'Permissions';

  @override
  String get groupDisplay => 'Display & language';

  @override
  String get groupAssistant => 'Smart features';

  @override
  String get groupData => 'Data';

  @override
  String get groupAbout => 'About';

  @override
  String get groupTeaching => 'Teaching';

  @override
  String get studentRoster => 'Student roster';

  @override
  String get studentRosterDesc =>
      'Add, edit, delete, or bulk import from Excel';

  @override
  String get classManagement => 'Classes';

  @override
  String get classManagementDesc =>
      'Classes and counts are created from imports';

  @override
  String get courseManagement => 'Courses';

  @override
  String get courseManagementDesc =>
      'Add courses, edit rooms and classes (tap an empty slot in the schedule to place one)';

  @override
  String get statisticsSettings => 'Statistics settings';

  @override
  String get statisticsSettingsDesc => 'Risk and warning thresholds';

  @override
  String get studentGender => 'Gender';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderUnset => 'Not set';

  @override
  String get studentNoOptional => 'Student no. (optional)';

  @override
  String get studentNameRequired => 'Name (required)';

  @override
  String get studentClassRequired => 'Class (required)';

  @override
  String get studentFormDesc =>
      'Name and class are required; gender and student no. are optional';

  @override
  String get courseNameLabel => 'Course name';

  @override
  String get courseRoomLabel => 'Room';

  @override
  String get courseClassLabel => 'Classes';

  @override
  String get courseCountLabel => 'Students';

  @override
  String get courseRemarkLabel => 'Note';

  @override
  String get courseMultiClassHint =>
      'Multiple classes allowed (combined class)';

  @override
  String get courseClassRequired => 'Pick at least one class';

  @override
  String get courseAutoCountHint => 'Counted from the selected classes';

  @override
  String get courseClearAll => 'Clear all courses';

  @override
  String get courseClearAllConfirm =>
      'This deletes every course and its lessons. It cannot be undone.';

  @override
  String get courseCleared => 'Courses cleared';

  @override
  String get importStudents => 'Bulk import students from Excel';

  @override
  String get importFormatTitle => 'File format';

  @override
  String get importFormatLine1 => 'Only .xlsx files';

  @override
  String get importFormatLine2 => '\"姓名\" and \"班级\" columns are required';

  @override
  String get importFormatLine3 => '\"学号\" and \"性别\" are optional';

  @override
  String get importFormatLine4 => 'Unknown classes are created automatically';

  @override
  String get importFormatExample => 'Example';

  @override
  String importAutoCreated(int count) {
    return 'Created $count classes';
  }

  @override
  String importRowsTotal(int count) {
    return 'Parsed $count rows';
  }

  @override
  String get importNeedNameOrClass => 'Both \"姓名\" and \"班级\" must be filled';

  @override
  String get importOverall => 'Import summary';

  @override
  String get importClassColumn => 'Class';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutChangelog => 'What\'s new';

  @override
  String get aboutChangelogBody =>
      '1.0.0 first release: schedule, attendance, statistics, todos and toolbox, with six themes and bilingual UI.';

  @override
  String get aboutDeveloper => 'Developer';

  @override
  String get aboutDeveloperName => 'Teaching Assistant Team';

  @override
  String get aboutTechStack => 'Tech stack';

  @override
  String get aboutAppName => 'Schedule Plan';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get attendanceWeekDefault => 'Week view';

  @override
  String get attendanceMonthView => 'Month view';

  @override
  String get attendanceNoLesson => 'No lessons today';

  @override
  String attendanceCountSummary(int total, int present) {
    return '$total total · $present present';
  }

  @override
  String get markAll => 'Mark all';

  @override
  String get statsRiskThresholdDesc =>
      'Flag as high risk when weekly absences reach this number';

  @override
  String get statsWarnThresholdDesc =>
      'Highlight in charts when attendance drops below this rate';

  @override
  String get statsColumnName => 'Name';

  @override
  String get statsColumnNo => 'Student no.';

  @override
  String get statsColumnStatus => 'Status';

  @override
  String get toolStatisticsDesc => 'Attendance trends and ranking';

  @override
  String get toolTodoDesc => 'Auto-generated from attendance';

  @override
  String get toolFocusDesc => 'Pomodoro focus timer';

  @override
  String get toolNoteDesc => 'Quick notes with AI expansion';

  @override
  String get toolCalendarDesc => 'Events and reminders';

  @override
  String get toolPrivateTodoDesc => 'Your private checklist';

  @override
  String get importReasonMissingClass => 'Missing class';

  @override
  String get noStudentNo => 'No student no.';

  @override
  String get unitTimes => ' times';

  @override
  String get unitDays => ' d';

  @override
  String get unitMinutes => ' min';

  @override
  String get unitPercent => '%';

  @override
  String get settingsSubtitle => 'Schedule, roster, permissions and display';

  @override
  String get themeSunrise => 'Sunrise';

  @override
  String get themeOceanBlue => 'Ocean';

  @override
  String get themeSakura => 'Sakura';

  @override
  String get scheduleCleared => 'Schedule cleared';

  @override
  String get periodTimeSaved => 'Period time updated';

  @override
  String get switchTemplate => 'Switch schedule';

  @override
  String scheduleGenerated(int count) {
    return 'Generated a schedule of $count periods';
  }

  @override
  String get studentNameShort => 'Name';

  @override
  String get studentNoShort => 'No.';

  @override
  String get attendanceColumn => 'Status';

  @override
  String calendarMonthTitle(int year, int month) {
    return '$month/$year';
  }

  @override
  String calendarWeekTitle(String start, String end) {
    return '$start - $end';
  }

  @override
  String get importFileUnreadable =>
      'This file cannot be read. Make sure it is an unencrypted .xlsx file, or open it in Excel/WPS and save it as .xlsx, then try again.';

  @override
  String get scheduleNoClassHint =>
      'No class yet - showing the default bell schedule';

  @override
  String get cellNoCourseTitle => 'No course in this slot';

  @override
  String get cellNoCourseBody =>
      'Create a course in course management first, then tap this slot again and swipe to place it.';

  @override
  String get cellNeedsClassBody =>
      'You have no class yet. Create a class and import its roster before scheduling.';

  @override
  String get goAddCourse => 'Add course';

  @override
  String get goCreateClass => 'Create class';

  @override
  String get pickCourseTitle => 'Pick a course for this slot';

  @override
  String get pickCourseHint =>
      'Scroll to browse, tap to pick, then place it here';

  @override
  String get placeHere => 'Place here';

  @override
  String get noCourseYet => 'No course yet';

  @override
  String get lessonDetailTitle => 'Course details';

  @override
  String get goRollCall => 'Take attendance';

  @override
  String get changeLessonCourse => 'Change course';

  @override
  String get removeFromSchedule => 'Remove from schedule';

  @override
  String get removedFromSchedule => 'Removed from schedule';

  @override
  String get placedToSchedule => 'Added to schedule';

  @override
  String cellStudentCount(int count) {
    return '$count';
  }

  @override
  String get classHeadTeacherFromClass => 'Head teacher (from the class)';

  @override
  String classDeleteConfirmWithStudents(int count) {
    return 'This class still has $count students. Deleting it also removes them, the courses, the schedule and all attendance records. This cannot be undone.';
  }

  @override
  String get classCreatedNextStep =>
      'Class created - add the student roster for it';

  @override
  String get goAddStudents => 'Add students';

  @override
  String attendanceLocatedTo(String date) {
    return 'Opened $date';
  }

  @override
  String get dialAmLabel => 'AM';

  @override
  String get dialPmLabel => 'PM';

  @override
  String get dialTwoRingHint =>
      'Inner ring sets the hour, outer ring sets the minute';

  @override
  String periodDurationMinutes(int count) {
    return 'Period length $count min';
  }

  @override
  String get periodAutoEndHint =>
      'End time is auto-calculated from the period length';

  @override
  String get periodCustomEnd => 'Custom end time';

  @override
  String get periodAutoEndBadge => 'Auto';

  @override
  String get classInfoTitle => 'Class info';

  @override
  String get classStatStudents => 'Students';

  @override
  String get classStatMale => 'Boys';

  @override
  String get classStatFemale => 'Girls';

  @override
  String get classStatUnset => 'Unset';

  @override
  String get classDetailStudents => 'Students in this class';

  @override
  String get classDetailStudentsDesc =>
      'Tap a student to edit; use the icon to delete';

  @override
  String get classDetailNoStudents => 'No students yet - tap + to add';

  @override
  String get classDetailCourses => 'Courses of this class';

  @override
  String get classDetailCoursesDesc =>
      'Maintain course names, rooms and classes';

  @override
  String get classDetailTapHint => 'Tap to open class details';

  @override
  String get deleteStudentConfirmBody =>
      'Deleting also removes this student\'s attendance records. This cannot be undone.';

  @override
  String rosterSummary(int students, int classes) {
    return '$students students · $classes classes';
  }

  @override
  String get rosterEmptyGuide => 'No students yet - import a roster from Excel';

  @override
  String get goImportRoster => 'Import roster';

  @override
  String get coursePickClassTitle => 'Select classes';

  @override
  String get coursePickClassHint =>
      'Multi-select (combined classes allowed); the headcount is summed automatically';

  @override
  String get pickClass => 'Select classes';

  @override
  String get teacherUnset => 'Not set';

  @override
  String get periodRestoreAuto => 'Reset to auto';

  @override
  String get classDetailTitle => 'Class details';

  @override
  String get importAutoHint => 'Imported automatically, no extra confirmation';

  @override
  String get importGoRoster => 'Open roster';

  @override
  String importDetailToggle(int count) {
    return 'View import details ($count rows)';
  }

  @override
  String get importDetailHide => 'Hide import details';

  @override
  String get courseColorLabel => 'Course color';

  @override
  String get courseColorAuto => 'Use class color';

  @override
  String get courseColorHint =>
      'Pick a color; schedule cells use it for this course';

  @override
  String get generateReplacesHint =>
      'This selection is authoritative; unselected weekdays are cleared';

  @override
  String get importEmptyFile =>
      'No student rows found — check that the name and class columns have content';

  @override
  String get moreActions => 'More actions';

  @override
  String get statusShortPresent => 'P';

  @override
  String get statusShortLate => 'L';

  @override
  String get statusShortEarlyLeave => 'EL';

  @override
  String get statusShortAbsent => 'A';

  @override
  String get statusShortLeave => 'Lv';

  @override
  String get statusShortUnmarked => '—';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get statusExempt => 'Exempt';

  @override
  String get statusShortSuspended => 'Sus';

  @override
  String get statusShortExempt => 'Ex';

  @override
  String attendanceLongTermUntil(String status, String date) {
    return '$status · until $date';
  }

  @override
  String attendanceLongTermSet(String name, String status, String date) {
    return '$name marked $status until $date';
  }

  @override
  String attendanceLongTermCleared(String name) {
    return '$name is back to normal roll call';
  }

  @override
  String attendanceLongTermClearTitle(String status) {
    return 'Cancel $status?';
  }

  @override
  String attendanceLongTermClearBody(String name) {
    return '$name returns to normal roll call and must be marked lesson by lesson.';
  }

  @override
  String attendanceLongTermLocked(String name, String status, String date) {
    return '$name · $status until $date — no per-lesson marking needed';
  }

  @override
  String rosterGroupCount(int count) {
    return '$count students';
  }

  @override
  String get shareSchedule => 'Share schedule';

  @override
  String get shareSavedToGallery => 'Saved to gallery';

  @override
  String get shareGalleryPermissionDenied =>
      'Allow photos & videos access to save to the gallery';

  @override
  String get shareOpenSettings => 'Settings';

  @override
  String get shareCaptureFailed => 'Couldn\'t capture, try again';

  @override
  String get shareQrPlaceholder => 'QR code';

  @override
  String get copyAction => 'Copy';

  @override
  String get summaryNoAbnormal => 'All present, nothing abnormal';

  @override
  String get courseFilterLabel => 'Filter by course';

  @override
  String get eventRecurrence => 'Repeats';

  @override
  String get eventRecurrenceOnce => 'Once';

  @override
  String get eventRecurrenceWeekly => 'Weekly';

  @override
  String get eventRecurrenceBiweekly => 'Biweekly';

  @override
  String get eventRecurrenceMonthly => 'Monthly';

  @override
  String get insightBenefitedStudents => 'Students reached';

  @override
  String get toolboxSwipeHint => 'Swipe · 2 pages';

  @override
  String get ocrTitle => 'Scan schedule photo';

  @override
  String get ocrEntryTitle => 'Schedule from photo';

  @override
  String get ocrEntryDesc =>
      'Snap a timetable, recognize it on-device, build the schedule';

  @override
  String get ocrPickPhoto => 'Choose a photo';

  @override
  String get ocrPickPhotoHint =>
      'Shoot the whole timetable flat and straight. Headers like \"Mon…Fri\" and \"period N\" help a lot';

  @override
  String get ocrFromCamera => 'Camera';

  @override
  String get ocrFromGallery => 'From gallery';

  @override
  String get ocrRecognizing => 'Recognizing…';

  @override
  String get ocrRecognizingHint =>
      'Runs entirely on this device — nothing is uploaded';

  @override
  String get ocrCropTitle => 'Frame the timetable';

  @override
  String get ocrCropHint =>
      'Frame just the table — drop the title and margins for better accuracy';

  @override
  String get ocrCropReset => 'Reset frame';

  @override
  String get ocrCropConfirm => 'Recognize this area';

  @override
  String get ocrResultTitle => 'Recognition result';

  @override
  String ocrResultSummary(Object courses, Object days, Object lessons) {
    return '$lessons lessons · $courses courses · $days days';
  }

  @override
  String get ocrConfidenceHigh => 'Looks good — review and import';

  @override
  String get ocrConfidenceMedium =>
      'So-so result — check each row before importing';

  @override
  String get ocrConfidenceLow =>
      'The photo is unclear — retake it or fix the rows by hand';

  @override
  String get ocrImport => 'Import';

  @override
  String ocrImportDone(Object courses, Object lessons) {
    return 'Imported $lessons lessons, $courses new courses';
  }

  @override
  String get ocrRecapture => 'Retake';

  @override
  String get ocrEditRow => 'Tap to edit the course name';

  @override
  String get ocrRowEditTitle => 'Edit course name';

  @override
  String get ocrNoPhoto => 'No photo selected';

  @override
  String get ocrNoPhotoPermission =>
      'Photo access is needed to read the timetable image';

  @override
  String get ocrEngineUnavailable =>
      'No on-device text recognition engine available — use Excel import instead';

  @override
  String get ocrEngineUnavailableTitle => 'Engine unavailable';

  @override
  String get ocrEngineUnavailableBody =>
      'Recognition runs fully on-device (offline ML Kit). No network, no upload. This device can\'t provide it — usually an old OS or missing Google services. Use Excel import or place lessons by hand for now.';

  @override
  String get ocrWarnNoWeekday =>
      'No weekday header found — make sure the whole table is in frame';

  @override
  String get ocrWarnPartialWeekday =>
      'Only some weekday columns were found — a few days may be missing';

  @override
  String get ocrWarnNoPeriod =>
      'No period header found — retake or fix it by hand';

  @override
  String get ocrWarnNoLesson =>
      'No lessons recognized — try another angle or a sharper shot';

  @override
  String get ocrManualAdd => 'Add a lesson by hand';

  @override
  String get ocrAllWeekdays => 'All';

  @override
  String get ocrNoGoogleServices =>
      'Google services missing — recognition unavailable';

  @override
  String get ocrSettingsHint =>
      'Snap the timetable, recognize it on-device, place it here';

  @override
  String get ocrDeviceTitle => 'Device support';

  @override
  String get ocrDeviceAndroid =>
      'Android (Xiaomi / OPPO / vivo and friends): ready to use. Recognition uses the device\'s offline text engine — ML Kit when Google services are present, with a system fallback otherwise. No network at any point.';

  @override
  String get ocrDeviceHarmony =>
      'Huawei (HarmonyOS): not supported yet — HarmonyOS exposes none of the engines above. A dedicated version is planned; use Excel import or place lessons by hand for now.';

  @override
  String get ocrDeviceIos =>
      'iOS: the hook is reserved on top of Apple Vision and will be enabled together with the iOS build.';

  @override
  String get timelineEventLegend => 'Event';

  @override
  String timelineEventTime(String start, String end) {
    return '$start - $end';
  }

  @override
  String get timelineEventTapHint => 'tap for time';

  @override
  String get holidayKindHoliday => 'Off';

  @override
  String get holidayKindMakeup => 'On';

  @override
  String get holidayLegend => 'Red = holiday · amber = makeup workday';

  @override
  String get holidayNameNewYear => 'New Year\'s Day';

  @override
  String get holidayNameSpringFestival => 'Spring Festival';

  @override
  String get holidayNameQingming => 'Qingming Festival';

  @override
  String get holidayNameLabourDay => 'Labour Day';

  @override
  String get holidayNameDragonBoat => 'Dragon Boat Festival';

  @override
  String get holidayNameMidAutumn => 'Mid-Autumn Festival';

  @override
  String get holidayNameNationalDay => 'National Day';

  @override
  String get holidayNameNationalDayMidAutumn =>
      'National Day & Mid-Autumn Festival';

  @override
  String get holidayMakeupTitle => 'Makeup workday today';

  @override
  String holidayMakeupAsk(String name) {
    return 'Making up for $name. Which weekday\'s timetable applies today?';
  }

  @override
  String holidayMakeupResolved(String weekday) {
    return 'Following the $weekday timetable';
  }

  @override
  String get holidayMakeupNotSet =>
      'Not confirmed yet — lesson counts will use today\'s weekday';

  @override
  String get holidayMakeupSet => 'Set';

  @override
  String get holidayShiftTitle => 'Which weekday\'s timetable?';

  @override
  String get holidayShiftBody =>
      'Follow your school\'s notice. Lesson counts for this day will use your choice.';

  @override
  String get holidayShiftNone => 'No change (use the weekday itself)';

  @override
  String holidayShiftSaved(String weekday) {
    return 'Now counting the $weekday timetable';
  }

  @override
  String get holidayShiftCleared => 'Back to no adjustment';

  @override
  String holidayOutsideCoverage(int year) {
    return 'Holiday schedule for $year isn\'t bundled yet — weekends only for now';
  }

  @override
  String holidayFreeCount(int count) {
    return '$count days off this week';
  }

  @override
  String holidayMakeupCount(int count) {
    return '$count makeup workdays this week';
  }

  @override
  String get toolboxOverviewTitle => 'Overview';

  @override
  String get toolboxTodayTitle => 'Today';

  @override
  String get insightWeekLessons => 'Teaching days';

  @override
  String get insightTotalLessons => 'Total lessons';

  @override
  String get insightFocusCount => 'Focus sessions';

  @override
  String get insightTodayLessons => 'Today\'s lessons';

  @override
  String get insightTodayNoLesson => 'No lessons today';

  @override
  String insightUnitDays(int count) {
    return '$count days';
  }

  @override
  String insightUnitLessons(int count) {
    return '$count lessons';
  }

  @override
  String insightUnitPeriods(int count) {
    return '$count periods';
  }

  @override
  String insightUnitTimes(int count) {
    return '$count times';
  }

  @override
  String insightUnitCourses(int count) {
    return '$count courses';
  }

  @override
  String insightFocusMinutes(int minutes) {
    return '$minutes minutes in total';
  }

  @override
  String get insightFocusNoRecord => 'No focus session yet';

  @override
  String get insightSectionLessons => 'Lesson distribution';

  @override
  String get insightSectionAttendance => 'Attendance';

  @override
  String get insightSectionFocus => 'Focus time';

  @override
  String get insightSectionEvents => 'Extra affairs';

  @override
  String get insightSectionLessonsDesc => 'Per day and per course';

  @override
  String get insightSectionAttendanceDesc => 'Rates and the class to watch';

  @override
  String get insightSectionEventsDesc => 'Events from your calendar';

  @override
  String insightDoneOfTotal(int done, int total) {
    return '$done of $total done';
  }

  @override
  String get insightPerDayTitle => 'Lessons per day';

  @override
  String get insightPerCourseTitle => 'By course';

  @override
  String get insightBestClass => 'Best attendance';

  @override
  String get insightWorstClass => 'Needs attention';

  @override
  String insightClassRate(int rate, int total) {
    return '$rate% · $total records';
  }

  @override
  String get insightNoClassData => 'No roll call recorded this week';

  @override
  String get insightSingleClass => 'Only one class had roll call this week';

  @override
  String get insightEventsEmpty => 'No extra affairs this week';

  @override
  String insightEventWithLocation(String title, String location) {
    return '$title · $location';
  }

  @override
  String get insightNoLessonThisWeek => 'Nothing scheduled this week';

  @override
  String insightUnitMinutes(int count) {
    return '$count min';
  }

  @override
  String insightUnitStudents(int count) {
    return '$count students';
  }

  @override
  String get insightFocusTotal => 'Total focus';

  @override
  String get insightFocusAverage => 'Avg. per session';

  @override
  String insightTodayEventsCount(int count) {
    return '$count events today';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String yearMonth(int year, int month) {
    return '$month/$year';
  }

  @override
  String get eventDayTitle => 'Events on this day';

  @override
  String get holidayAwareSwitch => 'Holidays & makeup days';

  @override
  String get holidayAwareDesc =>
      'Skip holidays in lesson counts, count makeup workdays, and remind you which weekday\'s timetable applies';

  @override
  String insightUnitItems(int count) {
    return '$count items';
  }

  @override
  String get holidayRemoteSwitch => 'Fetch holiday calendars automatically';

  @override
  String get holidayRemoteDesc =>
      'Picks up next year\'s holidays automatically; built-in data still works';

  @override
  String get holidayDataTitle => 'Holiday data';

  @override
  String get holidayDataUnknown => 'No data yet';

  @override
  String holidayDataSummary(String years) {
    return 'Covers $years';
  }

  @override
  String holidayDataSummaryChecked(String years, String date) {
    return 'Covers $years · last checked $date';
  }

  @override
  String get holidaySyncNow => 'Update now';

  @override
  String holidaySyncUpdated(String years) {
    return 'Updated holidays for $years';
  }

  @override
  String holidaySyncNotPublished(String years) {
    return '$years isn\'t published yet — it will be fetched automatically';
  }

  @override
  String get holidaySyncFailed =>
      'Couldn\'t fetch — check your connection and try again';

  @override
  String get holidaySyncUpToDate => 'Already up to date';

  @override
  String get holidaySyncDisabled =>
      'Automatic fetching is off — turn it on above first';

  @override
  String get updateTitle => 'Software update';

  @override
  String get updateCurrentVersionLabel => 'Installed version';

  @override
  String updateVersionWithBuild(String version, int code) {
    return '$version (build $code)';
  }

  @override
  String get updateVersionUnknown => 'Version unavailable';

  @override
  String get updateInstallBlockedTitle =>
      '\"Install unknown apps\" permission needed';

  @override
  String get updateInstallBlockedDesc =>
      'Android must allow this app to install apps, otherwise the install is rejected';

  @override
  String get updateGrantInstall => 'Open settings';

  @override
  String get updateRecheck => 'I\'ve granted it';

  @override
  String get updateUnsupported =>
      'In-app updates aren\'t available on this platform';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateFellBackToFull =>
      'Delta update didn\'t work — switched to the full package';

  @override
  String get updateAssembling =>
      'Building the new version from the installed package…';

  @override
  String get updateAssemblingHint =>
      'No extra download needed — this runs on your device';

  @override
  String get updateInstallingHint => 'Confirm the install in the system dialog';

  @override
  String get updateInstalledHint => 'Installed — restart the app to use it';

  @override
  String get updateUpToDate => 'You\'re up to date';

  @override
  String get updateCheckAgain => 'Check again';

  @override
  String updateAvailableTitle(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateDeltaBadge => 'Delta';

  @override
  String get updateFullBadge => 'Full package';

  @override
  String updateSizeWithDelta(String download, String full) {
    return 'Download $download (full package is $full)';
  }

  @override
  String updateSizeFull(String full) {
    return 'Download $full';
  }

  @override
  String updateSavedHint(String saved, int percent) {
    return '$saved less than the full package — about $percent% saved';
  }

  @override
  String get updateChangesTitle => 'What\'s new';

  @override
  String get updateNoChanges => 'No release notes for this version';

  @override
  String get updateDownloadDelta => 'Update with delta';

  @override
  String get updateDownloadFull => 'Download & install';

  @override
  String get updateSkipVersion => 'Skip this version';

  @override
  String updateSkipConfirmBody(String version) {
    return 'You won\'t be reminded about $version again — a newer release will prompt you';
  }

  @override
  String get updateSkippedHint =>
      'Skipped — you\'ll be notified about newer releases';

  @override
  String get updateReadyTitle => 'New version is ready';

  @override
  String get updateReadyDeltaHint =>
      'Built on this device — hand it to the system installer';

  @override
  String get updateReadyFullHint => 'Downloaded and verified — tap to install';

  @override
  String get updateInstallNow => 'Install now';

  @override
  String get updateRetry => 'Retry';

  @override
  String get updateFailureNetwork =>
      'Couldn\'t reach the server — check your connection';

  @override
  String get updateFailureManifest =>
      'Version information is unavailable right now';

  @override
  String get updateFailureAssetMissing =>
      'This release has no package for your device\'s architecture';

  @override
  String get updateFailureHash =>
      'The download failed verification and was discarded';

  @override
  String get updateFailureDelta => 'The rebuilt package failed verification';

  @override
  String get updateFailureNoSpace => 'Not enough storage';

  @override
  String get updateFailureInstallBlocked =>
      'This app isn\'t allowed to install apps yet';

  @override
  String get updateFailureInstallRejected => 'The system rejected the install';

  @override
  String get updateFailureUnknown => 'Something went wrong';

  @override
  String get updateMirrorTitle => 'Download mirror';

  @override
  String get updateMirrorDesc =>
      'GitHub downloads can be slow on some networks. Add proxy prefixes (one per line); they\'re tried after the direct URL';

  @override
  String get updateMirrorHint => 'https://your-proxy/';

  @override
  String get updateMirrorSaved => 'Saved — check for updates again';

  @override
  String updateSettingsSubtitle(String version) {
    return 'Installed $version';
  }

  @override
  String updateSettingsSubtitleAvailable(String version) {
    return 'Version $version available';
  }

  @override
  String get attendanceResumeTitle => 'Resume roll call?';

  @override
  String attendanceResumeBody(String name) {
    return '$name is currently suspended. Resuming restores normal roll call.';
  }

  @override
  String get attendanceResumeConfirm => 'Resume';

  @override
  String gridMakeupHint(String date, String weekday) {
    return '$date make-up workday · $weekday schedule';
  }

  @override
  String get attendanceLegendMakeup => 'Make-up workday';

  @override
  String get attendanceLegendHoliday => 'Holiday';

  @override
  String get attendanceLegendNoRecord => 'Not marked';

  @override
  String get attendanceLegendRate => 'Attendance';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule Planner'**
  String get appTitle;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get noData;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHint;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @mon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mon;

  /// No description provided for @tue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tue;

  /// No description provided for @wed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wed;

  /// No description provided for @thu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thu;

  /// No description provided for @fri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get fri;

  /// No description provided for @sat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get sat;

  /// No description provided for @sun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sun;

  /// No description provided for @tabSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get tabSchedule;

  /// No description provided for @tabAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get tabAttendance;

  /// No description provided for @tabStatistics.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get tabStatistics;

  /// No description provided for @tabTodo.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get tabTodo;

  /// No description provided for @tabToolbox.
  ///
  /// In en, this message translates to:
  /// **'Toolbox'**
  String get tabToolbox;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'My Schedule'**
  String get scheduleTitle;

  /// No description provided for @scheduleAggregateView.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get scheduleAggregateView;

  /// No description provided for @scheduleClassView.
  ///
  /// In en, this message translates to:
  /// **'Class grid'**
  String get scheduleClassView;

  /// No description provided for @selectClass.
  ///
  /// In en, this message translates to:
  /// **'Select class'**
  String get selectClass;

  /// No description provided for @emptyScheduleHint.
  ///
  /// In en, this message translates to:
  /// **'No lessons this week. Tap + to add one.'**
  String get emptyScheduleHint;

  /// No description provided for @addLesson.
  ///
  /// In en, this message translates to:
  /// **'Add lesson'**
  String get addLesson;

  /// No description provided for @editLesson.
  ///
  /// In en, this message translates to:
  /// **'Edit lesson'**
  String get editLesson;

  /// No description provided for @deleteLesson.
  ///
  /// In en, this message translates to:
  /// **'Delete lesson'**
  String get deleteLesson;

  /// No description provided for @deleteLessonConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This lesson and all attendance records tied to it will be removed. This cannot be undone.'**
  String get deleteLessonConfirmBody;

  /// No description provided for @lessonSaved.
  ///
  /// In en, this message translates to:
  /// **'Lesson saved'**
  String get lessonSaved;

  /// No description provided for @lessonDeleted.
  ///
  /// In en, this message translates to:
  /// **'Lesson deleted'**
  String get lessonDeleted;

  /// No description provided for @conflictMessage.
  ///
  /// In en, this message translates to:
  /// **'Time conflict with another lesson'**
  String get conflictMessage;

  /// No description provided for @slotOccupied.
  ///
  /// In en, this message translates to:
  /// **'This slot is already taken'**
  String get slotOccupied;

  /// No description provided for @noTemplatePeriod.
  ///
  /// In en, this message translates to:
  /// **'The bound schedule template has no matching period'**
  String get noTemplatePeriod;

  /// No description provided for @quickAddLessonHint.
  ///
  /// In en, this message translates to:
  /// **'Pick class, then course, then weekday and period to schedule it'**
  String get quickAddLessonHint;

  /// No description provided for @swapModeHint.
  ///
  /// In en, this message translates to:
  /// **'Swap mode: drag a block onto another to swap'**
  String get swapModeHint;

  /// No description provided for @swapForbidden.
  ///
  /// In en, this message translates to:
  /// **'Cannot swap across classes or templates'**
  String get swapForbidden;

  /// No description provided for @swapDone.
  ///
  /// In en, this message translates to:
  /// **'Lessons swapped'**
  String get swapDone;

  /// No description provided for @editLessonTime.
  ///
  /// In en, this message translates to:
  /// **'Adjust time'**
  String get editLessonTime;

  /// No description provided for @cascadeTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get cascadeTitle;

  /// No description provided for @cascadeOnlyThis.
  ///
  /// In en, this message translates to:
  /// **'Only this period'**
  String get cascadeOnlyThis;

  /// No description provided for @cascadeAllFollowing.
  ///
  /// In en, this message translates to:
  /// **'This and all following periods'**
  String get cascadeAllFollowing;

  /// No description provided for @periodIndexLabel.
  ///
  /// In en, this message translates to:
  /// **'Period {index}'**
  String periodIndexLabel(int index);

  /// No description provided for @templateTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule templates'**
  String get templateTitle;

  /// No description provided for @templateNew.
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get templateNew;

  /// No description provided for @templateName.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get templateName;

  /// No description provided for @templateNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Template name cannot be empty'**
  String get templateNameRequired;

  /// No description provided for @templateSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get templateSetDefault;

  /// No description provided for @templateSetDefaultConfirm.
  ///
  /// In en, this message translates to:
  /// **'New classes will use this template by default. Classes already bound to other templates are not affected.'**
  String get templateSetDefaultConfirm;

  /// No description provided for @templateIsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get templateIsDefault;

  /// No description provided for @templateBoundClasses.
  ///
  /// In en, this message translates to:
  /// **'{count} classes'**
  String templateBoundClasses(int count);

  /// No description provided for @templateDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get templateDelete;

  /// No description provided for @templateDeleteBlocked.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete this template'**
  String get templateDeleteBlocked;

  /// No description provided for @templateDeleteBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'These classes are still bound to it, please migrate them first: {names}'**
  String templateDeleteBlockedBody(String names);

  /// No description provided for @templateEditAffectClasses.
  ///
  /// In en, this message translates to:
  /// **'This change affects the displayed time of {count} classes. Lesson content will not be modified.'**
  String templateEditAffectClasses(int count);

  /// No description provided for @copyFromOtherDay.
  ///
  /// In en, this message translates to:
  /// **'Copy from another day'**
  String get copyFromOtherDay;

  /// No description provided for @copyToTargets.
  ///
  /// In en, this message translates to:
  /// **'Copy to'**
  String get copyToTargets;

  /// No description provided for @copyDone.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copyDone;

  /// No description provided for @addPeriod.
  ///
  /// In en, this message translates to:
  /// **'Add period'**
  String get addPeriod;

  /// No description provided for @removePeriod.
  ///
  /// In en, this message translates to:
  /// **'Remove period'**
  String get removePeriod;

  /// No description provided for @periodType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get periodType;

  /// No description provided for @periodStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get periodStart;

  /// No description provided for @periodEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get periodEnd;

  /// No description provided for @periodLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get periodLabel;

  /// No description provided for @periodTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get periodTypeNormal;

  /// No description provided for @periodTypeLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch break'**
  String get periodTypeLunch;

  /// No description provided for @periodTypeRecess.
  ///
  /// In en, this message translates to:
  /// **'Recess'**
  String get periodTypeRecess;

  /// No description provided for @periodTypeSelfStudy.
  ///
  /// In en, this message translates to:
  /// **'Self study'**
  String get periodTypeSelfStudy;

  /// No description provided for @periodTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get periodTypeOther;

  /// No description provided for @periodErrorInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Time must use HH:mm'**
  String get periodErrorInvalidFormat;

  /// No description provided for @periodErrorEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End time must be later than start time'**
  String get periodErrorEndBeforeStart;

  /// No description provided for @periodErrorOverlap.
  ///
  /// In en, this message translates to:
  /// **'Overlaps another period'**
  String get periodErrorOverlap;

  /// No description provided for @periodErrorNotAscending.
  ///
  /// In en, this message translates to:
  /// **'Start time must increase with period index'**
  String get periodErrorNotAscending;

  /// No description provided for @templateSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved'**
  String get templateSaved;

  /// No description provided for @attendanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendanceTitle;

  /// No description provided for @calendarMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarMonth;

  /// No description provided for @calendarWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarWeek;

  /// No description provided for @courseChipToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s classes'**
  String get courseChipToday;

  /// No description provided for @courseChipOther.
  ///
  /// In en, this message translates to:
  /// **'Other classes'**
  String get courseChipOther;

  /// No description provided for @studentList.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get studentList;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'By name (pinyin)'**
  String get sortByName;

  /// No description provided for @sortByNo.
  ///
  /// In en, this message translates to:
  /// **'By student No.'**
  String get sortByNo;

  /// No description provided for @sortByStatus.
  ///
  /// In en, this message translates to:
  /// **'By status'**
  String get sortByStatus;

  /// No description provided for @statusPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get statusPresent;

  /// No description provided for @statusLate.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get statusLate;

  /// No description provided for @statusEarlyLeave.
  ///
  /// In en, this message translates to:
  /// **'Left early'**
  String get statusEarlyLeave;

  /// No description provided for @statusAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get statusAbsent;

  /// No description provided for @statusLeave.
  ///
  /// In en, this message translates to:
  /// **'On leave'**
  String get statusLeave;

  /// No description provided for @statusUnmarked.
  ///
  /// In en, this message translates to:
  /// **'Unmarked'**
  String get statusUnmarked;

  /// No description provided for @rollCall.
  ///
  /// In en, this message translates to:
  /// **'Random picker'**
  String get rollCall;

  /// No description provided for @rollCallTitle.
  ///
  /// In en, this message translates to:
  /// **'Rolling...'**
  String get rollCallTitle;

  /// No description provided for @copySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy summary'**
  String get copySummary;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Summary copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @highRisk.
  ///
  /// In en, this message translates to:
  /// **'High risk'**
  String get highRisk;

  /// No description provided for @riskScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Risk score {score}'**
  String riskScoreLabel(int score);

  /// No description provided for @tagTitle.
  ///
  /// In en, this message translates to:
  /// **'Performance tags'**
  String get tagTitle;

  /// No description provided for @starRating.
  ///
  /// In en, this message translates to:
  /// **'Stars'**
  String get starRating;

  /// No description provided for @remark.
  ///
  /// In en, this message translates to:
  /// **'Remark'**
  String get remark;

  /// No description provided for @noStudentsHint.
  ///
  /// In en, this message translates to:
  /// **'No students in this class yet'**
  String get noStudentsHint;

  /// No description provided for @attendanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Attendance saved'**
  String get attendanceSaved;

  /// No description provided for @tagActiveSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Active in class'**
  String get tagActiveSpeaking;

  /// No description provided for @tagHomeworkOnTime.
  ///
  /// In en, this message translates to:
  /// **'Homework on time'**
  String get tagHomeworkOnTime;

  /// No description provided for @tagFocusedListening.
  ///
  /// In en, this message translates to:
  /// **'Focused listening'**
  String get tagFocusedListening;

  /// No description provided for @tagHelpingOthers.
  ///
  /// In en, this message translates to:
  /// **'Helps others'**
  String get tagHelpingOthers;

  /// No description provided for @tagGoodQuestion.
  ///
  /// In en, this message translates to:
  /// **'Good questions'**
  String get tagGoodQuestion;

  /// No description provided for @tagNeatHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Neat handwriting'**
  String get tagNeatHandwriting;

  /// No description provided for @tagTeamLeader.
  ///
  /// In en, this message translates to:
  /// **'Team leader'**
  String get tagTeamLeader;

  /// No description provided for @statisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTitle;

  /// No description provided for @granularityDay.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get granularityDay;

  /// No description provided for @granularityWeek.
  ///
  /// In en, this message translates to:
  /// **'By week'**
  String get granularityWeek;

  /// No description provided for @granularityMonth.
  ///
  /// In en, this message translates to:
  /// **'By month'**
  String get granularityMonth;

  /// No description provided for @attendanceRateChart.
  ///
  /// In en, this message translates to:
  /// **'Attendance rate'**
  String get attendanceRateChart;

  /// No description provided for @courseRateChart.
  ///
  /// In en, this message translates to:
  /// **'Rate by course'**
  String get courseRateChart;

  /// No description provided for @abnormalList.
  ///
  /// In en, this message translates to:
  /// **'Abnormal records'**
  String get abnormalList;

  /// No description provided for @riskRanking.
  ///
  /// In en, this message translates to:
  /// **'High-risk ranking'**
  String get riskRanking;

  /// No description provided for @emotionCard.
  ///
  /// In en, this message translates to:
  /// **'Encouragement'**
  String get emotionCard;

  /// No description provided for @exportExcel.
  ///
  /// In en, this message translates to:
  /// **'Export Excel'**
  String get exportExcel;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Workbook generated'**
  String get exportSuccess;

  /// No description provided for @filterByStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by status'**
  String get filterByStatus;

  /// No description provided for @attendanceRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Attendance rate'**
  String get attendanceRateLabel;

  /// No description provided for @emotionExcellent.
  ///
  /// In en, this message translates to:
  /// **'This class is doing amazingly well!'**
  String get emotionExcellent;

  /// No description provided for @emotionGood.
  ///
  /// In en, this message translates to:
  /// **'Solid attendance, keep it up!'**
  String get emotionGood;

  /// No description provided for @emotionNormal.
  ///
  /// In en, this message translates to:
  /// **'Every step forward counts.'**
  String get emotionNormal;

  /// No description provided for @emotionEncourage.
  ///
  /// In en, this message translates to:
  /// **'New week, new chances to shine.'**
  String get emotionEncourage;

  /// No description provided for @todoTitle.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get todoTitle;

  /// No description provided for @todoSmart.
  ///
  /// In en, this message translates to:
  /// **'Smart'**
  String get todoSmart;

  /// No description provided for @todoGeneral.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get todoGeneral;

  /// No description provided for @todoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to-do'**
  String get todoAdd;

  /// No description provided for @todoTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty'**
  String get todoTitleRequired;

  /// No description provided for @todoDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get todoDescription;

  /// No description provided for @todoPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get todoPriority;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @priorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get priorityMedium;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @todoDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date (optional)'**
  String get todoDueDate;

  /// No description provided for @todoAutoCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed automatically'**
  String get todoAutoCompleted;

  /// No description provided for @todoDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This to-do will be deleted permanently.'**
  String get todoDeleteConfirmBody;

  /// No description provided for @emptyTodo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do right now'**
  String get emptyTodo;

  /// No description provided for @todoCompletedSection.
  ///
  /// In en, this message translates to:
  /// **'Completed ({count})'**
  String todoCompletedSection(int count);

  /// No description provided for @toolboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Toolbox'**
  String get toolboxTitle;

  /// No description provided for @focusTimer.
  ///
  /// In en, this message translates to:
  /// **'Focus timer'**
  String get focusTimer;

  /// No description provided for @focusStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get focusStart;

  /// No description provided for @focusPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get focusPause;

  /// No description provided for @focusResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get focusResume;

  /// No description provided for @focusReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get focusReset;

  /// No description provided for @focusBreak.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get focusBreak;

  /// No description provided for @focusDone.
  ///
  /// In en, this message translates to:
  /// **'Focus session complete'**
  String get focusDone;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick notes'**
  String get noteTitle;

  /// No description provided for @noteEditor.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteEditor;

  /// No description provided for @noteEmpty.
  ///
  /// In en, this message translates to:
  /// **'Start writing...'**
  String get noteEmpty;

  /// No description provided for @aiExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get aiExpand;

  /// No description provided for @aiPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get aiPolish;

  /// No description provided for @aiSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get aiSummarize;

  /// No description provided for @aiApply.
  ///
  /// In en, this message translates to:
  /// **'Apply result'**
  String get aiApply;

  /// No description provided for @aiDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get aiDiscard;

  /// No description provided for @aiDiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Review AI result'**
  String get aiDiffTitle;

  /// No description provided for @aiOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get aiOriginal;

  /// No description provided for @aiResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get aiResult;

  /// No description provided for @aiNoProvider.
  ///
  /// In en, this message translates to:
  /// **'No LLM provider configured'**
  String get aiNoProvider;

  /// No description provided for @aiSelectTextFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a piece of text first'**
  String get aiSelectTextFirst;

  /// No description provided for @scheduleCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get scheduleCalendar;

  /// No description provided for @eventAdd.
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get eventAdd;

  /// No description provided for @eventTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get eventTitle;

  /// No description provided for @eventLocation.
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get eventLocation;

  /// No description provided for @eventReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get eventReminder;

  /// No description provided for @eventReminderBefore.
  ///
  /// In en, this message translates to:
  /// **'Minutes before'**
  String get eventReminderBefore;

  /// No description provided for @generalTodoTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal to-do list'**
  String get generalTodoTitle;

  /// No description provided for @llmProviders.
  ///
  /// In en, this message translates to:
  /// **'LLM providers'**
  String get llmProviders;

  /// No description provided for @llmProviderName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get llmProviderName;

  /// No description provided for @llmBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get llmBaseUrl;

  /// No description provided for @llmApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get llmApiKey;

  /// No description provided for @llmModelName.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get llmModelName;

  /// No description provided for @llmSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Use by default'**
  String get llmSetDefault;

  /// No description provided for @manageTitle.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get manageTitle;

  /// No description provided for @manageClasses.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get manageClasses;

  /// No description provided for @manageCourses.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get manageCourses;

  /// No description provided for @manageStudents.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get manageStudents;

  /// No description provided for @className.
  ///
  /// In en, this message translates to:
  /// **'Class name'**
  String get className;

  /// No description provided for @gradeName.
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get gradeName;

  /// No description provided for @headTeacher.
  ///
  /// In en, this message translates to:
  /// **'Head teacher'**
  String get headTeacher;

  /// No description provided for @studentCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} students'**
  String studentCountLabel(int count);

  /// No description provided for @classColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get classColor;

  /// No description provided for @templateBinding.
  ///
  /// In en, this message translates to:
  /// **'Schedule template'**
  String get templateBinding;

  /// No description provided for @studentName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get studentName;

  /// No description provided for @studentNo.
  ///
  /// In en, this message translates to:
  /// **'Student No.'**
  String get studentNo;

  /// No description provided for @importExcel.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel'**
  String get importExcel;

  /// No description provided for @importPreview.
  ///
  /// In en, this message translates to:
  /// **'Import preview'**
  String get importPreview;

  /// No description provided for @importResult.
  ///
  /// In en, this message translates to:
  /// **'Success {success}, failed {fail}, skipped {skip}'**
  String importResult(int success, int fail, int skip);

  /// No description provided for @importReasonMissingName.
  ///
  /// In en, this message translates to:
  /// **'Name is empty'**
  String get importReasonMissingName;

  /// No description provided for @importReasonClassNotFound.
  ///
  /// In en, this message translates to:
  /// **'No matching class'**
  String get importReasonClassNotFound;

  /// No description provided for @importReasonDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Already exists'**
  String get importReasonDuplicate;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Import finished'**
  String get importDone;

  /// No description provided for @dragToReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press and drag to reorder'**
  String get dragToReorderHint;

  /// No description provided for @batchUpdateTemplate.
  ///
  /// In en, this message translates to:
  /// **'Batch update template'**
  String get batchUpdateTemplate;

  /// No description provided for @batchUpdateTemplateConfirm.
  ///
  /// In en, this message translates to:
  /// **'The following classes will be updated: {names}'**
  String batchUpdateTemplateConfirm(String names);

  /// No description provided for @classDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting this class also removes its courses, lessons, students and attendance records.'**
  String get classDeleteConfirmBody;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeMint.
  ///
  /// In en, this message translates to:
  /// **'Fresh mint'**
  String get themeMint;

  /// No description provided for @themeMinimalGray.
  ///
  /// In en, this message translates to:
  /// **'Minimal gray'**
  String get themeMinimalGray;

  /// No description provided for @themeNightCare.
  ///
  /// In en, this message translates to:
  /// **'Night care'**
  String get themeNightCare;

  /// No description provided for @riskThreshold.
  ///
  /// In en, this message translates to:
  /// **'High-risk absence threshold'**
  String get riskThreshold;

  /// No description provided for @attendanceWarnThreshold.
  ///
  /// In en, this message translates to:
  /// **'Attendance warning threshold (%)'**
  String get attendanceWarnThreshold;

  /// No description provided for @retentionDays.
  ///
  /// In en, this message translates to:
  /// **'Keep attendance for (days)'**
  String get retentionDays;

  /// No description provided for @retentionImportLogDays.
  ///
  /// In en, this message translates to:
  /// **'Keep import logs for (days)'**
  String get retentionImportLogDays;

  /// No description provided for @cascadeSwitch.
  ///
  /// In en, this message translates to:
  /// **'Cascade time updates'**
  String get cascadeSwitch;

  /// No description provided for @defaultAttendanceStatus.
  ///
  /// In en, this message translates to:
  /// **'Default status for unrecorded days'**
  String get defaultAttendanceStatus;

  /// No description provided for @notificationPermission.
  ///
  /// In en, this message translates to:
  /// **'Notification permission'**
  String get notificationPermission;

  /// No description provided for @notificationCheck.
  ///
  /// In en, this message translates to:
  /// **'Check permission'**
  String get notificationCheck;

  /// No description provided for @notificationOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get notificationOpenSettings;

  /// No description provided for @notificationGranted.
  ///
  /// In en, this message translates to:
  /// **'Notifications are enabled'**
  String get notificationGranted;

  /// No description provided for @notificationDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled'**
  String get notificationDenied;

  /// No description provided for @lessonReminder.
  ///
  /// In en, this message translates to:
  /// **'Pre-class reminder'**
  String get lessonReminder;

  /// No description provided for @reminderMinutesBefore.
  ///
  /// In en, this message translates to:
  /// **'Remind minutes before'**
  String get reminderMinutesBefore;

  /// No description provided for @reminderRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Rebuild reminders now'**
  String get reminderRegenerate;

  /// No description provided for @reminderRegenerated.
  ///
  /// In en, this message translates to:
  /// **'{count} reminders rebuilt from current templates'**
  String reminderRegenerated(int count);

  /// No description provided for @cleanupNow.
  ///
  /// In en, this message translates to:
  /// **'Clean up expired data'**
  String get cleanupNow;

  /// No description provided for @cleanupResult.
  ///
  /// In en, this message translates to:
  /// **'Cleaned attendance {attendance}, import logs {logs}'**
  String cleanupResult(int attendance, int logs);

  /// No description provided for @cleanupAborted.
  ///
  /// In en, this message translates to:
  /// **'Backup failed, cleanup cancelled'**
  String get cleanupAborted;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear all data'**
  String get clearAllData;

  /// No description provided for @clearAllDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'All classes, courses, lessons, students, attendance and to-dos will be erased permanently.'**
  String get clearAllDataConfirm;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @autoTodoTitle.
  ///
  /// In en, this message translates to:
  /// **'Check absences for {className} this week'**
  String autoTodoTitle(String className);

  /// No description provided for @colRow.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get colRow;

  /// No description provided for @colName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get colName;

  /// No description provided for @colNo.
  ///
  /// In en, this message translates to:
  /// **'No.'**
  String get colNo;

  /// No description provided for @colClass.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get colClass;

  /// No description provided for @colStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get colStatus;

  /// No description provided for @classFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get classFormTitle;

  /// No description provided for @courseFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get courseFormTitle;

  /// No description provided for @studentFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get studentFormTitle;

  /// No description provided for @eventFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get eventFormTitle;

  /// No description provided for @addClass.
  ///
  /// In en, this message translates to:
  /// **'Add class'**
  String get addClass;

  /// No description provided for @addCourse.
  ///
  /// In en, this message translates to:
  /// **'Add course'**
  String get addCourse;

  /// No description provided for @addStudent.
  ///
  /// In en, this message translates to:
  /// **'Add student'**
  String get addStudent;

  /// No description provided for @addEvent.
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get addEvent;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get addNote;

  /// No description provided for @deleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get deleteNote;

  /// No description provided for @deleteEvent.
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get deleteEvent;

  /// No description provided for @deleteStudent.
  ///
  /// In en, this message translates to:
  /// **'Delete student'**
  String get deleteStudent;

  /// No description provided for @deleteCourse.
  ///
  /// In en, this message translates to:
  /// **'Delete course'**
  String get deleteCourse;

  /// No description provided for @deleteClass.
  ///
  /// In en, this message translates to:
  /// **'Delete class'**
  String get deleteClass;

  /// No description provided for @pickColor.
  ///
  /// In en, this message translates to:
  /// **'Pick color'**
  String get pickColor;

  /// No description provided for @importChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose Excel file'**
  String get importChooseFile;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// No description provided for @classSaved.
  ///
  /// In en, this message translates to:
  /// **'Class saved'**
  String get classSaved;

  /// No description provided for @courseSaved.
  ///
  /// In en, this message translates to:
  /// **'Course saved'**
  String get courseSaved;

  /// No description provided for @studentSaved.
  ///
  /// In en, this message translates to:
  /// **'Student saved'**
  String get studentSaved;

  /// No description provided for @eventSaved.
  ///
  /// In en, this message translates to:
  /// **'Event saved'**
  String get eventSaved;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @timePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick time'**
  String get timePickerTitle;

  /// No description provided for @hour.
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get hour;

  /// No description provided for @minute.
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get minute;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get requiredField;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {message}'**
  String operationFailed(String message);

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error, please retry'**
  String get unexpectedError;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @scheduleModeTraditional.
  ///
  /// In en, this message translates to:
  /// **'Class grid'**
  String get scheduleModeTraditional;

  /// No description provided for @scheduleModeStaggered.
  ///
  /// In en, this message translates to:
  /// **'Teacher timeline'**
  String get scheduleModeStaggered;

  /// No description provided for @scheduleModeSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch schedule view'**
  String get scheduleModeSwitch;

  /// No description provided for @scheduleSettings.
  ///
  /// In en, this message translates to:
  /// **'Schedule settings'**
  String get scheduleSettings;

  /// No description provided for @gridPeriodHeader.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get gridPeriodHeader;

  /// No description provided for @gridTimeHeader.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get gridTimeHeader;

  /// No description provided for @todayLabel.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayLabel;

  /// No description provided for @quickGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate periods'**
  String get quickGenerateTitle;

  /// No description provided for @quickGenerateDesc.
  ///
  /// In en, this message translates to:
  /// **'Batch-generate periods from start time, lesson length, break and count'**
  String get quickGenerateDesc;

  /// No description provided for @generateStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get generateStartTime;

  /// No description provided for @generateLessonMinutes.
  ///
  /// In en, this message translates to:
  /// **'Lesson length (min)'**
  String get generateLessonMinutes;

  /// No description provided for @generateBreakMinutes.
  ///
  /// In en, this message translates to:
  /// **'Break length (min)'**
  String get generateBreakMinutes;

  /// No description provided for @generatePeriodCount.
  ///
  /// In en, this message translates to:
  /// **'Periods per day'**
  String get generatePeriodCount;

  /// No description provided for @generateWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get generateWeekdays;

  /// No description provided for @generatePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get generatePreview;

  /// No description provided for @generateDone.
  ///
  /// In en, this message translates to:
  /// **'Generated {count} periods'**
  String generateDone(int count);

  /// No description provided for @generatePreviewRow.
  ///
  /// In en, this message translates to:
  /// **'Period {index}　{start}-{end}'**
  String generatePreviewRow(int index, String start, String end);

  /// No description provided for @generateInvalidRange.
  ///
  /// In en, this message translates to:
  /// **'Range exceeds one day. Reduce periods or length.'**
  String get generateInvalidRange;

  /// No description provided for @generateEmptyWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one weekday'**
  String get generateEmptyWeekdays;

  /// No description provided for @editPeriodTime.
  ///
  /// In en, this message translates to:
  /// **'Edit period time'**
  String get editPeriodTime;

  /// No description provided for @editPeriodTimeDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit this period, with optional shift of the following ones'**
  String get editPeriodTimeDesc;

  /// No description provided for @cascadeFollowing.
  ///
  /// In en, this message translates to:
  /// **'Shift following periods'**
  String get cascadeFollowing;

  /// No description provided for @periodTimeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Period time updated'**
  String get periodTimeUpdated;

  /// No description provided for @cascadeApplied.
  ///
  /// In en, this message translates to:
  /// **'Shifted {count} periods'**
  String cascadeApplied(int count);

  /// No description provided for @defaultTemplateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit default periods'**
  String get defaultTemplateEdit;

  /// No description provided for @defaultTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Used by default for new classes'**
  String get defaultTemplateHint;

  /// No description provided for @clearSchedule.
  ///
  /// In en, this message translates to:
  /// **'Clear schedule'**
  String get clearSchedule;

  /// No description provided for @clearScheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clears the lessons of every class on this template. Period times are kept. This cannot be undone.'**
  String get clearScheduleConfirm;

  /// No description provided for @clearScheduleDone.
  ///
  /// In en, this message translates to:
  /// **'Schedule cleared'**
  String get clearScheduleDone;

  /// No description provided for @importPhotoSchedule.
  ///
  /// In en, this message translates to:
  /// **'Import from photo'**
  String get importPhotoSchedule;

  /// No description provided for @importPhotoScheduleHint.
  ///
  /// In en, this message translates to:
  /// **'Take or pick a timetable photo — it is recognized on-device'**
  String get importPhotoScheduleHint;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @toolboxAllTools.
  ///
  /// In en, this message translates to:
  /// **'All tools'**
  String get toolboxAllTools;

  /// No description provided for @toolStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get toolStatistics;

  /// No description provided for @toolTodo.
  ///
  /// In en, this message translates to:
  /// **'Smart todos'**
  String get toolTodo;

  /// No description provided for @toolFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get toolFocus;

  /// No description provided for @toolNote.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get toolNote;

  /// No description provided for @toolCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get toolCalendar;

  /// No description provided for @toolPrivateTodo.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get toolPrivateTodo;

  /// No description provided for @toolboxInsight.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get toolboxInsight;

  /// No description provided for @insightDoneLessons.
  ///
  /// In en, this message translates to:
  /// **'Lessons done'**
  String get insightDoneLessons;

  /// No description provided for @insightLeftLessons.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get insightLeftLessons;

  /// No description provided for @insightAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get insightAttention;

  /// No description provided for @insightNoAttention.
  ///
  /// In en, this message translates to:
  /// **'All good, keep it up'**
  String get insightNoAttention;

  /// No description provided for @insightAttendanceRate.
  ///
  /// In en, this message translates to:
  /// **'Attendance rate'**
  String get insightAttendanceRate;

  /// No description provided for @insightCheer.
  ///
  /// In en, this message translates to:
  /// **'{done} lessons done this week. Nice work.'**
  String insightCheer(int done);

  /// No description provided for @insightStudentRisk.
  ///
  /// In en, this message translates to:
  /// **'{name} was absent {count} times this week'**
  String insightStudentRisk(String name, int count);

  /// No description provided for @pageIndicator.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String pageIndicator(int current, int total);

  /// No description provided for @weekRange.
  ///
  /// In en, this message translates to:
  /// **'{start} ~ {end}'**
  String weekRange(String start, String end);

  /// No description provided for @groupScheduleData.
  ///
  /// In en, this message translates to:
  /// **'Schedule & roster'**
  String get groupScheduleData;

  /// No description provided for @groupPermission.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get groupPermission;

  /// No description provided for @groupDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display & language'**
  String get groupDisplay;

  /// No description provided for @groupAssistant.
  ///
  /// In en, this message translates to:
  /// **'Smart features'**
  String get groupAssistant;

  /// No description provided for @groupData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get groupData;

  /// No description provided for @groupAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get groupAbout;

  /// No description provided for @groupTeaching.
  ///
  /// In en, this message translates to:
  /// **'Teaching'**
  String get groupTeaching;

  /// No description provided for @studentRoster.
  ///
  /// In en, this message translates to:
  /// **'Student roster'**
  String get studentRoster;

  /// No description provided for @studentRosterDesc.
  ///
  /// In en, this message translates to:
  /// **'Add, edit, delete, or bulk import from Excel'**
  String get studentRosterDesc;

  /// No description provided for @classManagement.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get classManagement;

  /// No description provided for @classManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Classes and counts are created from imports'**
  String get classManagementDesc;

  /// No description provided for @courseManagement.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get courseManagement;

  /// No description provided for @courseManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Add courses, edit rooms and classes (tap an empty slot in the schedule to place one)'**
  String get courseManagementDesc;

  /// No description provided for @statisticsSettings.
  ///
  /// In en, this message translates to:
  /// **'Statistics settings'**
  String get statisticsSettings;

  /// No description provided for @statisticsSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Risk and warning thresholds'**
  String get statisticsSettingsDesc;

  /// No description provided for @studentGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get studentGender;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @genderUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get genderUnset;

  /// No description provided for @studentNoOptional.
  ///
  /// In en, this message translates to:
  /// **'Student no. (optional)'**
  String get studentNoOptional;

  /// No description provided for @studentNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name (required)'**
  String get studentNameRequired;

  /// No description provided for @studentClassRequired.
  ///
  /// In en, this message translates to:
  /// **'Class (required)'**
  String get studentClassRequired;

  /// No description provided for @studentFormDesc.
  ///
  /// In en, this message translates to:
  /// **'Name and class are required; gender and student no. are optional'**
  String get studentFormDesc;

  /// No description provided for @courseNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Course name'**
  String get courseNameLabel;

  /// No description provided for @courseRoomLabel.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get courseRoomLabel;

  /// No description provided for @courseClassLabel.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get courseClassLabel;

  /// No description provided for @courseCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get courseCountLabel;

  /// No description provided for @courseRemarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get courseRemarkLabel;

  /// No description provided for @courseMultiClassHint.
  ///
  /// In en, this message translates to:
  /// **'Multiple classes allowed (combined class)'**
  String get courseMultiClassHint;

  /// No description provided for @courseClassRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one class'**
  String get courseClassRequired;

  /// No description provided for @courseAutoCountHint.
  ///
  /// In en, this message translates to:
  /// **'Counted from the selected classes'**
  String get courseAutoCountHint;

  /// No description provided for @courseClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all courses'**
  String get courseClearAll;

  /// No description provided for @courseClearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'This deletes every course and its lessons. It cannot be undone.'**
  String get courseClearAllConfirm;

  /// No description provided for @courseCleared.
  ///
  /// In en, this message translates to:
  /// **'Courses cleared'**
  String get courseCleared;

  /// No description provided for @importStudents.
  ///
  /// In en, this message translates to:
  /// **'Bulk import students from Excel'**
  String get importStudents;

  /// No description provided for @importFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'File format'**
  String get importFormatTitle;

  /// No description provided for @importFormatLine1.
  ///
  /// In en, this message translates to:
  /// **'Only .xlsx files'**
  String get importFormatLine1;

  /// No description provided for @importFormatLine2.
  ///
  /// In en, this message translates to:
  /// **'\"姓名\" and \"班级\" columns are required'**
  String get importFormatLine2;

  /// No description provided for @importFormatLine3.
  ///
  /// In en, this message translates to:
  /// **'\"学号\" and \"性别\" are optional'**
  String get importFormatLine3;

  /// No description provided for @importFormatLine4.
  ///
  /// In en, this message translates to:
  /// **'Unknown classes are created automatically'**
  String get importFormatLine4;

  /// No description provided for @importFormatExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get importFormatExample;

  /// No description provided for @importAutoCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {count} classes'**
  String importAutoCreated(int count);

  /// No description provided for @importRowsTotal.
  ///
  /// In en, this message translates to:
  /// **'Parsed {count} rows'**
  String importRowsTotal(int count);

  /// No description provided for @importNeedNameOrClass.
  ///
  /// In en, this message translates to:
  /// **'Both \"姓名\" and \"班级\" must be filled'**
  String get importNeedNameOrClass;

  /// No description provided for @importOverall.
  ///
  /// In en, this message translates to:
  /// **'Import summary'**
  String get importOverall;

  /// No description provided for @importClassColumn.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get importClassColumn;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutChangelog.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get aboutChangelog;

  /// No description provided for @aboutChangelogBody.
  ///
  /// In en, this message translates to:
  /// **'1.0.0 first release: schedule, attendance, statistics, todos and toolbox, with six themes and bilingual UI.'**
  String get aboutChangelogBody;

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloper;

  /// No description provided for @aboutDeveloperName.
  ///
  /// In en, this message translates to:
  /// **'Teaching Assistant Team'**
  String get aboutDeveloperName;

  /// No description provided for @aboutTechStack.
  ///
  /// In en, this message translates to:
  /// **'Tech stack'**
  String get aboutTechStack;

  /// No description provided for @aboutAppName.
  ///
  /// In en, this message translates to:
  /// **'Schedule Plan'**
  String get aboutAppName;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @attendanceWeekDefault.
  ///
  /// In en, this message translates to:
  /// **'Week view'**
  String get attendanceWeekDefault;

  /// No description provided for @attendanceMonthView.
  ///
  /// In en, this message translates to:
  /// **'Month view'**
  String get attendanceMonthView;

  /// No description provided for @attendanceNoLesson.
  ///
  /// In en, this message translates to:
  /// **'No lessons today'**
  String get attendanceNoLesson;

  /// No description provided for @attendanceCountSummary.
  ///
  /// In en, this message translates to:
  /// **'{total} total · {present} present'**
  String attendanceCountSummary(int total, int present);

  /// No description provided for @markAll.
  ///
  /// In en, this message translates to:
  /// **'Mark all'**
  String get markAll;

  /// No description provided for @statsRiskThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Flag as high risk when weekly absences reach this number'**
  String get statsRiskThresholdDesc;

  /// No description provided for @statsWarnThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Highlight in charts when attendance drops below this rate'**
  String get statsWarnThresholdDesc;

  /// No description provided for @statsColumnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get statsColumnName;

  /// No description provided for @statsColumnNo.
  ///
  /// In en, this message translates to:
  /// **'Student no.'**
  String get statsColumnNo;

  /// No description provided for @statsColumnStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statsColumnStatus;

  /// No description provided for @toolStatisticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Attendance trends and ranking'**
  String get toolStatisticsDesc;

  /// No description provided for @toolTodoDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated from attendance'**
  String get toolTodoDesc;

  /// No description provided for @toolFocusDesc.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro focus timer'**
  String get toolFocusDesc;

  /// No description provided for @toolNoteDesc.
  ///
  /// In en, this message translates to:
  /// **'Quick notes with AI expansion'**
  String get toolNoteDesc;

  /// No description provided for @toolCalendarDesc.
  ///
  /// In en, this message translates to:
  /// **'Events and reminders'**
  String get toolCalendarDesc;

  /// No description provided for @toolPrivateTodoDesc.
  ///
  /// In en, this message translates to:
  /// **'Your private checklist'**
  String get toolPrivateTodoDesc;

  /// No description provided for @importReasonMissingClass.
  ///
  /// In en, this message translates to:
  /// **'Missing class'**
  String get importReasonMissingClass;

  /// No description provided for @noStudentNo.
  ///
  /// In en, this message translates to:
  /// **'No student no.'**
  String get noStudentNo;

  /// No description provided for @unitTimes.
  ///
  /// In en, this message translates to:
  /// **' times'**
  String get unitTimes;

  /// No description provided for @unitDays.
  ///
  /// In en, this message translates to:
  /// **' d'**
  String get unitDays;

  /// No description provided for @unitMinutes.
  ///
  /// In en, this message translates to:
  /// **' min'**
  String get unitMinutes;

  /// No description provided for @unitPercent.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get unitPercent;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule, roster, permissions and display'**
  String get settingsSubtitle;

  /// No description provided for @themeSunrise.
  ///
  /// In en, this message translates to:
  /// **'Sunrise'**
  String get themeSunrise;

  /// No description provided for @themeOceanBlue.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get themeOceanBlue;

  /// No description provided for @themeSakura.
  ///
  /// In en, this message translates to:
  /// **'Sakura'**
  String get themeSakura;

  /// No description provided for @scheduleCleared.
  ///
  /// In en, this message translates to:
  /// **'Schedule cleared'**
  String get scheduleCleared;

  /// No description provided for @periodTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Period time updated'**
  String get periodTimeSaved;

  /// No description provided for @switchTemplate.
  ///
  /// In en, this message translates to:
  /// **'Switch schedule'**
  String get switchTemplate;

  /// No description provided for @scheduleGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated a schedule of {count} periods'**
  String scheduleGenerated(int count);

  /// No description provided for @studentNameShort.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get studentNameShort;

  /// No description provided for @studentNoShort.
  ///
  /// In en, this message translates to:
  /// **'No.'**
  String get studentNoShort;

  /// No description provided for @attendanceColumn.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get attendanceColumn;

  /// No description provided for @calendarMonthTitle.
  ///
  /// In en, this message translates to:
  /// **'{month}/{year}'**
  String calendarMonthTitle(int year, int month);

  /// No description provided for @calendarWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'{start} - {end}'**
  String calendarWeekTitle(String start, String end);

  /// No description provided for @importFileUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This file cannot be read. Make sure it is an unencrypted .xlsx file, or open it in Excel/WPS and save it as .xlsx, then try again.'**
  String get importFileUnreadable;

  /// No description provided for @scheduleNoClassHint.
  ///
  /// In en, this message translates to:
  /// **'No class yet - showing the default bell schedule'**
  String get scheduleNoClassHint;

  /// No description provided for @cellNoCourseTitle.
  ///
  /// In en, this message translates to:
  /// **'No course in this slot'**
  String get cellNoCourseTitle;

  /// No description provided for @cellNoCourseBody.
  ///
  /// In en, this message translates to:
  /// **'Create a course in course management first, then tap this slot again and swipe to place it.'**
  String get cellNoCourseBody;

  /// No description provided for @cellNeedsClassBody.
  ///
  /// In en, this message translates to:
  /// **'You have no class yet. Create a class and import its roster before scheduling.'**
  String get cellNeedsClassBody;

  /// No description provided for @goAddCourse.
  ///
  /// In en, this message translates to:
  /// **'Add course'**
  String get goAddCourse;

  /// No description provided for @goCreateClass.
  ///
  /// In en, this message translates to:
  /// **'Create class'**
  String get goCreateClass;

  /// No description provided for @pickCourseTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a course for this slot'**
  String get pickCourseTitle;

  /// No description provided for @pickCourseHint.
  ///
  /// In en, this message translates to:
  /// **'Scroll to browse, tap to pick, then place it here'**
  String get pickCourseHint;

  /// No description provided for @placeHere.
  ///
  /// In en, this message translates to:
  /// **'Place here'**
  String get placeHere;

  /// No description provided for @noCourseYet.
  ///
  /// In en, this message translates to:
  /// **'No course yet'**
  String get noCourseYet;

  /// No description provided for @lessonDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Course details'**
  String get lessonDetailTitle;

  /// No description provided for @goRollCall.
  ///
  /// In en, this message translates to:
  /// **'Take attendance'**
  String get goRollCall;

  /// No description provided for @changeLessonCourse.
  ///
  /// In en, this message translates to:
  /// **'Change course'**
  String get changeLessonCourse;

  /// No description provided for @removeFromSchedule.
  ///
  /// In en, this message translates to:
  /// **'Remove from schedule'**
  String get removeFromSchedule;

  /// No description provided for @removedFromSchedule.
  ///
  /// In en, this message translates to:
  /// **'Removed from schedule'**
  String get removedFromSchedule;

  /// No description provided for @placedToSchedule.
  ///
  /// In en, this message translates to:
  /// **'Added to schedule'**
  String get placedToSchedule;

  /// No description provided for @cellStudentCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String cellStudentCount(int count);

  /// No description provided for @classHeadTeacherFromClass.
  ///
  /// In en, this message translates to:
  /// **'Head teacher (from the class)'**
  String get classHeadTeacherFromClass;

  /// No description provided for @classDeleteConfirmWithStudents.
  ///
  /// In en, this message translates to:
  /// **'This class still has {count} students. Deleting it also removes them, the courses, the schedule and all attendance records. This cannot be undone.'**
  String classDeleteConfirmWithStudents(int count);

  /// No description provided for @classCreatedNextStep.
  ///
  /// In en, this message translates to:
  /// **'Class created - add the student roster for it'**
  String get classCreatedNextStep;

  /// No description provided for @goAddStudents.
  ///
  /// In en, this message translates to:
  /// **'Add students'**
  String get goAddStudents;

  /// No description provided for @attendanceLocatedTo.
  ///
  /// In en, this message translates to:
  /// **'Opened {date}'**
  String attendanceLocatedTo(String date);

  /// No description provided for @dialAmLabel.
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get dialAmLabel;

  /// No description provided for @dialPmLabel.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get dialPmLabel;

  /// No description provided for @dialTwoRingHint.
  ///
  /// In en, this message translates to:
  /// **'Inner ring sets the hour, outer ring sets the minute'**
  String get dialTwoRingHint;

  /// No description provided for @periodDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Period length {count} min'**
  String periodDurationMinutes(int count);

  /// No description provided for @periodAutoEndHint.
  ///
  /// In en, this message translates to:
  /// **'End time is auto-calculated from the period length'**
  String get periodAutoEndHint;

  /// No description provided for @periodCustomEnd.
  ///
  /// In en, this message translates to:
  /// **'Custom end time'**
  String get periodCustomEnd;

  /// No description provided for @periodAutoEndBadge.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get periodAutoEndBadge;

  /// No description provided for @classInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Class info'**
  String get classInfoTitle;

  /// No description provided for @classStatStudents.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get classStatStudents;

  /// No description provided for @classStatMale.
  ///
  /// In en, this message translates to:
  /// **'Boys'**
  String get classStatMale;

  /// No description provided for @classStatFemale.
  ///
  /// In en, this message translates to:
  /// **'Girls'**
  String get classStatFemale;

  /// No description provided for @classStatUnset.
  ///
  /// In en, this message translates to:
  /// **'Unset'**
  String get classStatUnset;

  /// No description provided for @classDetailStudents.
  ///
  /// In en, this message translates to:
  /// **'Students in this class'**
  String get classDetailStudents;

  /// No description provided for @classDetailStudentsDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap a student to edit; use the icon to delete'**
  String get classDetailStudentsDesc;

  /// No description provided for @classDetailNoStudents.
  ///
  /// In en, this message translates to:
  /// **'No students yet - tap + to add'**
  String get classDetailNoStudents;

  /// No description provided for @classDetailCourses.
  ///
  /// In en, this message translates to:
  /// **'Courses of this class'**
  String get classDetailCourses;

  /// No description provided for @classDetailCoursesDesc.
  ///
  /// In en, this message translates to:
  /// **'Maintain course names, rooms and classes'**
  String get classDetailCoursesDesc;

  /// No description provided for @classDetailTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to open class details'**
  String get classDetailTapHint;

  /// No description provided for @deleteStudentConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting also removes this student\'s attendance records. This cannot be undone.'**
  String get deleteStudentConfirmBody;

  /// No description provided for @rosterSummary.
  ///
  /// In en, this message translates to:
  /// **'{students} students · {classes} classes'**
  String rosterSummary(int students, int classes);

  /// No description provided for @rosterEmptyGuide.
  ///
  /// In en, this message translates to:
  /// **'No students yet - import a roster from Excel'**
  String get rosterEmptyGuide;

  /// No description provided for @goImportRoster.
  ///
  /// In en, this message translates to:
  /// **'Import roster'**
  String get goImportRoster;

  /// No description provided for @coursePickClassTitle.
  ///
  /// In en, this message translates to:
  /// **'Select classes'**
  String get coursePickClassTitle;

  /// No description provided for @coursePickClassHint.
  ///
  /// In en, this message translates to:
  /// **'Multi-select (combined classes allowed); the headcount is summed automatically'**
  String get coursePickClassHint;

  /// No description provided for @pickClass.
  ///
  /// In en, this message translates to:
  /// **'Select classes'**
  String get pickClass;

  /// No description provided for @teacherUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get teacherUnset;

  /// No description provided for @periodRestoreAuto.
  ///
  /// In en, this message translates to:
  /// **'Reset to auto'**
  String get periodRestoreAuto;

  /// No description provided for @classDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Class details'**
  String get classDetailTitle;

  /// No description provided for @importAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Imported automatically, no extra confirmation'**
  String get importAutoHint;

  /// No description provided for @importGoRoster.
  ///
  /// In en, this message translates to:
  /// **'Open roster'**
  String get importGoRoster;

  /// No description provided for @importDetailToggle.
  ///
  /// In en, this message translates to:
  /// **'View import details ({count} rows)'**
  String importDetailToggle(int count);

  /// No description provided for @importDetailHide.
  ///
  /// In en, this message translates to:
  /// **'Hide import details'**
  String get importDetailHide;

  /// No description provided for @courseColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Course color'**
  String get courseColorLabel;

  /// No description provided for @courseColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Use class color'**
  String get courseColorAuto;

  /// No description provided for @courseColorHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a color; schedule cells use it for this course'**
  String get courseColorHint;

  /// No description provided for @generateReplacesHint.
  ///
  /// In en, this message translates to:
  /// **'This selection is authoritative; unselected weekdays are cleared'**
  String get generateReplacesHint;

  /// No description provided for @importEmptyFile.
  ///
  /// In en, this message translates to:
  /// **'No student rows found — check that the name and class columns have content'**
  String get importEmptyFile;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @statusShortPresent.
  ///
  /// In en, this message translates to:
  /// **'P'**
  String get statusShortPresent;

  /// No description provided for @statusShortLate.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get statusShortLate;

  /// No description provided for @statusShortEarlyLeave.
  ///
  /// In en, this message translates to:
  /// **'EL'**
  String get statusShortEarlyLeave;

  /// No description provided for @statusShortAbsent.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get statusShortAbsent;

  /// No description provided for @statusShortLeave.
  ///
  /// In en, this message translates to:
  /// **'Lv'**
  String get statusShortLeave;

  /// No description provided for @statusShortUnmarked.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get statusShortUnmarked;

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get statusSuspended;

  /// No description provided for @statusExempt.
  ///
  /// In en, this message translates to:
  /// **'Exempt'**
  String get statusExempt;

  /// No description provided for @statusShortSuspended.
  ///
  /// In en, this message translates to:
  /// **'Sus'**
  String get statusShortSuspended;

  /// No description provided for @statusShortExempt.
  ///
  /// In en, this message translates to:
  /// **'Ex'**
  String get statusShortExempt;

  /// No description provided for @attendanceLongTermUntil.
  ///
  /// In en, this message translates to:
  /// **'{status} · until {date}'**
  String attendanceLongTermUntil(String status, String date);

  /// No description provided for @attendanceLongTermSet.
  ///
  /// In en, this message translates to:
  /// **'{name} marked {status} until {date}'**
  String attendanceLongTermSet(String name, String status, String date);

  /// No description provided for @attendanceLongTermCleared.
  ///
  /// In en, this message translates to:
  /// **'{name} is back to normal roll call'**
  String attendanceLongTermCleared(String name);

  /// No description provided for @attendanceLongTermClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel {status}?'**
  String attendanceLongTermClearTitle(String status);

  /// No description provided for @attendanceLongTermClearBody.
  ///
  /// In en, this message translates to:
  /// **'{name} returns to normal roll call and must be marked lesson by lesson.'**
  String attendanceLongTermClearBody(String name);

  /// No description provided for @attendanceLongTermLocked.
  ///
  /// In en, this message translates to:
  /// **'{name} · {status} until {date} — no per-lesson marking needed'**
  String attendanceLongTermLocked(String name, String status, String date);

  /// No description provided for @rosterGroupCount.
  ///
  /// In en, this message translates to:
  /// **'{count} students'**
  String rosterGroupCount(int count);

  /// No description provided for @shareSchedule.
  ///
  /// In en, this message translates to:
  /// **'Share schedule'**
  String get shareSchedule;

  /// No description provided for @shareSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to gallery'**
  String get shareSavedToGallery;

  /// No description provided for @shareGalleryPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow photos & videos access to save to the gallery'**
  String get shareGalleryPermissionDenied;

  /// No description provided for @shareOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get shareOpenSettings;

  /// No description provided for @shareCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t capture, try again'**
  String get shareCaptureFailed;

  /// No description provided for @shareQrPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get shareQrPlaceholder;

  /// No description provided for @copyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

  /// No description provided for @summaryNoAbnormal.
  ///
  /// In en, this message translates to:
  /// **'All present, nothing abnormal'**
  String get summaryNoAbnormal;

  /// No description provided for @courseFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Filter by course'**
  String get courseFilterLabel;

  /// No description provided for @eventRecurrence.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get eventRecurrence;

  /// No description provided for @eventRecurrenceOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get eventRecurrenceOnce;

  /// No description provided for @eventRecurrenceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get eventRecurrenceWeekly;

  /// No description provided for @eventRecurrenceBiweekly.
  ///
  /// In en, this message translates to:
  /// **'Biweekly'**
  String get eventRecurrenceBiweekly;

  /// No description provided for @eventRecurrenceMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get eventRecurrenceMonthly;

  /// No description provided for @insightBenefitedStudents.
  ///
  /// In en, this message translates to:
  /// **'Students reached'**
  String get insightBenefitedStudents;

  /// No description provided for @toolboxSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe · 2 pages'**
  String get toolboxSwipeHint;

  /// No description provided for @ocrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan schedule photo'**
  String get ocrTitle;

  /// No description provided for @ocrEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule from photo'**
  String get ocrEntryTitle;

  /// No description provided for @ocrEntryDesc.
  ///
  /// In en, this message translates to:
  /// **'Snap a timetable, recognize it on-device, build the schedule'**
  String get ocrEntryDesc;

  /// No description provided for @ocrPickPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get ocrPickPhoto;

  /// No description provided for @ocrPickPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Shoot the whole timetable flat and straight. Headers like \"Mon…Fri\" and \"period N\" help a lot'**
  String get ocrPickPhotoHint;

  /// No description provided for @ocrFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get ocrFromCamera;

  /// No description provided for @ocrFromGallery.
  ///
  /// In en, this message translates to:
  /// **'From gallery'**
  String get ocrFromGallery;

  /// No description provided for @ocrRecognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing…'**
  String get ocrRecognizing;

  /// No description provided for @ocrRecognizingHint.
  ///
  /// In en, this message translates to:
  /// **'Runs entirely on this device — nothing is uploaded'**
  String get ocrRecognizingHint;

  /// No description provided for @ocrCropTitle.
  ///
  /// In en, this message translates to:
  /// **'Frame the timetable'**
  String get ocrCropTitle;

  /// No description provided for @ocrCropHint.
  ///
  /// In en, this message translates to:
  /// **'Frame just the table — drop the title and margins for better accuracy'**
  String get ocrCropHint;

  /// No description provided for @ocrCropReset.
  ///
  /// In en, this message translates to:
  /// **'Reset frame'**
  String get ocrCropReset;

  /// No description provided for @ocrCropConfirm.
  ///
  /// In en, this message translates to:
  /// **'Recognize this area'**
  String get ocrCropConfirm;

  /// No description provided for @ocrResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Recognition result'**
  String get ocrResultTitle;

  /// No description provided for @ocrResultSummary.
  ///
  /// In en, this message translates to:
  /// **'{lessons} lessons · {courses} courses · {days} days'**
  String ocrResultSummary(Object courses, Object days, Object lessons);

  /// No description provided for @ocrConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'Looks good — review and import'**
  String get ocrConfidenceHigh;

  /// No description provided for @ocrConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'So-so result — check each row before importing'**
  String get ocrConfidenceMedium;

  /// No description provided for @ocrConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'The photo is unclear — retake it or fix the rows by hand'**
  String get ocrConfidenceLow;

  /// No description provided for @ocrImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get ocrImport;

  /// No description provided for @ocrImportDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {lessons} lessons, {courses} new courses'**
  String ocrImportDone(Object courses, Object lessons);

  /// No description provided for @ocrRecapture.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get ocrRecapture;

  /// No description provided for @ocrEditRow.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit the course name'**
  String get ocrEditRow;

  /// No description provided for @ocrRowEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit course name'**
  String get ocrRowEditTitle;

  /// No description provided for @ocrNoPhoto.
  ///
  /// In en, this message translates to:
  /// **'No photo selected'**
  String get ocrNoPhoto;

  /// No description provided for @ocrNoPhotoPermission.
  ///
  /// In en, this message translates to:
  /// **'Photo access is needed to read the timetable image'**
  String get ocrNoPhotoPermission;

  /// No description provided for @ocrEngineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No on-device text recognition engine available — use Excel import instead'**
  String get ocrEngineUnavailable;

  /// No description provided for @ocrEngineUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Engine unavailable'**
  String get ocrEngineUnavailableTitle;

  /// No description provided for @ocrEngineUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Recognition runs fully on-device (offline ML Kit). No network, no upload. This device can\'t provide it — usually an old OS or missing Google services. Use Excel import or place lessons by hand for now.'**
  String get ocrEngineUnavailableBody;

  /// No description provided for @ocrWarnNoWeekday.
  ///
  /// In en, this message translates to:
  /// **'No weekday header found — make sure the whole table is in frame'**
  String get ocrWarnNoWeekday;

  /// No description provided for @ocrWarnPartialWeekday.
  ///
  /// In en, this message translates to:
  /// **'Only some weekday columns were found — a few days may be missing'**
  String get ocrWarnPartialWeekday;

  /// No description provided for @ocrWarnNoPeriod.
  ///
  /// In en, this message translates to:
  /// **'No period header found — retake or fix it by hand'**
  String get ocrWarnNoPeriod;

  /// No description provided for @ocrWarnNoLesson.
  ///
  /// In en, this message translates to:
  /// **'No lessons recognized — try another angle or a sharper shot'**
  String get ocrWarnNoLesson;

  /// No description provided for @ocrManualAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a lesson by hand'**
  String get ocrManualAdd;

  /// No description provided for @ocrAllWeekdays.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ocrAllWeekdays;

  /// No description provided for @ocrNoGoogleServices.
  ///
  /// In en, this message translates to:
  /// **'Google services missing — recognition unavailable'**
  String get ocrNoGoogleServices;

  /// No description provided for @ocrSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Snap the timetable, recognize it on-device, place it here'**
  String get ocrSettingsHint;

  /// No description provided for @ocrDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Device support'**
  String get ocrDeviceTitle;

  /// No description provided for @ocrDeviceAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android (Xiaomi / OPPO / vivo and friends): ready to use. Recognition uses the device\'s offline text engine — ML Kit when Google services are present, with a system fallback otherwise. No network at any point.'**
  String get ocrDeviceAndroid;

  /// No description provided for @ocrDeviceHarmony.
  ///
  /// In en, this message translates to:
  /// **'Huawei (HarmonyOS): not supported yet — HarmonyOS exposes none of the engines above. A dedicated version is planned; use Excel import or place lessons by hand for now.'**
  String get ocrDeviceHarmony;

  /// No description provided for @ocrDeviceIos.
  ///
  /// In en, this message translates to:
  /// **'iOS: the hook is reserved on top of Apple Vision and will be enabled together with the iOS build.'**
  String get ocrDeviceIos;

  /// No description provided for @timelineEventLegend.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get timelineEventLegend;

  /// No description provided for @timelineEventTime.
  ///
  /// In en, this message translates to:
  /// **'{start} - {end}'**
  String timelineEventTime(String start, String end);

  /// No description provided for @timelineEventTapHint.
  ///
  /// In en, this message translates to:
  /// **'tap for time'**
  String get timelineEventTapHint;

  /// No description provided for @holidayKindHoliday.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get holidayKindHoliday;

  /// No description provided for @holidayKindMakeup.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get holidayKindMakeup;

  /// No description provided for @holidayLegend.
  ///
  /// In en, this message translates to:
  /// **'Red = holiday · amber = makeup workday'**
  String get holidayLegend;

  /// No description provided for @holidayNameNewYear.
  ///
  /// In en, this message translates to:
  /// **'New Year\'s Day'**
  String get holidayNameNewYear;

  /// No description provided for @holidayNameSpringFestival.
  ///
  /// In en, this message translates to:
  /// **'Spring Festival'**
  String get holidayNameSpringFestival;

  /// No description provided for @holidayNameQingming.
  ///
  /// In en, this message translates to:
  /// **'Qingming Festival'**
  String get holidayNameQingming;

  /// No description provided for @holidayNameLabourDay.
  ///
  /// In en, this message translates to:
  /// **'Labour Day'**
  String get holidayNameLabourDay;

  /// No description provided for @holidayNameDragonBoat.
  ///
  /// In en, this message translates to:
  /// **'Dragon Boat Festival'**
  String get holidayNameDragonBoat;

  /// No description provided for @holidayNameMidAutumn.
  ///
  /// In en, this message translates to:
  /// **'Mid-Autumn Festival'**
  String get holidayNameMidAutumn;

  /// No description provided for @holidayNameNationalDay.
  ///
  /// In en, this message translates to:
  /// **'National Day'**
  String get holidayNameNationalDay;

  /// No description provided for @holidayNameNationalDayMidAutumn.
  ///
  /// In en, this message translates to:
  /// **'National Day & Mid-Autumn Festival'**
  String get holidayNameNationalDayMidAutumn;

  /// No description provided for @holidayMakeupTitle.
  ///
  /// In en, this message translates to:
  /// **'Makeup workday today'**
  String get holidayMakeupTitle;

  /// No description provided for @holidayMakeupAsk.
  ///
  /// In en, this message translates to:
  /// **'Making up for {name}. Which weekday\'s timetable applies today?'**
  String holidayMakeupAsk(String name);

  /// No description provided for @holidayMakeupResolved.
  ///
  /// In en, this message translates to:
  /// **'Following the {weekday} timetable'**
  String holidayMakeupResolved(String weekday);

  /// No description provided for @holidayMakeupNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed yet — lesson counts will use today\'s weekday'**
  String get holidayMakeupNotSet;

  /// No description provided for @holidayMakeupSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get holidayMakeupSet;

  /// No description provided for @holidayShiftTitle.
  ///
  /// In en, this message translates to:
  /// **'Which weekday\'s timetable?'**
  String get holidayShiftTitle;

  /// No description provided for @holidayShiftBody.
  ///
  /// In en, this message translates to:
  /// **'Follow your school\'s notice. Lesson counts for this day will use your choice.'**
  String get holidayShiftBody;

  /// No description provided for @holidayShiftNone.
  ///
  /// In en, this message translates to:
  /// **'No change (use the weekday itself)'**
  String get holidayShiftNone;

  /// No description provided for @holidayShiftSaved.
  ///
  /// In en, this message translates to:
  /// **'Now counting the {weekday} timetable'**
  String holidayShiftSaved(String weekday);

  /// No description provided for @holidayShiftCleared.
  ///
  /// In en, this message translates to:
  /// **'Back to no adjustment'**
  String get holidayShiftCleared;

  /// No description provided for @holidayOutsideCoverage.
  ///
  /// In en, this message translates to:
  /// **'Holiday schedule for {year} isn\'t bundled yet — weekends only for now'**
  String holidayOutsideCoverage(int year);

  /// No description provided for @holidayFreeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} days off this week'**
  String holidayFreeCount(int count);

  /// No description provided for @holidayMakeupCount.
  ///
  /// In en, this message translates to:
  /// **'{count} makeup workdays this week'**
  String holidayMakeupCount(int count);

  /// No description provided for @toolboxOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get toolboxOverviewTitle;

  /// No description provided for @toolboxTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get toolboxTodayTitle;

  /// No description provided for @insightWeekLessons.
  ///
  /// In en, this message translates to:
  /// **'Teaching days'**
  String get insightWeekLessons;

  /// No description provided for @insightTotalLessons.
  ///
  /// In en, this message translates to:
  /// **'Total lessons'**
  String get insightTotalLessons;

  /// No description provided for @insightFocusCount.
  ///
  /// In en, this message translates to:
  /// **'Focus sessions'**
  String get insightFocusCount;

  /// No description provided for @insightTodayLessons.
  ///
  /// In en, this message translates to:
  /// **'Today\'s lessons'**
  String get insightTodayLessons;

  /// No description provided for @insightTodayNoLesson.
  ///
  /// In en, this message translates to:
  /// **'No lessons today'**
  String get insightTodayNoLesson;

  /// No description provided for @insightUnitDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String insightUnitDays(int count);

  /// No description provided for @insightUnitLessons.
  ///
  /// In en, this message translates to:
  /// **'{count} lessons'**
  String insightUnitLessons(int count);

  /// No description provided for @insightUnitPeriods.
  ///
  /// In en, this message translates to:
  /// **'{count} periods'**
  String insightUnitPeriods(int count);

  /// No description provided for @insightUnitTimes.
  ///
  /// In en, this message translates to:
  /// **'{count} times'**
  String insightUnitTimes(int count);

  /// No description provided for @insightUnitCourses.
  ///
  /// In en, this message translates to:
  /// **'{count} courses'**
  String insightUnitCourses(int count);

  /// No description provided for @insightFocusMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes in total'**
  String insightFocusMinutes(int minutes);

  /// No description provided for @insightFocusNoRecord.
  ///
  /// In en, this message translates to:
  /// **'No focus session yet'**
  String get insightFocusNoRecord;

  /// No description provided for @insightSectionLessons.
  ///
  /// In en, this message translates to:
  /// **'Lesson distribution'**
  String get insightSectionLessons;

  /// No description provided for @insightSectionAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get insightSectionAttendance;

  /// No description provided for @insightSectionFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus time'**
  String get insightSectionFocus;

  /// No description provided for @insightSectionEvents.
  ///
  /// In en, this message translates to:
  /// **'Extra affairs'**
  String get insightSectionEvents;

  /// No description provided for @insightSectionLessonsDesc.
  ///
  /// In en, this message translates to:
  /// **'Per day and per course'**
  String get insightSectionLessonsDesc;

  /// No description provided for @insightSectionAttendanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Rates and the class to watch'**
  String get insightSectionAttendanceDesc;

  /// No description provided for @insightSectionEventsDesc.
  ///
  /// In en, this message translates to:
  /// **'Events from your calendar'**
  String get insightSectionEventsDesc;

  /// No description provided for @insightDoneOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String insightDoneOfTotal(int done, int total);

  /// No description provided for @insightPerDayTitle.
  ///
  /// In en, this message translates to:
  /// **'Lessons per day'**
  String get insightPerDayTitle;

  /// No description provided for @insightPerCourseTitle.
  ///
  /// In en, this message translates to:
  /// **'By course'**
  String get insightPerCourseTitle;

  /// No description provided for @insightBestClass.
  ///
  /// In en, this message translates to:
  /// **'Best attendance'**
  String get insightBestClass;

  /// No description provided for @insightWorstClass.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get insightWorstClass;

  /// No description provided for @insightClassRate.
  ///
  /// In en, this message translates to:
  /// **'{rate}% · {total} records'**
  String insightClassRate(int rate, int total);

  /// No description provided for @insightNoClassData.
  ///
  /// In en, this message translates to:
  /// **'No roll call recorded this week'**
  String get insightNoClassData;

  /// No description provided for @insightSingleClass.
  ///
  /// In en, this message translates to:
  /// **'Only one class had roll call this week'**
  String get insightSingleClass;

  /// No description provided for @insightEventsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No extra affairs this week'**
  String get insightEventsEmpty;

  /// No description provided for @insightEventWithLocation.
  ///
  /// In en, this message translates to:
  /// **'{title} · {location}'**
  String insightEventWithLocation(String title, String location);

  /// No description provided for @insightNoLessonThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled this week'**
  String get insightNoLessonThisWeek;

  /// No description provided for @insightUnitMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String insightUnitMinutes(int count);

  /// No description provided for @insightUnitStudents.
  ///
  /// In en, this message translates to:
  /// **'{count} students'**
  String insightUnitStudents(int count);

  /// No description provided for @insightFocusTotal.
  ///
  /// In en, this message translates to:
  /// **'Total focus'**
  String get insightFocusTotal;

  /// No description provided for @insightFocusAverage.
  ///
  /// In en, this message translates to:
  /// **'Avg. per session'**
  String get insightFocusAverage;

  /// No description provided for @insightTodayEventsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} events today'**
  String insightTodayEventsCount(int count);

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @yearMonth.
  ///
  /// In en, this message translates to:
  /// **'{month}/{year}'**
  String yearMonth(int year, int month);

  /// No description provided for @eventDayTitle.
  ///
  /// In en, this message translates to:
  /// **'Events on this day'**
  String get eventDayTitle;

  /// No description provided for @holidayAwareSwitch.
  ///
  /// In en, this message translates to:
  /// **'Holidays & makeup days'**
  String get holidayAwareSwitch;

  /// No description provided for @holidayAwareDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip holidays in lesson counts, count makeup workdays, and remind you which weekday\'s timetable applies'**
  String get holidayAwareDesc;

  /// No description provided for @insightUnitItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String insightUnitItems(int count);

  /// No description provided for @holidayRemoteSwitch.
  ///
  /// In en, this message translates to:
  /// **'Fetch holiday calendars automatically'**
  String get holidayRemoteSwitch;

  /// No description provided for @holidayRemoteDesc.
  ///
  /// In en, this message translates to:
  /// **'Picks up next year\'s holidays automatically; built-in data still works'**
  String get holidayRemoteDesc;

  /// No description provided for @holidayDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Holiday data'**
  String get holidayDataTitle;

  /// No description provided for @holidayDataUnknown.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get holidayDataUnknown;

  /// No description provided for @holidayDataSummary.
  ///
  /// In en, this message translates to:
  /// **'Covers {years}'**
  String holidayDataSummary(String years);

  /// No description provided for @holidayDataSummaryChecked.
  ///
  /// In en, this message translates to:
  /// **'Covers {years} · last checked {date}'**
  String holidayDataSummaryChecked(String years, String date);

  /// No description provided for @holidaySyncNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get holidaySyncNow;

  /// No description provided for @holidaySyncUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated holidays for {years}'**
  String holidaySyncUpdated(String years);

  /// No description provided for @holidaySyncNotPublished.
  ///
  /// In en, this message translates to:
  /// **'{years} isn\'t published yet — it will be fetched automatically'**
  String holidaySyncNotPublished(String years);

  /// No description provided for @holidaySyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t fetch — check your connection and try again'**
  String get holidaySyncFailed;

  /// No description provided for @holidaySyncUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get holidaySyncUpToDate;

  /// No description provided for @holidaySyncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic fetching is off — turn it on above first'**
  String get holidaySyncDisabled;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Software update'**
  String get updateTitle;

  /// No description provided for @updateCurrentVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed version'**
  String get updateCurrentVersionLabel;

  /// No description provided for @updateVersionWithBuild.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {code})'**
  String updateVersionWithBuild(String version, int code);

  /// No description provided for @updateVersionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Version unavailable'**
  String get updateVersionUnknown;

  /// No description provided for @updateInstallBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'\"Install unknown apps\" permission needed'**
  String get updateInstallBlockedTitle;

  /// No description provided for @updateInstallBlockedDesc.
  ///
  /// In en, this message translates to:
  /// **'Android must allow this app to install apps, otherwise the install is rejected'**
  String get updateInstallBlockedDesc;

  /// No description provided for @updateGrantInstall.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get updateGrantInstall;

  /// No description provided for @updateRecheck.
  ///
  /// In en, this message translates to:
  /// **'I\'ve granted it'**
  String get updateRecheck;

  /// No description provided for @updateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'In-app updates aren\'t available on this platform'**
  String get updateUnsupported;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateDownloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloadingPercent(int percent);

  /// No description provided for @updateFellBackToFull.
  ///
  /// In en, this message translates to:
  /// **'Delta update didn\'t work — switched to the full package'**
  String get updateFellBackToFull;

  /// No description provided for @updateAssembling.
  ///
  /// In en, this message translates to:
  /// **'Building the new version from the installed package…'**
  String get updateAssembling;

  /// No description provided for @updateAssemblingHint.
  ///
  /// In en, this message translates to:
  /// **'No extra download needed — this runs on your device'**
  String get updateAssemblingHint;

  /// No description provided for @updateInstallingHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm the install in the system dialog'**
  String get updateInstallingHint;

  /// No description provided for @updateInstalledHint.
  ///
  /// In en, this message translates to:
  /// **'Installed — restart the app to use it'**
  String get updateInstalledHint;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get updateUpToDate;

  /// No description provided for @updateCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get updateCheckAgain;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateAvailableTitle(String version);

  /// No description provided for @updateDeltaBadge.
  ///
  /// In en, this message translates to:
  /// **'Delta'**
  String get updateDeltaBadge;

  /// No description provided for @updateFullBadge.
  ///
  /// In en, this message translates to:
  /// **'Full package'**
  String get updateFullBadge;

  /// No description provided for @updateSizeWithDelta.
  ///
  /// In en, this message translates to:
  /// **'Download {download} (full package is {full})'**
  String updateSizeWithDelta(String download, String full);

  /// No description provided for @updateSizeFull.
  ///
  /// In en, this message translates to:
  /// **'Download {full}'**
  String updateSizeFull(String full);

  /// No description provided for @updateSavedHint.
  ///
  /// In en, this message translates to:
  /// **'{saved} less than the full package — about {percent}% saved'**
  String updateSavedHint(String saved, int percent);

  /// No description provided for @updateChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateChangesTitle;

  /// No description provided for @updateNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No release notes for this version'**
  String get updateNoChanges;

  /// No description provided for @updateDownloadDelta.
  ///
  /// In en, this message translates to:
  /// **'Update with delta'**
  String get updateDownloadDelta;

  /// No description provided for @updateDownloadFull.
  ///
  /// In en, this message translates to:
  /// **'Download & install'**
  String get updateDownloadFull;

  /// No description provided for @updateSkipVersion.
  ///
  /// In en, this message translates to:
  /// **'Skip this version'**
  String get updateSkipVersion;

  /// No description provided for @updateSkipConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You won\'t be reminded about {version} again — a newer release will prompt you'**
  String updateSkipConfirmBody(String version);

  /// No description provided for @updateSkippedHint.
  ///
  /// In en, this message translates to:
  /// **'Skipped — you\'ll be notified about newer releases'**
  String get updateSkippedHint;

  /// No description provided for @updateReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'New version is ready'**
  String get updateReadyTitle;

  /// No description provided for @updateReadyDeltaHint.
  ///
  /// In en, this message translates to:
  /// **'Built on this device — hand it to the system installer'**
  String get updateReadyDeltaHint;

  /// No description provided for @updateReadyFullHint.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and verified — tap to install'**
  String get updateReadyFullHint;

  /// No description provided for @updateInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get updateInstallNow;

  /// No description provided for @updateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get updateRetry;

  /// No description provided for @updateFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server — check your connection'**
  String get updateFailureNetwork;

  /// No description provided for @updateFailureManifest.
  ///
  /// In en, this message translates to:
  /// **'Version information is unavailable right now'**
  String get updateFailureManifest;

  /// No description provided for @updateFailureAssetMissing.
  ///
  /// In en, this message translates to:
  /// **'This release has no package for your device\'s architecture'**
  String get updateFailureAssetMissing;

  /// No description provided for @updateFailureHash.
  ///
  /// In en, this message translates to:
  /// **'The download failed verification and was discarded'**
  String get updateFailureHash;

  /// No description provided for @updateFailureDelta.
  ///
  /// In en, this message translates to:
  /// **'The rebuilt package failed verification'**
  String get updateFailureDelta;

  /// No description provided for @updateFailureNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage'**
  String get updateFailureNoSpace;

  /// No description provided for @updateFailureInstallBlocked.
  ///
  /// In en, this message translates to:
  /// **'This app isn\'t allowed to install apps yet'**
  String get updateFailureInstallBlocked;

  /// No description provided for @updateFailureInstallRejected.
  ///
  /// In en, this message translates to:
  /// **'The system rejected the install'**
  String get updateFailureInstallRejected;

  /// No description provided for @updateFailureUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get updateFailureUnknown;

  /// No description provided for @updateMirrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Download mirror'**
  String get updateMirrorTitle;

  /// No description provided for @updateMirrorDesc.
  ///
  /// In en, this message translates to:
  /// **'GitHub downloads can be slow on some networks. Add proxy prefixes (one per line); they\'re tried after the direct URL'**
  String get updateMirrorDesc;

  /// No description provided for @updateMirrorHint.
  ///
  /// In en, this message translates to:
  /// **'https://your-proxy/'**
  String get updateMirrorHint;

  /// No description provided for @updateMirrorSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved — check for updates again'**
  String get updateMirrorSaved;

  /// No description provided for @updateSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Installed {version}'**
  String updateSettingsSubtitle(String version);

  /// No description provided for @updateSettingsSubtitleAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} available'**
  String updateSettingsSubtitleAvailable(String version);

  /// No description provided for @attendanceResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Resume roll call?'**
  String get attendanceResumeTitle;

  /// No description provided for @attendanceResumeBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is currently suspended. Resuming restores normal roll call.'**
  String attendanceResumeBody(String name);

  /// No description provided for @attendanceResumeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get attendanceResumeConfirm;

  /// No description provided for @gridMakeupHint.
  ///
  /// In en, this message translates to:
  /// **'{date} make-up workday · {weekday} schedule'**
  String gridMakeupHint(String date, String weekday);

  /// No description provided for @attendanceLegendMakeup.
  ///
  /// In en, this message translates to:
  /// **'Make-up workday'**
  String get attendanceLegendMakeup;

  /// No description provided for @attendanceLegendHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get attendanceLegendHoliday;

  /// No description provided for @attendanceLegendNoRecord.
  ///
  /// In en, this message translates to:
  /// **'Not marked'**
  String get attendanceLegendNoRecord;

  /// No description provided for @attendanceLegendRate.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendanceLegendRate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

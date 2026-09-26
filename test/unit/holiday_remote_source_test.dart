import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/services/china_holiday_calendar.dart';
import 'package:schedule_plan/data/services/holiday_remote_source.dart';

/// 把一段放假区间摊成 holiday-cn 那种逐日条目。
List<Map<String, dynamic>> _offDayRange(String from, String to) {
  final result = <Map<String, dynamic>>[];
  var day = DateTime.parse(from);
  final end = DateTime.parse(to);
  while (!day.isAfter(end)) {
    // 名字随便给：这一组用例只关心"哪几天放假、哪几天补班"
    result.add(<String, dynamic>{
      'name': '假',
      'date': _format(day),
      'isOffDay': true,
    });
    day = day.add(const Duration(days: 1));
  }
  return result;
}

List<Map<String, dynamic>> _makeupDays(List<String> dates) => dates
    .map((date) => <String, dynamic>{
          'name': '班',
          'date': date,
          'isOffDay': false,
        })
    .toList();

String _format(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

void main() {
  setUp(ChinaHolidayCalendar.resetOverride);

  group('parseTimorYear', () {
    test('type 段认四态：2=放假、3=调休上班；0/1 是"天生"属性不入表', () {
      final days = parseTimorYear(<String, dynamic>{
        'code': 0,
        'type': <String, dynamic>{
          '2027-01-01': <String, dynamic>{'type': 2, 'name': '元旦', 'week': 5},
          '2027-01-04': <String, dynamic>{'type': 0, 'name': '周一', 'week': 1},
          '2027-02-06': <String, dynamic>{'type': 3, 'name': '春节调休', 'week': 6},
          '2027-02-07': <String, dynamic>{'type': 1, 'name': '周日', 'week': 7},
        },
      });

      expect(days.length, 2, reason: '只该留下 type=2 和 3 那两天');
      expect(days['2027-01-01']?.kind, CalendarDayKind.holiday);
      expect(days['2027-01-01']?.name, HolidayName.newYear);
      expect(days['2027-02-06']?.kind, CalendarDayKind.makeupWorkday);
      expect(days.containsKey('2027-01-04'), isFalse);
      expect(days.containsKey('2027-02-07'), isFalse);
    });

    test('同一天两段都有时听 type 段的——它能认出调休，holiday 段只会说"放假"', () {
      final days = parseTimorYear(<String, dynamic>{
        'type': <String, dynamic>{
          '2027-01-04': <String, dynamic>{'type': 3, 'name': '元旦调休'},
        },
        'holiday': <String, dynamic>{
          '01-04': <String, dynamic>{
            'holiday': true,
            'name': '元旦',
            'date': '2027-01-04',
          },
        },
      });

      expect(
        days['2027-01-04']?.kind,
        CalendarDayKind.makeupWorkday,
        reason: '顺序反了的话调休会被降级成放假，那正是最要命的一天',
      );
    });

    test('没有 type 段时用 holiday 段兜底，年份从 payload.date 补齐', () {
      final days = parseTimorYear(<String, dynamic>{
        'holiday': <String, dynamic>{
          '10-01': <String, dynamic>{
            'holiday': true,
            'name': '国庆节',
            'date': '2027-10-01',
          },
          '10-02': <String, dynamic>{
            'holiday': true,
            'name': '国庆节',
            'date': '2027-10-02',
          },
        },
      });

      expect(days.length, 2);
      expect(days['2027-10-01']?.kind, CalendarDayKind.holiday);
      expect(days['2027-10-01']?.name, HolidayName.nationalDay);
    });

    test('某年还没公布 → 两段都空 → 返回空表，不抛异常', () {
      expect(parseTimorYear(<String, dynamic>{'code': 0}), isEmpty);
      expect(
        parseTimorYear(<String, dynamic>{
          'code': 0,
          'holiday': <String, dynamic>{},
          'type': <String, dynamic>{},
        }),
        isEmpty,
      );
    });

    test('脏数据一律不进表：日期格式不对 / payload 不是对象 / 码不认识 / 缺年份', () {
      final days = parseTimorYear(<String, dynamic>{
        'type': <String, dynamic>{
          '2027/01/01': <String, dynamic>{'type': 2},
          '2027-01-02': 'not-a-map',
          '2027-01-03': <String, dynamic>{'type': 9},
        },
        'holiday': <String, dynamic>{
          // 缺 date，年份补不出来 —— 宁可少一天，也不要猜出一个错的年份
          '01-05': <String, dynamic>{'holiday': true, 'name': '元旦'},
        },
      });

      expect(days, isEmpty);
    });

    test('type 码是字符串也能认（有的网关会把数字序列化成字符串）', () {
      final days = parseTimorYear(<String, dynamic>{
        'type': <String, dynamic>{
          '2027-01-01': <String, dynamic>{'type': '2', 'name': '元旦'},
        },
      });
      expect(days['2027-01-01']?.kind, CalendarDayKind.holiday);
    });

    test('「国庆节、中秋节」连放要认成合体假，不能只算国庆', () {
      final days = parseTimorYear(<String, dynamic>{
        'type': <String, dynamic>{
          '2028-10-03': <String, dynamic>{'type': 2, 'name': '国庆节、中秋节'},
        },
      });
      expect(days['2028-10-03']?.name, HolidayName.nationalDayMidAutumn);
    });

    test('认不出的节日名只丢名字、不丢这条数据', () {
      final days = parseTimorYear(<String, dynamic>{
        'type': <String, dynamic>{
          '2027-03-08': <String, dynamic>{'type': 2, 'name': '某某纪念日'},
        },
      });
      expect(days['2027-03-08']?.kind, CalendarDayKind.holiday);
      expect(days['2027-03-08']?.name, isNull);
    });
  });

  group('parseHolidayCnYear', () {
    test('isOffDay=true 认放假、false 认调休上班', () {
      final days = parseHolidayCnYear(<String, dynamic>{
        'year': 2027,
        'days': <dynamic>[
          <String, dynamic>{
            'name': '元旦',
            'date': '2027-01-01',
            'isOffDay': true,
          },
          <String, dynamic>{
            'name': '元旦',
            'date': '2027-01-04',
            'isOffDay': false,
          },
        ],
      });

      expect(days.length, 2);
      expect(days['2027-01-01']?.kind, CalendarDayKind.holiday);
      expect(days['2027-01-04']?.kind, CalendarDayKind.makeupWorkday);
    });

    test('结构不对时安静地返回空表，不抛异常', () {
      expect(parseHolidayCnYear(<String, dynamic>{}), isEmpty);
      expect(parseHolidayCnYear(<String, dynamic>{'days': 'nope'}), isEmpty);
      expect(
        parseHolidayCnYear(<String, dynamic>{
          'days': <dynamic>[
            'not-a-map',
            <String, dynamic>{'date': '2027-01-01'},
            <String, dynamic>{'date': 'bogus', 'isOffDay': true},
          ],
        }),
        isEmpty,
      );
    });
  });

  group('远程解析与内置表交叉校验', () {
    test('2026 年按通知展开的结果，与内置常量表逐日一致', () {
      // 国办发明电〔2025〕7 号（2025-11-04 发布）——和内置表是同一份来源，
      // 所以两边必须严丝合缝。对不上就说明有一边抄错了。
      final remote = parseHolidayCnYear(<String, dynamic>{
        'year': 2026,
        'days': <dynamic>[
          ..._offDayRange('2026-01-01', '2026-01-03'),
          ..._offDayRange('2026-02-15', '2026-02-23'),
          ..._offDayRange('2026-04-04', '2026-04-06'),
          ..._offDayRange('2026-05-01', '2026-05-05'),
          ..._offDayRange('2026-06-19', '2026-06-21'),
          ..._offDayRange('2026-09-25', '2026-09-27'),
          ..._offDayRange('2026-10-01', '2026-10-07'),
          ..._makeupDays(<String>[
            '2026-01-04',
            '2026-02-14',
            '2026-02-28',
            '2026-05-09',
            '2026-09-20',
            '2026-10-10',
          ]),
        ],
      });

      final builtin = <String, CalendarDayKind>{};
      for (var day = DateTime(2026, 1, 1);
          day.year == 2026;
          day = day.add(const Duration(days: 1))) {
        final info = ChinaHolidayCalendar.infoOf(day);
        if (info != null) {
          builtin[info.date] = info.kind;
        }
      }

      expect(
        remote.map((key, value) => MapEntry<String, CalendarDayKind>(key, value.kind)),
        equals(builtin),
        reason: '远程按通知展开的结果与内置常量表对不上，有一边抄错了',
      );
      expect(builtin.length, 39, reason: '2026 年应有 33 天放假 + 6 天补班');
    });
  });
}

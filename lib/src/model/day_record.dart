import '../util/day.dart';

/// Recorded steps for one local day.
///
/// The *absence* of a record means "unknown" (no data) — distinct from a
/// record with `steps == 0`, which is a known day without steps.
class DayRecord {
  const DayRecord(this.day, this.steps, {this.complete = true});

  final Day day;
  final int steps;

  /// `true` when tracking covered the whole day, so [steps] is reliable.
  /// `false` when part of the day is unknown (tracking started mid-day,
  /// an unexpected reboot, ambiguous steps across midnight…). Incomplete
  /// days are still displayed, but excluded from the daily average.
  final bool complete;

  DayRecord copyWith({int? steps, bool? complete}) =>
      DayRecord(day, steps ?? this.steps, complete: complete ?? this.complete);

  @override
  bool operator ==(Object other) =>
      other is DayRecord &&
      other.day == day &&
      other.steps == steps &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(day, steps, complete);

  @override
  String toString() => 'DayRecord($day, $steps${complete ? '' : ', partial'})';
}

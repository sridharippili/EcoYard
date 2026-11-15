import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

PlanEntry entry(
  String id, {
  List<String> birds = const ['norcar'],
  String added = '2026-11-14T10:00:00Z',
  String? done,
}) =>
    PlanEntry(
      actionId: id,
      birdIds: birds,
      addedOn: added,
      doneOn: done,
      titleSnapshot: 'Snapshot title $id',
      bodySnapshot: 'Snapshot body $id',
      costSnapshot: 'free',
    );

void main() {
  final repo = ReferenceRepository.fromJson(realContent());

  test('to-do items come before done items', () {
    final v = buildPlanView([
      entry('add-water-source', done: '2026-11-15T10:00:00Z'),
      entry('leave-leaf-litter', added: '2026-11-14T11:00:00Z'),
    ], repo);
    expect(v.items.map((i) => i.entry.actionId),
        ['leave-leaf-litter', 'add-water-source']);
    expect(v.items.map((i) => i.isDone), [false, true]);
  });

  test('order inside a group is oldest first, then id, not alphabetical', () {
    final v = buildPlanView([
      entry('b-late', added: '2026-11-14T12:00:00Z'),
      entry('z-early', added: '2026-11-14T09:00:00Z'),
      entry('a-same-time-a', added: '2026-11-14T10:00:00Z'),
      entry('a-same-time-b', added: '2026-11-14T10:00:00Z'),
    ], repo);
    expect(v.items.map((i) => i.entry.actionId),
        ['z-early', 'a-same-time-a', 'a-same-time-b', 'b-late']);
  });

  test('dates of different precision are compared as times, not text', () {
    final v = buildPlanView([
      entry('later', added: '2026-11-14T10:00:00Z'),
      entry('earlier', added: '2026-11-14T09:59:59.999999Z'),
      entry('same-second-micro', added: '2026-11-14T10:00:00.000001Z'),
    ], repo);
    expect(v.items.map((i) => i.entry.actionId),
        ['earlier', 'later', 'same-second-micro']);
  });

  test('unparseable dates do not crash the ordering', () {
    final v = buildPlanView([
      entry('b', added: 'not a date'),
      entry('a', added: 'also not'),
    ], repo);
    expect(v.items, hasLength(2));
  });

  test('entries with no birds and a done date but no content still show', () {
    final v = buildPlanView([
      entry('gone', birds: const [], done: '2026-11-15T00:00:00Z'),
    ], repo);
    expect(v.items.single.birds, isEmpty);
    expect(v.items.single.unknownBirdCount, 0);
    expect(v.progress.done, 1);
  });

  test('ticking one item does not reorder the others', () {
    final open = [
      entry('x1', added: '2026-11-14T09:00:00Z'),
      entry('x2', added: '2026-11-14T10:00:00Z'),
      entry('x3', added: '2026-11-14T11:00:00Z'),
    ];
    final before = buildPlanView(open, repo);
    final after = buildPlanView([
      open[0],
      entry('x2', added: '2026-11-14T10:00:00Z', done: '2026-11-15T00:00:00Z'),
      open[2],
    ], repo);
    expect(before.items.map((i) => i.entry.actionId), ['x1', 'x2', 'x3']);
    expect(after.items.map((i) => i.entry.actionId), ['x1', 'x3', 'x2']);
  });

  test('progress counts done and total, including removed actions', () {
    final v = buildPlanView([
      entry('add-water-source', done: '2026-11-15T10:00:00Z'),
      entry('gone-action'),
      entry('leave-leaf-litter'),
    ], repo);
    expect(v.progress.done, 1);
    expect(v.progress.total, 3);
    expect(v.progress.fraction, closeTo(1 / 3, 1e-9));
  });

  test('empty plan has zero progress, not a division error', () {
    final v = buildPlanView(const [], repo);
    expect(v.items, isEmpty);
    expect(v.progress.fraction, 0);
  });

  test('an action missing from the content shows its snapshot', () {
    final v = buildPlanView([entry('gone-action')], repo);
    final item = v.items.single;
    expect(item.isRemovedFromContent, isTrue);
    expect(item.title, 'Snapshot title gone-action');
    expect(item.body, 'Snapshot body gone-action');
    expect(item.costJson, 'free');
  });

  test('a known action shows today\'s content, not the snapshot', () {
    final v = buildPlanView([entry('add-water-source')], repo);
    final item = v.items.single;
    expect(item.isRemovedFromContent, isFalse);
    expect(item.title, repo.actionById('add-water-source')!.title);
    expect(item.title, isNot(startsWith('Snapshot')));
  });

  test('birds are listed; unknown birds are counted, not dropped silently', () {
    final v = buildPlanView([
      entry('add-water-source', birds: ['norcar', 'ghost', 'amegfi']),
    ], repo);
    final item = v.items.single;
    expect(item.birds.map((b) => b.id), ['norcar', 'amegfi']);
    expect(item.unknownBirdCount, 1);
  });

  test('a candidate copies the action text and cost', () {
    final a = repo.actionById('add-water-source')!;
    final c = PlanCandidate.fromAction(a);
    expect(c.actionId, a.id);
    expect(c.title, a.title);
    expect(c.body, a.body);
    expect(c.costTier, a.costTier);
  });
}

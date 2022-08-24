// ignore_for_file: prefer_expression_function_bodies

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:taskc/taskc.dart';
import 'package:taskj/json.dart';

import 'package:taskw/taskw.dart';

class Data {
  Data(this.home);

  final Directory home;

  void updateWaitOrUntil(Iterable<Task> pendingData) {
    var now = DateTime.now().toUtc();
    for (var task in pendingData) {
      if (task.until != null && task.until!.isBefore(now)) {
        mergeTask(
          task.rebuild(
            (b) => b
              ..status = 'deleted'
              ..end = now,
          ),
        );
      } else if (task.status == 'waiting' &&
          (task.wait == null || task.wait!.isBefore(now))) {
        _mergeTasks(
          [
            task.rebuild(
              (b) => b
                ..status = 'pending'
                ..wait = null,
            ),
          ],
        );
      }
    }
  }

  List<Task> pendingData() {
    var data = _allData().where(
        (task) => task.status != 'completed' && task.status != 'deleted');
    var now = DateTime.now();
    if (data.any((task) =>
        (task.until != null && task.until!.isBefore(now)) ||
        (task.status == 'waiting' &&
            (task.wait == null || task.wait!.isBefore(now))))) {
      updateWaitOrUntil(data);
      data = _allData().where(
          (task) => task.status != 'completed' && task.status != 'deleted');
    }
    return data
        .toList()
        .asMap()
        .entries
        .map((entry) => entry.value.rebuild((b) => b..id = entry.key + 1))
        .toList();
  }

  List<Task> _completedData() {
    var data = _allData().where(
        (task) => task.status == 'completed' || task.status == 'deleted');
    return [
      for (var task in data) task.rebuild((b) => b..id = 0),
    ];
  }

  List<Task> allData() {
    var data = pendingData()..addAll(_completedData());
    return data;
  }

  List<Task> _allData() => [
        if (File('${home.path}/.task/all.data').existsSync())
          for (var line in File('${home.path}/.task/all.data')
              .readAsStringSync()
              .trim()
              .split('\n'))
            if (line.isNotEmpty) Task.fromJson(json.decode(line)),
      ];

  String export() {
    var string = allData()
        .map((task) {
          var _task = task.toJson();

          _task['urgency'] = num.parse(urgency(task)
              .toStringAsFixed(1)
              .replaceFirst(RegExp(r'.0$'), ''));

          var keyOrder = [
            'id',
            'annotations',
            'depends',
            'description',
            'due',
            'end',
            'entry',
            'imask',
            'mask',
            'modified',
            'parent',
            'priority',
            'project',
            'recur',
            'scheduled',
            'start',
            'status',
            'tags',
            'until',
            'uuid',
            'wait',
            'urgency',
          ].asMap().map((key, value) => MapEntry(value, key));

          var fallbackOrder = _task.keys
              .toList()
              .asMap()
              .map((key, value) => MapEntry(value, key));

          for (var entry in fallbackOrder.entries) {
            keyOrder.putIfAbsent(
              entry.key,
              () => entry.value + keyOrder.length,
            );
          }

          return json.encode(SplayTreeMap.of(_task, (key1, key2) {
            return keyOrder[key1]!.compareTo(keyOrder[key2]!);
          }));
        })
        .toList()
        .join(',\n');
    return '[\n$string\n]\n';
  }

  void mergeTask(Task task) {
    _mergeTasks([task]);
    File('${home.path}/.task/backlog.data').writeAsStringSync(
      '${json.encode(task.rebuild((b) => b..id = null).toJson())}\n',
      mode: FileMode.append,
    );
  }

  Task getTask(String uuid) {
    return allData().firstWhere((task) => task.uuid == uuid);
  }

  void _mergeTasks(List<Task> tasks) {
    File('${home.path}/.task/all.data').createSync(recursive: true);
    var lines = File('${home.path}/.task/all.data')
        .readAsStringSync()
        .trim()
        .split('\n');
    var taskMap = {
      for (var taskLine in lines)
        if (taskLine.isNotEmpty)
          (json.decode(taskLine) as Map)['uuid']: taskLine,
    };
    for (var task in tasks) {
      taskMap[task.uuid] =
          json.encode(task.rebuild((b) => b..id = null).toJson());
    }
    File('${home.path}/.task/all.data').writeAsStringSync('');
    for (var task in taskMap.values) {
      File('${home.path}/.task/all.data').writeAsStringSync(
        '$task\n',
        mode: FileMode.append,
      );
    }
  }

  String payload() {
    var _payload = '';
    if (File('${home.path}/.task/backlog.data').existsSync()) {
      _payload = File('${home.path}/.task/backlog.data').readAsStringSync();
    }
    return _payload;
  }

  void mergeSynchronizeResponse(Payload payload) {
    var tasks = [
      for (var task in payload.tasks)
        Task.fromJson(
            (json.decode(task) as Map<String, dynamic>)..remove('id')),
    ];
    _mergeTasks(tasks);
    File('${home.path}/.task/backlog.data')
        .writeAsStringSync('${payload.userKey}\n');
  }
}

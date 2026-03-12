import 'dart:convert';
import 'dart:io';
import 'dart:math';

part 'p1_aggregate/p1_aggregate_models.dart';
part 'p1_aggregate/p1_aggregate_io.dart';
part 'p1_aggregate/p1_aggregate_aggregate.dart';
part 'p1_aggregate/p1_aggregate_render.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final kvArgs = _parseArgs(args);
    final options = _buildOptions(kvArgs);
    final allFiles = _collectJsonFiles(options.inputDir);
    final reports = <_BenchReport>[];
    final samples = <_ChannelSample>[];

    for (final file in allFiles) {
      final parsed = _tryParseReport(file.path, options: options);
      if (parsed == null) {
        continue;
      }
      reports.add(parsed);
      samples.addAll(parsed.samples);
    }

    stdout.writeln(
      '[p1-aggregate] scannedFiles=${allFiles.length} '
      'matchedReports=${reports.length} '
      'samples=${samples.length}',
    );

    if (samples.isEmpty) {
      stderr.writeln('[p1-aggregate] no matched benchmark reports found.');
      stderr.writeln(
        '[p1-aggregate] input=${options.inputDir.path} '
        'scenario=${options.scenario} '
        'consumeMode=${options.consumeModeFilter ?? 'any'}',
      );
      exitCode = 2;
      return;
    }

    final statsByChannelKey = _aggregateChannelStats(samples);
    final pairRows = _buildPairRows(statsByChannelKey);
    final markdown = _buildMarkdown(
      options: options,
      reports: reports,
      samples: samples,
      pairRows: pairRows,
    );

    stdout.writeln(markdown);

    if (options.outputMarkdown != null) {
      await options.outputMarkdown!.parent.create(recursive: true);
      await options.outputMarkdown!.writeAsString(markdown);
      stdout.writeln(
        '[p1-aggregate] markdown saved to ${options.outputMarkdown!.path}',
      );
    }

    if (options.outputJson != null) {
      final summary = _buildJsonSummary(
        options: options,
        reports: reports,
        samples: samples,
        pairRows: pairRows,
      );
      await options.outputJson!.parent.create(recursive: true);
      await options.outputJson!.writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      stdout.writeln(
        '[p1-aggregate] json saved to ${options.outputJson!.path}',
      );
    }
  } catch (error) {
    stderr.writeln('[p1-aggregate] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
}

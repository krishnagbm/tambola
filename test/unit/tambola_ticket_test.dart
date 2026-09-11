import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/utils/tambola_ticket.dart';

void main() {
  group('TambolaTicketHelper', () {
    test('generateTicket produces valid 3x9 grid with exactly 15 numbers across 250 generations with uniqueness', () {
      final generatedTickets = <String>{};

      for (int i = 0; i < 250; i++) {
        final ticket = TambolaTicketHelper.generateTicket();

        expect(ticket.length, 3);
        for (final row in ticket) {
          expect(row.length, 9);
        }

        final allNumbers = TambolaTicketHelper.getAllNumbers(ticket);
        expect(allNumbers.length, 15);

        // Check each row has exactly 5 numbers
        for (int r = 0; r < 3; r++) {
          final rowNums = ticket[r].where((n) => n > 0).length;
          expect(rowNums, 5, reason: 'Row $r does not have 5 numbers in iteration $i');
        }

        // Check column bounds and vertical sorting
        for (int col = 0; col < 9; col++) {
          final minVal = col == 0 ? 1 : col * 10;
          final maxVal = col == 8 ? 90 : (col * 10 + 9);

          final colNums = <int>[];
          for (int row = 0; row < 3; row++) {
            final val = ticket[row][col];
            if (val > 0) {
              expect(val >= minVal && val <= maxVal, isTrue,
                  reason: 'Number $val in col $col is out of range [$minVal, $maxVal]');
              colNums.add(val);
            }
          }

          expect(colNums.isNotEmpty && colNums.length <= 3, isTrue,
              reason: 'Column $col has ${colNums.length} numbers, expected 1-3');

          // Vertically sorted
          for (int k = 0; k < colNums.length - 1; k++) {
            expect(colNums[k] < colNums[k + 1], isTrue,
                reason: 'Col $col not vertically sorted: $colNums');
          }
        }

        final signature = ticket.map((row) => row.join(',')).join(';');
        generatedTickets.add(signature);
      }

      // Out of 250 random tickets, there should be high diversity (>240 unique)
      expect(generatedTickets.length >= 245, isTrue,
          reason: 'Expected unique random tickets, got ${generatedTickets.length} unique out of 250');
    });

    test('generateSqlEquivalentTicket produces valid 3x9 grid matching PostgreSQL MPT_generate_ticket_matrix across 250 generations', () {
      final generatedTickets = <String>{};
      final List<Map<String, dynamic>> ticketsList = [];

      for (int i = 0; i < 250; i++) {
        final ticket = TambolaTicketHelper.generateSqlEquivalentTicket();

        expect(ticket.length, 3);
        for (final row in ticket) {
          expect(row.length, 9);
        }

        final allNumbers = TambolaTicketHelper.getAllNumbers(ticket);
        expect(allNumbers.length, 15);
        expect(allNumbers.toSet().length, 15);

        // Check each row has exactly 5 numbers
        for (int r = 0; r < 3; r++) {
          final rowNums = ticket[r].where((n) => n > 0).length;
          expect(rowNums, 5, reason: 'Row $r does not have 5 numbers in SQL generation iteration $i');
        }

        // Check column bounds and vertical sorting
        for (int col = 0; col < 9; col++) {
          final minVal = col == 0 ? 1 : col * 10;
          final maxVal = col == 8 ? 90 : (col * 10 + 9);

          final colNums = <int>[];
          for (int row = 0; row < 3; row++) {
            final val = ticket[row][col];
            if (val > 0) {
              expect(val >= minVal && val <= maxVal, isTrue,
                  reason: 'Number $val in col $col is out of range [$minVal, $maxVal]');
              colNums.add(val);
            }
          }

          expect(colNums.isNotEmpty && colNums.length <= 2, isTrue,
              reason: 'Column $col has ${colNums.length} numbers, expected 1-2 in SQL pattern');

          // Vertically sorted
          for (int k = 0; k < colNums.length - 1; k++) {
            expect(colNums[k] < colNums[k + 1], isTrue,
                reason: 'Col $col not vertically sorted: $colNums');
          }
        }

        final signature = ticket.map((row) => row.join(',')).join(';');
        generatedTickets.add(signature);

        ticketsList.add({
          'ticketNumber': i + 1,
          'ticketId': 'SQL_TICKET_${(i + 1).toString().padLeft(3, '0')}',
          'grid_3x9': ticket,
          'numbers_count': allNumbers.length,
          'numbers': allNumbers,
          'row1': ticket[0].where((n) => n > 0).toList(),
          'row2': ticket[1].where((n) => n > 0).toList(),
          'row3': ticket[2].where((n) => n > 0).toList(),
          'columns': List.generate(9, (c) => [ticket[0][c], ticket[1][c], ticket[2][c]].where((n) => n > 0).toList()),
        });
      }

      // Out of 250 SQL tickets generated from 8.12 Trillion combinations, expect 250 unique (0 duplicates)
      expect(generatedTickets.length, 250,
          reason: 'Expected 250 unique SQL tickets, got ${generatedTickets.length}');

      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'totalTickets': ticketsList.length,
        'generatedAt': DateTime.now().toIso8601String(),
        'algorithm': 'PostgreSQL public.MPT_generate_ticket_matrix()',
        'description': '250 unique stress-tested Tambola tickets (Mega Event tier capacity).',
        'tickets': ticketsList,
      });

      File('docs/sql_generated_250_tickets.json').writeAsStringSync(jsonString);
      expect(File('docs/sql_generated_250_tickets.json').existsSync(), isTrue);
    });

    test('exports 250 valid unique tickets to docs/generated_250_tickets.json', () {
      final List<Map<String, dynamic>> ticketsList = [];
      final Set<String> seenSignatures = {};

      int count = 1;
      while (ticketsList.length < 250) {
        final ticket = TambolaTicketHelper.generateTicket();
        final signature = ticket.map((row) => row.join(',')).join(';');
        if (seenSignatures.contains(signature)) continue;
        seenSignatures.add(signature);

        final numbers = TambolaTicketHelper.getAllNumbers(ticket);
        ticketsList.add({
          'ticketNumber': count,
          'ticketId': 'TICKET_${count.toString().padLeft(3, '0')}',
          'grid_3x9': ticket,
          'numbers_count': numbers.length,
          'numbers': numbers,
          'row1': ticket[0].where((n) => n > 0).toList(),
          'row2': ticket[1].where((n) => n > 0).toList(),
          'row3': ticket[2].where((n) => n > 0).toList(),
          'columns': List.generate(9, (c) => [ticket[0][c], ticket[1][c], ticket[2][c]].where((n) => n > 0).toList()),
        });
        count++;
      }

      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'totalTickets': ticketsList.length,
        'generatedAt': DateTime.now().toIso8601String(),
        'description': '250 unique Tambola tickets following 3x9 grid, 15 numbers (5 per row, 1-3 per column, vertically sorted).',
        'tickets': ticketsList,
      });

      File('docs/generated_250_tickets.json').writeAsStringSync(jsonString);
      expect(File('docs/generated_250_tickets.json').existsSync(), isTrue);
    });

    test('Winning patterns detection strictly rejects incomplete patterns', () {
      final matrix = [
        [4, 0, 22, 0, 45, 0, 63, 0, 81],
        [0, 15, 0, 34, 0, 56, 0, 77, 85],
        [8, 0, 29, 0, 48, 59, 0, 79, 0],
      ];

      // Early 5
      final early5Set = {4, 22, 45, 15, 34};
      expect(TambolaTicketHelper.checkEarlyFive(matrix, early5Set), isTrue);
      expect(TambolaTicketHelper.checkEarlyFive(matrix, {4, 22, 45}), isFalse);

      // Top Line: 4, 22, 45, 63, 81
      final topLineSet = {4, 22, 45, 63, 81};
      expect(TambolaTicketHelper.checkTopLine(matrix, topLineSet), isTrue);
      expect(TambolaTicketHelper.checkTopLine(matrix, {4, 22, 45, 63}), isFalse);

      // Bottom Line: 8, 29, 48, 59, 79
      final bottomLineSet = {8, 29, 48, 59, 79};
      expect(TambolaTicketHelper.checkBottomLine(matrix, bottomLineSet), isTrue);
      // Bug 15 verification: only 3 out of 5 matched must be FALSE
      expect(TambolaTicketHelper.checkBottomLine(matrix, {8, 29, 48}), isFalse);
      expect(TambolaTicketHelper.validatePrizePattern(matrix, {8, 29, 48}, 'BOTTOM_LINE'), isFalse);

      // Four Corners: 4 (first top), 81 (last top), 8 (first bottom), 79 (last bottom)
      final fourCornersSet = {4, 81, 8, 79};
      expect(TambolaTicketHelper.checkFourCorners(matrix, fourCornersSet), isTrue);
      expect(TambolaTicketHelper.checkFourCorners(matrix, {4, 81, 8}), isFalse);

      // Full House (all 15 numbers)
      final allNumbers = TambolaTicketHelper.getAllNumbers(matrix).toSet();
      expect(TambolaTicketHelper.checkFullHouse(matrix, allNumbers), isTrue);
      allNumbers.remove(4);
      expect(TambolaTicketHelper.checkFullHouse(matrix, allNumbers), isFalse);
    });
  });
}

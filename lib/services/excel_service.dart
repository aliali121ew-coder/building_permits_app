import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/permit_model.dart';
import '../core/utils/date_utils.dart';

class ExcelService {
  ExcelService._();
  static final ExcelService instance = ExcelService._();

  Excel _createWorkbook(List<PermitModel> permits, {String sheetName = 'الإجازات'}) {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    final headers = [
      'رقم الإجازة',
      'السنة',
      'الاسم الثلاثي',
      'رقم القطعة',
      'التاريخ',
      'نوع الإجازة',
      'مساحة العرصة',
      'مساحة البناء',
      'الملاحظات',
      'التغيرات',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final p in permits) {
      sheet.appendRow([
        IntCellValue(p.permitNumber),
        IntCellValue(p.permitYear),
        TextCellValue(p.fullName),
        TextCellValue(p.plotNumber),
        TextCellValue(AppDateUtils.formatDate(p.permitDate)),
        TextCellValue(p.permitType),
        p.plotArea != null ? DoubleCellValue(p.plotArea!) : TextCellValue(''),
        p.buildingArea != null ? DoubleCellValue(p.buildingArea!) : TextCellValue(''),
        TextCellValue(p.notes),
        TextCellValue(p.nameChangeNotes),
      ]);
    }

    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 20);
    }

    return excel;
  }

  Future<File> exportPermits(List<PermitModel> permits, {String sheetName = 'الإجازات'}) async {
    final excel = _createWorkbook(permits, sheetName: sheetName);
    final bytes = excel.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/permits_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes!);
    return file;
  }

  /// تصدير وفتح ملف Excel على الكمبيوتر (الويب/الويندوز) أو الهاتف
  Future<void> exportAndOpenPermits(List<PermitModel> permits, {String sheetName = 'الإجازات'}) async {
    final fileName = permits.length == 1
        ? 'permit_${permits.first.permitYear}_${permits.first.permitNumber}.xlsx'
        : 'permits_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    if (kIsWeb) {
      final excel = _createWorkbook(permits, sheetName: sheetName);
      excel.save(fileName: fileName);
      return;
    }
    final file = await exportPermits(permits, sheetName: sheetName);
    await OpenFilex.open(file.path);
  }
}

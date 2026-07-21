import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../models/permit_model.dart';
import '../core/utils/date_utils.dart';

class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  /// تحميل الخطوط والشعار مرة واحدة لإعادة الاستخدام
  Future<_PdfAssets> _loadAssets() async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/images/logo.jpg');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    return _PdfAssets(arabicFont: arabicFont, arabicBold: arabicBold, logoImage: logoImage);
  }

  /// بناء الهيدر الرسمي الموحد (يُستخدم في جميع التقارير)
  pw.Widget _buildOfficialHeader(_PdfAssets assets, {String? subtitleText}) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // اليمين
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('جمهورية العراق', style: pw.TextStyle(font: assets.arabicBold, fontSize: 10)),
                pw.Text('وزارة الإعمار والإسكان والبلديات', style: pw.TextStyle(font: assets.arabicFont, fontSize: 8)),
                pw.Text('مديرية بلدية الهاشمية', style: pw.TextStyle(font: assets.arabicBold, fontSize: 9)),
                pw.Text('قسم الإجازات والتقارير', style: pw.TextStyle(font: assets.arabicFont, fontSize: 8)),
              ],
            ),
            // الوسط: الشعار الرسمي
            if (assets.logoImage != null)
              pw.Container(
                width: 54,
                height: 54,
                child: pw.Image(assets.logoImage!),
              )
            else
              pw.SizedBox(width: 54, height: 54),
            // اليسار
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('تاريخ الطباعة:', style: pw.TextStyle(font: assets.arabicBold, fontSize: 8)),
                pw.Text(AppDateUtils.formatDate(DateTime.now()), style: pw.TextStyle(font: assets.arabicFont, fontSize: 8)),
                if (subtitleText != null)
                  pw.Text(subtitleText, style: pw.TextStyle(font: assets.arabicFont, fontSize: 8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.5, color: const PdfColor.fromInt(0xFF2A5C8A)),
        pw.SizedBox(height: 10),
      ],
    );
  }

  /// يبني ملف PDF لقائمة إجازات (كشف سنوي) بخط عربي - بدون صور مرفقة
  Future<File> buildPermitsListPdf(List<PermitModel> permits, {String title = 'كشف إجازات البناء'}) async {
    final doc = pw.Document();
    final assets = await _loadAssets();

    const headers = ['ت', 'رقم الإجازة', 'الاسم الثلاثي', 'رقم القطعة', 'التاريخ', 'الملاحظات'];

    // تحديد عرض الأعمدة بنسب ثابتة لمنع تجاوز حدود الصفحة
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(25),     // ت (تسلسل)
      1: const pw.FixedColumnWidth(60),     // رقم الإجازة
      2: const pw.FlexColumnWidth(3),       // الاسم الثلاثي (مرن - الأعرض)
      3: const pw.FixedColumnWidth(55),     // رقم القطعة
      4: const pw.FixedColumnWidth(62),     // التاريخ
      5: const pw.FlexColumnWidth(2),       // الملاحظات (مرن)
    };

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: assets.arabicFont, bold: assets.arabicBold),
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 28,
          marginRight: 28,
          marginTop: 24,
          marginBottom: 24,
        ),
        build: (context) => [
          _buildOfficialHeader(assets, subtitleText: 'تقرير سنوي إلكتروني'),
          pw.Center(
            child: pw.Text(title, style: pw.TextStyle(font: assets.arabicBold, fontSize: 14)),
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'العدد الإجمالي: ${permits.length} إجازة',
              style: pw.TextStyle(font: assets.arabicFont, fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            columnWidths: columnWidths,
            data: permits
                .asMap()
                .entries
                .map((entry) => [
                      '${entry.key + 1}',
                      '${entry.value.permitYear}/${entry.value.permitNumber}',
                      entry.value.fullName,
                      entry.value.plotNumber,
                      AppDateUtils.formatDate(entry.value.permitDate),
                      entry.value.notes,
                    ])
                .toList(),
            headerStyle: pw.TextStyle(font: assets.arabicBold, fontSize: 7, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF2A5C8A)),
            headerAlignment: pw.Alignment.center,
            cellStyle: pw.TextStyle(font: assets.arabicFont, fontSize: 7),
            cellAlignment: pw.Alignment.centerRight,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ],
      ),
    );

    // لا تُطبع الصور المرفقة في التقرير السنوي - حصرياً في الطباعة الفردية فقط

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/permits_export_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// بطاقة إجازة فردية بصيغة رسمية للطباعة - بجدول رسمي وهيدر حكومي
  Future<File> buildSinglePermitPdf(PermitModel permit) async {
    final doc = pw.Document();
    final assets = await _loadAssets();

    // بناء صفوف الجدول الفردي
    final tableData = <List<String>>[
      ['رقم الإجازة', '${permit.permitYear}/${permit.permitNumber}'],
      ['الاسم الثلاثي', permit.fullName],
      ['رقم القطعة', permit.plotNumber],
      ['تاريخ الإجازة', AppDateUtils.formatDate(permit.permitDate)],
      ['نوع الإجازة', permit.permitType.isNotEmpty ? permit.permitType : '-'],
      ['مساحة العرصة', permit.plotArea != null ? '${permit.plotArea} م²' : '-'],
      ['مساحة البناء', permit.buildingArea != null ? '${permit.buildingArea} م²' : '-'],
      ['الملاحظات', permit.notes.isNotEmpty ? permit.notes : '-'],
    ];

    // إضافة حقول اختيارية
    if (permit.nameChangeNotes.isNotEmpty) {
      tableData.add(['ملاحظات تغيير الاسم', permit.nameChangeNotes]);
    }
    if (permit.namePerNewRegistry.isNotEmpty) {
      tableData.add(['الاسم حسب السجل الجديد', permit.namePerNewRegistry]);
    }

    // الجدول الفردي الرسمي
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2), // البيان
      1: const pw.FlexColumnWidth(3), // القيمة
    };

    // تجميع الصور المرفقة
    final localImages = <_AttachedImage>[];
    for (final path in permit.attachmentUrls) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
        final file = File(path);
        if (file.existsSync()) {
          try {
            final imgBytes = file.readAsBytesSync();
            localImages.add(_AttachedImage(
              image: pw.MemoryImage(imgBytes),
              fileName: path.split('/').last.split('\\').last,
            ));
          } catch (_) {}
        }
      }
    }

    // صفحة الجدول الرسمي
    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: assets.arabicFont, bold: assets.arabicBold),
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 32,
          marginRight: 32,
          marginTop: 28,
          marginBottom: 28,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildOfficialHeader(assets, subtitleText: 'إجازة بناء فردية'),
            pw.Center(
              child: pw.Text(
                'إجازة بناء - رقم ${permit.permitYear}/${permit.permitNumber}',
                style: pw.TextStyle(font: assets.arabicBold, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: ['البيان', 'التفاصيل'],
              columnWidths: columnWidths,
              data: tableData,
              headerStyle: pw.TextStyle(font: assets.arabicBold, fontSize: 10, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF2A5C8A)),
              headerAlignment: pw.Alignment.center,
              cellStyle: pw.TextStyle(font: assets.arabicFont, fontSize: 9),
              cellAlignment: pw.Alignment.centerRight,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              oddCellStyle: pw.TextStyle(font: assets.arabicFont, fontSize: 9),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F4F8)),
            ),
            pw.SizedBox(height: 20),
            // توقيعات رسمية
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text('توقيع المهندس المسؤول', style: pw.TextStyle(font: assets.arabicBold, fontSize: 9)),
                    pw.SizedBox(height: 30),
                    pw.Container(width: 120, child: pw.Divider(thickness: 0.8)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('توقيع مدير البلدية', style: pw.TextStyle(font: assets.arabicBold, fontSize: 9)),
                    pw.SizedBox(height: 30),
                    pw.Container(width: 120, child: pw.Divider(thickness: 0.8)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // إلحاق الصور المرفقة (فقط في الطباعة الفردية)
    for (final attached in localImages) {
      doc.addPage(
        pw.Page(
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: assets.arabicFont, bold: assets.arabicBold),
          pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: 32,
            marginRight: 32,
            marginTop: 28,
            marginBottom: 28,
          ),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildOfficialHeader(assets, subtitleText: 'وثيقة مرفقة'),
              pw.Center(
                child: pw.Text(
                  'وثيقة مرفقة للإجازة رقم ${permit.permitYear}/${permit.permitNumber} - ${permit.fullName}',
                  style: pw.TextStyle(font: assets.arabicBold, fontSize: 11),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'اسم الملف: ${attached.fileName}',
                  style: pw.TextStyle(font: assets.arabicFont, fontSize: 8, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(attached.image),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/permit_${permit.permitYear}_${permit.permitNumber}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> printFile(File file) async {
    await Printing.layoutPdf(onLayout: (format) async => file.readAsBytesSync());
  }
}

/// أصول PDF المشتركة (خطوط وشعار)
class _PdfAssets {
  final pw.Font arabicFont;
  final pw.Font arabicBold;
  final pw.MemoryImage? logoImage;

  const _PdfAssets({required this.arabicFont, required this.arabicBold, this.logoImage});
}

/// صورة مرفقة مع اسم الملف
class _AttachedImage {
  final pw.MemoryImage image;
  final String fileName;

  const _AttachedImage({required this.image, required this.fileName});
}

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
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
    pw.Font arabicFont;
    pw.Font arabicBold;
    try {
      // خطوط Cairo المضمّنة في التطبيق أولاً (تعمل بدون إنترنت).
      // ملاحظة: PdfGoogleFonts لا يرمي خطأً عند فشل التنزيل بل يرجع Helvetica
      // التي لا تدعم العربية، لذا لا نعتمد عليه إلا كاحتياط.
      arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
      arabicBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
    } catch (_) {
      arabicFont = await PdfGoogleFonts.cairoRegular();
      arabicBold = await PdfGoogleFonts.cairoBold();
    }

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

    // حزمة pdf ترسم أعمدة الجدول يسار←يمين ولا تعكسها تلقائياً، لذا نرتّب
    // الأعمدة عكسياً في المصفوفة كي تُقرأ على الصفحة من اليمين إلى اليسار:
    // ت | رقم الإجازة | الاسم الثلاثي | رقم القطعة | التاريخ | الملاحظات
    const headers = ['الملاحظات', 'التاريخ', 'رقم القطعة', 'الاسم الثلاثي', 'رقم الإجازة', 'ت'];

    // عرض الأعمدة (مطابق للترتيب المعكوس أعلاه)
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2),       // الملاحظات (مرن)
      1: const pw.FixedColumnWidth(62),     // التاريخ
      2: const pw.FixedColumnWidth(55),     // رقم القطعة
      3: const pw.FlexColumnWidth(3),       // الاسم الثلاثي (مرن - الأعرض)
      4: const pw.FixedColumnWidth(60),     // رقم الإجازة
      5: const pw.FixedColumnWidth(25),     // ت (تسلسل)
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
                      entry.value.notes,
                      AppDateUtils.formatDate(entry.value.permitDate),
                      entry.value.plotNumber,
                      entry.value.fullName,
                      '${entry.value.permitYear}/${entry.value.permitNumber}',
                      '${entry.key + 1}',
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

  // ═══════════════════════════════════════════════════════════════════
  // تصميم وثيقة الإجازة الفردية (إطار أزرق رسمي + شعار + باركود + توقيعات)
  // ═══════════════════════════════════════════════════════════════════

  static const _navy = PdfColor.fromInt(0xFF0B2545);
  static const _blue = PdfColor.fromInt(0xFF13578A);
  static const _teal = PdfColor.fromInt(0xFF1FA2C4);
  static const _soft = PdfColor.fromInt(0xFFF3F7FB);
  static const _line = PdfColor.fromInt(0xFFD5DEE8);

  /// نص رمز QR — يقرؤه ماسح التطبيق ويفتح بطاقة الإجازة مباشرة
  String _qrData(PermitModel p) => 'PERMIT:${p.permitYear}/${p.permitNumber}';

  String _fmtArea(double? v) {
    if (v == null) return '-';
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return '$s متر مربع';
  }

  /// إطار الصفحة (أشرطة زرقاء متدرجة أعلى اليمين وأسفل اليسار) مرسوم كـ SVG
  /// متجهي ليبقى حاداً عند الطباعة بأي حجم. التصميم مبني على عرض 595 نقطة
  /// ويُحجَّم تلقائياً لأي مقاس صفحة.
  String _frameSvg(double w, double h) {
    final s = w / 595.0;
    final hh = h / s; // ارتفاع الصفحة بوحدات التصميم
    String n(double v) => (v * s).toStringAsFixed(2);
    String pts(List<double> p) {
      final b = StringBuffer();
      for (var i = 0; i < p.length; i += 2) {
        if (i > 0) b.write(' ');
        b.write('${n(p[i])},${n(p[i + 1])}');
      }
      return b.toString();
    }

    final corner = StringBuffer();
    // مثلثات زخرفية رمادية فاتحة في الزاوية
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4 - r; c++) {
        final x = 12 + c * 15.0, y = 20 + r * 15.0;
        corner.write('<polygon points="${pts([x, y, x + 11, y, x, y + 11])}" fill="#E2E8EF"/>');
      }
    }
    // معيّنات خفيفة على الحافة الجانبية
    for (final f in [0.30, 0.62]) {
      final y = hh * f;
      corner.write('<polygon points="${pts([0, y - 70, 34, y, 0, y + 70])}" fill="#F0F3F7"/>');
      corner.write('<polygon points="${pts([0, y - 40, 18, y, 0, y + 40])}" fill="#E7ECF2"/>');
    }

    final band = '''
<rect x="0" y="0" width="${n(595)}" height="${n(11)}" fill="#0B2545"/>
<polygon points="${pts([330, 0, 595, 0, 595, 62, 390, 62])}" fill="url(#gA)"/>
<polyline points="${pts([350, 0, 400, 50, 595, 50])}" fill="none" stroke="#FFFFFF" stroke-width="${n(1.3)}"/>
<polygon points="${pts([256, 18, 284, 18, 308, 44, 280, 44])}" fill="url(#gB)"/>
<polygon points="${pts([290, 18, 322, 18, 346, 44, 314, 44])}" fill="url(#gB)"/>
$corner''';

    return '''
<svg xmlns="http://www.w3.org/2000/svg" width="${w.toStringAsFixed(2)}" height="${h.toStringAsFixed(2)}" viewBox="0 0 ${w.toStringAsFixed(2)} ${h.toStringAsFixed(2)}">
<defs>
<linearGradient id="gA" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#13578A"/><stop offset="1" stop-color="#24B3D3"/></linearGradient>
<linearGradient id="gB" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#0E4C7A"/><stop offset="1" stop-color="#2AA6CF"/></linearGradient>
</defs>
$band
<g transform="matrix(-1 0 0 -1 ${w.toStringAsFixed(2)} ${h.toStringAsFixed(2)})">
$band
</g>
</svg>''';
  }

  /// قالب الصفحة الموحد: الإطار + علامة مائية للشعار
  pw.PageTheme _framedTheme(_PdfAssets assets, PdfPageFormat format, {double watermark = 0.05}) {
    final baseTheme = pw.ThemeData.withFont(base: assets.arabicFont, bold: assets.arabicBold);
    return pw.PageTheme(
      pageFormat: format,
      textDirection: pw.TextDirection.rtl,
      theme: baseTheme.copyWith(
        // توسيع مسافة الكلمات قليلاً كي لا تلتصق الأسماء (ثامر وعامر)
        defaultTextStyle: baseTheme.defaultTextStyle.copyWith(wordSpacing: 1.8),
      ),
      buildBackground: (ctx) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.SvgImage(svg: _frameSvg(format.width, format.height), fit: pw.BoxFit.fill),
            ),
            if (assets.logoImage != null && watermark > 0)
              pw.Center(
                child: pw.Opacity(
                  opacity: watermark,
                  child: pw.Image(assets.logoImage!, width: format.width * 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  pw.Widget _gradientRule({double height = 2.5}) => pw.Container(
        height: height,
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [_navy, _blue, _teal]),
        ),
      );

  /// رأس الوثيقة: الجهة الرسمية يميناً، الشعار وسطاً، بيانات الوثيقة يساراً
  pw.Widget _framedHeader(_PdfAssets assets, PermitModel permit) {
    pw.TextStyle st(double size, {bool bold = false, PdfColor? color}) => pw.TextStyle(
          font: bold ? assets.arabicBold : assets.arabicFont,
          fontSize: size,
          color: color ?? _navy,
        );
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('جمهورية العراق', style: st(11, bold: true)),
                  pw.Text('وزارة الإعمار والإسكان والبلديات', style: st(8.5, color: PdfColors.grey800)),
                  pw.Text('مديرية بلدية الهاشمية', style: st(10.5, bold: true, color: _blue)),
                  pw.Text('قسم الإجازات', style: st(8.5, color: PdfColors.grey800)),
                ],
              ),
            ),
            pw.Container(
              width: 70,
              height: 70,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColors.white,
                border: pw.Border.all(color: _teal, width: 1.5),
              ),
              child: assets.logoImage != null
                  ? pw.ClipOval(child: pw.Image(assets.logoImage!, fit: pw.BoxFit.cover))
                  : pw.SizedBox(),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('رقم الوثيقة', style: st(8, color: PdfColors.grey700)),
                  pw.Text('BP-${permit.permitYear}-${permit.permitNumber}', style: st(10, bold: true)),
                  pw.SizedBox(height: 3),
                  pw.Text('تاريخ الإصدار', style: st(8, color: PdfColors.grey700)),
                  pw.Text(AppDateUtils.formatDate(DateTime.now()), style: st(10, bold: true)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        _gradientRule(),
      ],
    );
  }

  pw.Widget _infoCell(_PdfAssets assets, String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _line, width: 0.8),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 3,
            height: 26,
            decoration: pw.BoxDecoration(color: _teal, borderRadius: pw.BorderRadius.circular(2)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: pw.TextStyle(font: assets.arabicFont, fontSize: 8, color: PdfColors.grey700)),
                pw.Text(value, style: pw.TextStyle(font: assets.arabicBold, fontSize: 11, color: _navy), maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _signatureBlock(_PdfAssets assets, String title) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(font: assets.arabicBold, fontSize: 11, color: _navy)),
        pw.SizedBox(height: 34),
        pw.Container(width: 140, height: 0.9, color: PdfColors.grey600),
        pw.SizedBox(height: 3),
        pw.Text('الاسم والتوقيع', style: pw.TextStyle(font: assets.arabicFont, fontSize: 7.5, color: PdfColors.grey600)),
      ],
    );
  }

  /// صفحة تفاصيل الإجازة بالتصميم الرسمي
  pw.Page _buildPermitDetailsPage(_PdfAssets assets, PermitModel permit) {
    final format = PdfPageFormat.a4.copyWith(marginLeft: 46, marginRight: 46, marginTop: 76, marginBottom: 74);
    final code = '${permit.permitYear} / ${permit.permitNumber}';

    final fields = <List<String>>[
      ['رقم الإجازة', code],
      ['تاريخ الإجازة', AppDateUtils.formatDate(permit.permitDate)],
      ['رقم القطعة / العقار', permit.plotNumber.isNotEmpty ? permit.plotNumber : '-'],
      ['نوع الإجازة', permit.permitType.isNotEmpty ? permit.permitType : '-'],
      ['مساحة العرصة', _fmtArea(permit.plotArea)],
      ['مساحة البناء', _fmtArea(permit.buildingArea)],
      if (permit.namePerNewRegistry.isNotEmpty) ['الاسم حسب السجل الجديد', permit.namePerNewRegistry],
      if (permit.nameChangeNotes.isNotEmpty) ['ملاحظات تغيير الاسم', permit.nameChangeNotes],
    ];

    final gridRows = <pw.Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final hasSecond = i + 1 < fields.length;
      gridRows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          children: [
            pw.Expanded(child: _infoCell(assets, fields[i][0], fields[i][1])),
            pw.SizedBox(width: 8),
            pw.Expanded(child: hasSecond ? _infoCell(assets, fields[i + 1][0], fields[i + 1][1]) : pw.SizedBox()),
          ],
        ),
      ));
    }

    return pw.Page(
      pageTheme: _framedTheme(assets, format),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _framedHeader(assets, permit),
          pw.SizedBox(height: 14),

          // شريط العنوان
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(10),
              gradient: const pw.LinearGradient(colors: [_navy, _blue]),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('إجازة بناء', style: pw.TextStyle(font: assets.arabicBold, fontSize: 20, color: PdfColors.white)),
                    pw.Text('وثيقة رسمية صادرة عن مديرية بلدية الهاشمية',
                        style: pw.TextStyle(font: assets.arabicFont, fontSize: 8.5, color: const PdfColor.fromInt(0xFFCFE6F2))),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(20),
                  ),
                  child: pw.Text('رقم $code', style: pw.TextStyle(font: assets.arabicBold, fontSize: 13, color: _navy)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // بطاقة صاحب الإجازة + الباركود
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Container(
                  height: 128,
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    color: _soft,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: _line),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('اسم صاحب الإجازة', style: pw.TextStyle(font: assets.arabicFont, fontSize: 8.5, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(permit.fullName, style: pw.TextStyle(font: assets.arabicBold, fontSize: 16, color: _navy), maxLines: 2),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          _chip(assets, 'القطعة: ${permit.plotNumber.isNotEmpty ? permit.plotNumber : '-'}'),
                          pw.SizedBox(width: 6),
                          _chip(assets, 'التاريخ: ${AppDateUtils.formatDate(permit.permitDate)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: 122,
                height: 128,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(color: _teal, width: 1.2),
                ),
                child: pw.Column(
                  children: [
                    pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qrData(permit), width: 92, height: 92, color: _navy),
                    pw.SizedBox(height: 4),
                    pw.Text('امسح للتحقق من الإجازة', style: pw.TextStyle(font: assets.arabicBold, fontSize: 7.5, color: _blue)),
                    pw.Text(code, style: pw.TextStyle(font: assets.arabicFont, fontSize: 7.5, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // عنوان قسم التفاصيل
          pw.Row(
            children: [
              pw.Container(width: 4, height: 14, color: _teal),
              pw.SizedBox(width: 6),
              pw.Text('تفاصيل الإجازة', style: pw.TextStyle(font: assets.arabicBold, fontSize: 12, color: _navy)),
            ],
          ),
          pw.SizedBox(height: 8),
          ...gridRows,

          // الملاحظات
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.circular(7),
              border: pw.Border.all(color: _line, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('الملاحظات', style: pw.TextStyle(font: assets.arabicBold, fontSize: 9, color: _blue)),
                pw.SizedBox(height: 2),
                pw.Text(permit.notes.isNotEmpty ? permit.notes : 'لا توجد ملاحظات',
                    style: pw.TextStyle(font: assets.arabicFont, fontSize: 10, color: PdfColors.grey900), maxLines: 5),
              ],
            ),
          ),

          pw.Spacer(),

          // التوقيعات
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _signatureBlock(assets, 'الموظف الإداري'),
              pw.Container(
                width: 74,
                height: 74,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: PdfColors.grey400, width: 1),
                ),
                child: pw.Text('ختم المديرية',
                    style: pw.TextStyle(font: assets.arabicFont, fontSize: 8, color: PdfColors.grey500)),
              ),
              _signatureBlock(assets, 'مسؤول القسم'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'وثيقة صادرة إلكترونياً من نظام إجازات البناء — يمكن التحقق من صحتها بمسح رمز QR',
              style: pw.TextStyle(font: assets.arabicFont, fontSize: 7.5, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _chip(_PdfAssets assets, String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _line, width: 0.8),
        ),
        child: pw.Text(text, style: pw.TextStyle(font: assets.arabicBold, fontSize: 8.5, color: _blue)),
      );

  /// صفحة وثيقة مرفقة بنفس الإطار
  pw.Page _buildAttachmentPage(_PdfAssets assets, PermitModel permit, _AttachedImage attached) {
    final format = PdfPageFormat.a4.copyWith(marginLeft: 46, marginRight: 46, marginTop: 76, marginBottom: 74);
    return pw.Page(
      pageTheme: _framedTheme(assets, format, watermark: 0),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _framedHeader(assets, permit),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'وثيقة مرفقة للإجازة رقم ${permit.permitYear}/${permit.permitNumber} - ${permit.fullName}',
              style: pw.TextStyle(font: assets.arabicBold, fontSize: 11, color: _navy),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Center(
            child: pw.Text('اسم الملف: ${attached.fileName}',
                style: pw.TextStyle(font: assets.arabicFont, fontSize: 8, color: PdfColors.grey600)),
          ),
          pw.SizedBox(height: 8),
          pw.Expanded(child: pw.Center(child: pw.Image(attached.image))),
        ],
      ),
    );
  }

  List<_AttachedImage> _collectLocalImages(PermitModel permit) {
    final localImages = <_AttachedImage>[];
    if (kIsWeb) return localImages;
    for (final path in permit.attachmentUrls) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
        final file = File(path);
        if (file.existsSync()) {
          try {
            localImages.add(_AttachedImage(
              image: pw.MemoryImage(file.readAsBytesSync()),
              fileName: path.split('/').last.split('\\').last,
            ));
          } catch (_) {}
        }
      }
    }
    return localImages;
  }

  /// بطاقة إجازة فردية بالتصميم الرسمي + الصور المرفقة (الأنظمة المحلية)
  Future<File> buildSinglePermitPdf(PermitModel permit) async {
    final assets = await _loadAssets();
    final doc = pw.Document();
    doc.addPage(_buildPermitDetailsPage(assets, permit));
    for (final attached in _collectLocalImages(permit)) {
      doc.addPage(_buildAttachmentPage(assets, permit, attached));
    }
    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/permit_${permit.permitYear}_${permit.permitNumber}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// توليد بايتات PDF لتفاصيل الإجازة (يعمل على الويب والكمبيوتر والهاتف)
  Future<Uint8List> buildSinglePermitPdfBytes(PermitModel permit) async {
    final assets = await _loadAssets();
    final doc = pw.Document();
    doc.addPage(_buildPermitDetailsPage(assets, permit));
    return doc.save();
  }

  /// بطاقة الباركود المنفصلة (مقاس A6) — للطباعة واللصق على ملف الإجازة
  Future<Uint8List> buildPermitBarcodePdfBytes(PermitModel permit) async {
    final assets = await _loadAssets();
    final doc = pw.Document();
    final format = PdfPageFormat.a6.copyWith(marginLeft: 22, marginRight: 22, marginTop: 40, marginBottom: 38);
    final code = '${permit.permitYear} / ${permit.permitNumber}';

    doc.addPage(
      pw.Page(
        pageTheme: _framedTheme(assets, format, watermark: 0),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (assets.logoImage != null)
                  pw.Container(
                    width: 34,
                    height: 34,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _teal, width: 1),
                    ),
                    child: pw.ClipOval(child: pw.Image(assets.logoImage!, fit: pw.BoxFit.cover)),
                  ),
                pw.SizedBox(width: 6),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('مديرية بلدية الهاشمية', style: pw.TextStyle(font: assets.arabicBold, fontSize: 10, color: _navy)),
                    pw.Text('قسم الإجازات', style: pw.TextStyle(font: assets.arabicFont, fontSize: 7.5, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            _gradientRule(height: 1.6),
            pw.SizedBox(height: 8),
            pw.Text('باركود إجازة بناء', style: pw.TextStyle(font: assets.arabicBold, fontSize: 12, color: _blue)),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _teal, width: 1.4),
              ),
              child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qrData(permit), width: 138, height: 138, color: _navy),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(colors: [_navy, _blue]),
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Text('رقم $code', style: pw.TextStyle(font: assets.arabicBold, fontSize: 12, color: PdfColors.white)),
            ),
            pw.SizedBox(height: 5),
            pw.Text(permit.fullName,
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: pw.TextStyle(font: assets.arabicBold, fontSize: 10, color: _navy)),
            pw.Text(
              'القطعة: ${permit.plotNumber.isNotEmpty ? permit.plotNumber : '-'}  •  ${AppDateUtils.formatDate(permit.permitDate)}',
              style: pw.TextStyle(font: assets.arabicFont, fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// طباعة بطاقة الباركود وحدها (يفتح نافذة الطباعة للنظام)
  Future<void> printPermitBarcode(PermitModel permit) async {
    final bytes = await buildPermitBarcodePdfBytes(permit);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'barcode_${permit.permitYear}_${permit.permitNumber}.pdf',
      format: PdfPageFormat.a6,
    );
  }

  /// تصدير أو فتح ملف PDF لتفاصيل الإجازة على الكمبيوتر (الويب/الويندوز) أو الهاتف
  Future<void> exportOrOpenSinglePermitPdf(PermitModel permit) async {
    final fileName = 'permit_${permit.permitYear}_${permit.permitNumber}.pdf';
    if (kIsWeb) {
      final bytes = await buildSinglePermitPdfBytes(permit);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fileName,
      );
      return;
    }
    final file = await buildSinglePermitPdf(permit);
    await OpenFilex.open(file.path);
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

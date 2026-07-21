#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
سكربت ترحيل بيانات إجازات البناء من ملفي الإكسل القديمين
إلى ملف CSV موحّد جاهز للاستيراد المباشر إلى جدول public.permits في Supabase.

الاستخدام:
    python3 migrate_excel_to_supabase.py

المخرجات:
    output/permits_import.csv   -> يُستورد مباشرة عبر Supabase Table Editor > Import data from CSV
    output/migration_report.txt -> تقرير بعدد السجلات، السنوات، وأي صفوف تم تجاهلها مع السبب
"""

import re
import csv
import datetime
from pathlib import Path
import openpyxl

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"
OUTPUT_DIR.mkdir(exist_ok=True)

# ضع مسارات الملفين هنا (أو مرّرهما كوسيطين عند التشغيل)
FILES = [
    BASE_DIR.parent.parent / "الاجازات_القديمه_22.xlsx",
    BASE_DIR.parent.parent / "اجازات_البناء_الاصلية-1.xlsx",
]

# كلمات مفتاحية لمطابقة أسماء الأعمدة المختلفة عبر السنوات (تختلف صياغتها قليلاً كل سنة)
COLUMN_KEYWORDS = {
    "permit_number": ["رقم الاجازة", "رقم الاجازه", "ت"],
    "full_name": ["الاسم الثلاثي", "الأسم الثلاثي"],
    "plot_number": ["رقم القطعة", "رقم القطعه"],
    "permit_date": ["التاريخ", "تاريخها"],
    "notes": ["الملاحظات"],
    "name_change_notes": ["التغيرات", "التغييرات", "التـــغيـــرات", "التــغيـــرات"],
    "plot_area": ["مساحة العرصة", "مساحة العرصه"],
    "building_area": ["مساحة البناء"],
    "name_per_new_registry": ["الاسم الثلاثي حسب صورة القيد", "الاسم حسب صورة القيد"],
    "fine_no_permit": ["الغرامه بدون اجازة", "غرامة بدون أجازة", "غرامة بدون اجازة", "الغرامة بدون اجازة"],
    "fine_plan_change": ["غرامة بتغير المخططات"],
}

YEAR_TITLE_RE = re.compile(r"(19|20)\d{2}")
# عنوان السنة الحقيقي يبدأ دائماً بـ"اجازات البناء لـ..." (مع/بدون همزة) خلافاً لنص داخل خانة ملاحظات عادية
YEAR_TITLE_PREFIX_RE = re.compile(r"^\s*\(?\s*[أا]جازات\s+البناء\s+ل")
HEADER_MARKERS = {"رقم الاجازة", "رقم الاجازه", "ت", "الاسم الثلاثي", "الأسم الثلاثي"}


def normalize(s):
    if s is None:
        return ""
    return str(s).strip()


def match_column(header_cell):
    h = normalize(header_cell)
    for field, keywords in COLUMN_KEYWORDS.items():
        for kw in keywords:
            if kw.strip() == h.strip():
                return field
    return None


def looks_like_header_row(row_values):
    normalized = {normalize(v) for v in row_values if v}
    return len(normalized & HEADER_MARKERS) > 0


def looks_like_year_title(row_values):
    non_empty = [v for v in row_values if v not in (None, "")]
    # صف العنوان الحقيقي دائماً شبه فارغ (خانة واحدة مدموجة تحمل النص، أو خانتين كحد أقصى)
    if len(non_empty) > 2:
        return None
    for v in non_empty:
        if isinstance(v, str) and YEAR_TITLE_PREFIX_RE.search(v):
            m = YEAR_TITLE_RE.search(v)
            if m:
                return int(m.group(0))
    return None


def parse_date(value, fallback_year):
    if isinstance(value, datetime.datetime):
        return value.date()
    if isinstance(value, datetime.date):
        return value
    if isinstance(value, str) and value.strip():
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y"):
            try:
                return datetime.datetime.strptime(value.strip(), fmt).date()
            except ValueError:
                continue
    # لا يوجد تاريخ صالح -> نستخدم أول يوم من السنة المعروفة كحل احتياطي (يُذكر في التقرير)
    if fallback_year:
        return datetime.date(fallback_year, 1, 1)
    return None


def parse_number(value):
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return value
    try:
        return float(str(value).replace(",", "").strip())
    except ValueError:
        return None


def process_workbook(path, records, report_lines, skipped_counter):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        if ws.max_row <= 1:
            continue

        current_year = None
        current_map = None  # dict: field -> column_index
        year_seq = {}  # year -> next fallback permit_number counter (لصفوف بلا رقم)

        for row in ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True):
            if row is None or all(v is None for v in row):
                continue

            year_title = looks_like_year_title(row)
            if year_title:
                current_year = year_title
                current_map = None
                continue

            if looks_like_header_row(row):
                current_map = {}
                for idx, cell in enumerate(row):
                    field = match_column(cell)
                    if field:
                        current_map[field] = idx
                continue

            if current_map is None or "permit_number" not in current_map:
                # صف بيانات بلا رأس أعمدة معروف بعد - تجاهل مع تسجيل
                if row[0] is not None:
                    skipped_counter[0] += 1
                continue

            def get(field):
                idx = current_map.get(field)
                return row[idx] if idx is not None and idx < len(row) else None

            raw_permit_number = get("permit_number")
            full_name = normalize(get("full_name"))
            plot_number = normalize(get("plot_number"))

            if not full_name and not plot_number:
                # صف فارغ فعلياً
                continue

            row_year = current_year
            permit_date = parse_date(get("permit_date"), row_year)
            if permit_date:
                row_year = row_year or permit_date.year

            if not row_year:
                skipped_counter[0] += 1
                report_lines.append(f"  [تخطي] لا يمكن تحديد السنة للصف: {full_name} / {plot_number}")
                continue

            permit_number = parse_number(raw_permit_number)
            if permit_number is None:
                year_seq[row_year] = year_seq.get(row_year, 0) + 1
                permit_number = year_seq[row_year]
                report_lines.append(
                    f"  [تنبيه] رقم إجازة مفقود للسنة {row_year} - تم توليد رقم مؤقت {permit_number} للاسم: {full_name}"
                )
            else:
                permit_number = int(permit_number)
                year_seq[row_year] = max(year_seq.get(row_year, 0), permit_number)

            notes_parts = [normalize(get("notes"))]
            fine1 = normalize(get("fine_no_permit"))
            fine2 = normalize(get("fine_plan_change"))
            if fine1 and fine1 not in ("لايوجد", "لا يوجد", "-"):
                notes_parts.append(f"غرامة بدون إجازة: {fine1}")
            if fine2 and fine2 not in ("لايوجد", "لا يوجد", "-"):
                notes_parts.append(f"غرامة تغيير مخططات: {fine2}")
            notes = " | ".join(p for p in notes_parts if p)

            records.append({
                "permit_year": row_year,
                "permit_number": permit_number,
                "full_name": full_name,
                "plot_number": plot_number,
                "permit_date": permit_date.isoformat() if permit_date else "",
                "notes": notes,
                "permit_type": "",  # لا يوجد عمود صريح "نوع" بالبيانات القديمة؛ يُستنتج غالباً من الملاحظات
                "name_change_notes": normalize(get("name_change_notes")),
                "plot_area": parse_number(get("plot_area")) or "",
                "building_area": parse_number(get("building_area")) or "",
                "name_per_new_registry": normalize(get("name_per_new_registry")),
                "source_file": path.name,
                "source_sheet": sheet_name,
            })


def flag_duplicate_permit_numbers(records, report_lines):
    """
    لا نُعيد ترقيم الإجازات أبداً (رقم الإجازة قيمة رسمية تاريخية لا يجوز تغييرها تلقائياً).
    فقط نضع علامة duplicate_flag=1 على كل سجل يشارك (السنة+الرقم) مع سجل آخر،
    ليراجعها الأدمن يدوياً من داخل التطبيق (غالباً بسبب تداخل تغطية الملفين لنفس السنوات).
    """
    from collections import defaultdict
    groups = defaultdict(list)
    for rec in records:
        groups[(rec["permit_year"], rec["permit_number"])].append(rec)

    dup_count = 0
    for key, group in groups.items():
        if len(group) > 1:
            dup_count += len(group)
            for rec in group:
                rec["duplicate_flag"] = 1
            report_lines.append(
                f"  [تكرار يحتاج مراجعة] السنة {key[0]} - رقم الإجازة {key[1]}: "
                f"{len(group)} سجلات بنفس الرقم ({', '.join(r['full_name'] for r in group)})"
            )
        else:
            group[0]["duplicate_flag"] = 0
    report_lines.append(f"\nإجمالي السجلات التي تحمل رقم إجازة مكرر ضمن نفس السنة: {dup_count}")


def main():
    records = []
    report_lines = []
    skipped_counter = [0]

    for f in FILES:
        if not f.exists():
            report_lines.append(f"[تحذير] الملف غير موجود: {f}")
            continue
        report_lines.append(f"معالجة الملف: {f.name}")
        process_workbook(f, records, report_lines, skipped_counter)

    flag_duplicate_permit_numbers(records, report_lines)

    records.sort(key=lambda r: (r["permit_year"], r["permit_number"]))

    csv_path = OUTPUT_DIR / "permits_import.csv"
    fieldnames = [
        "permit_year", "permit_number", "full_name", "plot_number", "permit_date",
        "notes", "permit_type", "name_change_notes", "plot_area", "building_area",
        "name_per_new_registry", "duplicate_flag", "source_file", "source_sheet",
    ]
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

    years = sorted({r["permit_year"] for r in records})
    report_path = OUTPUT_DIR / "migration_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("تقرير ترحيل بيانات إجازات البناء\n")
        f.write("=" * 50 + "\n")
        f.write(f"إجمالي السجلات المُرحّلة: {len(records)}\n")
        f.write(f"عدد الصفوف المتجاهلة (بلا اسم أو رقم قطعة): {skipped_counter[0]}\n")
        f.write(f"نطاق السنوات: {years[0]} - {years[-1]} ({len(years)} سنة)\n\n")
        f.write("تفاصيل:\n")
        f.write("\n".join(report_lines))

    print(f"تم إنشاء: {csv_path}")
    print(f"تم إنشاء: {report_path}")
    print(f"إجمالي السجلات: {len(records)} | السنوات: {years[0]}-{years[-1]}")


if __name__ == "__main__":
    main()

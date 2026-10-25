insert into categories (slug, name_ar, sort_order) values
  ('dresses', 'فساتين', 1),
  ('suits', 'بدلات', 2),
  ('tops', 'تيشرتات', 3)
on conflict (slug) do nothing;

insert into delivery_zones (name_ar, city_slug, fee_lyd) values
  ('سرت — استلام من المحل', 'sirt-pickup', 0),
  ('طرابلس', 'tripoli', 25),
  ('بنغازي', 'benghazi', 30),
  ('مدينة أخرى — تأكيد الرسوم', 'other', 0)
on conflict do nothing;

insert into cms_pages (slug, title_ar, body_html) values
  ('sizes', 'جدول المقاسات', '<p>المقاس M: محيط صدر 90–94 سم. L: 95–100. XL: 101–106. للاستفسار تواصلي معنا على واتساب.</p>'),
  ('about', 'من نحن', '<p><strong>AZIZA Boutique</strong> في سرت — أحدث صيحات الموضة النسائية بجودة عالية.</p>'),
  ('returns', 'الاستبدال والإرجاع', '<p>يمكن الاستبدال خلال 3 أيام للقطع غير المستخدمة مع الفاتورة. التواصل عبر واتساب.</p>'),
  ('terms', 'الشروط والخصوصية', '<p>نحفظ بيانات الطلب (الاسم، الهاتف، العنوان) لإتمام التوصيل فقط ولا نشاركها مع أطراف ثالثة.</p>')
on conflict (slug) do update set body_html = excluded.body_html;

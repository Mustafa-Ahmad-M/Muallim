-- مُعلّمي — تجهيز السحابة بشكل آمن (جدول مقفول + دالتان)
-- شغّله مرة واحدة: supabase.com ← مشروعك ← SQL Editor ← الصق ← Run
--
-- لماذا تغيّر؟ التصميم القديم كان يستخدم صفًا واحدًا مشتركًا id='main'
-- وسياسة using(true) with check(true)، أي أن أي مستخدم كان يستطيع قراءة
-- وكتابة بيانات كل المستخدمين (أسماء وصور الأطفال!). هذا الإصلاح يقفل الجدول
-- تمامًا، ولا يمرّ الوصول إلا عبر دالتين تتطلّبان «رمز المزامنة» السرّي.

create table if not exists app_backups (
  id text primary key,           -- رمز المزامنة السرّي لكل مستخدم (وليس 'main')
  data jsonb,
  updated_at timestamptz default now()
);

alter table app_backups enable row level security;

-- لا سياسات مباشرة: لا يستطيع anon قراءة/كتابة الجدول مباشرةً نهائيًا
revoke all on table app_backups from anon, authenticated;

-- قراءة نسخة المستخدم عبر رمزه السرّي فقط
create or replace function get_backup(p_code text)
returns table(data jsonb, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select data, updated_at from app_backups where id = p_code;
$$;

-- حفظ/تحديث نسخة المستخدم عبر رمزه السرّي فقط
create or replace function put_backup(p_code text, p_data jsonb, p_iso timestamptz default now())
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into app_backups (id, data, updated_at)
  values (p_code, p_data, p_iso)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
end;
$$;

-- السماح باستدعاء الدالتين فقط (لا وصول مباشر للجدول)
grant execute on function get_backup(text) to anon, authenticated;
grant execute on function put_backup(text, jsonb, timestamptz) to anon, authenticated;

-- ملاحظة أمنية: «رمز المزامنة» يعمل كمفتاح سرّي حامل (bearer). من يملكه يصل لبياناته
-- ويزامنها بين الأجهزة. لا تشاركه. هذا أبسط بكثير من تسجيل دخول كامل، ويمنع
-- تصادم المستخدمين وتسريب بياناتهم تمامًا. لعزل أقوى مبني على هوية مسجّلة،
-- استخدم Supabase Auth واربط الصف بـ auth.uid() بدل الرمز.

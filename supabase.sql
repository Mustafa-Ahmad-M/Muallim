-- مُعلّمي — قاعدة البيانات السحابية (مرجع توثيقي فقط)
-- =====================================================================
-- ⚠️ هذا الكود مُطبَّق بالفعل على قاعدة بيانات التطبيق المدمجة، ولا تحتاج
--    لتشغيله. التطبيق متصل تلقائيًا بالمشروع، والمستخدم لا يضيف أي رابط أو مفتاح.
--    نتركه هنا للتوثيق وللنقل إلى مشروع آخر عند الحاجة فقط.
--
-- التصميم: جدول مقفول بالكامل عبر RLS، لا يُقرأ ولا يُكتب إلا عبر دالتين
-- آمنتين (security definer) تتطلّبان «مفتاح الحساب» السرّي (p_code).
-- مفتاح الحساب يُشتقّ داخل التطبيق من: اسم المعلّم + كلمة المرور (تجزئة ثابتة)،
-- فيُسترجع المعلّم بياناته على أي جهاز بنفس الاسم وكلمة المرور، ولا تختلط
-- بيانات المعلّمين ببعضها أبدًا، ولا يصل أحد لبيانات غيره.

create table if not exists app_backups (
  id text primary key,           -- مفتاح الحساب السرّي (مشتقّ من الاسم + كلمة المرور)
  data jsonb,                    -- كامل حالة التطبيق للمستخدم (مواد، دروس، أطفال، تقييمات…)
  updated_at timestamptz default now()
);

alter table app_backups enable row level security;

-- لا سياسات مباشرة: anon/authenticated لا يقرؤون ولا يكتبون الجدول مباشرةً
revoke all on table app_backups from anon, authenticated;

-- قراءة نسخة المستخدم عبر مفتاح حسابه فقط
create or replace function get_backup(p_code text)
returns table(data jsonb, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select data, updated_at from app_backups where id = p_code;
$$;

-- حفظ/تحديث نسخة المستخدم عبر مفتاح حسابه فقط (رفع مباشر لأي مدخل بلا أخطاء)
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

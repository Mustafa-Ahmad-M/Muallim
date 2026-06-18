-- مُعلّمي — قاعدة البيانات السحابية (مُطبّقة بالفعل على مشروع التطبيق "maullim")
-- هذا الملف للتوثيق وإعادة الإنشاء عند الحاجة فقط. شغّله مرة واحدة على مشروع جديد:
-- supabase.com ← مشروعك ← SQL Editor ← الصق الكل ← Run
-- =====================================================================
-- النموذج الآمن: لكل معلّم حساب مُتحقَّق منه (البريد = هوية ثابتة + كلمة مرور مُجزّأة bcrypt).
-- البريد نفسه دائمًا يصل لنفس الصف، وكلمة المرور الخاطئة تُرفَض ولا تُنشئ حسابًا فارغًا.
-- هذا يمنع نهائيًا «تفرّع الحسابات» واختفاء البيانات الذي كان يحدث في النظام القديم.

create extension if not exists pgcrypto with schema extensions;

-- ===== جدول الحسابات المُتحقَّق منها (النظام الحالي) =====
create table if not exists accounts (
  email text primary key,
  pass_hash text not null,
  data jsonb,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);
alter table accounts enable row level security;
revoke all on table accounts from anon, authenticated;

-- دالة واحدة للقراءة/الكتابة مع تحقّق كلمة المرور على السيرفر.
-- p_write=false: دخول/قراءة | p_write=true: حفظ
-- ترجع status: 'ok' | 'new' (لا حساب) | 'denied' (كلمة مرور خاطئة/مدخلات ناقصة)
create or replace function account_sync(p_email text, p_pass text, p_data jsonb default null, p_write boolean default false)
returns table(status text, data jsonb, updated_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
declare r accounts; e text;
begin
  e := lower(trim(coalesce(p_email,'')));
  if length(e) < 3 or coalesce(p_pass,'') = '' then
    return query select 'denied'::text, null::jsonb, null::timestamptz; return;
  end if;
  select * into r from accounts a where a.email = e;
  if not found then
    if p_write then
      insert into accounts(email, pass_hash, data)
      values (e, crypt(p_pass, gen_salt('bf')), coalesce(p_data, '{}'::jsonb))
      returning * into r;
      return query select 'ok'::text, r.data, r.updated_at; return;
    else
      return query select 'new'::text, null::jsonb, null::timestamptz; return;
    end if;
  end if;
  if r.pass_hash <> crypt(p_pass, r.pass_hash) then
    return query select 'denied'::text, null::jsonb, null::timestamptz; return;
  end if;
  if p_write then
    update accounts a set data = coalesce(p_data, a.data), updated_at = now()
    where a.email = e returning * into r;
  end if;
  return query select 'ok'::text, r.data, r.updated_at;
end;
$$;
revoke all on function account_sync(text,text,jsonb,boolean) from public;
grant execute on function account_sync(text,text,jsonb,boolean) to anon, authenticated;

-- ===== جدول النُّسخ القديم (يُبقى فقط لاسترجاع البيانات القديمة عبر زر «نسخة قديمة») =====
create table if not exists app_backups (
  id text primary key,
  data jsonb,
  updated_at timestamptz default now()
);
alter table app_backups enable row level security;
revoke all on table app_backups from anon, authenticated;

create or replace function get_backup(p_code text)
returns table(data jsonb, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select data, updated_at from app_backups where id = p_code;
$$;
grant execute on function get_backup(text) to anon, authenticated;
